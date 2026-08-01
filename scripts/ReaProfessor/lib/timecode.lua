-- @description ReaProfessor timecode helpers + cue chase
-- @version 0.6.0
-- @author JewishBidoof
-- @noindex
--
-- Show clock = REAPER project time (playhead while playing/recording,
-- edit cursor when stopped). Works with REAPER LTC/MTC chase when the
-- project playhead follows external timecode.

local TC = {}

local MARKER_PREFIX = "RP|"

function TC.fps()
  local ok, fps = pcall(reaper.TimeMap_curFrameRate, 0)
  if ok and type(fps) == "number" and fps > 0 then return fps end
  return 30
end

--- Current show position in seconds.
function TC.now_seconds()
  local state = reaper.GetPlayState() or 0
  if (state & 1) ~= 0 or (state & 4) ~= 0 then
    return reaper.GetPlayPosition() or 0
  end
  return reaper.GetCursorPosition() or 0
end

function TC.is_running()
  local state = reaper.GetPlayState() or 0
  return (state & 1) ~= 0 or (state & 4) ~= 0
end

--- Format seconds as H:M:S:F (project frame rate).
function TC.format(seconds)
  seconds = tonumber(seconds) or 0
  if seconds < 0 then seconds = 0 end
  local ok, s = pcall(reaper.format_timestr_pos, seconds, "", 5)
  if ok and type(s) == "string" and s ~= "" then return s end
  -- Fallback without REAPER formatter
  local fps = TC.fps()
  local total_f = math.floor(seconds * fps + 1e-9)
  local f = total_f % math.floor(fps + 0.5)
  local total_s = math.floor(total_f / math.max(1, math.floor(fps + 0.5)))
  local sec = total_s % 60
  local mins = math.floor(total_s / 60) % 60
  local hrs = math.floor(total_s / 3600)
  return string.format("%02d:%02d:%02d:%02d", hrs, mins, sec, f)
end

--- Parse H:M:S:F (or REAPER timestr) → seconds, or nil if blank/invalid.
function TC.parse(str)
  if not str then return nil end
  str = tostring(str):match("^%s*(.-)%s*$")
  if str == "" or str == "-" or str == "—" then return nil end
  local ok, pos = pcall(reaper.parse_timestr_pos, str, 5)
  if ok and type(pos) == "number" and pos >= 0 then return pos end
  local parts = {}
  for p in str:gmatch("%d+") do parts[#parts + 1] = tonumber(p) or 0 end
  if #parts < 3 then return nil end
  local fps = TC.fps()
  local h, m, s, f = 0, 0, 0, 0
  if #parts == 3 then
    m, s, f = parts[1], parts[2], parts[3]
  else
    h, m, s, f = parts[1], parts[2], parts[3], parts[4] or 0
  end
  return h * 3600 + m * 60 + s + (f / math.max(1, fps))
end

function TC.cue_seconds(cue)
  if type(cue) ~= "table" then return nil end
  if cue.tc_sec ~= nil then
    local n = tonumber(cue.tc_sec)
    if n then return n end
  end
  if cue.tc and cue.tc ~= "" then return TC.parse(cue.tc) end
  return nil
end

function TC.set_cue_tc(cue, seconds_or_str)
  if type(cue) ~= "table" then return false end
  local sec
  if type(seconds_or_str) == "number" then
    sec = seconds_or_str
  else
    sec = TC.parse(seconds_or_str)
  end
  if not sec then
    cue.tc = ""
    cue.tc_sec = nil
    return true
  end
  if sec < 0 then sec = 0 end
  cue.tc_sec = sec
  cue.tc = TC.format(sec)
  return true
end

function TC.clear_cue_tc(cue)
  if type(cue) ~= "table" then return end
  cue.tc = ""
  cue.tc_sec = nil
end

--- Runtime chase state (not persisted).
function TC.new_chase_state()
  return { last_pos = nil, fired = {} }
end

--- Edge-detect cues whose TC was crossed since last poll.
-- opts.pos / opts.running override transport (for tests).
-- @return array of 1-based cue indices to fire (in list order)
function TC.poll_chase(cues, armed, state, opts)
  if not armed or type(cues) ~= "table" or type(state) ~= "table" then
    return {}
  end
  opts = opts or {}
  local running = opts.running
  if running == nil then running = TC.is_running() end
  local pos = opts.pos
  if pos == nil then pos = TC.now_seconds() end

  if not running then
    state.last_pos = pos
    return {}
  end

  local last = state.last_pos
  state.last_pos = pos

  if last == nil then return {} end

  -- Seek / rewind: clear fired set so cues can fire again on the next pass.
  if pos + 0.002 < last then
    state.fired = {}
    return {}
  end

  -- Ignore huge forward jumps (scrub) — wait for a normal tick.
  if pos - last > 2.0 then
    return {}
  end

  local to_fire = {}
  for i, cue in ipairs(cues) do
    local t = TC.cue_seconds(cue)
    local key = (cue and cue.id) or ("#" .. i)
    if t and not state.fired[key] then
      if last < t and pos >= t then
        state.fired[key] = true
        to_fire[#to_fire + 1] = i
      end
    end
  end
  return to_fire
end

local function marker_name(cue)
  local id = tostring(cue.id or "?")
  local name = tostring(cue.name or "Cue"):gsub("|", "/")
  return MARKER_PREFIX .. id .. "|" .. name
end

local function marker_cue_id(name)
  if type(name) ~= "string" then return nil end
  return name:match("^RP|([^|]+)")
end

--- Upsert a project marker at the cue's TC (for timeline visibility).
function TC.sync_marker(cue)
  if type(cue) ~= "table" then return false end
  local sec = TC.cue_seconds(cue)
  local want = marker_name(cue)
  local idx = 0
  while true do
    local rv, isrgn, _, _, name, markrgnidx = reaper.EnumProjectMarkers(idx)
    if rv == 0 then break end
    idx = idx + 1
    if not isrgn then
      local id = marker_cue_id(name)
      if id and cue.id and id == tostring(cue.id) then
        if not sec then
          reaper.DeleteProjectMarker(0, markrgnidx, false)
          return true
        end
        reaper.SetProjectMarker(markrgnidx, false, sec, 0, want)
        return true
      end
    end
  end
  if not sec then return false end
  reaper.AddProjectMarker2(0, false, sec, 0, want, -1, 0)
  return true
end

function TC.remove_marker(cue)
  if type(cue) ~= "table" or not cue.id then return false end
  local idx = 0
  while true do
    local rv, isrgn, _, _, name, markrgnidx = reaper.EnumProjectMarkers(idx)
    if rv == 0 then break end
    idx = idx + 1
    if not isrgn and marker_cue_id(name) == tostring(cue.id) then
      reaper.DeleteProjectMarker(0, markrgnidx, false)
      return true
    end
  end
  return false
end

return TC
