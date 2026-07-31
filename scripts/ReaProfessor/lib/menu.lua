-- @description ReaProfessor action + Extensions menu registration
-- @version 0.4.1
-- @author JewishBidoof
-- @noindex
--
-- Pure ReaScript cannot append to Extensions without writing [Main extensions]
-- in reaper-menu.ini. That replaces the stock menu, and REAPER then parks
-- hookcustommenu items (ReaPack, SWS) under "Default menu: Main extensions".
--
-- Fix: write a complete Extensions layout with ReaProfessor plus explicit
-- ReaPack and SWS/S&M submenus (named commands), so those stay reachable at
-- the top level. After quit/reopen, optionally uncheck
-- Options → Customize menus/toolbars → Include default menu as submenu
-- to hide the leftover Default menu wrapper.

local Menu = {}

local MENU_TITLE = "ReaProfessor"
local SECTION = "Main extensions"
local FLAG_KEY = "extensions_menu_installed"
local PENDING_KEY = "menu_named_cmd"
local HUB_KEY = "menu_hub_path"
local TITLE_NEEDLE = "ReaProfessor"
local LAYOUT_TAG = "reaprofessor_layout=0.4.1"

-- ReaPack's own Extensions submenu (from ReaPack main.cpp).
local REAPACK_ITEMS = {
  { id = "_REAPACK_SYNC",   label = "&Synchronize packages" },
  { id = "_REAPACK_BROWSE", label = "&Browse packages..." },
  { id = "_REAPACK_IMPORT", label = "&Import repositories..." },
  { id = "_REAPACK_MANAGE", label = "&Manage repositories..." },
  { id = "-" },
  { id = "_REAPACK_ABOUT",  label = "&About ReaPack" },
}

-- Top-level entries from SWS SWSCreateExtensionsMenu (Menus.cpp). Nested
-- SWS submenus are flattened to their primary open/dialog actions.
local SWS_ITEMS = {
  { id = "_SWSAUTOCOLOR_OPEN",            label = "Auto Color/Icon/Layout" },
  { id = "_AUTORENDER",                   label = "Autorender: Batch render regions..." },
  { id = "_XENAKIOS_SHOW_COMMANDPARAMS",  label = "Command parameters..." },
  { id = "_BR_CONTEXTUAL_TOOLBARS_PREF",  label = "Contextual toolbars..." },
  { id = "_S&M_SENDS4",                   label = "Cue Buss generator" },
  { id = "_S&M_CYCLEDITOR",               label = "Cycle Action editor..." },
  { id = "_PADRE_ENVPROC",                label = "Envelope processor..." },
  { id = "_S&M_SHOWFIND",                 label = "Find" },
  { id = "_FNG_GROOVE_TOOL",              label = "Groove tool..." },
  { id = "_IX_LABEL_PROC",                label = "Label processor..." },
  { id = "_BR_ANALAYZE_LOUDNESS_DLG",     label = "Loudness..." },
  { id = "_PADRE_ENVLFO",                 label = "LFO generator..." },
  { id = "_S&M_SHOWMIDILIVE",             label = "Live Configs" },
  { id = "_SWSMARKERLIST1",               label = "MarkerList" },
  { id = "_S&M_SHOW_NOTES_VIEW",          label = "Notes" },
  { id = "_SWS_PROJLIST_OPEN",            label = "Project List" },
  { id = "_SWSCONSOLE",                   label = "ReaConsole..." },
  { id = "_S&M_SHOW_RGN_PLAYLIST",        label = "Region Playlist" },
  { id = "_S&M_SHOW_RESOURCES_VIEW",      label = "Resources" },
  { id = "_SWSSNAPSHOT_OPEN",             label = "Snapshots" },
  { id = "_SWSTL_OPEN",                   label = "Tracklist" },
  { id = "_SWS_ZOOMPREFS",                label = "Zoom preferences..." },
  { id = "-" },
  { id = "_SWS_ABOUT",                    label = "About SWS Extension" },
}

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

local function cmd_available(id)
  if not id or id == "" or id == "-" then return false end
  local n = reaper.NamedCommandLookup(id)
  return n and n ~= 0
end

