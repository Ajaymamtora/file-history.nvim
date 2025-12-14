-- Loaded by busted before each test file.
-- Sets up package paths for local development dependencies (LuaRocks).

local lua_ver = _VERSION:match("(%d+%.%d+)")
local home = os.getenv("HOME") or ""

local luarocks_share = home .. "/.luarocks/share/lua/" .. (lua_ver or "")
local luarocks_lib = home .. "/.luarocks/lib/lua/" .. (lua_ver or "")

package.path = table.concat({
  './lua/?.lua',
  './lua/?/init.lua',
  './spec/?.lua',
  './spec/?/init.lua',
  luarocks_share .. '/?.lua',
  luarocks_share .. '/?/init.lua',
  package.path,
}, ';')

package.cpath = table.concat({
  luarocks_lib .. '/?.so',
  package.cpath,
}, ';')
