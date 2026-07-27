-- @description ReaProfessor action registration (no Extensions menu hijack)
-- @version 0.3.6
-- @author JewishBidoof
-- @noindex
--
-- Pure ReaScript cannot append to Extensions without customizing [Main extensions]
-- in reaper-menu.ini. That customization nests ReaPack/SWS/etc. under a submenu.
-- We only register the hub in the Action List, and we remove any prior
-- [Main extensions] edits we made so the stock Extensions menu is restored.

local Menu = {}

local SECTION = "Main extensions"
local FLAG_KEY = "extensions_menu_installed"
local PENDING_KEY = "menu_named_cmd"
local HUB_KEY = "menu_hub_path"
local TITLE_NEEDLE = "ReaProfessor"

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
  return path:gsub("\\", "/")
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
    if body ~= nil then
      if name ~= "" then
        parts[#parts + 1] = "[" .. name .. "]"
      end
      for _, line in ipairs(body) do
        parts[#parts + 1] = line
      end
      if parts[#parts] ~= "" then parts[#parts + 1] = "" end
    end
  end
  return table.concat(parts, "\n")
end

local function line_is_ours(line, named_cmd)
  if not line or line:match("^%s*$") then return false end
  if named_cmd and named_cmd ~= "" and line:find(named_cmd, 1, true) then
    return true
  end
  if line:find(TITLE_NEEDLE, 1, true) then
    return true
  end
  local lower = line:lower()
  if line:match("^item_%d+=_RS") and lower:find("reaprofessor", 1, true) then
    return true
  end
  return false
end

local function line_is_separator(line)
  return line and line:match("^item_%d+=%s*%-1%s*$") ~= nil
end

local function line_is_item(line)
  return line and line:match("^item_%d+=") ~= nil
end

--- Remove ReaProfessor entries from [Main extensions].
--- If that leaves the section empty (or separators only), delete the section so
--- REAPER restores the default Extensions menu (ReaPack/SWS at top level).
function Menu.restore_extensions_menu()
  local path = reaper.GetResourcePath() .. "/reaper-menu.ini"
  local text = read_file(path)
  if not text or text == "" then
    reaper.DeleteExtState("ReaProfessor", FLAG_KEY, true)
    return true, false, "Extensions menu already using defaults"
  end

  local named = reaper.GetExtState("ReaProfessor", PENDING_KEY)
  local sections, order = parse_sections(text)
  local body = sections[SECTION]
  if not body then
    reaper.DeleteExtState("ReaProfessor", FLAG_KEY, true)
    return true, false, "Extensions menu already using defaults"
  end

  local kept = {}
  local removed = 0
  for _, line in ipairs(body) do
    if line_is_ours(line, named) then
      removed = removed + 1
    else
      kept[#kept + 1] = line
    end
  end

  while #kept > 0 and (kept[#kept]:match("^%s*$") or line_is_separator(kept[#kept])) do
    kept[#kept] = nil
  end
  while #kept > 0 and (kept[1]:match("^%s*$") or line_is_separator(kept[1])) do
    table.remove(kept, 1)
  end

  local has_real_item = false
  for _, line in ipairs(kept) do
    if line_is_item(line) and not line_is_separator(line) then
      has_real_item = true
      break
    end
  end

  local changed = false
  if not has_real_item then
    sections[SECTION] = nil
    local new_order = {}
    for _, name in ipairs(order) do
      if name ~= SECTION then new_order[#new_order + 1] = name end
    end
    order = new_order
    changed = true
  elseif removed > 0 then
    sections[SECTION] = kept
    changed = true
  end

  if changed then
    local out = serialize_sections(sections, order)
    if out:gsub("%s", "") == "" then
      os.remove(path)
    else
      if not write_file(path, out) then
        return false, false, "Could not write reaper-menu.ini"
      end
    end
  end

  reaper.DeleteExtState("ReaProfessor", FLAG_KEY, true)
  if changed then
    return true, true, "Restored Extensions menu defaults (ReaPack/SWS back at top level).\n\nQuit REAPER fully (File → Quit), then reopen."
  end
  return true, false, "Extensions menu already using defaults"
end

--- Remove our Scripts/__startup.lua snippet that re-wrote the Extensions menu.
function Menu.remove_startup_hook()
  local startup = reaper.GetResourcePath() .. "/Scripts/__startup.lua"
  local existing = read_file(startup)
  if not existing or existing == "" then return true end
  if not existing:find("ReaProfessor", 1, true) then return true end

  local lines = {}
  for line in (existing .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end

  local function opens_block(line)
    -- crude but enough for our generated snippet + typical Lua
    if line:match("^%s*%-%-") then return false end
    if line:match("%f[%w]function%f[%W]") then return true end
    if line:match("%f[%w]then%f[%W]") then return true end
    if line:match("%f[%w]do%f[%W]") then return true end
    if line:match("%f[%w]repeat%f[%W]") then return true end
    return false
  end

  local function closes_block(line)
    if line:match("^%s*%-%-") then return false end
    return line:match("%f[%w]end%f[%W]") ~= nil or line:match("%f[%w]until%f[%W]") ~= nil
  end

  local out = {}
  local i = 1
  while i <= #lines do
    local line = lines[i]
    local start_block = line:find("ReaProfessor", 1, true)
      and (line:find("startup_hook", 1, true)
        or line:find("keep Extensions", 1, true)
        or line:find("Extensions menu entry", 1, true)
        or line:find("never customize Extensions", 1, true))
    if start_block then
      i = i + 1
      -- Optional blank lines then a do/if block
      while i <= #lines and lines[i]:match("^%s*$") do i = i + 1 end
      if i <= #lines and opens_block(lines[i]) then
        local depth = 1
        i = i + 1
        while i <= #lines and depth > 0 do
          if opens_block(lines[i]) then depth = depth + 1 end
          if closes_block(lines[i]) then depth = depth - 1 end
          i = i + 1
        end
      end
    else
      out[#out + 1] = line
      i = i + 1
    end
  end

  local cleaned = table.concat(out, "\n"):gsub("\n\n\n+", "\n\n"):gsub("^%s+", ""):gsub("%s+$", "")
  -- Leftover stray ends from a partial prior cleanup
  if cleaned == "" or cleaned == "end" or cleaned:match("^end%s*$") then
    os.remove(startup)
    return true
  end
  return write_file(startup, cleaned .. "\n")
end

--- Register Actions entry only; undo any prior Extensions menu customization.
function Menu.install(hub_path)
  local cmd, named = Menu.register_hub(hub_path)
  if cmd == 0 or not named then
    return false, "AddRemoveReaScript failed — use Actions → Load ReaScript… on ReaProfessor.lua, then retry."
  end
  Menu.remove_startup_hook()
  local ok, _, msg = Menu.restore_extensions_menu()
  if not ok then return false, msg, named, cmd end
  return true, msg, named, cmd
end

function Menu.ensure(hub_path)
  return Menu.install(hub_path)
end

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
