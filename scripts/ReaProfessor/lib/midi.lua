-- @description ReaProfessor MIDI map + polling helpers
-- @version 0.2.0
-- @author ReaProfessor

local MIDI = {}

local DEFAULT_MAP = {
  -- Note 36 (C1) / CC 64 on ch 1 → cue go; note 37 → back (editable)
  { id = "go", type = "note_on", channel = 1, note = 36, command = "cue_go" },
  { id = "back", type = "note_on", channel = 1, note = 37, command = "cue_back" },
  { id = "go_cc", type = "cc", channel = 1, cc = 64, command = "cue_go", threshold = 64 },
}

function MIDI.default_map()
  local copy = {}
  for i, row in ipairs(DEFAULT_MAP) do copy[i] = {
    id = row.id, type = row.type, channel = row.channel, note = row.note,
    cc = row.cc, command = row.command, threshold = row.threshold,
  } end
  return copy
end

local function parse_message(msg)
  -- msg is packed integer from MIDI_GetRecentInputEvent (low 3 bytes)
  if not msg or msg == 0 then return nil end
  local b0 = msg & 0xFF
  local b1 = (msg >> 8) & 0xFF
  local b2 = (msg >> 16) & 0xFF
  local status = b0 & 0xF0
  local channel = (b0 & 0x0F) + 1
  if status == 0x90 and b2 > 0 then
    return { type = "note_on", channel = channel, note = b1, velocity = b2 }
  elseif status == 0x80 or (status == 0x90 and b2 == 0) then
    return { type = "note_off", channel = channel, note = b1, velocity = b2 }
  elseif status == 0xB0 then
    return { type = "cc", channel = channel, cc = b1, value = b2 }
  end
  return nil
end

function MIDI.match(event, map)
  if not event or type(map) ~= "table" then return nil end
  for _, bind in ipairs(map) do
    if bind.channel and bind.channel ~= event.channel then goto continue end
    if bind.type == "note_on" and event.type == "note_on" and bind.note == event.note then
      return bind.command, bind
    elseif bind.type == "cc" and event.type == "cc" and bind.cc == event.cc then
      local thr = bind.threshold or 1
      if (event.value or 0) >= thr then
        return bind.command, bind
      end
    end
    ::continue::
  end
  return nil
end

--- Poll recent MIDI events; returns list of matched command strings.
function MIDI.poll_commands(map, max_events)
  local cmds = {}
  if not reaper.MIDI_GetRecentInputEvent then return cmds end
  max_events = max_events or 32
  for i = 0, max_events - 1 do
    local ts, raw = reaper.MIDI_GetRecentInputEvent(i)
    if not ts or ts == 0 then break end
    -- raw may be returned as second value; older signatures vary
    local msg = raw
    if type(ts) == "number" and type(raw) == "number" then
      msg = raw
    elseif type(ts) == "number" and raw == nil then
      -- some builds return only timestamp of empty
      break
    end
    local event = parse_message(msg)
    local command = MIDI.match(event, map)
    if command then cmds[#cmds + 1] = command end
  end
  return cmds
end

-- More reliable poll: walk until timestamp 0
function MIDI.poll_commands_v2(map, last_ts)
  local cmds = {}
  local newest = last_ts or 0
  if not reaper.MIDI_GetRecentInputEvent then return cmds, newest end
  for i = 0, 63 do
    local a, b, c = reaper.MIDI_GetRecentInputEvent(i)
    -- REAPER returns: retval (1/0), ts, msg  OR  ts, msg depending on version
    local ts, msg
    if c ~= nil then
      ts, msg = b, c
      if a == 0 then break end
    else
      ts, msg = a, b
    end
    if not ts or ts == 0 then break end
    if ts <= (last_ts or 0) then break end
    if ts > newest then newest = ts end
    local event = parse_message(msg)
    local command = MIDI.match(event, map)
    if command then cmds[#cmds + 1] = command end
  end
  return cmds, newest
end

return MIDI
