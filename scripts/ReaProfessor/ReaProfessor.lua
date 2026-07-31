-- @description ReaProfessor
-- @version 0.5.1
-- @author JewishBidoof
-- @about Live cue list: each cue recalls a full FX + send snapshot.
-- @noindex

local res = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/"
local src = debug.getinfo(1, "S").source
local script_dir = (src:sub(1, 1) == "@" and src:sub(2):match("(.+[\\/])")) or res
local alt = reaper.GetResourcePath() .. "/Scripts/Live/ReaProfessor/"
package.path = script_dir .. "lib/?.lua;" .. alt .. "lib/?.lua;" .. res .. "lib/?.lua;" .. package.path

-- Quietly keep Extensions registration / clear old menu.ini hijacks.
do
  local ok, Menu = pcall(require, "menu")
  if ok and Menu and Menu.ensure then
    local hub = script_dir .. "ReaProfessor.lua"
    if not reaper.file_exists(hub) then hub = alt .. "ReaProfessor.lua" end
    pcall(Menu.ensure, hub)
  end
end

-- Single-screen app: the cue list.
local cue = script_dir .. "cue_list.lua"
if not reaper.file_exists(cue) then cue = alt .. "cue_list.lua" end
dofile(cue)
