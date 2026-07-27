-- @description ReaProfessor OSC address map + ExtState bridge
-- @version 0.2.0
-- @author ReaProfessor
--
-- Transport options:
-- 1) In-process: OSC.dispatch / control_service handlers
-- 2) ExtState bridge: write ReaProfessor/osc_queue JSON (UDP bridge or /action scripts)
-- 3) Native REAPER OSC: resources/osc/ReaProfessor.ReaperOSC → /action/...

local OSC = {}

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
local QUEUE_KEY = "osc_queue"

function OSC.dispatch(path, args, handlers)
  if not path or not handlers then return false end
  local fn = handlers[path]
  if type(fn) == "function" then
    fn(args or {})
    return true
  end
  return false
end

--- Push a command for the control service (from external OSC→ExtState bridges).
function OSC.enqueue(path, args)
  local raw = select(2, reaper.GetProjExtState(0, QUEUE_SECTION, QUEUE_KEY))
  local Data = require("data")
  local queue = Data.decode(raw)
  if type(queue) ~= "table" then queue = {} end
  queue[#queue + 1] = { path = path, args = args or {}, t = os.time() }
  reaper.SetProjExtState(0, QUEUE_SECTION, QUEUE_KEY, Data.encode(queue))
end

--- Drain queued OSC commands; returns list of {path,args}.
function OSC.drain_queue()
  local Data = require("data")
  local raw = select(2, reaper.GetProjExtState(0, QUEUE_SECTION, QUEUE_KEY))
  local queue = Data.decode(raw)
  reaper.SetProjExtState(0, QUEUE_SECTION, QUEUE_KEY, "")
  if type(queue) ~= "table" then return {} end
  return queue
end

--- Also accept global ExtState one-shot: ReaProfessor / osc_cmd = "/CueLists/Go"
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
