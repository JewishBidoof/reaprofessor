-- @description ReaProfessor - Navigator (LiveProfessor-style plugin overview)
-- @version 0.3.9
-- @author JewishBidoof
-- @noindex
-- @about Overview of all plugins across chains — click to show, power to bypass.

local res = reaper.GetResourcePath() .. "/Scripts/ReaProfessor/"
local src = debug.getinfo(1, "S").source
local script_dir = (src:sub(1, 1) == "@" and src:sub(2):match("(.+[\\/])")) or res
package.path = script_dir .. "lib/?.lua;" .. res .. "lib/?.lua;" .. package.path

local UI = require("ui")
local Config = require("config")

local running = true
local selected = { chain = 0, fx = -1 }
local scroll = 0

UI.init("ReaProfessor · Navigator", 420, 640, 0)

local function collect()
  local folders = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(tr)
    local _, role = reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:ReaProfessor_role", "", false)
    local plugins = {}
    for fi = 0, reaper.TrackFX_GetCount(tr) - 1 do
      local _, fx = reaper.TrackFX_GetFXName(tr, fi, "")
      local short = fx:gsub("^[^:]+:%s*", "")
      local en = reaper.TrackFX_GetEnabled(tr, fi)
      local open = false
      if reaper.TrackFX_GetOpen then open = reaper.TrackFX_GetOpen(tr, fi) end
      plugins[#plugins + 1] = {
        index = fi, name = short, full = fx, enabled = en, open = open,
      }
    end
    folders[#folders + 1] = {
      track = tr, index = i, name = name, role = role, plugins = plugins,
      mute = reaper.GetMediaTrackInfo_Value(tr, "B_MUTE") > 0,
    }
  end
  return folders
end

local function draw()
  local w, h = gfx.w, gfx.h
  UI.fill_rect(0, 0, w, h, UI.colors.bg)
  UI.header_bar(w, "Navigator", "All plugins by chain  ·  click name = show  ·  power = bypass")

  local folders = collect()
  local y = 56 - scroll
  local row_h = 26

  if #folders == 0 then
    gfx.setfont(1)
    UI.label(20, 70, "No tracks in project.", UI.colors.muted)
  end

  for ci, folder in ipairs(folders) do
    if y > 50 and y < h - 40 then
      local fbg = (selected.chain == ci and selected.fx < 0) and UI.colors.selected or UI.colors.panel2
      UI.fill_rect(8, y, w - 16, row_h, fbg)
      gfx.setfont(1)
      local title = folder.name or ("Chain " .. ci)
      if folder.role ~= "" then title = title .. "  [" .. folder.role .. "]" end
      UI.label(16, y + 5, title, UI.colors.text)
      if folder.mute then
        UI.label(w - 60, y + 5, "MUTE", UI.colors.danger)
      end
    end
    local fhit = gfx.mouse_y >= y and gfx.mouse_y < y + row_h and gfx.mouse_x >= 8 and gfx.mouse_x <= w - 8
    if fhit and gfx.mouse_cap & 1 == 1 and not UI._nav_down then
      selected = { chain = ci, fx = -1 }
      reaper.SetOnlyTrackSelected(folder.track)
    end
    y = y + row_h + 2

    for fi, plug in ipairs(folder.plugins) do
      if y > 50 and y < h - 40 then
        local pbg = (selected.chain == ci and selected.fx == fi) and UI.colors.selected or UI.colors.row_alt
        UI.fill_rect(20, y, w - 28, row_h - 2, pbg)
        -- Power
        local pc = plug.enabled and UI.colors.go or UI.colors.pip_off
        UI.fill_rect(28, y + 6, 14, 14, pc)
        UI.stroke_rect(28, y + 6, 14, 14, UI.colors.border)
        gfx.setfont(3)
        local col = plug.enabled and UI.colors.text or UI.colors.muted
        UI.label(50, y + 5, plug.name, col)
        if plug.open then
          UI.label(w - 50, y + 5, "GUI", UI.colors.accent)
        end

        local phit = gfx.mouse_y >= y and gfx.mouse_y < y + row_h - 2 and gfx.mouse_x >= 20 and gfx.mouse_x <= w - 8
        if phit and gfx.mouse_cap & 1 == 1 and not UI._nav_down then
          selected = { chain = ci, fx = fi }
          reaper.SetOnlyTrackSelected(folder.track)
          -- Power click
          if gfx.mouse_x >= 28 and gfx.mouse_x <= 42 then
            if Config.actions_enabled() then
              reaper.TrackFX_SetEnabled(folder.track, plug.index, not plug.enabled)
            end
          else
            -- Show floating FX
            reaper.TrackFX_Show(folder.track, plug.index, 3)
          end
        end
      end
      y = y + row_h
    end
    y = y + 6
  end

  if gfx.mouse_cap & 1 == 0 then UI._nav_down = false else UI._nav_down = true end

  -- Scroll via mouse wheel
  local wheel = gfx.mouse_wheel or 0
  if wheel ~= 0 then
    scroll = math.max(0, scroll - wheel * 12)
    gfx.mouse_wheel = 0
  end

  UI.fill_rect(0, h - 36, w, 36, UI.colors.header)
  UI.hline(0, h - 36, w, UI.colors.border)
  gfx.setfont(3)
  local nplug = 0
  for _, f in ipairs(folders) do nplug = nplug + #f.plugins end
  UI.label(12, h - 24, string.format("%d chains · %d plugins", #folders, nplug), UI.colors.muted)

  local ch = gfx.getchar()
  if ch == 27 or ch < 0 then running = false
  elseif ch == 30064 then scroll = math.max(0, scroll - 40) -- up
  elseif ch == 1685026670 then scroll = scroll + 40 -- down
  end
end

local function loop()
  if not running then gfx.quit(); return end
  draw()
  gfx.update()
  reaper.defer(loop)
end

loop()
