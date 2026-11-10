-- Chronik page: profile, level flow, diary by day, XP sources and forecast. Data from journal/model/Chronik.lua
-- (display-ready texts); only frames and layout here.
-- The sub-views "Tagebuch", "Weggefährten" (with the switch "Gruppe | Am Feuer") and "Meilensteine" (pages/ChronikViews.lua,
-- pages/ChronikMeilensteine.lua; Meilensteine only in WoW Forever) open via Page.subs (the dungeon runs moved to the tab Dungeons,
-- pages/Dungeons.lua, I12); the overview
-- sits in its own holders (mainL/mainR), which get hidden. No ticker, no OnUpdate; frames are created in Build, pools
-- are bounded.
local _, ns = ...

local Journal = ns.Journal
local Pages, Widgets, Chronik = Journal and Journal.Pages, Journal and Journal.Widgets, Journal and Journal.Chronik
if not (Pages and Widgets and Chronik) then return end
local D = Widgets.Diary -- diary toolkit "diary with stickers": section heads and day paging
if not D then return end

local Theme = Journal.Theme or {}
local floor, max, min = math.floor, math.max, math.min

local Page = { needs = { index = true } }
Journal.ChronikPage = Page

-- grid (Theme.GRID / docs/raster.md): text block left x 92 / right x 44, 402 wide each. Level ring in column 1, profile
-- from column 5, medals across the full width (6 columns, scrollable); bottom right quill and ink (from y 593), the XP
-- note ends above it.
local G = Theme.GRID
local SZ = G.size                                  -- font steps xs 11 · s 12 · m 14 · l 18 · xl 28
local SL, SR = {}, {}                              -- text block left / right { x, w }
SL.x, SL.w = Theme.gridX("L")
SR.x, SR.w = Theme.gridX("R")
local RING_X, RING_Y, RING_SIZE = SL.x, 64, 120
local CARD_X = Theme.gridX("L", 5)                 -- profile right of the ring (column 5, 16 px gap)
local CARD_W = SL.x + SL.w - CARD_X
local SEAL_X, SEAL_AREA_W = SL.x, SL.w         -- medals: the whole text block
-- journey medals: image slot 56 px (motif + ring from Theme.sealLayers), 6 columns, 35 medals = 6 rows, 2 visible; the
-- area is a ScrollFrame (mouse wheel), the profile above stays fixed.
local SEAL_COLS, SEAL_ICON = 6, 56
-- cell: image, below it the tier dots (one per tier, earned in the tier colour, tiered medals only), below that the
-- name (always visible, up to 2 lines). The height is computed from the parts
-- so a two-line name never reaches into the next row; the name frame is fixed at 2 lines and cuts longer names. Two
-- rows end before the content end of the grid (y 574).
local SEAL_PAD_TOP, SEAL_LINE, SEAL_PAD_BOTTOM = 0, 13, 2   -- SEAL_LINE: line height of the name font (xs 11)
local SEAL_DOT, SEAL_DOT_STEP, SEAL_DOT_GAP = 5, 8, 1       -- tier dots: edge, distance of centres, gap to the image
local SEAL_GAP = SEAL_DOT_GAP + SEAL_DOT + 2                -- image -> name (the dots sit in between)
local SEAL_NAME_H = 2 * SEAL_LINE + 2
local SEAL_W = floor((SEAL_AREA_W - 8) / SEAL_COLS)   -- whole pixels; the scrollbar sits to the right (within the text block)
local SEAL_VIEW_W = SEAL_W * SEAL_COLS
local SEAL_NAME_W = SEAL_W - 2
local SEAL_H = SEAL_PAD_TOP + SEAL_ICON + SEAL_GAP + SEAL_NAME_H + SEAL_PAD_BOTTOM
local SEAL_TOP = 384                         -- top edge (from the top of the page); 2 rows visible down to the content end
local SEAL_VIEW_H = 2 * SEAL_H
local SEAL_STEP = 52                         -- pixels per mouse wheel notch
local SEAL_DIM = { 0.5, 0.46, 0.42 }         -- tint of unearned medals (additionally desaturated)
local SEAL_DOT_OFF = { 0.55, 0.48, 0.38, 0.45 } -- open tier (pale dot)
Page.SEAL = { cols = SEAL_COLS, icon = SEAL_ICON, w = SEAL_W, h = SEAL_H, nameH = SEAL_NAME_H, lineH = SEAL_LINE }
-- level ring: filled strokes in rich dark bronze, fully opaque; unfilled ones pale
Page.RING_ON, Page.RING_OFF = { 0.50, 0.33, 0.07 }, Theme.C and Theme.C.faint or { 0.80, 0.71, 0.53 }
Page.RING_THICK = 4 -- stroke width at 60 levels (Forever); more levels (Retail) get proportionally thinner strokes
local FLOW_H = 100
local DIARY_ROWS, DIARY_ROW_H = 6, G.line.row   -- 6 rows (mouse wheel scrolls): room for XP + note above the quill
local BAR_W = 150   -- XP sources: the bar ends before the forecast note (grid 402 wide)
-- XP sources: legend rows start 38 px below the block top, 14 px apart; the note sits directly below the last visible row
-- and may reach down to SRC_NOTE_BOTTOM (above the quill and ink, from y 593)
local SRC_LEG_Y, SRC_LEG_STEP, SRC_NOTE_BOTTOM = 38, 14, 590

