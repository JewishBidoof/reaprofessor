-- @description ReaProfessor action registration (native Extensions menu)
-- @version 0.4.6
-- @author JewishBidoof
-- @noindex
--
-- Extensions → ReaProfessor is provided by the native extension
-- (reaper_reaprofessor.*) via hookcustommenu — the same mechanism ReaPack/SWS
-- use. Pure ReaScript must NOT customize [Main extensions] in reaper-menu.ini;
-- that replaces the stock menu and nests every other extension under
-- "Default menu: Main extensions".
--
-- This module:
--   • registers the hub in the Action List
--   • removes any prior [Main extensions] hijack from older ReaProfessor builds
--   • reports whether the native extension is loaded

local Menu = {}

local SECTION = "Main extensions"
local PENDING_KEY = "menu_named_cmd"
local HUB_KEY = "menu_hub_path"
local FLAG_KEY = "extensions_menu_installed"
local TITLE_NEEDLE = "ReaProfessor"
local NATIVE_CMD = "_REAPROFESSOR"

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

local function section_looks_like_ours(body)
  if not body then return false end
  local text = table.concat(body, "\n")
  if text:find(TITLE_NEEDLE, 1, true) then return true end
  if text:find("_RS", 1, true) and text:lower():find("reaprofessor", 1, true) then
    return true
  end
  -- Old 0.4.1 bandaid layout
  if text:find("_REAPACK_BROWSE", 1, true) and text:find("ReaProfessor", 1, true) then
    return true
  end
  return false
end

--- True when the native extension registered _REAPROFESSOR (or set native_ext).
function Menu.native_extension_loaded()
  local cmd = reaper.NamedCommandLookup(NATIVE_CMD)
  if cmd and cmd ~= 0 then return true end
  local flag = reaper.GetExtState("ReaProfessor", "native_ext")
  return flag == "1"
end

--- Remove [Main extensions] if we (or an older ReaProfessor) customized it,
--- so ReaPack/SWS/other hookcustommenu extensions return to the stock menu.
function Menu.restore_extensions_menu()
  local path = reaper.GetResourcePath() .. "/reaper-menu.ini"
  local text = read_file(path)
  if not text or text == "" then
    reaper.DeleteExtState("ReaProfessor", FLAG_KEY, true)
    reaper.DeleteExtState("ReaProfessor", "menu_layout", true)
    return true, false, "Extensions menu already using defaults"
  end

  local sections, order = parse_sections(text)
  local body = sections[SECTION]
  if not body then
    reaper.DeleteExtState("ReaProfessor", FLAG_KEY, true)
    reaper.DeleteExtState("ReaProfessor", "menu_layout", true)
    return true, false, "Extensions menu already using defaults"
  end

  -- Only remove the section if it looks like ours. If the user has a genuine
  -- custom Extensions menu without ReaProfessor, leave it alone.
  if not section_looks_like_ours(body) then
    return true, false, "Custom Extensions menu left unchanged (no ReaProfessor entries)"
  end

  sections[SECTION] = nil
  local new_order = {}
  for _, name in ipairs(order) do
    if name ~= SECTION then new_order[#new_order + 1] = name end
  end

  local out = serialize_sections(sections, new_order)
  if out:gsub("%s", "") == "" then
    os.remove(path)
  else
    if not write_file(path, out) then
      return false, false, "Could not write reaper-menu.ini"
    end
  end

  reaper.DeleteExtState("ReaProfessor", FLAG_KEY, true)
  reaper.DeleteExtState("ReaProfessor", "menu_layout", true)
  return true, true,
    "Removed ReaProfessor reaper-menu.ini hijack.\nStock Extensions menu restored (ReaPack/SWS/others via hooks).\n\nQuit REAPER fully, then reopen."
end

-- Kept name for callers; no longer writes menu.ini.
function Menu.ensure_extensions_item(named_cmd, title)
  local ok, changed, msg = Menu.restore_extensions_menu()
  if not ok then return false, false, msg end

  if Menu.native_extension_loaded() then
    local extra = changed
      and ("\n\n" .. msg)
      or ""
    return true, changed,
      "Extensions → ReaProfessor comes from the native extension (hookcustommenu)."
      .. "\nOther extensions stay top-level siblings."
      .. extra
  end

  return true, changed, table.concat({
    "Native extension not loaded — Extensions menu entry unavailable.",
    "",
    "Install reaper_reaprofessor into UserPlugins (ReaPack or ./tools/link_to_reaper.sh),",
    "then File → Quit and reopen REAPER.",
    "",
    "Do not customize [Main extensions] in reaper-menu.ini; that nests other extensions.",
    changed and ("\n" .. msg) or "",
  }, "\n")
end

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
        or line:find("Extensions menu", 1, true)
        or line:find("never customize Extensions", 1, true))
    if start_block then
      i = i + 1
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
  if cleaned == "" or cleaned:match("^end%s*$") then
    os.remove(startup)
    return true
  end
  return write_file(startup, cleaned .. "\n")
