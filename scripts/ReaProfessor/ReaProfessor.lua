-- @description ReaProfessor hub — launch live panels
-- @version 0.2.0
-- @author ReaProfessor
-- @about Entry point for ReaProfessor (LiveProfessor-style REAPER workflow).

local res = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/"
local src = debug.getinfo(1, "S").source
local script_dir = (src:sub(1, 1) == "@" and src:sub(2):match("(.+[\\/])")) or res
package.path = script_dir .. "lib/?.lua;" .. res .. "lib/?.lua;" .. package.path

local UI = require("ui")

local running = true
UI.init("ReaProfessor", 560, 520, 0)

local function open(rel)
  local path = script_dir .. rel
  if reaper.file_exists(path) then
    gfx.quit()
    running = false
    dofile(path)
  else
    reaper.ShowMessageBox("Missing script:\n" .. path, "ReaProfessor", 0)
  end
end

local buttons = {
  { id = "ch", label = "Create Channels (1:1 I/O)", file = "create_channels.lua" },
  { id = "cues", label = "Cue List", file = "cue_list.lua" },
  { id = "snaps", label = "Snapshots (bypass / params / full)", file = "snapshots.lua" },
  { id = "chains", label = "Chain Rack", file = "chain_rack.lua" },
  { id = "ctrl", label = "OSC / MIDI Control", file = "control_panel.lua" },
}

local function draw()
  local w, h = gfx.w, gfx.h
  UI.fill_rect(0, 0, w, h, UI.colors.bg)

  gfx.setfont(2)
  UI.label(24, 24, "ReaProfessor", UI.colors.accent)
  gfx.setfont(1)
  UI.label(24, 58, "Live plugin hosting for REAPER", UI.colors.text)
  gfx.setfont(3)
  UI.label(24, 84, "Multitrack record · FX snapshots · cue lists · OSC/MIDI", UI.colors.muted)

  local y = 130
  local bw, bh = w - 48, 40
  for _, b in ipairs(buttons) do
    if UI.button(b.id, 24, y, bw, bh, b.label) then open(b.file) end
    y = y + 48
  end
  if UI.button("live", 24, y, bw, bh, "Toggle Live Mode", { bg = UI.colors.go, fg = {0.05, 0.1, 0.05} }) then
    dofile(script_dir .. "live_mode.lua")
  end

  local ch = gfx.getchar()
  if ch == 27 or ch < 0 then running = false end
end

local function loop()
  if not running then
    gfx.quit()
    return
  end
  draw()
  gfx.update()
  reaper.defer(loop)
end

loop()
