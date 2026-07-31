-- @description ReaProfessor - Restore / install Extensions menu entry
-- @version 0.4.0
-- @author JewishBidoof
-- @about Registers ReaProfessor in Actions and installs Extensions → ReaProfessor (flat item).
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
  text = string.format(
    "%s\n\nAction ID: %s\nCommand: %s\n\nExtensions → ReaProfessor is a flat menu item (not a submenu),\nso ReaPack/SWS stay as separate top-level Extensions entries.\n\nIf the message asks you to quit, use File → Quit, then reopen.",
    tostring(msg),
    tostring(named),
    tostring(cmd)
  )
else
  text = "Failed:\n\n" .. tostring(msg)
end
reaper.ShowMessageBox(text, "ReaProfessor", 0)
