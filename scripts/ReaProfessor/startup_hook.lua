-- ReaProfessor startup hook — register Actions; undo menu.ini hijack.

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
  -- Undo any prior [Main extensions] customization from older builds.
  if Menu.restore_extensions_menu then
    Menu.restore_extensions_menu()
  end
end
