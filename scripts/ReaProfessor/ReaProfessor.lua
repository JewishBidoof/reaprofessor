-- @description ReaProfessor
-- @version 0.5.0
-- @author JewishBidoof
-- @about Live cue list: each cue recalls a full FX + send snapshot. Create Channels helper.
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
Nav.clear()
Nav.set_current(THIS)

local running = true
local status = ""

UI.init("ReaProfessor", 480, 420, 0)

local function open_script(rel)
  local path = Nav.resolve(rel, script_dir)
  if not path or not reaper.file_exists(path) then
    reaper.ShowMessageBox("Missing script:\n" .. tostring(rel), "ReaProfessor", 0)
    return
  end
  Nav.go(path)
  running = false
end

local function install_menu()
  local ok, msg = Menu.install(THIS)
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
  UI.label(24, 44, "Cue list · snapshot recall · channel setup", UI.colors.muted)

  local y = 100
  local bw = w - 48
  if UI.go_button("cues", 24, y, bw, 52, "Cue List") then
    open_script("cue_list.lua")
  end
  y = y + 68
  if UI.button("ch", 24, y, bw, 44, "Create Channels (1:1)", { bg = UI.colors.panel }) then
    open_script("create_channels.lua")
  end
  y = y + 64
  if UI.button("menu", 24, y, bw, 32, "Check Extensions menu", { bg = UI.colors.panel2, font = 3 }) then
    install_menu()
  end

  gfx.setfont(3)
  UI.label(24, h - 48, "Show data is stored in the project (.RPP ExtState).", UI.colors.muted)
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
    status = "Native Extensions entry OK"
  else
    status = ok and "Put reaper_reaprofessor in UserPlugins, then quit/reopen" or tostring(msg)
  end
end

loop()
