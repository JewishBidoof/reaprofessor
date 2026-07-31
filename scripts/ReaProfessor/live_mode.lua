-- @description ReaProfessor - Live Mode (perform surface)
-- @version 0.3.9
-- @author JewishBidoof
-- @noindex
-- @about LiveProfessor-style perform view: next cue, GO NEXT, chain summary.

local res = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/"
local src = debug.getinfo(1, "S").source
local script_dir = (src:sub(1, 1) == "@" and src:sub(2):match("(.+[\\/])")) or res
package.path = script_dir .. "lib/?.lua;" .. res .. "lib/?.lua;" .. package.path

local UI = require("ui")
local Nav = require("nav")

local THIS = script_dir .. "live_mode.lua"
if not reaper.file_exists(THIS) then
  local altp = reaper.GetResourcePath() .. "/Scripts/Live/ReaProfessor/live_mode.lua"
  if reaper.file_exists(altp) then THIS = altp end
end
Nav.set_current(THIS)
local Data = require("data")
local Commands = require("commands")
local Config = require("config")

if not Config.actions_enabled() then
  Config.deny_action("Live Mode")
  return
end

local meta = Data.load_meta()
meta.live_mode = true
Data.save_meta(meta)

-- Mixer visible
do
  local state = reaper.GetToggleCommandState(40078)
  if state == 0 then reaper.Main_OnCommand(40078, 0) end
end

local running = true
local status = "Live Mode"
local armed = true

UI.init("ReaProfessor · Live", 720, 420, 0)

local function refresh()
  return Data.load_cues(), Data.load_snapshots(), Data.load_meta()
end

local function chain_summary()
  local lines = {}
  for i = 0, math.min(7, reaper.CountTracks(0) - 1) do
    local tr = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(tr)
    local _, role = reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:ReaProfessor_role", "", false)
    if role ~= "record" then
      local fx = {}
      for fi = 0, reaper.TrackFX_GetCount(tr) - 1 do
        local _, fxn = reaper.TrackFX_GetFXName(tr, fi, "")
        local short = fxn:gsub("^[^:]+:%s*", "")
        if not reaper.TrackFX_GetEnabled(tr, fi) then short = "[" .. short .. "]" end
        fx[#fx + 1] = short
      end
      lines[#lines + 1] = {
        name = name,
        fx = #fx > 0 and table.concat(fx, " → ") or "(empty)",
      }
    end
  end
  return lines
end

local function go()
  if not armed then status = "Disarmed"; return end
  local ok, msg = Commands.cue_go()
  status = msg or (ok and "GO" or "Failed")
end

local function draw()
  local w, h = UI.dims()
  local mx, my, mcap = UI.mouse()
  local cues, snaps, meta_now = refresh()
  UI.fill_rect(0, 0, w, h, UI.colors.bg)
  if Nav.back_button(UI, 8, 10) then running = false end

  UI.fill_rect(0, 0, w, 56, UI.colors.header)
  gfx.setfont(2)
  UI.label(96, 10, "Live Mode", UI.colors.text)
  gfx.setfont(3)
  UI.label(96, 34, "Space = GO NEXT  ·  Esc = exit", UI.colors.muted)

  local idx = meta_now.cue_index or 1
  if idx < 1 then idx = 1 end
  local cue = cues[idx]
  local next_cue = cues[idx + 1]

  -- Current / next cue cards
  UI.fill_rect(12, 72, w / 2 - 18, 120, UI.colors.panel)
  UI.stroke_rect(12, 72, w / 2 - 18, 120, UI.colors.border)
  UI.fill_rect(12, 72, w / 2 - 18, 4, UI.colors.go)
  gfx.setfont(3)
  UI.label(24, 84, "NEXT CUE  #" .. tostring(idx), UI.colors.muted)
  gfx.setfont(2)
  UI.label(24, 108, cue and (cue.name or "Cue") or "(empty list)", UI.colors.text)
  gfx.setfont(3)
  if cue then
    cue = Data.normalize_cue(cue)
    local acts = {}
    for _, a in ipairs(cue.actions or {}) do
      acts[#acts + 1] = a.label or a.snapshot or a.kind
    end
    UI.label(24, 140, #acts > 0 and table.concat(acts, " · ") or "No actions", UI.colors.muted)
    UI.label(24, 162, "Pre " .. Data.format_ms(cue.pre_wait_ms) .. "  Fade " .. Data.format_ms(cue.fade_ms), UI.colors.muted)
  end

  UI.fill_rect(w / 2 + 6, 72, w / 2 - 18, 120, UI.colors.panel)
  UI.stroke_rect(w / 2 + 6, 72, w / 2 - 18, 120, UI.colors.border)
  gfx.setfont(3)
  UI.label(w / 2 + 18, 84, "ON DECK  #" .. tostring(idx + 1), UI.colors.muted)
  gfx.setfont(1)
  UI.label(w / 2 + 18, 112, next_cue and (next_cue.name or "Cue") or "—", UI.colors.muted)
  UI.label(w / 2 + 18, 140, meta_now.last_snapshot ~= "" and ("Last snap: " .. tostring(meta_now.last_snapshot)) or "No snap recalled yet", UI.colors.muted)

  -- GO
  if UI.go_button("go", 12, 208, 200, 52, "GO NEXT") then go() end
  if UI.button("back", 224, 218, 80, 36, "BACK") then
    local ok, msg = Commands.cue_back()
    status = msg or "Back"
  end
  local arm_bg = armed and UI.colors.armed or UI.colors.panel
  if UI.button("arm", 316, 218, 90, 36, armed and "Armed" or "Safe", { bg = arm_bg }) then
    armed = not armed
  end
  if UI.button("cues", 418, 218, 100, 36, "Cue List") then
    Nav.go(Nav.resolve("cue_list.lua", script_dir))
    running = false
    return
  end
  if UI.button("snaps", 528, 218, 100, 36, "Snapshots") then
    Nav.go(Nav.resolve("snapshots.lua", script_dir))
    running = false
    return
  end

  -- Chain strip
  gfx.setfont(3)
  UI.label(16, 280, "CHAINS", UI.colors.accent)
  local cy = 300
  for _, line in ipairs(chain_summary()) do
    if cy > h - 40 then break end
    UI.fill_rect(12, cy, w - 24, 28, UI.colors.panel)
    gfx.setfont(1)
    UI.label(20, cy + 5, line.name, UI.colors.text)
    gfx.setfont(3)
    UI.label(160, cy + 7, line.fx, UI.colors.muted)
    cy = cy + 32
  end

  UI.fill_rect(0, h - 32, w, 32, UI.colors.header)
  gfx.setfont(3)
  UI.label(16, h - 22, status .. "  ·  " .. #cues .. " cues  ·  " .. #snaps .. " snaps", UI.colors.muted)

  local ch = gfx.getchar()
  if ch == 27 or ch < 0 then
    if Nav.can_back() then Nav.back() end
    meta_now.live_mode = false
    Data.save_meta(meta_now)
    running = false
  elseif ch == 32 then
    go()
  end
end

local function loop()
  if not running then UI.quit_and_nav(Nav); return end
  draw()
  gfx.update()
  reaper.defer(loop)
end

loop()
