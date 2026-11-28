#!/usr/bin/env python3
"""Lists every global the addon's Lua files read or write.

    pip install lupa
    python3 list_globals.py [/path/to/repo/StatusEfficiency [File.lua ...]]

With no folder named, the addon in the checkout this file is in is read.

Each file is compiled with a real Lua 5.1 (no code is run) and the GETGLOBAL
and SETGLOBAL instructions are read out of the bytecode, so this also covers
code the test scenarios never reach. Anything in the list that is not a Lua
library name, a game API name or one of the addon's own three globals
(StatusEfficiencyDB and the two SLASH_ names) is a typo or a leaked global.
"""
import locale
import struct
import sys
from pathlib import Path

from lupa import lua51

# The game's Lua sorts bytes by the plain "C" character table. Python takes the
# computer's own at start (a code page on Windows), and the Lua inside it would
# follow: go back to the plain one first, as tests/run_tests.py does.
locale.setlocale(locale.LC_ALL, "C")

GETGLOBAL, SETGLOBAL = 5, 7


def parse(data):
    assert data[:5] == b"\x1bLua\x51", "not Lua 5.1 bytecode"
    assert tuple(data[6:11]) == (1, 4, 8, 4, 8), "unexpected bytecode layout"
    pos = [12]

    def u8():
        value = data[pos[0]]
        pos[0] += 1
        return value

    def i32():
        value = struct.unpack_from("<i", data, pos[0])[0]
        pos[0] += 4
        return value

    def u32():
        value = struct.unpack_from("<I", data, pos[0])[0]
        pos[0] += 4
        return value

    def string():
        length = struct.unpack_from("<Q", data, pos[0])[0]
        pos[0] += 8
        if length == 0:
            return None
        text = data[pos[0]:pos[0] + length - 1]
        pos[0] += length
        return text.decode("utf-8", "replace")

    found = []

    def function():
        string()
        i32()
        i32()
        for _ in range(4):
            u8()
        code = [u32() for _ in range(i32())]
        constants = []
        for _ in range(i32()):
            kind = u8()
            if kind == 0:
                constants.append(None)
            elif kind == 1:
                constants.append(bool(u8()))
            elif kind == 3:
                constants.append(struct.unpack_from("<d", data, pos[0])[0])
                pos[0] += 8
            elif kind == 4:
                constants.append(string())
            else:
                raise ValueError(f"unknown constant type {kind}")
        for _ in range(i32()):
            function()
        lines = [i32() for _ in range(i32())]
        for _ in range(i32()):
            string()
            i32()
            i32()
        for _ in range(i32()):
            string()
        for index, instruction in enumerate(code):
            opcode = instruction & 0x3F
            if opcode in (GETGLOBAL, SETGLOBAL):
                name = constants[instruction >> 14]
                line = lines[index] if index < len(lines) else 0
                found.append((name, "WRITE" if opcode == SETGLOBAL else "read", line))

    function()
    return found


def main():
    folder = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / "StatusEfficiency"
    names = sys.argv[2:] or sorted(path.name for path in folder.glob("*.lua"))
    lua = lua51.LuaRuntime(encoding=None)
    dump = lua.eval(
        "function(source, name) local fn, err = loadstring(source, name) "
        "if not fn then return nil, err end return string.dump(fn) end"
    )
    uses = {}
    failed = False
    for name in names:
        result = dump((folder / name).read_bytes(), ("@" + name).encode())
        if isinstance(result, tuple):
            print(f"{name} does not compile: {result[1].decode('utf-8', 'replace')}")
            failed = True
            continue
        for glob, how, line in parse(bytes(result)):
            uses.setdefault((glob, how), []).append(f"{name}:{line}")
    for (glob, how), where in sorted(uses.items()):
        more = " ..." if len(where) > 5 else ""
        print(f"{how:5} {glob:34} {len(where):3}  {', '.join(where[:5])}{more}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
