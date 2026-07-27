-- @description ReaProfessor - OSC/MIDI Control panel
-- @version 0.3.2
-- @author JewishBidoof
-- @noindex
-- @about Start/stop the control service and open the mapping editor.

local res = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/"
local src = debug.getinfo(1, "S").source
local script_dir = (src:sub(1, 1) == "@" and src:sub(2):match("(.+[\\/])")) or res
package.path = script_dir .. "lib/?.lua;" .. res .. "lib/?.lua;" .. package.path

local UI = require("ui")
local Data = require("data")
local Commands = require("commands")
local Config = require("config")

local running = true
local pending_open = nil
local status = Config.actions_enabled() and "" or "Prototype — service/GO disabled"

UI.init("ReaProfessor · Control", 560, 360, 0)

local function ensure_service()
  if not Config.actions_enabled() then
    return Config.deny_action("Control Service")
  end
  if reaper.GetExtState("ReaProfessor", "control_service") == "1" then
    status = "Control service already running"
    return
  end
  local path = script_dir .. "control_service.lua"
  if reaper.file_exists(path) then
    reaper.defer(function() dofile(path) end)
    status = "Control service starting…"
  else
    status = "Missing control_service.lua"
  end
end

local function open_mapping()
  local path = script_dir .. "mapping.lua"
  if not reaper.file_exists(path) then
    reaper.ShowMessageBox("Missing mapping.lua", "ReaProfessor", 0)
    return
  end
  pending_open = path
  running = false
end

local function draw()
  local w, h = gfx.w, gfx.h
  UI.fill_rect(0, 0, w, h, UI.colors.bg)
  gfx.setfont(2)
  UI.label(16, 14, "CONTROL", UI.colors.accent)
  gfx.setfont(3)
  UI.label(140, 22, "Service + custom MIDI/OSC maps", UI.colors.muted)

  local midi_n = #Data.load_midi_map()
  local osc_n = #Data.load_osc_map()
  local svc = reaper.GetExtState("ReaProfessor", "control_service") == "1"

  gfx.setfont(1)
  UI.label(24, 70, "Service: " .. (svc and "RUNNING" or "stopped"), svc and UI.colors.go or UI.colors.danger)
  UI.label(24, 100, string.format("Mappings:  %d MIDI  ·  %d OSC", midi_n, osc_n), UI.colors.text)
  gfx.setfont(3)
  UI.label(24, 130, "Mapping UI is available; starting the service is gated until finalized.", UI.colors.muted)

  if UI.button("map", 24, 170, w - 48, 44, "Open Mapping…", { bg = UI.colors.accent, fg = {0.08, 0.08, 0.08} }) then
    open_mapping()
  end

  if UI.button("start", 24, 230, (w - 60) / 2, 40, "Start service") then
    ensure_service()
  end
  if UI.button("stop", 36 + (w - 60) / 2, 230, (w - 60) / 2, 40, "Stop service") then
    reaper.SetExtState("ReaProfessor", "control_service_stop", "1", false)
    status = "Stop requested"
  end

  if UI.button("fire", 24, 286, w - 48, 36, "Test: Fire Cue GO now") then
    if not Config.actions_enabled() then
      Config.deny_action("Cue GO")
    else
      Commands.cue_go()
      status = "cue_go executed (direct, not via map)"
    end
  end

  UI.label(24, h - 28, status, UI.colors.muted)

  local ch = gfx.getchar()
  if ch == 27 or ch < 0 then running = false end
end

local function loop()
  if not running then
    gfx.quit()
    if pending_open then
      local path = pending_open
      pending_open = nil
      reaper.defer(function() dofile(path) end)
    end
    return
  end
  draw()
  gfx.update()
  reaper.defer(loop)
end

loop()
