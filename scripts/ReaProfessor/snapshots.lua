-- @description ReaProfessor - Global Snapshots (LiveProfessor 2–style)
-- @version 0.3.9
-- @author JewishBidoof
-- @noindex
-- @about Global snapshots with filter, update, fire-cue link, double-click recall.

local res = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/"
local src = debug.getinfo(1, "S").source
local script_dir = (src:sub(1, 1) == "@" and src:sub(2):match("(.+[\\/])")) or res
package.path = script_dir .. "lib/?.lua;" .. res .. "lib/?.lua;" .. package.path

local UI = require("ui")
local Data = require("data")
local Commands = require("commands")
local Config = require("config")

local snaps = Data.load_snapshots()
local meta = Data.load_meta()
local cues = Data.load_cues()
local selected = 1
local mode = meta.snapshot_mode or "full"
local selected_only = meta.selected_only and true or false
local show_options = false
local running = true
local status = Config.actions_enabled() and "" or "Prototype — Capture/Recall disabled"

-- Highlight last recalled
for i, s in ipairs(snaps) do
  if meta.last_snapshot and s.name == meta.last_snapshot then selected = i break end
end

local function persist_meta()
  if not Config.actions_enabled() then return end
  meta.snapshot_mode = mode
  meta.selected_only = selected_only
  Data.save_meta(meta)
end

