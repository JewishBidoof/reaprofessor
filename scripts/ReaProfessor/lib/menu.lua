-- @description ReaProfessor Extensions-menu registration
-- @version 0.3.4
-- @author JewishBidoof
-- @noindex
--
-- Pure ReaScript cannot hook Extensions like ReaPack/SWS (C++ hookcustommenu).
-- We register the hub action and append it under [Main extensions] in reaper-menu.ini.
-- REAPER reads that file at startup, so a full quit + reopen is required once.
-- Writes also run on atexit so a quit does not wipe a mid-session install.

local Menu = {}

local MENU_TITLE = "&ReaProfessor"
local SECTION = "Main extensions"
local FLAG_KEY = "extensions_menu_installed"
local PENDING_KEY = "menu_named_cmd"
local HUB_KEY = "menu_hub_path"

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local function write_file(path, data)
  local f = io.open(path, "w")
  if not f then return false end
  f:write(data)
  f:close()
  return true
end

local function normalize_path(path)
  if not path then return nil end
  path = path:gsub("\\", "/")
  return path
end

--- Register hub script into the Action List; returns numeric cmd id and named id (_RS…).
function Menu.register_hub(hub_path)
  hub_path = normalize_path(hub_path)
  if not hub_path or not reaper.AddRemoveReaScript then
    return 0, nil
  end
  if not reaper.file_exists(hub_path) then
    return 0, nil
  end
  local cmd = reaper.AddRemoveReaScript(true, 0, hub_path, true)
  if not cmd or cmd == 0 then return 0, nil end
  local named = reaper.ReverseNamedCommandLookup(cmd)
  if not named or named == "" then return cmd, nil end
  if named:sub(1, 1) ~= "_" then
    named = "_" .. named
  end
  reaper.SetExtState("ReaProfessor", PENDING_KEY, named, true)
  reaper.SetExtState("ReaProfessor", HUB_KEY, hub_path, true)
  return cmd, named
end

