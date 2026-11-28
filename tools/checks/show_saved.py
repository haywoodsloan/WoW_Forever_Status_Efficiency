"""Prints one key of a saved settings file (StatusEfficiency.lua from the game's
SavedVariables folder), or its top-level keys. The file is only read.

  python3 show_saved.py <saved file> <key.path|keys> [depth]

Keep copies of saved files out of the repository: they are the player's own
data. Needs `pip install lupa`.
"""
import locale
import sys
from lupa import lua51
# Lua sorts bytes by the C library's table. The game keeps the plain one, and so must this
# (on Windows Python starts with a code page in which bytes above 127 are letters).
locale.setlocale(locale.LC_ALL, "C")
path, want = sys.argv[1], sys.argv[2]
depth = sys.argv[3] if len(sys.argv) > 3 else "nil"
lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lua.globals().SAVED = open(path, "rb").read().decode("utf-8", "replace")
lua.globals().WANT = want
print(lua.eval('''(function()
local env = {}
local chunk = assert(loadstring(SAVED))
setfenv(chunk, env)
chunk()
local db = env.StatusEfficiencyDB
local function show(v, indent, depth)
  indent = indent or ""
  if type(v) == "string" then return string.format("%%q", v) end
  if type(v) ~= "table" then return tostring(v) end
  if depth and depth <= 0 then return "{...}" end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) if type(a) == type(b) then return a < b end return tostring(a) < tostring(b) end)
  local out = {}
  for _, k in ipairs(keys) do
    out[#out + 1] = indent .. "  " .. tostring(k) .. " = " .. show(v[k], indent .. "  ", depth and depth - 1)
  end
  if #out == 0 then return "{}" end
  return "{\\n" .. table.concat(out, "\\n") .. "\\n" .. indent .. "}"
end
if WANT == "keys" then
  local keys = {}
  for k, v in pairs(db) do keys[#keys + 1] = k .. " (" .. type(v) .. (type(v) ~= "table" and (" = " .. tostring(v)) or "") .. ")" end
  table.sort(keys)
  return table.concat(keys, "\\n")
end
local v = db
for part in WANT:gmatch("[^.]+") do v = v and v[tonumber(part) or part] end
return WANT .. " = " .. show(v, "", %s)
end)()''' % depth))
