-- @description ReaProfessor in-window navigation (back stack)
-- @version 0.4.0
-- @author JewishBidoof
-- @noindex
--
-- Child gfx scripts open via dofile after gfx.quit. ExtState holds a return
-- stack so pages can navigate back to the hub without reopening from Actions.

local Nav = {}

local STACK_KEY = "nav_stack"
local CUR_KEY = "nav_current"
local PENDING_KEY = "nav_pending"
local SECTION = "ReaProfessor"

local function normalize(path)
  if not path or path == "" then return nil end
  return path:gsub("\\", "/")
end

local function read_stack()
  local raw = reaper.GetExtState(SECTION, STACK_KEY) or ""
  if raw == "" then return {} end
  local t = {}
  for part in raw:gmatch("[^|]+") do
    t[#t + 1] = part
  end
  return t
end

local function write_stack(t)
  reaper.SetExtState(SECTION, STACK_KEY, table.concat(t, "|"), false)
end

function Nav.set_current(path)
  path = normalize(path)
  if path then
    reaper.SetExtState(SECTION, CUR_KEY, path, false)
  end
end

function Nav.current()
  local p = reaper.GetExtState(SECTION, CUR_KEY)
  return (p and p ~= "") and p or nil
end

function Nav.can_back()
  return #(read_stack()) > 0
end

function Nav.clear()
  reaper.DeleteExtState(SECTION, STACK_KEY, false)
  reaper.DeleteExtState(SECTION, PENDING_KEY, false)
end

--- Navigate to a sibling/child script. Pushes the current page for Back.
function Nav.go(path)
  path = normalize(path)
  if not path or not reaper.file_exists(path) then
    return false, "Missing script: " .. tostring(path)
  end
  local cur = Nav.current()
  if cur and cur ~= path then
    local stack = read_stack()
    -- Avoid pushing duplicates in a row
    if stack[#stack] ~= cur then
      stack[#stack + 1] = cur
      write_stack(stack)
    end
  end
  reaper.SetExtState(SECTION, PENDING_KEY, path, false)
  return true
end

--- Pop stack and open previous page.
function Nav.back()
  local stack = read_stack()
  if #stack == 0 then return false end
  local prev = table.remove(stack)
  write_stack(stack)
  reaper.SetExtState(SECTION, PENDING_KEY, prev, false)
  return true
end

function Nav.take_pending()
  local p = reaper.GetExtState(SECTION, PENDING_KEY)
  reaper.DeleteExtState(SECTION, PENDING_KEY, false)
  if p and p ~= "" and reaper.file_exists(p) then return p end
  return nil
end

--- Call after gfx.quit() when leaving a page.
function Nav.defer_pending()
  local p = Nav.take_pending()
  if not p then return false end
  reaper.defer(function()
    dofile(p)
  end)
  return true
end

--- Draw a Back button; on click requests Nav.back() and returns true (caller should stop loop).
function Nav.back_button(UI, x, y, w, h)
  if not Nav.can_back() then return false end
  if UI.button("nav_back", x or 8, y or 10, w or 72, h or 26, "← Back", {
    bg = UI.colors.panel2,
  }) then
    Nav.back()
    return true
  end
  return false
end

--- Resolve a script relative to the ReaProfessor scripts folder.
function Nav.resolve(rel, script_dir)
  script_dir = script_dir or ""
  local path = script_dir .. rel
  if reaper.file_exists(path) then return normalize(path) end
  local alt = reaper.GetResourcePath() .. "/Scripts/Live/ReaProfessor/" .. rel
  if reaper.file_exists(alt) then return normalize(alt) end
  local res = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/" .. rel
  if reaper.file_exists(res) then return normalize(res) end
  return normalize(path)
end

return Nav