-- locale scope "p.Chronik" (English in locales/enUS_pages.lua), read when drawing
Page.TEXT = ns.Locale.ns("p.Chronik", {
  ofSeals = "%s von %s", longest = "längste: %s", noLevel = "%s ohne Stufe", pageOf = "Seite %s von %s",
  brand = "INK & EMBERS", profile = "STECKBRIEF", page = "CHRONIK", traveller = "REISENDE/R", travellerM = "REISENDER", travellerF = "REISENDE",
  since = "Unterwegs seit", played = "Gesamte Spielzeit", perDay = "Ø pro Spieltag", sessions = "Sitzungen", entries = "Festgehaltene Ereignisse",
  seals = "MEDAILLEN DER REISE", flow = "Stufenfluss", flowSub = "Wie lange jede Stufe dauerte",
  legend = "rote Punkte = gestorben", xpTotal = "EP GESAMT", sources = "WOHER DIE ERFAHRUNG KAM",
  standDate = "Stand: %s", standXp = "Stand: %s · %s", standFmt = "%d.%m.%Y",
  noXp = "Noch keine Erfahrung gesammelt.", diaryEmpty = "Noch nichts erlebt – das Tagebuch wartet.",
  diaryNone = "Aus dem Tagebuch", ofMax = "VON %s", ringStart = "Auf geht's!", prevTip = "Tag davor", nextTip = "Tag danach",
  toDiary = "Tagebuch", toDiaryTip = "Das Tagebuch lesen", toDiaryTip2 = "Jeder Spieltag als Eintrag, Tag für Tag",
  toMates = "Weggefährten", toMatesTip = "Weggefährten ansehen", toMatesTip2 = "Wer mit Euch gereist ist",
  toProfile = "Steckbrief", toProfileTip = "Steckbrief, Stufenfluss und Tagebuch-Auszug",
  toMilestones = "Meilensteine", toMilestonesTip = "Meilensteine ansehen", toMilestonesTip2 = "Alle zehn Stufen eine Bilanz der Reise, bei Stufe 60 der Abschluss",
})

local function font(parent, kind, size, color, justify)
  local fs = Widgets.font(parent, kind, size, color)
  if justify then fs:SetJustifyH(justify) end
  return fs
end

local function set(fs, text) Widgets.setText(fs, text) end

local function tex(parent, layer)
  return parent:CreateTexture(nil, layer or "ARTWORK")
end

-- rule: shared building block of the book layout (journal/widgets/Print.lua)
local function rule(parent, x, y, w)
  return Widgets.NewRule(parent, x, y, w)
end


-- medal image: a fixed slot (size x size, invisible) with the lower layer (motif) and the upper one (tier ring)
-- centred; each layer at its own scale (Theme.sealLayers)
local function sealIcon(parent, size)
  local slot = tex(parent, "BACKGROUND")
  slot:SetSize(size, size)
  slot:SetColorTexture(0, 0, 0, 0)
  local t = tex(parent, "ARTWORK")
  t:SetSize(size, size)
  t:SetPoint("CENTER", slot, "CENTER", 0, 0)
  local m = parent:CreateTexture(nil, "OVERLAY")
  m:SetSize(size, size)
  m:SetPoint("CENTER", slot, "CENTER", 0, 0)
  m:Hide()
  return slot, t, m
end

-- set one image layer (layer = { tex, coords, color, scale } from Theme.sealLayers); dim = not earned
local function paintLayer(t, layer, size, dim)
  if not layer or not layer.tex then
    t:Hide()
    return
  end
  t:SetTexture(layer.tex)
  local c = layer.coords
  if c then t:SetTexCoord(c[1], c[2], c[3], c[4]) else t:SetTexCoord(0, 1, 0, 1) end
  local px = floor(size * (layer.scale or 1) + 0.5)
  t:SetSize(px, px)
  t:SetDesaturated(dim and true or false)
  local col = layer.color or { 1, 1, 1 }
  if dim then
    t:SetVertexColor(col[1] * SEAL_DIM[1], col[2] * SEAL_DIM[2], col[3] * SEAL_DIM[3], 0.9)
  else
    t:SetVertexColor(col[1], col[2], col[3], 1)
  end
  t:Show()
end
Page.paintSealLayer = paintLayer

-- getLines(frame) -> lines, colors (colors optional: colour per line, see Widgets.tip)
local function hover(frame, getLines)
  frame:EnableMouse(true)
  frame:SetScript("OnEnter", function(self)
    local ok, lines, colors = Widgets.call(getLines, self)
    if ok and type(lines) == "table" then Widgets.tip(self, lines, colors) end
  end)
  frame:SetScript("OnLeave", function(self) Widgets.hideTip(self) end)
end

