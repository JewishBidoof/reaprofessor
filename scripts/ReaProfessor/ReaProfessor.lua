-- @description ReaProfessor
-- @version 0.3.6
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

local running = true
local pending_open = nil
local status = ""

UI.init("ReaProfessor", 560, 620, 0)

-- Safe handoff: quit this gfx script fully, then open the next on a later defer tick.
local function open_script(rel)
  local path = script_dir .. rel
  if not reaper.file_exists(path) then
    path = alt .. rel
  end
  if not reaper.file_exists(path) then
    reaper.ShowMessageBox("Missing script:\n" .. tostring(rel), "ReaProfessor", 0)
    return
  end
  pending_open = path
  running = false
end

local buttons = {
  { id = "ch", label = "Create Channels (1:1 I/O)", file = "create_channels.lua" },
  { id = "cues", label = "Cue List", file = "cue_list.lua" },
  { id = "snaps", label = "Snapshots (bypass / params / full)", file = "snapshots.lua" },
  { id = "chains", label = "Chain Rack", file = "chain_rack.lua" },
  { id = "map", label = "MIDI / OSC Mapping", file = "mapping.lua" },
  { id = "ctrl", label = "Control Service", file = "control_panel.lua" },
}

local function restore_menu()
  local hub = script_dir .. "ReaProfessor.lua"
  if not reaper.file_exists(hub) then hub = alt .. "ReaProfessor.lua" end
  local ok, msg = Menu.install(hub)
  status = tostring(msg)
  reaper.ShowMessageBox(tostring(msg), "ReaProfessor", 0)
end

local function draw()
  local w, h = gfx.w, gfx.h
  UI.fill_rect(0, 0, w, h, UI.colors.bg)

  gfx.setfont(2)
  UI.label(24, 20, "ReaProfessor", UI.colors.accent)
  gfx.setfont(1)
  UI.label(24, 52, "Live plugin hosting for REAPER", UI.colors.text)
  gfx.setfont(3)
  UI.label(24, 78, "Open from Actions list  ·  Extensions menu left untouched", UI.colors.muted)

  local y = 110
  local bw, bh = w - 48, 38
  for _, b in ipairs(buttons) do
    if UI.button(b.id, 24, y, bw, bh, b.label) then
      open_script(b.file)
    end
    y = y + 44
  end

  if UI.button("live", 24, y, bw, bh, "Toggle Live Mode", { bg = UI.colors.panel }) then
    open_script("live_mode.lua")
  end
  y = y + 50

  if UI.button("menu", 24, y, bw, bh, "Restore Extensions menu (fix nesting)", { bg = UI.colors.go, fg = {0.05, 0.1, 0.05} }) then
    restore_menu()
  end

  gfx.setfont(3)
  UI.label(24, h - 28, status, UI.colors.muted)

  local ch = gfx.getchar()
  if ch == 27 or ch < 0 then running = false end
end

local function loop()
  if not running then
    gfx.quit()
    if pending_open then
      local path = pending_open
      pending_open = nil
      reaper.defer(function()
        dofile(path)
      end)
    end
    return
  end
  draw()
  gfx.update()
  reaper.defer(loop)
end

-- Register in Actions; undo any prior [Main extensions] customization that nested other plugins.
do
  local hub = script_dir .. "ReaProfessor.lua"
  if not reaper.file_exists(hub) then hub = alt .. "ReaProfessor.lua" end
  local ok, msg = Menu.ensure(hub)
  status = ok and "Actions registered · Extensions menu left stock (ReaPack/SWS stay top-level)" or tostring(msg)
end

loop()
