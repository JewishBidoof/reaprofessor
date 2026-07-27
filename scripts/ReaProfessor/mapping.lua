-- @description ReaProfessor - MIDI / OSC Mapping
-- @version 0.3.0
-- @author JewishBidoof
-- @noindex
-- @about Fully customize MIDI and OSC bindings. No defaults are applied.

local res = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/"
local src = debug.getinfo(1, "S").source
local script_dir = (src:sub(1, 1) == "@" and src:sub(2):match("(.+[\\/])")) or res
package.path = script_dir .. "lib/?.lua;" .. res .. "lib/?.lua;" .. package.path

local UI = require("ui")
local Data = require("data")
local MIDI = require("midi")
local OSC = require("osc")
local Commands = require("commands")

local tab = "midi" -- midi | osc
local midi_map = Data.load_midi_map()
local osc_map = Data.load_osc_map()
local selected = 1
local cmd_index = 1
local learn_mode = false
local learn_ts = 0
local status = "No default bindings — add your own"
local running = true

UI.init("ReaProfessor · Mapping", 820, 560, 0)

local function save_all()
  Data.save_midi_map(midi_map)
  Data.save_osc_map(osc_map)
  Commands.maps_changed()
  status = "Saved — control service will reload"
end

local function current_list()
  return (tab == "midi") and midi_map or osc_map
end

local function ensure_selection()
  local list = current_list()
  if #list == 0 then selected = 0
  elseif selected < 1 then selected = 1
  elseif selected > #list then selected = #list end
end

local function add_midi()
  local cat = Commands.catalog[cmd_index] or Commands.catalog[1]
  midi_map[#midi_map + 1] = {
    id = Data.new_id("midi"),
    type = "note_on",
    channel = 1,
    note = 60,
    cc = 1,
    threshold = 64,
    command = cat.id,
    arg = "",
    enabled = true,
  }
  selected = #midi_map
  save_all()
end

local function add_osc()
  local cat = Commands.catalog[cmd_index] or Commands.catalog[1]
  local path = OSC.suggested_paths[1] or "/CueLists/Go"
  osc_map[#osc_map + 1] = {
    id = Data.new_id("osc"),
    path = path,
    command = cat.id,
    arg = "",
    enabled = true,
  }
  selected = #osc_map
  save_all()
end

local function delete_selected()
  local list = current_list()
  if selected < 1 or selected > #list then return end
  table.remove(list, selected)
  ensure_selection()
  save_all()
end

local function cycle_command(bind, dir)
  if not bind then return end
  local idx = 1
  for i, c in ipairs(Commands.catalog) do
    if c.id == bind.command then idx = i break end
  end
  idx = idx + (dir or 1)
  if idx < 1 then idx = #Commands.catalog end
  if idx > #Commands.catalog then idx = 1 end
  bind.command = Commands.catalog[idx].id
  cmd_index = idx
  save_all()
end

