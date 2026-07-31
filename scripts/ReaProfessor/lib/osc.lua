-- @description ReaProfessor OSC address map + ExtState bridge
-- @version 0.5.4
-- @author JewishBidoof
-- @noindex
--
-- Built-in path suggestions exist for documentation only.
-- The control service only honors user-defined OSC mappings.

local OSC = {}

--- Suggested LP2-style paths (not active until mapped by the user).
OSC.suggested_paths = {
  "/CueLists/Go",
  "/CueLists/Back",
  "/CueLists/GoTo",
  "/GlobalSnapshots/Recall",
  "/GlobalSnapshots/RecallName",
  "/GlobalSnapshots/Mode",
  "/Command/Channels/Create",
  "/Command/Channels/Mode",
  "/Command/Channels/ApplyRecordSafe",
  "/Command/View/LiveMode",
}

-- Kept for docs / older call sites; not used as live defaults.
OSC.addresses = {
  cue_go           = "/CueLists/Go",
  cue_back         = "/CueLists/Back",
  cue_goto         = "/CueLists/GoTo",
  snap_recall      = "/GlobalSnapshots/Recall",
  snap_recall_name = "/GlobalSnapshots/RecallName",
  snap_mode        = "/GlobalSnapshots/Mode",
  live_mode        = "/Command/View/LiveMode",
  create_channels  = "/Command/Channels/Create",
  channel_mode     = "/Command/Channels/Mode",
  record_safe      = "/Command/Channels/ApplyRecordSafe",
}

local QUEUE_SECTION = "ReaProfessor"
local QUEUE_KEY = "osc_queue"       -- inbound only (external → ReaProfessor)
local OUT_KEY = "osc_out"           -- last outbound path (ReaProfessor → external)
local OUT_QUEUE_KEY = "osc_out_queue" -- outbound queue (never drained as input)

function OSC.empty_map()
  return {}
end

function OSC.describe(bind)
  if not bind then return "?" end
  local cmd = tostring(bind.command or "?")
  if bind.arg ~= nil and tostring(bind.arg) ~= "" then
    cmd = cmd .. " (" .. tostring(bind.arg) .. ")"
  end
  local state = (bind.enabled == false) and "OFF" or "ON"
  return string.format("[%s] %s  →  %s", state, tostring(bind.path or "?"), cmd)
end

--- Resolve a received OSC path against the user map.
-- @return command, bind or nil
function OSC.match(path, map)
  if not path or type(map) ~= "table" then return nil, nil end
  for _, bind in ipairs(map) do
    if bind.enabled ~= false and bind.path == path then
      return bind.command, bind
    end
  end
  return nil, nil
end

function OSC.dispatch(path, args, handlers)
  if not path or not handlers then return false end
  local fn = handlers[path]
  if type(fn) == "function" then
    fn(args or {})
    return true
  end
  return false
end

--- Enqueue an *inbound* OSC message (external control → ReaProfessor).
-- Do NOT use this for messages we generate on cue fire — that causes a feedback loop.
function OSC.enqueue(path, args)
  local raw = select(2, reaper.GetProjExtState(0, QUEUE_SECTION, QUEUE_KEY))
  local Data = require("data")
  local queue = Data.decode(raw)
  if type(queue) ~= "table" then queue = {} end
  queue[#queue + 1] = { path = path, args = args or {}, t = os.time() }
  reaper.SetProjExtState(0, QUEUE_SECTION, QUEUE_KEY, Data.encode(queue))
end

function OSC.drain_queue()
  local Data = require("data")
  local raw = select(2, reaper.GetProjExtState(0, QUEUE_SECTION, QUEUE_KEY))
  local queue = Data.decode(raw)
  reaper.SetProjExtState(0, QUEUE_SECTION, QUEUE_KEY, "")
  if type(queue) ~= "table" then return {} end
  return queue
end

function OSC.clear_inbound_queue()
  reaper.SetProjExtState(0, QUEUE_SECTION, QUEUE_KEY, "")
end

--- Publish an *outbound* OSC path (cue fire → lighting desk / etc.).
-- Never written to the inbound queue.
function OSC.send_out(path, args)
  if not path or path == "" then return false end
  reaper.SetExtState(QUEUE_SECTION, OUT_KEY, tostring(path), false)
  if args ~= nil then
    local Data = require("data")
    reaper.SetExtState(QUEUE_SECTION, "osc_out_args", Data.encode(args), false)
  end
  local Data = require("data")
  local raw = select(2, reaper.GetProjExtState(0, QUEUE_SECTION, OUT_QUEUE_KEY))
  local queue = Data.decode(raw)
  if type(queue) ~= "table" then queue = {} end
  queue[#queue + 1] = { path = path, args = args or {}, t = os.time() }
  -- Keep outbound queue bounded
  while #queue > 64 do table.remove(queue, 1) end
  reaper.SetProjExtState(0, QUEUE_SECTION, OUT_QUEUE_KEY, Data.encode(queue))
  return true
end

function OSC.poll_oneshot()
  local cmd = reaper.GetExtState(QUEUE_SECTION, "osc_cmd")
  if not cmd or cmd == "" then return nil end
  reaper.DeleteExtState(QUEUE_SECTION, "osc_cmd", false)
  local arg = reaper.GetExtState(QUEUE_SECTION, "osc_arg")
  reaper.DeleteExtState(QUEUE_SECTION, "osc_arg", false)
  local args = {}
  if arg and arg ~= "" then
    for token in tostring(arg):gmatch("[^,]+") do
      local n = tonumber(token)
      args[#args + 1] = n or token
    end
  end
  return { path = cmd, args = args }
end

return OSC
