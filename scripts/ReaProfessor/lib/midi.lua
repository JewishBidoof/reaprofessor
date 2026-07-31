-- @description ReaProfessor MIDI map + polling helpers
-- @version 0.5.0
-- @author JewishBidoof
-- @noindex

local MIDI = {}

--- Empty map — no bindings until the user creates them.
function MIDI.empty_map()
  return {}
end

function MIDI.describe(bind)
  if not bind then return "?" end
  local cmd = tostring(bind.command or "?")
  if bind.arg ~= nil and tostring(bind.arg) ~= "" then
    cmd = cmd .. " (" .. tostring(bind.arg) .. ")"
  end
  if bind.type == "cc" then
    return string.format("Ch%d  CC%d ≥%d  →  %s",
      bind.channel or 1, bind.cc or 0, bind.threshold or 1, cmd)
  end
  return string.format("Ch%d  Note %d  →  %s",
    bind.channel or 1, bind.note or 0, cmd)
end

local function parse_message(msg)
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

function MIDI.match(event, map, opts)
  if not event or type(map) ~= "table" then return nil, nil end
  opts = opts or {}
  -- global_channel: 0/nil = omni, 1–16 = require that channel unless bind overrides
  local global_ch = tonumber(opts.global_channel) or 0
  for _, bind in ipairs(map) do
    if bind.enabled == false then goto continue end
    local want_ch = tonumber(bind.channel)
    if want_ch and want_ch > 0 and want_ch ~= event.channel then goto continue end
    if (not want_ch or want_ch == 0) and global_ch > 0 and event.channel ~= global_ch then
      goto continue
    end
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
  return nil, nil
end

--- Poll until timestamp regresses; return commands and newest ts.
-- opts.global_channel: 0/nil = omni, 1–16 = filter
function MIDI.poll_commands_v2(map, last_ts, opts)
  local cmds = {}
  local newest = last_ts or 0
  opts = opts or {}
  if not reaper.MIDI_GetRecentInputEvent then return cmds, newest end
  if type(map) ~= "table" or #map == 0 then return cmds, newest end
  for i = 0, 63 do
    local a, b, c = reaper.MIDI_GetRecentInputEvent(i)
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
    local command, bind = MIDI.match(event, map, { global_channel = opts.global_channel })
    if command then
      cmds[#cmds + 1] = { command = command, arg = bind and bind.arg, bind = bind }
    end
  end
  return cmds, newest
end

--- Peek the most recent MIDI note/cc for Learn mode.
function MIDI.learn_next(last_ts)
  if not reaper.MIDI_GetRecentInputEvent then return nil, last_ts or 0 end
  local newest = last_ts or 0
  local found = nil
  for i = 0, 63 do
    local a, b, c = reaper.MIDI_GetRecentInputEvent(i)
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
    if event and (event.type == "note_on" or event.type == "cc") then
      found = event
      break
    end
  end
  return found, newest
end

return MIDI
