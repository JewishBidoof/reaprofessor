-- @description ReaProfessor - Cue List
-- @version 0.5.1
-- @author JewishBidoof
-- @noindex
-- @about Single-screen cue list: recall FX/send snapshots. Go / Back / Fire Selected.

local res = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/"
local src = debug.getinfo(1, "S").source
local script_dir = (src:sub(1, 1) == "@" and src:sub(2):match("(.+[\\/])")) or res
local alt = reaper.GetResourcePath() .. "/Scripts/Live/ReaProfessor/"
package.path = script_dir .. "lib/?.lua;" .. alt .. "lib/?.lua;" .. res .. "lib/?.lua;" .. package.path

local UI = require("ui")
local Data = require("data")
local Commands = require("commands")
local Config = require("config")
local MIDI = require("midi")
local OSC = require("osc")
local Routing = require("routing")

local cues = Data.load_cues()
local meta = Data.load_meta()
local snaps = Data.load_snapshots()
local selected = meta.cue_index or 1
if selected < 1 then selected = 1 end
if selected > #cues then selected = math.max(1, #cues) end

local status = ""
local running = true
local edit_mode = meta.edit_mode and true or false
local scroll = 0
local midi_ts = 0
local learn_target = nil -- "go"|"back"|"fire"|"cue"|nil
local learn_ts = 0

local function set_status(msg, also_console)
  status = tostring(msg or "")
  if also_console and status ~= "" then
    reaper.ShowConsoleMsg("[ReaProfessor] " .. status .. "\n")
  end
end

local function persist()
  Data.save_cues(cues)
  meta.cue_index = selected
  meta.edit_mode = edit_mode
  Data.save_meta(meta)
end

local function refresh()
  cues = Data.load_cues()
  meta = Data.load_meta()
  snaps = Data.load_snapshots()
  selected = meta.cue_index or selected
  if selected > #cues then selected = math.max(1, #cues) end
  if selected < 1 then selected = 1 end
  edit_mode = meta.edit_mode and true or false
end

local function find_snap(name)
  if not name or name == "" then return nil end
  for _, s in ipairs(snaps) do
    if s.name == name then return s end
  end
  return nil
end

