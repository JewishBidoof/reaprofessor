-- @description ReaProfessor OSC helpers (path-compatible stubs for LP2)
-- @version 0.1.0
-- @author ReaProfessor
--
-- Full UDP OSC I/O needs an extension (e.g. CSI, oscilua) or external bridge.
-- This module defines the address map and in-process dispatch used by Cue List.

local OSC = {}

OSC.addresses = {
  cue_go           = "/CueLists/Go",
  cue_back         = "/CueLists/Back",
  cue_goto         = "/CueLists/GoTo",
  snap_recall      = "/GlobalSnapshots/Recall",
  snap_recall_name = "/GlobalSnapshots/RecallName",
  live_mode        = "/Command/View/LiveMode",
}

--- Dispatch a logical OSC command to ReaProfessor handlers.
-- @param path string
-- @param args table|nil
-- @param handlers table of path -> function(args)
function OSC.dispatch(path, args, handlers)
  if not path or not handlers then return false end
  local fn = handlers[path]
  if type(fn) == "function" then
    fn(args or {})
    return true
  end
  return false
end

return OSC
