"""Runs two versions of the Status Efficiency tooltip reader (Spells.ParseDuration)
over a file of spell descriptions, one per line, and prints every line the two
read differently: the old result, the new one, and the words that decided it.

  python3 compare_tooltip_readers.py [descriptions.txt] [git revision]

The old reader is StatusEfficiency/Spells.lua at the given revision (HEAD by
default), the new one is the file in the working tree. Run it before changing
which wordings count as an effect's length: a line that goes from a number to
None is a skill losing its icon. tooltip_corpus.txt, next to this file, holds
about 130 Classic and Season of Discovery descriptions written from memory, so
they are close to the game's wording and not copies of it.

SE_REPO=/path/to/clone compares in another checkout than the one this file is
in. Needs `pip install lupa`.
"""
import locale
import os
import subprocess
import sys
from pathlib import Path

from lupa.lua51 import LuaRuntime

# The game's Lua sorts bytes by the plain "C" character table. Python takes the
# computer's own at start (a code page on Windows), and the Lua inside it would
# follow: go back to the plain one first, as tests/run_tests.py does.
locale.setlocale(locale.LC_ALL, "C")

repo = os.environ.get('SE_REPO') or str(Path(__file__).resolve().parents[2])
corpus = sys.argv[1] if len(sys.argv) > 1 else str(Path(__file__).with_name('tooltip_corpus.txt'))
revision = sys.argv[2] if len(sys.argv) > 2 else 'HEAD'


def parser(src):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('NS = { db = { spells = {}, learned = {} } }')
    fn = lua.eval('function(src) local f = assert(loadstring(src, "Spells")); f("StatusEfficiency", NS); '
                  'return NS.Spells.ParseDuration end')
    return fn(src)


old = parser(subprocess.run(['git', '-C', repo, 'show', revision + ':StatusEfficiency/Spells.lua'],
                            capture_output=True, check=True).stdout.decode('utf-8'))
new = parser(open(repo + '/StatusEfficiency/Spells.lua', encoding='utf-8').read())
same = 0
for line in open(corpus, encoding='utf-8'):
    line = line.strip()
    if not line:
        continue
    o = old(line)
    o = o[0] if isinstance(o, tuple) else o
    n = new(line)
    n, read, passed = n if isinstance(n, tuple) else (n, None, None)
    if o == n:
        same += 1
        continue
    print(f'{o} -> {n}   passed over: {passed!r}   read from: {read!r}\n     {line}')
print('read the same by both:', same)
