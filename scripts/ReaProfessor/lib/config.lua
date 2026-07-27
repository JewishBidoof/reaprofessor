-- @description ReaProfessor config flags
-- @version 0.3.3
-- @author JewishBidoof
-- @noindex

local Config = {}

-- Flip to true when channel/cue/snapshot actions are ready for real use.
-- Until then: browse UI / Mapping only — no project or show mutations.
Config.FINALIZED = false

function Config.actions_enabled()
  return Config.FINALIZED == true
end

function Config.deny_action(name)
  reaper.ShowMessageBox(
    string.format(
      "%s is disabled until ReaProfessor is finalized.\n\nYou can browse the UI; actions will not modify the project yet.",
      name or "This action"
    ),
    "ReaProfessor",
    0
  )
  return false
end

--- Return true if actions may run; otherwise deny and return false.
function Config.require_enabled(name)
  if Config.actions_enabled() then
    return true
  end
  return Config.deny_action(name)
end

--- Run fn only when finalized; otherwise show deny message.
function Config.guard(name, fn)
  if not Config.require_enabled(name) then
    return false
  end
  return fn()
end

return Config
