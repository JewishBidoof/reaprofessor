-- @description ReaProfessor shared UI helpers (gfx)
-- @version 0.3.0
-- @author JewishBidoof
-- @noindex

local UI = {}

UI.colors = {
  bg       = {0.08, 0.09, 0.11},
  panel    = {0.12, 0.14, 0.17},
  border   = {0.22, 0.25, 0.30},
  text     = {0.90, 0.92, 0.94},
  muted    = {0.55, 0.58, 0.62},
  accent   = {0.95, 0.55, 0.12}, -- amber stage accent (not purple)
  go       = {0.20, 0.72, 0.40},
  danger   = {0.85, 0.25, 0.22},
  selected = {0.18, 0.28, 0.36},
  row_alt  = {0.10, 0.11, 0.14},
}

function UI.set_color(c, a)
  gfx.set(c[1], c[2], c[3], a or 1)
end

function UI.fill_rect(x, y, w, h, c, a)
  UI.set_color(c, a)
  gfx.rect(x, y, w, h, 1)
end

function UI.stroke_rect(x, y, w, h, c, a)
  UI.set_color(c, a)
  gfx.rect(x, y, w, h, 0)
end

function UI.label(x, y, text, c, flags)
  UI.set_color(c or UI.colors.text)
  gfx.x, gfx.y = x, y
  gfx.drawstr(text, flags or 0)
end

function UI.measure(text)
  return gfx.measurestr(text)
end

--- Hit-testable button. Returns true on left-click release inside bounds.
function UI.button(id, x, y, w, h, label, opts)
  opts = opts or {}
  local bg = opts.bg or UI.colors.panel
  local fg = opts.fg or UI.colors.text
  local hover = gfx.mouse_x >= x and gfx.mouse_x <= x + w
            and gfx.mouse_y >= y and gfx.mouse_y <= y + h
  if hover then
    bg = opts.hover or {bg[1] + 0.06, bg[2] + 0.06, bg[3] + 0.06}
  end
  UI.fill_rect(x, y, w, h, bg)
  UI.stroke_rect(x, y, w, h, UI.colors.border)
  local tw, th = gfx.measurestr(label)
  UI.label(x + (w - tw) / 2, y + (h - th) / 2, label, fg)

  local clicked = false
  if hover and gfx.mouse_cap & 1 == 1 then
    UI._down = UI._down or {}
    UI._down[id] = true
  elseif UI._down and UI._down[id] and gfx.mouse_cap & 1 == 0 then
    if hover then clicked = true end
    UI._down[id] = nil
  end
  return clicked
end

function UI.init(title, w, h, dock)
  gfx.init(title, w or 720, h or 480, dock or 0)
  gfx.setfont(1, "Arial", 16)
  gfx.setfont(2, "Arial", 22)
  gfx.setfont(3, "Arial", 13)
end

return UI
