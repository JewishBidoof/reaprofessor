-- @description ReaProfessor - Create Channels
-- @version 0.5.3
-- @author JewishBidoof
-- @noindex
-- @about Popup confirm, then create N mono channels with 1:1 hardware I/O.

local res = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/"
local src = debug.getinfo(1, "S").source
local script_dir = (src:sub(1, 1) == "@" and src:sub(2):match("(.+[\\/])")) or res
package.path = script_dir .. "lib/?.lua;" .. res .. "lib/?.lua;" .. package.path

-- Standalone action: settings + confirm popups only (no success message box).
local Routing = require("routing")
Routing.prompt_create_channels()
