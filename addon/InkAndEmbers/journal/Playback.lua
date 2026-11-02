-- Playback: timeline (play/pause, speed slow | medium | fast, level scale, date, played time) and chapter bar (one sticker
-- per zone stay; click selects the chapter). At most Playback.CHIP_POOL stickers, paged by arrow pair or mouse wheel.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Playback = {}
Journal.Playback = Playback

local floor, max, min, huge = math.floor, math.max, math.min, math.huge

-- Speed: play-time seconds per real second. Playback runs on the model axis (Model.toAxis: idle and offline gaps cut),
-- so the figure keeps moving.
Playback.SPEEDS = { 20, 60, 180 }
local T = ns.Locale.ns("Playback", {
  speed20 = "Langsam", speed60 = "Mittel", speed180 = "Schnell",
  chapterNum = "Kapitel %s",
  lvSpan = "ST. %s",
  lvSpanRange = "ST. %s–%s",
  tipPause = "Wiedergabe anhalten",
  tipPlay = "Reise abspielen",
  tipSpeed = "Wiedergabe-Tempo: %s",
  tipSpeedSec = "Spielzeit je Sekunde: %s s. Stillstand wird übersprungen.",
  tipScrub = "Reise abspielen von Hand",
  tipScrubHint = "Klicken oder den Punkt ziehen.",
  prevPage = "Vorige Seite",
  prevChapters = "Frühere Kapitel",
  nextPage = "Nächste Seite",
  nextChapters = "Spätere Kapitel",
  wholeTrip = "Die ganze Reise: alle %s Zonenaufenthalte",
  chapterOf = "Kapitel %s von %s",
  playedSuffix = "%s gespielt",
})
Playback.SPEED_NAMES = setmetatable({}, { __index = function(_, speed)
  if speed == 20 or speed == 60 or speed == 180 then return T["speed" .. speed] end
  return nil
end })
Playback.DEFAULT_SPEED = 60
Playback.CHAPTERS_VISIBLE = 6
Playback.CHIP_POOL = 8
Playback.GRID_POOL = 24
Playback.CHIP_MAX = 210
Playback.CHIP_GAP = 6
Playback.CHIP_PAD = 10
Playback.CHIP_MIN = 44
Playback.CHIP_TOP = 4
Playback.CHIP_NAME = 18
Playback.CHIP_NUM = 11
-- Tilt per sticker slot (degrees like CSS rotate, negative = right side higher): fixed instead of random
Playback.CHIP_TILTS = { -2, 1.5, -1, 2, -1.5, 1, -2.5, 1.5 }
Playback.PIN_TILT = 2
Playback.PIN_BADGE = 22
Playback.PIN_GAP = 12
Playback.NAV_SIZE = 18
Playback.SPEED_SIZE = 12
Playback.TICK_GAP = 18
-- Book layout: bottom of the left page. lay.barX / lay.barY = position of the chapter bar relative to the playback top;
-- lay.speedBelow = speed toggle in its own row; lay.navOut = the caller places the arrow pair (ui.nav, ui.range) itself;
-- lay.grid = chapter grid instead of the scrolling bar. Without lay: everything stacked, with a rule.
Playback.PLAY_SIZE = 26
Playback.SPEED_W = 160
Playback.INFO_Y = -38
Playback.SPEED_Y = -72
Playback.TOP_H = 86
Playback.BAR_Y = -62
Playback.CHIP_H = 42
Playback.HEIGHT = 104

function Playback.validSpeed(speed)
  if Playback.SPEED_NAMES[speed] then return speed end
  return Playback.DEFAULT_SPEED
end

function Playback.new(speed)
  return { p0 = 0, p1 = 0, p = 0, playing = false, speed = Playback.validSpeed(speed) }
end

function Playback.setRange(st, p0, p1)
  p0 = tonumber(p0) or 0
  p1 = tonumber(p1) or p0
  if p1 < p0 then p1 = p0 end
  st.p0, st.p1, st.p, st.playing = p0, p1, p1, false
  return st
end

function Playback.resume(st, p, wasPlaying)
  if not wasPlaying then return st end
  p = tonumber(p)
  if not p or p ~= p then return st end
  st.p = max(st.p0, min(p, st.p1))
  st.playing = st.p < st.p1
  return st
end

function Playback.toggle(st)
  if st.playing then
    st.playing = false
  else
    if st.p >= st.p1 then st.p = st.p0 end
    st.playing = st.p1 > st.p0
  end
  return st.playing
end

function Playback.step(st, dt)
  if not st.playing or not dt or dt <= 0 then return false end
  local before = st.p
  st.p = st.p + dt * st.speed
  if st.p >= st.p1 then
    st.p = st.p1
    st.playing = false
  end
  return st.p ~= before
end

function Playback.seek(st, frac)
  frac = max(0, min(1, tonumber(frac) or 0))
  st.p = st.p0 + (st.p1 - st.p0) * frac
  return st.p
end

function Playback.frac(st)
  if st.p1 <= st.p0 then return 1 end
  return (st.p - st.p0) / (st.p1 - st.p0)
end

function Playback.mapP(st)
  if not st.playing and st.p >= st.p1 then return huge end
  return st.p
end

