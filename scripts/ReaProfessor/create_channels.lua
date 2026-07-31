-- @description ReaProfessor - Create Channels
-- @version 0.5.1
-- @author JewishBidoof
-- @noindex
-- @about Popup confirm, then create N mono channels with 1:1 hardware I/O.

local res = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/"
local src = debug.getinfo(1, "S").source
local script_dir = (src:sub(1, 1) == "@" and src:sub(2):match("(.+[\\/])")) or res
package.path = script_dir .. "lib/?.lua;" .. res .. "lib/?.lua;" .. package.path

local Routing = require("routing")
local ok, msg = Routing.prompt_create_channels()
if ok then
  reaper.ShowMessageBox(tostring(msg), "ReaProfessor", 0)
elseif msg and msg ~= "cancelled" and msg ~= "disabled" then
  reaper.ShowMessageBox(tostring(msg), "ReaProfessor", 0)
end
