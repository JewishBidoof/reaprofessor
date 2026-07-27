-- @description ReaProfessor ExtState data helpers
-- @version 0.3.0
-- @author JewishBidoof
-- @noindex

local Data = {}

local EXT_SECTION = "ReaProfessor"
local CUES_KEY = "cues_json"
local SNAPS_KEY = "snapshots_json"
local META_KEY = "meta_json"
local MIDI_KEY = "midi_map_json"
local OSC_KEY = "osc_map_json"

-- Snapshot recall modes:
--   bypass  = only FX enable/bypass (+ mute/solo)
--   params  = bypass + parameter values (no add/remove FX)
--   full    = rebuild FX chain (delete/add by name) then apply params/bypass
Data.SNAPSHOT_MODES = { "bypass", "params", "full" }

local function json_escape(s)
  s = tostring(s or "")
  s = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r")
  return '"' .. s .. '"'
end

function Data.encode(val)
  local t = type(val)
  if t == "nil" then return "null"
  elseif t == "boolean" then return val and "true" or "false"
  elseif t == "number" then return string.format("%.14g", val)
  elseif t == "string" then return json_escape(val)
  elseif t == "table" then
    local is_array = true
    local n = 0
    for k, _ in pairs(val) do
      if type(k) ~= "number" then is_array = false break end
      if k > n then n = k end
    end
    if is_array then
      local parts = {}
      for i = 1, n do parts[i] = Data.encode(val[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      local parts = {}
      for k, v in pairs(val) do
        parts[#parts + 1] = json_escape(tostring(k)) .. ":" .. Data.encode(v)
      end
      table.sort(parts)
      return "{" .. table.concat(parts, ",") .. "}"
    end
  end
  return "null"
end

function Data.decode(str)
  if not str or str == "" then return nil end
  local pos = 1
  local function peek() return str:sub(pos, pos) end
  local function nextc() local c = peek(); pos = pos + 1; return c end
  local function skip()
    while peek():match("%s") do pos = pos + 1 end
  end
  local parse_value
  local function parse_string()
    nextc()
    local out = {}
    while true do
      local c = nextc()
      if c == "" then error("unterminated string") end
      if c == '"' then break end
      if c == "\\" then
        local e = nextc()
        if e == "n" then out[#out + 1] = "\n"
        elseif e == "r" then out[#out + 1] = "\r"
        elseif e == "t" then out[#out + 1] = "\t"
        else out[#out + 1] = e end
      else
        out[#out + 1] = c
      end
    end
    return table.concat(out)
  end
  local function parse_number()
    local start = pos
    while peek():match("[%d%+%-%.eE]") do pos = pos + 1 end
    return tonumber(str:sub(start, pos - 1))
  end
  local function parse_array()
    nextc(); skip()
    local arr = {}
    if peek() == "]" then nextc(); return arr end
    while true do
      arr[#arr + 1] = parse_value()
      skip()
      local c = peek()
      if c == "]" then nextc(); return arr end
      if c ~= "," then error("expected , in array") end
      nextc(); skip()
    end
  end
  local function parse_object()
    nextc(); skip()
    local obj = {}
    if peek() == "}" then nextc(); return obj end
    while true do
      skip()
      local key = parse_string()
      skip()
      if nextc() ~= ":" then error("expected :") end
      skip()
      obj[key] = parse_value()
      skip()
      local c = peek()
      if c == "}" then nextc(); return obj end
      if c ~= "," then error("expected , in object") end
      nextc(); skip()
    end
  end
  parse_value = function()
    skip()
    local c = peek()
    if c == '"' then return parse_string()
    elseif c == "{" then return parse_object()
    elseif c == "[" then return parse_array()
    elseif c == "t" then pos = pos + 4; return true
    elseif c == "f" then pos = pos + 5; return false
    elseif c == "n" then pos = pos + 4; return nil
    else return parse_number() end
  end
  local ok, result = pcall(parse_value)
  if not ok then return nil end
  return result
end

local function proj_ext_get(key)
  local _, val = reaper.GetProjExtState(0, EXT_SECTION, key)
  return val
end

local function proj_ext_set(key, val)
  reaper.SetProjExtState(0, EXT_SECTION, key, val or "")
end

function Data.load_cues()
  local raw = proj_ext_get(CUES_KEY)
  local cues = Data.decode(raw)
  if type(cues) ~= "table" then
    cues = {
      { id = "cue_1", name = "Top of show", kind = "snapshot", payload = { snapshot = "Default" }, notes = "" },
      { id = "cue_2", name = "Song 1", kind = "snapshot", payload = { snapshot = "Song 1" }, notes = "" },
      { id = "cue_3", name = "Song 2", kind = "snapshot", payload = { snapshot = "Song 2" }, notes = "" },
    }
  end
  return cues
end

function Data.save_cues(cues)
  proj_ext_set(CUES_KEY, Data.encode(cues))
end

function Data.load_snapshots()
  local raw = proj_ext_get(SNAPS_KEY)
  local snaps = Data.decode(raw)
  if type(snaps) ~= "table" then snaps = {} end
  return snaps
end

function Data.save_snapshots(snaps)
  proj_ext_set(SNAPS_KEY, Data.encode(snaps))
end

function Data.load_meta()
  local raw = proj_ext_get(META_KEY)
  local meta = Data.decode(raw)
  if type(meta) ~= "table" then
    meta = {
      cue_index = 1,
      live_mode = false,
      version = "0.2.0",
      snapshot_mode = "params",
      channel_mode = "same_strip",
      selected_only = false,
    }
  end
  if not meta.snapshot_mode then meta.snapshot_mode = "params" end
  if not meta.channel_mode then meta.channel_mode = "same_strip" end
  return meta
end

function Data.save_meta(meta)
  proj_ext_set(META_KEY, Data.encode(meta))
end

function Data.load_midi_map()
  local raw = proj_ext_get(MIDI_KEY)
  local map = Data.decode(raw)
  if type(map) ~= "table" then return {} end
  return map
end

function Data.save_midi_map(map)
  proj_ext_set(MIDI_KEY, Data.encode(map or {}))
end

function Data.load_osc_map()
  local raw = proj_ext_get(OSC_KEY)
  local map = Data.decode(raw)
  if type(map) ~= "table" then return {} end
  return map
end

function Data.save_osc_map(map)
  proj_ext_set(OSC_KEY, Data.encode(map or {}))
end

function Data.new_id(prefix)
  return string.format("%s_%d_%d", prefix or "id", os.time(), math.random(1000, 9999))
end

local function fx_add_name(fx_name)
  -- Prefer short name after type prefix for AddByName
  local short = tostring(fx_name or ""):gsub("^[^:]+:%s*", "")
  -- Strip trailing parenthetical vendor when present for Cockos
  return short
end

local function capture_fx(tr, fi, mode)
  local _, fx_name = reaper.TrackFX_GetFXName(tr, fi, "")
  local bypassed = reaper.TrackFX_GetEnabled(tr, fi) == false
  local entry = { name = fx_name, bypassed = bypassed }
  if mode == "bypass" then return entry end

  local params = {}
  local pc = reaper.TrackFX_GetNumParams(tr, fi)
  local limit = (mode == "full") and pc or math.min(pc, 64)
  for pi = 0, limit - 1 do
    params[#params + 1] = reaper.TrackFX_GetParam(tr, fi, pi)
  end
  entry.params = params

  if mode == "full" then
    -- Store opaque FX state when available (REAPER 6.37+)
    if reaper.TrackFX_GetNamedConfigParm then
      local ok, typ = reaper.TrackFX_GetNamedConfigParm(tr, fi, "fx_type")
      if ok then entry.fx_type = typ end
      local ok2, ident = reaper.TrackFX_GetNamedConfigParm(tr, fi, "fx_ident")
      if ok2 then entry.fx_ident = ident end
    end
  end
  return entry
end

local function iter_snapshot_tracks(selected_only)
  local Routing_ok, Routing = pcall(require, "routing")
  if Routing_ok and Routing.snapshot_target_tracks then
    return Routing.snapshot_target_tracks(selected_only)
  end
  local targets = {}
  local n = reaper.CountTracks(0)
  for i = 0, n - 1 do
    local tr = reaper.GetTrack(0, i)
    if not selected_only or reaper.IsTrackSelected(tr) then
      targets[#targets + 1] = { track = tr, index = i }
    end
  end
  return targets
end

--- Capture snapshot.
-- @param name string
-- @param opts { mode="bypass"|"params"|"full", selected_only=bool }
function Data.capture_snapshot(name, opts)
  opts = opts or {}
  local meta = Data.load_meta()
  local mode = opts.mode or meta.snapshot_mode or "params"
  local selected_only = opts.selected_only
  if selected_only == nil then selected_only = meta.selected_only end

  local tracks = {}
  for _, target in ipairs(iter_snapshot_tracks(selected_only)) do
    local tr = target.track
    local _, tname = reaper.GetTrackName(tr)
    local fx_list = {}
    local fx_count = reaper.TrackFX_GetCount(tr)
    for fi = 0, fx_count - 1 do
      fx_list[#fx_list + 1] = capture_fx(tr, fi, mode)
    end
    tracks[#tracks + 1] = {
      name = tname,
      guid = reaper.GetTrackGUID(tr),
      role = target.role,
      mute = reaper.GetMediaTrackInfo_Value(tr, "B_MUTE") > 0,
      solo = reaper.GetMediaTrackInfo_Value(tr, "I_SOLO") > 0,
      fx = fx_list,
    }
  end

  return {
    id = Data.new_id("snap"),
    name = name or ("Snapshot " .. os.date("%H:%M:%S")),
    created = os.time(),
    mode = mode,
    selected_only = selected_only and true or false,
    tracks = tracks,
  }
end

local function apply_bypass_and_params(tr, fi, fx, mode)
  if fx.bypassed ~= nil then
    reaper.TrackFX_SetEnabled(tr, fi, not fx.bypassed)
  end
  if mode ~= "bypass" and type(fx.params) == "table" then
    for pi = 1, #fx.params do
      reaper.TrackFX_SetParam(tr, fi, pi - 1, fx.params[pi])
    end
  end
end

local function recall_track_bypass_or_params(tr, src, mode)
  if src.mute ~= nil then
    reaper.SetMediaTrackInfo_Value(tr, "B_MUTE", src.mute and 1 or 0)
  end
  if src.solo ~= nil then
    reaper.SetMediaTrackInfo_Value(tr, "I_SOLO", src.solo and 1 or 0)
  end
  if type(src.fx) ~= "table" then return end
  local fx_count = reaper.TrackFX_GetCount(tr)
  for fi = 1, math.min(#src.fx, fx_count) do
    apply_bypass_and_params(tr, fi - 1, src.fx[fi], mode)
  end
end

local function recall_track_full(tr, src)
  if src.mute ~= nil then
    reaper.SetMediaTrackInfo_Value(tr, "B_MUTE", src.mute and 1 or 0)
  end
  if src.solo ~= nil then
    reaper.SetMediaTrackInfo_Value(tr, "I_SOLO", src.solo and 1 or 0)
  end
  -- Remove existing FX then rebuild
  for i = reaper.TrackFX_GetCount(tr) - 1, 0, -1 do
    reaper.TrackFX_Delete(tr, i)
  end
  if type(src.fx) ~= "table" then return end
  for _, fx in ipairs(src.fx) do
    local add_name = fx.fx_ident or fx_add_name(fx.name)
    local idx = reaper.TrackFX_AddByName(tr, add_name, false, -1)
    if idx < 0 then
      -- fallback to full displayed name
      idx = reaper.TrackFX_AddByName(tr, fx.name or "", false, -1)
    end
    if idx >= 0 then
      apply_bypass_and_params(tr, idx, fx, "full")
    end
  end
end

local function find_track_for_src(src, used)
  if src.guid and reaper.BR_GetMediaTrackByGUID then
    local tr = reaper.BR_GetMediaTrackByGUID(0, src.guid)
    if tr then return tr end
  end
  if src.guid then
    local n = reaper.CountTracks(0)
    for i = 0, n - 1 do
      local tr = reaper.GetTrack(0, i)
      if reaper.GetTrackGUID(tr) == src.guid and not used[tr] then return tr end
    end
  end
  if src.name then
    local n = reaper.CountTracks(0)
    for i = 0, n - 1 do
      local tr = reaper.GetTrack(0, i)
      if used[tr] then goto continue end
      local _, name = reaper.GetTrackName(tr)
      if name == src.name then return tr end
      ::continue::
    end
  end
  return nil
end

--- Recall snapshot.
-- @param snap table
-- @param opts { mode=override, selected_only=bool }
function Data.recall_snapshot(snap, opts)
  if not snap or type(snap.tracks) ~= "table" then return false end
  opts = opts or {}
  local meta = Data.load_meta()
  local mode = opts.mode or snap.mode or meta.snapshot_mode or "params"
  local selected_only = opts.selected_only
  if selected_only == nil then selected_only = snap.selected_only end

  reaper.Undo_BeginBlock2(0)
  local used = {}
  local targets = iter_snapshot_tracks(selected_only)
  local positional = 1

  local function apply(tr, src)
    local _, role = reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:ReaProfessor_role", "", false)
    if role == "record" then return end
    if selected_only and not reaper.IsTrackSelected(tr) then return end
    used[tr] = true
    if mode == "full" then
      recall_track_full(tr, src)
    else
      recall_track_bypass_or_params(tr, src, mode)
    end
  end

  for _, src in ipairs(snap.tracks) do
    local tr = find_track_for_src(src, used)
    if not tr then
      while positional <= #targets and used[targets[positional].track] do
        positional = positional + 1
      end
      if positional <= #targets then
        tr = targets[positional].track
        positional = positional + 1
      end
    end
    if tr then apply(tr, src) end
  end

  reaper.Undo_EndBlock2(0, string.format("ReaProfessor: Recall snapshot '%s' (%s)", tostring(snap.name), mode), -1)
  return true
end

return Data
