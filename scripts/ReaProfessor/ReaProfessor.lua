-- @description ReaProfessor hub — launch live panels
-- @version 0.1.0
-- @author ReaProfessor
-- @about Entry point for ReaProfessor (LiveProfessor-style REAPER workflow).

local res = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/"
local src = debug.getinfo(1, "S").source
local script_dir = (src:sub(1, 1) == "@" and src:sub(2):match("(.+[\\/])")) or res
package.path = script_dir .. "lib/?.lua;" .. res .. "lib/?.lua;" .. package.path

local UI = require("ui")

local running = true
UI.init("ReaProfessor", 520, 360, 0)

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

local function draw()
  local w, h = gfx.w, gfx.h
  UI.fill_rect(0, 0, w, h, UI.colors.bg)

  gfx.setfont(2)
  UI.label(24, 28, "ReaProfessor", UI.colors.accent)
  gfx.setfont(1)
  UI.label(24, 64, "Live plugin hosting for REAPER", UI.colors.text)
  gfx.setfont(3)
  UI.label(24, 92, "Cue lists · snapshots · chain racks — LiveProfessor-style", UI.colors.muted)

  local y = 140
  local bw, bh = w - 48, 40
  if UI.button("cues", 24, y, bw, bh, "Open Cue List") then open("cue_list.lua") end
  y = y + 52
  if UI.button("snaps", 24, y, bw, bh, "Open Snapshots") then open("snapshots.lua") end
  y = y + 52
  if UI.button("chains", 24, y, bw, bh, "Open Chain Rack") then open("chain_rack.lua") end
  y = y + 52
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
