#!/usr/bin/env python3
"""Runs the addon against a pretend game client.

    pip install lupa
    python3 tests/run_tests.py [--only lists|sealed] [--stop-early] [words to filter scenario names by]

The addon is plain Lua 5.1, the same dialect the game embeds, so it is loaded
unchanged into a Lua 5.1 runtime where tests/wow_mock.lua stands in for the game.

Every scenario is played twice, because there are two ways a client may report
that a unit's effects changed while their details are hidden, and the addon
judges casts differently under each (see PAYLOADS below). A scenario that is
about one of them chooses it for itself, with the auraPayload option, and so
plays the same both times. --only plays one of the two. --stop-early leaves
the second out when the first has failures.
"""

import re
import sys
from pathlib import Path

from lupa import lua51

ROOT = Path(__file__).resolve().parent.parent
ADDON = ROOT / "StatusEfficiency"

# Game functions that only Compat.lua is allowed to call, because their answers
# can be secret values that must not be compared or tested.
GUARDED = re.compile(
    r"(?<![\w.:])(Unit[A-Z]\w*|C_[A-Z]\w*|GetActionInfo|GetMacroSpell|InCombatLockdown|issecretvalue|GetTime)\s*[\(\.]"
)


def static_checks():
    problems = []
    toc = (ADDON / "StatusEfficiency.toc").read_text(encoding="utf-8").splitlines()
    files = [line.strip() for line in toc if line.strip() and not line.startswith("#")]
    for name in files:
        path = ADDON / name
        if not path.exists():
            problems.append(f"{name} is listed in the TOC but missing")
            continue
        if name == "Compat.lua":
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            code = line.split("--", 1)[0]
            match = GUARDED.search(code)
            if match:
                problems.append(f"{name}:{number} calls {match.group(1)} outside Compat.lua")
    # Every texture the addon names must ship with it, in a format the client loads.
    icons = (ADDON / "Icons.lua").read_text(encoding="utf-8")
    named = set(re.findall(r'MEDIA \.\. "([^"]+)"', icons))
    shipped = {path.name for path in (ADDON / "Media").iterdir()}
    for texture in sorted(named - shipped):
        problems.append(f"Icons.lua names Media/{texture}, which is missing")
    for texture in sorted(shipped - named):
        problems.append(f"Media/{texture} ships with the addon but nothing uses it")
    for texture in sorted(named & shipped):
        data = (ADDON / "Media" / texture).read_bytes()
        if not (data[2] == 2 and data[16] == 32 and data[12:16] == b"\x40\x00\x40\x00" and len(data) == 18 + 64 * 64 * 4):
            problems.append(f"Media/{texture} is not a 64x64 uncompressed 32-bit TGA")
    for line in toc:
        if line.startswith("## IconTexture:"):
            texture = line.split(":", 1)[1].strip().split("\\")[-1]
            if texture not in shipped:
                problems.append(f"the TOC's icon, {texture}, is missing from Media")
    if len(named) < 3:
        problems.append("could not find the shipped textures in Icons.lua")
    return problems


# What comes with a report that a unit's effects changed, while their details
# are hidden: the mock's auraPayload option, for the scenarios that do not
# choose. The first is what the client was seen to send. The second is what its
# documentation describes, and what a later build may do.
PAYLOADS = [
    ("lists", "each change report says whether effects were added, renewed or removed (seen on build 71139)"),
    ("sealed", "nothing can be read from a change report (what the documentation describes)"),
]


def main():
    args = sys.argv[1:]
    stop_early = "--stop-early" in args
    if stop_early:
        args.remove("--stop-early")
    only = None
    if "--only" in args:
        at = args.index("--only")
        only = args[at + 1] if at + 1 < len(args) else ""
        del args[at:at + 2]
        if only not in [name for name, _ in PAYLOADS]:
            print("--only takes one of: " + ", ".join(name for name, _ in PAYLOADS))
            return 2
    words = [word.lower() for word in args]
    failures = []

    for problem in static_checks():
        failures.append(("static checks", problem))

    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().REPO_ROOT = str(ROOT)
    tests = lua.eval('dofile(REPO_ROOT .. "/tests/scenarios.lua")')
    run = lua.eval('function(fn) local ok, err = xpcall(fn, debug.traceback) return ok, err or "" end')

    count = 0
    played = []
    for payload, meaning in PAYLOADS:
        if only and payload != only:
            continue
        if stop_early and failures:
            break
        played.append(payload)
        lua.globals().DEFAULT_AURA_PAYLOAD = payload
        print(f"== {payload}: {meaning}")
        count = 0
        for index in range(1, len(tests) + 1):
            name, fn = tests[index].name, tests[index].fn
            if words and not all(word in name.lower() for word in words):
                continue
            count += 1
            ok, err = run(fn)
            print(("ok    " if ok else "FAIL  ") + name)
            if not ok:
                failures.append((f"{name} [{payload}]", str(err)))
        print()

    how = "played both ways" if len(played) == len(PAYLOADS) else "played as " + " and ".join(played) + " only"
    if failures:
        for name, err in failures:
            print(f"--- {name}\n{err}\n")
        print(f"{len(failures)} failed, {count} scenarios run, {how}")
        return 1
    print(f"all {count} scenarios passed, {how}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
