-- @description ReaProfessor central command handlers
-- @version 0.3.9
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
  if key == nil or key == "" then return nil, nil end
  if type(key) == "number" then
    return snaps[key], key
  end
  local as_num = tonumber(key)
  if as_num and snaps[as_num] then return snaps[as_num], as_num end
  local want = tostring(key)
  local want_l = want:lower()
  for i, s in ipairs(snaps) do
    if s.name == want then return s, i end
  end
  for i, s in ipairs(snaps) do
    if type(s.name) == "string" and s.name:lower() == want_l then return s, i end
  end
  return nil, nil
end

--- Fire one cue. Returns ok, status_message.
-- LP2 model: a cue is a container; all actions fire (fire_all) or just the first.
local function fire_action(act, snaps)
  if not act then return false, "No action" end
  local Data = require("data")
  if act.kind == "snapshot" then
    local key = act.snapshot or act.label
    local snap = select(1, find_snapshot(snaps, key))
    if not snap then
      return false, string.format("Missing snapshot '%s' — capture one or re-link this cue", tostring(key or "?"))
    end
    Data.recall_snapshot(snap)
    local meta = Data.load_meta()
    meta.last_snapshot = snap.name
    Data.save_meta(meta)
    return true, "Snapshot " .. tostring(snap.name)
  elseif act.kind == "action" then
    local cmd = act.command_id
    if not cmd then return false, "Action has no command id" end
    local id = reaper.NamedCommandLookup(tostring(cmd))
    if id == 0 then id = tonumber(cmd) or 0 end
    if id == 0 then return false, "Unknown action " .. tostring(cmd) end
    reaper.Main_OnCommand(id, 0)
    return true, "Action " .. tostring(cmd)
  elseif act.kind == "midi" then
    -- Soft MIDI out via StuffMIDIMessage when available (channel 0-15)
    local ch = (tonumber(act.channel) or 1) - 1
    if ch < 0 then ch = 0 end
    if ch > 15 then ch = 15 end
    local note = tonumber(act.note) or 36
    local vel = tonumber(act.velocity) or 100
    local status = 0x90 + ch
    if act.type == "cc" then
      status = 0xB0 + ch
      note = tonumber(act.cc) or note
    elseif act.type == "note_off" then
      status = 0x80 + ch
    end
    if reaper.StuffMIDIMessage then
      reaper.StuffMIDIMessage(0, status, note, vel)
      return true, "MIDI"
    end
    return false, "StuffMIDIMessage unavailable"
  elseif act.kind == "comment" then
    return true, act.label or "Comment"
  end
  return false, "Unknown action kind: " .. tostring(act.kind)
end

