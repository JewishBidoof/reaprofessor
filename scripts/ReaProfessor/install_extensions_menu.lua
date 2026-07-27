-- @description ReaProfessor - Restore Extensions menu
-- @version 0.3.6
-- @author JewishBidoof
-- @about Registers ReaProfessor in Actions and removes our prior Extensions menu customization (which nested other extensions).
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
    "%s\n\nAction ID: %s\nCommand: %s\n\nReaProfessor stays in the Actions list.\nWe do not add an Extensions menu item — that nesting broke ReaPack/SWS.\n\nIf the message asks you to quit, use File → Quit, then reopen.",
    tostring(msg),
    tostring(named),
    tostring(cmd)
  )
else
  text = "Failed:\n\n" .. tostring(msg)
end
reaper.ShowMessageBox(text, "ReaProfessor", 0)