local function buildLeft(self, left)
  local T = Page.TEXT
  local u = {}
  self.L = u
  Widgets.NewPageHead(left, { side = "L" }):SetTexts(T.brand, T.profile)

  -- soft bars (Media/ClockBar) instead of rotated colour areas: smooth edges instead of stairs. Filled strokes in rich
  -- bronze ink,
  -- unfilled pale (Chronik.RING_ON / RING_OFF in SetData below).
  local ring = Widgets.NewRing(left, { size = RING_SIZE, length = 14, thickness = Page.RING_THICK, on = "gold", off = "faint",
    tex = Theme.TEX and Theme.TEX.clockBar, texPad = Theme.CLOCK_BAR_PAD })
  ring.frame:SetPoint("TOPLEFT", left, "TOPLEFT", RING_X, -RING_Y)
  ring.center:SetFont(Widgets.FONT.title, SZ.xl, "")
  ring.center:ClearAllPoints()
  ring.center:SetPoint("CENTER", ring.frame, "CENTER", 0, 6)
  local of = font(ring.frame, "label", SZ.xs, "sepia", "CENTER")
  of:SetPoint("TOP", ring.center, "BOTTOM", 0, -2)
  set(of, T("ofMax", tostring(Chronik.maxLevel())))
  -- on level 1 (a single stroke) a handwritten "Auf geht's!" in the ring instead of a nearly empty chart
  local st = D.font(ring.frame, "hand", 16, "red")
  st:SetPoint("TOP", of, "BOTTOM", 0, -1)
  u.ring, u.ringOf, u.ringStart = ring, of, st

  local x = CARD_X
  local who = font(left, "label", SZ.xs, "sepia", "LEFT")
  who:SetPoint("TOPLEFT", left, "TOPLEFT", x, -G.slots.title.y)
  set(who, T.traveller)
  u.who = who
  local name = font(left, "title", SZ.xl, "ink", "LEFT")
  name:SetPoint("TOPLEFT", left, "TOPLEFT", x, -(G.slots.title.y + 16))
  name:SetWidth(CARD_W)
  name:SetWordWrap(false)
  local sub = font(left, "text", SZ.s, "sepia", "LEFT")
  sub:SetPoint("TOPLEFT", left, "TOPLEFT", x, -(G.slots.title.y + 52))
  sub:SetWidth(CARD_W)
  sub:SetWordWrap(false)
  local motto = font(left, "title", SZ.m, "red", "LEFT")
  motto:SetPoint("TOPLEFT", left, "TOPLEFT", x, -(G.slots.title.y + 72))
  motto:SetWidth(CARD_W)
  u.name, u.sub, u.motto = name, sub, motto
  -- away time (AFK): one small line at the foot of the card (between motto and point lines, beside the ring), hover = details
  -- (model: profile.afk). Empty below one minute of away time.
  local afk = font(left, "label", SZ.xs, "sepia", "LEFT")
  afk:SetPoint("TOPLEFT", left, "TOPLEFT", x, -(G.slots.title.y + 108))
  afk:SetWidth(CARD_W)
  afk:SetWordWrap(false)
  u.afk = afk
  local afkHit = CreateFrame("Frame", nil, left)
  afkHit:SetSize(CARD_W, 14)
  afkHit:SetPoint("TOPLEFT", afk, "TOPLEFT", 0, 1)
  hover(afkHit, function()
    local p = self.view and self.view.profile
    if p and type(p.afk) == "table" and p.afk.text and type(p.afk.tip) == "table" then return p.afk.tip, p.afk.tipColors end
  end)
  u.afkHit = afkHit

  -- point lines: key left, value right, dotted line in between
  u.leads = {}
  for i, key in ipairs({ "since", "played", "perDay", "sessions", "entries" }) do
    local y = -196 - (i - 1) * G.line.text   -- five lines on the text grid (18), ending before the XP line (296)
    local k = font(left, "label", SZ.s, "sepia", "LEFT")
    k:SetPoint("TOPLEFT", left, "TOPLEFT", SL.x, y)
    set(k, T[key])
    -- values in Friz instead of Morpheus small caps (date dots and "min" read badly there)
    local v = font(left, "text", SZ.s + 1, "ink", "RIGHT")
    v:SetPoint("TOPRIGHT", left, "TOPLEFT", SL.x + SL.w, y)
    local dots = tex(left, "ARTWORK")
    dots:SetColorTexture(Widgets.color("sepia", 0.4))
    dots:SetHeight(1)
    dots:SetPoint("BOTTOMLEFT", k, "BOTTOMRIGHT", 6, 3)
    dots:SetPoint("BOTTOMRIGHT", v, "BOTTOMLEFT", -6, 3)
    u.leads[key] = v
    if key == "entries" then
      -- hover over the whole line: breakdown by kind (model: profile.entriesTip, display time only)
      local hit = CreateFrame("Frame", nil, left)
      hit:SetSize(SL.w, 20)
      hit:SetPoint("TOPLEFT", left, "TOPLEFT", SL.x, y + 3)
      hover(hit, function()
        local p = self.view and self.view.profile
        if p and type(p.entriesTip) == "table" then return p.entriesTip, p.entriesTipColors end
      end)
      u.entriesHit = hit
    end
  end

  local xl = font(left, "label", SZ.s, "sepia", "LEFT")
  xl:SetPoint("TOPLEFT", left, "TOPLEFT", SL.x, -296)
  local xp = font(left, "title", SZ.m, "ink", "RIGHT")
  xp:SetPoint("TOPRIGHT", left, "TOPLEFT", SL.x + SL.w, -295)
  local bg = tex(left, "BORDER")
  bg:SetColorTexture(Widgets.color("sepia", 0.18))
  bg:SetPoint("TOPLEFT", left, "TOPLEFT", SL.x, -316)
  bg:SetSize(SL.w, 12)
  local fill = tex(left, "ARTWORK")
  fill:SetColorTexture(Widgets.color("gold", 0.95))
  fill:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, 0)
  fill:SetHeight(12)
  local rest = tex(left, "ARTWORK")
  rest:SetColorTexture(Widgets.color("gold", 0.38))
  rest:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
  rest:SetHeight(12)
  local rt = font(left, "label", SZ.xs, "sepia", "LEFT")
  rt:SetPoint("TOPLEFT", left, "TOPLEFT", SL.x, -333)
  rt:SetWidth(SL.w)
  u.xpLabel, u.xpPct, u.xpBg, u.xpFill, u.xpRest, u.xpRestText = xl, xp, bg, fill, rest, rt

  local sh = font(left, "label", SZ.xs, "sepia", "LEFT")
  sh:SetPoint("TOPLEFT", left, "TOPLEFT", SL.x, -358)
  set(sh, T.seals)
  local sc = font(left, "title", SZ.m, "ink", "RIGHT")
  sc:SetPoint("TOPRIGHT", left, "TOPLEFT", SL.x + SL.w, -356)
  rule(left, SL.x, 376, SL.w)
  u.sealCount = sc
  -- counter "14 von 35 · 31 von 93 Stufen": tooltip with the breakdown by family (model: seals.countTip)
  local sch = CreateFrame("Frame", nil, left)
  sch:SetSize(260, 20)
  sch:SetPoint("TOPRIGHT", left, "TOPLEFT", SL.x + SL.w, -353)
  hover(sch, function()
    local v = self.view and self.view.seals
    if v and type(v.countTip) == "table" then return v.countTip, v.countTipColors end
  end)
  u.sealCountHit = sch
  -- scrollable area: ScrollFrame with a tall content frame (mouse wheel); an error in the handler becomes the page notice
  local rows = math.ceil(#Chronik.SEALS / SEAL_COLS)
  u.sealRows, u.sealContentH = rows, rows * SEAL_H
  local sv = CreateFrame("ScrollFrame", nil, left)
  sv:SetSize(SEAL_VIEW_W, SEAL_VIEW_H)
  sv:SetPoint("TOPLEFT", left, "TOPLEFT", SEAL_X, -SEAL_TOP)
  local content = CreateFrame("Frame", nil, sv)
  content:SetSize(SEAL_VIEW_W, u.sealContentH)
  sv:SetScrollChild(content)
  sv:EnableMouseWheel(true)
  sv:SetScript("OnMouseWheel", function(_, delta)
    delta = tonumber(delta) or 0
    if delta == 0 then return end
    local ok, err = pcall(Page.ScrollSeals, self, -delta * SEAL_STEP)
    if not ok then Pages.fail("chronik", err) end
  end)
  u.sealScroll, u.sealContent, u.sealOffset = sv, content, 0
  -- bar to the right of the area (visible only when it can scroll)
  local track = tex(left, "ARTWORK")
  track:SetColorTexture(Widgets.color("sepia", 0.2))
  track:SetPoint("TOPLEFT", left, "TOPLEFT", SEAL_X + SEAL_VIEW_W + 3, -SEAL_TOP)
  track:SetSize(3, SEAL_VIEW_H)
  local thumb = tex(left, "OVERLAY")
  thumb:SetColorTexture(Widgets.color("sepia", 0.75))
  thumb:SetWidth(5)
  u.sealTrack, u.sealThumb = track, thumb
  u.seals = {}
  for i = 1, #Chronik.SEALS do
    local col, row = (i - 1) % SEAL_COLS, floor((i - 1) / SEAL_COLS)
    local b = CreateFrame("Frame", nil, content)
    b:SetSize(SEAL_W, SEAL_H)
    b:SetPoint("TOPLEFT", content, "TOPLEFT", col * SEAL_W, -row * SEAL_H)
    local slot, icon, motif = sealIcon(b, SEAL_ICON)
    slot:SetPoint("TOP", b, "TOP", 0, -SEAL_PAD_TOP)
    -- tier dots: three small discs centred under the image
    local dots = {}
    for k = 1, 3 do
      local d = tex(b, "ARTWORK")
      d:SetSize(SEAL_DOT, SEAL_DOT)
      if Theme.TEX and Theme.TEX.disc then d:SetTexture(Theme.TEX.disc) end
      d:SetPoint("TOP", slot, "BOTTOM", (k - 2) * SEAL_DOT_STEP, -SEAL_DOT_GAP)
      d:Hide()
      dots[k] = d
    end
    local title = font(b, "text", SZ.xs, "ink", "CENTER")
    title:SetPoint("TOP", slot, "BOTTOM", 0, -SEAL_GAP)
    title:SetSize(SEAL_NAME_W, SEAL_NAME_H)
    title:SetJustifyV("TOP")
    b.slot, b.icon, b.motif, b.dots, b.title = slot, icon, motif, dots, title
    hover(b, function(f)
      local s = f.seal
      if s then return s.tip, s.tipColors end
    end)
    u.seals[i] = b
  end
  Page.ScrollSeals(self, 0)
end

-- shift the medal area by px pixels (limits 0 .. content - visible height), update the bar
function Page.ScrollSeals(self, px)
  local u = self.L
  if not (u and u.sealScroll) then return end
  local range = max(0, u.sealContentH - SEAL_VIEW_H)
  local off = max(0, min(floor((tonumber(u.sealOffset) or 0) + (tonumber(px) or 0) + 0.5), range))
  u.sealOffset = off
  u.sealScroll:SetVerticalScroll(off)
  u.sealRange = range
  if range <= 0 then
    u.sealTrack:Hide()
    u.sealThumb:Hide()
    return
  end
  local th = max(14, floor(SEAL_VIEW_H * SEAL_VIEW_H / u.sealContentH))
  u.sealThumb:SetHeight(th)
  u.sealThumb:ClearAllPoints()
  u.sealThumb:SetPoint("TOPLEFT", self.left, "TOPLEFT", SEAL_X + SEAL_VIEW_W + 2, -SEAL_TOP - floor((SEAL_VIEW_H - th) * off / range))
  u.sealTrack:Show()
  u.sealThumb:Show()
end

local function buildRight(self, right)
  local T = Page.TEXT
  local u = {}
  self.R = u
  u.head = Widgets.NewPageHead(right, { side = "R" })
  u.head:SetTexts("", T.page)

  -- section head "Stufenfluss" (handwriting red, underline); the sub line moves below it.
  -- Grid: section head at the title position (y 66), sub line and "longest" below, chart from the control line
  local ft = D.NewSectionHead(right, T.flow, { width = SR.w })
  ft:SetPoint("TOPLEFT", right, "TOPLEFT", SR.x, -(G.slots.title.y - 4))
  local fs = font(right, "label", SZ.s, "sepia", "LEFT")
  fs:SetPoint("TOPLEFT", right, "TOPLEFT", SR.x, -(G.slots.title.y + 34))
  set(fs, T.flowSub)
  local fm = font(right, "label", SZ.xs, "sepia", "RIGHT")
  fm:SetPoint("TOPRIGHT", right, "TOPLEFT", SR.x + SR.w, -(G.slots.title.y + 35))
  u.flowMax = fm
  local top = G.slots.ctrl.y
  local grid = tex(right, "BORDER")
  grid:SetColorTexture(Widgets.color("sepia", 0.2))
  grid:SetPoint("TOPLEFT", right, "TOPLEFT", SR.x, -top)
  grid:SetSize(SR.w, 1)
  local base = tex(right, "BORDER")
  base:SetColorTexture(Widgets.color("sepia", 0.5))
  base:SetPoint("TOPLEFT", right, "TOPLEFT", SR.x, -top - FLOW_H)
  base:SetSize(SR.w, 1)
  local cols = Widgets.NewColumns(right, { width = SR.w, height = FLOW_H, gap = 2, color = "ink", markColor = "red", sketch = true,
    tip = function(item) return item.tip end })
  cols.frame:SetPoint("TOPLEFT", right, "TOPLEFT", SR.x, -top)
  u.cols = cols
  -- empty state in handwriting; grid, baseline and axis disappear then (no chart with an empty column)
  local fe = D.emptyNote(right, SR.w - 60)
  fe:SetPoint("CENTER", cols.frame, "CENTER", 0, -6)
  u.flowEmpty, u.flowGrid, u.flowBase = fe, grid, base
  u.axis = Widgets.Pool(function()
    local a = font(right, "label", SZ.xs, "sepia", "CENTER")
    a:SetWidth(24)
    return a
  end, function(a) a:SetText("") end, 16)
  u.notes = {}
  for i = 1, 2 do
    local n = font(right, "title", SZ.m, "red", "LEFT")
    n:SetPoint("TOPLEFT", right, "TOPLEFT", SR.x, -(top + FLOW_H + 22) - (i - 1) * G.line.text)
    n:SetWidth(SR.w - 130)
    n:SetWordWrap(false)
    u.notes[i] = n
  end
  local lg = font(right, "label", SZ.xs, "sepia", "RIGHT")
  lg:SetPoint("TOPRIGHT", right, "TOPLEFT", SR.x + SR.w, -(top + FLOW_H + 24))
  u.legend = lg

  -- diary: section head with the day as text (u.diaryTitle is its font), paging pair to its right
  local diaryY = top + FLOW_H + 22 + 2 * G.line.text + 4
  local dh = D.NewSectionHead(right, "", { width = SR.w - 150 })
  dh:SetPoint("TOPLEFT", right, "TOPLEFT", SR.x, -diaryY)
  u.diaryHead, u.diaryTitle = dh, dh.text
  -- page the day: an error in the handler (broken SV data) becomes the page notice (Pages.fail), never a Lua error
  local function shift(delta)
    local ok, err = pcall(Page.ShiftDay, self, delta)
    if not ok then Pages.fail("chronik", err) end
  end
  u.nav = D.NewNavPair(right, { onPrev = function() shift(-1) end, onNext = function() shift(1) end,
    tipPrev = { T.prevTip }, tipNext = { T.nextTip } })
  u.nav.frame:SetPoint("TOPRIGHT", right, "TOPLEFT", SR.x + SR.w + 4, -(diaryY + 4))
  u.prev, u.next = u.nav.prev, u.nav.next
  -- "Seite x von y" directly left of the arrow pair (grid: paging on the right)
  local pos = font(right, "label", SZ.s, "sepia", "RIGHT")
  pos:SetPoint("RIGHT", u.nav.frame, "LEFT", -6, 0)
  u.dayPos = pos
  local list = Widgets.NewList(right, {
    rows = DIARY_ROWS, rowHeight = DIARY_ROW_H, width = SR.w, empty = T.diaryEmpty, emptyHand = true,
    build = function(row)
      local tm = font(row, "title", SZ.m, "red", "LEFT")
      tm:SetPoint("LEFT", row, "LEFT", 2, 0)
      tm:SetWidth(46)
      row.time = tm
      row.label:ClearAllPoints()
      row.label:SetPoint("LEFT", row, "LEFT", 52, 0)
      row.label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
      local line = tex(row, "BORDER")
      line:SetColorTexture(Widgets.color("sepia", 0.18))
      line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
      line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
      line:SetHeight(1)
      hover(row, function(r)
        local e = r.entry
        if not e then return nil end
        local text = Chronik.entryText(self.view, e)
        -- campfire: below it who sat at the fire (class, level), foreign text only sanitized (journal/pages/ChronikViews.lua)
        local FV = Journal.FireMatesView
        if type(e.ctx) == "table" and e.ctx.kind == "campfire" and FV and FV.entryTip then
          local lines, colors = FV.entryTip(e, text)
          if lines then return lines, colors end
        end
        local link = type(e.ctx) == "table" and e.ctx.kind == "loot" and e.ctx.link or nil
        -- finds: original item tooltip, below it time and diary line
        return { e.clock or "", text, item = link, itemExtra = link and { (e.clock or "") .. " " .. (text or "") } or nil }
      end)
    end,
    fill = function(row, entry)
      row.entry = entry
      set(row.time, entry.clock)
      set(row.label, Chronik.entryText(self.view, entry))
    end,
    clear = function(row)
      row.entry = nil
      set(row.time, "")
      Widgets.hideTip(row)
    end,
  })
  list.frame:SetPoint("TOPLEFT", right, "TOPLEFT", SR.x, -(diaryY + 38))
  u.list = list

  local y0 = -(diaryY + 38 + DIARY_ROWS * DIARY_ROW_H + 14)
  local tot = font(right, "title", SZ.xl, "ink", "LEFT")
  tot:SetPoint("TOPLEFT", right, "TOPLEFT", SR.x, y0)
  local totL = font(right, "label", SZ.xs, "sepia", "LEFT")
  totL:SetPoint("TOPLEFT", right, "TOPLEFT", SR.x, y0 - 34)
  set(totL, T.xpTotal)
  Widgets.fitLine(totL, Theme.gridX("R", 4) - SR.x - 6) -- label ends before the bar column (English is longer than German)
  u.xpTotal = tot
  local bx = Theme.gridX("R", 4)
  local sl = font(right, "label", SZ.xs, "sepia", "LEFT")
  sl:SetPoint("TOPLEFT", right, "TOPLEFT", bx, y0)
  set(sl, T.sources)
  Widgets.fitLine(sl, BAR_W) -- ends before the forecast note (never into the neighbouring column)
  local sbg = tex(right, "BORDER")
  sbg:SetColorTexture(Widgets.color("sepia", 0.15))
  sbg:SetPoint("TOPLEFT", right, "TOPLEFT", bx, y0 - 18)
  sbg:SetSize(BAR_W, 12)
  u.srcBg = sbg
  u.segs, u.legends = {}, {}
  for i = 1, #Chronik.SOURCES do
    local s = tex(right, "ARTWORK")
    s:SetHeight(12)
    u.segs[i] = s
    local sw = tex(right, "ARTWORK")
    sw:SetSize(8, 8)
    sw:SetPoint("TOPLEFT", right, "TOPLEFT", bx, y0 - 38 - (i - 1) * 14)
    local lt = font(right, "label", SZ.xs, "ink", "LEFT")
    lt:SetPoint("LEFT", sw, "RIGHT", 5, 0)
    lt:SetWidth(BAR_W - 14)
    u.legends[i] = { swatch = sw, text = lt }
  end
  local sn = font(right, "label", SZ.xs, "sepia", "LEFT")
  sn:SetPoint("TOPLEFT", right, "TOPLEFT", bx, y0 - SRC_LEG_Y - #Chronik.SOURCES * SRC_LEG_STEP) -- placed again per legend length (drawSources)
  sn:SetWidth(SR.x + SR.w - 10 - bx)
  u.srcY0 = y0
  sn:SetJustifyV("TOP")
  u.srcNote = sn
  -- explanation of rested bonus/jump in the tooltip above the short line
  local snHit = CreateFrame("Frame", nil, right)
  snHit:SetPoint("TOPLEFT", sn, "TOPLEFT", 0, 2)
  snHit:SetSize(SR.x + SR.w - 10 - bx, 30)
  hover(snHit, function()
    local src = self.view and self.view.sources
    if not src then return nil end
    local lines = {}
    for _, tip in ipairs({ src.restedTip, src.unclearTip }) do
      if type(tip) == "table" then
        for _, l in ipairs(tip) do lines[#lines + 1] = l end
      end
    end
    return #lines > 0 and lines or nil
  end)
  u.srcNoteHit = snHit
  local se = font(right, "text", SZ.s, "sepia", "LEFT")
  se:SetPoint("TOPLEFT", right, "TOPLEFT", bx, y0 - 20)
  se:SetWidth(BAR_W)
  u.srcEmpty = se

  local note = Widgets.NewNote(right, { width = 138, titleSize = SZ.m, textSize = SZ.xs })
  note.frame:SetPoint("TOPRIGHT", right, "TOPLEFT", SR.x + SR.w, y0 + 2)
  u.note = note
end

function Page:Build(left, right)
  -- overview in its own holders so the sub-views (pages/ChronikViews.lua) can hide it
  local mainL, mainR = CreateFrame("Frame", nil, left), CreateFrame("Frame", nil, right)
  mainL:SetAllPoints(left)
  mainR:SetAllPoints(right)
  self.mainL, self.mainR = mainL, mainR
  self.holderL, self.holderR = left, right
  left, right = mainL, mainR
  self.left, self.right = left, right
  buildLeft(self, left)
  buildRight(self, right)
  -- mouse wheel on the right page (outside the diary list, which uses the wheel itself) pages the days;
  -- an error in the handler becomes the page notice as with the quests
  right:EnableMouseWheel(true)
  right:SetScript("OnMouseWheel", function(_, delta)
    delta = tonumber(delta) or 0
    if delta == 0 then return end
    local ok, err = pcall(Page.ShiftDay, self, delta > 0 and -1 or 1)
    if not ok then Pages.fail("chronik", err) end
  end)
  self.built = true
end

-- "Reisender" / "Reisende" by the character's sex (UnitSex: 2 male, 3 female), else "Reisende/r"
function Page.travellerLabel(guest)
  local T = Page.TEXT
  if guest then return T.traveller end -- another character's book: not the logged-in character's sex
  local ok, sex = false, nil
  if type(UnitSex) == "function" then ok, sex = pcall(UnitSex, "player") end
  if ok and sex == 2 then return T.travellerM end
  if ok and sex == 3 then return T.travellerF end
  return T.traveller
end

-- Guest book: the experience bar is the stand of the last login, marked with its date ("Stand: 07.11.2026 · <rested note>").
-- Own book / no bar / no date: the model's own text.
function Page.xpNote(guest, xp)
  if not guest or not xp or xp.maxed or not xp.max then return xp and xp.restText end
  local seen = guest.lastSeen
  local okd, d = false, nil
  if type(seen) == "number" then okd, d = pcall(date, Page.TEXT.standFmt, seen) end
  if not okd or type(d) ~= "string" or d == "" then return xp.restText end
  local CT = Journal.Chronik and Journal.Chronik.TEXT
  local rest
  if CT and xp.rested then rest = CT("restLeft", Journal.Texts.int(xp.rested)) elseif CT then rest = CT.restNone end
  if rest then return Page.TEXT("standXp", d, rest) end
  return Page.TEXT("standDate", d)
end

local function drawLeft(self, view)
  local u, p, xp = self.L, view.profile, view.xp
  -- one stroke per level up to the client's highest level (Forever 60, Retail 80/90): thinner strokes for more levels
  local top = Chronik.maxLevel()
  local lvl = min(tonumber(p.level) or 0, top)
  u.ring.thickness = max(2, min(Page.RING_THICK, Page.RING_THICK * Chronik.MAX_LEVEL / top))
  set(u.ringOf, Page.TEXT("ofMax", Journal.Texts.int(top)))
  u.ring:SetData(top, function(i)
    if i <= lvl then return Page.RING_ON, 1 end
    return Page.RING_OFF, 0.6
  end)
  set(u.ring.center, Journal.Texts.int(p.level))
  set(u.ringStart, lvl <= 1 and Page.TEXT.ringStart or "")
  set(u.who, Page.travellerLabel(self.guest))
  set(u.name, p.name)
  set(u.sub, p.subtitle)
  set(u.motto, p.motto)
  set(u.afk, type(p.afk) == "table" and p.afk.text or "")
  Widgets.fitLine(u.afk, CARD_W) -- English is longer: smaller instead of cut off
  set(u.leads.since, p.since)
  set(u.leads.played, p.played)
  set(u.leads.perDay, p.perDay)
  set(u.leads.sessions, Journal.Texts.int(p.sessions))
  set(u.leads.entries, Journal.Texts.int(p.entries))

  set(u.xpLabel, xp.label)
  set(u.xpPct, xp.pctText)
  set(u.xpRestText, Page.xpNote(self.guest, xp))
  local pct = tonumber(xp.pct)
  if pct and pct > 0 then
    u.xpFill:SetWidth(max(1, SL.w * pct))
    u.xpFill:Show()
  else
    u.xpFill:SetWidth(0.01)
    u.xpFill:Hide()
  end
  local rested = (xp.rested and xp.max and xp.max > 0) and min(xp.rested / xp.max, 1 - (pct or 0)) or 0
  if rested > 0 then
    u.xpRest:SetWidth(max(1, SL.w * rested))
    u.xpRest:Show()
  else
    u.xpRest:SetWidth(0.01)
    u.xpRest:Hide()
  end

  local seals = view.seals
  set(u.sealCount, seals.countText or Page.TEXT("ofSeals", Journal.Texts.int(seals.broken), Journal.Texts.int(seals.total)))
  local shown = 0 -- visible cells so far: a hidden medal (s.hidden, e.g. health locked) leaves no gap in the grid
  for i, b in ipairs(u.seals) do
    local s = seals.list[i]
    local def = Chronik.SEALS[i]
    b.seal = s
    if s and def and s.hidden then
      b:Hide()
    elseif s and def then
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", u.sealContent, "TOPLEFT", (shown % SEAL_COLS) * SEAL_W, -floor(shown / SEAL_COLS) * SEAL_H)
      shown = shown + 1
      b:Show()
      local dim = not s.broken
      local base, motif = Theme.sealLayers(def, s.broken and s.tier or nil)
      paintLayer(b.icon, base, SEAL_ICON, dim)
      paintLayer(b.motif, motif, SEAL_ICON, dim)
      b.title:SetTextColor(Widgets.color(dim and "sepia" or "ink"))
      -- grid label: catalogue field grid (long single words hyphenated by hand, the client truncates instead of wrapping)
      set(b.title, def.grid or s.title)
      -- dots: one per tier, earned in their tier colour; one-off medals without dots
      for k, d in ipairs(b.dots) do
        if s.stepped and k <= (s.max or 0) then
          local st = s.steps and s.steps[k]
          local tc = st and Chronik.TIERS[st.tier]
          if tc then d:SetVertexColor(tc.color[1], tc.color[2], tc.color[3], 1) else d:SetVertexColor(SEAL_DOT_OFF[1], SEAL_DOT_OFF[2], SEAL_DOT_OFF[3], SEAL_DOT_OFF[4]) end
          d:Show()
        else
          d:Hide()
        end
      end
    else
      b:Hide()
    end
  end
end

local function drawFlow(self, flow)
  local u = self.R
  local items = {}
  if not flow.empty then
    for i, c in ipairs(flow.cols) do
      items[i] = { value = c.value, color = c.color, mark = c.mark, tip = c.tip }
    end
  end
  for _, t in ipairs({ u.flowGrid, u.flowBase }) do
    if flow.empty then t:Hide() else t:Show() end
  end
  u.cols:SetData(items)
  u.axis:ReleaseAll()
  local n = #items
  if n > 0 then
    local gap = 2
    local colW = (SR.w - gap * (n - 1)) / n
    if colW < 1 then colW, gap = 1, 0 end
    for _, a in ipairs(flow.axis) do
      local fs = u.axis:Acquire()
      if not fs then break end
      fs:SetPoint("TOP", self.right, "TOPLEFT", SR.x + (a.i - 1) * (colW + gap) + colW / 2, -(G.slots.ctrl.y + FLOW_H + 4))
      set(fs, a.text)
    end
  end
  set(u.flowMax, flow.maxText and Page.TEXT("longest", flow.maxText) or "")
  set(u.flowEmpty, flow.empty and Chronik.TEXT.noFlow or "")
  for i = 1, 2 do set(u.notes[i], flow.notes[i]) end
  local legend = Page.TEXT.legend
  if flow.deathsNoLevel and flow.deathsNoLevel > 0 then
    legend = legend .. " · " .. Page.TEXT("noLevel", Journal.Texts.int(flow.deathsNoLevel))
  end
  set(u.legend, (flow.deathsTotal or 0) > 0 and legend or "")
end

-- day in the diary: index into view.diary.days (nil = newest)
local function drawDiary(self)
  local u, diary = self.R, self.view.diary
  local days = diary.days
  local n = #days
  if n == 0 then
    set(u.diaryTitle, Page.TEXT.diaryNone)
    u.list:SetItems({})
    u.nav:SetEnabled(false, false)
    set(u.dayPos, "")
    return
  end
  local i = self.dayIdx
  if not i or i < 1 or i > n then i = n end
  self.dayIdx = i
  local d = days[i]
  set(u.diaryTitle, d.title)
  u.list:SetOffset(0)
  u.list:SetItems(d.entries)
  u.nav:SetEnabled(i > 1, i < n)
  set(u.dayPos, n > 1 and Page.TEXT("pageOf", Journal.Texts.int(i), Journal.Texts.int(n)) or "")
end

function Page.ShiftDay(self, delta)
  if not self.view then return end
  local n = #self.view.diary.days
  local i = (self.dayIdx or n) + (tonumber(delta) or 0)
  if i < 1 or i > n then return end
  self.dayIdx = i
  drawDiary(self)
end

local function drawSources(self, src)
  local u = self.R
  set(u.xpTotal, src.totalText)
  Widgets.fitLine(u.xpTotal, Theme.gridX("R", 4) - SR.x - 6, 18) -- big number ("4,79 Mio.") stays before the bar column
  local x = 0
  for i, seg in ipairs(u.segs) do
    local part = src.parts[i]
    local lg = u.legends[i]
    if part then
      local w = BAR_W * part.pct / 100
      seg:SetColorTexture(Widgets.color(part.color, 0.9))
      seg:ClearAllPoints()
      seg:SetPoint("TOPLEFT", u.srcBg, "TOPLEFT", x, 0)
      seg:SetWidth(max(w, 0.01))
      seg:SetShown(w >= 0.5)
      x = x + w
      lg.swatch:SetColorTexture(Widgets.color(part.color, 0.9))
      lg.swatch:Show()
      set(lg.text, part.label .. " " .. part.pctText)
    else
      seg:Hide()
      lg.swatch:Hide()
      set(lg.text, "")
    end
  end
  local empty = #src.parts == 0
  u.srcBg:SetShown(not empty)
  set(u.srcEmpty, empty and Page.TEXT.noXp or "")
  local notes = {}
  if src.restedText then notes[#notes + 1] = src.restedText end
  if src.unclearText then notes[#notes + 1] = src.unclearText end
  set(u.srcNote, table.concat(notes, "\n"))
  -- the note starts below the last visible legend row (or the two-line empty text), so it never overlaps the legend
  -- whatever the number of rows or the language; the line count is capped to the room left above the quill
  local y0 = u.srcY0
  if y0 then
    local lineH = Page.SEAL.lineH
    local top = empty and (20 + 2 * lineH + 4) or (SRC_LEG_Y + #src.parts * SRC_LEG_STEP)
    local lines = math.max(1, floor((SRC_NOTE_BOTTOM + y0 - top) / lineH)) -- y0 is negative: the block top is -y0
    u.srcNote:ClearAllPoints()
    u.srcNote:SetPoint("TOPLEFT", self.right, "TOPLEFT", Theme.gridX("R", 4), y0 - top)
    if u.srcNote.SetMaxLines then u.srcNote:SetMaxLines(lines) end
    u.srcNoteHit:ClearAllPoints()
    u.srcNoteHit:SetPoint("TOPLEFT", u.srcNote, "TOPLEFT", 0, 2)
    u.srcNoteHit:SetHeight(lines * lineH + 2)
  end
end

-- sub-views: diary and companions. Entry via the sub-bookmarks (Page.subs), Esc leads back to the overview
-- (ChronikViews: D.escKeys on the sub-view); every change is reported to Pages.subChanged.

local function openSub(self, field, ctor)
  local View = Journal[ctor]
  if not (self.built and View and self.index) then return end
  if self.sub and self.sub ~= self[field] then self.sub:Close() end
  if not self[field] then self[field] = View.new(self, self.holderL, self.holderR) end
  self.mainL:Hide()
  self.mainR:Hide()
  self.sub = self[field]
  self.sub:Open(self.index, self.now)
  Pages.subChanged("chronik")
end

function Page.OpenDiary(self) openSub(self, "diaryView", "DiaryView") end
function Page.OpenCompanions(self) openSub(self, "matesView", "CompanionsView") end
function Page.OpenFire(self) openSub(self, "fireView", "FireMatesView") end -- inside "Weggefährten" (switch "Am Feuer")
function Page.OpenMilestones(self) openSub(self, "milestonesView", "MilestonesView") end

function Page:CloseSub()
  local was = self.sub
  if self.sub then self.sub:Close() end
  self.sub = nil
  if self.mainL then
    self.mainL:Show()
    self.mainR:Show()
  end
  if was then Pages.subChanged("chronik") end
end

-- sub-bookmarks (contract journal/Pages.lua): overview · diary · companions · milestones. Labels are read late (the language is not
-- yet fixed when the file loads)
local function subTab(key, label, tip1, tip2)
  return setmetatable({ key = key }, { __index = function(_, k)
    if k == "label" then return Page.TEXT[label] end
    if k == "tip" then return { Page.TEXT[tip1], Page.TEXT[tip2] } end
  end })
end
Page.subs = {
  subTab("steckbrief", "toProfile", "toProfile", "toProfileTip"),
  subTab("tagebuch", "toDiary", "toDiaryTip", "toDiaryTip2"),
  subTab("weggefaehrten", "toMates", "toMatesTip", "toMatesTip2"),
  subTab("meilensteine", "toMilestones", "toMilestonesTip", "toMilestonesTip2"),
}

-- Retail: the milestones belong to WoW Forever (as the level-up note), so their bookmark stays out there
Pages.hideSub("chronik", "meilensteine", function()
  local L = Journal.Lehrplan
  return L ~= nil and type(L.active) == "function" and L.active() == false
end)

function Page:GetSub()
  if self.sub and self.sub == self.diaryView then return "tagebuch" end
  -- the companions bookmark holds two views: the group (matesView) and the people at the fire (fireView)
  if self.sub and (self.sub == self.matesView or self.sub == self.fireView) then return "weggefaehrten" end
  if self.sub and self.sub == self.milestonesView then return "meilensteine" end
  return "steckbrief"
end

function Page:ShowSub(key)
  if key == self:GetSub() then return end
  if key == "tagebuch" then
    Page.OpenDiary(self)
  elseif key == "weggefaehrten" then
    Page.OpenCompanions(self)
  elseif key == "meilensteine" then
    Page.OpenMilestones(self)
  else
    self:CloseSub()
  end
end

function Page:Refresh(data)
  if not self.built then return end
  self.index, self.now = data.index, data.now
  self.guest = data.guest -- another character's book (read only) or nil
  if self.sub then self.sub:Refresh(data.index, data.now) end
  local view = Chronik.evaluate(data.index, { live = data.live, now = data.now })
  if not view then error("Chronik: keine Auswertung") end
  local fresh = self.view == nil or self.view.diary ~= view.diary
  local atNewest = self.view == nil or self.dayIdx == nil or self.dayIdx == #self.view.diary.days
  local keepDay = (not atNewest) and self.view and self.view.diary.days[self.dayIdx] and self.view.diary.days[self.dayIdx].day
  self.view = view
  self.R.head:SetTexts(Widgets.playerLine(data) or view.profile.head, Page.TEXT.page)
  drawLeft(self, view)
  drawFlow(self, view.flow)
  if fresh then
    self.dayIdx = nil
    if keepDay then
      for i, d in ipairs(view.diary.days) do
        if d.day == keepDay then self.dayIdx = i end
      end
    end
    drawDiary(self)
  else
    self.R.list:Refresh()
  end
  drawSources(self, view.sources)
  local fc = view.forecast
  self.R.note:SetContent(fc.title, fc.body)
end

function Page:OnHide()
  local L, R = self.L, self.R
  if L then
    for _, b in ipairs(L.seals) do Widgets.hideTip(b) end
    if L.entriesHit then Widgets.hideTip(L.entriesHit) end
    if L.sealCountHit then Widgets.hideTip(L.sealCountHit) end
    if L.afkHit then Widgets.hideTip(L.afkHit) end
  end
  -- the next open starts with the overview again
  if self.sub then self:CloseSub() end
  if R then
    Widgets.hideTip(R.nav.prev)
    Widgets.hideTip(R.nav.next)
    for _, row in ipairs(R.list.rows) do Widgets.hideTip(row) end
    local hits = R.cols.hits and R.cols.hits.used
    if type(hits) == "table" then for _, h in ipairs(hits) do Widgets.hideTip(h) end end
  end
end

Pages.register("chronik", Page)