local function edit_midi_fields(bind)
  if not bind then return end
  local def = string.format("%s,%d,%d,%d,%s",
    bind.type == "cc" and "cc" or "note",
    bind.channel or 1,
    bind.type == "cc" and (bind.cc or 0) or (bind.note or 0),
    bind.threshold or 64,
    tostring(bind.arg or ""))
  local ok, vals = reaper.GetUserInputs("Edit MIDI binding", 5,
    "Type (note/cc),Channel 1-16,Number (note or CC),CC threshold,Command arg (optional),extrawidth=120",
    def)
  if not ok then return end
  local parts = {}
  for p in (vals .. ","):gmatch("([^,]*),") do parts[#parts + 1] = p end
  local typ = tostring(parts[1] or "note"):lower()
  bind.type = (typ == "cc") and "cc" or "note_on"
  bind.channel = math.max(1, math.min(16, tonumber(parts[2]) or 1))
  local num = tonumber(parts[3]) or 0
  if bind.type == "cc" then bind.cc = num else bind.note = num end
  bind.threshold = tonumber(parts[4]) or 64
  bind.arg = parts[5] or ""
  save_all()
end

local function edit_osc_fields(bind)
  if not bind then return end
  local def = string.format("%s,%s", bind.path or "", tostring(bind.arg or ""))
  local ok, vals = reaper.GetUserInputs("Edit OSC binding", 2,
    "OSC path,Command arg (optional),extrawidth=280", def)
  if not ok then return end
  local parts = {}
  for p in (vals .. ","):gmatch("([^,]*),") do parts[#parts + 1] = p end
  bind.path = parts[1] ~= "" and parts[1] or bind.path
  bind.arg = parts[2] or ""
  save_all()
end

local function pick_suggested_path(bind)
  if not bind then return end
  local labels = table.concat(OSC.suggested_paths, "\n")
  local ok, idx = reaper.GetUserInputs("Suggested OSC paths", 1,
    "Index 1-" .. #OSC.suggested_paths .. " (see console),extrawidth=80", "1")
  reaper.ClearConsole()
  reaper.ShowConsoleMsg("Suggested OSC paths:\n")
  for i, p in ipairs(OSC.suggested_paths) do
    reaper.ShowConsoleMsg(string.format("  %d  %s\n", i, p))
  end
  if not ok then return end
  local n = tonumber(idx)
  if n and OSC.suggested_paths[n] then
    bind.path = OSC.suggested_paths[n]
    save_all()
  end
end

local function draw_tabs(w)
  local midi_bg = (tab == "midi") and UI.colors.selected or UI.colors.panel
  local osc_bg = (tab == "osc") and UI.colors.selected or UI.colors.panel
  if UI.button("tabm", 16, 52, 120, 32, "MIDI", { bg = midi_bg }) then
    tab = "midi"; ensure_selection(); learn_mode = false
  end
  if UI.button("tabo", 144, 52, 120, 32, "OSC", { bg = osc_bg }) then
    tab = "osc"; ensure_selection(); learn_mode = false
  end
  gfx.setfont(3)
  UI.label(280, 60, "Bindings are empty until you add them. Stored in the project.", UI.colors.muted)
end

local function draw_list(w, h)
  local list = current_list()
  local top = 100
  local row_h = 30
  local list_h = h - 200
  UI.fill_rect(12, top, w - 24, list_h, UI.colors.panel)
  if #list == 0 then
    gfx.setfont(1)
    UI.label(28, top + 20, "No bindings yet. Click + Add, then Edit / Learn / cycle Command.", UI.colors.muted)
    return
  end
  local visible = math.floor(list_h / row_h)
  for i = 1, math.min(#list, visible) do
    local y = top + (i - 1) * row_h
    local bind = list[i]
    local bg = (i == selected) and UI.colors.selected or ((i % 2 == 0) and UI.colors.row_alt or UI.colors.panel)
    UI.fill_rect(12, y, w - 24, row_h - 2, bg)
    if gfx.mouse_x >= 12 and gfx.mouse_x <= w - 12 and gfx.mouse_y >= y and gfx.mouse_y <= y + row_h - 2 then
      if gfx.mouse_cap & 1 == 1 then selected = i end
    end
    gfx.setfont(1)
    local text = (tab == "midi") and MIDI.describe(bind) or OSC.describe(bind)
    local label = Commands.label_for(bind.command)
    UI.label(24, y + 6, text, UI.colors.text)
    UI.label(w - 260, y + 6, label, UI.colors.muted)
  end
end

local function draw_actions(w, h)
  local y = h - 88
  if UI.button("add", 12, y, 90, 34, "+ Add") then
    if tab == "midi" then add_midi() else add_osc() end
  end
  if UI.button("del", 110, y, 90, 34, "Delete", { bg = UI.colors.danger }) then
    delete_selected()
  end
  if UI.button("edit", 208, y, 90, 34, "Edit") then
    local list = current_list()
    local bind = list[selected]
    if tab == "midi" then edit_midi_fields(bind) else edit_osc_fields(bind) end
  end
  if UI.button("cmd", 306, y, 130, 34, "Command ▶") then
    local list = current_list()
    cycle_command(list[selected], 1)
  end
  if tab == "midi" then
    local learn_bg = learn_mode and UI.colors.go or UI.colors.panel
    if UI.button("learn", 444, y, 110, 34, learn_mode and "Listening…" or "Learn", { bg = learn_bg }) then
      learn_mode = not learn_mode
      learn_ts = 0
      status = learn_mode and "Send a MIDI note or CC…" or "Learn cancelled"
    end
  else
    if UI.button("sug", 444, y, 130, 34, "Suggested path") then
      pick_suggested_path(osc_map[selected])
    end
  end

  local list = current_list()
  local bind = list[selected]
  if bind then
    local en_bg = (bind.enabled ~= false) and UI.colors.go or UI.colors.danger
    if UI.button("en", 584, y, 100, 34, (bind.enabled ~= false) and "Enabled" or "Disabled", { bg = en_bg }) then
      bind.enabled = not (bind.enabled ~= false)
      save_all()
    end
  end

  if UI.button("clr", 694, y, 110, 34, "Clear all") then
    if tab == "midi" then midi_map = {} else osc_map = {} end
    selected = 0
    save_all()
    status = "Cleared " .. tab .. " map"
  end

  gfx.setfont(3)
  UI.label(16, h - 40, status, UI.colors.muted)
  UI.label(16, h - 22, "Tip: start Control Service after mapping so MIDI/OSC are live.", UI.colors.muted)
end

local function tick_learn()
  if not learn_mode or tab ~= "midi" then return end
  local event
  event, learn_ts = MIDI.learn_next(learn_ts)
  if not event then return end
  local list = midi_map
  if selected < 1 or not list[selected] then
    add_midi()
  end
  local bind = midi_map[selected]
  if not bind then return end
  bind.channel = event.channel
  if event.type == "cc" then
    bind.type = "cc"
    bind.cc = event.cc
    bind.threshold = math.max(1, event.value or 64)
  else
    bind.type = "note_on"
    bind.note = event.note
  end
  learn_mode = false
  save_all()
  status = "Learned " .. MIDI.describe(bind)
end

local function draw()
  local w, h = gfx.w, gfx.h
  UI.fill_rect(0, 0, w, h, UI.colors.bg)
  gfx.setfont(2)
  UI.label(16, 14, "MAPPING", UI.colors.accent)
  gfx.setfont(3)
  UI.label(150, 22, "Customize MIDI & OSC — nothing is bound by default", UI.colors.muted)
  draw_tabs(w)
  draw_list(w, h)
  draw_actions(w, h)
  tick_learn()

  local ch = gfx.getchar()
  if ch == 27 or ch < 0 then running = false
  elseif ch == ("m"):byte() then tab = "midi"; ensure_selection()
  elseif ch == ("o"):byte() then tab = "osc"; ensure_selection()
  end
end

local function loop()
  if not running then gfx.quit(); return end
  draw()
  gfx.update()
  reaper.defer(loop)
end

ensure_selection()
loop()