local function capture()
  if not Config.actions_enabled() then return Config.deny_action("Snapshot Capture") end
  local retval, name = reaper.GetUserInputs("Create global snapshot", 1, "Name:,extrawidth=200", "Snapshot " .. tostring(#snaps + 1))
  if not retval or name == "" then return end
  local snap = Data.capture_snapshot(name, { mode = mode, selected_only = selected_only })
  snap.fire_cue = ""
  snap.color = 0
  snaps[#snaps + 1] = snap
  Data.save_snapshots(snaps)
  selected = #snaps
  persist_meta()
  status = "Created '" .. name .. "'"
end

local function update_selected()
  if not Config.actions_enabled() then return Config.deny_action("Update Snapshot") end
  local prev = snaps[selected]
  if not prev then return end
  local snap = Data.capture_snapshot(prev.name, { mode = mode, selected_only = selected_only })
  snap.id = prev.id or snap.id
  snap.fire_cue = prev.fire_cue
  snap.color = prev.color
  snaps[selected] = snap
  Data.save_snapshots(snaps)
  status = "Updated '" .. tostring(prev.name) .. "'"
end

local function recall()
  if not Config.actions_enabled() then return Config.deny_action("Snapshot Recall") end
  local snap = snaps[selected]
  if not snap then return end
  Data.recall_snapshot(snap, { selected_only = selected_only })
  meta.last_snapshot = snap.name
  Data.save_meta(meta)
  local ok2, msg2 = Commands.snap_fire_linked_cue(snap)
  status = "Recalled '" .. tostring(snap.name) .. "'"
  if msg2 then status = status .. " · " .. msg2 end
  if ok2 == false and msg2 then status = status .. " (!)" end
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

local function link_fire_cue()
  if not snaps[selected] then return end
  local cur = snaps[selected].fire_cue or ""
  local retval, val = reaper.GetUserInputs(
    "Fire cue on recall (LP)",
    1,
    "Cue name or # (blank=none):,extrawidth=220",
    tostring(cur)
  )
  if not retval then return end
  val = (val or ""):match("^%s*(.-)%s*$")
  snaps[selected].fire_cue = val
  Data.save_snapshots(snaps)
  status = val ~= "" and ("Fire cue → " .. val) or "Fire cue cleared"
end

local function cycle_color()
  if not snaps[selected] then return end
  snaps[selected].color = ((snaps[selected].color or 0) + 1) % 6
  Data.save_snapshots(snaps)
end

local COLOR_PIP = {
  {0.30, 0.78, 0.42},
  {0.35, 0.72, 0.95},
  {0.95, 0.55, 0.18},
  {0.86, 0.28, 0.38},
  {0.78, 0.62, 0.18},
  {0.55, 0.45, 0.75},
}

UI.init("ReaProfessor · Global Snapshots", 540, 600, 0)

local function mode_btn(id, x, y, w, label, value)
  local bg = (mode == value) and UI.colors.selected or UI.colors.panel
  if UI.button(id, x, y, w, 24, label, { bg = bg }) then
    mode = value
    persist_meta()
  end
end

local function draw()
  local w, h = gfx.w, gfx.h
  UI.fill_rect(0, 0, w, h, UI.colors.bg)
  UI.header_bar(w, "Global Snapshots", "Double-click to recall  ·  Alt+style filters below")

  gfx.setfont(3)
  UI.label(16, 56, "Filter:", UI.colors.muted)
  mode_btn("mb", 58, 52, 80, "Bypass", "bypass")
  mode_btn("mp", 144, 52, 80, "Params", "params")
  mode_btn("mf", 230, 52, 80, "Full", "full")

  local sel_bg = selected_only and UI.colors.selected or UI.colors.panel
  if UI.button("sel", w - 280, 52, 130, 24, selected_only and "Selected tr." or "All eligible", { bg = sel_bg }) then
    selected_only = not selected_only
    persist_meta()
  end
  if UI.button("opt", w - 140, 52, 124, 24, show_options and "Options ▾" or "Options ▸") then
    show_options = not show_options
  end

  local opt_h = show_options and 56 or 0
  if show_options then
    UI.fill_rect(8, 82, w - 16, 50, UI.colors.panel)
    UI.stroke_rect(8, 82, w - 16, 50, UI.colors.border)
    gfx.setfont(3)
    local snap = snaps[selected]
    local fc = snap and (snap.fire_cue or "") or ""
    UI.label(16, 90, "Fire cue on recall: " .. (fc ~= "" and fc or "(none)"), UI.colors.text)
    if UI.button("fc", 16, 108, 100, 20, "Select…") then link_fire_cue() end
    if UI.button("fcc", 124, 108, 80, 20, "Clear") then
      if snaps[selected] then snaps[selected].fire_cue = ""; Data.save_snapshots(snaps) end
    end
    UI.label(220, 112, "Color tag:", UI.colors.muted)
    if UI.button("col", 290, 108, 60, 20, "Cycle") then cycle_color() end
  end

  local top = 88 + opt_h
  local row_h = 52
  local bottom_bar = 56
  local list_h = h - top - bottom_bar - 8

  UI.fill_rect(8, top, w - 16, list_h, UI.colors.panel)
  UI.stroke_rect(8, top, w - 16, list_h, UI.colors.border)

  if #snaps == 0 then
    gfx.setfont(1)
    UI.label(24, top + 24, "No snapshots — press + to create a global snapshot.", UI.colors.muted)
  end

  for i, snap in ipairs(snaps) do
    local y = top + 4 + (i - 1) * row_h
    if y + row_h > top + list_h then break end
    local is_last = meta.last_snapshot and snap.name == meta.last_snapshot
    local bg = (i == selected) and UI.colors.selected or (is_last and UI.colors.next_cue or ((i % 2 == 0) and UI.colors.row_alt or UI.colors.panel))
    UI.fill_rect(10, y, w - 20, row_h - 4, bg)
    if i == selected then UI.fill_rect(10, y, 3, row_h - 4, UI.colors.accent) end

    local col = COLOR_PIP[(snap.color or 0) % 6 + 1]
    UI.fill_rect(18, y + 10, 8, 28, col)

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

    gfx.setfont(1)
    UI.label(34, y + 8, tostring(snap.name or "?"), UI.colors.text)
    local nfx = 0
    if type(snap.tracks) == "table" then
      for _, t in ipairs(snap.tracks) do nfx = nfx + (type(t.fx) == "table" and #t.fx or 0) end
    end
    UI.pips(34, y + 32, 10, math.min(10, math.max(1, nfx)))
    gfx.setfont(3)
    UI.label(w - 140, y + 8, tostring(snap.mode or "?"), UI.colors.muted)
    UI.label(w - 140, y + 26, nfx .. " FX", UI.colors.muted)
    if snap.fire_cue and snap.fire_cue ~= "" then
      UI.label(w - 140, y + 40, "→cue", UI.colors.tool_snap)
    end
  end

  if gfx.mouse_cap & 1 == 0 then UI._snap_down = false end

  local by = h - bottom_bar
  UI.fill_rect(0, by, w, bottom_bar, UI.colors.header)
  UI.hline(0, by, w, UI.colors.border)

  -- LP bottom: + / update / recall / delete
  if UI.button("add", 12, by + 12, 40, 32, "+", { bg = UI.colors.go, fg = UI.colors.go_fg }) then capture() end
  if UI.button("upd", 60, by + 12, 40, 32, "↻", { bg = UI.colors.tool_midi, fg = {0.05,0.05,0.1} }) then update_selected() end
  if UI.go_button("rec", 112, by + 12, 110, 32, "RECALL") then recall() end
  if UI.button("del", w - 52, by + 12, 40, 32, "⌫", { bg = UI.colors.danger }) then delete_selected() end
  gfx.setfont(3)
  UI.label(240, by + 20, status, UI.colors.muted)

  local ch = gfx.getchar()
  if ch == 27 or ch < 0 then running = false
  elseif ch == 13 then recall()
  elseif ch == ("c"):byte() or ch == ("n"):byte() then capture()
  elseif ch == ("u"):byte() then update_selected()
  end
end

local function loop()
  if not running then gfx.quit(); return end
  draw()
  gfx.update()
  reaper.defer(loop)
end

loop()
