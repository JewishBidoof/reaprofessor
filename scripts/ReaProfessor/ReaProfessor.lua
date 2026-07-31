-- @description ReaProfessor
-- @version 0.4.3
-- @author JewishBidoof
-- @about Live plugin host toolkit for REAPER (cue lists, snapshots, 1:1 channels, custom MIDI/OSC).
-- @noindex

local res = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/"
local src = debug.getinfo(1, "S").source
local script_dir = (src:sub(1, 1) == "@" and src:sub(2):match("(.+[\\/])")) or res
local alt = reaper.GetResourcePath() .. "/Scripts/Live/ReaProfessor/"
package.path = script_dir .. "lib/?.lua;" .. alt .. "lib/?.lua;" .. res .. "lib/?.lua;" .. package.path

local UI = require("ui")
local Menu = require("menu")
local Nav = require("nav")

local THIS = script_dir .. "ReaProfessor.lua"
if not reaper.file_exists(THIS) then THIS = alt .. "ReaProfessor.lua" end
Nav.set_current(THIS)
-- Opening the hub clears the back stack (home).
Nav.clear()
Nav.set_current(THIS)

local running = true
local status = ""

UI.init("ReaProfessor", 480, 640, 0)

local function open_script(rel)
  local path = Nav.resolve(rel, script_dir)
  if not path or not reaper.file_exists(path) then
    reaper.ShowMessageBox("Missing script:\n" .. tostring(rel), "ReaProfessor", 0)
    return
  end
  Nav.go(path)
  running = false
end

local buttons = {
  { id = "live",  label = "Live Mode (perform)",   file = "live_mode.lua" },
  { id = "cues",  label = "Cue List",              file = "cue_list.lua" },
  { id = "snaps", label = "Global Snapshots",      file = "snapshots.lua" },
  { id = "nav",   label = "Navigator",             file = "navigator.lua" },
  { id = "chains",label = "Chains",                file = "chain_rack.lua" },
  { id = "ch",    label = "Create Channels (1:1)", file = "create_channels.lua" },
  { id = "map",   label = "MIDI / OSC Mapping",    file = "mapping.lua" },
  { id = "ctrl",  label = "Control Service",       file = "control_panel.lua" },
}

local function install_menu()
  local hub = THIS
  local ok, msg = Menu.install(hub)
  status = tostring(msg)
  reaper.ShowMessageBox(tostring(msg), "ReaProfessor", 0)
end

local function remove_menu_entry()
  local ok, _, msg = Menu.restore_extensions_menu()
  status = tostring(msg)
  reaper.ShowMessageBox(tostring(msg), "ReaProfessor", 0)
end

local function draw()
  local w, h = UI.dims()
  UI.fill_rect(0, 0, w, h, UI.colors.bg)
  UI.fill_rect(0, 0, w, 72, UI.colors.header)
  UI.hline(0, 72, w, UI.colors.border)

  gfx.setfont(2)
  UI.label(24, 16, "ReaProfessor", UI.colors.text)
  gfx.setfont(3)
  UI.label(24, 44, "Live plugin hosting for REAPER", UI.colors.muted)

  local y = 92
  local bw, bh = w - 48, 40
  for _, b in ipairs(buttons) do
    if UI.button(b.id, 24, y, bw, bh, b.label, { bg = UI.colors.panel }) then
      open_script(b.file)
    end
    y = y + 46
  end

  if UI.button("menu", 24, y + 8, bw, 34, "Check Extensions / undo menu.ini hijack", { bg = UI.colors.go, fg = UI.colors.go_fg }) then
    install_menu()
  end
  y = y + 48
  if UI.button("unmenu", 24, y, bw, 28, "Remove old Extensions menu.ini customization", { bg = UI.colors.panel2 }) then
    remove_menu_entry()
  end

  gfx.setfont(3)
  UI.label(24, h - 28, status, UI.colors.muted)

  local ch = gfx.getchar()
  if ch == 27 or ch < 0 then running = false end
end

local function loop()
  if not running then
    UI.quit_and_nav(Nav)
    return
  end
  draw()
  gfx.update()
  reaper.defer(loop)
end

do
  local ok, msg = Menu.ensure(THIS)
  if Menu.native_extension_loaded and Menu.native_extension_loaded() then
    status = "Native Extensions entry OK (quit/reopen if menu.ini was cleaned)"
  else
    status = ok and "Put reaper_reaprofessor in UserPlugins, then quit/reopen" or tostring(msg)
  end
end

loop()
