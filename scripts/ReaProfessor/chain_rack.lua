-- @description ReaProfessor - Chains (LiveProfessor-style rack overview)
-- @version 0.3.8
-- @author JewishBidoof
-- @noindex
-- @about Horizontal signal-chain overview of tracks and FX order.

local res = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/"
local src = debug.getinfo(1, "S").source
local script_dir = (src:sub(1, 1) == "@" and src:sub(2):match("(.+[\\/])")) or res
package.path = script_dir .. "lib/?.lua;" .. res .. "lib/?.lua;" .. package.path

local UI = require("ui")
local Config = require("config")

local selected = 0
local running = true

UI.init("ReaProfessor · Chains", 960, 560, 0)

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
      fx_name = fx_name:gsub("^[^:]+:%s*", "")
      local enabled = reaper.TrackFX_GetEnabled(tr, fi)
      local typ = ""
      if reaper.TrackFX_GetNamedConfigParm then
        local ok, t = reaper.TrackFX_GetNamedConfigParm(tr, fi, "fx_type")
        if ok then typ = t end
      end
      fx[#fx + 1] = { name = fx_name, enabled = enabled, typ = typ, index = fi }
    end
    local mute = reaper.GetMediaTrackInfo_Value(tr, "B_MUTE") > 0
    local solo = reaper.GetMediaTrackInfo_Value(tr, "I_SOLO") > 0
    local _, role = reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:ReaProfessor_role", "", false)
    chains[#chains + 1] = {
      index = i,
      name = name,
      fx = fx,
      mute = mute,
      solo = solo,
      role = role,
      track = tr,
    }
  end
  return chains
end

local function draw_node(x, y, nw, nh, title, sub, opts)
  opts = opts or {}
  local bg = opts.bg or UI.colors.panel
  UI.fill_rect(x, y, nw, nh, bg)
  UI.stroke_rect(x, y, nw, nh, opts.border or UI.colors.border)
  if opts.accent then
    UI.fill_rect(x, y, nw, 3, opts.accent)
  end
  gfx.setfont(1)
  UI.label(x + 10, y + 10, title, UI.colors.text)
  if sub and sub ~= "" then
    gfx.setfont(3)
    UI.label(x + 10, y + 32, sub, UI.colors.muted)
  end
  if opts.power ~= nil then
    local pc = opts.power and UI.colors.go or UI.colors.pip_off
    UI.fill_rect(x + nw - 22, y + 10, 12, 12, pc)
  end
end

local function draw()
  local w, h = gfx.w, gfx.h
  UI.fill_rect(0, 0, w, h, UI.colors.bg)
  UI.header_bar(w, "Chains", "Each track is a signal chain  ·  click selects  ·  double-click opens FX")

  if UI.button("addtr", w - 140, 10, 124, 28, "+ Chain", { bg = UI.colors.go, fg = UI.colors.go_fg }) then
    if not Config.actions_enabled() then
      Config.deny_action("Add Chain")
    else
      reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
      local tr = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
      reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "Chain " .. reaper.CountTracks(0), true)
    end
  end

  local chains = track_chains()
  local y = 64
  local row_h = 100
  local node_w, node_h = 168, 72
  local gap = 28

  if #chains == 0 then
    gfx.setfont(1)
    UI.label(24, y, "No tracks — add a chain to start building racks.", UI.colors.muted)
  end

  for i, chain in ipairs(chains) do
    if y + row_h > h - 12 then break end
    local row_bg = (selected == i) and {0.10, 0.12, 0.14} or UI.colors.bg
    UI.fill_rect(0, y, w, row_h - 8, row_bg)
    if selected == i then
      UI.fill_rect(0, y, 3, row_h - 8, UI.colors.accent)
    end

    local x = 16
    local accent = (selected == i) and UI.colors.accent or nil
    local sub = chain.role ~= "" and chain.role or ((#chain.fx) .. " plugins")
    if chain.mute then sub = sub .. " · MUTE" end
    if chain.solo then sub = sub .. " · SOLO" end
    draw_node(x, y + 10, node_w, node_h, chain.name or ("Chain " .. i), sub, {
      accent = accent,
      power = not chain.mute,
      bg = UI.colors.panel2,
    })

    local hit_header = gfx.mouse_x >= x and gfx.mouse_x <= x + node_w
                   and gfx.mouse_y >= y + 10 and gfx.mouse_y <= y + 10 + node_h
    if hit_header and gfx.mouse_cap & 1 == 1 then
      selected = i
      reaper.SetOnlyTrackSelected(chain.track)
    end

    x = x + node_w + gap
    for fi, fx in ipairs(chain.fx) do
      if x + node_w > w - 20 then
        gfx.setfont(3)
        UI.label(x, y + 40, "+" .. (#chain.fx - fi + 1) .. " more", UI.colors.muted)
        break
      end
      -- Connector +
      UI.fill_rect(x - gap / 2 - 8, y + 10 + node_h / 2 - 8, 16, 16, UI.colors.panel)
      UI.stroke_rect(x - gap / 2 - 8, y + 10 + node_h / 2 - 8, 16, 16, UI.colors.border)
      gfx.setfont(3)
      UI.label(x - gap / 2 - 4, y + 10 + node_h / 2 - 6, "+", UI.colors.muted)

      local typ = fx.typ ~= "" and fx.typ or "FX"
      draw_node(x, y + 10, node_w, node_h, fx.name, typ, {
        power = fx.enabled,
        bg = fx.enabled and UI.colors.panel or UI.colors.row_alt,
      })

      local hit = gfx.mouse_x >= x and gfx.mouse_x <= x + node_w
              and gfx.mouse_y >= y + 10 and gfx.mouse_y <= y + 10 + node_h
      if hit and gfx.mouse_cap & 1 == 1 then
        selected = i
        reaper.SetOnlyTrackSelected(chain.track)
        if UI._last_fx == (i .. ":" .. fi) and (reaper.time_precise() - (UI._last_fx_t or 0) < 0.35) then
          reaper.TrackFX_Show(chain.track, fx.index, 3)
          UI._last_fx_t = 0
        else
          UI._last_fx = i .. ":" .. fi
          UI._last_fx_t = reaper.time_precise()
        end
      end
      x = x + node_w + gap
    end

    -- Trailing + to add FX via REAPER
    if x + 40 < w then
      if UI.button("addfx" .. i, x - gap / 2 - 8, y + 10 + node_h / 2 - 8, 16, 16, "+", { bg = UI.colors.panel2 }) then
        if Config.actions_enabled() then
          reaper.SetOnlyTrackSelected(chain.track)
          reaper.Main_OnCommand(40271, 0) -- FX: Show/hide track FX for selected tracks
        end
      end
    end

    y = y + row_h
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
