-- @description ReaProfessor - Chain Rack
-- @version 0.3.0
-- @author JewishBidoof
-- @noindex
-- @about Signal-chain overview of tracks and FX order.

local res = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/"
local src = debug.getinfo(1, "S").source
local script_dir = (src:sub(1, 1) == "@" and src:sub(2):match("(.+[\\/])")) or res
package.path = script_dir .. "lib/?.lua;" .. res .. "lib/?.lua;" .. package.path

local UI = require("ui")

local selected = 0
local running = true

UI.init("ReaProfessor · Chain Rack", 860, 520, 0)

local function track_chains()
  local chains = {}
  local n = reaper.CountTracks(0)
  for i = 0, n - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(tr)
    local fx_count = reaper.TrackFX_GetCount(tr)
    local fx = {}
    for fi = 0, fx_count - 1 do
      local _, fx_name = reaper.TrackFX_GetFXName(tr, fi, "")
      -- strip type prefix like "VST3: "
      fx_name = fx_name:gsub("^[^:]+:%s*", "")
      local enabled = reaper.TrackFX_GetEnabled(tr, fi)
      fx[#fx + 1] = { name = fx_name, enabled = enabled }
    end
    local mute = reaper.GetMediaTrackInfo_Value(tr, "B_MUTE") > 0
    local solo = reaper.GetMediaTrackInfo_Value(tr, "I_SOLO") > 0
    chains[#chains + 1] = {
      index = i,
      name = name,
      fx = fx,
      mute = mute,
      solo = solo,
      track = tr,
    }
  end
  return chains
end

local function draw()
  local w, h = gfx.w, gfx.h
  UI.fill_rect(0, 0, w, h, UI.colors.bg)
  gfx.setfont(2)
  UI.label(16, 14, "CHAIN RACK", UI.colors.accent)
  gfx.setfont(3)
  UI.label(180, 22, "Each track is a signal chain  ·  click to select  ·  double-click opens FX", UI.colors.muted)

  if UI.button("addtr", w - 150, 12, 138, 36, "+ Chain") then
    reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
    local tr = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
    reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "Chain " .. reaper.CountTracks(0), true)
  end

  local chains = track_chains()
  local y = 64
  local card_h = 72

  if #chains == 0 then
    gfx.setfont(1)
    UI.label(24, y, "No tracks — add a chain to start building racks.", UI.colors.muted)
  end

  for i, chain in ipairs(chains) do
    if y + card_h > h - 20 then break end
    local bg = (selected == i) and UI.colors.selected or UI.colors.panel
    UI.fill_rect(12, y, w - 24, card_h - 8, bg)
    UI.stroke_rect(12, y, w - 24, card_h - 8, UI.colors.border)

    local hit = gfx.mouse_x >= 12 and gfx.mouse_x <= w - 12
            and gfx.mouse_y >= y and gfx.mouse_y <= y + card_h - 8
    if hit and gfx.mouse_cap & 1 == 1 then
      if selected == i and (UI._last_click_i == i) and (reaper.time_precise() - (UI._last_click_t or 0) < 0.35) then
        reaper.TrackFX_Show(chain.track, 0, 1) -- show chain
      end
      selected = i
      reaper.SetOnlyTrackSelected(chain.track)
      UI._last_click_i = i
      UI._last_click_t = reaper.time_precise()
    end

    gfx.setfont(1)
    local status = ""
    if chain.mute then status = status .. " MUTE" end
    if chain.solo then status = status .. " SOLO" end
    UI.label(24, y + 10, string.format("%02d  %s", i, chain.name), UI.colors.text)
    if status ~= "" then
      UI.label(w - 120, y + 10, status, UI.colors.danger)
    end

    gfx.setfont(3)
    local fx_line = {}
    for _, fx in ipairs(chain.fx) do
      local label = fx.enabled and fx.name or ("[" .. fx.name .. "]")
      fx_line[#fx_line + 1] = label
    end
    local line = #fx_line > 0 and table.concat(fx_line, "  →  ") or "(empty chain)"
    UI.label(40, y + 38, line, UI.colors.muted)

    y = y + card_h
  end

  local ch = gfx.getchar()
  if ch == 27 or ch < 0 then running = false end
end

local function loop()
  if not running then gfx.quit(); return end
  draw()
  gfx.update()
  reaper.defer(loop)
end

loop()
