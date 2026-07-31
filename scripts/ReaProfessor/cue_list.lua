-- @description ReaProfessor - Cue List (LiveProfessor 2–style)
-- @version 0.3.9
-- @author JewishBidoof
-- @noindex
-- @about Hierarchical cues with nested actions, tool palette, inspector, GO NEXT.

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
local selected_action = 0 -- 0 = cue itself
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

local function persist()
  Data.save_cues(cues)
  meta.cue_index = selected
  Data.save_meta(meta)
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

local function add_empty_cue()
  if not Config.actions_enabled() then return Config.deny_action("Add Cue") end
  local cue = Data.new_cue("Cue " .. tostring(#cues + 1))
  cues[#cues + 1] = cue
  selected = #cues
  selected_action = 0
  persist()
  set_status("Added empty cue")
end

--- Capture full FX as snapshot action inside a new (or selected) cue — LP camera tool.
local function add_snapshot_action(into_selected)
  if not Config.actions_enabled() then return Config.deny_action("Add Snapshot Action") end
  local default_name = "Snapshot " .. tostring(#snaps + 1)
  local retval, name = reaper.GetUserInputs("Snapshot action", 1, "Snapshot name:,extrawidth=220", default_name)
  if not retval or name == "" then return end

  local snap = Data.capture_snapshot(name, {
    mode = "full",
    selected_only = meta.selected_only and true or false,
  })
  snaps[#snaps + 1] = snap
  Data.save_snapshots(snaps)

  local cue
  if into_selected and cues[selected] then
    cue = Data.normalize_cue(cues[selected])
  else
    cue = Data.new_cue(name)
    cues[#cues + 1] = cue
    selected = #cues
  end
  cue.actions[#cue.actions + 1] = {
    kind = "snapshot",
    snapshot = name,
    label = name,
  }
  cue.payload = cue.payload or {}
  cue.payload.snapshot = name
  cue.kind = "snapshot"
  cues[selected] = cue
  selected_action = #cue.actions
  persist()
  set_status("Snapshot action → " .. name, true)
end

local function add_midi_action()
  if not Config.actions_enabled() then return Config.deny_action("Add MIDI Action") end
  if not cues[selected] then add_empty_cue() end
  local cue = Data.normalize_cue(cues[selected])
  local retval, vals = reaper.GetUserInputs("MIDI action", 3, "Channel,Note,Velocity", "1,36,100")
  if not retval then return end
  local ch, note, vel = vals:match("([^,]+),([^,]+),([^,]+)")
  cue.actions[#cue.actions + 1] = {
    kind = "midi",
    type = "note_on",
    channel = tonumber(ch) or 1,
    note = tonumber(note) or 36,
    velocity = tonumber(vel) or 100,
    label = string.format("MIDI ch%s note%s", tostring(ch), tostring(note)),
  }
  cues[selected] = cue
  selected_action = #cue.actions
  persist()
  set_status("MIDI action added")
end

local function add_comment_action()
  if not Config.actions_enabled() then return Config.deny_action("Add Comment") end
  if not cues[selected] then add_empty_cue() end
  local cue = Data.normalize_cue(cues[selected])
  local retval, text = reaper.GetUserInputs("Comment action", 1, "Text:,extrawidth=260", "")
  if not retval or text == "" then return end
  cue.actions[#cue.actions + 1] = { kind = "comment", label = text }
  cues[selected] = cue
  selected_action = #cue.actions
  persist()
end

local function delete_selected()
  if not Config.actions_enabled() then return Config.deny_action("Delete") end
  local cue = cues[selected]
  if not cue then return end
  if selected_action > 0 and cue.actions and cue.actions[selected_action] then
    table.remove(cue.actions, selected_action)
    selected_action = math.max(0, math.min(selected_action, #cue.actions))
    cues[selected] = cue
    persist()
    set_status("Deleted action")
    return
  end
  table.remove(cues, selected)
  selected = math.max(1, math.min(selected, #cues))
  selected_action = 0
  persist()
  set_status("Deleted cue")
end

local function rename_cue()
  if not Config.actions_enabled() then return Config.deny_action("Rename") end
  local cue = cues[selected]
  if not cue then return end
  local retval, new_name = reaper.GetUserInputs("Rename cue", 1, "Name:,extrawidth=200", cue.name or "")
  if retval and new_name ~= "" then
    cue.name = new_name
    persist()
  end
end

local function edit_timing(field)
  if not Config.actions_enabled() then return end
  local cue = cues[selected]
  if not cue then return end
  local cur = Data.format_ms(cue[field] or 0)
  local retval, val = reaper.GetUserInputs("Edit " .. field, 1, "Time (mm:ss:cs or ms):,extrawidth=160", cur)
  if not retval then return end
  cue[field] = Data.parse_time_input(val)
  persist()
end

UI.init("ReaProfessor · Cue List", 700, 680, 0)

local CUE_H = 28
local ACT_H = 26
local TOOL = 28

local function draw()
  local w, h = gfx.w, gfx.h
  UI.fill_rect(0, 0, w, h, UI.colors.bg)

  -- Title
  UI.fill_rect(0, 0, w, 36, UI.colors.header)
  gfx.setfont(2)
  UI.label(12, 8, "Cue List", UI.colors.text)
  gfx.setfont(3)
  UI.label(110, 12, "tools add actions into cues  ·  Space = GO NEXT", UI.colors.muted)

  -- Tool palette (LP style)
  local ty = 42
  UI.fill_rect(0, ty, w, TOOL + 12, UI.colors.panel)
  UI.hline(0, ty + TOOL + 12, w, UI.colors.border)
  local tx = 10
  if UI.tool_btn("tq", tx, ty + 6, TOOL, "Q", UI.colors.tool_q) then add_empty_cue() end
  tx = tx + TOOL + 6
  if UI.tool_btn("ts", tx, ty + 6, TOOL, "S", UI.colors.tool_snap) then
    add_snapshot_action(false) -- new cue + snapshot
  end
  tx = tx + TOOL + 6
  if UI.tool_btn("tS", tx, ty + 6, TOOL, "+S", UI.colors.tool_snap) then
    add_snapshot_action(true) -- into selected
  end
  tx = tx + TOOL + 6
  if UI.tool_btn("tm", tx, ty + 6, TOOL, "M", UI.colors.tool_midi) then add_midi_action() end
  tx = tx + TOOL + 6
  if UI.tool_btn("tn", tx, ty + 6, TOOL, "…", UI.colors.tool_note) then add_comment_action() end
  gfx.setfont(3)
  UI.label(tx + TOOL + 12, ty + 12, "Q cue · S new+snap · +S into cue · M MIDI · … comment", UI.colors.muted)

  local list_top = ty + TOOL + 14
  local inspector_h = 110
  local bottom_h = 72
  local list_h = h - list_top - inspector_h - bottom_h

  UI.fill_rect(8, list_top, w - 16, list_h, UI.colors.panel)
  UI.stroke_rect(8, list_top, w - 16, list_h, UI.colors.border)

  -- Column headers
  gfx.setfont(3)
  UI.fill_rect(8, list_top, w - 16, 20, UI.colors.header)
  UI.label(36, list_top + 3, "#  NAME", UI.colors.muted)
  UI.label(w - 200, list_top + 3, "FADE", UI.colors.muted)
  UI.label(w - 130, list_top + 3, "PRE", UI.colors.muted)
  UI.label(w - 70, list_top + 3, "POST", UI.colors.muted)

  if #cues == 0 then
    gfx.setfont(1)
    UI.label(24, list_top + 40, "Empty list — press Q or S to add a cue.", UI.colors.muted)
  end

  local y = list_top + 22
  local next_idx = meta.cue_index or 1
  local max_y = list_top + list_h - 4

  for i, cue in ipairs(cues) do
    if y > max_y then break end
    cue = Data.normalize_cue(cue)
    cues[i] = cue
    local is_sel = (i == selected and selected_action == 0)
    local is_next = (i == next_idx)
    local bg = is_sel and UI.colors.selected or (is_next and UI.colors.next_cue or UI.colors.panel2)
    UI.fill_rect(10, y, w - 20, CUE_H - 2, bg)
    if is_sel then UI.fill_rect(10, y, 3, CUE_H - 2, UI.colors.accent) end

    -- Expand triangle
    local tri = cue.expanded and "▼" or "▶"
    gfx.setfont(3)
    UI.label(16, y + 6, tri, UI.colors.muted)
    local tri_hit = gfx.mouse_x >= 14 and gfx.mouse_x <= 34
                 and gfx.mouse_y >= y and gfx.mouse_y <= y + CUE_H
    local down = gfx.mouse_cap & 1 == 1
    if tri_hit and down and not UI._cue_down then
      cue.expanded = not cue.expanded
      persist()
    end

    gfx.setfont(4)
    UI.label(40, y + 7, tostring(i), UI.colors.tool_q)
    gfx.setfont(1)
    UI.label(64, y + 5, cue.name or "Cue", UI.colors.text)
    gfx.setfont(4)
    UI.label(w - 200, y + 7, Data.format_ms(cue.fade_ms), UI.colors.muted)
    UI.label(w - 130, y + 7, Data.format_ms(cue.pre_wait_ms), UI.colors.muted)
    UI.label(w - 70, y + 7, Data.format_ms(cue.post_wait_ms), UI.colors.muted)

    local hit = gfx.mouse_x >= 36 and gfx.mouse_x <= w - 12
            and gfx.mouse_y >= y and gfx.mouse_y <= y + CUE_H - 2
    if hit and down and not UI._cue_down then
      if selected == i and selected_action == 0 and UI._last_cue_i == i
         and (reaper.time_precise() - (UI._last_cue_t or 0) < 0.35) then
        go_to(i)
        UI._last_cue_t = 0
      else
        selected = i
        selected_action = 0
        meta.cue_index = selected
        Data.save_meta(meta)
        UI._last_cue_i = i
        UI._last_cue_t = reaper.time_precise()
      end
    end

    y = y + CUE_H

    if cue.expanded then
      for ai, act in ipairs(cue.actions or {}) do
        if y > max_y then break end
        local abg = (i == selected and selected_action == ai) and UI.colors.selected or UI.colors.row_alt
        UI.fill_rect(28, y, w - 38, ACT_H - 2, abg)
        local icon = "S"
        local ic = UI.colors.tool_snap
        if act.kind == "midi" then icon = "M"; ic = UI.colors.tool_midi
        elseif act.kind == "comment" then icon = "…"; ic = UI.colors.tool_note
        elseif act.kind == "action" then icon = "A"; ic = UI.colors.tool_cmd end
        UI.fill_rect(34, y + 4, 16, 16, ic)
        gfx.setfont(3)
        UI.label(36, y + 5, icon, {0.05, 0.05, 0.05})
        local label = act.label or act.snapshot or act.kind or "?"
        local missing = act.kind == "snapshot" and not snapshot_exists(act.snapshot or act.label)
        UI.label(56, y + 5, label .. (missing and "  !missing" or ""), missing and UI.colors.danger or UI.colors.text)

        local ahit = gfx.mouse_x >= 28 and gfx.mouse_x <= w - 12
                 and gfx.mouse_y >= y and gfx.mouse_y <= y + ACT_H - 2
        if ahit and down and not UI._cue_down then
          selected = i
          selected_action = ai
          meta.cue_index = selected
          Data.save_meta(meta)
        end
        y = y + ACT_H
      end
    end
  end

  if gfx.mouse_cap & 1 == 0 then UI._cue_down = false else UI._cue_down = true end

  -- Inspector (LP bottom properties)
  local iy = list_top + list_h + 4
  UI.fill_rect(8, iy, w - 16, inspector_h - 8, UI.colors.panel)
  UI.stroke_rect(8, iy, w - 16, inspector_h - 8, UI.colors.border)
  gfx.setfont(3)
  UI.label(16, iy + 6, "Cue", UI.colors.accent)

  local cue = cues[selected]
  if cue then
    cue = Data.normalize_cue(cue)
    UI.label(16, iy + 28, "No.", UI.colors.muted)
    UI.field(40, iy + 24, 36, 22, tostring(selected))
    UI.label(86, iy + 28, "Name", UI.colors.muted)
    UI.field(126, iy + 24, 180, 22, cue.name or "")
    if UI.button("ren", 314, iy + 24, 70, 22, "Edit") then rename_cue() end

    UI.label(16, iy + 56, "Fade", UI.colors.muted)
    UI.field(50, iy + 52, 80, 22, Data.format_ms(cue.fade_ms))
    if UI.button("fade", 134, iy + 52, 40, 22, "…") then edit_timing("fade_ms") end
    UI.label(186, iy + 56, "Pre", UI.colors.muted)
    UI.field(214, iy + 52, 80, 22, Data.format_ms(cue.pre_wait_ms))
    if UI.button("pre", 298, iy + 52, 40, 22, "…") then edit_timing("pre_wait_ms") end
    UI.label(348, iy + 56, "Post", UI.colors.muted)
    UI.field(382, iy + 52, 80, 22, Data.format_ms(cue.post_wait_ms))
    if UI.button("post", 466, iy + 52, 40, 22, "…") then edit_timing("post_wait_ms") end

    if UI.checkbox("fall", 16, iy + 82, "Fire all actions in the cue", cue.fire_all ~= false) then
      cue.fire_all = not (cue.fire_all ~= false)
      cues[selected] = cue
      persist()
    end
    if UI.checkbox("midi", 280, iy + 82, "Trigger by MIDI", cue.trigger_midi) then
      cue.trigger_midi = not cue.trigger_midi
      cues[selected] = cue
      persist()
    end
  else
    UI.label(16, iy + 36, "No cue selected", UI.colors.muted)
  end

  -- Bottom transport
  local by = h - bottom_h
  UI.fill_rect(0, by, w, bottom_h, UI.colors.header)
  UI.hline(0, by, w, UI.colors.border)
  if UI.go_button("go", 12, by + 14, 160, 44, "GO NEXT") then go_next() end
  if UI.button("back", 184, by + 20, 72, 32, "BACK") then go_back() end
  if UI.button("fire", 264, by + 20, 72, 32, "Fire") then go_to(selected) end
  if edit_mode and UI.button("del", 344, by + 20, 72, 32, "Delete", { bg = UI.colors.danger }) then
    delete_selected()
  end

  local edit_bg = edit_mode and UI.colors.edit or UI.colors.panel
  if UI.button("edit", w - 200, by + 20, 88, 32, "Edit Mode", {
    bg = edit_bg, fg = edit_mode and {0.1, 0.1, 0.05} or UI.colors.text
  }) then edit_mode = not edit_mode end
  local arm_bg = armed and UI.colors.armed or UI.colors.panel
  if UI.button("arm", w - 100, by + 20, 88, 32, armed and "Armed" or "Safe", { bg = arm_bg }) then
    armed = not armed
  end

  gfx.setfont(3)
  UI.label(430, by + 28, status ~= "" and status or string.format("%d cues", #cues), UI.colors.muted)

  local ch = gfx.getchar()
  if ch == 27 or ch < 0 then running = false
  elseif ch == 32 then go_next()
  elseif ch == 8 then go_back()
  elseif ch == ("q"):byte() then add_empty_cue()
  elseif ch == ("s"):byte() then add_snapshot_action(false)
  end
end

local function loop()
  if not running then gfx.quit(); return end
  draw()
  gfx.update()
  reaper.defer(loop)
end

loop()
