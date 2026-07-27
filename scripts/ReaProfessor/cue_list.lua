-- @description ReaProfessor - Cue List (LiveProfessor-style show control)
-- @version 0.1.0
-- @author ReaProfessor
-- @about Ordered cue list with GO / Back / Jump. Cues stored in project ExtState.
-- @provides
--   [main] .

local script_path = ({reaper.get_action_context()})[2]
local script_dir = script_path:match("(.+[\\/])") or ""
package.path = script_dir .. "lib/?.lua;" .. package.path

local UI = require("ui")
local Data = require("data")
local OSC = require("osc")

local cues = Data.load_cues()
local meta = Data.load_meta()
local snaps = Data.load_snapshots()
local selected = meta.cue_index or 1
if selected < 1 then selected = 1 end
if selected > #cues then selected = math.max(1, #cues) end

local function find_snapshot(name)
  for _, s in ipairs(snaps) do
    if s.name == name then return s end
  end
  return nil
end

local function run_cue(cue)
  if not cue then return end
  if cue.kind == "snapshot" then
    local name = cue.payload and cue.payload.snapshot
    local snap = find_snapshot(name)
    if snap then
      Data.recall_snapshot(snap)
      reaper.ShowConsoleMsg("[ReaProfessor] Recalled snapshot: " .. tostring(name) .. "\n")
    else
      reaper.ShowConsoleMsg("[ReaProfessor] Snapshot not found: " .. tostring(name) .. " (cue still advances)\n")
    end
  elseif cue.kind == "action" then
    local cmd = cue.payload and cue.payload.command_id
    if cmd then
      local id = reaper.NamedCommandLookup(tostring(cmd))
      if id == 0 then id = tonumber(cmd) or 0 end
      if id ~= 0 then reaper.Main_OnCommand(id, 0) end
    end
  elseif cue.kind == "midi" then
    reaper.ShowConsoleMsg("[ReaProfessor] MIDI cue stub: " .. tostring(cue.name) .. "\n")
  elseif cue.kind == "osc" then
    reaper.ShowConsoleMsg("[ReaProfessor] OSC out stub: " .. tostring(cue.payload and cue.payload.path) .. "\n")
  else
    reaper.ShowConsoleMsg("[ReaProfessor] Unknown cue kind: " .. tostring(cue.kind) .. "\n")
  end
end

local function go_next()
  if #cues == 0 then return end
  run_cue(cues[selected])
  selected = math.min(#cues, selected + 1)
  meta.cue_index = selected
  Data.save_meta(meta)
end

local function go_back()
  if #cues == 0 then return end
  selected = math.max(1, selected - 1)
  run_cue(cues[selected])
  meta.cue_index = selected
  Data.save_meta(meta)
end

local function go_to(idx)
  if idx < 1 or idx > #cues then return end
  selected = idx
  run_cue(cues[selected])
  meta.cue_index = selected
  Data.save_meta(meta)
end

local handlers = {
  [OSC.addresses.cue_go] = function() go_next() end,
  [OSC.addresses.cue_back] = function() go_back() end,
  [OSC.addresses.cue_goto] = function(args) go_to(tonumber(args[1]) or 1) end,
}

local function add_cue()
  local name = "Cue " .. tostring(#cues + 1)
  cues[#cues + 1] = {
    id = Data.new_id("cue"),
    name = name,
    kind = "snapshot",
    payload = { snapshot = name },
    notes = "",
  }
  Data.save_cues(cues)
  selected = #cues
end

local function delete_cue()
  if #cues == 0 then return end
  table.remove(cues, selected)
  selected = math.max(1, math.min(selected, #cues))
  Data.save_cues(cues)
  meta.cue_index = selected
  Data.save_meta(meta)
end

local function rename_selected()
  if not cues[selected] then return end
  local retval, new_name = reaper.GetUserInputs("Rename cue", 1, "Name:,extrawidth=200", cues[selected].name)
  if retval and new_name ~= "" then
    cues[selected].name = new_name
    Data.save_cues(cues)
  end
end

UI.init("ReaProfessor · Cue List", 780, 520, 0)
local row_h = 28
local list_top = 72
local running = true

local function draw()
  local w, h = gfx.w, gfx.h
  UI.fill_rect(0, 0, w, h, UI.colors.bg)

  gfx.setfont(2)
  UI.label(16, 14, "CUE LIST", UI.colors.accent)
  gfx.setfont(3)
  UI.label(140, 22, "ReaProfessor  ·  GO advances and fires cue", UI.colors.muted)

  if UI.button("go", w - 280, 12, 80, 36, "GO", { bg = UI.colors.go, fg = {0.05, 0.1, 0.05} }) then
    go_next()
  end
  if UI.button("back", w - 190, 12, 80, 36, "BACK") then
    go_back()
  end
  if UI.button("add", w - 100, 12, 84, 36, "+ CUE") then
    add_cue()
  end

  -- column headers
  gfx.setfont(3)
  UI.fill_rect(12, list_top - 22, w - 24, 20, UI.colors.panel)
  UI.label(24, list_top - 20, "#", UI.colors.muted)
  UI.label(56, list_top - 20, "NAME", UI.colors.muted)
  UI.label(w - 280, list_top - 20, "KIND", UI.colors.muted)
  UI.label(w - 180, list_top - 20, "TARGET", UI.colors.muted)

  local visible = math.floor((h - list_top - 56) / row_h)
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
      -- right-click rename
      selected = i
      rename_selected()
    end

    gfx.setfont(1)
    UI.label(24, y + 5, string.format("%02d", i), UI.colors.muted)
    UI.label(56, y + 5, cue.name or "?", UI.colors.text)
    UI.label(w - 280, y + 5, cue.kind or "?", UI.colors.muted)
    local target = (cue.payload and (cue.payload.snapshot or cue.payload.path or cue.payload.command_id)) or "—"
    UI.label(w - 180, y + 5, tostring(target), UI.colors.muted)
  end

  -- footer actions
  if UI.button("ren", 12, h - 44, 100, 32, "Rename") then rename_selected() end
  if UI.button("del", 122, h - 44, 100, 32, "Delete", { bg = UI.colors.danger }) then delete_cue() end
  if UI.button("fire", 232, h - 44, 120, 32, "Fire Selected") then go_to(selected) end

  gfx.setfont(3)
  UI.label(370, h - 34, string.format("%d cues  ·  OSC %s / %s", #cues, OSC.addresses.cue_go, OSC.addresses.cue_back), UI.colors.muted)

  -- keyboard: space = GO, backspace = back
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

  -- expose in-process OSC dispatch for tests / future UDP bridge
  _G.ReaProfessor_OSC = function(path, args)
    return OSC.dispatch(path, args, handlers)
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
