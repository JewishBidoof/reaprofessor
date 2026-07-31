-- @description ReaProfessor ExtState data helpers
-- @version 0.5.0
-- @author JewishBidoof
-- @noindex

local Data = {}

local EXT_SECTION = "ReaProfessor"
local CUES_KEY = "cues_json"
local SNAPS_KEY = "snapshots_json"
local META_KEY = "meta_json"
local MIDI_KEY = "midi_map_json"
local OSC_KEY = "osc_map_json"

-- Snapshot recall modes (stored preference / recall filter):
--   bypass  = only FX enable/bypass (+ mute/solo)
--   params  = bypass + normalized parameter values (matched by FX identity);
--             auto-upgrades to full rebuild when the chain no longer matches
--   full    = restore exact FXCHAIN chunk (fallback: rebuild by name + params)
-- Capture always stores full FXCHAIN + params so recall cannot lose data.
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
    cues = {}
  end
  for i = 1, #cues do
    cues[i] = Data.normalize_cue(cues[i])
  end
  return cues
end

function Data.save_cues(cues)
  proj_ext_set(CUES_KEY, Data.encode(cues))
end

--- Normalize a cue.
-- Simplified model: each cue recalls one processing snapshot (+ optional MIDI/OSC).
-- kind = "cue" (recall) | "dummy" (MIDI/OSC only). Legacy nested actions are migrated.
function Data.normalize_cue(cue)
  if type(cue) ~= "table" then
    cue = { name = "Cue" }
  end
  cue.id = cue.id or Data.new_id("cue")
  cue.name = cue.name or "Cue"

  -- Migrate legacy nested-action cues → snapshot_name + midi/osc fields.
  if (not cue.snapshot_name or cue.snapshot_name == "") and type(cue.actions) == "table" then
    for _, a in ipairs(cue.actions) do
      if a.kind == "snapshot" then
        cue.snapshot_name = a.snapshot or a.label
        break
      end
    end
    if not cue.snapshot_name and cue.payload and cue.payload.snapshot then
      cue.snapshot_name = cue.payload.snapshot
    end
    if not cue.midi then
      for _, a in ipairs(cue.actions) do
        if a.kind == "midi" then
          cue.midi = {
            type = a.type or "note_on",
            channel = a.channel,
            note = a.note,
            cc = a.cc,
            velocity = a.velocity or 100,
          }
          break
        end
      end
    end
  end
  if cue.payload and cue.payload.snapshot and (not cue.snapshot_name or cue.snapshot_name == "") then
    cue.snapshot_name = cue.payload.snapshot
  end

  if cue.kind == "group" or cue.kind == "snapshot" or cue.kind == "action" or not cue.kind or cue.kind == "" then
    cue.kind = "cue"
  end
  if cue.kind ~= "dummy" then cue.kind = "cue" end

  cue.osc = cue.osc or "" -- empty → default {parent}/{cue#}
  cue.send_on_fire = cue.send_on_fire and true or false
  if type(cue.midi) ~= "table" then cue.midi = nil end
  return cue
end

--- Create a cue. Capture snapshot separately via Data.capture_snapshot + assign snapshot_name.
function Data.new_cue(name, opts)
  opts = opts or {}
  return Data.normalize_cue({
    id = Data.new_id("cue"),
    name = name or "Cue",
    kind = opts.kind or "cue",
    snapshot_name = opts.snapshot_name or "",
    osc = opts.osc or "",
    midi = opts.midi,
    send_on_fire = opts.send_on_fire and true or false,
  })
end

--- Default OSC path for cue index (1-based): {parent}/{n}
function Data.default_cue_osc(meta, index)
  meta = meta or Data.load_meta()
  local parent = tostring(meta.osc_parent or "/ReaProfessor"):gsub("/+$", "")
  if parent == "" then parent = "/ReaProfessor" end
  return string.format("%s/%d", parent, tonumber(index) or 1)
end

function Data.cue_osc_path(cue, index, meta)
  cue = Data.normalize_cue(cue or {})
  if cue.osc and cue.osc ~= "" then
    local path = tostring(cue.osc)
    if path:sub(1, 1) ~= "/" then
      local parent = tostring((meta or Data.load_meta()).osc_parent or "/ReaProfessor"):gsub("/+$", "")
      path = parent .. "/" .. path:gsub("^/+", "")
    end
    return path
  end
  return Data.default_cue_osc(meta, index)
end

function Data.format_ms(ms)
  ms = tonumber(ms) or 0
  if ms < 0 then ms = 0 end
  local total_cs = math.floor(ms / 10 + 0.5) -- centiseconds
  local cs = total_cs % 100
  local total_s = math.floor(total_cs / 100)
  local s = total_s % 60
  local m = math.floor(total_s / 60) % 60
  local h = math.floor(total_s / 3600)
  if h > 0 then
    return string.format("%02d:%02d:%02d:%02d", h, m, s, cs)
  end
  return string.format("%02d:%02d:%02d", m, s, cs)
end

function Data.parse_time_input(str)
  if not str or str == "" then return 0 end
  str = tostring(str):match("^%s*(.-)%s*$")
  -- plain milliseconds
  if str:match("^%d+$") then return tonumber(str) or 0 end
  local parts = {}
  for p in str:gmatch("%d+") do parts[#parts + 1] = tonumber(p) or 0 end
  if #parts == 1 then return parts[1] end -- treat as ms
  if #parts == 2 then -- mm:ss
    return (parts[1] * 60 + parts[2]) * 1000
  end
  if #parts == 3 then -- mm:ss:cs
    return (parts[1] * 60 + parts[2]) * 1000 + parts[3] * 10
  end
  if #parts >= 4 then -- hh:mm:ss:cs
    return ((parts[1] * 3600 + parts[2] * 60 + parts[3]) * 1000) + parts[4] * 10
  end
  return 0
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
    meta = {}
  end
  if meta.cue_index == nil then meta.cue_index = 1 end
  if meta.live_mode == nil then meta.live_mode = false end
  if not meta.version then meta.version = "0.5.0" end
  if not meta.snapshot_mode then meta.snapshot_mode = "full" end
  if not meta.channel_mode then meta.channel_mode = "same_strip" end
  if meta.selected_only == nil then meta.selected_only = false end
  if not meta.last_snapshot then meta.last_snapshot = "" end
  -- OSC parent prefix; cue default path = {parent}/{cue number}
  if not meta.osc_parent or meta.osc_parent == "" then
    meta.osc_parent = "/ReaProfessor"
  end
  -- Global MIDI listen channel: 0 = omni, 1–16 = filter
  meta.midi_channel = tonumber(meta.midi_channel) or 0
  if meta.midi_channel < 0 then meta.midi_channel = 0 end
  if meta.midi_channel > 16 then meta.midi_channel = 16 end
  if type(meta.transport) ~= "table" then meta.transport = {} end
  for _, key in ipairs({ "go", "back", "fire" }) do
    if type(meta.transport[key]) ~= "table" then
      meta.transport[key] = { midi = nil, osc = "" }
    else
      meta.transport[key].osc = meta.transport[key].osc or ""
    end
  end
  if meta.edit_mode == nil then meta.edit_mode = false end
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

--- Extract a REAPER state-chunk block like <FXCHAIN ... > (nested <> aware).
-- Depth starts at 1 for the opening tag itself. Starting at 0 incorrectly
-- closes on the first nested plugin's trailing '>' and truncates the chain.
local function extract_chunk_block(chunk, tag)
  if not chunk or not tag then return nil end
  local open = "<" .. tag
  local start = 1
  while true do
    start = chunk:find(open, start, true)
    if not start then return nil end
    -- Require a real tag boundary: "<TAG" then whitespace/newline/CR (not "<TAGFOO").
    local after = start + #open
    local ch = chunk:sub(after, after)
    if ch == "" or ch:match("[%s\r\n]") then
      break
    end
    start = after
  end
  -- Already inside the opening '<' of this block.
  local depth = 1
  local i = start + 1
  while i <= #chunk do
    local c = chunk:sub(i, i)
    if c == "<" then
      depth = depth + 1
    elseif c == ">" then
      depth = depth - 1
      if depth == 0 then
        return chunk:sub(start, i)
      end
    end
    i = i + 1
  end
  return nil
end

local function replace_chunk_block(chunk, tag, new_block)
  local old = extract_chunk_block(chunk, tag)
  if old and new_block and new_block ~= "" then
    local s, e = chunk:find(old, 1, true)
    if s then
      return chunk:sub(1, s - 1) .. new_block .. chunk:sub(e + 1), true
    end
  end
  if (not old) and new_block and new_block ~= "" then
    -- Insert before the track's final closing '>'
    local pos = chunk:find("\n>\n%s*$") or chunk:find("\n>$")
    if pos then
      return chunk:sub(1, pos) .. new_block .. "\n" .. chunk:sub(pos + 1), true
    end
  end
  if new_block == nil or new_block == "" then
    if old then
      local s, e = chunk:find(old, 1, true)
      if s then return chunk:sub(1, s - 1) .. chunk:sub(e + 1), true end
    end
  end
  return chunk, false
end

-- Exported for harnesses / diagnostics.
function Data.extract_chunk_block(chunk, tag)
  return extract_chunk_block(chunk, tag)
end

function Data.replace_chunk_block(chunk, tag, new_block)
  return replace_chunk_block(chunk, tag, new_block)
end

local function get_param(tr, fi, pi)
  if reaper.TrackFX_GetParamNormalized then
    return reaper.TrackFX_GetParamNormalized(tr, fi, pi)
  end
  return reaper.TrackFX_GetParam(tr, fi, pi)
end

local function set_param(tr, fi, pi, value)
  if value == nil then return end
  if reaper.TrackFX_SetParamNormalized then
    reaper.TrackFX_SetParamNormalized(tr, fi, pi, value)
  else
    reaper.TrackFX_SetParam(tr, fi, pi, value)
  end
end

local function fx_add_candidates(fx)
  local list = {}
  local function push(v)
    if v and v ~= "" then list[#list + 1] = v end
  end
  local typ = fx.fx_type or ""
  local ident = fx.fx_ident or ""
  if typ == "JS" or typ:find("JS", 1, true) == 1 then
    push("JS:" .. ident)
    push("JS: " .. ident)
    push(ident)
  end
  push(ident)
  push(fx.name)
  if fx.name then
    push(fx.name:gsub("^[^:]+:%s*", ""))
  end
  return list
end

local function capture_fx(tr, fi, _mode)
  -- Always capture full FX identity + params; mode is a recall filter only.
  local _, fx_name = reaper.TrackFX_GetFXName(tr, fi, "")
  local bypassed = reaper.TrackFX_GetEnabled(tr, fi) == false
  local offline = false
  if reaper.TrackFX_GetOffline then
    offline = reaper.TrackFX_GetOffline(tr, fi) and true or false
  end
  local entry = {
    name = fx_name,
    bypassed = bypassed,
    offline = offline,
    params_normalized = true,
  }
  if reaper.TrackFX_GetNamedConfigParm then
    local ok, typ = reaper.TrackFX_GetNamedConfigParm(tr, fi, "fx_type")
    if ok then entry.fx_type = typ end
    local ok2, ident = reaper.TrackFX_GetNamedConfigParm(tr, fi, "fx_ident")
    if ok2 then entry.fx_ident = ident end
  end

  local params = {}
  local pc = reaper.TrackFX_GetNumParams(tr, fi)
  for pi = 0, pc - 1 do
    params[#params + 1] = get_param(tr, fi, pi)
  end
  entry.params = params
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

local function track_guid(tr)
  if not tr then return nil end
  return reaper.GetTrackGUID(tr)
end

--- Capture track→track sends (sidechain / MIDI routing). Does not touch HW outs or record.
local function capture_sends(tr)
  local sends = {}
  local n = reaper.GetTrackNumSends(tr, 0) or 0
  for i = 0, n - 1 do
    local dest = nil
    if reaper.GetTrackSendInfo_Value then
      dest = reaper.GetTrackSendInfo_Value(tr, 0, i, "P_DESTTRACK")
    end
    if (not dest or dest == 0) and reaper.BR_GetMediaTrackSendInfo_Track then
      dest = reaper.BR_GetMediaTrackSendInfo_Track(tr, 0, i, false)
    end
    local dest_guid = track_guid(dest)
    if dest_guid then
      sends[#sends + 1] = {
        dest_guid = dest_guid,
        vol = reaper.GetTrackSendInfo_Value(tr, 0, i, "D_VOL") or 1,
        pan = reaper.GetTrackSendInfo_Value(tr, 0, i, "D_PAN") or 0,
        mute = (reaper.GetTrackSendInfo_Value(tr, 0, i, "B_MUTE") or 0) > 0,
        mode = reaper.GetTrackSendInfo_Value(tr, 0, i, "I_SENDMODE") or 0,
        src_chan = reaper.GetTrackSendInfo_Value(tr, 0, i, "I_SRCCHAN") or 0,
        dst_chan = reaper.GetTrackSendInfo_Value(tr, 0, i, "I_DSTCHAN") or 0,
        midiflags = reaper.GetTrackSendInfo_Value(tr, 0, i, "I_MIDIFLAGS") or 0,
      }
    end
  end
  return sends
end

local function find_track_by_guid(guid)
  if not guid or guid == "" then return nil end
  if reaper.BR_GetMediaTrackByGUID then
    local tr = reaper.BR_GetMediaTrackByGUID(0, guid)
    if tr then return tr end
  end
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if reaper.GetTrackGUID(tr) == guid then return tr end
  end
  return nil
end

local function recall_sends(tr, sends)
  if type(sends) ~= "table" then return end
  -- Remove existing track sends, then recreate from snapshot.
  for i = (reaper.GetTrackNumSends(tr, 0) or 0) - 1, 0, -1 do
    reaper.RemoveTrackSend(tr, 0, i)
  end
  for _, s in ipairs(sends) do
    local dest = find_track_by_guid(s.dest_guid)
    if dest and reaper.CreateTrackSend then
      local idx = reaper.CreateTrackSend(tr, dest)
      if idx >= 0 then
        if s.vol ~= nil then reaper.SetTrackSendInfo_Value(tr, 0, idx, "D_VOL", s.vol) end
        if s.pan ~= nil then reaper.SetTrackSendInfo_Value(tr, 0, idx, "D_PAN", s.pan) end
        if s.mute ~= nil then reaper.SetTrackSendInfo_Value(tr, 0, idx, "B_MUTE", s.mute and 1 or 0) end
        if s.mode ~= nil then reaper.SetTrackSendInfo_Value(tr, 0, idx, "I_SENDMODE", s.mode) end
        if s.src_chan ~= nil then reaper.SetTrackSendInfo_Value(tr, 0, idx, "I_SRCCHAN", s.src_chan) end
        if s.dst_chan ~= nil then reaper.SetTrackSendInfo_Value(tr, 0, idx, "I_DSTCHAN", s.dst_chan) end
        if s.midiflags ~= nil then reaper.SetTrackSendInfo_Value(tr, 0, idx, "I_MIDIFLAGS", s.midiflags) end
      end
    end
  end
end

--- Capture snapshot.
-- Always stores FXCHAIN + normalized params + track sends (sidechain/MIDI routing).
-- Does not capture record-arm / input / items. `mode` is the preferred recall filter.
-- @param name string
-- @param opts { mode="bypass"|"params"|"full", selected_only=bool }
function Data.capture_snapshot(name, opts)
  opts = opts or {}
  local meta = Data.load_meta()
  local mode = opts.mode or meta.snapshot_mode or "full"
  local selected_only = opts.selected_only
  if selected_only == nil then selected_only = meta.selected_only end
  -- Nothing selected with selected_only → capture all eligible (avoid empty snap).
  if selected_only then
    local any = false
    for i = 0, reaper.CountTracks(0) - 1 do
      if reaper.IsTrackSelected(reaper.GetTrack(0, i)) then any = true break end
    end
    if not any then selected_only = false end
  end

  local tracks = {}
  for _, target in ipairs(iter_snapshot_tracks(selected_only)) do
    local tr = target.track
    local _, tname = reaper.GetTrackName(tr)
    local fx_list = {}
    local fx_count = reaper.TrackFX_GetCount(tr)
    for fi = 0, fx_count - 1 do
      fx_list[#fx_list + 1] = capture_fx(tr, fi, mode)
    end
    local row = {
      name = tname,
      guid = reaper.GetTrackGUID(tr),
      role = target.role,
      mute = reaper.GetMediaTrackInfo_Value(tr, "B_MUTE") > 0,
      solo = reaper.GetMediaTrackInfo_Value(tr, "I_SOLO") > 0,
      fx = fx_list,
      sends = capture_sends(tr),
    }
    -- Always store exact FXCHAIN so recall can rebuild even if filter is params/bypass.
    local ok, chunk = reaper.GetTrackStateChunk(tr, "", false)
    if ok and chunk then
      row.fxchain = extract_chunk_block(chunk, "FXCHAIN")
    end
    tracks[#tracks + 1] = row
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
  if fx.offline ~= nil and reaper.TrackFX_SetOffline then
    reaper.TrackFX_SetOffline(tr, fi, fx.offline and true or false)
  end
  if fx.bypassed ~= nil then
    reaper.TrackFX_SetEnabled(tr, fi, not fx.bypassed)
  end
  if mode == "bypass" then return end
  if type(fx.params) ~= "table" then return end

  local use_norm = fx.params_normalized
  if use_norm == nil then
    -- Legacy snapshots: detect likely-normalized values (all within 0..1).
    use_norm = true
    for i = 1, #fx.params do
      local v = fx.params[i]
      if type(v) == "number" and (v < -0.001 or v > 1.001) then
        use_norm = false
        break
      end
    end
  end

  for pi = 1, #fx.params do
    local v = fx.params[pi]
    if use_norm then
      set_param(tr, fi, pi - 1, v)
    else
      -- Legacy raw values captured with TrackFX_GetParam on JSFX
      reaper.TrackFX_SetParam(tr, fi, pi - 1, v)
    end
  end
end

local function fx_identity_key(fx)
  if not fx then return "" end
  if fx.fx_ident and fx.fx_ident ~= "" then return tostring(fx.fx_ident):lower() end
  return tostring(fx.name or ""):gsub("^[^:]+:%s*", ""):lower()
end

local function live_fx_key(tr, fi)
  local _, name = reaper.TrackFX_GetFXName(tr, fi, "")
  local ident = ""
  if reaper.TrackFX_GetNamedConfigParm then
    local ok, id = reaper.TrackFX_GetNamedConfigParm(tr, fi, "fx_ident")
    if ok then ident = id end
  end
  if ident ~= "" then return ident:lower() end
  return name:gsub("^[^:]+:%s*", ""):lower()
end

--- True when track FX order/identity no longer matches the snapshot (needs rebuild).
local function needs_chain_rebuild(tr, src)
  if type(src.fx) ~= "table" then return false end
  local live_n = reaper.TrackFX_GetCount(tr)
  if live_n ~= #src.fx then return true end
  for si = 1, #src.fx do
    if live_fx_key(tr, si - 1) ~= fx_identity_key(src.fx[si]) then
      return true
    end
  end
  return false
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
  local used = {}
  for si = 1, #src.fx do
    local want = src.fx[si]
    local want_key = fx_identity_key(want)
    local matched = nil
    -- Prefer identity match over positional (survives reorder)
    for fi = 0, fx_count - 1 do
      if not used[fi] then
        if live_fx_key(tr, fi) == want_key then
          matched = fi
          break
        end
      end
    end
    if matched == nil and (si - 1) < fx_count and not used[si - 1] then
      matched = si - 1 -- positional fallback
    end
    if matched ~= nil then
      used[matched] = true
      apply_bypass_and_params(tr, matched, want, mode)
    end
  end
end

local function recall_track_full_by_add(tr, src)
  for i = reaper.TrackFX_GetCount(tr) - 1, 0, -1 do
    reaper.TrackFX_Delete(tr, i)
  end
  if type(src.fx) ~= "table" then return end
  for _, fx in ipairs(src.fx) do
    local idx = -1
    for _, name in ipairs(fx_add_candidates(fx)) do
      idx = reaper.TrackFX_AddByName(tr, name, false, -1)
      if idx >= 0 then break end
    end
    if idx >= 0 then
      apply_bypass_and_params(tr, idx, fx, "full")
    else
      reaper.ShowConsoleMsg("[ReaProfessor] Full recall: could not add FX '" .. tostring(fx.name or fx.fx_ident) .. "'\n")
    end
  end
end

local function recall_track_full(tr, src)
  if src.mute ~= nil then
    reaper.SetMediaTrackInfo_Value(tr, "B_MUTE", src.mute and 1 or 0)
  end
  if src.solo ~= nil then
    reaper.SetMediaTrackInfo_Value(tr, "I_SOLO", src.solo and 1 or 0)
  end

  -- Prefer exact FXCHAIN chunk restore (handles JSFX raw sliders, order, bypass).
  if type(src.fxchain) == "string" and src.fxchain:find("<FXCHAIN", 1, true) then
    local want_count = type(src.fx) == "table" and #src.fx or nil
    -- Clear existing FX first so a failed/partial chunk write cannot leave orphans.
    for i = reaper.TrackFX_GetCount(tr) - 1, 0, -1 do
      reaper.TrackFX_Delete(tr, i)
    end
    local ok, chunk = reaper.GetTrackStateChunk(tr, "", false)
    if ok and chunk then
      local new_chunk, replaced = replace_chunk_block(chunk, "FXCHAIN", src.fxchain)
      if replaced and reaper.SetTrackStateChunk(tr, new_chunk, false) then
        local got = reaper.TrackFX_GetCount(tr)
        if want_count == nil or got == want_count then
          return
        end
        reaper.ShowConsoleMsg(string.format(
          "[ReaProfessor] Full recall: FXCHAIN apply count mismatch (got %d want %d); rebuilding\n",
          got, want_count))
      end
    end
  end
  -- Fallback for legacy snapshots without fxchain, or failed chunk apply
  recall_track_full_by_add(tr, src)
end

local function find_track_for_src(src, used)
  if src.guid and reaper.BR_GetMediaTrackByGUID then
    local tr = reaper.BR_GetMediaTrackByGUID(0, src.guid)
    if tr and not used[tr] then return tr end
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
      if not used[tr] then
        local _, name = reaper.GetTrackName(tr)
        if name == src.name then return tr end
      end
    end
  end
  return nil
end

--- Recall snapshot.
-- Uses the snapshot's own mode unless opts.mode is explicitly set.
-- Params/bypass auto-upgrade to full rebuild when the live chain no longer matches
-- and an FXCHAIN was stored (prevents silent "recall did nothing" after FX edits).
-- @param snap table
-- @param opts { mode=override, selected_only=bool }
function Data.recall_snapshot(snap, opts)
  if not snap or type(snap.tracks) ~= "table" then return false end
  opts = opts or {}
  local meta = Data.load_meta()
  -- Prefer the mode stored on the snapshot (what was captured for). Explicit opts.mode
  -- overrides — callers that want the snap's mode must not pass mode.
  local mode = opts.mode or snap.mode or meta.snapshot_mode or "full"
  local selected_only = opts.selected_only
  if selected_only == nil then selected_only = snap.selected_only end
  if selected_only then
    local any = false
    for i = 0, reaper.CountTracks(0) - 1 do
      if reaper.IsTrackSelected(reaper.GetTrack(0, i)) then any = true break end
    end
    if not any then
      selected_only = false
      reaper.ShowConsoleMsg("[ReaProfessor] No tracks selected — recalling all eligible tracks\n")
    end
  end

  reaper.Undo_BeginBlock2(0)
  local used = {}
  local targets = iter_snapshot_tracks(selected_only)
  local positional = 1

  local function apply(tr, src)
    local _, role = reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:ReaProfessor_role", "", false)
    if role == "record" then return end
    if selected_only and not reaper.IsTrackSelected(tr) then return end
    used[tr] = true

    local do_full = (mode == "full")
    if not do_full and mode == "params" and type(src.fxchain) == "string"
       and src.fxchain:find("<FXCHAIN", 1, true) and needs_chain_rebuild(tr, src) then
      do_full = true
    end
    -- Legacy params snaps without fxchain but with fx list: rebuild via AddByName
    if not do_full and mode == "params" and needs_chain_rebuild(tr, src)
       and type(src.fx) == "table" and #src.fx > 0 then
      do_full = true
    end

    if do_full then
      recall_track_full(tr, src)
      -- If the preferred filter was bypass after a forced rebuild, re-apply enables only
      -- would wipe params — keep full result (correct show behavior).
    else
      recall_track_bypass_or_params(tr, src, mode)
    end
    -- Sidechain / MIDI sends after FX so routing matches the snap without touching record.
    recall_sends(tr, src.sends)
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