local function parse_sections(text)
  local sections = {}
  local order = {}
  local current = nil
  local body = {}
  local function flush()
    if current then
      sections[current] = body
      order[#order + 1] = current
    end
  end
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local name = line:match("^%[(.-)%]%s*$")
    if name then
      flush()
      current = name
      body = {}
    else
      if not current then
        current = ""
        body = {}
      end
      body[#body + 1] = line
    end
  end
  flush()
  return sections, order
end

local function serialize_sections(sections, order)
  local parts = {}
  for _, name in ipairs(order) do
    local body = sections[name]
    if name ~= "" then
      parts[#parts + 1] = "[" .. name .. "]"
    end
    for _, line in ipairs(body or {}) do
      parts[#parts + 1] = line
    end
    if parts[#parts] ~= "" then parts[#parts + 1] = "" end
  end
  return table.concat(parts, "\n")
end

local function next_item_index(body)
  local max_idx = -1
  for _, line in ipairs(body) do
    local idx = line:match("^item_(%d+)=")
    if idx then
      idx = tonumber(idx) or -1
      if idx > max_idx then max_idx = idx end
    end
  end
  return max_idx + 1
end

local function body_has_cmd(body, named_cmd)
  for _, line in ipairs(body) do
    if line:find(named_cmd, 1, true) then
      return true
    end
  end
  return false
end

local function ensure_section_item(sections, order, section, named_cmd, title)
  if not sections[section] then
    sections[section] = {}
    order[#order + 1] = section
  end
  local body = sections[section]
  if body_has_cmd(body, named_cmd) then
    return false
  end
  -- Prefer a separator before our item when the section already has entries
  if #body > 0 then
    local last = body[#body]
    if last and not last:match("^%s*$") and not last:match("^-1%s*$") and not last:match("= %-1%s*$") then
      body[#body + 1] = string.format("item_%d=-1", next_item_index(body))
    end
  end
  body[#body + 1] = string.format("item_%d=%s %s", next_item_index(body), named_cmd, title)
  sections[section] = body
  return true
end

--- Ensure [Main extensions] contains our item.
--- Returns: ok, changed, message
function Menu.ensure_extensions_item(named_cmd, title)
  title = title or MENU_TITLE
  if not named_cmd or named_cmd == "" then
    return false, false, "Hub action is not registered"
  end

  local path = reaper.GetResourcePath() .. "/reaper-menu.ini"
  local text = read_file(path) or ""
  local sections, order = parse_sections(text)

  local changed = ensure_section_item(sections, order, SECTION, named_cmd, title)

  if changed then
    if not write_file(path, serialize_sections(sections, order)) then
      return false, false, "Could not write reaper-menu.ini"
    end
    return true, true, "Added Extensions → ReaProfessor.\n\nQuit REAPER fully (File → Quit), then reopen to see it."
  end
  return true, false, "Extensions menu already contains ReaProfessor.\n\nIf you still do not see it, quit REAPER fully and reopen."
end

local atexit_registered = false

local function flush_pending_menu()
  local named = reaper.GetExtState("ReaProfessor", PENDING_KEY)
  if not named or named == "" then return end
  Menu.ensure_extensions_item(named, MENU_TITLE)
end

function Menu.register_atexit_flush()
  if atexit_registered then return end
  atexit_registered = true
  reaper.atexit(flush_pending_menu)
end

--- Ensure Scripts/__startup.lua loads our hook (idempotent).
function Menu.ensure_startup_hook(hub_path)
  hub_path = normalize_path(hub_path)
  if not hub_path then return false end
  local hook = hub_path:gsub("[\\/]ReaProfessor%.lua$", "/startup_hook.lua")
  if not reaper.file_exists(hook) then
    -- ReaPack layout: .../ReaProfessor/ReaProfessor.lua → sibling startup_hook.lua
    local dir = hub_path:match("(.+[\\/])")
    hook = (dir or "") .. "startup_hook.lua"
  end
  if not reaper.file_exists(hook) then return false end

  local startup = reaper.GetResourcePath() .. "/Scripts/__startup.lua"
  local marker = "ReaProfessor/startup_hook.lua"
  local existing = read_file(startup) or ""
  if existing:find(marker, 1, true) or existing:find("startup_hook.lua", 1, true) then
    return true
  end

  local snippet = string.format([[
-- ReaProfessor: keep Extensions menu entry registered
do
  local hook = %q
  if reaper.file_exists(hook) then
    local ok, err = pcall(dofile, hook)
    if not ok then reaper.ShowConsoleMsg("[ReaProfessor] startup hook: " .. tostring(err) .. "\n") end
  end
end
]], hook)

  local data = existing
  if data ~= "" and not data:match("\n$") then data = data .. "\n" end
  data = data .. snippet
  return write_file(startup, data)
end

function Menu.install(hub_path)
  local cmd, named = Menu.register_hub(hub_path)
  if cmd == 0 or not named then
    return false, "AddRemoveReaScript failed — use Actions → Load ReaScript… on ReaProfessor.lua, then retry."
  end
  Menu.ensure_startup_hook(hub_path)
  Menu.register_atexit_flush()
  local ok, changed, msg = Menu.ensure_extensions_item(named, MENU_TITLE)
  if ok then
    reaper.SetExtState("ReaProfessor", FLAG_KEY, "1", true)
  end
  return ok, msg, named, cmd
end

--- Quiet ensure for hub/startup: register + write menu.ini, no message box.
function Menu.ensure(hub_path)
  local ok, msg = Menu.install(hub_path)
  return ok, msg
end

--- Resolve hub path from common install locations.
function Menu.find_hub()
  local res = reaper.GetResourcePath()
  local candidates = {
    res .. "/Scripts/ReaProfessor/ReaProfessor.lua",
    res .. "/Scripts/Live/ReaProfessor/ReaProfessor.lua",
    reaper.GetExtState("ReaProfessor", HUB_KEY),
  }
  for _, p in ipairs(candidates) do
    p = normalize_path(p)
    if p and p ~= "" and reaper.file_exists(p) then
      return p
    end
  end
  return nil
end

return Menu