--- Build a complete [Main extensions] body: ReaProfessor + ReaPack + SWS.
local function build_extensions_body(named_cmd, title)
  title = title or MENU_TITLE
  local items = {}
  local function add(val)
    items[#items + 1] = val
  end

  add(named_cmd .. " " .. title)
  add("-1")

  add("-2 Rea&Pack")
  local rp = 0
  for _, e in ipairs(REAPACK_ITEMS) do
    if e.id == "-" then
      if rp > 0 then add("-1") end
    elseif cmd_available(e.id) then
      add(e.id .. " " .. e.label)
      rp = rp + 1
    end
  end
  add("-3")

  add("-1")
  add("-2 S&WS/S&M")
  local sw = 0
  for _, e in ipairs(SWS_ITEMS) do
    if e.id == "-" then
      if sw > 0 then add("-1") end
    elseif cmd_available(e.id) then
      add(e.id .. " " .. e.label)
      sw = sw + 1
    end
  end
  add("-3")

  local out = { "title=E&xtensions" }
  for i, val in ipairs(items) do
    out[#out + 1] = string.format("item_%d=%s", i - 1, val)
  end
  return out, rp, sw
end

local function layout_is_complete(body, named_cmd)
  if not body or not named_cmd then return false end
  local joined = table.concat(body, "\n")
  if not joined:find(named_cmd, 1, true) then return false end
  if not joined:find("ReaProfessor", 1, true) then return false end
  -- Must include ReaPack browse as a real command (not only Default menu).
  if not joined:find("_REAPACK_BROWSE", 1, true) then return false end
  -- ReaProfessor itself must be a flat _RS command, not a numeric submenu id.
  local flat = false
  for _, line in ipairs(body) do
    local val = line:match("^item_%d+=(.*)$")
    if val and val:find(named_cmd, 1, true) and val:match("^_RS") then
      flat = true
      break
    end
  end
  return flat
end

local RESTART_HINT = table.concat({
  "Quit REAPER fully (File → Quit), then reopen to load the menu.",
  "",
  "If ReaPack/SWS still sit under “Default menu: Main extensions”:",
  "  Options → Customize menus/toolbars… → Main extensions",
  "  → uncheck “Include default menu as submenu” → OK.",
  "Our layout already lists ReaPack and SWS/S&M as top-level submenus.",
}, "\n")

--- Install / repair complete Extensions → ReaProfessor + ReaPack + SWS layout.
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
  if layout_is_complete(body, named_cmd) then
    reaper.SetExtState("ReaProfessor", FLAG_KEY, "1", true)
    reaper.SetExtState("ReaProfessor", "menu_layout", LAYOUT_TAG, true)
    return true, false,
      "Extensions menu already has ReaProfessor + ReaPack/SWS.\n\n"
      .. "If you do not see it yet, quit REAPER fully and reopen.\n"
      .. "If ReaPack/SWS are under “Default menu”, uncheck\n"
      .. "“Include default menu as submenu” in Customize menus/toolbars."
  end

  local new_body, rp, sw = build_extensions_body(named_cmd, title)
  sections[SECTION] = new_body

  if not write_file(path, serialize_sections(sections, order)) then
    return false, false, "Could not write reaper-menu.ini"
  end
  reaper.SetExtState("ReaProfessor", FLAG_KEY, "1", true)
  reaper.SetExtState("ReaProfessor", "menu_layout", LAYOUT_TAG, true)

  local summary = string.format(
    "Updated Extensions menu:\n  • ReaProfessor\n  • ReaPack (%d actions)\n  • SWS/S&M (%d actions)\n\n%s",
    rp, sw, RESTART_HINT
  )
  return true, true, summary
end

--- Remove our Extensions section entirely so REAPER restores stock hooks.
function Menu.restore_extensions_menu()
  local path = reaper.GetResourcePath() .. "/reaper-menu.ini"
  local text = read_file(path)
  if not text or text == "" then
    reaper.DeleteExtState("ReaProfessor", FLAG_KEY, true)
    reaper.DeleteExtState("ReaProfessor", "menu_layout", true)
    return true, false, "Extensions menu already using defaults"
  end

  local sections, order = parse_sections(text)
  if not sections[SECTION] then
    reaper.DeleteExtState("ReaProfessor", FLAG_KEY, true)
    reaper.DeleteExtState("ReaProfessor", "menu_layout", true)
    return true, false, "Extensions menu already using defaults"
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
  return true, true, "Removed customized Extensions menu (stock ReaPack/SWS restored).\n\nQuit REAPER fully, then reopen."
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
        or line:find("Extensions menu entry", 1, true)
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
  if cleaned == "" or cleaned == "end" or cleaned:match("^end%s*$") then
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
-- ReaProfessor: keep Extensions menu layout registered
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

--- Register Actions + ensure complete Extensions menu layout.
function Menu.install(hub_path)
  local cmd, named = Menu.register_hub(hub_path)
  if cmd == 0 or not named then
    return false, "AddRemoveReaScript failed — use Actions → Load ReaScript… on ReaProfessor.lua, then retry."
  end
  Menu.ensure_startup_hook(hub_path)
  Menu.register_atexit_flush()
  local ok, _, msg = Menu.ensure_extensions_item(named, MENU_TITLE)
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

-- Exported for tests
Menu._build_extensions_body = build_extensions_body
Menu._layout_is_complete = layout_is_complete

return Menu
