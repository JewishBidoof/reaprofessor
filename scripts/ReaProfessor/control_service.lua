-- @description ReaProfessor - Control Service (OSC ExtState + MIDI)
-- @version 0.3.1
-- @author JewishBidoof
-- @noindex
-- @about Background defer loop using user-defined MIDI/OSC maps only (no defaults).

local res = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/"
local src = debug.getinfo(1, "S").source
local script_dir = (src:sub(1, 1) == "@" and src:sub(2):match("(.+[\\/])")) or res
package.path = script_dir .. "lib/?.lua;" .. res .. "lib/?.lua;" .. package.path

local Data = require("data")
local OSC = require("osc")
local MIDI = require("midi")
local Commands = require("commands")
local Config = require("config")

if not Config.actions_enabled() then
  Config.deny_action("Control Service")
  return
end

if reaper.GetExtState("ReaProfessor", "control_service") == "1" then
  reaper.ShowConsoleMsg("[ReaProfessor] Control service already running\n")
  return
end
reaper.SetExtState("ReaProfessor", "control_service", "1", false)

local midi_map = Data.load_midi_map()
local osc_map = Data.load_osc_map()
local last_midi_ts = 0
local running = true

local function reload_maps()
  midi_map = Data.load_midi_map()
  osc_map = Data.load_osc_map()
  reaper.ShowConsoleMsg(string.format(
    "[ReaProfessor] Maps loaded — MIDI:%d  OSC:%d\n", #midi_map, #osc_map))
end

reload_maps()
reaper.ShowConsoleMsg("[ReaProfessor] Control service started (user maps only)\n")
reaper.ShowConsoleMsg("  Configure bindings via ReaProfessor → Mapping\n")

local function handle_incoming_path(path, args)
  local command, bind = OSC.match(path, osc_map)
  if not command then return false end
  local arg = bind.arg
  if arg == nil or arg == "" then
    arg = args and args[1]
  end
  Commands.run_named(command, arg)
  reaper.ShowConsoleMsg(string.format("[ReaProfessor] OSC %s → %s\n", tostring(path), tostring(command)))
  return true
end

local function tick()
  if not running then
    reaper.DeleteExtState("ReaProfessor", "control_service", false)
    return
  end

  if reaper.GetExtState("ReaProfessor", "maps_dirty") == "1" then
    reaper.DeleteExtState("ReaProfessor", "maps_dirty", false)
    reload_maps()
  end

  local one = OSC.poll_oneshot()
  if one then handle_incoming_path(one.path, one.args) end

  for _, item in ipairs(OSC.drain_queue()) do
    handle_incoming_path(item.path, item.args)
  end

  local events
  events, last_midi_ts = MIDI.poll_commands_v2(midi_map, last_midi_ts)
  for _, ev in ipairs(events) do
    Commands.run_named(ev.command, ev.arg)
    reaper.ShowConsoleMsg("[ReaProfessor] MIDI → " .. tostring(ev.command) .. "\n")
  end

  if reaper.GetExtState("ReaProfessor", "control_service_stop") == "1" then
    reaper.DeleteExtState("ReaProfessor", "control_service_stop", false)
    running = false
  end

  reaper.defer(tick)
end

tick()
