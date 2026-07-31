-- ReaProfessor startup hook — register Actions + keep Extensions shortcut.
-- Adds a flat Extensions → ReaProfessor item (never a popup/submenu).

local res = reaper.GetResourcePath()
local candidates = {
  res .. "/Scripts/ReaProfessor/lib/menu.lua",
  res .. "/Scripts/Live/ReaProfessor/lib/menu.lua",
}

local menu_path = nil
for _, p in ipairs(candidates) do
  if reaper.file_exists(p) then
    menu_path = p
    break
  end
end
if not menu_path then return end

local lib_dir = menu_path:match("(.+[\\/])")
package.path = lib_dir .. "?.lua;" .. package.path

local ok, Menu = pcall(require, "menu")
if not ok or not Menu then return end

local hub = Menu.find_hub and Menu.find_hub() or nil
if hub then
  Menu.register_hub(hub)
  local named = reaper.GetExtState("ReaProfessor", "menu_named_cmd")
  if named and named ~= "" then
    Menu.ensure_extensions_item(named, "ReaProfessor")
  end
  Menu.register_atexit_flush()
end
