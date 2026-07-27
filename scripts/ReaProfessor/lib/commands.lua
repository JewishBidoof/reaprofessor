-- @description ReaProfessor central command handlers (cues, snaps, channels)
-- @version 0.2.0
-- @author ReaProfessor

local Commands = {}

local function load_deps()
  return require("data"), require("osc"), require("routing")
end

local function find_snapshot(snaps, key)
  if type(key) == "number" then
    return snaps[key], key
  end
  local as_num = tonumber(key)
  if as_num and snaps[as_num] then return snaps[as_num], as_num end
  for i, s in ipairs(snaps) do
    if s.name == key then return s, i end
  end
  return nil, nil
end

function Commands.cue_go()
  local Data = require("data")
  local cues = Data.load_cues()
  local meta = Data.load_meta()
  local snaps = Data.load_snapshots()
  if #cues == 0 then return false end
  local idx = meta.cue_index or 1
  if idx < 1 then idx = 1 end
  if idx > #cues then idx = #cues end
  local cue = cues[idx]
  if cue and cue.kind == "snapshot" then
    local name = cue.payload and cue.payload.snapshot
    local snap = select(1, find_snapshot(snaps, name))
    if snap then Data.recall_snapshot(snap) end
  elseif cue and cue.kind == "action" then
    local cmd = cue.payload and cue.payload.command_id
    if cmd then
      local id = reaper.NamedCommandLookup(tostring(cmd))
      if id == 0 then id = tonumber(cmd) or 0 end
      if id ~= 0 then reaper.Main_OnCommand(id, 0) end
    end
  end
  meta.cue_index = math.min(#cues, idx + 1)
  Data.save_meta(meta)
  return true
end

function Commands.cue_back()
  local Data = require("data")
  local cues = Data.load_cues()
  local meta = Data.load_meta()
  local snaps = Data.load_snapshots()
  if #cues == 0 then return false end
  local idx = math.max(1, (meta.cue_index or 1) - 1)
  local cue = cues[idx]
  if cue and cue.kind == "snapshot" then
    local name = cue.payload and cue.payload.snapshot
    local snap = select(1, find_snapshot(snaps, name))
    if snap then Data.recall_snapshot(snap) end
  end
  meta.cue_index = idx
  Data.save_meta(meta)
  return true
end

function Commands.cue_goto(n)
  local Data = require("data")
  local cues = Data.load_cues()
  local meta = Data.load_meta()
  local snaps = Data.load_snapshots()
  local idx = tonumber(n) or 1
  if idx < 1 or idx > #cues then return false end
  local cue = cues[idx]
  if cue and cue.kind == "snapshot" then
    local name = cue.payload and cue.payload.snapshot
    local snap = select(1, find_snapshot(snaps, name))
    if snap then Data.recall_snapshot(snap) end
  end
  meta.cue_index = idx
  Data.save_meta(meta)
  return true
end

function Commands.snap_recall(key)
  local Data = require("data")
  local snaps = Data.load_snapshots()
  local snap = select(1, find_snapshot(snaps, key))
  if not snap then return false end
  return Data.recall_snapshot(snap)
end

function Commands.set_snapshot_mode(mode)
  local Data = require("data")
  local meta = Data.load_meta()
  mode = tostring(mode or "")
  if mode ~= "bypass" and mode ~= "params" and mode ~= "full" then return false end
  meta.snapshot_mode = mode
  Data.save_meta(meta)
  return true
end

function Commands.set_channel_mode(mode)
  local Data = require("data")
  local meta = Data.load_meta()
  mode = tostring(mode or "")
  if mode ~= "same_strip" and mode ~= "double_patch" then return false end
  meta.channel_mode = mode
  Data.save_meta(meta)
  return true
end

function Commands.create_channels(count, mode)
  local Data, _, Routing = load_deps()
  local meta = Data.load_meta()
  mode = mode or meta.channel_mode or "same_strip"
  count = tonumber(count) or 16
  return Routing.create_channels(count, { mode = mode })
end

function Commands.apply_record_safe(mode)
  local Data, _, Routing = load_deps()
  local meta = Data.load_meta()
  Routing.apply_record_safe(mode or meta.channel_mode)
  return true
end

function Commands.handlers()
  local OSC = require("osc")
  return {
    [OSC.addresses.cue_go] = function() Commands.cue_go() end,
    [OSC.addresses.cue_back] = function() Commands.cue_back() end,
    [OSC.addresses.cue_goto] = function(args) Commands.cue_goto(args[1]) end,
    [OSC.addresses.snap_recall] = function(args) Commands.snap_recall(args[1]) end,
    [OSC.addresses.snap_recall_name] = function(args) Commands.snap_recall(args[1]) end,
    [OSC.addresses.snap_mode] = function(args) Commands.set_snapshot_mode(args[1]) end,
    [OSC.addresses.create_channels] = function(args) Commands.create_channels(args[1], args[2]) end,
    [OSC.addresses.channel_mode] = function(args) Commands.set_channel_mode(args[1]) end,
    [OSC.addresses.record_safe] = function(args) Commands.apply_record_safe(args[1]) end,
    [OSC.addresses.live_mode] = function()
      local dir = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/"
      if reaper.file_exists(dir .. "live_mode.lua") then dofile(dir .. "live_mode.lua") end
    end,
  }
end

function Commands.run_named(command)
  if command == "cue_go" then return Commands.cue_go()
  elseif command == "cue_back" then return Commands.cue_back()
  elseif command == "live_mode" then
    local dir = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/"
    if reaper.file_exists(dir .. "live_mode.lua") then dofile(dir .. "live_mode.lua") end
    return true
  end
  return false
end

return Commands
