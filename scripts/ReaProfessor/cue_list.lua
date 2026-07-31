-- @description ReaProfessor - Cue List (LiveProfessor-style)
-- @version 0.3.8
-- @author JewishBidoof
-- @noindex
-- @about Ordered cue list with GO NEXT. + CUE captures full FX state and links it.

local res = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/"
local src = debug.getinfo(1, "S").source
local script_dir = (src:sub(1, 1) == "@" and src:sub(2):match("(.+[\\/])")) or res
local alt = reaper.GetResourcePath() .. "/Scripts/Live/ReaProfessor/"
package.path = script_dir .. "lib/?.lua;" .. alt .. "lib/?.lua;" .. res .. "lib/?.lua;" .. package.path

local UI = require("ui")
local Data = require("data")
local Commands = require("commands")
local Config = require("config")

local cues = Data.load_cues()
local meta = Data.load_meta()
local snaps = Data.load_snapshots()
local selected = meta.cue_index or 1
if selected < 1 then selected = 1 end
if selected > #cues then selected = math.max(1, #cues) end
local status = ""
local running = true
local edit_mode = true
local armed = true

local function set_status(msg, also_console)
  status = tostring(msg or "")
  if also_console and status ~= "" then
    reaper.ShowConsoleMsg("[ReaProfessor] " .. status .. "\n")
  end
end

local function refresh()
  cues = Data.load_cues()
  meta = Data.load_meta()
  snaps = Data.load_snapshots()
  selected = meta.cue_index or selected
  if selected > #cues then selected = math.max(1, #cues) end
  if selected < 1 then selected = 1 end
end

local function snapshot_exists(name)
  if not name or name == "" then return false end
  for _, s in ipairs(snaps) do
    if s.name == name then return true end
  end
  return false
end

local function go_next()
  if not Config.actions_enabled() then return Config.deny_action("Cue GO") end
  if not armed then set_status("Disarmed — enable Armed to fire"); return end
  local ok, msg = Commands.cue_go()
  refresh()
  set_status(msg or (ok and "GO" or "GO failed"), not ok)
end

local function go_back()
  if not Config.actions_enabled() then return Config.deny_action("Cue Back") end
  local ok, msg = Commands.cue_back()
  refresh()
  set_status(msg or (ok and "Back" or "Back failed"), not ok)
end

local function go_to(idx)
  if not Config.actions_enabled() then return Config.deny_action("Cue Fire") end
  if not armed then set_status("Disarmed — enable Armed to fire"); return end
  local ok, msg = Commands.cue_goto(idx)
  refresh()
  set_status(msg or (ok and "Fired" or "Fire failed"), not ok)
end

