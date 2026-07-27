-- @description ReaProfessor ExtState data helpers
-- @version 0.1.0
-- @author ReaProfessor

local Data = {}

local EXT_SECTION = "ReaProfessor"
local CUES_KEY = "cues_json"
local SNAPS_KEY = "snapshots_json"
local META_KEY = "meta_json"

local function json_escape(s)
  s = tostring(s or "")
  s = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r")
  return '"' .. s .. '"'
end

-- Minimal JSON encode/decode for our small schema (no external deps).
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
    nextc() -- "
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
    nextc() -- [
    skip()
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
    nextc() -- {
    skip()
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
    meta = { cue_index = 1, live_mode = false, version = "0.1.0" }
  end
  return meta
end

function Data.save_meta(meta)
  proj_ext_set(META_KEY, Data.encode(meta))
end

function Data.new_id(prefix)
  return string.format("%s_%d_%d", prefix or "id", os.time(), math.random(1000, 9999))
end

--- Capture FX bypass + selected params for all tracks (lightweight snapshot).
function Data.capture_snapshot(name)
  local tracks = {}
  local track_count = reaper.CountTracks(0)
  for ti = 0, track_count - 1 do
    local tr = reaper.GetTrack(0, ti)
    local _, tname = reaper.GetTrackName(tr)
    local fx_count = reaper.TrackFX_GetCount(tr)
    local fx_list = {}
    for fi = 0, fx_count - 1 do
      local _, fx_name = reaper.TrackFX_GetFXName(tr, fi, "")
      local bypassed = reaper.TrackFX_GetEnabled(tr, fi) == false
      local params = {}
      local pc = reaper.TrackFX_GetNumParams(tr, fi)
      -- Cap params to keep ExtState reasonable during prototyping
      local limit = math.min(pc, 32)
      for pi = 0, limit - 1 do
        params[#params + 1] = reaper.TrackFX_GetParam(tr, fi, pi)
      end
      fx_list[#fx_list + 1] = {
        name = fx_name,
        bypassed = bypassed,
        params = params,
      }
    end
    tracks[#tracks + 1] = {
      name = tname,
      mute = reaper.GetMediaTrackInfo_Value(tr, "B_MUTE") > 0,
      solo = reaper.GetMediaTrackInfo_Value(tr, "I_SOLO") > 0,
      fx = fx_list,
    }
  end
  return {
    id = Data.new_id("snap"),
    name = name or ("Snapshot " .. os.date("%H:%M:%S")),
    created = os.time(),
    tracks = tracks,
  }
end

function Data.recall_snapshot(snap)
  if not snap or type(snap.tracks) ~= "table" then return false end
  reaper.Undo_BeginBlock2(0)
  local track_count = reaper.CountTracks(0)
  for ti = 1, math.min(#snap.tracks, track_count) do
    local tr = reaper.GetTrack(0, ti - 1)
    local src = snap.tracks[ti]
    if src.mute ~= nil then
      reaper.SetMediaTrackInfo_Value(tr, "B_MUTE", src.mute and 1 or 0)
    end
    if src.solo ~= nil then
      reaper.SetMediaTrackInfo_Value(tr, "I_SOLO", src.solo and 1 or 0)
    end
    if type(src.fx) == "table" then
      local fx_count = reaper.TrackFX_GetCount(tr)
      for fi = 1, math.min(#src.fx, fx_count) do
        local fx = src.fx[fi]
        if fx.bypassed ~= nil then
          reaper.TrackFX_SetEnabled(tr, fi - 1, not fx.bypassed)
        end
        if type(fx.params) == "table" then
          for pi = 1, #fx.params do
            reaper.TrackFX_SetParam(tr, fi - 1, pi - 1, fx.params[pi])
          end
        end
      end
    end
  end
  reaper.Undo_EndBlock2(0, "ReaProfessor: Recall snapshot " .. tostring(snap.name), -1)
  return true
end

return Data
