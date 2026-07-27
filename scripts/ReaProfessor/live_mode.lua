-- @description ReaProfessor - Live Mode
-- @version 0.3.2
-- @author JewishBidoof
-- @noindex
-- @about Focus mixer and open cue list for live use.

local res = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/"
local src = debug.getinfo(1, "S").source
local script_dir = (src:sub(1, 1) == "@" and src:sub(2):match("(.+[\\/])")) or res
package.path = script_dir .. "lib/?.lua;" .. res .. "lib/?.lua;" .. package.path

local Config = require("config")
local Data = require("data")

if not Config.actions_enabled() then
  Config.deny_action("Live Mode")
  return
end

local meta = Data.load_meta()
local enable = not meta.live_mode

local function ensure_mixer(visible)
  local state = reaper.GetToggleCommandState(40078)
  if state < 0 then
    reaper.Main_OnCommand(40078, 0)
    return
  end
  if (state == 1) ~= visible then
    reaper.Main_OnCommand(40078, 0)
  end
end

if enable then
  ensure_mixer(true)
  local cue = script_dir .. "cue_list.lua"
  if reaper.file_exists(cue) then
    reaper.defer(function()
      dofile(cue)
    end)
  end
  reaper.ShowConsoleMsg("[ReaProfessor] Live Mode ON\n")
else
  reaper.ShowConsoleMsg("[ReaProfessor] Live Mode OFF\n")
end

meta.live_mode = enable
Data.save_meta(meta)
reaper.Main_OnCommand(1011, 0)
