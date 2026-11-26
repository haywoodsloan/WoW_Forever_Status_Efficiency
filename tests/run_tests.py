#!/usr/bin/env python3
"""Runs the addon against a pretend game client.

    pip install lupa
    python3 tests/run_tests.py [words to filter scenario names by]

The addon is plain Lua 5.1, the same dialect the game embeds, so it is loaded
unchanged into a Lua 5.1 runtime where tests/wow_mock.lua stands in for the game.
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


def main():
    words = [word.lower() for word in sys.argv[1:]]
    failures = []

    for problem in static_checks():
        failures.append(("static checks", problem))

    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().REPO_ROOT = str(ROOT)
    tests = lua.eval('dofile(REPO_ROOT .. "/tests/scenarios.lua")')
    run = lua.eval('function(fn) local ok, err = xpcall(fn, debug.traceback) return ok, err or "" end')

    count = 0
    for index in range(1, len(tests) + 1):
        name, fn = tests[index].name, tests[index].fn
        if words and not all(word in name.lower() for word in words):
            continue
        count += 1
        ok, err = run(fn)
        print(("ok    " if ok else "FAIL  ") + name)
        if not ok:
            failures.append((name, str(err)))

    print()
    if failures:
        for name, err in failures:
            print(f"--- {name}\n{err}\n")
        print(f"{len(failures)} failed, {count} scenarios run")
        return 1
    print(f"all {count} scenarios passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
