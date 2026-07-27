-- @description ReaProfessor - Global Snapshots
-- @version 0.1.0
-- @author ReaProfessor
-- @about Capture and recall lightweight track/FX snapshots (LiveProfessor-style).

local script_path = ({reaper.get_action_context()})[2]
local script_dir = script_path:match("(.+[\\/])") or ""
package.path = script_dir .. "lib/?.lua;" .. package.path

local UI = require("ui")
local Data = require("data")

local snaps = Data.load_snapshots()
local selected = 1
local running = true

local function capture()
  local retval, name = reaper.GetUserInputs("Capture snapshot", 1, "Name:,extrawidth=200", "Snapshot " .. tostring(#snaps + 1))
  if not retval or name == "" then return end
  local snap = Data.capture_snapshot(name)
  snaps[#snaps + 1] = snap
  Data.save_snapshots(snaps)
  selected = #snaps
  reaper.ShowConsoleMsg("[ReaProfessor] Captured snapshot: " .. name .. "\n")
end

local function recall()
  local snap = snaps[selected]
  if not snap then return end
  Data.recall_snapshot(snap)
  reaper.ShowConsoleMsg("[ReaProfessor] Recalled: " .. tostring(snap.name) .. "\n")
end

local function delete_selected()
  if not snaps[selected] then return end
  table.remove(snaps, selected)
  selected = math.max(1, math.min(selected, #snaps))
  Data.save_snapshots(snaps)
end

UI.init("ReaProfessor · Snapshots", 640, 440, 0)

local function draw()
  local w, h = gfx.w, gfx.h
  UI.fill_rect(0, 0, w, h, UI.colors.bg)
  gfx.setfont(2)
  UI.label(16, 14, "SNAPSHOTS", UI.colors.accent)
  gfx.setfont(3)
  UI.label(170, 22, "Track mute/solo + FX params (first 32)", UI.colors.muted)

  if UI.button("cap", w - 210, 12, 100, 36, "Capture", { bg = UI.colors.go, fg = {0.05, 0.1, 0.05} }) then
    capture()
  end
  if UI.button("rec", w - 100, 12, 88, 36, "Recall") then
    recall()
  end

  local top = 64
  local row_h = 28
  for i, snap in ipairs(snaps) do
    local y = top + (i - 1) * row_h
    if y > h - 60 then break end
    local bg = (i == selected) and UI.colors.selected or ((i % 2 == 0) and UI.colors.row_alt or UI.colors.bg)
    UI.fill_rect(12, y, w - 24, row_h - 2, bg)
    if gfx.mouse_x >= 12 and gfx.mouse_x <= w - 12 and gfx.mouse_y >= y and gfx.mouse_y <= y + row_h - 2 then
      if gfx.mouse_cap & 1 == 1 then selected = i end
    end
    gfx.setfont(1)
    UI.label(24, y + 5, string.format("%02d  %s", i, snap.name or "?"), UI.colors.text)
    local ntracks = type(snap.tracks) == "table" and #snap.tracks or 0
    UI.label(w - 140, y + 5, ntracks .. " tracks", UI.colors.muted)
  end

  if #snaps == 0 then
    gfx.setfont(1)
    UI.label(24, top + 8, "No snapshots yet — Capture to store current FX state.", UI.colors.muted)
  end

  if UI.button("del", 12, h - 44, 100, 32, "Delete", { bg = UI.colors.danger }) then
    delete_selected()
  end
  UI.label(130, h - 34, "Tip: name snapshots to match cue targets", UI.colors.muted)

  local ch = gfx.getchar()
  if ch == 27 or ch < 0 then running = false
  elseif ch == 13 then recall()
  elseif ch == ("c"):byte() then capture()
  end
end

local function loop()
  if not running then gfx.quit(); return end
  draw()
  gfx.update()
  reaper.defer(loop)
end

loop()