--- Capture current FX as a FULL snapshot and append a cue that points at it.
local function add_cue()
  if not Config.actions_enabled() then return Config.deny_action("Add Cue") end
  local default_name = "Cue " .. tostring(#cues + 1)
  local retval, name = reaper.GetUserInputs(
    "Add cue (captures current FX)",
    1,
    "Name:,extrawidth=220",
    default_name
  )
  if not retval or name == "" then return end

  -- Always full — show cues must restore plugins, not just params on whatever is loaded.
  local snap = Data.capture_snapshot(name, {
    mode = "full",
    selected_only = meta.selected_only and true or false,
  })
  snaps[#snaps + 1] = snap
  Data.save_snapshots(snaps)

  cues[#cues + 1] = {
    id = Data.new_id("cue"),
    name = name,
    kind = "snapshot",
    payload = { snapshot = name },
    notes = "",
  }
  Data.save_cues(cues)
  selected = #cues
  meta.cue_index = selected
  Data.save_meta(meta)
  set_status(string.format("Captured + linked '%s' (full)", name), true)
end

local function link_snapshot()
  if not Config.actions_enabled() then return Config.deny_action("Link Snapshot") end
  local cue = cues[selected]
  if not cue then
    set_status("Select a cue first")
    return
  end

  local cur = (cue.payload and cue.payload.snapshot) or cue.name or ""
  local retval, target = reaper.GetUserInputs(
    "Link cue to snapshot",
    1,
    "Snapshot name or #:,extrawidth=260",
    cur
  )
  if not retval then return end
  target = (target or ""):match("^%s*(.-)%s*$")
  if target == "" then return end

  local as_num = tonumber(target)
  if as_num and snaps[as_num] then
    target = snaps[as_num].name
  end

  if not snapshot_exists(target) then
    local snap = Data.capture_snapshot(target, {
      mode = "full",
      selected_only = meta.selected_only and true or false,
    })
    snaps[#snaps + 1] = snap
    Data.save_snapshots(snaps)
    set_status("Captured missing snapshot '" .. target .. "' (full)", true)
  end

  cue.payload = cue.payload or {}
  cue.payload.snapshot = target
  cue.kind = "snapshot"
  Data.save_cues(cues)
  refresh()
  set_status("Linked cue → " .. target)
end

local function delete_cue()
  if not Config.actions_enabled() then return Config.deny_action("Delete Cue") end
  if #cues == 0 then return end
  table.remove(cues, selected)
  selected = math.max(1, math.min(selected, #cues))
  Data.save_cues(cues)
  meta.cue_index = selected
  Data.save_meta(meta)
  set_status("Deleted cue")
end

local function rename_selected()
  if not Config.actions_enabled() then return Config.deny_action("Rename Cue") end
  if not cues[selected] then return end
  local cue = cues[selected]
  local retval, new_name = reaper.GetUserInputs("Rename cue", 1, "Name:,extrawidth=200", cue.name)
  if retval and new_name ~= "" then
    cue.name = new_name
    Data.save_cues(cues)
    set_status("Renamed cue")
  end
end

UI.init("ReaProfessor · Cue List", 640, 620, 0)
local row_h = 36

local function draw()
  local w, h = gfx.w, gfx.h
  UI.fill_rect(0, 0, w, h, UI.colors.bg)
  UI.header_bar(w, "Cue List", "+ captures full FX · Space / GO NEXT fires")

  -- Tool strip (LP icon bar → labeled tools)
  local ty = 56
  if UI.button("add", 12, ty, 72, 28, "+ CUE", { bg = UI.colors.panel2 }) then add_cue() end
  if UI.button("link", 92, ty, 88, 28, "Snapshot") then link_snapshot() end
  if edit_mode then
    if UI.button("ren", 188, ty, 72, 28, "Rename") then rename_selected() end
    if UI.button("del", 268, ty, 72, 28, "Delete", { bg = UI.colors.danger }) then delete_cue() end
  end

  local list_top = 96
  local bottom = 88
  local list_h = h - list_top - bottom

  UI.fill_rect(8, list_top, w - 16, list_h, UI.colors.panel)
  UI.stroke_rect(8, list_top, w - 16, list_h, UI.colors.border)

  -- Column headers
  gfx.setfont(3)
  UI.fill_rect(8, list_top, w - 16, 22, UI.colors.header)
  UI.label(20, list_top + 4, "#", UI.colors.muted)
  UI.label(56, list_top + 4, "NAME", UI.colors.muted)
  UI.label(w - 220, list_top + 4, "ACTION", UI.colors.muted)

  if #cues == 0 then
    gfx.setfont(1)
    UI.label(24, list_top + 40, "No cues yet. Build your FX, then + CUE.", UI.colors.muted)
  end

  local rows_top = list_top + 24
  local visible = math.floor((list_h - 24) / row_h)
  for i = 1, math.min(#cues, visible) do
    local y = rows_top + (i - 1) * row_h
    local cue = cues[i]
    local bg = (i == selected) and UI.colors.selected or ((i % 2 == 0) and UI.colors.row_alt or UI.colors.panel)
    UI.fill_rect(10, y, w - 20, row_h - 2, bg)
    if i == selected then
      UI.fill_rect(10, y, 3, row_h - 2, UI.colors.accent)
    end

    local hit = gfx.mouse_x >= 10 and gfx.mouse_x <= w - 10
            and gfx.mouse_y >= y and gfx.mouse_y <= y + row_h - 2
    local down = gfx.mouse_cap & 1 == 1
    if hit and down and not UI._cue_down then
      if selected == i and UI._last_cue_i == i and (reaper.time_precise() - (UI._last_cue_t or 0) < 0.35) then
        selected = i
        meta.cue_index = selected
        Data.save_meta(meta)
        go_to(i)
        UI._last_cue_t = 0
      else
        selected = i
        meta.cue_index = selected
        Data.save_meta(meta)
        UI._last_cue_i = i
        UI._last_cue_t = reaper.time_precise()
      end
    end
    if hit then UI._cue_down = down end

    local target = (cue.payload and cue.payload.snapshot) or cue.name or "—"
    local missing = cue.kind ~= "action" and not snapshot_exists(target)

    gfx.setfont(4)
    UI.label(20, y + 10, string.format("%d", i), UI.colors.muted)
    gfx.setfont(1)
    UI.label(56, y + 10, cue.name or "?", UI.colors.text)
    gfx.setfont(3)
    local action = "Snapshot · " .. tostring(target)
    if missing then action = action .. "  !missing" end
    UI.label(w - 220, y + 10, action, missing and UI.colors.danger or UI.colors.muted)
  end

  -- Bottom action bar (LP: Go Next + Edit Mode + Armed)
  local by = h - bottom
  UI.fill_rect(0, by, w, bottom, UI.colors.header)
  UI.hline(0, by, w, UI.colors.border)

  if UI.go_button("go", 12, by + 18, 160, 44, "GO NEXT") then
    go_next()
  end
  if UI.button("back", 184, by + 24, 72, 32, "BACK") then
    go_back()
  end
  if UI.button("fire", 264, by + 24, 88, 32, "Fire") then
    go_to(selected)
  end

  local edit_bg = edit_mode and UI.colors.edit or UI.colors.panel
  if UI.button("edit", w - 200, by + 24, 88, 32, "Edit Mode", { bg = edit_bg, fg = edit_mode and {0.1, 0.1, 0.05} or UI.colors.text }) then
    edit_mode = not edit_mode
  end
  local arm_bg = armed and UI.colors.armed or UI.colors.panel
  if UI.button("arm", w - 100, by + 24, 88, 32, armed and "Armed" or "Safe", { bg = arm_bg }) then
    armed = not armed
  end

  gfx.setfont(3)
  local footer = string.format("%d cues · %d snaps", #cues, #snaps)
  if status ~= "" then footer = status end
  UI.label(370, by + 32, footer, UI.colors.muted)

  if gfx.mouse_cap & 1 == 0 then UI._cue_down = false end

  local ch = gfx.getchar()
  if ch == 27 or ch < 0 then
    running = false
  elseif ch == 32 then
    go_next()
  elseif ch == 8 then
    go_back()
  elseif ch == ("n"):byte() then
    add_cue()
  end
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
