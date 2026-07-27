-- @description ReaProfessor central command handlers
-- @version 0.3.0
-- @author JewishBidoof
-- @noindex

local Commands = {}

Commands.catalog = {
  { id = "cue_go",            label = "Cue: GO",                 needs_arg = false },
  { id = "cue_back",          label = "Cue: Back",               needs_arg = false },
  { id = "cue_goto",          label = "Cue: Go To #",            needs_arg = true,  arg_hint = "cue index" },
  { id = "snap_recall",       label = "Snapshot: Recall",        needs_arg = true,  arg_hint = "index or name" },
  { id = "snap_mode_bypass",  label = "Snapshot mode: Bypass",   needs_arg = false },
  { id = "snap_mode_params",  label = "Snapshot mode: Params",   needs_arg = false },
  { id = "snap_mode_full",    label = "Snapshot mode: Full FX",  needs_arg = false },
  { id = "create_channels",   label = "Create Channels",         needs_arg = true,  arg_hint = "count" },
  { id = "channel_mode_same", label = "Channel mode: Same strip", needs_arg = false },
  { id = "channel_mode_dbl",  label = "Channel mode: Double patch", needs_arg = false },
  { id = "record_safe",       label = "Apply record-safe",       needs_arg = false },
  { id = "live_mode",         label = "Toggle Live Mode",        needs_arg = false },
}

function Commands.label_for(id)
  for _, c in ipairs(Commands.catalog) do
    if c.id == id then return c.label end
  end
  return id or "?"
end

function Commands.catalog_entry(id)
  for _, c in ipairs(Commands.catalog) do
    if c.id == id then return c end
  end
  return nil
end

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

function Commands.run_named(command, arg)
  if command == "cue_go" then return Commands.cue_go()
  elseif command == "cue_back" then return Commands.cue_back()
  elseif command == "cue_goto" then return Commands.cue_goto(arg)
  elseif command == "snap_recall" then return Commands.snap_recall(arg)
  elseif command == "snap_mode_bypass" then return Commands.set_snapshot_mode("bypass")
  elseif command == "snap_mode_params" then return Commands.set_snapshot_mode("params")
  elseif command == "snap_mode_full" then return Commands.set_snapshot_mode("full")
  elseif command == "create_channels" then return Commands.create_channels(arg)
  elseif command == "channel_mode_same" then return Commands.set_channel_mode("same_strip")
  elseif command == "channel_mode_dbl" then return Commands.set_channel_mode("double_patch")
  elseif command == "record_safe" then return Commands.apply_record_safe()
  elseif command == "live_mode" then
    local src = debug.getinfo(1, "S").source
    local lib_dir = (src:sub(1, 1) == "@" and src:sub(2):match("(.+[\\/])")) or ""
    local dir = lib_dir:gsub("[\\/]lib[\\/]$", "/")
    local path = dir .. "live_mode.lua"
    if not reaper.file_exists(path) then
      path = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/live_mode.lua"
    end
    if reaper.file_exists(path) then dofile(path) end
    return true
  end
  return false
end

--- Mark maps dirty so the control service reloads.
function Commands.maps_changed()
  reaper.SetExtState("ReaProfessor", "maps_dirty", "1", false)
end

return Commands
