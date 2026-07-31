-- @description ReaProfessor - Extensions menu status / repair
-- @version 0.4.4
-- @author JewishBidoof
-- @about Checks native Extensions registration and removes any old menu.ini hijack.
-- @noindex

local res = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/"
local src = debug.getinfo(1, "S").source
local script_dir = (src:sub(1, 1) == "@" and src:sub(2):match("(.+[\\/])")) or res
package.path = script_dir .. "lib/?.lua;" .. res .. "lib/?.lua;" .. package.path

local alt = reaper.GetResourcePath() .. "/Scripts/Live/ReaProfessor/"
package.path = alt .. "lib/?.lua;" .. package.path

local Menu = require("menu")

local hub = script_dir .. "ReaProfessor.lua"
if not reaper.file_exists(hub) then
  hub = alt .. "ReaProfessor.lua"
end

local ok, msg, named, cmd = Menu.install(hub)
local text
if ok then
  text = string.format("%s\n\nAction ID: %s\nCommand: %s", tostring(msg), tostring(named), tostring(cmd))
else
  text = "Failed:\n\n" .. tostring(msg)
end
reaper.ShowMessageBox(text, "ReaProfessor", 0)