end

function Menu.ensure_startup_hook(hub_path)
  hub_path = normalize_path(hub_path)
  if not hub_path then return false end
  local dir = hub_path:match("(.+[\\/])") or ""
  local hook = dir .. "startup_hook.lua"
  if not reaper.file_exists(hook) then return false end

  local startup = reaper.GetResourcePath() .. "/Scripts/__startup.lua"
  local existing = read_file(startup) or ""
  if existing:find("ReaProfessor/startup_hook.lua", 1, true)
     or existing:find("startup_hook.lua", 1, true) then
    return true
  end

  local snippet = string.format([[
-- ReaProfessor: register Actions; undo any menu.ini hijack
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
  return write_file(startup, data .. snippet)
end

function Menu.register_atexit_flush()
  -- No menu.ini writes to flush.
end

function Menu.install(hub_path)
  local cmd, named = Menu.register_hub(hub_path)
  if cmd == 0 or not named then
    return false, "AddRemoveReaScript failed — use Actions → Load ReaScript… on ReaProfessor.lua, then retry."
  end
  Menu.ensure_startup_hook(hub_path)
  local ok, _, msg = Menu.ensure_extensions_item(named, "ReaProfessor")
  if not ok then return false, msg, named, cmd end
  return true, msg, named, cmd
end

function Menu.ensure(hub_path)
  return Menu.install(hub_path)
end

function Menu.find_hub()
  local res = reaper.GetResourcePath()
  local candidates = {
    reaper.GetExtState("ReaProfessor", HUB_KEY),
    res .. "/Scripts/ReaProfessor/ReaProfessor.lua",
    res .. "/Scripts/Live/ReaProfessor/ReaProfessor.lua",
    res .. "/Scripts/ReaProfessor Scripts/ReaProfessor/ReaProfessor.lua",
    res .. "/Scripts/ReaProfessor Scripts/Live/ReaProfessor.lua",
  }
  for _, p in ipairs(candidates) do
    p = normalize_path(p)
    if p and p ~= "" and reaper.file_exists(p) then
      return p
    end
  end
  -- Shallow scan Scripts/ for any ReaProfessor.lua (odd ReaPack layouts).
  local scripts = res .. "/Scripts"
  local function walk(dir, depth)
    if depth < 0 or not reaper.EnumerateFiles then return nil end
    local i = 0
    while true do
      local name = reaper.EnumerateFiles(dir, i)
      if not name then break end
      i = i + 1
      if name == "ReaProfessor.lua" then
        local p = normalize_path(dir .. "/" .. name)
        if reaper.file_exists(p) then return p end
      end
    end
    i = 0
    while true do
      local name = reaper.EnumerateSubdirectories(dir, i)
      if not name then break end
      i = i + 1
      local found = walk(dir .. "/" .. name, depth - 1)
      if found then return found end
    end
    return nil
  end
  return walk(scripts, 4)
end

return Menu
