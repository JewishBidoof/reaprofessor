-- @description ReaProfessor - Create Channels
-- @version 0.5.0
-- @author JewishBidoof
-- @noindex
-- @about Create N mono channels with 1:1 hardware I/O.

local res = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/"
local src = debug.getinfo(1, "S").source
local script_dir = (src:sub(1, 1) == "@" and src:sub(2):match("(.+[\\/])")) or res
package.path = script_dir .. "lib/?.lua;" .. res .. "lib/?.lua;" .. package.path

local UI = require("ui")
local Nav = require("nav")

local THIS = script_dir .. "create_channels.lua"
if not reaper.file_exists(THIS) then
  local altp = reaper.GetResourcePath() .. "/Scripts/Live/ReaProfessor/create_channels.lua"
  if reaper.file_exists(altp) then THIS = altp end
end
Nav.set_current(THIS)
local Data = require("data")
local Routing = require("routing")
local Config = require("config")

local meta = Data.load_meta()
local count = 16
local start_in = 1
local start_out = 1
local mode = meta.channel_mode or "same_strip"
local running = true
local status = Config.actions_enabled() and "Ready" or "Prototype — Create is disabled"

UI.init("ReaProfessor · Create Channels", 560, 420, 0)

local function create()
  if not Config.actions_enabled() then
    return Config.deny_action("Create Channels")
  end
  local created = Routing.create_channels(count, {
    start_input = start_in,
    start_output = start_out,
    mode = mode,
    arm = true,
    prefix = "CH",
  })
  meta.channel_mode = mode
  Data.save_meta(meta)
  status = string.format("Created %d %s channel(s)", #created, mode)
  reaper.ShowConsoleMsg("[ReaProfessor] " .. status .. "\n")
end

local function draw()
  local w, h = UI.dims()
  local mx, my, mcap = UI.mouse()
  UI.fill_rect(0, 0, w, h, UI.colors.bg)
  if Nav.back_button(UI, 8, 10) then running = false end
  gfx.setfont(2)
  UI.label(96, 14, "CREATE CHANNELS", UI.colors.accent)
  gfx.setfont(3)
  UI.label(16, 48, "1:1 mono hardware routing for live multitrack", UI.colors.muted)

  gfx.setfont(1)
  UI.label(24, 100, string.format("Count: %d", count), UI.colors.text)
  if UI.button("c-", 200, 92, 40, 32, "−") then count = math.max(1, count - 1) end
  if UI.button("c+", 248, 92, 40, 32, "+") then count = math.min(128, count + 1) end
  if UI.button("c8", 300, 92, 48, 32, "8") then count = 8 end
  if UI.button("c16", 356, 92, 48, 32, "16") then count = 16 end
  if UI.button("c32", 412, 92, 48, 32, "32") then count = 32 end

  UI.label(24, 150, string.format("Start input: %d", start_in), UI.colors.text)
  if UI.button("si-", 200, 142, 40, 32, "−") then start_in = math.max(1, start_in - 1) end
  if UI.button("si+", 248, 142, 40, 32, "+") then start_in = start_in + 1 end

  UI.label(24, 200, string.format("Start output: %d", start_out), UI.colors.text)
  if UI.button("so-", 200, 192, 40, 32, "−") then start_out = math.max(1, start_out - 1) end
  if UI.button("so+", 248, 192, 40, 32, "+") then start_out = start_out + 1 end

  UI.label(24, 250, "Routing mode:", UI.colors.text)
  local same_bg = (mode == "same_strip") and UI.colors.selected or UI.colors.panel
  local dbl_bg = (mode == "double_patch") and UI.colors.selected or UI.colors.panel
  if UI.button("same", 160, 242, 150, 32, "Same strip", { bg = same_bg }) then mode = "same_strip" end
  if UI.button("dbl", 320, 242, 150, 32, "Double patch", { bg = dbl_bg }) then mode = "double_patch" end

  gfx.setfont(3)
  if mode == "same_strip" then
    UI.label(24, 290, "Record dry input on the strip; monitor/hear through FX; HW out N.", UI.colors.muted)
    UI.label(24, 310, "Snapshots change FX on the same strip — recording stays dry.", UI.colors.muted)
  else
    UI.label(24, 290, "CH## REC = dry multitrack  ·  CH## FX = plugins + HW out (same input).", UI.colors.muted)
    UI.label(24, 310, "Snapshots only touch FX tracks — record strips are never modified.", UI.colors.muted)
  end

  if UI.button("go", 24, h - 70, w - 48, 44, string.format("Create %d channels  (%d→%d)", count, start_in, start_in + count - 1), {
    bg = UI.colors.go, fg = {0.05, 0.1, 0.05}
  }) then
    create()
  end

  UI.label(24, h - 20, status, UI.colors.muted)

  local ch = gfx.getchar()
  if ch == 27 or ch < 0 then
    if Nav.can_back() then Nav.back() end
    running = false
  elseif ch == 13 then create()
  end
end

local function loop()
  if not running then UI.quit_and_nav(Nav); return end
  draw()
  gfx.update()
  reaper.defer(loop)
end

loop()