function Playback.nextSpeed(speed)
  local list = Playback.SPEEDS
  for i, s in ipairs(list) do
    if s == speed then return list[i % #list + 1] end
  end
  return list[2]
end

function Playback.speedText(speed)
  return Playback.SPEED_NAMES[speed] or Playback.SPEED_NAMES[Playback.DEFAULT_SPEED]
end

function Playback.ticks(levels, p0, p1, width, gap)
  local out = {}
  if not (p1 > p0) then return out end
  local minFrac = (gap or Playback.TICK_GAP) / max(width or 600, 1)
  local cands = {}
  local startLevel
  for _, l in ipairs(levels or {}) do
    if l.p and l.level then
      if l.p <= p0 then startLevel = l.level end
      if l.p > p0 and l.p <= p1 and l.level % 5 == 0 then
        cands[#cands + 1] = { frac = (l.p - p0) / (p1 - p0), level = l.level, major = l.level % 10 == 0 }
      end
    end
  end
  if p0 == 0 or startLevel then
    table.insert(cands, 1, { frac = 0, level = startLevel or 1, major = false })
  end
  for _, c in ipairs(cands) do
    local last = out[#out]
    if not last or c.frac - last.frac >= minFrac then
      out[#out + 1] = c
    elseif c.major and not last.major and (#out < 2 or c.frac - out[#out - 1].frac >= minFrac) then
      out[#out] = c
    end
  end
  return out
end

function Playback.levelFracs(levels, p0, p1)
  local out = {}
  if not (p1 > p0) then return out end
  for _, l in ipairs(levels or {}) do
    if l.p and l.level and l.level >= 2 and l.p > p0 and l.p <= p1 then
      out[#out + 1] = (l.p - p0) / (p1 - p0)
    end
  end
  return out
end

function Playback.crossed(levels, a, b)
  local hit
  for _, l in ipairs(levels or {}) do
    if l.p and l.level and l.level >= 2 then
      if l.p > a and l.p <= b then hit = l elseif l.p > b then break end
    end
  end
  return hit
end

function Playback.window(n, size, focus, first)
  size = size or Playback.CHAPTERS_VISIBLE
  if n <= size then return 1 end
  first = first or 1
  if focus then
    if focus < first then first = focus end
    if focus > first + size - 1 then first = focus - size + 1 end
  end
  return max(1, min(first, n - size + 1))
end

function Playback.fitCount(widths, first, barW, gap)
  gap = gap or Playback.CHIP_GAP
  local n, x = 0, 0
  for i = first, #widths do
    local w = widths[i]
    if n >= Playback.CHIP_POOL then break end
    if n > 0 and x + gap + w > barW then break end
    x = x + (n > 0 and gap or 0) + w
    n = n + 1
  end
  return n
end

function Playback.firstEndingAt(widths, last, barW, gap)
  gap = gap or Playback.CHIP_GAP
  last = max(1, min(last, #widths))
  local first, x, n = last, widths[last] or 0, 1
  while first > 1 and n < Playback.CHIP_POOL and x + gap + widths[first - 1] <= barW do
    first = first - 1
    x = x + gap + widths[first]
    n = n + 1
  end
  return first
end

function Playback.clampFirst(widths, first, barW, focus, gap)
  local n = #widths
  if n == 0 then return 1 end
  local maxFirst = Playback.firstEndingAt(widths, n, barW, gap)
  first = max(1, min(first or 1, maxFirst))
  if focus and focus >= 1 and focus <= n then
    if focus < first then
      first = focus
    elseif focus > first + Playback.fitCount(widths, first, barW, gap) - 1 then
      first = Playback.firstEndingAt(widths, focus, barW, gap)
    end
  end
  return max(1, min(first, maxFirst))
end

-- Chapter grid (lay.grid): chips flow left to right in rows (new row when the next one does not fit), at most rows rows (and
-- GRID_POOL chips) per page. An over-wide chip stands alone in its row (cut to barW).
function Playback.pages(widths, barW, rows, gap)
  gap = gap or Playback.CHIP_GAP
  rows = max(1, floor(tonumber(rows) or 1))
  local pages = {}
  local page, row, x
  for i = 1, #widths do
    local w = min(widths[i], barW)
    local newRow = not row or (x + gap + w > barW)
    if page and not newRow and page.count >= Playback.GRID_POOL then newRow = true end
    if newRow then
      if not page or #page.rows >= rows or page.count >= Playback.GRID_POOL then
        page = { first = i, last = i - 1, rows = {}, count = 0 }
        pages[#pages + 1] = page
      end
      row = { from = i, to = i - 1 }
      page.rows[#page.rows + 1] = row
      x = 0
    end
    x = x + (x > 0 and gap or 0) + w
    row.to = i
    page.last = i
    page.count = page.count + 1
  end
  return pages
end

function Playback.pageOf(pages, idx)
  for n, pg in ipairs(pages or {}) do
    if idx and idx >= pg.first and idx <= pg.last then return n end
  end
  return nil
end

function Playback.visibleCount(segs, p)
  local lo, hi = 0, #segs
  while lo < hi do
    local mid = floor((lo + hi + 1) / 2)
    if segs[mid].p0 <= p then lo = mid else hi = mid - 1 end
  end
  return lo
end

function Playback.chipTexts(c, i)
  local name = c.zoneName or c.title or T("chapterNum", tostring(i))
  local label = c.label or Playback.levelSpan(c)
  return name, label
end

function Playback.levelSpan(c)
  local a, b = tonumber(c.levelFrom), tonumber(c.levelTo)
  if not a then return "" end
  if b and b ~= a then return T("lvSpanRange", tostring(floor(a)), tostring(floor(b))) end
  return T("lvSpan", tostring(floor(a)))
end

local Theme, View

local function W() return Journal.Widgets end

Playback.PLAY_LABEL = 32
Playback.PLAY_LABEL_TILT = -6
Playback.KNOB_SIZE = 16
-- texcoords for a 90 degree counter-clockwise rotation (full area u0..u1, v0..v1): UL, LL, UR, LR
function Playback.rot90(u0, u1, v0, v1)
  return u1, v0, u0, v0, u1, v1, u0, v1
end

local function playButton(parent, size)
  local D = W().Diary
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  local face = CreateFrame("Frame", nil, b)
  face:SetPoint("CENTER", b, "CENTER", 0, 0)
  face:SetSize(size, size)
  local ls = Playback.PLAY_LABEL
  local disc = D.mark(face, "badgeGold", ls, nil, "BACKGROUND")
  disc:ClearAllPoints()
  disc:SetPoint("CENTER", face, "CENTER", 0, 0)
  if disc.diaryOk and Theme.rotCoords8 then
    local u0, u1, v0, v1 = Theme.diaryCoords("badgeGold")
    disc:SetTexCoord(Theme.rotCoords8(u0, u1, v0, v1, ls, ls, Playback.PLAY_LABEL_TILT))
  elseif not disc.diaryOk then
    disc:SetColorTexture(Theme.C.gold[1], Theme.C.gold[2], Theme.C.gold[3], 1)
  end
  -- The arrow texture points down: rotated 90 degrees counter-clockwise it points right; nudged 1 px right optically.
  local tri = face:CreateTexture(nil, "ARTWORK")
  tri:SetSize(size * 0.56, size * 0.56)
  tri:SetPoint("CENTER", face, "CENTER", 1.5, 0)
  tri:SetTexture(Theme.TEX.arrow)
  tri:SetTexCoord(Playback.rot90(0, 1, 0, 1))
  local bars = {}
  for i, dx in ipairs({ -3.5, 3.5 }) do
    local s = face:CreateTexture(nil, "ARTWORK")
    s:SetSize(8, size * 0.5)
    s:SetPoint("CENTER", face, "CENTER", dx, 0)
    if Theme.HAS_DIARY and Theme.TEX.diaryStroke then
      s:SetTexture(Theme.TEX.diaryStroke)
      s:SetTexCoord(Playback.rot90(0, 1, 0, 1))
    else
      s:SetColorTexture(1, 1, 1, 1)
    end
    s:Hide()
    bars[i] = s
  end
  b.face, b.disc, b.tri, b.bars = face, disc, tri, bars
  function b:Paint()
    local c = self.hover and Theme.C.red or Theme.C.ink
    Theme.color(self.tri, c)
    for _, s in ipairs(self.bars) do Theme.color(s, c) end
    self.face:SetScale(self.hover and 1.08 or 1)
  end
  function b:SetPlaying(on)
    self.tri:SetShown(not on)
    for _, s in ipairs(self.bars) do s:SetShown(on and true or false) end
  end
  b:Paint()
  return b
end

function Playback.create(parent, x, y, w, h, cb, lay)
  Theme, View = Journal.Theme, Journal.View
  local D = W().Diary
  local ui = { W = w, ticks = {}, chapters = {}, first = 1, cb = cb }
  local f = CreateFrame("Frame", nil, parent)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  f:SetSize(w, h)
  f:EnableMouse(true)
  ui.frame = f

  local play = playButton(f, Playback.PLAY_SIZE)
  play:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -1)
  play:SetScript("OnClick", function() cb.onToggle() end)
  play:SetScript("OnEnter", function(self)
    self.hover = true
    self:Paint()
    if GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(ui.playing and T.tipPause or T.tipPlay, 1, 1, 1)
      GameTooltip:Show()
    end
  end)
  play:SetScript("OnLeave", function(self)
    self.hover = false
    self:Paint()
    Theme.hideTooltip()
  end)
  ui.play = play

  local items = {}
  for i, value in ipairs(Playback.SPEEDS) do
    items[i] = { key = value, label = Playback.speedText(value), tip = { T("tipSpeed", Playback.speedText(value)),
      T("tipSpeedSec", tostring(floor(value))) } }
  end
  local speed = D.NewToggle(f, { items = items, value = Playback.DEFAULT_SPEED, size = Playback.SPEED_SIZE, gap = 10,
    onChange = function(key) cb.onSpeed(key) end })
  local below = type(lay) == "table" and lay.speedBelow and true or false
  local compact = type(lay) == "table" and lay.compact and true or false
  local speedW = 0
  if compact then
    local mw = tonumber(speed.frame:GetWidth()) or 0
    speedW = (mw > 0 and mw == mw) and floor(mw + 10) or (tonumber(lay.speedW) or Playback.SPEED_W)
  end
  ui.compact = compact
  if compact then
    speed.frame:SetPoint("RIGHT", f, "TOPRIGHT", 2, Playback.INFO_Y - 6)
  elseif below then
    speed.frame:SetPoint("LEFT", f, "TOPLEFT", Playback.PLAY_SIZE + 12 - 3, Playback.SPEED_Y)
  else
    speed.frame:SetPoint("RIGHT", f, "TOPRIGHT", 2, -10)
  end
  for i, b in ipairs(speed.buttons) do b.value = Playback.SPEEDS[i] end
  ui.speedToggle, ui.speeds = speed, speed.buttons
  ui.speed = ui.speeds[2]

  local trackX = Playback.PLAY_SIZE + 12
  local trackW = w - trackX - ((below or compact) and 4 or Playback.SPEED_W)
  ui.trackW, ui.trackX = trackW, trackX
  local track = CreateFrame("Button", nil, f)
  track:SetPoint("TOPLEFT", f, "TOPLEFT", trackX, -4)
  track:SetSize(trackW, 28)
  local base = D.NewInkStroke(track, trackW, "ink", 0.5, "BACKGROUND")
  base:SetPoint("LEFT", track, "TOPLEFT", 0, -8.5)
  local fill = D.NewInkStroke(track, trackW, "red", 0.95, "ARTWORK")
  fill:SetPoint("LEFT", track, "TOPLEFT", 0, -8.5)
  fill.inkTex = Theme.HAS_DIARY and true or false
  local knobS = Playback.KNOB_SIZE
  local knob = D.mark(track, "badgeRed", knobS, nil, "OVERLAY")
  if knob.diaryOk and Theme.rotCoords8 then
    local u0, u1, v0, v1 = Theme.diaryCoords("badgeRed")
    knob:SetTexCoord(Theme.rotCoords8(u0, u1, v0, v1, knobS, knobS, 8))
  end
  ui.track, ui.fill, ui.knob, ui.rail = track, fill, knob, base
  track:SetScript("OnMouseDown", function(_, button)
    if button == nil or button == "LeftButton" then Playback.beginScrub(ui) end
  end)
  track:SetScript("OnMouseUp", function(_, button)
    if button == nil or button == "LeftButton" then
      if ui.scrubbing then Playback.scrubTo(ui) end
      Playback.endScrub(ui)
    end
  end)
  track:SetScript("OnEnter", function(self)
    if GameTooltip and not ui.scrubbing then
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(T.tipScrub, 1, 1, 1)
      GameTooltip:AddLine(T.tipScrubHint, 0.8, 0.8, 0.8, true)
      GameTooltip:Show()
    end
  end)
  track:SetScript("OnLeave", Theme.hideTooltip)

  local infoX = compact and 0 or trackX
  local infoW = w - infoX - speedW
  local whenW = floor(infoW * 0.62)
  local when = f:CreateFontString(nil, "OVERLAY")
  Theme.font(when, "text", 12, Theme.C.ink)
  when:SetPoint("TOPLEFT", f, "TOPLEFT", infoX, Playback.INFO_Y)
  when:SetJustifyH("LEFT")
  when:SetWidth(whenW)
  when:SetWordWrap(false)
  local played = f:CreateFontString(nil, "OVERLAY")
  Theme.font(played, "label", 12, Theme.C.sepia)
  played:SetPoint("TOPRIGHT", f, "TOPRIGHT", -speedW, Playback.INFO_Y)
  played:SetJustifyH("RIGHT")
  played:SetWidth(infoW - whenW - 8)
  played:SetWordWrap(false)
  ui.when, ui.played = when, played
  ui.infoW = infoW

  local rule = f:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(Theme.C.sepia[1], Theme.C.sepia[2], Theme.C.sepia[3], 0.35)
  rule:SetPoint("TOPLEFT", f, "TOPLEFT", 0, Playback.BAR_Y + 6)
  rule:SetSize(w, 1)
  ui.rule = rule
  local barY = Playback.BAR_Y
  local barX = 0
  if type(lay) == "table" and tonumber(lay.barY) then
    barY, barX = -tonumber(lay.barY), tonumber(lay.barX) or 0
    rule:Hide()
  end
  if compact then rule:Hide() end
  local grid = type(lay) == "table" and type(lay.grid) == "table" and lay.grid or nil
  ui.chipRoot = f
  if grid then
    ui.grid = { x = tonumber(grid.x) or 0, y = -(tonumber(grid.y) or 0), w = tonumber(grid.w) or w, rows = tonumber(grid.rows) or 3,
      gapY = tonumber(grid.gapY) or 6 }
    if type(grid.parent) == "table" then
      local gf = CreateFrame("Frame", nil, grid.parent)
      gf:SetPoint("TOPLEFT", grid.parent, "TOPLEFT", ui.grid.x, ui.grid.y)
      gf:SetSize(ui.grid.w, ui.grid.rows * Playback.CHIP_H + (ui.grid.rows - 1) * ui.grid.gapY)
      gf:EnableMouseWheel(true)
      ui.gridFrame, ui.chipRoot, ui.gridParent = gf, gf, grid.parent
      ui.gridX, ui.gridY = ui.grid.x, -ui.grid.y
      ui.grid.x, ui.grid.y = 0, 0
    end
  end
  local function turn(delta)
    ui.page = (ui.page or 1) + delta
    Playback.layoutChapters(ui)
  end
  local nav = D.NewNavPair(ui.chipRoot, { size = Playback.NAV_SIZE,
    tipPrev = { ui.grid and T.prevPage or T.prevChapters }, tipNext = { ui.grid and T.nextPage or T.nextChapters },
    onPrev = function()
      if ui.grid then return turn(-1) end
      ui.first = Playback.firstEndingAt(ui.widths or {}, (ui.first or 1) - 1, ui.listW0 or ui.barW)
      Playback.layoutChapters(ui)
    end,
    onNext = function()
      if ui.grid then return turn(1) end
      ui.first = (ui.first or 1) + max(1, ui.shown or 1)
      Playback.layoutChapters(ui)
    end })
  nav.frame:SetPoint("RIGHT", f, "TOPRIGHT", 4, barY - Playback.CHIP_H / 2)
  nav.frame:Hide()
  ui.nav, ui.prev, ui.next = nav, nav.prev, nav.next
  local navW = tonumber(nav.frame:GetWidth()) or 54
  local navOut = type(lay) == "table" and lay.navOut and true or false
  ui.navOut = navOut
  ui.barX, ui.barY, ui.barW = barX, barY, w - barX - (navOut and 0 or (navW + Playback.CHIP_GAP))
  local range = ui.chipRoot:CreateFontString(nil, "OVERLAY")
  Theme.font(range, "label", 12, Theme.C.sepia)
  range:SetJustifyH("RIGHT")
  range:SetWordWrap(false)
  range:Hide()
  ui.range = range
  ui.listX, ui.listW, ui.listX0, ui.listW0 = ui.barX, ui.barW, ui.barX, ui.barW
  local wheel = ui.gridFrame or f
  wheel:EnableMouseWheel(true)
  wheel:SetScript("OnMouseWheel", function(_, delta)
    if type(delta) ~= "number" or delta ~= delta then return end
    if ui.grid then
      ui.page = (ui.page or 1) - (delta > 0 and 1 or -1)
      Playback.layoutChapters(ui)
      return
    end
    ui.first = (ui.first or 1) - (delta > 0 and 1 or -1)
    Playback.layoutChapters(ui)
  end)
  local mName, mNum = D.font(f, "hand", Playback.CHIP_NAME, "ink"), D.font(f, "label", Playback.CHIP_NUM, "sepia")
  mName:Hide()
  mNum:Hide()
  ui.mName, ui.mNum = mName, mNum
  -- If the handwriting font arrived later (Friz fallback at load), re-measure the entry widths (Diary.recheck reports it).
  local function remeasure()
    local list, total = ui.list, ui.total
    if not list then return end
    ui.list, ui.total = nil, nil
    Playback.setChapters(ui, list, ui.selected, total, ui.totalSelected)
  end
  mName.diaryRefit, mNum.diaryRefit = remeasure, remeasure
  f:SetScript("OnHide", function()
    Playback.stopTicking(ui)
    Playback.endScrub(ui, true)
  end)
  return ui
end

function Playback.cursorFrac(cx, scale, left, width)
  cx, scale, left, width = tonumber(cx), tonumber(scale), tonumber(left), tonumber(width)
  if not (cx and scale and left and width) or scale <= 0 or width <= 0 then return nil end
  local f = (cx / scale - left) / width
  if f ~= f then return nil end
  return max(0, min(1, f))
end

local function trackFrac(ui)
  local cx = GetCursorPosition and GetCursorPosition()
  return Playback.cursorFrac(cx, ui.track:GetEffectiveScale() or 1, ui.track:GetLeft(), ui.trackW)
end

function Playback.scrubTo(ui)
  local f = trackFrac(ui)
  if f and f ~= ui.scrubFrac then
    ui.scrubFrac = f
    ui.cb.onSeek(f)
  end
end

function Playback.beginScrub(ui)
  if ui.scrubbing then return end
  ui.scrubbing, ui.scrubFrac = true, nil
  if ui.cb.onScrubStart then ui.cb.onScrubStart() end
  Playback.scrubTo(ui)
  ui.track:SetScript("OnUpdate", function()
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
      Playback.endScrub(ui)
    else
      Playback.scrubTo(ui)
    end
  end)
end

function Playback.endScrub(ui, aborted)
  if not ui.scrubbing then return end
  ui.scrubbing, ui.scrubFrac = false, nil
  ui.track:SetScript("OnUpdate", nil)
  if ui.cb.onScrubEnd then ui.cb.onScrubEnd(aborted and true or false) end
end

Playback.CHIP_LOOK = {
  normal = { text = "ink", mark = false },
  hover = { text = "red", mark = false },
  selected = { text = "red", mark = true },
}

function Playback.chipState(b)
  if b.selected then return "selected" end
  if b.hover then return "hover" end
  return "normal"
end

local function chipColor(b)
  local look = Playback.CHIP_LOOK[Playback.chipState(b)]
  b.name:SetTextColor(W().color(look.text))
  b.mark:SetShown(look.mark)
end

local function chipTip(ui, b)
  local c = b.chapter
  if not c then return nil end
  local lines = { type(c.title) == "string" and c.title or "" }
  if c.total then
    lines[#lines + 1] = T("wholeTrip", tostring(c.stays or #(ui.list or {})))
  else
    lines[#lines + 1] = T("chapterOf", tostring(b.index or 0), tostring(#(ui.list or {})))
  end
  if c.stats and type(c.stats.playedText) == "string" then lines[#lines + 1] = T("playedSuffix", c.stats.playedText) end
  if type(c.story) == "string" then lines[#lines + 1] = c.story end
  if type(c.detourText) == "string" then lines[#lines + 1] = c.detourText end
  return lines
end

local function sizeChip(b, w, h)
  b.faceW, b.faceH = w, h
  b:SetSize(w, h)
  b.face:SetSize(w, h)
  W().call(b.diaryPaint, b)
end

local function newChip(ui, tilt)
  local D = W().Diary
  local b = D.NewSticker(ui.chipRoot or ui.frame, "", function(self) ui.cb.onChapter(self.index) end,
    { height = Playback.CHIP_H, tilt = tilt, tip = function(self) return chipTip(ui, self) end })
  b.text:Hide()
  local name = D.font(b.face, "hand", Playback.CHIP_NAME, "ink")
  name:SetPoint("TOPLEFT", b.face, "TOPLEFT", Playback.CHIP_PAD, -Playback.CHIP_TOP)
  name:SetJustifyH("LEFT")
  name:SetWordWrap(false)
  local num = D.font(b.face, "label", Playback.CHIP_NUM, "sepia")
  num:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, 2)
  num:SetJustifyH("LEFT")
  num:SetWordWrap(false)
  local mark = D.NewInkStroke(b.face, nil, "red", 0.9)
  mark:SetPoint("TOPLEFT", b.face, "BOTTOMLEFT", Playback.CHIP_PAD - 2, 1)
  mark:SetPoint("TOPRIGHT", b.face, "BOTTOMRIGHT", -(Playback.CHIP_PAD - 2), 1)
  mark:Hide()
  b.name, b.num, b.mark = name, num, mark
  b:HookScript("OnEnter", chipColor)
  b:HookScript("OnLeave", chipColor)
  b:HookScript("OnHide", chipColor)
  chipColor(b)
  return b
end

local function newPin(ui)
  local b = newChip(ui, Playback.PIN_TILT)
  b.isPin = true
  local badge = W().Diary.NewBadge(b.face, { size = Playback.PIN_BADGE, textSize = 10 })
  badge:SetPoint("CENTER", b.face, "TOPRIGHT", -Playback.PIN_BADGE / 2 + 4, -3)
  b.badge = badge
  return b
end

local function chapterButton(ui, i)
  local b = ui.chapters[i]
  if b then return b end
  local tilts = Playback.CHIP_TILTS
  b = newChip(ui, tilts[(i - 1) % #tilts + 1])
  ui.chapters[i] = b
  return b
end

local function chipWidth(ui, c, i)
  local name, label = Playback.chipTexts(c, i)
  ui.mName:SetText(name)
  ui.mNum:SetText(label)
  local D = W().Diary
  local w = max(D.measure(ui.mName), D.measure(ui.mNum)) + 2 * Playback.CHIP_PAD + 2
  return min(Playback.CHIP_MAX, max(Playback.CHIP_MIN, w)), name, label
end

function Playback.setChapters(ui, chapters, selected, total, totalSelected)
  local list = chapters or {}
  if list ~= ui.list then
    ui.widths = {}
    for i, c in ipairs(list) do ui.widths[i] = chipWidth(ui, c, i) end
  end
  if total ~= ui.total then
    ui.total = total
    ui.pinW = total and min(Playback.CHIP_MAX, (chipWidth(ui, total, 0)) + Playback.PIN_BADGE / 2) or nil
  end
  ui.pinX = ui.barX
  local x0 = ui.total and (ui.pinX + ui.pinW + Playback.PIN_GAP) or ui.barX
  ui.listX0, ui.listW0 = x0, ui.barX + ui.barW - x0
  ui.listX, ui.listW = ui.listX0, ui.listW0
  local selChanged = ui.selected ~= selected or ui.page == nil
  ui.list, ui.selected, ui.totalSelected = list, selected, totalSelected and true or false
  if ui.grid then
    ui.pages = Playback.pages(ui.widths, ui.grid.w, ui.grid.rows)
    if selChanged then ui.page = Playback.pageOf(ui.pages, selected or #list) or #ui.pages end
    Playback.layoutChapters(ui)
    return
  end
  ui.first = Playback.clampFirst(ui.widths, ui.first or 1, ui.listW0, selected)
  Playback.layoutChapters(ui)
end

local function layoutPin(ui)
  local c = ui.total
  if not c then
    if ui.pin then ui.pin:Hide() end
    return
  end
  local b = ui.pin
  if not b then
    b = newPin(ui)
    ui.pin = b
  end
  b.index, b.chapter = 0, c
  local name, label = Playback.chipTexts(c, 0)
  b.name:SetText(name)
  b.num:SetText(label)
  local tw = max(10, ui.pinW - 2 * Playback.CHIP_PAD - Playback.PIN_BADGE / 2)
  b.name:SetWidth(tw)
  b.num:SetWidth(tw)
  b.badge:SetValue(tonumber(c.stays) or #(ui.list or {}))
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", ui.pinX, ui.barY)
  sizeChip(b, ui.pinW, Playback.CHIP_H)
  b.selected = ui.totalSelected
  chipColor(b)
  b:Show()
end

local function layoutGrid(ui)
  local list, widths, g = ui.list or {}, ui.widths or {}, ui.grid
  ui.pages = ui.pages or Playback.pages(widths, g.w, g.rows)
  local pages = ui.pages
  ui.page = max(1, min(ui.page or 1, max(1, #pages)))
  local pg = pages[ui.page]
  ui.first = pg and pg.first or 1
  ui.shown = pg and pg.count or 0
  if ui.pin then ui.pin:Hide() end
  local prevOn, nextOn = ui.page > 1, ui.page < #pages
  ui.nav:SetEnabled(prevOn, nextOn)
  ui.nav.frame:SetShown(prevOn or nextOn)
  if ui.range then
    local txt = ""
    if ui.navOut and #pages > 1 and pg and pg.count > 0 then
      local a, b = pg.first, pg.first + pg.count - 1
      txt = T("chapterOf", tostring(a) .. (b > a and ("–" .. tostring(b)) or ""), tostring(#list))
    end
    ui.range:SetText(txt)
    ui.range:SetShown(txt ~= "")
  end
  local used = 0
  if pg then
    for r, row in ipairs(pg.rows) do
      local x = g.x
      local y = g.y - (r - 1) * (Playback.CHIP_H + g.gapY)
      for i = row.from, row.to do
        used = used + 1
        local c = list[i]
        local b = chapterButton(ui, used)
        b.index, b.chapter = i, c
        local name, label = Playback.chipTexts(c, i)
        b.name:SetText(name)
        b.num:SetText(label)
        local bw = min(widths[i] or 60, g.w)
        b.name:SetWidth(max(10, bw - 2 * Playback.CHIP_PAD))
        b.num:SetWidth(max(10, bw - 2 * Playback.CHIP_PAD))
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", ui.chipRoot or ui.frame, "TOPLEFT", x, y)
        sizeChip(b, bw, Playback.CHIP_H)
        x = x + bw + Playback.CHIP_GAP
        b.selected = (i == ui.selected)
        chipColor(b)
        b:Show()
      end
    end
  end
  for slot = used + 1, #ui.chapters do
    local b = ui.chapters[slot]
    if b then
      b.index, b.chapter = nil, nil
      b:Hide()
    end
  end
end
Playback.layoutGrid = layoutGrid

function Playback.placeGrid(ui, x, y, rows)
  local gf = ui and ui.gridFrame
  if not gf then return false end
  rows = max(1, floor(tonumber(rows) or ui.grid.rows))
  local moved = ui.gridX ~= x or ui.gridY ~= y
  if moved then
    ui.gridX, ui.gridY = x, y
    gf:ClearAllPoints()
    gf:SetPoint("TOPLEFT", ui.gridParent, "TOPLEFT", x, -y)
  end
  if rows == ui.grid.rows and not moved then return false end
  ui.grid.rows = rows
  gf:SetHeight(rows * Playback.CHIP_H + (rows - 1) * ui.grid.gapY)
  if ui.widths then
    ui.pages = Playback.pages(ui.widths, ui.grid.w, rows)
    ui.page = Playback.pageOf(ui.pages, ui.selected or #(ui.list or {})) or #ui.pages
    Playback.layoutChapters(ui)
  end
  return true
end

function Playback.setGridShown(ui, on)
  if ui and ui.gridFrame then ui.gridFrame:SetShown(on and true or false) end
end

function Playback.layoutChapters(ui)
  if ui.grid then return layoutGrid(ui) end
  local list, widths = ui.list or {}, ui.widths or {}
  ui.listX, ui.listW = ui.listX0 or ui.barX, ui.listW0 or ui.barW
  ui.first = Playback.clampFirst(widths, ui.first or 1, ui.listW, nil)
  local shown = Playback.fitCount(widths, ui.first, ui.listW)
  layoutPin(ui)
  ui.shown = shown
  local prevOn, nextOn = ui.first > 1, ui.first + shown - 1 < #list
  ui.nav:SetEnabled(prevOn, nextOn)
  ui.nav.frame:SetShown(prevOn or nextOn)
  if ui.range then
    local n = #list
    local a, b = ui.first, ui.first + shown - 1
    local txt = ""
    if ui.navOut and (prevOn or nextOn) and shown > 0 then
      txt = T("chapterOf", tostring(a) .. (b > a and ("–" .. tostring(b)) or ""), tostring(n))
    end
    ui.range:SetText(txt)
    ui.range:SetShown(txt ~= "")
  end
  local gap = Playback.CHIP_GAP
  local x = ui.listX
  for slot = 1, Playback.CHIP_POOL do
    local i = ui.first + slot - 1
    local c = list[i]
    if c and slot <= shown then
      local b = chapterButton(ui, slot)
      b.index, b.chapter = i, c
      local name, label = Playback.chipTexts(c, i)
      b.name:SetText(name)
      b.num:SetText(label)
      local bw = min(widths[i] or 60, ui.listW)
      b.name:SetWidth(max(10, bw - 2 * Playback.CHIP_PAD))
      b.num:SetWidth(max(10, bw - 2 * Playback.CHIP_PAD))
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", x, ui.barY)
      sizeChip(b, bw, Playback.CHIP_H)
      x = x + bw + gap
      b.selected = (i == ui.selected)
      chipColor(b)
      b:Show()
    elseif ui.chapters[slot] then
      local b = ui.chapters[slot]
      b.index, b.chapter = nil, nil
      b:Hide()
    end
  end
end

function Playback.whenVariants(s)
  s = tostring(s or "")
  local out = { s }
  local short = s:gsub("(%d%d?%.%d%d?%.)%d%d%d%d$", "%1"):gsub("(%d%d?/%d%d?)/%d%d%d%d$", "%1")
  if short ~= s then out[#out + 1] = short end
  local bare = s:gsub("%s*·%s*[^·]*$", "")
  if bare ~= s and bare ~= "" and bare ~= out[#out] then out[#out + 1] = bare end
  return out
end

function Playback.playedVariants(s)
  s = tostring(s or "")
  local out = { s }
  local short = s:gsub("%s+gespielt$", "")
  if short ~= s and short ~= "" then out[#out + 1] = short end
  return out
end

local function textW(fs, s)
  fs:SetText(s)
  for _, m in ipairs({ "GetUnboundedStringWidth", "GetStringWidth" }) do
    local fn = fs[m]
    if type(fn) == "function" then
      local ok, v = pcall(fn, fs)
      v = ok and tonumber(v) or nil
      if v and v == v and v > 0 then return v end
    end
  end
  return 0
end

Playback.INFO_GAP = 12
function Playback.fitInfo(ui, when, played)
  when, played = tostring(when or ""), tostring(played or "")
  if ui.infoWhen == when and ui.infoPlayed == played then return end
  ui.infoWhen, ui.infoPlayed = when, played
  local avail = ui.infoW or 0
  local wv, pv = Playback.whenVariants(when), Playback.playedVariants(played)
  local pw = textW(ui.played, played)
  local ww = textW(ui.when, when)
  if avail <= 0 or pw <= 0 or ww <= 0 then
    ui.when:SetText(when)
    ui.played:SetText(played)
    return
  end
  local wi, pi = 1, 1
  while ww + pw + Playback.INFO_GAP > avail and wi < #wv do
    wi = wi + 1
    ww = textW(ui.when, wv[wi])
  end
  while ww + pw + Playback.INFO_GAP > avail and pi < #pv do
    pi = pi + 1
    pw = textW(ui.played, pv[pi])
  end
  ui.when:SetText(wv[wi])
  ui.played:SetText(pv[pi])
  pw = min(pw, avail * 0.5)
  ui.played:SetWidth(pw + 2)
  ui.when:SetWidth(max(20, avail - pw - Playback.INFO_GAP))
end

function Playback.show(ui, st, info)
  local frac = Playback.frac(st)
  local fw = max(0.01, ui.trackW * frac)
  ui.fill:SetWidth(fw)
  if ui.fill.inkTex then ui.fill:SetTexCoord(0, max(0.001, frac), 0, 1) end
  ui.fill:SetShown(frac > 0.002)
  ui.knob:ClearAllPoints()
  ui.knob:SetPoint("CENTER", ui.track, "TOPLEFT", ui.trackW * frac, -8.5)
  Playback.fitInfo(ui, info.when, info.played)
  ui.playing = st.playing
  ui.play:SetPlaying(st.playing)
  ui.speedToggle:SetValue(st.speed)
end

function Playback.setTicks(ui, ticks)
  local n = 0
  for _, t in ipairs(ticks) do
    n = n + 1
    local fs = ui.ticks[n]
    if not fs then
      fs = ui.track:CreateFontString(nil, "OVERLAY")
      ui.ticks[n] = fs
    end
    Theme.font(fs, t.major and "text" or "label", 11, t.major and Theme.C.ink or Theme.C.sepia)
    fs:SetText(tostring(floor(t.level)))
    fs:ClearAllPoints()
    fs:SetPoint("TOP", ui.track, "TOPLEFT", ui.trackW * t.frac, -12)
    fs:Show()
  end
  for i = n + 1, #ui.ticks do ui.ticks[i]:Hide() end
end

function Playback.setLevelMarks(ui, fracs)
  ui.lvMarks = ui.lvMarks or {}
  local n = 0
  for _, f in ipairs(fracs or {}) do
    n = n + 1
    local t = ui.lvMarks[n]
    if not t then
      t = ui.track:CreateTexture(nil, "ARTWORK", nil, 1)
      t:SetColorTexture(Theme.C.ink[1], Theme.C.ink[2], Theme.C.ink[3], 0.45)
      t:SetSize(1, 6)
      ui.lvMarks[n] = t
    end
    t:ClearAllPoints()
    t:SetPoint("TOP", ui.track, "TOPLEFT", ui.trackW * f, -5.5)
    t:Show()
  end
  for i = n + 1, #ui.lvMarks do ui.lvMarks[i]:Hide() end
  ui.lvMarkCount = n
end

function Playback.startTicking(ui)
  ui.frame:SetScript("OnUpdate", function(_, dt) ui.cb.onUpdate(dt) end)
  ui.ticking = true
end

function Playback.stopTicking(ui)
  if ui.ticking then
    ui.frame:SetScript("OnUpdate", nil)
    ui.ticking = false
  end
end
