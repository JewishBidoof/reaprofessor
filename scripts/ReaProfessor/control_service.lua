-- @description ReaProfessor - Control Service (OSC ExtState + MIDI)
-- @version 0.2.0
-- @author ReaProfessor
-- @about Background defer loop: MIDI map + ExtState OSC queue → commands.
-- @provide [main] .

local res = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/"
local src = debug.getinfo(1, "S").source
local script_dir = (src:sub(1, 1) == "@" and src:sub(2):match("(.+[\\/])")) or res
package.path = script_dir .. "lib/?.lua;" .. res .. "lib/?.lua;" .. package.path

local Data = require("data")
local OSC = require("osc")
local MIDI = require("midi")
local Commands = require("commands")

-- Singleton guard via global ExtState
if reaper.GetExtState("ReaProfessor", "control_service") == "1" then
  reaper.ShowConsoleMsg("[ReaProfessor] Control service already running\n")
  return
end
reaper.SetExtState("ReaProfessor", "control_service", "1", false)

local handlers = Commands.handlers()
local midi_map = Data.load_midi_map() or MIDI.default_map()
if not Data.load_midi_map() then
  Data.save_midi_map(midi_map)
end
local last_midi_ts = 0
local running = true

reaper.ShowConsoleMsg("[ReaProfessor] Control service started (MIDI + OSC queue)\n")
reaper.ShowConsoleMsg("  OSC oneshot: ExtState ReaProfessor/osc_cmd = /CueLists/Go\n")
reaper.ShowConsoleMsg("  MIDI defaults: Note 36=GO, 37=Back, CC64=GO (ch1)\n")

local function handle_path(path, args)
  if OSC.dispatch(path, args, handlers) then
    reaper.ShowConsoleMsg(string.format("[ReaProfessor] OSC %s\n", tostring(path)))
  end
end

local function tick()
  if not running then
    reaper.DeleteExtState("ReaProfessor", "control_service", false)
    return
  end

  -- ExtState oneshot
  local one = OSC.poll_oneshot()
  if one then handle_path(one.path, one.args) end

  -- Project ExtState queue
  for _, item in ipairs(OSC.drain_queue()) do
    handle_path(item.path, item.args)
  end

  -- MIDI
  local cmds
  cmds, last_midi_ts = MIDI.poll_commands_v2(midi_map, last_midi_ts)
  for _, cmd in ipairs(cmds) do
    Commands.run_named(cmd)
    reaper.ShowConsoleMsg("[ReaProfessor] MIDI → " .. tostring(cmd) .. "\n")
  end

  -- Allow stop via ExtState
  if reaper.GetExtState("ReaProfessor", "control_service_stop") == "1" then
    reaper.DeleteExtState("ReaProfessor", "control_service_stop", false)
    running = false
  end

  reaper.defer(tick)
end

tick()
