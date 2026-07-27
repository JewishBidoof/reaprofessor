-- @description ReaProfessor - Cue List
-- @version 0.3.5
-- @author JewishBidoof
-- @noindex
-- @about Ordered cue list with GO / Back / Jump. + CUE captures FX state and links it.

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
  local ok, msg = Commands.cue_goto(idx)
  refresh()
  set_status(msg or (ok and "Fired" or "Fire failed"), not ok)
end

--- Capture current FX state as a snapshot and append a cue that points at it.
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

  local mode = meta.snapshot_mode or "params"
  local snap = Data.capture_snapshot(name, {
    mode = mode,
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
  set_status(string.format("Captured + linked '%s' (%s)", name, mode), true)
end

--- Re-bind selected cue to an existing snapshot (or capture if missing).
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
    local mode = meta.snapshot_mode or "params"
    local snap = Data.capture_snapshot(target, {
      mode = mode,
      selected_only = meta.selected_only and true or false,
    })
    snaps[#snaps + 1] = snap
    Data.save_snapshots(snaps)
    set_status("Captured missing snapshot '" .. target .. "'", true)
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

UI.init("ReaProfessor · Cue List", 820, 540, 0)
local row_h = 28
local list_top = 72

local function draw()
  local w, h = gfx.w, gfx.h
  UI.fill_rect(0, 0, w, h, UI.colors.bg)

  gfx.setfont(2)
  UI.label(16, 14, "CUE LIST", UI.colors.accent)
  gfx.setfont(3)
  UI.label(140, 22, "+ CUE captures current FX as a snapshot and links it", UI.colors.muted)

  if UI.button("go", w - 280, 12, 80, 36, "GO", { bg = UI.colors.go, fg = {0.05, 0.1, 0.05} }) then
    go_next()
  end
  if UI.button("back", w - 190, 12, 80, 36, "BACK") then
    go_back()
  end
  if UI.button("add", w - 100, 12, 84, 36, "+ CUE") then
    add_cue()
  end

  gfx.setfont(3)
  UI.fill_rect(12, list_top - 22, w - 24, 20, UI.colors.panel)
  UI.label(24, list_top - 20, "#", UI.colors.muted)
  UI.label(56, list_top - 20, "NAME", UI.colors.muted)
  UI.label(w - 300, list_top - 20, "KIND", UI.colors.muted)
  UI.label(w - 200, list_top - 20, "SNAPSHOT", UI.colors.muted)

  local visible = math.floor((h - list_top - 72) / row_h)
  if #cues == 0 then
    gfx.setfont(1)
    UI.label(24, list_top + 8, "No cues yet. Build your FX, then click + CUE to capture & fire later with GO.", UI.colors.muted)
  end

  for i = 1, math.min(#cues, visible) do
    local y = list_top + (i - 1) * row_h
    local cue = cues[i]
    local bg = (i == selected) and UI.colors.selected or ((i % 2 == 0) and UI.colors.row_alt or UI.colors.bg)
    UI.fill_rect(12, y, w - 24, row_h - 2, bg)

    local hit = gfx.mouse_x >= 12 and gfx.mouse_x <= w - 12
            and gfx.mouse_y >= y and gfx.mouse_y <= y + row_h - 2
    if hit and gfx.mouse_cap & 1 == 1 then
      selected = i
      meta.cue_index = selected
      Data.save_meta(meta)
    end
    if hit and gfx.mouse_cap & 2 == 2 then
      selected = i
      rename_selected()
    end

    local target = (cue.payload and cue.payload.snapshot) or cue.name or "—"
    local missing = cue.kind ~= "action" and not snapshot_exists(target)

    gfx.setfont(1)
    UI.label(24, y + 5, string.format("%02d", i), UI.colors.muted)
    UI.label(56, y + 5, cue.name or "?", UI.colors.text)
    UI.label(w - 300, y + 5, cue.kind or "snapshot", UI.colors.muted)
    UI.label(w - 200, y + 5, tostring(target) .. (missing and "  !missing" or ""), missing and UI.colors.danger or UI.colors.muted)
  end

  if UI.button("ren", 12, h - 56, 90, 32, "Rename") then rename_selected() end
  if UI.button("link", 110, h - 56, 120, 32, "Link snap") then link_snapshot() end
  if UI.button("del", 238, h - 56, 90, 32, "Delete", { bg = UI.colors.danger }) then delete_cue() end
  if UI.button("fire", 336, h - 56, 120, 32, "Fire Selected") then go_to(selected) end

  gfx.setfont(3)
  local footer = string.format("%d cues  ·  %d snapshots  ·  Space=GO", #cues, #snaps)
  if status ~= "" then footer = footer .. "  ·  " .. status end
  UI.label(470, h - 46, footer, UI.colors.muted)

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