local function capture_for_cue(cue, name)
  local snap = Data.capture_snapshot(name, { mode = "full", selected_only = false })
  -- Upsert into snaps library by name
  local replaced = false
  for i, s in ipairs(snaps) do
    if s.name == snap.name then
      snaps[i] = snap
      replaced = true
      break
    end
  end
  if not replaced then snaps[#snaps + 1] = snap end
  Data.save_snapshots(snaps)
  cue.snapshot_name = snap.name
  cue.kind = "cue"
  return snap
end

local function add_cue(as_dummy)
  if not Config.actions_enabled() then return Config.deny_action("Add Cue") end
  local n = #cues + 1
  local name = as_dummy and ("Dummy " .. n) or ("Cue " .. n)
  local cue = Data.new_cue(name, { kind = as_dummy and "dummy" or "cue" })
  if not as_dummy then
    capture_for_cue(cue, name)
  end
  cues[#cues + 1] = cue
  selected = #cues
  persist()
  set_status(as_dummy and "Added dummy cue" or ("Captured " .. name), true)
end

local function update_selected_snapshot()
  if not Config.actions_enabled() then return Config.deny_action("Update Cue") end
  local cue = cues[selected]
  if not cue then return end
  cue = Data.normalize_cue(cue)
  if cue.kind == "dummy" then
    set_status("Dummy cue has no snapshot")
    return
  end
  local name = cue.snapshot_name
  if not name or name == "" then name = cue.name or ("Cue " .. selected) end
  capture_for_cue(cue, name)
  cues[selected] = cue
  persist()
  set_status("Updated snapshot → " .. name, true)
end

local function delete_selected()
  if not edit_mode then return end
  if not Config.actions_enabled() then return Config.deny_action("Delete") end
  if not cues[selected] then return end
  table.remove(cues, selected)
  selected = math.max(1, math.min(selected, #cues))
  persist()
  set_status("Deleted cue")
end

local function move_selected(delta)
  if not edit_mode then return end
  local j = selected + delta
  if j < 1 or j > #cues then return end
  cues[selected], cues[j] = cues[j], cues[selected]
  selected = j
  persist()
end

local function rename_selected()
  local cue = cues[selected]
  if not cue then return end
  local ok, name = reaper.GetUserInputs("Rename cue", 1, "Name:,extrawidth=220", cue.name or "")
  if ok and name ~= "" then
    cue.name = name
    persist()
  end
end

local function edit_cue_osc()
  local cue = cues[selected]
  if not cue then return end
  local cur = cue.osc or ""
  local def = Data.default_cue_osc(meta, selected)
  local ok, val = reaper.GetUserInputs(
    "Cue OSC", 1,
    "OSC (blank = " .. def .. "):,extrawidth=280",
    cur
  )
  if ok then
    cue.osc = val or ""
    persist()
    set_status("OSC → " .. Data.cue_osc_path(cue, selected, meta))
  end
end

local function edit_cue_midi()
  local cue = cues[selected]
  if not cue then return end
  local m = cue.midi or {}
  local def = string.format("%s,%s,%s,%s",
    m.type or "note_on",
    tostring(m.note or m.cc or 36),
    tostring(m.velocity or 100),
    tostring(m.channel or 0))
  local ok, vals = reaper.GetUserInputs(
    "Cue MIDI trigger", 4,
    "Type (note_on/cc),Note or CC #,Velocity/Value,Channel (0=global)",
    def
  )
  if not ok then return end
  local typ, num, vel, ch = vals:match("([^,]+),([^,]+),([^,]+),([^,]+)")
  typ = (typ or "note_on"):match("^%s*(.-)%s*$")
  if typ == "" or typ == "none" or typ == "-" then
    cue.midi = nil
  else
    cue.midi = {
      type = typ,
      note = (typ == "cc") and nil or (tonumber(num) or 36),
      cc = (typ == "cc") and (tonumber(num) or 1) or nil,
      velocity = tonumber(vel) or 100,
      channel = tonumber(ch) or 0,
    }
  end
  persist()
  set_status(cue.midi and "MIDI assigned" or "MIDI cleared")
end

local function edit_parent_osc()
  local ok, val = reaper.GetUserInputs(
    "Parent OSC", 1, "Parent OSC prefix:,extrawidth=240", meta.osc_parent or "/ReaProfessor"
  )
  if ok and val and val ~= "" then
    if val:sub(1, 1) ~= "/" then val = "/" .. val end
    meta.osc_parent = val:gsub("/+$", "")
    persist()
    set_status("Parent OSC → " .. meta.osc_parent)
  end
end

local function cycle_midi_channel()
  -- 0=omni, then 1..16, wrap
  meta.midi_channel = (tonumber(meta.midi_channel) or 0) + 1
  if meta.midi_channel > 16 then meta.midi_channel = 0 end
  persist()
end

local function midi_channel_label()
  local ch = tonumber(meta.midi_channel) or 0
  if ch <= 0 then return "MIDI: Omni" end
  return string.format("MIDI: Ch %d", ch)
end

local function describe_midi(m)
  if type(m) ~= "table" then return "—" end
  if m.type == "cc" then
    return string.format("CC%d%s", m.cc or 0, (m.channel and m.channel > 0) and ("/ch" .. m.channel) or "")
  end
  return string.format("N%d%s", m.note or 0, (m.channel and m.channel > 0) and ("/ch" .. m.channel) or "")
end

local function edit_transport_binding(which)
  local t = meta.transport[which] or { midi = nil, osc = "" }
  local cur_osc = t.osc or ""
  local ok, val = reaper.GetUserInputs(
    "Transport " .. which:upper(), 1,
    "OSC path (blank=none). Then Learn MIDI or Cancel:,extrawidth=280",
    cur_osc
  )
  if not ok then return end
  t.osc = val or ""
  meta.transport[which] = t
  persist()
  learn_target = which
  learn_ts = midi_ts
  set_status("Learn MIDI for " .. which:upper() .. " (play a note/CC)…")
end

local function go_next()
  if not Config.actions_enabled() then return Config.deny_action("Go") end
  local ok, msg = Commands.cue_go()
  refresh()
  set_status(msg or (ok and "GO" or "GO failed"), not ok)
end

local function go_back()
  if not Config.actions_enabled() then return Config.deny_action("Back") end
  local ok, msg = Commands.cue_back()
  refresh()
  set_status(msg or (ok and "Back" or "Back failed"), not ok)
end

local function fire_selected()
  if not Config.actions_enabled() then return Config.deny_action("Fire") end
  local ok, msg = Commands.cue_goto(selected)
  refresh()
  set_status(msg or (ok and "Fired" or "Fire failed"), not ok)
end

local function create_channels_popup()
  local ok, msg = Routing.prompt_create_channels()
  if ok then
    set_status(msg, true)
  elseif msg and msg ~= "cancelled" and msg ~= "disabled" then
    set_status(msg, true)
  end
end

local function build_listen_map()
  local map = {}
  for key, cmd in pairs({ go = "cue_go", back = "cue_back", fire = "cue_goto" }) do
    local t = meta.transport[key]
    if t and type(t.midi) == "table" then
      local b = {
        type = t.midi.type or "note_on",
        note = t.midi.note,
        cc = t.midi.cc,
        channel = t.midi.channel,
        threshold = 1,
        command = cmd,
        arg = (cmd == "cue_goto") and selected or nil,
        enabled = true,
      }
      map[#map + 1] = b
    end
  end
  for i, cue in ipairs(cues) do
    cue = Data.normalize_cue(cue)
    if type(cue.midi) == "table" then
      map[#map + 1] = {
        type = cue.midi.type or "note_on",
        note = cue.midi.note,
        cc = cue.midi.cc,
        channel = cue.midi.channel,
        threshold = 1,
        command = "cue_goto",
        arg = i,
        enabled = true,
      }
    end
  end
  return map
end

local function poll_midi()
  if learn_target then
    local ev, ts = MIDI.learn_next(learn_ts)
    learn_ts = ts or learn_ts
    if ev then
      local m = {
        type = ev.type == "cc" and "cc" or "note_on",
        note = ev.note,
        cc = ev.cc,
        velocity = ev.velocity or ev.value or 100,
        channel = 0, -- use global channel filter
      }
      if learn_target == "cue" then
        local cue = cues[selected]
        if cue then
          cue.midi = m
          persist()
          set_status("Cue MIDI learned: " .. describe_midi(m))
        end
      else
        meta.transport[learn_target] = meta.transport[learn_target] or { osc = "" }
        meta.transport[learn_target].midi = m
        persist()
        set_status(learn_target:upper() .. " MIDI learned: " .. describe_midi(m))
      end
      learn_target = nil
    end
    midi_ts = learn_ts
    return
  end

  local map = build_listen_map()
  local cmds
  cmds, midi_ts = MIDI.poll_commands_v2(map, midi_ts, { global_channel = meta.midi_channel })
  for _, c in ipairs(cmds) do
    if c.command == "cue_go" then go_next()
    elseif c.command == "cue_back" then go_back()
    elseif c.command == "cue_goto" then
      local idx = tonumber(c.arg) or selected
      selected = idx
      fire_selected()
    end
  end

  -- OSC queue for transport + cue paths
  for _, item in ipairs(OSC.drain_queue()) do
    local path = item.path
    if not path then goto continue end
    for key, cmd in pairs({ go = true, back = true, fire = true }) do
      local t = meta.transport[key]
      if t and t.osc and t.osc ~= "" and path == t.osc then
        if key == "go" then go_next()
        elseif key == "back" then go_back()
        else fire_selected() end
        goto continue
      end
    end
    for i, cue in ipairs(cues) do
      if path == Data.cue_osc_path(cue, i, meta) then
        selected = i
        fire_selected()
        break
      end
    end
    ::continue::
  end
end

UI.init("ReaProfessor", 720, 720, 0)

local function draw()
  local w, h = UI.dims()
  UI.fill_rect(0, 0, w, h, UI.colors.bg)

  -- Header
  UI.fill_rect(0, 0, w, 56, UI.colors.header)
  UI.hline(0, 56, w, UI.colors.border)
  gfx.setfont(2)
  UI.label(24, 10, "ReaProfessor", UI.colors.text)
  gfx.setfont(3)
  UI.label(24, 34, "Cue list · each cue recalls FX + send snapshot", UI.colors.muted)

  -- Transport
  local y = 68
  local bw = math.floor((w - 48) / 3)
  if UI.go_button("go", 16, y, bw, 44, "GO") then go_next() end
  if UI.button("back", 24 + bw, y, bw, 44, "BACK", { bg = UI.colors.panel }) then go_back() end
  if UI.button("fire", 32 + bw * 2, y, bw, 44, "FIRE SELECTED", { bg = UI.colors.selected }) then
    fire_selected()
  end

  -- Settings row
  y = 124
  gfx.setfont(3)
  UI.label(16, y + 6, "Parent OSC", UI.colors.muted)
  if UI.button("parent", 100, y, math.min(220, w * 0.35), 28, meta.osc_parent or "/ReaProfessor", { bg = UI.colors.panel2, font = 3 }) then
    edit_parent_osc()
  end
  if UI.button("midich", 110 + math.min(220, w * 0.35), y, 110, 28, midi_channel_label(), { bg = UI.colors.panel2, font = 3 }) then
    cycle_midi_channel()
  end
  local edit_bg = edit_mode and UI.colors.edit or UI.colors.panel
  if UI.button("edit", w - 100, y, 84, 28, edit_mode and "EDIT ON" or "EDIT", { bg = edit_bg, fg = edit_mode and {0.1,0.1,0.05} or UI.colors.text, font = 3 }) then
    edit_mode = not edit_mode
    persist()
  end

  -- Transport bindings
  y = 160
  gfx.setfont(3)
  UI.label(16, y, "Go / Back / Fire bindings (click to set OSC, then learn MIDI)", UI.colors.muted)
  y = 178
  for i, key in ipairs({ "go", "back", "fire" }) do
    local t = meta.transport[key] or {}
    local label = string.format("%s  MIDI:%s  OSC:%s",
      key:upper(),
      describe_midi(t.midi),
      (t.osc and t.osc ~= "") and t.osc or "—")
    local x = 16 + (i - 1) * ((w - 40) / 3)
    if UI.button("tr_" .. key, x, y, (w - 48) / 3, 26, label, { bg = UI.colors.panel2, font = 3 }) then
      edit_transport_binding(key)
    end
  end

  -- Cue list
  y = 216
  UI.hline(16, y, w - 32, UI.colors.border)
  y = 224
  local list_top = y
  local list_bottom = h - 120
  local row_h = 36
  local visible = math.max(1, math.floor((list_bottom - list_top) / row_h))
  if selected < scroll + 1 then scroll = selected - 1 end
  if selected > scroll + visible then scroll = selected - visible end
  if scroll < 0 then scroll = 0 end

  for row = 1, visible do
    local idx = scroll + row
    local cue = cues[idx]
    local yy = list_top + (row - 1) * row_h
    if not cue then break end
    cue = Data.normalize_cue(cue)
    local is_sel = (idx == selected)
    local is_next = (idx == (meta.cue_index or 1))
    local bg = is_sel and UI.colors.selected or (is_next and UI.colors.next_cue or ((row % 2 == 0) and UI.colors.row_alt or UI.colors.panel))
    if UI.button("cue_" .. idx, 16, yy, w - 32, row_h - 2, "", { bg = bg }) then
      selected = idx
      persist()
    end
    gfx.setfont(1)
    local kind_tag = (cue.kind == "dummy") and "D" or tostring(idx)
    UI.label(24, yy + 8, kind_tag, UI.colors.accent)
    UI.label(56, yy + 8, cue.name or ("Cue " .. idx), UI.colors.text)
    gfx.setfont(3)
    local osc = Data.cue_osc_path(cue, idx, meta)
    local snap_ok = cue.kind == "dummy" or find_snap(cue.snapshot_name)
    local right = string.format("%s  %s  %s",
      describe_midi(cue.midi),
      osc,
      cue.kind == "dummy" and "dummy" or (snap_ok and "snap" or "MISSING"))
    local tw = select(1, UI.measure(right))
    UI.label(w - 24 - tw, yy + 10, right, snap_ok and UI.colors.muted or UI.colors.danger)
  end

  if #cues == 0 then
    gfx.setfont(1)
    UI.label(24, list_top + 20, "No cues yet — Capture Cue to store the current FX/sends state.", UI.colors.muted)
  end

  -- Footer actions
  local fy = h - 104
  UI.hline(16, fy - 8, w - 32, UI.colors.border)
  local fw = math.floor((w - 56) / 4)
  if UI.button("add", 16, fy, fw, 32, "+ Capture Cue", { bg = UI.colors.tool_snap, fg = {0.05,0.08,0.05} }) then
    add_cue(false)
  end
  if UI.button("upd", 24 + fw, fy, fw, 32, "Update Selected", { bg = UI.colors.panel }) then
    update_selected_snapshot()
  end
  if UI.button("dummy", 32 + fw * 2, fy, fw, 32, "+ Dummy", { bg = UI.colors.tool_midi, fg = {0.05,0.05,0.08} }) then
    add_cue(true)
  end
  if UI.button("ch", 40 + fw * 3, fy, fw, 32, "Create Channels", { bg = UI.colors.panel }) then
    create_channels_popup()
  end

  fy = h - 64
  if edit_mode then
    if UI.button("up", 16, fy, 56, 28, "↑", { bg = UI.colors.panel2 }) then move_selected(-1) end
    if UI.button("dn", 80, fy, 56, 28, "↓", { bg = UI.colors.panel2 }) then move_selected(1) end
    if UI.button("del", 144, fy, 72, 28, "Delete", { bg = UI.colors.danger }) then delete_selected() end
    if UI.button("ren", 224, fy, 72, 28, "Rename", { bg = UI.colors.panel2 }) then rename_selected() end
  end
  if UI.button("cosc", w - 260, fy, 80, 28, "Cue OSC", { bg = UI.colors.panel2, font = 3 }) then
    edit_cue_osc()
  end
  if UI.button("cmidi", w - 172, fy, 80, 28, "Cue MIDI", { bg = UI.colors.panel2, font = 3 }) then
    edit_cue_midi()
  end
  if UI.button("learn", w - 84, fy, 68, 28, learn_target and "…" or "Learn", { bg = UI.colors.panel2, font = 3 }) then
    learn_target = "cue"
    learn_ts = midi_ts
    set_status("Learn MIDI for selected cue…")
  end

  gfx.setfont(3)
  UI.label(16, h - 28, status, UI.colors.muted)

  local ch = gfx.getchar()
  if ch == 27 or ch < 0 then running = false end
  if ch == 13 then fire_selected() end -- Enter
  if ch == 32 then go_next() end -- Space
end

local function loop()
  if not running then
    gfx.quit()
    return
  end
  poll_midi()
  draw()
  gfx.update()
  reaper.defer(loop)
end

loop()
