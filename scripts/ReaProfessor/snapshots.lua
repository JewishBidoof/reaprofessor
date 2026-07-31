-- @description ReaProfessor - Snapshots (LiveProfessor-style Global Snapshots)
-- @version 0.3.8
-- @author JewishBidoof
-- @noindex
-- @about Capture/recall FX chains. Capture always stores full FXCHAIN; mode is recall filter.

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
local mode = meta.snapshot_mode or "full"
local selected_only = meta.selected_only and true or false
local running = true
local status = Config.actions_enabled() and "" or "Prototype — Capture/Recall disabled"

local function persist_meta()
  if not Config.actions_enabled() then return end
  meta.snapshot_mode = mode
  meta.selected_only = selected_only
  Data.save_meta(meta)
end

local function capture()
  if not Config.actions_enabled() then return Config.deny_action("Snapshot Capture") end
  local retval, name = reaper.GetUserInputs("Capture snapshot", 1, "Name:,extrawidth=200", "Snapshot " .. tostring(#snaps + 1))
  if not retval or name == "" then return end
  -- Always stores FXCHAIN+params; mode is preferred recall filter.
  local snap = Data.capture_snapshot(name, { mode = mode, selected_only = selected_only })
  snaps[#snaps + 1] = snap
  Data.save_snapshots(snaps)
  selected = #snaps
  persist_meta()
  local nfx = 0
  if snap.tracks then
    for _, t in ipairs(snap.tracks) do nfx = nfx + (t.fx and #t.fx or 0) end
  end
  status = string.format("Stored '%s' · %d FX · filter %s", name, nfx, mode)
  reaper.ShowConsoleMsg("[ReaProfessor] " .. status .. "\n")
end

local function update_selected()
  if not Config.actions_enabled() then return Config.deny_action("Update Snapshot") end
  local prev = snaps[selected]
  if not prev then return end
  local snap = Data.capture_snapshot(prev.name, { mode = mode, selected_only = selected_only })
  snap.id = prev.id or snap.id
  snaps[selected] = snap
  Data.save_snapshots(snaps)
  status = "Updated '" .. tostring(prev.name) .. "'"
end

local function recall()
  if not Config.actions_enabled() then return Config.deny_action("Snapshot Recall") end
  local snap = snaps[selected]
  if not snap then return end
  -- CRITICAL: use the snapshot's own mode — do not override with UI filter.
  -- (Passing UI mode="params" over a full snap was silently breaking recall.)
  Data.recall_snapshot(snap, { selected_only = selected_only })
  status = "Recalled '" .. tostring(snap.name) .. "' (" .. tostring(snap.mode or mode) .. ")"
  reaper.ShowConsoleMsg("[ReaProfessor] " .. status .. "\n")
end

local function delete_selected()
  if not Config.actions_enabled() then return Config.deny_action("Delete Snapshot") end
  if not snaps[selected] then return end
  table.remove(snaps, selected)
  selected = math.max(1, math.min(selected, #snaps))
  Data.save_snapshots(snaps)
  status = "Deleted"
end

UI.init("ReaProfessor · Global Snapshots", 520, 560, 0)

local function mode_btn(id, x, y, w, label, value)
  local bg = (mode == value) and UI.colors.selected or UI.colors.panel
  if UI.button(id, x, y, w, 26, label, { bg = bg }) then
    mode = value
    persist_meta()
  end
end

local function draw()
  local w, h = gfx.w, gfx.h
  UI.fill_rect(0, 0, w, h, UI.colors.bg)
  UI.header_bar(w, "Global Snapshots", "Capture stores full FX chains · Recall uses each snapshot's filter")

  -- Capture-mode / recall-filter strip
  gfx.setfont(3)
  UI.label(16, 58, "Filter:", UI.colors.muted)
  mode_btn("mb", 60, 54, 88, "Bypass", "bypass")
  mode_btn("mp", 154, 54, 88, "Params", "params")
  mode_btn("mf", 248, 54, 88, "Full", "full")

  local sel_bg = selected_only and UI.colors.selected or UI.colors.panel
  if UI.button("sel", w - 168, 54, 152, 26, selected_only and "Selected tracks" or "All eligible", { bg = sel_bg }) then
    selected_only = not selected_only
    persist_meta()
  end

  local top = 92
  local row_h = 52
  local bottom_bar = 56
  local list_h = h - top - bottom_bar - 8

  UI.fill_rect(8, top, w - 16, list_h, UI.colors.panel)
  UI.stroke_rect(8, top, w - 16, list_h, UI.colors.border)

  if #snaps == 0 then
    gfx.setfont(1)
    UI.label(24, top + 24, "No snapshots — press + to store the current FX state.", UI.colors.muted)
  end

  for i, snap in ipairs(snaps) do
    local y = top + 4 + (i - 1) * row_h
    if y + row_h > top + list_h then break end
    local bg = (i == selected) and UI.colors.selected or ((i % 2 == 0) and UI.colors.row_alt or UI.colors.panel)
    UI.fill_rect(10, y, w - 20, row_h - 4, bg)
    if i == selected then
      UI.fill_rect(10, y, 3, row_h - 4, UI.colors.accent)
    end

    local hover = gfx.mouse_x >= 10 and gfx.mouse_x <= w - 10 and gfx.mouse_y >= y and gfx.mouse_y <= y + row_h - 4
    local down = gfx.mouse_cap & 1 == 1
    if hover and down and not UI._snap_down then
      if selected == i and UI._last_snap_i == i and (reaper.time_precise() - (UI._last_snap_t or 0) < 0.35) then
        selected = i
        recall()
        UI._last_snap_t = 0
      else
        selected = i
        UI._last_snap_i = i
        UI._last_snap_t = reaper.time_precise()
      end
    end
    if hover then UI._snap_down = down end

    gfx.setfont(1)
    UI.label(24, y + 8, tostring(snap.name or "?"), UI.colors.text)
    local nfx = 0
    if type(snap.tracks) == "table" then
      for _, t in ipairs(snap.tracks) do nfx = nfx + (type(t.fx) == "table" and #t.fx or 0) end
    end
    local has_chain = false
    if type(snap.tracks) == "table" then
      for _, t in ipairs(snap.tracks) do
        if type(t.fxchain) == "string" and t.fxchain:find("<FXCHAIN", 1, true) then has_chain = true break end
      end
    end
    UI.pips(24, y + 32, 8, math.min(8, math.max(1, nfx)), has_chain and nil or 4)
    gfx.setfont(3)
    UI.label(w - 120, y + 10, tostring(snap.mode or "?"), UI.colors.muted)
    UI.label(w - 120, y + 28, nfx .. " FX", UI.colors.muted)
  end

  -- Bottom toolbar (LP-style: + / update / recall / delete)
  local by = h - bottom_bar
  UI.fill_rect(0, by, w, bottom_bar, UI.colors.header)
  UI.hline(0, by, w, UI.colors.border)

  if UI.button("add", 12, by + 12, 44, 32, "+", { bg = UI.colors.go, fg = UI.colors.go_fg }) then
    capture()
  end
  if UI.button("upd", 64, by + 12, 44, 32, "↻", { bg = UI.colors.panel2 }) then
    update_selected()
  end
  if UI.go_button("rec", 116, by + 12, 120, 32, "RECALL") then
    recall()
  end
  if UI.button("del", w - 56, by + 12, 44, 32, "⌫", { bg = UI.colors.danger }) then
    delete_selected()
  end
  gfx.setfont(3)
  UI.label(250, by + 20, status, UI.colors.muted)

  if gfx.mouse_cap & 1 == 0 then UI._snap_down = false end

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
