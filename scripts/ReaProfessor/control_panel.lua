-- @description ReaProfessor - OSC/MIDI Control panel
-- @version 0.2.0
-- @author ReaProfessor
-- @about Start control service, edit MIDI bindings, fire test OSC commands.

local res = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/"
local src = debug.getinfo(1, "S").source
local script_dir = (src:sub(1, 1) == "@" and src:sub(2):match("(.+[\\/])")) or res
package.path = script_dir .. "lib/?.lua;" .. res .. "lib/?.lua;" .. package.path

local UI = require("ui")
local Data = require("data")
local OSC = require("osc")
local MIDI = require("midi")
local Commands = require("commands")

local midi_map = Data.load_midi_map() or MIDI.default_map()
local running = true
local status = ""

UI.init("ReaProfessor · Control", 640, 480, 0)

local function ensure_service()
  if reaper.GetExtState("ReaProfessor", "control_service") == "1" then
    status = "Control service already running"
    return
  end
  local path = script_dir .. "control_service.lua"
  if reaper.file_exists(path) then
    -- Launch service in defer without blocking this UI
    reaper.defer(function() dofile(path) end)
    status = "Control service starting…"
  else
    status = "Missing control_service.lua"
  end
end

local function draw()
  local w, h = gfx.w, gfx.h
  UI.fill_rect(0, 0, w, h, UI.colors.bg)
  gfx.setfont(2)
  UI.label(16, 14, "CONTROL", UI.colors.accent)
  gfx.setfont(3)
  UI.label(140, 22, "OSC ExtState bridge + MIDI map", UI.colors.muted)

  local svc = reaper.GetExtState("ReaProfessor", "control_service") == "1"
  gfx.setfont(1)
  UI.label(24, 60, "Service: " .. (svc and "RUNNING" or "stopped"), svc and UI.colors.go or UI.colors.danger)
  if UI.button("start", w - 220, 52, 100, 32, "Start") then ensure_service() end
  if UI.button("stop", w - 110, 52, 90, 32, "Stop") then
    reaper.SetExtState("ReaProfessor", "control_service_stop", "1", false)
    status = "Stop requested"
  end

  UI.label(24, 110, "Test OSC (via queue)", UI.colors.text)
  if UI.button("tgo", 24, 140, 100, 36, "GO") then
    OSC.enqueue(OSC.addresses.cue_go, {})
    ensure_service()
    status = "Queued " .. OSC.addresses.cue_go
  end
  if UI.button("tback", 134, 140, 100, 36, "BACK") then
    OSC.enqueue(OSC.addresses.cue_back, {})
    ensure_service()
    status = "Queued " .. OSC.addresses.cue_back
  end
  if UI.button("tsnap", 244, 140, 140, 36, "Recall snap 1") then
    OSC.enqueue(OSC.addresses.snap_recall, { 1 })
    ensure_service()
    status = "Queued snapshot recall 1"
  end

  gfx.setfont(3)
  UI.label(24, 200, "MIDI bindings (channel / type / number → command)", UI.colors.muted)
  local y = 230
  for i, bind in ipairs(midi_map) do
    if y > h - 80 then break end
    local desc
    if bind.type == "cc" then
      desc = string.format("Ch%d  CC%d  →  %s", bind.channel or 1, bind.cc or 0, bind.command)
    else
      desc = string.format("Ch%d  Note %d  →  %s", bind.channel or 1, bind.note or 0, bind.command)
    end
    UI.fill_rect(16, y, w - 32, 26, (i % 2 == 0) and UI.colors.row_alt or UI.colors.panel)
    gfx.setfont(1)
    UI.label(28, y + 4, desc, UI.colors.text)
    y = y + 28
  end

  if UI.button("reset", 24, h - 50, 160, 36, "Reset MIDI map") then
    midi_map = MIDI.default_map()
    Data.save_midi_map(midi_map)
    status = "MIDI map reset to defaults"
  end
  if UI.button("fire", 200, h - 50, 160, 36, "Fire GO now") then
    Commands.cue_go()
    status = "cue_go executed"
  end

  UI.label(380, h - 40, status, UI.colors.muted)

  local ch = gfx.getchar()
  if ch == 27 or ch < 0 then running = false end
end

local function loop()
  if not running then gfx.quit(); return end
  draw()
  gfx.update()
  reaper.defer(loop)
end

ensure_service()
loop()