local function fire_cue(cue, snaps)
  if not cue then return false, "No cue" end
  local Data = require("data")
  cue = Data.normalize_cue(cue)

  -- Optional pre-wait (blocking sleep kept short; long waits use defer in UI later)
  local pre = tonumber(cue.pre_wait_ms) or 0
  if pre > 0 and pre <= 2000 then
    local t0 = reaper.time_precise()
    while (reaper.time_precise() - t0) * 1000 < pre do end
  end

  local actions = cue.actions or {}
  if #actions == 0 then
    return false, "Cue has no actions — add a Snapshot action"
  end

  local msgs = {}
  local any_ok = false
  local limit = cue.fire_all == false and 1 or #actions
  for i = 1, limit do
    local ok, msg = fire_action(actions[i], snaps)
    if ok then any_ok = true end
    msgs[#msgs + 1] = msg
    if not ok and cue.fire_all ~= false then
      -- continue firing remaining actions (LP fires all; report failures)
    end
  end

  local post = tonumber(cue.post_wait_ms) or 0
  if post > 0 and post <= 2000 then
    local t0 = reaper.time_precise()
    while (reaper.time_precise() - t0) * 1000 < post do end
  end

  if not any_ok then
    return false, table.concat(msgs, "; ")
  end
  return true, table.concat(msgs, " · ")
end

--- After recalling a snapshot, optionally fire a linked cue (LP "Fire cue").
function Commands.snap_fire_linked_cue(snap)
  if not snap or not snap.fire_cue or snap.fire_cue == "" then return true, nil end
  local Data = require("data")
  local cues = Data.load_cues()
  local snaps = Data.load_snapshots()
  local idx = tonumber(snap.fire_cue)
  local cue = nil
  if idx and cues[idx] then
    cue = cues[idx]
  else
    for _, c in ipairs(cues) do
      if c.name == snap.fire_cue then cue = c break end
    end
  end
  if not cue then return false, "Linked cue missing: " .. tostring(snap.fire_cue) end
  return fire_cue(cue, snaps)
end

--- Block show/project mutations until Config.FINALIZED (smoke may flip the flag).
local function require_actions(name)
  local Config = require("config")
  return Config.require_enabled(name)
end

function Commands.cue_go()
  if not require_actions("Cue GO") then return false, "disabled" end
  local Data = require("data")
  local cues = Data.load_cues()
  local meta = Data.load_meta()
  local snaps = Data.load_snapshots()
  if #cues == 0 then return false, "Cue list is empty — use + CUE to capture" end
  local idx = meta.cue_index or 1
  if idx < 1 then idx = 1 end
  if idx > #cues then idx = #cues end
  local ok, msg = fire_cue(cues[idx], snaps)
  meta.cue_index = math.min(#cues, idx + 1)
  Data.save_meta(meta)
  return ok, msg
end

function Commands.cue_back()
  if not require_actions("Cue Back") then return false, "disabled" end
  local Data = require("data")
  local cues = Data.load_cues()
  local meta = Data.load_meta()
  local snaps = Data.load_snapshots()
  if #cues == 0 then return false, "Cue list is empty" end
  local idx = math.max(1, (meta.cue_index or 1) - 1)
  local ok, msg = fire_cue(cues[idx], snaps)
  meta.cue_index = idx
  Data.save_meta(meta)
  return ok, msg
end

function Commands.cue_goto(n)
  if not require_actions("Cue Fire") then return false, "disabled" end
  local Data = require("data")
  local cues = Data.load_cues()
  local meta = Data.load_meta()
  local snaps = Data.load_snapshots()
  local idx = tonumber(n) or 1
  if idx < 1 or idx > #cues then return false, "Cue index out of range" end
  local ok, msg = fire_cue(cues[idx], snaps)
  meta.cue_index = idx
  Data.save_meta(meta)
  return ok, msg
end

function Commands.snap_recall(key)
  if not require_actions("Snapshot Recall") then return false end
  local Data = require("data")
  local snaps = Data.load_snapshots()
  local snap = select(1, find_snapshot(snaps, key))
  if not snap then return false end
  local ok = Data.recall_snapshot(snap)
  if ok then
    local meta = Data.load_meta()
    meta.last_snapshot = snap.name
    Data.save_meta(meta)
    Commands.snap_fire_linked_cue(snap)
  end
  return ok
end

function Commands.set_snapshot_mode(mode)
  if not require_actions("Snapshot mode") then return false end
  local Data = require("data")
  local meta = Data.load_meta()
  mode = tostring(mode or "")
  if mode ~= "bypass" and mode ~= "params" and mode ~= "full" then return false end
  meta.snapshot_mode = mode
  Data.save_meta(meta)
  return true
end

function Commands.set_channel_mode(mode)
  if not require_actions("Channel mode") then return false end
  local Data = require("data")
  local meta = Data.load_meta()
  mode = tostring(mode or "")
  if mode ~= "same_strip" and mode ~= "double_patch" then return false end
  meta.channel_mode = mode
  Data.save_meta(meta)
  return true
end

function Commands.create_channels(count, mode)
  if not require_actions("Create Channels") then return false end
  local Data, _, Routing = load_deps()
  local meta = Data.load_meta()
  mode = mode or meta.channel_mode or "same_strip"
  count = tonumber(count) or 16
  return Routing.create_channels(count, { mode = mode })
end

function Commands.apply_record_safe(mode)
  if not require_actions("Apply record-safe") then return false end
  local Data, _, Routing = load_deps()
  local meta = Data.load_meta()
  Routing.apply_record_safe(mode or meta.channel_mode)
  return true
end

function Commands.run_named(command, arg)
  if not require_actions(command or "Command") then return false end
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
