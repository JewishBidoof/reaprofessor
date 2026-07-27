-- @description ReaProfessor config flags
-- @version 0.3.2
-- @author JewishBidoof
-- @noindex

local Config = {}

-- Flip to true when channel/cue/snapshot actions are ready for real use.
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

--- Run fn only when finalized; otherwise show deny message.
function Config.guard(name, fn)
  if not Config.actions_enabled() then
    return Config.deny_action(name)
  end
  return fn()
end

return Config
