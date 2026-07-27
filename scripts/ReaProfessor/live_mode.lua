-- @description ReaProfessor - Live Mode
-- @version 0.3.0
-- @author JewishBidoof
-- @noindex
-- @about Focus mixer and open cue list for live use.

local res = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/"
local src = debug.getinfo(1, "S").source
local script_dir = (src:sub(1, 1) == "@" and src:sub(2):match("(.+[\\/])")) or res
package.path = script_dir .. "lib/?.lua;" .. res .. "lib/?.lua;" .. package.path

local Data = require("data")

local meta = Data.load_meta()
local enable = not meta.live_mode

-- Command IDs (main section)
local CMD = {
  SHOW_MIXER = 40078,          -- View: Toggle mixer visible (toggle — use carefully)
  MIXER = 40083,               -- Mixer: Toggle master track visible — fallback set below
  TOGGLE_TCP_VIS = 40027,      -- not always present; we use SetMaster*
}

-- Prefer show/hide via window actions that exist across platforms.
local function ensure_mixer(visible)
  -- 40078 toggles; check state via GetToggleCommandState
  local state = reaper.GetToggleCommandState(40078)
  if state < 0 then
    -- action may not report state; just invoke show mixer action if available
    reaper.Main_OnCommand(40078, 0)
    return
  end
  if (state == 1) ~= visible then
    reaper.Main_OnCommand(40078, 0)
  end
end

local function set_arrange_zoom_out()
  -- Zoom out a bit so arrange is less dominant if still visible
  reaper.Main_OnCommand(1011, 0) -- zoom out horizontal (safe no-op-ish)
end

if enable then
  ensure_mixer(true)
  -- Hide transport options that clutter live; keep transport itself
  -- Show FX browser closed
  -- Open cue list automatically
  local cue = script_dir .. "cue_list.lua"
  if reaper.file_exists(cue) then
    -- defer open so toggle completes first
    reaper.defer(function()
      dofile(cue)
    end)
  end
  reaper.ShowConsoleMsg("[ReaProfessor] Live Mode ON — mixer focused, cue list opening\n")
else
  reaper.ShowConsoleMsg("[ReaProfessor] Live Mode OFF\n")
end

meta.live_mode = enable
Data.save_meta(meta)
set_arrange_zoom_out()
