-- Momente page: the album as a wall of handwritten notes (3 x 2 per sheet, filter chips, paging) or the reading window of a
-- book; right the play-time clock, the library and curiosities. Reads only via ns.Journal.Momente; writes only the filter
-- choice.
-- Each moment is a small note (the note pad of the to-do note, Media/TodoPad, tape included) with the symbol of its kind,
-- title, the diary line and day/time in handwriting. Paper and shadow are tilted slightly and fixed per entry (noteLook,
-- from the key); text is never rotated. No pictures, no screenshots. No ticker, no OnUpdate.
local _, ns = ...

local Journal = ns.Journal
local W, Pages, Momente = Journal.Widgets, Journal.Pages, Journal.Momente
local D = W and W.Diary -- diary toolkit "diary with stickers"
if not (W and Pages and Momente and D) then return end

local Theme = Journal.Theme or {}
local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil

local Page = { needs = { index = true, model = false } }

-- locale scope "p.Momente" (English in locales/enUS_pages.lua), read when drawing
local T = ns.Locale.ns("p.Momente", {
  level = "Stufe %s", day = "Tag %s", readAt = "Gelesen: %s", ofWhich = "davon %s", hour = "%s Uhr",
  brand = "INK & EMBERS", page = "MOMENTE", moment = "Moment", moments = "Momente",
  kept = "festgehalten", zoneOne = "neue Zone", zonesOf = "neue Zonen",   prevTip = "Neuere Momente", nextTip = "Ältere Momente", pageOf = "Seite %d von %d",
  emptyHead = "Noch kein Moment eingeklebt.", emptyBody = "Stufen, seltene Gegner, erste Funde und neue Orte landen hier im Album.",
  emptyFilter = "In dieser Gruppe klebt noch nichts.",
  unreadable = "Eintrag nicht lesbar",
  filters = { all = "Alle", levels = "Stufen", fights = "Kämpfe", finds = "Funde", places = "Orte" },
  clock = "SPIELZEIT NACH TAGESZEIT", fav = "Lieblingsstunde", longest = "Längste Sitzung", sessions = "Sitzungen",
  interrupted = "unterbrochen", noClock = "Noch keine Spielzeit erfasst.",
  -- empty state of the clock in handwriting; shift-click jumps to the end of the album
  noClockHand = "Bald zeigt die Uhr, zu welcher Tageszeit Ihr am liebsten unterwegs seid.",
  jumpFirst = "Umschalt-Klick: zum neuesten Blatt", jumpLast = "Umschalt-Klick: zum ältesten Blatt",
  library = "BIBLIOTHEK", libEmpty = "Noch kein Buch gelesen.", book = "Buch", books = "Bücher", pageW = "Seite", pagesW = "Seiten",
  readPages = "gelesen", curios = "KURIOSES", curiosEmpty = "Noch nichts Kurioses erlebt.",
  back = "Zurück zum Album", pagePrev = "Vorige Seite", pageNext = "Nächste Seite", pageGone = "Diese Seite ist nicht lesbar.",
})

-- page measures from the grid (Theme.GRID, docs/raster.md): text block left x 92, right x 44, 402 wide. Decorations:
-- wax drop top left (x 58..121, y 32..93: title from y 98), blot bottom right of the left page (x 409..475, y 555..622:
-- album ends before y 555),
-- another top right (x 40..121, y 18..91) and a large flower bottom right (x 365..517, y 452..644: only narrow content above it).
local G = Theme.GRID
local LX, LW = Theme.gridX("L")
local RX, RW = Theme.gridX("R")
-- note wall: 3 columns x 2 rows per sheet. Note NOTE_W x NOTE_H in the aspect of the note pad (Theme.TODO_PAD_SLICE.aspect,
-- the texture is shown whole, never stretched); its own tape sits top centre. Without the pad texture a plain paper area
-- with a strip of diary tape (Media/DiaryTape) stands in. Paper and shadow tilt slightly (noteLook, via texcoords); the
-- symbol tilts with the paper, text stays straight.
local PER_PAGE, COLS = 6, 3
-- the pad is looked up when the cards are built (a test can switch it off); size and margin follow its slice table
local function padSlice() return Theme.TEX and Theme.HAS_TODO_PAD and Theme.TEX.todoPad and Theme.TODO_PAD_SLICE or nil end
local SLICE = Theme.TODO_PAD_SLICE or {}
local NOTE_W = 126 -- three notes per row: 4 grid columns (130 px) each, the note centred in it
local NOTE_H = floor(NOTE_W * (SLICE.aspect or 2120 / 1560) + 0.5)
local _, SLOT_W = Theme.gridX("L", 1, 4)
local function slotX(i) return (Theme.gridX("L", 1 + 4 * i, 4)) + floor((SLOT_W - NOTE_W) / 2) end -- i = 0..2
-- head as on all pages: title y 66 (the wax drop top left, keep-out to x 121, is avoided by indenting), sub title,
-- control line y 118 (switch left, paging right);
-- below it the note wall: two rows from y 168, the lower one ends (tilt included) well before the blot at y 555
local TITLE_Y = G.slots.title.y
local TITLE_X, TITLE_W = Theme.gridX("L", 2, 11)
local SUB_Y = TITLE_Y + 34
local CTRL_CY = G.slots.ctrl.y + G.slots.ctrl.h / 2
local GRID_Y, ROW_PITCH = G.slots.body.y + 18, NOTE_H + 24
local TILT_MIN, TILT_MAX = 1, 3
local SHADOW_X, SHADOW_Y, SHADOW_ALPHA = 2, -3, 0.28
local TAPE_W, TAPE_H = 52, 14 -- only without the pad texture (the pad brings its own tape)
local ICON_SIZE = 30
local LIB_ROWS = 4
local CURIO_ROWS = 7

