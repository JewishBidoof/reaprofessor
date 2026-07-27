-- @description ReaProfessor - Snapshots
-- @version 0.3.0
-- @author JewishBidoof
-- @noindex
-- @about Capture/recall with bypass, params, or full FX reload.

local res = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/"
local src = debug.getinfo(1, "S").source
local script_dir = (src:sub(1, 1) == "@" and src:sub(2):match("(.+[\\/])")) or res
package.path = script_dir .. "lib/?.lua;" .. res .. "lib/?.lua;" .. package.path

local UI = require("ui")
local Data = require("data")
local Config = require("config")

local snaps = Data.load_snapshots()
local meta = Data.load_meta()
local selected = 1
local mode = meta.snapshot_mode or "params"
local selected_only = meta.selected_only and true or false
local running = true
local status = Config.actions_enabled() and "" or "Prototype — Capture/Recall disabled"

local function capture()
  if not Config.actions_enabled() then return Config.deny_action("Snapshot Capture") end
  local retval, name = reaper.GetUserInputs("Capture snapshot", 1, "Name:,extrawidth=200", "Snapshot " .. tostring(#snaps + 1))
  if not retval or name == "" then return end
  local snap = Data.capture_snapshot(name, { mode = mode, selected_only = selected_only })
  snaps[#snaps + 1] = snap
  Data.save_snapshots(snaps)
  selected = #snaps
  meta.snapshot_mode = mode
  meta.selected_only = selected_only
  Data.save_meta(meta)
  status = "Captured " .. name .. " (" .. mode .. ")"
  reaper.ShowConsoleMsg("[ReaProfessor] " .. status .. "\n")
end

local function recall()
  if not Config.actions_enabled() then return Config.deny_action("Snapshot Recall") end
  local snap = snaps[selected]
  if not snap then return end
  Data.recall_snapshot(snap, { mode = mode, selected_only = selected_only })
  status = "Recalled " .. tostring(snap.name) .. " (" .. mode .. ")"
  reaper.ShowConsoleMsg("[ReaProfessor] " .. status .. "\n")
end

local function delete_selected()
  if not Config.actions_enabled() then return Config.deny_action("Delete Snapshot") end
  if not snaps[selected] then return end
  table.remove(snaps, selected)
  selected = math.max(1, math.min(selected, #snaps))
  Data.save_snapshots(snaps)
end

UI.init("ReaProfessor · Snapshots", 720, 500, 0)

local function mode_btn(id, x, y, w, label, value)
  local bg = (mode == value) and UI.colors.selected or UI.colors.panel
  if UI.button(id, x, y, w, 28, label, { bg = bg }) then
    mode = value
    if Config.actions_enabled() then
      meta.snapshot_mode = mode
      Data.save_meta(meta)
    end
  end
end

local function draw()
  local w, h = gfx.w, gfx.h
  UI.fill_rect(0, 0, w, h, UI.colors.bg)
  gfx.setfont(2)
  UI.label(16, 14, "SNAPSHOTS", UI.colors.accent)
  gfx.setfont(3)
  UI.label(170, 22, "Record strips are never modified", UI.colors.muted)

  if UI.button("cap", w - 210, 12, 100, 36, "Capture", { bg = UI.colors.go, fg = {0.05, 0.1, 0.05} }) then
    capture()
  end
  if UI.button("rec", w - 100, 12, 88, 36, "Recall") then
    recall()
  end

  gfx.setfont(1)
  UI.label(16, 58, "Recall mode:", UI.colors.text)
  mode_btn("mb", 130, 52, 110, "Bypass only", "bypass")
  mode_btn("mp", 250, 52, 110, "Params", "params")
  mode_btn("mf", 370, 52, 140, "Full FX reload", "full")

  local sel_bg = selected_only and UI.colors.selected or UI.colors.panel
  if UI.button("sel", 520, 52, 180, 28, selected_only and "Selected tracks" or "All (eligible)", { bg = sel_bg }) then
    selected_only = not selected_only
    if Config.actions_enabled() then
      meta.selected_only = selected_only
      Data.save_meta(meta)
    end
  end

  gfx.setfont(3)
  UI.label(16, 88, "bypass = enable states  ·  params = bypass+values  ·  full = rebuild chain then params", UI.colors.muted)

  local top = 112
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
    UI.label(w - 220, y + 5, tostring(snap.mode or "?"), UI.colors.muted)
    UI.label(w - 120, y + 5, ntracks .. " tr", UI.colors.muted)
  end

  if #snaps == 0 then
    gfx.setfont(1)
    UI.label(24, top + 8, "No snapshots yet — Capture to store FX state.", UI.colors.muted)
  end

  if UI.button("del", 12, h - 44, 100, 32, "Delete", { bg = UI.colors.danger }) then
    delete_selected()
  end
  UI.label(130, h - 34, status, UI.colors.muted)

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
