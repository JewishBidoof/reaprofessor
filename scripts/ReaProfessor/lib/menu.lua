-- @description ReaProfessor Extensions-menu registration
-- @version 0.3.2
-- @author JewishBidoof
-- @noindex
--
-- Pure ReaScript cannot hook the Extensions menu like a C++ plugin.
-- We register the hub action and add it under [Main extensions] in reaper-menu.ini.
-- REAPER must be restarted once for a new menu item to appear.

local Menu = {}

local MENU_TITLE = "ReaProfessor"
local SECTION = "Main extensions"
local FLAG_KEY = "extensions_menu_installed"

local function script_paths()
  local src = debug.getinfo(2, "S").source
  -- caller should pass hub path; this helper resolves from lib/
  local lib = (src:sub(1, 1) == "@" and src:sub(2):match("(.+[\\/])")) or ""
  local dir = lib:gsub("[\\/]lib[\\/]$", "/")
  return dir .. "ReaProfessor.lua", dir
end

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

--- Register hub script into the Action List; returns numeric cmd id and named id (_RS…).
function Menu.register_hub(hub_path)
  if not reaper.AddRemoveReaScript then
    return 0, nil
  end
  local cmd = reaper.AddRemoveReaScript(true, 0, hub_path, true)
  if not cmd or cmd == 0 then return 0, nil end
  local named = reaper.ReverseNamedCommandLookup(cmd)
  if named and named ~= "" and named:sub(1, 1) ~= "_" then
    named = "_" .. named
  end
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
    -- ensure blank line between sections
    if parts[#parts] ~= "" then parts[#parts + 1] = "" end
  end
  return table.concat(parts, "\n")
end

--- Ensure [Main extensions] contains our menu item. Returns: ok, changed, message
function Menu.ensure_extensions_item(named_cmd, title)
  title = title or MENU_TITLE
  if not named_cmd or named_cmd == "" then
    return false, false, "Hub action is not registered"
  end

  local path = reaper.GetResourcePath() .. "/reaper-menu.ini"
  local text = read_file(path) or ""
  local sections, order = parse_sections(text)

  if not sections[SECTION] then
    sections[SECTION] = {}
    order[#order + 1] = SECTION
  end

  local body = sections[SECTION]
  local needle = named_cmd
  for _, line in ipairs(body) do
    if line:find(needle, 1, true) and line:find(title, 1, true) then
      return true, false, "Extensions menu already contains ReaProfessor"
    end
    -- update title if command present under another label
    if line:find(needle, 1, true) then
      return true, false, "Extensions menu already references hub action"
    end
  end

  local max_idx = -1
  for _, line in ipairs(body) do
    local idx = line:match("^item_(%d+)=")
    if idx then
      idx = tonumber(idx) or -1
      if idx > max_idx then max_idx = idx end
    end
  end
  local next_idx = max_idx + 1
  body[#body + 1] = string.format("item_%d=%s %s", next_idx, named_cmd, title)
  sections[SECTION] = body

  if not write_file(path, serialize_sections(sections, order)) then
    return false, false, "Could not write reaper-menu.ini"
  end
  return true, true, "Added Extensions → ReaProfessor (restart REAPER to see it)"
end

function Menu.install(hub_path)
  hub_path = hub_path or select(1, script_paths())
  local cmd, named = Menu.register_hub(hub_path)
  if cmd == 0 or not named then
    return false, "AddRemoveReaScript failed — load ReaProfessor.lua from Actions once, then retry."
  end
  local ok, changed, msg = Menu.ensure_extensions_item(named, MENU_TITLE)
  if ok then
    reaper.SetExtState("ReaProfessor", FLAG_KEY, changed and "1" or "1", true)
  end
  return ok, msg, named, cmd
end

return Menu