local function int(n) return Journal.Texts.int(n) end

local function label(parent, kind, size, color, justify)
  local fs = W.font(parent, kind, size, color)
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

local rect = W.NewRect

local function place(region, parent, x, y, point)
  region:ClearAllPoints()
  region:SetPoint(point or "TOPLEFT", parent, point or "TOPLEFT", x, -y)
end

local function hover(frame, getLines)
  frame:EnableMouse(true)
  frame:SetScript("OnEnter", function(self)
    local ok, lines = W.call(getLines, self)
    if ok and type(lines) == "table" then W.tip(self, lines) end
  end)
  frame:SetScript("OnLeave", function(self) W.hideTip(self) end)
end

local function entryTip(e, caption)
  local lines = { e.title }
  if e.what then lines[#lines + 1] = e.what end
  if caption and caption ~= "" then lines[#lines + 1] = caption end
  local when = e.date or e.when
  if when then lines[#lines + 1] = when end
  if e.place then lines[#lines + 1] = e.place end
  if e.sub and e.zone and e.sub ~= e.zone then lines[#lines + 1] = e.zone end
  if e.level then lines[#lines + 1] = T("level", int(e.level)) end
  -- finds: original item tooltip, below it the moment lines (without the duplicate item name)
  if e.item then
    lines.item = e.item
    local extra = {}
    for i, l in ipairs(lines) do
      if not (i == 2 and e.what) then extra[#extra + 1] = l end
    end
    lines.itemExtra = extra
  end
  return lines
end

-- symbol per moment kind (Theme.MOMENT_ICONS), like the filter groups; death has its own symbol, everything without a
-- group and "Ein Moment" is memory. It stands small at the top of the note, below the tape.
local GROUP_ICON = { levels = "level", fights = "fight", finds = "find", places = "place" }
local DEATH_KINDS = { first_death = true, death = true }
local function momentIcon(e)
  if DEATH_KINDS[e.kind] then return "death" end
  if e.kind == "other" then return "memory" end
  return GROUP_ICON[e.group] or "memory"
end
Page.momentIcon = momentIcon

-- scatter values from the moment's key (same entry = same position). Numbers stay below 2^53 (exact in Lua 5.1 as in
-- fengari); one mixing step per property so similar keys ("MO:12", "MO:13") do not land similarly
local function hash(key)
  local h = 7
  key = tostring(key or "")
  for i = 1, #key do h = (h * 31 + string.byte(key, i)) % 2147483647 end
  return h
end
local function mix(h, salt)
  h = (h * 48271 + salt * 69621) % 2147483647
  return (h * 48271) % 2147483647
end

-- position of the note: { angle (degrees, magnitude TILT_MIN..TILT_MAX in half degrees, sign scattered) }
local function noteLook(key)
  local h = hash(key)
  local steps = floor((TILT_MAX - TILT_MIN) * 2) + 1
  local angle = TILT_MIN + (mix(h, 1) % steps) * 0.5
  if mix(h, 2) % 2 == 0 then angle = -angle end
  return { angle = angle }
end
Page.noteLook = noteLook

-- rotate point (x, y) in the note's field (origin top left, y down) around the centre (positive angle =
-- counter-clockwise like Texture:SetRotation); result in whole pixels
local function rotated(card, x, y)
  local dx, dy = x - NOTE_W / 2, NOTE_H / 2 - y
  local c, s = card.cosA or 1, card.sinA or 0
  return floor(NOTE_W / 2 + dx * c - dy * s + 0.5), floor(NOTE_H / 2 - (dx * s + dy * c) + 0.5)
end

-- writing area on the paper (left/right margin of the pad, Theme.TODO_PAD_SLICE.margin), from top to bottom: symbol
-- (centre ICON_Y), title (handwriting, up to 2 lines, field TITLE.top .. TITLE.top + TITLE.avail), the diary line
-- (handwriting, up to CAPTION.lines lines from CAPTION.top) and day/time (handwriting, one line, centre WHEN_Y) above the
-- torn bottom edge. Level and place are not on the note, only in the tooltip (entryTip).
local MARGIN = floor(NOTE_W * (SLICE.margin or 0.115) + 0.5)
local TEXT_W = NOTE_W - 2 * MARGIN
local ICON_Y = 31
local TITLE = { max = 18, min = 14, avail = 42, top = 49 }
local CAPTION = { size = 15, lines = 3, top = TITLE.top + TITLE.avail + 2 }
local WHEN_Y = NOTE_H - 17
Page.TITLE = TITLE
Page.NOTE = { w = NOTE_W, h = NOTE_H, margin = MARGIN, textW = TEXT_W, cols = COLS,
  perPage = PER_PAGE, tiltMin = TILT_MIN, tiltMax = TILT_MAX, iconY = ICON_Y, caption = CAPTION, whenY = WHEN_Y }

local function handLabel(parent, size, color, justifyV)
  local fs = D.font(parent, "hand", size, color)
  fs:SetJustifyH("CENTER")
  if justifyV then fs:SetJustifyV(justifyV) end
  fs:SetWidth(TEXT_W)
  return fs
end

local function newCard(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(NOTE_W, NOTE_H)
  -- shadow and paper (rotated), on it the symbol (rotated); text straight on top
  f.shadow = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  f.paper = f:CreateTexture(nil, "BACKGROUND", nil, 2)
  f.pad = padSlice() and true or false
  -- tilted paper needs room for its corners (Theme.tiltQuad); the plain stand-in stays straight at note size
  local pw, ph, sw, sh = NOTE_W, NOTE_H, NOTE_W + 2, NOTE_H + 2
  if f.pad and Theme.tiltQuad then
    pw, ph = Theme.tiltQuad(NOTE_W, NOTE_H, TILT_MAX)
    sw, sh = Theme.tiltQuad(NOTE_W + 2, NOTE_H + 2, TILT_MAX)
  end
  if f.pad then
    f.shadow:SetTexture(Theme.TEX.todoPad)
    f.paper:SetTexture(Theme.TEX.todoPad)
    f.shadow:SetVertexColor(0.17, 0.10, 0.05, SHADOW_ALPHA)
  else
    f.shadow:SetColorTexture(0.17, 0.10, 0.05, SHADOW_ALPHA * 0.6)
    f.paper:SetColorTexture(W.color("card"))
    f.tape = f:CreateTexture(nil, "ARTWORK", nil, 3)
    if Theme.TEX and Theme.TEX.diaryTape then
      f.tape:SetTexture(Theme.TEX.diaryTape)
    else
      f.tape:SetColorTexture(0.89, 0.84, 0.69, 0.8)
    end
    f.tape:SetSize(TAPE_W, TAPE_H)
    f.tape:SetPoint("CENTER", f, "TOP", 0, -2)
  end
  f.shadow:SetSize(sw, sh)
  f.shadow:SetPoint("CENTER", f, "CENTER", SHADOW_X, SHADOW_Y)
  f.paper:SetSize(pw, ph)
  f.paper:SetPoint("CENTER", f, "CENTER", 0, 0)
  f.icon = f:CreateTexture(nil, "ARTWORK", nil, 1)
  f.icon:SetSize(ICON_SIZE, ICON_SIZE)
  if Theme.TEX and Theme.TEX.momentIcons then f.icon:SetTexture(Theme.TEX.momentIcons) end
  f.title = handLabel(f, TITLE.max, "ink")
  f.title:SetWordWrap(true)
  f.caption = handLabel(f, CAPTION.size, "sepia", "TOP")
  f.caption:SetWordWrap(true)
  if f.caption.SetMaxLines then f.caption:SetMaxLines(CAPTION.lines) end
  f.when = handLabel(f, G.size.m, "sepia")
  f.when:SetWordWrap(false)
  hover(f, function(card) return card.tipLines end)
  f:Hide()
  return f
end

-- lay out paper, shadow, symbol and text lines by the entry's position (textures rotated, text straight).
-- Theme.tiltFull returns the sampling scale as ninth value; SetTexCoord gets only the eight coordinates
local function first8(a, b, c, d, e, f, g, h) return a, b, c, d, e, f, g, h end
local function layCard(card, key)
  local look = noteLook(key)
  if not card.pad then look.angle = 0 end -- the plain stand-in stays straight (a colour area cannot be turned via texcoords)
  card.look = look
  local rad = look.angle * math.pi / 180
  card.cosA, card.sinA = math.cos(rad), math.sin(rad)
  -- paper and shadow rotate rigidly via their texture coordinates (Theme.tiltFull), not via SetRotation, which shears a
  -- non-square area
  if card.pad and Theme.tiltFull then
    card.paper:SetTexCoord(first8(Theme.tiltFull(NOTE_W, NOTE_H, look.angle, TILT_MAX)))
    card.shadow:SetTexCoord(first8(Theme.tiltFull(NOTE_W + 2, NOTE_H + 2, look.angle, TILT_MAX)))
  end
  local ix, iy = rotated(card, NOTE_W / 2, ICON_Y)
  card.icon:ClearAllPoints()
  card.icon:SetPoint("CENTER", card, "TOPLEFT", ix, -iy)
  local tx, ty = rotated(card, NOTE_W / 2, TITLE.top + TITLE.avail / 2)
  card.title:ClearAllPoints()
  card.title:SetPoint("CENTER", card, "TOPLEFT", tx, -ty)
  local cx, cy = rotated(card, NOTE_W / 2, CAPTION.top)
  card.caption:ClearAllPoints()
  card.caption:SetPoint("TOP", card, "TOPLEFT", cx, -cy)
  local wx, wy = rotated(card, NOTE_W / 2, WHEN_Y)
  card.when:ClearAllPoints()
  card.when:SetPoint("CENTER", card, "TOPLEFT", wx, -wy)
end
Page.layCard = layCard

-- symbol (cell of the symbol atlas) tilted with the note: rotated with aspect correction and zoomed in so far that no
-- neighbour cell bleeds in; the area itself stays straight
local function setIcon(card, iconName)
  if iconName and Theme.momentIconCoords and Theme.rotCoords8 then
    local u0, u1, v0, v1 = Theme.momentIconCoords(iconName)
    card.icon:SetTexCoord(Theme.rotCoords8(u0, u1, v0, v1, ICON_SIZE, ICON_SIZE, card.look and card.look.angle or 0))
    card.icon:Show()
  else
    card.icon:Hide()
  end
end

-- title of the note: the name that goes with the moment (enemy, find, dungeon, mount ...), for level, close win and first
-- death the occasion, for new zones the place
local TITLE_IS_EVENT = { level = true, close_win = true, first_death = true }
local function noteTitle(e)
  if e.kind == "zone" then return e.place or e.title end
  if TITLE_IS_EVENT[e.kind] or not e.what then return e.title end
  return e.what
end
Page.noteTitle = noteTitle

-- set the title and fit it into the title field: wrap into up to 2 lines (width TEXT_W); if the text does not fit
-- TITLE.avail at the current font, shrink the font step by step down to TITLE.min; only then cut to 2 lines (SetMaxLines,
-- the client adds "..."): the title never reaches into the diary line. Height from GetStringHeight (the whole text).
-- In the Friz stand-in for the handwriting (D.font, fs.diaryFallback) the sizes scale like there.
local function fitTitle(fs, text)
  W.setText(fs, text)
  local file, _, flags = fs:GetFont()
  if not file then return end
  if fs.SetMaxLines then fs:SetMaxLines(0) end -- 0 = unlimited: the whole text is measured
  fs:SetWordWrap(true)
  local k = fs.diaryFallback and (D.HAND_FALLBACK_SCALE or 0.72) or 1
  for size = TITLE.max, TITLE.min, -1 do
    fs:SetFont(file, floor(size * k + 0.5), flags or "")
    if (tonumber(fs:GetStringHeight()) or 0) <= TITLE.avail then return end
  end
  if fs.SetMaxLines then fs:SetMaxLines(2) end
end
Page.fitTitle = fitTitle

local function fillCard(card, e, album, used)
  card.entry = e
  local caption = Momente.caption(album, e, used)
  layCard(card, e.key)
  card.iconName = momentIcon(e)
  setIcon(card, card.iconName)
  fitTitle(card.title, noteTitle(e))
  W.setText(card.caption, caption)
  W.setText(card.when, e.when)
  card.tipLines = entryTip(e, caption)
  card:Show()
end

local function failCard(card)
  card.entry, card.tipLines, card.iconName = nil, nil, nil
  layCard(card, "?")
  setIcon(card, nil)
  fitTitle(card.title, T.unreadable)
  W.setText(card.caption, "")
  W.setText(card.when, "")
  card:Show()
end

-- album entries without loose screenshots (the page does not show them); "all" filtered once per album
local function visibleList(self, album)
  if self.filter ~= "all" then return Momente.filter(album, self.filter) end
  local c = self.visible
  if c and c.album == album then return c.list end
  local list = {}
  for _, e in ipairs(Momente.filter(album, "all")) do
    if e.kind ~= "shot" then list[#list + 1] = e end
  end
  self.visible = { album = album, list = list }
  return list
end
Page.visibleList = visibleList

local function buildLeft(self, left)
  local ui = self.ui
  ui.headL = W.NewPageHead(left, { side = "L" })
  ui.headL:SetTexts(T.brand, T.page)

  local album = CreateFrame("Frame", nil, left)
  album:SetAllPoints(left)
  ui.album = album
  ui.title = label(album, "title", G.size.xl, "ink")
  ui.title:SetWidth(TITLE_W)
  ui.title:SetWordWrap(false)
  place(ui.title, left, TITLE_X, TITLE_Y)
  ui.sub = label(album, "label", G.size.s, "sepia")
  ui.sub:SetWidth(TITLE_W)
  ui.sub:SetWordWrap(false)
  place(ui.sub, left, TITLE_X, SUB_Y)
  -- control line: switch left (short names, the counts are in the tooltip), paging right.
  -- Filter: toggle with the chosen group circled; the count follows the name in clean font ("Funde · 12")
  ui.filter = D.NewToggle(album, { size = G.size.s, gap = 12, value = self.filter, onChange = function(key) self:OnChip(key) end })
  ui.filter.frame:SetPoint("LEFT", left, "TOPLEFT", LX - 3, -CTRL_CY)
  -- note wall: PER_PAGE notes created once (pool), only refilled when paging
  ui.cards = {}
  for i = 1, PER_PAGE do
    local c = newCard(album)
    place(c, left, slotX((i - 1) % COLS), GRID_Y + floor((i - 1) / COLS) * ROW_PITCH)
    ui.cards[i] = c
  end
  -- paging: arrow pair right in the control line, "Seite x von y" to its left
  local function shift() return IsShiftKeyDown ~= nil and IsShiftKeyDown() and true or false end
  ui.pair = D.NewNavPair(album, { onPrev = function() self:Step(shift() and -math.huge or -1) end,
    onNext = function() self:Step(shift() and math.huge or 1) end,
    tipPrev = { T.prevTip, T.jumpFirst }, tipNext = { T.nextTip, T.jumpLast } })
  ui.pair.frame:SetPoint("RIGHT", left, "TOPLEFT", LX + LW, -CTRL_CY)
  ui.nav = label(album, "label", G.size.s, "sepia", "RIGHT")
  ui.nav:SetWidth(110)
  ui.nav:SetPoint("RIGHT", ui.pair.frame, "LEFT", -8, 0)
  ui.emptyHead = label(album, "title", G.size.l, "ink", "CENTER")
  ui.emptyHead:SetWidth(LW)
  ui.emptyHead:SetPoint("TOP", left, "TOPLEFT", LX + LW / 2, -280)
  ui.emptyBody = D.emptyNote(album, LW - 60) -- handwriting
  ui.emptyBody:SetPoint("TOP", left, "TOPLEFT", LX + LW / 2, -320)

  -- reading window: title (up to 2 lines), below it details left and paging right, rule, text (ends before y 555)
  local reader = CreateFrame("Frame", nil, left)
  reader:SetAllPoints(left)
  ui.reader = reader
  ui.rdBack = D.NewBack(reader, T.back, function() self:CloseBook() end)
  D.placeBack(ui.rdBack, left)
  ui.rdTitle = label(reader, "title", G.size.l, "ink")
  ui.rdTitle:SetWidth(TITLE_W)
  ui.rdTitle:SetWordWrap(true)
  ui.rdTitle:SetJustifyV("TOP")
  if ui.rdTitle.SetMaxLines then ui.rdTitle:SetMaxLines(2) end
  ui.rdTitle:SetHeight(2 * math.ceil(G.size.l * 1.2))
  place(ui.rdTitle, left, TITLE_X, TITLE_Y)
  local RD_Y = TITLE_Y + 2 * math.ceil(G.size.l * 1.2) + 6
  ui.rdMeta = label(reader, "label", G.size.s, "sepia")
  ui.rdMeta:SetWidth(LW - 190)
  ui.rdMeta:SetWordWrap(false)
  ui.rdMeta:SetPoint("LEFT", left, "TOPLEFT", LX, -(RD_Y + 10))
  W.NewRule(reader, LX, RD_Y + 30, LW)
  ui.rdText = W.NewTextView(reader, { width = LW, height = 540 - (RD_Y + 40), size = G.size.m, color = "ink", empty = T.pageGone })
  place(ui.rdText.frame, left, LX, RD_Y + 40)
  ui.rdPair = D.NewNavPair(reader, { onPrev = function() self:StepBook(-1) end, onNext = function() self:StepBook(1) end,
    tipPrev = { T.pagePrev }, tipNext = { T.pageNext } })
  ui.rdPair.frame:SetPoint("RIGHT", left, "TOPLEFT", LX + LW, -(RD_Y + 10))
  ui.rdNav = label(reader, "label", G.size.s, "sepia", "RIGHT")
  ui.rdNav:SetWidth(180)
  ui.rdNav:SetPoint("RIGHT", ui.rdPair.frame, "LEFT", -8, 0)
  reader:Hide()
end

local function buildRight(self, right)
  local ui = self.ui
  ui.headR = W.NewPageHead(right, { side = "R" }) -- grid (Theme.GRID)
  ui.headR:SetTexts("", T.page)

  -- right page: decoration top left (x 40..121, y 18..91) -> everything from y 98; bottom right the large flower (x
  -- 365..517, y 452..644)
  -- -> curiosities stay narrow (under 300 px) and start below the library
  local CLOCK_Y = G.slots.bodyTop.y
  ui.clockHead = label(right, "label", G.size.xs, "sepia")
  ui.clockHead:SetText(T.clock)
  place(ui.clockHead, right, RX, CLOCK_Y)
  local RING, RING_X, RING_Y = 120, RX + 8, CLOCK_Y + 28
  -- soft bars (Media/ClockBar) instead of rotated colour areas: smooth edges
  ui.ring = W.NewRing(right, { size = RING, length = 20, thickness = 6, on = "sepia", off = "faint", tex = Theme.TEX and Theme.TEX.clockBar,
    texPad = Theme.CLOCK_BAR_PAD })
  place(ui.ring.frame, right, RING_X, RING_Y)
  ui.ring.center:SetFont(W.FONT.title, G.size.l, "")
  ui.ring.center:SetTextColor(W.color("ink"))
  ui.hourLbl = {}
  local marks = { { "0", "TOP", RING_X + RING / 2, RING_Y - 14 }, { "6", "TOPLEFT", RING_X + RING + 4, RING_Y + RING / 2 - 7 },
    { "12", "TOP", RING_X + RING / 2, RING_Y + RING + 2 }, { "18", "TOPRIGHT", RING_X - 4, RING_Y + RING / 2 - 7 } }
  for i, m in ipairs(marks) do
    local fs = label(right, "label", G.size.xs, "sepia", m[2] == "TOPRIGHT" and "RIGHT" or (m[2] == "TOPLEFT" and "LEFT" or "CENTER"))
    fs:SetText(m[1])
    fs:SetWidth(24)
    fs:ClearAllPoints()
    if m[2] == "TOP" then
      fs:SetPoint("TOP", right, "TOPLEFT", m[3], -m[4])
    else
      fs:SetPoint(m[2], right, "TOPLEFT", m[3], -m[4])
    end
    ui.hourLbl[i] = fs
  end
  ui.stat = {}
  local STAT_X = RX + 170
  local names = { { "fav", T.fav }, { "longest", T.longest }, { "sessions", T.sessions } }
  for i, n in ipairs(names) do
    local y = RING_Y + 4 + (i - 1) * 46
    local l = label(right, "label", G.size.xs, "sepia")
    ui.statLbl = ui.statLbl or {}
    ui.statLbl[#ui.statLbl + 1] = l
    l:SetText(Journal.Fmt.upper(n[2])) -- with umlauts (string.upper only knows ASCII)
    l:SetWidth(RW - 170)
    place(l, right, STAT_X, y)
    local v = label(right, "title", G.size.l, "ink")
    v:SetWidth(RW - 170)
    v:SetWordWrap(false)
    place(v, right, STAT_X, y + 14)
    ui.stat[n[1]] = v
  end
  ui.clockNote = label(right, "label", G.size.xs, "sepia")
  ui.clockNote:SetWidth(RW - 170)
  place(ui.clockNote, right, STAT_X, RING_Y + 4 + 3 * 46)
  -- without play time no empty clock but a handwritten sentence (centred over the area of clock and values)
  ui.clockEmpty = D.emptyNote(right, RW - 60)
  ui.clockEmpty:SetPoint("TOP", right, "TOPLEFT", RX + RW / 2, -(RING_Y + 36))

  local LIB_Y = RING_Y + RING + 20 + G.section.before
  ui.libHead = label(right, "label", G.size.xs, "sepia")
  ui.libHead:SetText(T.library)
  place(ui.libHead, right, RX, LIB_Y)
  ui.libCount = label(right, "label", G.size.xs, "sepia", "RIGHT")
  ui.libCount:SetWidth(260)
  ui.libCount:SetPoint("TOPRIGHT", right, "TOPLEFT", RX + RW, -LIB_Y)
  W.NewRule(right, RX, LIB_Y + 18, RW)
  ui.list = W.NewList(right, { rows = LIB_ROWS, rowHeight = G.line.row, width = RW, step = 3, empty = T.libEmpty, emptyHand = true,
    build = function(row)
      local pg = label(row, "label", G.size.xs, "sepia", "RIGHT")
      pg:SetWidth(76)
      pg:SetPoint("RIGHT", row, "RIGHT", -4, 0)
      row.pg = pg
      row.label:ClearAllPoints()
      row.label:SetPoint("LEFT", row, "LEFT", 6, 0)
      row.label:SetPoint("RIGHT", row, "RIGHT", -84, 0)
      row:SetScript("OnEnter", function(r)
        if r.entry then
          local ok, lines = W.call(function() return self:BookTip(r.entry) end)
          if ok and type(lines) == "table" then W.tip(r, lines) end
        end
      end)
      row:SetScript("OnLeave", function(r) W.hideTip(r) end)
      D.RowStyle(row, { texts = { row.label, pg } }) -- after the scripts: ruled-paper line, hover red, selection outlined
    end,
    clear = function(row)
      row.entry = nil
      row:SetSelected(false)
      row.pg:SetText("")
    end,
    fill = function(row, b)
      row.entry = b
      W.setText(row.label, b.title)
      row.pg:SetText(int(b.nPages) .. " " .. (b.nPages == 1 and T.pageW or T.pagesW))
      row:SetSelected(self.reading ~= nil and self.reading.key == b.key)
      D.rowFilled(row)
    end,
    onClick = function(b) self:Read(b.key) end })
  place(ui.list.frame, right, RX, LIB_Y + 24)

  -- curiosities: start below the library, the flower (x 365..517, y 452..644) stays free: lines at most 300 px wide
  local CURIO_Y = LIB_Y + 24 + LIB_ROWS * G.line.row + G.section.before + 10
  ui.curioHead = label(right, "label", G.size.xs, "sepia")
  ui.curioHead:SetText(T.curios)
  place(ui.curioHead, right, RX, CURIO_Y)
  W.NewRule(right, RX, CURIO_Y + 18, RW)
  ui.curio = {}
  for i = 1, CURIO_ROWS do
    local y = CURIO_Y + 24 + (i - 1) * G.line.text
    local dot = rect(right, "red", 0.8, "ARTWORK")
    dot:SetSize(4, 4)
    dot:SetPoint("TOPLEFT", right, "TOPLEFT", RX + 4, -(y + 7))
    local fs = label(right, "text", G.size.m, "ink")
    fs:SetWidth(300)
    fs:SetWordWrap(false)
    place(fs, right, RX + 16, y)
    dot:Hide()
    ui.curio[i] = { dot = dot, text = fs }
  end
  ui.curioEmpty = D.emptyNote(right, 300, 18) -- handwriting
  ui.curioEmpty:SetJustifyH("LEFT")
  ui.curioEmpty:SetText(T.curiosEmpty)
  place(ui.curioEmpty, right, RX + 4, CURIO_Y + 26)
end

function Page.Build(self, left, right)
  self.left, self.right = left, right
  self.ui = {}
  self.filter = Pages.setting("albumFilter")
  self.pageNo, self.reading = 1, nil
  buildLeft(self, left)
  buildRight(self, right)
  -- mouse wheel pages the album; in the reading window the text keeps the wheel (only if it can scroll), otherwise the
  -- sheets page
  left:EnableMouseWheel(true)
  left:SetScript("OnMouseWheel", function(_, delta)
    delta = tonumber(delta) or 0
    if delta == 0 then return end
    local ok, err = pcall(self.Wheel, self, delta < 0 and 1 or -1)
    if not ok then Pages.fail("momente", err) end
  end)
end

function Page:Wheel(dir)
  if self.reading then
    self:StepBook(dir)
  else
    self:Step(dir)
  end
end

-- dir = 1: older moments (next sheet), -1: newer
function Page:Step(dir)
  if self.reading or not self.view then return end
  local list = visibleList(self, self.view.album)
  local pages = max(1, ceil(#list / PER_PAGE))
  local to = self.pageNo + dir
  if dir == math.huge or dir == -math.huge then to = max(1, min(pages, to)) end -- jump to the end
  if to < 1 or to > pages or to == self.pageNo then return end
  self.pageNo = to
  self:Render()
end

function Page:OnChip(key)
  if not Momente.FILTER_OK[key] then return end
  self.filter, self.pageNo = key, 1
  Pages.setSetting("albumFilter", key)
  self:Render()
end

function Page:FindBook(key)
  local lib = self.view and self.view.library
  if not lib then return nil end
  for _, b in ipairs(lib.books) do
    if b.key == key then return b end
  end
  return nil
end

function Page:Read(key)
  local b = self:FindBook(key)
  if not b then return end
  self.reading = { key = key, i = 1 }
  self:Render()
end

function Page:CloseBook()
  self.reading = nil
  self:Render()
end

function Page:StepBook(dir)
  local r = self.reading
  local b = r and self:FindBook(r.key)
  if not b then return end
  local to = r.i + dir
  if to < 1 or to > b.nPages then return end
  r.i = to
  self:Render()
end

function Page:BookTip(b)
  local lines = { b.title }
  local bits = {}
  if b.material then bits[#bits + 1] = b.material end
  bits[#bits + 1] = int(b.nPages) .. " " .. (b.nPages == 1 and T.pageW or T.pagesW) .. " " .. T.readPages
  lines[#lines + 1] = table.concat(bits, " · ")
  local where = {}
  if b.day then where[#where + 1] = T("day", int(b.day)) end
  if b.level then where[#where + 1] = T("level", int(b.level)) end
  if b.zone then where[#where + 1] = b.zone end
  if #where > 0 then lines[#lines + 1] = T("readAt", table.concat(where, " · ")) end
  return lines
end

local function playerLine(data)
  local info = type(data.char) == "table" and type(data.char.info) == "table" and data.char.info or {}
  local S = ns.Sanitize
  local function d(v) return S.display(v, 32) end
  local parts = {}
  local who = d(ns.Names and ns.Names.fullName(info) or info.name) -- "Vorname Nachname" on Forever (Names.lua)
  if who then parts[#parts + 1] = who end
  local rc = {}
  local race, class = d(info.race), d(info.class)
  if race then rc[#rc + 1] = race end
  if class then rc[#rc + 1] = class end
  if #rc > 0 then parts[#parts + 1] = table.concat(rc, " ") end
  local level = data.live and data.live.level and data.live.level()
  if not level then
    local last = Journal.Index.list(data.index, "LV")
    last = last[#last]
    level = last and Journal.Index.num(last, "LV", "level") or nil
  end
  if level then parts[#parts + 1] = T("level", int(level)) end
  return table.concat(parts, " · ")
end

function Page:RenderAlbum()
  local ui, album = self.ui, self.view.album
  local total = album.total
  W.setText(ui.title, int(total) .. " " .. (total == 1 and T.moment or T.moments))
  local bits = {}
  bits[1] = T.kept
  if album.zones > 0 then bits[#bits + 1] = T("ofWhich", int(album.zones) .. " " .. (album.zones == 1 and T.zoneOne or T.zonesOf)) end
  W.setText(ui.sub, table.concat(bits, " · "))
  local shown = max(0, (album.counts.all or 0) - (album.loose or 0)) -- without loose screenshots
  local items = {}
  for i, key in ipairs(Momente.GROUPS) do
    items[i] = { key = key, label = T.filters[key], count = key == "all" and shown or album.counts[key], active = self.filter == key }
  end
  -- short names in the switch (fits with "Seite x von y" in the control line), the count is in the tooltip
  for _, it in ipairs(items) do
    it.tip = { it.label, int(it.count or 0) .. " " .. (it.count == 1 and T.moment or T.moments) }
  end
  ui.filter:SetItems(items)
  ui.filter:SetValue(self.filter)
  local list = visibleList(self, album)
  local pages = max(1, ceil(#list / PER_PAGE))
  if self.pageNo > pages then self.pageNo = pages end
  if self.pageNo < 1 then self.pageNo = 1 end
  local from = (self.pageNo - 1) * PER_PAGE
  local used = {} -- captions of this sheet: no repetition
  for i, card in ipairs(ui.cards) do
    local e = list[from + i]
    if e then
      if not W.call(fillCard, card, e, album, used) then failCard(card) end
    else
      card.entry, card.tipLines = nil, nil
      W.hideTip(card)
      card:Hide()
    end
  end
  local none = shown == 0
  ui.emptyHead:SetShown(none or #list == 0)
  ui.emptyBody:SetShown(none)
  W.setText(ui.emptyHead, none and T.emptyHead or T.emptyFilter)
  W.setText(ui.emptyBody, none and T.emptyBody or "")
  ui.filter.frame:SetShown(not none)
  ui.pair.frame:SetShown(not none)
  ui.nav:SetShown(not none)
  ui.pair:SetEnabled(self.pageNo > 1, self.pageNo < pages)
  W.setText(ui.nav, T("pageOf", self.pageNo, pages))
end

function Page:RenderReader(book)
  local ui, r = self.ui, self.reading
  r.i = max(1, min(r.i, book.nPages))
  local num = book.pages[r.i]
  W.setText(ui.rdTitle, book.title)
  local meta = {}
  if book.material then meta[#meta + 1] = book.material end
  if book.day then meta[#meta + 1] = T("day", int(book.day)) end
  if book.level then meta[#meta + 1] = T("level", int(book.level)) end
  if book.zone then meta[#meta + 1] = book.zone end
  W.setText(ui.rdMeta, table.concat(meta, " · "))
  local text = Momente.bookPage(self.data.index, book, num)
  ui.rdText.text:SetTextColor(W.color(text and "ink" or "sepia"))
  ui.rdText:SetText(text)
  local nav = T("pageOf", num, book.last)
  if book.nPages < book.last then nav = nav .. " · " .. int(book.nPages) .. " " .. T.readPages end
  W.setText(ui.rdNav, nav)
  ui.rdPair:SetEnabled(r.i > 1, r.i < book.nPages)
end

function Page:RenderClock()
  local ui, c = self.ui, self.view.clock
  ui.ring:SetData(24, function(i)
    if c.fav and i - 1 == c.fav then return "gold" end
    return (c.hours[i] or 0) > 0 and "sepia" or "faint"
  end, function(i)
    local top = c.fav and c.hours[c.fav + 1] or 0
    if top <= 0 then return 0.05 end
    return (c.hours[i] or 0) / top
  end)
  W.setText(ui.ring.center, c.fav and T("hour", tostring(c.fav)) or "–")
  W.setText(ui.stat.fav, c.favText or "–")
  W.setText(ui.stat.longest, c.longestText or "–")
  local s = int(c.sessions)
  if c.interrupted > 0 then s = s .. " · " .. int(c.interrupted) .. " " .. T.interrupted end
  W.setText(ui.stat.sessions, s)
  W.setText(ui.clockNote, "")
  local has = c.hasData and true or false
  ui.ring.frame:SetShown(has)
  for _, list in ipairs({ ui.hourLbl, ui.statLbl or {} }) do
    for _, fs in ipairs(list) do fs:SetShown(has) end
  end
  for _, v in pairs(ui.stat) do v:SetShown(has) end
  W.setText(ui.clockEmpty, has and "" or T.noClockHand)
end

function Page:RenderLibrary()
  local ui, lib = self.ui, self.view.library
  local text = ""
  if lib.count > 0 then
    text = int(lib.count) .. " " .. (lib.count == 1 and T.book or T.books) .. " · " .. int(lib.pages) .. " "
      .. (lib.pages == 1 and T.pageW or T.pagesW)
  end
  W.setText(ui.libCount, text)
  ui.list:SetItems(lib.books)
  ui.list:Refresh()
end

function Page:RenderCurios()
  local ui, c = self.ui, self.view.curios
  for i, row in ipairs(ui.curio) do
    local line = c.lines[i]
    row.dot:SetShown(line ~= nil)
    W.setText(row.text, line)
  end
  ui.curioEmpty:SetShown(not c.any)
end

function Page:Render()
  local data, ui, view = self.data, self.ui, self.view
  if not (data and ui and view) then return end
  ui.headR:SetTexts(playerLine(data), T.page)
  local book = self.reading and self:FindBook(self.reading.key) or nil
  if self.reading and not book then self.reading = nil end -- the book no longer exists (other data)
  ui.album:SetShown(book == nil)
  ui.reader:SetShown(book ~= nil)
  ui.headL:SetTexts(book and "" or T.brand, T.page) -- in the reading window "Zurück" stands top left (grid: slot back)
  if book then
    self:RenderReader(book)
  else
    self:RenderAlbum()
  end
  self:RenderClock()
  self:RenderLibrary()
  self:RenderCurios()
end

function Page.Refresh(self, data)
  self.data = data
  self.view = Momente.evaluate(data.index, { now = data.now, db = EveNChronicleDB })
  self:Render()
end

function Page.OnHide(self)
  local ui = self.ui
  if not ui then return end
  for _, c in ipairs(ui.cards) do W.hideTip(c) end
  W.hideTip(ui.pair.prev)
  W.hideTip(ui.pair.next)
  W.hideTip(ui.rdPair.prev)
  W.hideTip(ui.rdPair.next)
  for _, row in ipairs(ui.list.rows) do W.hideTip(row) end
end

Journal.MomentePage = Page -- handle for tests and the diagnostics (ui, view, filter, reading)
Pages.register("momente", Page)
