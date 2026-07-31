-- @description ReaProfessor shared UI helpers (gfx) — LiveProfessor-inspired
-- @version 0.3.8
-- @author JewishBidoof
-- @noindex

local UI = {}

-- Palette drawn from LiveProfessor 2: near-black panels, cool selection blue,
-- signal green GO, pink/red armed/danger. Avoid purple/glow AI defaults.
UI.colors = {
  bg         = {0.07, 0.07, 0.08},
  panel      = {0.14, 0.14, 0.15},
  panel2     = {0.18, 0.18, 0.19},
  border     = {0.28, 0.28, 0.30},
  text       = {0.92, 0.92, 0.93},
  muted      = {0.55, 0.55, 0.58},
  accent     = {0.35, 0.72, 0.95}, -- cool blue (LP selection / recall)
  go         = {0.30, 0.78, 0.42},
  go_fg      = {0.04, 0.08, 0.04},
  danger     = {0.86, 0.28, 0.38},
  armed      = {0.86, 0.28, 0.38},
  edit       = {0.78, 0.72, 0.42},
  selected   = {0.22, 0.42, 0.58}, -- LP light-blue row
  row_alt    = {0.10, 0.10, 0.11},
  pip_on     = {0.30, 0.78, 0.42},
  pip_warn   = {0.95, 0.55, 0.18},
  pip_off    = {0.30, 0.30, 0.32},
  header     = {0.11, 0.11, 0.12},
}

UI.FONT = "Noto Sans"
UI.FONT_MONO = "JetBrains Mono"

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

function UI.hline(x, y, w, c, a)
  UI.set_color(c or UI.colors.border, a)
  gfx.line(x, y, x + w, y)
end

function UI.label(x, y, text, c, flags)
  UI.set_color(c or UI.colors.text)
  gfx.x, gfx.y = x, y
  gfx.drawstr(tostring(text or ""), flags or 0)
end

function UI.measure(text)
  return gfx.measurestr(tostring(text or ""))
end

--- Hit-testable button. Returns true on left-click release inside bounds.
function UI.button(id, x, y, w, h, label, opts)
  opts = opts or {}
  local bg = opts.bg or UI.colors.panel
  local fg = opts.fg or UI.colors.text
  local hover = gfx.mouse_x >= x and gfx.mouse_x <= x + w
            and gfx.mouse_y >= y and gfx.mouse_y <= y + h
  if hover then
    bg = opts.hover or { math.min(1, bg[1] + 0.06), math.min(1, bg[2] + 0.06), math.min(1, bg[3] + 0.06) }
  end
  UI.fill_rect(x, y, w, h, bg)
  UI.stroke_rect(x, y, w, h, opts.border or UI.colors.border)
  gfx.setfont(1)
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

--- Large primary action (LP "Go Next" style).
function UI.go_button(id, x, y, w, h, label)
  return UI.button(id, x, y, w, h, label or "GO NEXT", {
    bg = UI.colors.go,
    fg = UI.colors.go_fg,
    border = {0.22, 0.55, 0.30},
  })
end

--- Row of small status pips (LP global snapshot indicators).
function UI.pips(x, y, n, on_count, warn_at)
  n = n or 8
  on_count = on_count or n
  local pw, ph, gap = 10, 5, 3
  for i = 1, n do
    local c = UI.colors.pip_off
    if i <= on_count then
      c = (warn_at and i == warn_at) and UI.colors.pip_warn or UI.colors.pip_on
    end
    UI.fill_rect(x + (i - 1) * (pw + gap), y, pw, ph, c)
  end
end

function UI.header_bar(w, title, subtitle)
  UI.fill_rect(0, 0, w, 48, UI.colors.header)
  UI.hline(0, 48, w, UI.colors.border)
  gfx.setfont(2)
  UI.label(16, 12, title, UI.colors.text)
  if subtitle and subtitle ~= "" then
    gfx.setfont(3)
    UI.label(16, 32, subtitle, UI.colors.muted)
  end
end

function UI.init(title, w, h, dock)
  gfx.init(title, w or 720, h or 480, dock or 0)
  gfx.setfont(1, UI.FONT, 15)
  gfx.setfont(2, UI.FONT, 20)
  gfx.setfont(3, UI.FONT, 12)
  gfx.setfont(4, UI.FONT_MONO, 12)
end

return UI
