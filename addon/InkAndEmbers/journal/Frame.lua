-- Journal window: the open book (leather cover, two parchment pages with a fold, tabs on the right) in the book layout:
-- everything looks printed into the paper, nothing floats. Left page: head, chapter (number, zone, level and date,
-- narrative sentence), values table, margin notes, below them the chapter grid or the "Stations of the journey".
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Frame = {}
Journal.Frame = Frame

local floor, max, huge = math.floor, math.max, math.huge

Frame.NAME = "EveNChronicleJournal"
Frame.HOME = "reise"
Frame.RIM = 30
Frame.SPREAD_W, Frame.SPREAD_H = 1076, 666
Frame.W, Frame.H = Frame.SPREAD_W + 2 * Frame.RIM, Frame.SPREAD_H + 2 * Frame.RIM
-- Layers from the bottom: base image (Media/Book) -> bookmarks -> parchment of the tab -> content. PAPER_OUT: how far the
-- parchment image extends past the double page (top 21, bottom 6, 0 at the sides); its edges are irregular and partly
-- transparent, the page block shows through.
Frame.PAPER_OUT = { x = 0, top = 21, bottom = 6 }
-- Book layout on the grid (Theme.GRID, docs/raster.md), pixels of the double page (1076 x 666, fold at 538); the right page is
-- Theme.gridX("R", ..., true). Content avoids painted decorations that reach into the text block (journal/DecorKeepout.lua):
-- left: chapter grid / stations from column 2 + 10 (blot and doodle reach to x 132); right: title ends before the top blot.
local GRID = (Journal.Theme and Journal.Theme.GRID) or { slots = {} }
local function gx(side, col, span, spread)
  return Journal.Theme.gridX(side, col, span, spread)
end
do
  local lx, lw = gx("L", 1, 12, true)
  local rx, rw = gx("R", 1, 12, true)
  Frame.LEFT = { x = lx, w = lw }
  Frame.RIGHT = { x = rx, w = rw }
end
Frame.HEAD_Y = GRID.head and GRID.head.y or 36
-- Playback bar: compact under the map on the right page, the same in chapter and total journey. Row 1 play + timeline (full
-- width, level scale below), row 2 date | played time | speed (speedW px right). It ends before the doodle at the bottom right
-- (x 408 from y 577, hence 360 wide) and above the dot at the bottom left (y 601).
Frame.TIMELINE = { x = Frame.RIGHT.x, y = 546, w = 360, h = 54, speedW = 140 }
-- Chapter grid in an own frame on the lower left page: x = column 2 + 10, y = 394 (margin notes above, Frame.NOTE), four rows of
-- 42 px to y 580; more chapters page via the arrow pair at the top right. The total journey shows the "Stations of the journey"
-- in the same place (Frame.STATIONS).
Frame.TIMELINE.GRID = { x = gx("L", 2, nil, true) + 10, y = 394, rows = 4, gapY = 6 }
Frame.TIMELINE.GRID.w = Frame.LEFT.x + Frame.LEFT.w - Frame.TIMELINE.GRID.x
Frame.STATIONS = { x = Frame.TIMELINE.GRID.x, y = Frame.TIMELINE.GRID.y, w = Frame.TIMELINE.GRID.w, h = 200, rows = 5 }
-- Without margin notes their space belongs to the grid / stations (Frame.placeLower): they start at the height of the notes
-- (Frame.NOTE.y) with one more row.
Frame.LOWER_FREE = { gridRows = 5, stationRows = 6 }
Frame.CARD_Y = GRID.slots.title and GRID.slots.title.y or 66
Frame.TABLE_W = 300
Frame.ROW_H = GRID.line and GRID.line.row or 22
-- Margin notes directly under the values table from column 2 (+10): the blot at the bottom left reaches to x 132 (y 503..572)
Frame.NOTE = { x = gx("L", 2, nil, true) + 10, y = 336, h = 52, max = 2 }
Frame.NOTE.w = Frame.LEFT.x + Frame.LEFT.w - Frame.NOTE.x
Frame.TITLE_Y = GRID.slots.title and GRID.slots.title.y or 66
Frame.TITLE_W = Frame.RIGHT.w - 30
Frame.MAP = { x = Frame.RIGHT.x, y = GRID.slots.body and GRID.slots.body.y or 150, w = Frame.RIGHT.w }
Frame.WORLD_LINK = { h = 28, size = 16 }
Frame.WORLD_LINK.y = Frame.TIMELINE.y - 4 - Frame.WORLD_LINK.h
Frame.MAP.h = Frame.WORLD_LINK.y - 4 - Frame.MAP.y
Frame.CTRL_Y = GRID.slots.ctrl and GRID.slots.ctrl.y or 118
Frame.CTRL_H = GRID.slots.ctrl and GRID.slots.ctrl.h or 24
Frame.CTRL_SIZE = GRID.size and GRID.size.m or 14
Frame.BACK = { x = 90, y = 29 }
Frame.EAR = 54
Frame.EAR_GAP = 10
Frame.TABS_OUT = 72
-- Tabs, style "Forever bronze" (Media/BookmarksBronze.tga, cell 480 : 102): the straight left end is tucked under the right edge
-- of the parchment, the tab runs over the leather rim (RIM) and sticks out. Layers: cover < tabs (Frame.TAB_LEVEL) < pages
-- (Frame.SPREAD_LEVEL). Anchored TOPLEFT to the window's TOPRIGHT, so it fits at every scale and position.
Frame.TAB = { w = 120, h = 25.5, under = 74, pull = 9, hover = 2, y0 = 84, pitch = 34, sx = 1, sy = 2, sa = 0.35, pad = 2,
  capX = 90, textX = 68, textW = 42, size = 11, minSize = 9 }
Frame.TAB_LABEL = { gold = { 0.88, 0.70, 0.43 }, shadow = { 0.06, 0.035, 0.02, 0.95 }, lip = { 1, 0.9, 0.68, 0.30 } }
Frame.TAB_LEVEL, Frame.SPREAD_LEVEL = 2, 4
-- Sub-bookmarks: subpages of the active tab as ribbons hanging out at the bottom (none for a single view). Texture of the tabs
-- (Media/Bookmarks.tga, cell of the active tab), rotated 90 degrees: body = plain section (u body0..body1), end = swallowtail
-- (u tip0..tip1); trim = texture pixels cut at top/bottom. The top end is tucked under the parchment.
Frame.SUBTAB = { x0 = 122, gap = 6, edge = 40, under = 66, out = 14, pull = 9, hover = 3, tip = 20, pad = 11, minW = 58, size = 17,
  dim = 0.62, body0 = 0.02, body1 = 0.32, tip0 = 0.90, tip1 = 0.996, trim = 8, sx = 1, sy = 2, sa = 0.35 }
Frame.SUBTABS_OUT = Frame.SUBTAB.out + Frame.SUBTAB.pull + Frame.SUBTAB.hover
Frame.SUBTABS_MAX = 4
-- Journey subpages from left to right: total journey · chapter journey (= zone map, key "karte", the default view on open
-- even though it sits in the middle) · to-do (key "vorhaben"). The other tabs register theirs via Pages.subs. Label and
-- tooltip come from Frame.TEXT when read (sub_<key>, subTip_<key>; the language is only known at ADDON_LOADED).
local function subtabDef(key)
  return setmetatable({ key = key }, { __index = function(_, k)
    if k == "label" then return Frame.TEXT["sub_" .. key] end
    if k == "tip" then return { Frame.TEXT["sub_" .. key], Frame.TEXT["subTip_" .. key] } end
    return nil
  end })
end
Frame.SUBTABS_REISE = { subtabDef("gesamt"), subtabDef("karte"), subtabDef("vorhaben") }
-- Fixed small deviation per tab id (no randomness): dx = sticks out +/- px (max 3), dy = offset down px (max 2), deg = tilt
-- (positive: counter-clockwise, max 2). Neighbours keep room: ribbon gap 12 px minus offset difference (max 4) minus both tilt
-- swings (each max 2.4) stays above 3 px.
Frame.TAB_WOBBLE = {
  reise = { dx = 2, dy = 1, deg = 1.5 },
  chronik = { dx = -2, dy = -1, deg = -1.0 },
  kampf = { dx = 3, dy = 2, deg = 2.0 },
  quests = { dx = -3, dy = -1, deg = -1.5 },
  schaetze = { dx = 2, dy = 1, deg = 1.0 },
  momente = { dx = -2, dy = -2, deg = -2.0 },
  notizen = { dx = 1, dy = 1, deg = 1.5 },
}
Frame.SCREEN_PAD = 16
Frame.SCALE_MIN, Frame.SCALE_MAX = 0.5, 2
Frame.DEFAULT_SCALE = 0.75
Frame.DEFAULT_MAX_HEIGHT = 0.9

Frame.TEXT = ns.Locale.ns("Frame", {
  sub_gesamt = "Gesamtreise",
  subTip_gesamt = "Die ganze Route auf der Kontinentkarte, links die Gesamtwerte und die Stationen der Reise",
  sub_karte = "Kapitelreise",
  subTip_karte = "Die Zonenkarte mit der Route und den Kapiteln (Standardansicht)",
  sub_vorhaben = "To Do",
  subTip_vorhaben = "Eigene Reiseziele eintragen und abhaken",
  row_played = "Spielzeit",
  row_levels = "Stufe",
  row_kills = "Kills",
  row_deaths = "Tode",
  row_quests = "Quests",
  row_moments = "Momente",
  tabTip_reise = "Karte mit Eurer Route, Kapitel für Kapitel, und Eure To Dos.",
  tabTip_chronik = "Steckbrief, Stufenfluss, Tagebuch, Weggefährten und Lagerfeuer-Gäste.",
  tabTip_kampf = "Kills, Gegner, knappe Siege und Tode.",
  tabTip_quests = "Abgeschlossene Quests mit Questtext und Belohnung, offene Quests der Zone und der Lehrplan.",
  tabTip_questsRetail = "Abgeschlossene Quests mit Questtext und Belohnung und die offenen Quests der Zone.",
  tabTip_chronikRetail = "Steckbrief, Stufenfluss, Tagebuch und Weggefährten.",
  tabTip_notizen = "Eure eigenen Notizen, gern mit einem Pin auf der Karte.",
  tabTip_schaetze = "Gold im Beutel, Haushaltsbuch, Goldfluss und Ausrüstung.",
  tabTip_momente = "Album der besonderen Augenblicke, Spielzeit-Uhr und Bibliothek.",
  closeTip = "Schließen (Esc)",
  levelHint = "Stufe %s erreicht",
  playedSuffix = "%s gespielt",
  mapN = "Karte %s",
  dayUpper = "TAG %s",
  chapterUpper = "KAPITEL %s",
  chapterRange = "Kapitel %s–%s von %s",
  underway = "Unterwegs",
  zeroMin = "0 Min.",
  dateFull = "%d.%m.%Y",
  loading = "Die Reise wird aufbereitet …",
  nodata = "Noch keine Reisedaten für diesen Charakter. Die Chronik schreibt ab jetzt mit.",
  error = "Das Reisejournal konnte nicht aufbereitet werden. Details: /chronik diag",
  stale = "wird aktualisiert …",
  soon = "kommt bald",
  back = "Zurück zur Übersicht",
  noteUntitled = "Notiz",
  backTitle = "Zurück zur ganzen Reise",
  backTip = "Auch Esc, Rechtsklick oder Doppelklick auf die Karte",
  zoomTip = "Mausrad: zoomen · Ziehen: verschieben",
  overview = "Die Reise",
  settings = "Einstellungen",
  settingsTip = "Öffnet Optionen -> AddOns -> Ink & Embers: Buch, Karte, To Do, Notizen, Einblendungen, Medaillen und Klänge.",
  continent = "Kontinent",
  continentTip = "Kontinentkarte mit der ganzen Route",
  rightTip = "Rechtsklick auf die Karte: erst Zoom aufheben, dann Kontinent",
  zone = "Zone",
  zoneTip = "Aufgedeckte Zonenkarte mit der Route",
  colors = "Karten in Originalfarben",
  kills = "Kämpfe zeigen",
  killsTip = "Erlegte Gegner (gekreuzte Schwerter) auf der Karte zeigen oder ausblenden",
  bookHead = "INK & EMBERS",
  bookHeadRight = "ATLAS",
  reset = "Reisejournal: Größe und Position auf Standard zurückgesetzt.",
  totalLabel = "DIE GANZE REISE",
  journeyUpper = "REISE",
  unexplored = "Unentdecktes Kapitel",
  unexploredNote = "Hier war ich noch nicht!",
  unknownArea = "Unbekanntes Gebiet",
  worldMap = "Auf der Weltkarte zeigen",
  worldMapTip = "Öffnet die Weltkarte an dieser Stelle; Route und Marken der Reise liegen darauf",
  worldSetting = "Reise auf der Weltkarte zeigen",
})
-- Scribbled sentence: every word its own font in ink, baseline rising from word to word (FontStrings cannot be rotated),
-- plus a slanted underline (Texture:SetRotation on a colour area)
Frame.SCRIBBLE = { size = 30, rise = 5, gap = 9, top = 16, underline = 2, lineGap = 8 }
Frame.HINT_SECONDS = 2.4
Frame.HINT_FADE = 0.7

local Theme, View, Map, Playback, Stations

-- mapMode: "zone" (default: uncovered zone map) | "continent" (continent view with route). contWhole: the continent view shows
-- the WHOLE continent map (button "Continent", right click, continent choice); otherwise (fallback without zone art) the
-- automatic zoom on the route or chapter stays.
local J = { sel = {}, st = nil, page = Frame.HOME, mapMode = "zone", contWhole = false }
Frame.state = J

local updateMode

local function deps()
  Theme, View, Map, Playback, Stations = Journal.Theme, Journal.View, Journal.Map, Journal.Playback, Journal.Stations
end

local function int(n) return tostring(floor(tonumber(n) or 0)) end

local function safe(fn)
  return function(...)
    local C = ns.Core
    if C and C.safe then return C.safe(fn, ...) end
    fn(...)
    return true
  end
end

local function safeDate(fmt, t)
  if type(t) ~= "number" or t ~= t or t == huge or t == -huge then return "" end
  local ok, s = pcall(date, fmt, t)
  return (ok and type(s) == "string") and s or ""
end

function Frame.clock()
  if type(debugprofilestop) == "function" then
    local ok, v = pcall(debugprofilestop)
    if ok and type(v) == "number" then return v end
  end
  return nil
end

-- Measurement "open -> done": Access.open calls beginOpen before showing; Frame.render ends it with the first finished draw.
-- Result in Frame.state.perf = { open, build, render, waited } (ms), visible in /chronik status.
function Frame.beginOpen(t0)
  J.openT0, J.openWaited = t0, false
  J.openBuild = t0 and ((Frame.clock() or t0) - t0) or nil
end

local function rowDef(key, red)
  return setmetatable({ key = key, red = red }, { __index = function(_, k)
    if k == "label" then return Frame.TEXT["row_" .. key] end
    return nil
  end })
end
Frame.ROWS = {
  rowDef("played"),
  rowDef("levels"),
  rowDef("kills"),
  rowDef("deaths", true),
  rowDef("quests"),
  rowDef("moments"),
}

local function buildCard(parent)
  local L = Frame.LEFT
  local card = CreateFrame("Frame", nil, parent)
  card:SetPoint("TOPLEFT", parent, "TOPLEFT", L.x, -Frame.CARD_Y)
  card:SetSize(L.w, 10)
  local S = GRID.size or {}
  local title = Theme.fontString(card, "title", S.xl or 28, Theme.C.ink, "OVERLAY", "LEFT")
  title:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
  title:SetWidth(L.w)
  title:SetWordWrap(false)
  local label = Theme.fontString(card, "label", S.s or 12, Theme.C.sepia, "OVERLAY", "LEFT")
  label:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -36)
  label:SetWordWrap(false)
  local sub = Theme.fontString(card, "text", S.s or 12, Theme.C.sepia, "OVERLAY", "LEFT")
  sub:SetPoint("LEFT", label, "RIGHT", 10, 0)
  sub:SetWidth(L.w - 250)
  sub:SetWordWrap(false)
  local story = Theme.fontString(card, "text", S.m or 14, Theme.C.ink, "OVERLAY", "LEFT")
  story:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -58)
  story:SetWidth(L.w)
  story:SetSpacing(3)
  -- Detour line "Abstecher: X, Y" (Model chapter.detourText) one line under the story; the rule follows it (Frame.setCard)
  local detour = Theme.fontString(card, "text", S.s or 12, Theme.C.sepia, "OVERLAY", "LEFT")
  detour:SetPoint("TOPLEFT", story, "BOTTOMLEFT", 0, -4)
  detour:SetWidth(L.w)
  detour:SetWordWrap(false)
  detour:Hide()
  local rule = card:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(Theme.C.sepia[1], Theme.C.sepia[2], Theme.C.sepia[3], 0.45)
  rule:SetPoint("TOPLEFT", story, "BOTTOMLEFT", 0, -12)
  rule:SetSize(L.w, 1)
  local rows, anchor = {}, rule
  for i, def in ipairs(Frame.ROWS) do
    local row = CreateFrame("Frame", nil, card)
    row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, i == 1 and -6 or 0)
    row:SetSize(Frame.TABLE_W, Frame.ROW_H)
    local l = Theme.fontString(row, "text", S.m or 14, Theme.C.sepia, "OVERLAY", "LEFT")
    l:SetPoint("LEFT", row, "LEFT", 0, 0)
    l:SetText(def.label)
    local v = Theme.fontString(row, "text", S.m or 14, def.red and Theme.C.red or Theme.C.ink, "OVERLAY", "RIGHT")
    v:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    v:SetWidth(Frame.TABLE_W - 120)
    v:SetWordWrap(false)
    local ln = row:CreateTexture(nil, "ARTWORK")
    ln:SetColorTexture(Theme.C.sepia[1], Theme.C.sepia[2], Theme.C.sepia[3], 0.2)
    ln:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    ln:SetSize(Frame.TABLE_W, 1)
    rows[i] = { frame = row, label = l, value = v, key = def.key }
    anchor = row
  end
  card.label, card.title, card.sub, card.story, card.rule, card.rows = label, title, sub, story, rule, rows
  card.detour = detour
  card.measure = Theme.fontString(card, "label", S.s or 12, Theme.C.sepia, "OVERLAY", "LEFT")
  card.measureText = Theme.fontString(card, "text", S.s or 12, Theme.C.sepia, "OVERLAY", "LEFT")
  card.measure:SetWordWrap(false)
  card.measureText:SetWordWrap(false)
  card.measure:Hide()
  card.measureText:Hide()
  local sh = CreateFrame("Frame", nil, card)
  sh:SetPoint("LEFT", sub, "LEFT", 0, 0)
  sh:SetSize(L.w - 250, 16)
  sh:EnableMouse(false)
  sh:SetScript("OnEnter", function(self)
    if card.subFull and Journal.Widgets then Journal.Widgets.tip(self, { card.subFull }) end
  end)
  sh:SetScript("OnLeave", function(self) if Journal.Widgets then Journal.Widgets.hideTip(self) end end)
  card.subHover = sh
  -- long chapter/zone title shrinks (fitLine in setCard); full text on hover
  local th = CreateFrame("Frame", nil, card)
  th:SetPoint("TOPLEFT", title, "TOPLEFT", 0, 0)
  th:SetSize(L.w, 34)
  th:EnableMouse(false)
  th:SetScript("OnEnter", function(self)
    local t = card.titleFull
    if t and Journal.Widgets then Journal.Widgets.tip(self, { t }) end
  end)
  th:SetScript("OnLeave", function(self) if Journal.Widgets then Journal.Widgets.hideTip(self) end end)
  card.titleHover = th
  card.scribble = Frame.buildScribble(card, title)
  return card, anchor
end

function Frame.buildScribble(card, title)
  local S = Frame.SCRIBBLE
  local maxW = Frame.LEFT.w
  local words = {}
  for w in tostring(Frame.TEXT.unexploredNote):gmatch("%S+") do words[#words + 1] = w end
  local box = CreateFrame("Frame", nil, card)
  box:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -(36 + 16 + S.top))
  box.words, box.lines = {}, {}
  local widths = {}
  for i, w in ipairs(words) do
    local fs = Theme.fontString(box, "title", S.size, Theme.C.ink, "OVERLAY", "LEFT")
    fs:SetWordWrap(false)
    fs:SetText(w)
    local ok, width = pcall(fs.GetStringWidth, fs)
    if not ok or type(width) ~= "number" or width <= 0 then width = #w * S.size * 0.5 end
    fs:SetWidth(width + 2)
    widths[i] = width
    box.words[i] = fs
  end
  local lines, cur, curW = {}, {}, 0
  for i = 1, #words do
    local need = (#cur > 0 and S.gap or 0) + widths[i]
    if #cur > 0 and curW + need > maxW then
      lines[#lines + 1] = cur
      cur, curW, need = {}, 0, widths[i]
    end
    cur[#cur + 1] = i
    curW = curW + need
  end
  if #cur > 0 then lines[#lines + 1] = cur end
  local y = 0
  for li, idxs in ipairs(lines) do
    local n = #idxs
    local rise = S.rise * (n - 1)
    local x = 0
    for k, i in ipairs(idxs) do
      box.words[i]:SetPoint("TOPLEFT", box, "TOPLEFT", x, -(y + S.rise * (n - k)))
      x = x + widths[i] + S.gap
    end
    local len = max(x - S.gap, 10)
    local line = box:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(Theme.C.ink[1], Theme.C.ink[2], Theme.C.ink[3], 0.55)
    line:SetSize(len, S.underline)
    line:SetPoint("CENTER", box, "TOPLEFT", len / 2, -(y + S.size + 4 + rise / 2))
    if line.SetRotation then line:SetRotation(math.atan(rise / len)) end
    box.lines[li] = line
    y = y + S.size + rise + S.lineGap
  end
  box.line = box.lines[1]
  box:SetSize(maxW, max(y, S.size))
  box:Hide()
  return box
end

-- Shorter versions of the subtitle (pure, tested): full -> without times -> "to" as a dash -> levels only (part before the
-- first " · ")
function Frame.subVariants(s)
  s = tostring(s or "")
  local out = { s }
  local noTime = s:gsub("%s+%d%d?:%d%d", "")
  if noTime ~= s then out[#out + 1] = noTime end
  local dash = noTime:gsub("%s+bis%s+", "–"):gsub("%s+to%s+", "–")
  if dash ~= noTime then out[#out + 1] = dash end
  local head = s:match("^(.-)%s+·%s+")
  if head and head ~= "" and head ~= out[#out] then out[#out + 1] = head end
  return out
end

local function strWidth(fs, text)
  fs:SetText(text)
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

Frame.CARD_LINE_GAP = 10
function Frame.fitCardLine(card, sub)
  local L = Frame.LEFT
  local lw = strWidth(card.measure, card.label:GetText() or "")
  if lw > 0 then card.label:SetWidth(lw + 2) end
  local reserve = 0
  local pb = J.pb
  if pb and pb.nav and pb.nav.frame:IsShown() then
    local n = pb.list and #pb.list or 0
    local nw = tonumber(pb.nav.frame:GetWidth()) or 54
    local rw = strWidth(card.measure, Frame.TEXT("chapterRange", int(n), int(n), int(n)))
    if rw <= 0 then rw = 110 end
    reserve = nw - 4 + 6 + rw + Frame.CARD_LINE_GAP
  end
  local avail = L.w - (lw > 0 and lw or 110) - Frame.CARD_LINE_GAP - reserve
  card.sub:SetWidth(max(40, avail))
  local list = Frame.subVariants(sub)
  local pick = list[1]
  for _, v in ipairs(list) do
    pick = v
    local w = strWidth(card.measureText, v)
    if w <= 0 or w <= avail then break end
  end
  card.sub:SetText(pick)
  card.subFull = pick ~= list[1] and list[1] or nil
  if card.subHover then
    card.subHover:SetWidth(max(40, avail))
    card.subHover:EnableMouse(card.subFull ~= nil)
  end
end

-- Detour line under the story: shown only with text, the rule (and with it the values table) moves down by one line
function Frame.setDetourLine(card, text)
  local d = card.detour
  if not d then return end
  local show = type(text) == "string" and text ~= ""
  d:SetText(show and text or "")
  d:SetShown(show)
  card.rule:ClearAllPoints()
  card.rule:SetPoint("TOPLEFT", show and d or card.story, "BOTTOMLEFT", 0, show and -8 or -12)
end

-- 28 pt title: shrinks down to 18 pt before it would be cut; the hover shows the full text only when it was too wide
function Frame.setCardTitle(card, text)
  card.title:SetText(text)
  local size = Journal.Widgets.fitLine(card.title, Frame.LEFT.w, 18)
  local cut = size and (size < (card.title.fitBase or size) or (tonumber(card.title:GetStringWidth()) or 0) > Frame.LEFT.w)
  card.titleFull = cut and text or nil
  if card.titleHover then card.titleHover:EnableMouse(cut and true or false) end
end

function Frame.setCard(c)
  local card = J.card
  if not card then return end
  if not c then
    card:Hide()
    return
  end
  local unexplored = c.unexplored and true or false
  card.sub:SetShown(not unexplored)
  card.story:SetShown(not unexplored)
  card.rule:SetShown(not unexplored)
  Frame.setDetourLine(card, (not unexplored and not c.total) and c.detourText or nil)
  for _, r in ipairs(card.rows) do r.frame:SetShown(not unexplored) end
  if card.scribble then card.scribble:SetShown(unexplored) end
  if unexplored then
    card.label:SetText(Frame.TEXT.unexplored)
    local lw = strWidth(card.measure, Frame.TEXT.unexplored)
    card.label:SetWidth(lw > 0 and (lw + 2) or Frame.LEFT.w)
    Frame.setCardTitle(card, c.zoneName or Frame.TEXT.unknownArea)
    card.shown = c.index
    card:Show()
    return
  end
  card.label:SetText(c.total and Frame.TEXT.totalLabel or Frame.TEXT("chapterUpper", c.roman or ""))
  Frame.setCardTitle(card, c.zoneName or Frame.TEXT.underway)
  Frame.fitCardLine(card, c.subtitle or c.label or "")
  card.story:SetText(c.story or "")
  local s = c.stats or {}
  local values = {
    played = s.playedText or Frame.TEXT.zeroMin, levels = View.levelSpan(c.levelFrom, c.levelTo) or "", kills = int(s.kills),
    deaths = int(s.deaths), quests = int(s.quests), shots = int(s.shots), moments = int(s.moments),
  }
  for _, r in ipairs(card.rows) do r.value:SetText(values[r.key] or "") end
  card.shown = c.index
  card:Show()
end

local function tabAvailable(id)
  if id == Frame.HOME then return true end
  local P = Journal.Pages
  return P ~= nil and P.isAvailable(id) == true
end

function Frame.updateTabs()
  if not J.tabs then return end
  for _, b in ipairs(J.tabs) do
    local current = J.page == b.tabId
    local available = tabAvailable(b.tabId)
    -- Bookmark: fixed size, only the position on the book frame changes: active sticks out further by pull and fully bright,
    -- inactive by the small spread dx and clearly darkened, minimally raised under the mouse. The left end stays under the cover.
    local k = Frame.TAB
    local lift = (not current and b.hover and available) and k.hover or 0
    local out = current and k.pull or (b.wobble.dx + lift)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", b.owner, "TOPRIGHT", out - k.under, b.baseY)
    -- clickable only from the parchment edge outwards; what is tucked under the page catches nothing
    if b.SetHitRectInsets then b:SetHitRectInsets(math.max(0, k.under - Frame.RIM - out), 0, 0, 0) end
    b:SetAlpha(available and 1 or 0.8)
    local v = current and 1 or (available and (lift > 0 and 0.85 or 0.7) or 0.5)
    b.tex:SetVertexColor(v, v, v)
    Frame.tabLabelTone(b, v)
    b.available = available
  end
  Frame.updateSubTabs()
end

Frame.TAB_TIP = setmetatable({}, { __index = function(_, id)
  if id == "reise" or id == "chronik" or id == "kampf" or id == "quests" or id == "schaetze" or id == "momente" or id == "notizen" then
    -- Retail: no campfire guests (bookmark "Am Feuer" hidden) and no Lehrplan
    local ms, lp = Journal.MapSpace, Journal.Lehrplan
    local noFire = id == "chronik" and ms ~= nil and type(ms.fireTalkHidden) == "function" and ms.fireTalkHidden() == true
    local noPlan = id == "quests" and lp ~= nil and type(lp.active) == "function" and lp.active() == false
    return Frame.TEXT["tabTip_" .. id .. ((noFire or noPlan) and "Retail" or "")]
  end
  return nil
end })

-- Tab label: Friz Quadrata in bronze-gold, "stamped" = dark shadow top left (the font's shadow) and a light under-cut (second
-- copy 1 px lower, behind). Centred at Frame.TAB.textX; if the name is wider than textW the font shrinks (down to minSize).
-- Returns main text, under-cut.
function Frame.tabLabel(b, text)
  local k, L = Frame.TAB, Frame.TAB_LABEL
  local font = (Theme.FONT and Theme.FONT.text) or "Fonts\\FRIZQT__.TTF"
  local function make(sub)
    local fs = b:CreateFontString(nil, "OVERLAY", nil, sub)
    fs.inkPlain = true
    fs:SetJustifyH("CENTER")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    return fs
  end
  local lip, fs = make(1), make(2)
  local size = k.size
  for _ = 1, 2 do
    for _, t in ipairs({ lip, fs }) do
      if not pcall(t.SetFont, t, font, size, "") and t.SetFontObject and GameFontNormal then t:SetFontObject(GameFontNormal) end
      t:SetText(text)
    end
    local w = fs.GetStringWidth and fs:GetStringWidth() or 0
    if w <= k.textW or size <= k.minSize then break end
    size = math.max(k.minSize, math.floor(size * k.textW / w * 2) / 2)
  end
  fs:SetPoint("CENTER", b, "LEFT", k.textX, 0)
  lip:SetPoint("CENTER", b, "LEFT", k.textX, -1)
  if fs.SetShadowColor then pcall(fs.SetShadowColor, fs, L.shadow[1], L.shadow[2], L.shadow[3], L.shadow[4]) end
  if fs.SetShadowOffset then pcall(fs.SetShadowOffset, fs, -1, 1) end
  if lip.SetShadowOffset then pcall(lip.SetShadowOffset, lip, 0, 0) end
  b.label, b.labelLip, b.labelSize = fs, lip, size
  return fs, lip
end

function Frame.tabLabelTone(b, v)
  if not b.label then return end
  local g, lip = Frame.TAB_LABEL.gold, Frame.TAB_LABEL.lip
  local t = 0.5 + 0.5 * v
  b.label:SetTextColor(g[1] * t, g[2] * t, g[3] * t, 1)
  b.labelLip:SetTextColor(lip[1], lip[2], lip[3], lip[4] * v)
end

local function buildTabs(f)
  J.tabs = {}
  for i, tab in ipairs(Theme.TABS) do
    local b = CreateFrame("Button", nil, f)
    b:SetFrameLevel(f:GetFrameLevel() + Frame.TAB_LEVEL)
    local t = b:CreateTexture(nil, "ARTWORK")
    local k, w = Frame.TAB, Frame.TAB_WOBBLE[tab.id]
    local u0, u1, v0, v1 = Theme.tabBandCoords(tab.id)
    b.bookmark, b.wobble, b.owner = true, w, f
    b.baseY = -(k.y0 + (i - 1) * k.pitch + w.dy)
    b:SetSize(k.w, k.h)
    -- Tilt without Texture:SetRotation (it shears at 5.3 : 1 and samples beyond the cell): the area stays straight and the content
    -- is rotated aspect-corrected with Theme.rotCoords. The area is k.pad px narrower than the cell at top and bottom so the
    -- rotated corners stay inside; the rest is zoomed in a few percent at most.
    local dv = (v1 - v0) * k.pad / k.h
    local A = Theme.TAB_BAND_ATLAS
    local cu0, cu1, cv0, cv1 = u0 + 0.5 / A.w, u1 - 0.5 / A.w, v0 + 0.5 / A.h, v1 - 0.5 / A.h
    local function tilted(tex, dx, dy)
      tex:ClearAllPoints()
      tex:SetPoint("TOPLEFT", b, "TOPLEFT", dx, -(k.pad + dy))
      tex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", dx, k.pad - dy)
      tex:SetTexture(Theme.TEX.tabBands)
      tex:SetTexCoord(Theme.rotCoords8(u0, u1, v0 + dv, v1 - dv, k.w, k.h - 2 * k.pad, w.deg, cu0, cu1, cv0, cv1))
    end
    local sh = b:CreateTexture(nil, "BACKGROUND")
    tilted(sh, k.sx, k.sy)
    sh:SetVertexColor(0, 0, 0)
    sh:SetAlpha(k.sa)
    b.shadow = sh
    tilted(t, 0, 0)
    b.tex, b.tabId = t, tab.id
    Frame.tabLabel(b, tab.label)
    b:SetScript("OnClick", safe(function() Frame.showPage(tab.id) end))
    b:SetScript("OnEnter", function(self)
      self.hover = true
      if self.bookmark then Frame.updateTabs() end
      if GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(tab.label, 1, 0.82, 0)
        if Frame.TAB_TIP[tab.id] then GameTooltip:AddLine(Frame.TAB_TIP[tab.id], 0.9, 0.85, 0.75, true) end
        if not self.available then GameTooltip:AddLine(Frame.TEXT.soon, 0.8, 0.8, 0.8) end
        GameTooltip:Show()
      end
    end)
    b:SetScript("OnLeave", function(self)
      self.hover = false
      if self.bookmark then Frame.updateTabs() end
      Theme.hideTooltip()
    end)
    J.tabs[i] = b
  end
  local size = Frame.TAB.size
  for _, b in ipairs(J.tabs) do size = math.min(size, b.labelSize or size) end
  local font = (Theme.FONT and Theme.FONT.text) or "Fonts\\FRIZQT__.TTF"
  for _, b in ipairs(J.tabs) do
    if b.labelSize ~= size then
      for _, t in ipairs({ b.label, b.labelLip }) do pcall(t.SetFont, t, font, size, "") end
      b.labelSize = size
    end
  end
  Frame.updateTabs()
end

function Frame.subList(id)
  if id == Frame.HOME then
    if Journal.Vorhaben then return Frame.SUBTABS_REISE end
    return { Frame.SUBTABS_REISE[1], Frame.SUBTABS_REISE[2] }
  end
  local P = Journal.Pages
  return P and P.subs and P.subs(id) or nil
end

function Frame.reiseSub()
  local V = Journal.Vorhaben
  if V and V.isOpen() then return "vorhaben" end
  if Frame.isTotal() then return "gesamt" end
  return "karte"
end

function Frame.currentSub()
  if not Frame.subList(J.page) then return nil end
  if J.page == Frame.HOME then return Frame.reiseSub() end
  local P = Journal.Pages
  return P and P.sub(J.page) or nil
end

local function showReiseSub(key)
  local V = Journal.Vorhaben
  if key == "vorhaben" then
    if V and not V.isOpen() then V.open() end
    return
  end
  if V and V.isOpen() then V.close() end
  local total = Frame.isTotal()
  if (key == "gesamt") ~= total then
    J.sel, J.contWhole = {}, false
    J.mapMode = key == "gesamt" and "continent" or "zone"
    Frame.refresh()
  end
end

function Frame.showSub(key)
  local list = Frame.subList(J.page)
  if not (J.frame and J.frame:IsShown() and list and type(key) == "string") then return false end
  local known = false
  for _, s in ipairs(list) do
    if s.key == key then known = true end
  end
  if not known or key == Frame.currentSub() then return false end
  if J.page == Frame.HOME then
    showReiseSub(key)
  else
    local P = Journal.Pages
    if not (P and P.showSub(J.page, key)) then
      Frame.updateSubTabs()
      return false
    end
  end
  if Journal.Sound then pcall(Journal.Sound.play, "page") end
  Frame.updateSubTabs()
  return true
end

function Frame.updateSubEsc()
  local e = J.subEsc
  if not e then return end
  local on = J.page == Frame.HOME and Frame.reiseSub() == "gesamt" and not (J.back and J.back:IsShown())
  e:SetShown(on and true or false)
end

-- Texcoords for a ribbon piece rotated 90 degrees clockwise: u (along the cell) runs top to bottom, v (across) right to left
-- (the top edge of the cell lies on the right). -> UL, LL, UR, LR
function Frame.subTabCoords(u0, u1, v0, v1)
  return u0, v1, u1, v1, u0, v0, u1, v0
end

local function subTabSetCell(b, tabId)
  local k = Frame.SUBTAB
  local _, _, v0, v1 = Theme.bookmarkCoords(tabId)
  if not v0 then _, _, v0, v1 = Theme.bookmarkCoords(Frame.HOME) end
  local dv = k.trim / Theme.BOOKMARK_ATLAS.h
  v0, v1 = v0 + dv, v1 - dv
  for _, t in ipairs({ b.body, b.bodyShadow }) do t:SetTexCoord(Frame.subTabCoords(k.body0, k.body1, v0, v1)) end
  for _, t in ipairs({ b.tip, b.tipShadow }) do t:SetTexCoord(Frame.subTabCoords(k.tip0, k.tip1, v0, v1)) end
  b.cell = tabId
end

local SUB_LABEL = { 0.97, 0.86, 0.55 }

function Frame.updateSubTabs()
  if not J.subTabs then return end
  local k = Frame.SUBTAB
  local list = Frame.subList(J.page)
  local cur = list and Frame.currentSub()
  local x = k.x0
  local D = Journal.Widgets and Journal.Widgets.Diary
  for i, b in ipairs(J.subTabs) do
    local s = list and list[i]
    if s then
      b.subKey, b.sub = s.key, s
      if b.labelText ~= s.label then
        b.labelText = s.label
        b.text:SetText(s.label)
      end
      local tw = (D and D.measure(b.text)) or 0
      if tw <= 0 then tw = #s.label * 7 end
      local w = math.max(k.minW, floor(tw + 2 * k.pad + 0.5))
      if b.cell ~= J.page then subTabSetCell(b, J.page) end
      local current = s.key == cur
      local lift = (not current and b.hover) and k.hover or 0
      local extra = current and k.pull or lift
      b:SetSize(w, k.under + k.out)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", b.owner, "BOTTOMLEFT", x, k.under - extra)
      if b.SetHitRectInsets then b:SetHitRectInsets(0, 0, math.max(0, k.under - extra - k.edge), 0) end
      local v = current and 1 or (b.hover and 0.8 or k.dim)
      b.body:SetVertexColor(v, v, v)
      b.tip:SetVertexColor(v, v, v)
      b.text:SetTextColor(SUB_LABEL[1], SUB_LABEL[2], SUB_LABEL[3], current and 1 or 0.82)
      b.current = current
      b:Show()
      x = x + w + k.gap
    else
      b.subKey, b.sub, b.current = nil, nil, false
      b:Hide()
    end
  end
  Frame.updateSubEsc()
end

local function buildSubTabs(f)
  J.subTabs = {}
  local k = Frame.SUBTAB
  local D = Journal.Widgets and Journal.Widgets.Diary
  for i = 1, Frame.SUBTABS_MAX do
    local b = CreateFrame("Button", nil, f)
    b:SetFrameLevel(f:GetFrameLevel() + Frame.TAB_LEVEL)
    b.owner = f
    local function piece(layer, dx, dy, isTip)
      local t = b:CreateTexture(nil, layer)
      t:SetTexture(Theme.TEX.bookmarks)
      if isTip then
        t:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", dx, -dy)
        t:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", dx, -dy)
        t:SetHeight(k.tip)
      else
        t:SetPoint("TOPLEFT", b, "TOPLEFT", dx, -dy)
        t:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", dx, k.tip - dy)
      end
      return t
    end
    b.bodyShadow = piece("BACKGROUND", k.sx, k.sy, false)
    b.tipShadow = piece("BACKGROUND", k.sx, k.sy, true)
    for _, t in ipairs({ b.bodyShadow, b.tipShadow }) do
      t:SetVertexColor(0, 0, 0)
      t:SetAlpha(k.sa)
    end
    b.body = piece("ARTWORK", 0, 0, false)
    b.tip = piece("ARTWORK", 0, 0, true)
    local fs = D and D.font(b, "hand", k.size, "ink", "OVERLAY") or Theme.fontString(b, "label", 13, Theme.C.parchment, "OVERLAY", "CENTER")
    fs:SetJustifyH("CENTER")
    fs:SetWordWrap(false)
    if fs.SetShadowColor then pcall(fs.SetShadowColor, fs, 0, 0, 0, 0.85) end
    if fs.SetShadowOffset then pcall(fs.SetShadowOffset, fs, 1, -1) end
    fs:SetPoint("CENTER", b, "BOTTOM", 0, k.tip + (k.out + k.edge - k.tip) / 2)
    fs.diaryRefit = function() Frame.updateSubTabs() end
    b.text = fs
    b:SetScript("OnClick", safe(function(self) if self.subKey then Frame.showSub(self.subKey) end end))
    b:SetScript("OnEnter", function(self)
      self.hover = true
      Frame.updateSubTabs()
      local W = Journal.Widgets
      if W and self.sub and type(self.sub.tip) == "table" then W.tip(self, self.sub.tip) end
    end)
    b:SetScript("OnLeave", function(self)
      self.hover = false
      Frame.updateSubTabs()
      local W = Journal.Widgets
      if W then W.hideTip(self) end
    end)
    b:Hide()
    J.subTabs[i] = b
  end
  Frame.updateSubTabs()
end

local function buildSettings(f)
  local gear = CreateFrame("Button", nil, f)
  gear:SetSize(34, 34)
  local gearY = -(Frame.TAB.y0 + #Theme.TABS * Frame.TAB.pitch + 8)
  gear:SetPoint("TOPLEFT", f, "TOPRIGHT", -2, gearY)
  local disc = gear:CreateTexture(nil, "BACKGROUND")
  disc:SetAllPoints(gear)
  disc:SetTexture(Theme.TEX.markers)
  disc:SetTexCoord(Theme.atlasCoords(Theme.ATLAS.disc))
  Theme.color(disc, Theme.C.cover)
  local ring = gear:CreateTexture(nil, "BORDER")
  ring:SetAllPoints(gear)
  ring:SetTexture(Theme.TEX.markers)
  ring:SetTexCoord(Theme.atlasCoords(Theme.ATLAS.pulse))
  local dots = Theme.fontString(gear, "text", 14, Theme.C.parchment, "OVERLAY", "CENTER")
  dots:SetPoint("CENTER", gear, "CENTER", 0, 3)
  dots:SetText("...")
  gear:SetScript("OnClick", function()
    Frame.showSettings()
  end)
  gear:SetScript("OnEnter", function(self)
    if GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(Frame.TEXT.settings, 1, 0.82, 0)
      GameTooltip:AddLine(Frame.TEXT.settingsTip, 0.8, 0.8, 0.8, true)
      GameTooltip:Show()
    end
  end)
  gear:SetScript("OnLeave", Theme.hideTooltip)
  J.gear = gear
end

function Frame.showSettings()
  local O = Journal.Options
  if not O or type(O.open) ~= "function" then return false end
  return O.open() and true or false
end

-- Anchor point, x, y for the settings: relative to UIParent with the same anchor point (as placeFrame sets them again). If
-- the window hangs on something else after dragging, converted from the centre.
function Frame.anchorOf(f)
  local point, rel, relPoint, x, y = f:GetPoint(1)
  if point and x and y and (rel == nil or rel == UIParent) and (relPoint == nil or relPoint == point) then
    return point, x, y
  end
  local fx, fy = f:GetCenter()
  local ux, uy = UIParent:GetCenter()
  local es, ues = f:GetEffectiveScale(), UIParent:GetEffectiveScale()
  if fx and fy and ux and uy and es and ues and es > 0 then
    return "CENTER", fx - ux * ues / es, fy - uy * ues / es
  end
  return nil
end

local function savePosition(f)
  f:StopMovingOrSizing()
  local point, x, y = Frame.anchorOf(f)
  if point then View.set("pos", { point = point, x = x, y = y }) end
end

local function placeFrame(f)
  f:ClearAllPoints()
  local pos = View.peek("pos")
  -- peek returns checked values only (anchor-point whitelist); the pcall is the second bolt: a SetPoint error must never keep
  -- the window from being created.
  if pos and pcall(f.SetPoint, f, pos.point, UIParent, pos.point, pos.x, pos.y) then return end
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
end

function Frame.maxScale()
  local uw = UIParent and UIParent.GetWidth and tonumber(UIParent:GetWidth())
  local uh = UIParent and UIParent.GetHeight and tonumber(UIParent:GetHeight())
  if not (uw and uh) or uw ~= uw or uh ~= uh or uw <= 0 or uh <= 0 then return nil end
  local pad = 2 * Frame.SCREEN_PAD
  return math.min((uw - pad) / (Frame.W + Frame.TABS_OUT), (uh - pad) / (Frame.H + Frame.SUBTABS_OUT))
end

-- Default size (no own choice): 75 %, at most so that the book is not taller than 90 % of the screen height (small
-- resolution, large UI scale). 75 % if the screen height is unknown.
function Frame.defaultScale()
  local s = Frame.DEFAULT_SCALE
  local uh = UIParent and UIParent.GetHeight and tonumber(UIParent:GetHeight())
  if uh and uh == uh and uh > 0 then s = math.min(s, Frame.DEFAULT_MAX_HEIGHT * uh / Frame.H) end
  return s
end

function Frame.currentScale()
  deps()
  if View.scaleChosen() then return View.peek("scale") or 1 end
  return Frame.defaultScale()
end

-- Effective scale: setting (0.5..2), at most so large that the window fits the screen. On very small screens it may fall below
-- 0.5 (otherwise the window would be unusable).
function Frame.effectiveScale(v)
  v = tonumber(v)
  if not v or v ~= v then v = 1 end
  v = math.max(Frame.SCALE_MIN, math.min(Frame.SCALE_MAX, v))
  local fit = Frame.maxScale()
  if fit and fit > 0.05 and v > fit then v = fit end
  return v
end

-- Scaling: the anchor point stays on screen (offset converted to window units); the new position is remembered so the
-- window does not drift on the next open.
function Frame.setScale(v)
  deps()
  v = tonumber(v)
  if not v or v ~= v or v < Frame.SCALE_MIN or v > Frame.SCALE_MAX then return false end
  if View.set("scale", v) and J.frame then Frame.applyScale(v) end
  return true
end

function Frame.applyScale(v)
  local f = J.frame
  if not f then return false end
  local eff = Frame.effectiveScale(v or Frame.currentScale())
  local old = f:GetScale() or 1
  if math.abs(old - eff) < 1e-6 then return true end
  local point, x, y = Frame.anchorOf(f)
  f:SetScale(eff)
  if point and old > 0 then
    local nx, ny = x * old / eff, y * old / eff
    f:ClearAllPoints()
    f:SetPoint(point, UIParent, point, nx, ny)
    View.set("pos", { point = point, x = nx, y = ny })
  end
  return true
end

function Frame.resetLayout()
  deps()
  View.set("scale", nil)
  View.set("pos", nil)
  J.pendingScale = nil
  local f = J.frame
  if f then
    f:SetScale(Frame.effectiveScale(Frame.currentScale()))
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
  end
  return true
end

local function releaseHome()
  if J.vorhaben and Journal.Vorhaben then pcall(Journal.Vorhaben.close) end
  if Journal.Vorhaben and Journal.Vorhaben.cancelPick then pcall(Journal.Vorhaben.cancelPick, true) end
  View.setActive(false)
  if J.st then J.st.playing = false end
  J.openT0 = nil
  Playback.stopTicking(J.pb)
  Theme.hideTooltip()
  if J.over then J.over:Hide() end
  if J.map then
    J.map.viewport:Hide()
    J.model, J.scene, J.map.scene = nil, nil, nil
  end
end

local function enterHome()
  J.pageLeft:Hide()
  J.pageRight:Hide()
  J.over:Show()
  View.setActive(true)
  local _, _, changed = View.request()
  if not changed then Frame.render(View.status, View.model, View.stale) end
end

local function applyPage(id)
  local P = Journal.Pages
  J.page = id
  local left, right = Theme.paper(id)
  J.paperL:SetTexture(left)
  J.paperR:SetTexture(right)
  Theme.setPaper(J.paperL, J.paperR, left, right)
  if id == Frame.HOME then
    if P then P.hide() end
    enterHome()
  else
    releaseHome()
    J.pageLeft:Show()
    J.pageRight:Show()
    P.show(id)
  end
  Frame.updateTabs()
end

function Frame.showPage(id)
  local f = J.frame
  if not f or not f:IsShown() or type(id) ~= "string" then return false end
  if not tabAvailable(id) then return false end
  if id == J.page then return true end
  applyPage(id)
  if Journal.Sound then pcall(Journal.Sound.play, "page") end
  return true
end

-- Book base image pieces (Theme.BOOK_SLICE): 3 rows x 5 columns, row by row; each with position/size in window pixels and
-- texcoords u0..u1, v0..v1. Scale s = rim / ring is equal everywhere; edges are rounded to whole pixels (no seams). The leather
-- edge lies on the window edge; the texture margin outside it (L.margin) sticks out by pad = margin * s px.
function Frame.bookPieces(w, h, rim)
  deps()
  w, h, rim = w or Frame.W, h or Frame.H, rim or Frame.RIM
  local L = Theme.BOOK_SLICE
  local s = rim / L.ring
  local function r(v) return floor(v + 0.5) end
  local m = L.margin or 0
  local cs, spw, pad = L.corner * s, (L.spine1 - L.spine0) * s, r(m * s)
  local xs = { -pad, r(cs), r(w / 2 - spw / 2), r(w / 2 + spw / 2), w - r(cs), w + pad }
  local us = { 0, m + L.corner, L.spine0, L.spine1, L.w - m - L.corner, L.w }
  local ys = { -pad, r(cs), h - r(cs), h + pad }
  local vs = { 0, m + L.corner, L.h - m - L.corner, L.h }
  local out = {}
  for row = 1, 3 do
    for col = 1, 5 do
      out[#out + 1] = { x = xs[col], y = ys[row], w = xs[col + 1] - xs[col], h = ys[row + 1] - ys[row],
        u0 = us[col] / L.w, u1 = us[col + 1] / L.w, v0 = vs[row] / L.h, v1 = vs[row + 1] / L.h,
        spine = col == 3 or nil }
    end
  end
  return out
end

function Frame.paperRect()
  local o = Frame.PAPER_OUT
  return Frame.RIM - o.x, Frame.RIM - o.top, Frame.SPREAD_W + 2 * o.x, Frame.SPREAD_H + o.top + o.bottom
end

function Frame.build()
  if J.frame then return J.frame end
  deps()
  local f = CreateFrame("Frame", Frame.NAME, UIParent)
  f:SetSize(Frame.W, Frame.H)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  if f.SetClampRectInsets then f:SetClampRectInsets(0, Frame.TABS_OUT, 0, -Frame.SUBTABS_OUT) end
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetDontSavePosition(true) -- the addon manages the position itself (EveNChronicleDB.ui.pos), not layout-local.txt
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", savePosition)
  f:SetScale(Frame.effectiveScale(Frame.currentScale()))
  placeFrame(f)
  f:Hide()
  J.frame = f

  J.book = {}
  for _, p in ipairs(Frame.bookPieces()) do
    local t = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    t:SetTexture(Theme.TEX.book)
    t:SetTexCoord(p.u0, p.u1, p.v0, p.v1)
    t:SetPoint("TOPLEFT", f, "TOPLEFT", p.x, -p.y)
    t:SetSize(p.w, p.h)
    J.book[#J.book + 1] = t
  end

  local spread = CreateFrame("Frame", nil, f)
  spread:SetPoint("TOPLEFT", f, "TOPLEFT", Frame.RIM, -Frame.RIM)
  spread:SetFrameLevel(f:GetFrameLevel() + Frame.SPREAD_LEVEL)
  spread:SetSize(Frame.SPREAD_W, Frame.SPREAD_H)
  J.spread = spread
  local half = Frame.SPREAD_W / 2
  local ppx, ppy, ppw, pph = Frame.paperRect()
  local pl = spread:CreateTexture(nil, "BACKGROUND")
  pl:SetTexture((Theme.paper(Frame.HOME)))
  pl:SetPoint("TOPLEFT", spread, "TOPLEFT", ppx - Frame.RIM, Frame.RIM - ppy)
  pl:SetSize(ppw / 2, pph)
  local pr = spread:CreateTexture(nil, "BACKGROUND")
  pr:SetTexture(select(2, Theme.paper(Frame.HOME)))
  pr:SetPoint("TOPLEFT", spread, "TOPLEFT", half, Frame.RIM - ppy)
  pr:SetSize(ppw / 2, pph)
  J.paperL, J.paperR = pl, pr
  Theme.setPaper(pl, pr, Theme.paper(Frame.HOME))

  local MA = Frame.MAP
  local map = Map.create(spread, MA.x, MA.y, MA.w, MA.h, { noteW = Frame.NOTE.w, noteMax = Frame.NOTE.max })
  map.onBack = safe(function() Frame.back() end)
  map.onRight = safe(function() Frame.rightClick() end)
  map.onPoint = safe(function(vx, vy) Frame.pickPoint(vx, vy) end)
  map.zoneAt = function(vx, vy) return Frame.hoverZone(vx, vy) end
  map.zoomTarget = function(dir, vx, vy) return Frame.zoomTarget(dir, vx, vy) end
  map.zoomApply = function(dir, target) return Frame.zoomApply(dir, target) end
  map.onView = safe(function() Frame.layoutControls() end)
  map.onPin = safe(function(id)
    if type(id) == "string" and string.match(id, "^todo:") then
      Frame.showSub("vorhaben")
      return
    end
    Frame.openNote(id)
  end)
  J.map = map

  local pageLevel = map.viewport:GetFrameLevel() + 2
  local pgLeft = CreateFrame("Frame", nil, spread)
  pgLeft:SetPoint("TOPLEFT", spread, "TOPLEFT", 0, 0)
  pgLeft:SetSize(half, Frame.SPREAD_H)
  pgLeft:SetFrameLevel(pageLevel)
  pgLeft:Hide()
  local pgRight = CreateFrame("Frame", nil, spread)
  pgRight:SetPoint("TOPLEFT", spread, "TOPLEFT", half, 0)
  pgRight:SetSize(half, Frame.SPREAD_H)
  pgRight:SetFrameLevel(pageLevel)
  pgRight:Hide()
  J.pageLeft, J.pageRight = pgLeft, pgRight
  local P = Journal.Pages
  if P then
    P.attach(pgLeft, pgRight)
    P.onChange(Frame.updateTabs)
    if P.onSubChange then P.onSubChange(function() Frame.updateSubTabs() end) end
  end

  local over = CreateFrame("Frame", nil, spread)
  over:SetAllPoints(spread)
  over:SetFrameLevel(map.viewport:GetFrameLevel() + 12)
  J.over = over
  local W = Journal.Widgets

  local card, tableEnd = buildCard(over)
  J.card = card
  local noteBox = CreateFrame("Frame", nil, over)
  noteBox:SetPoint("TOPLEFT", over, "TOPLEFT", Frame.NOTE.x, -Frame.NOTE.y)
  noteBox:SetSize(Frame.NOTE.w, Frame.NOTE.h)
  J.noteBox = noteBox

  map.noteBox = noteBox

  local L, R = Frame.LEFT, Frame.RIGHT
  local leftHead = W.NewPageHead(over, { side = "L", spread = true })
  leftHead:SetTexts(Frame.TEXT.bookHead, Frame.TEXT.bookHeadRight)
  local rightHead = W.NewPageHead(over, { side = "R", spread = true })
  J.leftHead, J.rightHead = leftHead, rightHead
  J.headLine, J.headDay, J.headRule = rightHead.left, rightHead.right, rightHead.rule

  local tb = CreateFrame("Frame", nil, over)
  tb:SetPoint("TOPLEFT", over, "TOPLEFT", R.x, -Frame.TITLE_Y)
  tb:SetSize(Frame.TITLE_W, Frame.CTRL_Y - Frame.TITLE_Y)
  J.titleBox = tb
  local S = GRID.size or {}
  local tn = Theme.fontString(tb, "title", S.xl or 28, Theme.C.ink, "OVERLAY", "LEFT")
  tn:SetPoint("TOPLEFT", tb, "TOPLEFT", 0, 0)
  tn:SetWidth(Frame.TITLE_W)
  tn:SetWordWrap(false)
  local tl = Theme.fontString(tb, "label", S.s or 12, Theme.C.sepia, "OVERLAY", "LEFT")
  tl:SetPoint("TOPLEFT", tb, "TOPLEFT", 0, -36)
  tl:SetWordWrap(false)
  local ts = Theme.fontString(tb, "label", S.s or 12, Theme.C.ink, "OVERLAY", "LEFT")
  ts:SetPoint("LEFT", tl, "RIGHT", 10, 0)
  ts:SetWidth(Frame.TITLE_W - 130)
  ts:SetWordWrap(false)
  J.titleLabel, J.titleName, J.titleStats = tl, tn, ts
  local tnh = CreateFrame("Frame", nil, tb)
  tnh:SetPoint("TOPLEFT", tn, "TOPLEFT", 0, 0)
  tnh:SetSize(Frame.TITLE_W, 34)
  tnh:EnableMouse(false)
  tnh:SetScript("OnEnter", function(self)
    local t = J.titleNameFull
    if t and Journal.Widgets then Journal.Widgets.tip(self, { t }) end
  end)
  tnh:SetScript("OnLeave", function(self) if Journal.Widgets then Journal.Widgets.hideTip(self) end end)
  J.titleNameHover = tnh
  if Journal.Vorhaben then
    J.vorhaben = Journal.Vorhaben.build(over)
    Journal.Vorhaben.onChange = function() Frame.updateSubTabs() end
  end

  local D = W.Diary
  local ctrl = CreateFrame("Frame", nil, over)
  ctrl:SetPoint("TOPLEFT", over, "TOPLEFT", R.x, -Frame.CTRL_Y)
  ctrl:SetSize(R.w, Frame.CTRL_H)
  J.ctrl = ctrl
  local back = D.NewBack(over, Frame.TEXT.back, safe(function() Frame.back() end),
    { tip = { Frame.TEXT.backTitle, Frame.TEXT.backTip } })
  D.placeBack(back, over, Frame.BACK.x, Frame.BACK.y)
  back:Hide()
  J.back = back
  -- Esc on the total journey (without zoom; otherwise "Back" removes the zoom first) leads to the default view "map".
  -- Invisible keyboard catcher, visible only while the total journey is shown without to-do sheet and without "Back".
  local subEsc = CreateFrame("Frame", nil, over)
  subEsc:SetSize(1, 1)
  subEsc:SetPoint("TOPLEFT", over, "TOPLEFT", 0, 0)
  D.escKeys(subEsc, safe(function() Frame.showSub("karte") end))
  subEsc:Hide()
  J.subEsc = subEsc
  local cont = D.NewToggle(ctrl, { size = Frame.CTRL_SIZE, gap = 14, onChange = safe(function(key)
    J.mapMode = "continent"
    Frame.select({ continent = key })
  end) })
  cont.frame:Hide()
  J.contToggle = cont
  local mode = D.NewToggle(ctrl, { size = Frame.CTRL_SIZE, gap = 14,
    items = {
      { key = "zone", label = Frame.TEXT.zone, tip = { Frame.TEXT.zone, Frame.TEXT.zoneTip } },
      { key = "continent", label = Frame.TEXT.continent, tip = { Frame.TEXT.continent, Frame.TEXT.continentTip, Frame.TEXT.rightTip } },
    },
    value = "zone",
    onChange = safe(function(key)
      if J.scene and key ~= J.scene.mode then Frame.toggleMapMode() elseif J.scene then updateMode(J.scene) end
    end) })
  mode.frame:SetPoint("LEFT", ctrl, "LEFT", -3, 0)
  mode.frame:Hide()
  J.modeToggle = mode
  J.modeLabel, J.modeButton = mode.buttons[1], mode.buttons[2]

  local kb = D.NewCheck(ctrl, Frame.TEXT.kills, { size = Frame.CTRL_SIZE, checked = Frame.killsShown(),
    tip = { Frame.TEXT.kills, Frame.TEXT.killsTip },
    onChange = safe(function(on) Frame.setShowKills(on) end) })
  kb:Hide()
  J.killBox = kb
  local stale = Theme.fontString(ctrl, "label", S.s or 12, Theme.C.sepia, "OVERLAY", "RIGHT")
  stale:SetPoint("RIGHT", ctrl, "RIGHT", 0, 0)
  stale:SetText(Frame.TEXT.stale)
  stale:Hide()
  J.staleHint = stale

  local WK = Frame.WORLD_LINK
  local wl = D.NewSticker(over, Frame.TEXT.worldMap, safe(function() Frame.openWorldMap() end),
    { height = WK.h, size = WK.size, tip = { Frame.TEXT.worldMap, Frame.TEXT.worldMapTip } })
  wl:SetPoint("TOPLEFT", over, "TOPLEFT", R.x, -WK.y)
  wl:Hide()
  J.worldLink = wl

  local msg = CreateFrame("Frame", nil, over)
  msg:SetSize(MA.w - 40, 90)
  msg:SetPoint("CENTER", over, "TOPLEFT", MA.x + MA.w / 2, -(MA.y + MA.h / 2))
  local mt = Theme.fontString(msg, "title", 18, Theme.C.ink, "OVERLAY", "CENTER")
  mt:SetPoint("CENTER", msg, "CENTER", 0, 0)
  mt:SetWidth(MA.w - 60)
  msg.text = mt
  msg:Hide()
  J.msg = msg

  local hint = CreateFrame("Frame", nil, over)
  hint:SetSize(230, 36)
  hint:SetPoint("TOP", over, "TOPLEFT", MA.x + MA.w / 2, -(MA.y + 12))
  hint:SetFrameLevel(over:GetFrameLevel() + 6)
  Theme.roundRect(hint, Theme.C.card, 0.94, 10, "BACKGROUND")
  Theme.roundRect(hint, Theme.C.gold, 0.95, 10, "BORDER", Theme.TEX.ring)
  hint.text = Theme.fontString(hint, "title", 18, Theme.C.ink, "OVERLAY", "CENTER")
  hint.text:SetPoint("CENTER", hint, "CENTER", 0, 0)
  hint:Hide()
  J.hint = hint

  local safeTick = safe(function(dt) Frame.tick(dt) end)
  local T = Frame.TIMELINE
  J.pb = Playback.create(over, T.x, T.y, T.w, T.h, {
    onToggle = safe(function() Frame.togglePlay() end),
    onSpeed = safe(function(speed) Frame.setSpeed(speed) end),
    onSeek = safe(function(frac) Frame.seek(frac) end),
    onScrubStart = safe(function() Frame.scrubStart() end),
    onScrubEnd = safe(function(aborted) Frame.scrubEnd(aborted) end),
    onChapter = safe(function(i)
      if i == 0 then Frame.selectTotal() else Frame.select(J.sel.chapter == i and nil or { chapter = i }) end
    end),
    -- If a tick throws, playback ends (otherwise the error would occur 60 times per second)
    onUpdate = function(dt)
      if not safeTick(dt) then
        if J.st then J.st.playing = false end
        Playback.stopTicking(J.pb)
      end
    end,
  }, { compact = true, speedW = T.speedW, navOut = true, grid = { x = T.GRID.x, y = T.GRID.y, w = T.GRID.w, rows = T.GRID.rows,
    gapY = T.GRID.gapY, parent = over } })
  local navY = Frame.CARD_Y + 36 + 7
  J.pb.nav.frame:ClearAllPoints()
  J.pb.nav.frame:SetPoint("RIGHT", over, "TOPLEFT", Frame.LEFT.x + Frame.LEFT.w + 4, -navY)
  J.pb.range:ClearAllPoints()
  J.pb.range:SetPoint("RIGHT", J.pb.nav.frame, "LEFT", -6, 0)
  J.st = Playback.new(View.peek("speed"))
  if Stations then
    local SA = Frame.STATIONS
    local sb = Stations.create(over, SA.x, SA.y, SA.w, SA.h, { onPick = safe(function(s) Frame.pickStation(s) end) })
    sb.nav.frame:ClearAllPoints()
    sb.nav.frame:SetPoint("RIGHT", over, "TOPLEFT", Frame.LEFT.x + Frame.LEFT.w + 4, -navY)
    sb.range:ClearAllPoints()
    sb.range:SetPoint("RIGHT", sb.nav.frame, "LEFT", -6, 0)
    sb.frame:Hide()
    J.stations = sb
    local I = Journal.Index
    if I and I.onReady then
      I.onReady(function()
        J.stationsFor = nil
        if J.frame and J.frame:IsShown() and J.page == Frame.HOME and J.model and Frame.isTotal() then Frame.updateStations(true, true) end
      end)
    end
  end

  local close = CreateFrame("Button", nil, f)
  close:SetSize(26, 26)
  close:SetPoint("CENTER", f, "TOPRIGHT", -4, -4)
  close:SetFrameLevel(over:GetFrameLevel() + 5)
  local cd = close:CreateTexture(nil, "BACKGROUND")
  cd:SetAllPoints(close)
  cd:SetTexture(Theme.TEX.markers)
  cd:SetTexCoord(Theme.atlasCoords(Theme.ATLAS.disc))
  Theme.color(cd, Theme.C.ink)
  local cx = close:CreateTexture(nil, "ARTWORK")
  cx:SetPoint("CENTER", close, "CENTER")
  cx:SetSize(18, 18)
  cx:SetTexture(Theme.TEX.markers)
  cx:SetTexCoord(Theme.atlasCoords(Theme.ATLAS.close))
  Theme.color(cx, Theme.C.parchment)
  close:SetScript("OnClick", function() f:Hide() end)
  close:SetScript("OnEnter", function(self)
    if GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(Frame.TEXT.closeTip, 1, 1, 1)
      GameTooltip:Show()
    end
  end)
  close:SetScript("OnLeave", Theme.hideTooltip)
  J.close = close

  buildTabs(f)
  buildSubTabs(f)
  buildSettings(f)

  f:SetScript("OnShow", safe(function(self)
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("UI_SCALE_CHANGED")
    self:RegisterEvent("DISPLAY_SIZE_CHANGED")
    Frame.applyScale()
    local P = Journal.Pages
    applyPage((P and P.initial()) or Frame.HOME)
    local S = Journal.Sound
    if S then
      S.play("open")
      S.animateOpen(self)
    end
  end))
  f:SetScript("OnHide", function(self)
    self:UnregisterEvent("PLAYER_REGEN_DISABLED")
    self:UnregisterEvent("UI_SCALE_CHANGED")
    self:UnregisterEvent("DISPLAY_SIZE_CHANGED")
    J.pendingScale = nil
    local P = Journal.Pages
    if P then pcall(P.hide) end
    releaseHome()
    local S = Journal.Sound
    if S then
      pcall(S.stopAnimation, self)
      pcall(S.play, "close")
    end
  end)
  f:SetScript("OnEvent", function(self, event)
    if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
      Frame.applyScale()
    elseif event == "PLAYER_REGEN_DISABLED" then
      local P = Journal.Pages
      if P then pcall(P.hide) end
      self:Hide()
    end
  end)
  View.onChange(function(status, model, stale)
    if f:IsShown() then Frame.render(status, model, stale) end
  end)

  if type(UISpecialFrames) == "table" then
    local present = false
    for _, n in ipairs(UISpecialFrames) do if n == Frame.NAME then present = true end end
    if not present then table.insert(UISpecialFrames, Frame.NAME) end
  end
  return f
end

local function showMessage(text)
  if text then
    J.msg.text:SetText(text)
    J.msg:Show()
  else
    J.msg:Hide()
  end
end

local function chapterIndexAt(p)
  local model = J.model
  if not model or not model.chapters or #model.chapters == 0 then return nil end
  if J.sel.chapter then return J.sel.chapter end
  if p == huge or not p then return #model.chapters end
  local t = View.timeAt(model, View.fromAxis(model, p))
  local i = t and View.chapterAt(model, t)
  if type(i) ~= "number" or not model.chapters[i] then return #model.chapters end
  return i
end

function Frame.isTotal()
  return J.mapMode == "continent" and not (J.sel.chapter or J.sel.zone)
end

local function zoneChapterIndex(zone)
  local chapters = J.model and J.model.chapters
  if type(chapters) ~= "table" or type(zone) ~= "number" then return nil end
  for i = #chapters, 1, -1 do
    if chapters[i] and chapters[i].zoneID == zone then return i end
  end
  return nil
end

local function zoneCard(zone)
  local ci = zoneChapterIndex(zone)
  if ci then return J.model.chapters[ci] end
  J.zoneCards = J.zoneCards or {}
  local c = J.zoneCards[zone]
  if c then return c end
  local name = View.mapName(zone)
  c = { unexplored = true, index = "u" .. tostring(zone), zoneID = zone, zoneName = name or Frame.TEXT.unknownArea }
  if name then J.zoneCards[zone] = c end
  return c
end

local function cardFor(p)
  local model = J.model
  if not model then return nil end
  if type(J.sel.zone) == "number" and not J.sel.chapter then return zoneCard(J.sel.zone) end
  if (p == huge or p == nil) and model.total and Frame.isTotal() then return model.total end
  local ci = chapterIndexAt(p)
  return ci and model.chapters[ci]
end

function Frame.levelHintText(level) return Frame.TEXT("levelHint", int(level)) end

function Frame.showLevelHint(level)
  if not J.hint then return end
  J.hint.text:SetText(Frame.levelHintText(level))
  J.hintLeft = Frame.HINT_SECONDS
  J.hint:SetAlpha(1)
  J.hint:Show()
end

function Frame.hideLevelHint()
  J.hintLeft = nil
  if J.hint then J.hint:Hide() end
end

local function fadeLevelHint(dt)
  if not J.hintLeft then return end
  J.hintLeft = J.hintLeft - (dt or 0)
  if J.hintLeft <= 0 then
    Frame.hideLevelHint()
  elseif J.hintLeft < Frame.HINT_FADE then
    J.hint:SetAlpha(J.hintLeft / Frame.HINT_FADE)
  end
end

local function updateTimeline()
  local st, model = J.st, J.model
  local info = { when = "", played = "" }
  if model then
    local p = View.fromAxis(model, st.p)
    local t = View.timeAt(model, p)
    if t then
      local w = View.formatWhen(model, t)
      local d = safeDate(Frame.TEXT.dateFull, t)
      info.when = (w or "") .. (d ~= "" and (" · " .. d) or "")
    end
    info.played = Frame.TEXT("playedSuffix", View.formatPlayed(p))
  end
  Playback.show(J.pb, st, info)
end

local function updateTitle(scene)
  local model = J.model
  local cont = scene.contID and View.mapName(scene.contID)
  local c = scene.chapter and model.chapters[scene.chapter]
  if scene.mode == "zone" then
    J.titleLabel:SetText(c and (cont or Frame.TEXT.overview) or Frame.TEXT.journeyUpper)
    J.titleName:SetText(View.mapName(scene.zoneID) or (c and c.zoneName) or Frame.TEXT.overview)
  elseif c then
    J.titleLabel:SetText(cont or Frame.TEXT.overview)
    J.titleName:SetText(c.zoneName or c.title or "")
  else
    J.titleLabel:SetText(cont and Frame.TEXT.journeyUpper or "")
    J.titleName:SetText(cont or (scene.mapID and View.mapName(scene.mapID)) or Frame.TEXT.overview)
  end
  J.titleStats:SetText(model.header and model.header.stats or "")
  -- 28 pt title: shrinks down to 18 pt before it would be cut; full text on hover when it had to shrink
  local size = Journal.Widgets.fitLine(J.titleName, Frame.TITLE_W, 18)
  local cut = size and (size < (J.titleName.fitBase or size) or (tonumber(J.titleName:GetStringWidth()) or 0) > Frame.TITLE_W)
  J.titleNameFull = cut and J.titleName:GetText() or nil
  if J.titleNameHover then J.titleNameHover:EnableMouse(cut and true or false) end
  Frame.anchorStats()
end

function Frame.anchorStats()
  local tl, ts = J.titleLabel, J.titleStats
  if not (tl and ts) then return end
  local label = tl:GetText()
  ts:ClearAllPoints()
  local avail = Frame.TITLE_W
  if type(label) == "string" and label ~= "" then
    ts:SetPoint("LEFT", tl, "RIGHT", 10, 0)
    avail = avail - (tonumber(tl:GetStringWidth()) or 0) - 10
  else
    ts:SetPoint("TOPLEFT", tl, "TOPLEFT", 0, 0)
  end
  Journal.Widgets.fitLine(ts, math.max(avail, 60), 10)
end

Frame.CONT_MAX = 4
local function updateContinents(scene)
  local model = J.model
  local list = model.continents or {}
  local show = scene.mode == "continent" and not (J.sel.chapter or J.sel.zone) and #list > 1 and not scene.empty
  local t = J.contToggle
  if show then
    local items = {}
    for _, c in ipairs(list) do
      if #items >= Frame.CONT_MAX then break end
      items[#items + 1] = { key = c.id, label = View.mapName(c.id) or Frame.TEXT("mapN", int(c.id)) }
    end
    t:SetItems(items)
    t:SetValue(scene.contID)
  end
  t.frame:SetShown(show)
end

function updateMode(scene)
  local t = J.modeToggle
  local show = false
  if not scene.empty or scene.mode == "zone" then
    if scene.mode == "zone" then
      show = true
    elseif J.mapMode == "continent" and View.zoneFor(J.model, J.sel) and View.zoneArt(View.zoneFor(J.model, J.sel)) then
      show = true
    end
  end
  local zone = scene.mode == "zone"
  t:SetValue(zone and "zone" or "continent")
  J.modeLabel, J.modeButton = t.buttons[zone and 1 or 2], t.buttons[zone and 2 or 1]
  t.frame:SetShown(show)
  for _, b in ipairs(t.buttons) do b:SetShown(show) end
  if J.killBox then
    J.killBox:SetShown(not scene.empty and scene.mode ~= "continent")
    J.killBox:SetChecked(Frame.killsShown(), true)
  end
end

function Frame.killsShown()
  deps()
  return View.peek("showKills") ~= false
end

function Frame.setShowKills(on)
  deps()
  on = on and true or false
  View.set("showKills", on)
  if J.killBox then J.killBox:SetChecked(on, true) end
  if J.model then Frame.refresh(true) end
  return on
end
function Frame.setMapColor(value)
  deps()
  if value ~= "original" then value = "sepia" end
  View.set("mapColor", value)
  Frame.refresh(true)
  local P = Journal.Pages
  if P and J.page ~= Frame.HOME and P.isShown() then pcall(P.refresh) end
  return value
end

local function width(o) return tonumber(o:GetWidth()) or 0 end

function Frame.layoutControls()
  local ctrl = J.ctrl
  if not ctrl then return 0 end
  local showBack = (J.sel.chapter or J.sel.zone or (J.map and Map.zoomed(J.map))) and J.model ~= nil and true or false
  J.back:SetShown(showBack)
  if J.leftHead then J.leftHead.left:SetShown(not showBack) end
  local n = showBack and 1 or 0
  if J.contToggle.frame:IsShown() then
    for _, b in ipairs(J.contToggle.buttons) do if b:IsShown() then n = n + 1 end end
  end
  local mode = J.modeToggle
  local lx = -3
  if mode.frame:IsShown() then
    n = n + 2
    lx = lx + width(mode.frame) + 18
  end
  local kb = J.killBox
  if kb and kb:IsShown() then
    kb:ClearAllPoints()
    kb:SetPoint("LEFT", ctrl, "LEFT", lx, 0)
  end
  J.contToggle.frame:ClearAllPoints()
  J.contToggle.frame:SetPoint("LEFT", ctrl, "LEFT", lx, 0)
  Frame.updateSubEsc()
  return n
end
Frame.layoutTitle = Frame.layoutControls

function Frame.obstacles()
  return {}
end

function Frame.rightClick()
  local scene = J.scene
  if scene and scene.mode == "zone" then
    if J.map and Map.resetView(J.map) then return "unzoom" end
    Frame.toggleMapMode()
    return "continent"
  end
  return Frame.back() and "back" or nil
end

function Frame.back()
  if J.sel.chapter or J.sel.zone then
    Frame.select(nil)
    return true
  end
  if J.map and Map.resetView(J.map) then return true end
  return false
end

function Frame.render(status, model, stale)
  if not J.frame or J.page ~= Frame.HOME then return end
  J.staleHint:SetShown(stale and true or false)
  if status ~= "ready" or not model then
    J.model, J.scene = nil, nil
    J.map.viewport:Hide()
    J.card:Hide()
    J.pb.frame:Hide()
    J.titleLabel:SetText("")
    J.titleName:SetText("")
    J.titleStats:SetText("")
    J.back:Hide()
    J.leftHead.left:Show()
    J.modeToggle.frame:Hide()
    J.contToggle.frame:Hide()
    J.titleBox:Hide()
    J.ctrl:Hide()
    if J.worldLink then J.worldLink:Hide() end
    J.noteBox:Hide()
    Playback.setGridShown(J.pb, false)
    if J.stations then Stations.setShown(J.stations, false) end
    J.headLine:SetText("")
    J.headDay:SetText("")
    J.openWaited = true
    showMessage(Frame.TEXT[status] or Frame.TEXT.loading)
    return
  end
  showMessage(nil)
  local hadModel = J.model ~= nil
  if J.model ~= model then
    if J.sel.chapter and not (model.chapters and model.chapters[J.sel.chapter]) then J.sel = {} end
  end
  J.model = model
  J.titleBox:Show()
  J.ctrl:Show()
  if J.worldLink then J.worldLink:Show() end
  J.noteBox:Show()
  J.map.viewport:Show()
  J.pb.frame:Show()
  local h = model.header or {}
  J.headLine:SetText(h.line or "")
  J.headDay:SetText(h.day and Frame.TEXT("dayUpper", int(h.day)) or "")
  local t0 = Frame.clock()
  Frame.refresh(hadModel)
  if t0 then
    local t1 = Frame.clock() or t0
    local perf = J.perf or {}
    J.perf = perf
    perf.render = t1 - t0
    if J.openT0 then
      perf.open, perf.build, perf.waited = t1 - J.openT0, J.openBuild or 0, J.openWaited
      J.openT0 = nil
    end
  end
end

function Frame.refresh(keepPlay)
  local model = J.model
  if not J.frame or not model then return end
  local scene = View.scene(model, J.sel, { mode = J.mapMode, whole = J.contWhole })
  J.scene = scene
  local art, aspect, outlines, clip
  if scene.mode == "zone" then
    art, clip = scene.art, scene.clip
  elseif scene.mode == "continent" then
    art = View.mapArt(scene.contID)
    if not art then outlines = View.zoneOutlines(model, scene.contID, Map.OUTLINES_MAX) end
  else
    aspect = View.mapAspect(scene.mapID)
  end
  J.st.speed = View.peek("speed") or J.st.speed
  local wasPlaying, oldP = J.st.playing, J.st.p
  local function axis(p) return View.toAxis(model, p) end
  local r0, r1 = axis(scene.range[1]), axis(scene.range[2])
  Playback.setRange(J.st, r0, r1)
  if keepPlay then Playback.resume(J.st, oldP, wasPlaying) end
  Playback.stopTicking(J.pb)
  if J.axisModel ~= model then
    J.axisModel, J.axisLevels = model, {}
    for i, l in ipairs(model.timeline and model.timeline.levels or {}) do
      J.axisLevels[i] = { p = axis(l.p), level = l.level, t = l.t }
    end
  end
  Playback.setTicks(J.pb, Playback.ticks(J.axisLevels, r0, r1, J.pb.trackW))
  Playback.setLevelMarks(J.pb, Playback.levelFracs(J.axisLevels, r0, r1))
  local total = Frame.isTotal()
  local ci = chapterIndexAt(huge)
  local selected = J.sel.chapter or ((not total) and ci or nil)
  if type(J.sel.zone) == "number" and not J.sel.chapter then selected = zoneChapterIndex(J.sel.zone) end
  Playback.setChapters(J.pb, model.chapters, selected, nil, false)
  Playback.setGridShown(J.pb, not total)
  Frame.updateStations(total)
  Frame.setCard(cardFor(J.st.playing and Playback.mapP(J.st) or huge))
  updateTitle(scene)
  updateContinents(scene)
  updateMode(scene)
  scene.pins = Frame.notePins(scene)
  J.stats = Map.render(J.map, scene, { art = art, aspect = aspect, outlines = outlines, clip = clip, axis = axis,
    color = View.peek("mapColor"), showKills = Frame.killsShown(), reduceMotion = View.peek("reduceMotion"), obstacles = Frame.obstacles(),
    keepView = keepPlay, when = function(t) return View.formatWhen(model, t) end })
  Frame.placeLower()
  Frame.layoutControls()
  Frame.updateSubTabs()
  updateTimeline()
  if J.st.playing then
    Map.setProgress(J.map, Playback.mapP(J.st))
    Playback.startTicking(J.pb)
  end
end

function Frame.notePins(scene)
  local N = Journal.Notes
  local out = {}
  if not (N and N.onMap and scene and type(scene.project) == "function") then return out end
  local okList, list = pcall(N.onMap)
  if not okList or type(list) ~= "table" then return out end
  local S = ns.Sanitize
  for _, n in ipairs(list) do
    local ok, vx, vy = pcall(scene.project, n.mapID, n.x, n.y)
    if ok and type(vx) == "number" and type(vy) == "number" and vx == vx and vy == vy then
      out[#out + 1] = { id = n.id, vx = vx, vy = vy, title = (S and S.display(n.title, 120)) or Frame.TEXT.noteUntitled }
    end
  end
  local V = Journal.Vorhaben
  if V and type(V.mapPins) == "function" then
    local okV, pins = pcall(V.mapPins, scene)
    if okV and type(pins) == "table" then
      for _, e in ipairs(pins) do out[#out + 1] = e end
    end
  end
  return out
end

function Frame.openNote(id)
  if not Frame.showPage("notizen") then return false end
  local P = Journal.NotizenPage
  if P and P.Open then return P:Open(id) end
  return false
end

local function notesChanged()
  if J.frame and J.frame:IsShown() and J.page == Frame.HOME and J.model then pcall(Frame.refresh, true) end
end
if Journal.Notes and Journal.Notes.onChange then Journal.Notes.onChange(notesChanged) end

function Frame.select(sel)
  J.sel = sel or {}
  if J.sel.chapter or J.sel.zone then J.mapMode = "zone" end
  J.contWhole = J.mapMode == "continent" and J.sel.continent ~= nil
  Frame.refresh()
end

function Frame.selectTotal()
  J.sel = {}
  if Frame.isTotal() then
    J.mapMode = "zone"
  else
    J.mapMode = "continent"
  end
  J.contWhole = false
  Frame.refresh()
  return Frame.isTotal()
end

function Frame.toggleMapMode()
  if J.mapMode == "zone" then
    J.mapMode = "continent"
    J.sel = J.sel.continent and J.sel or {}
    J.contWhole = true
  else
    J.mapMode = "zone"
    J.contWhole = false
    if J.sel.continent then J.sel = {} end
  end
  Frame.refresh()
  return J.mapMode
end

-- Zone under a point of the continent map if clickable there (continent view without chapter/zone, like Blizzard's world
-- map: any zone, even without travel traces). -> { id, name, mapID = continent } or nil
function Frame.hoverZone(vx, vy)
  local scene, model = J.scene, J.model
  if not scene or not model or scene.mode ~= "continent" or not scene.contID then return nil end
  if J.sel.chapter or J.sel.zone then return nil end
  local z = View.zoneInfoAt(scene.contID, vx, vy)
  if not z then return nil end
  z.mapID = scene.contID
  return z
end

function Frame.pickPoint(vx, vy)
  local V = Journal.Vorhaben
  if V and type(V.pickActive) == "function" and V.pickActive() then
    local ok, used = pcall(V.pickAt, vx, vy, J.scene)
    if ok and used then return true end
  end
  local z = Frame.hoverZone(vx, vy)
  if not z then return false end
  Frame.select({ zone = z.id })
  return true
end

-- Zoom switch (Map.zoomSwitchWheel): target for the switch continent <-> zone. dir "in": clickable zone under the continent
-- point (as hover/click) with zone art and rect on the continent; "out": the shown zone on its continent.
-- -> { zone, cont, a, b, c, d, artW, artH } or nil (no switch)
function Frame.zoomTarget(dir, vx, vy)
  local scene, G = J.scene, Journal.Geo
  if not scene or not J.model or not (G and G.affine) then return nil end
  local zone, cont, art
  if dir == "in" then
    local z = Frame.hoverZone(vx, vy)
    if not z then return nil end
    zone, cont = z.id, scene.contID
    art = View.zoneArt(zone)
    if not art then return nil end
  elseif dir == "out" then
    if scene.mode ~= "zone" then return nil end
    zone, cont = scene.zoneID, scene.contID
  else
    return nil
  end
  if not zone or not cont or zone == cont then return nil end
  local a, b, c, d = G.affine(zone, cont)
  if not a then return nil end
  return { zone = zone, cont = cont, a = a, b = b, c = c, d = d, artW = art and art.w, artH = art and art.h }
end

function Frame.zoomApply(dir, target)
  if not J.model or type(target) ~= "table" then return false end
  local st = J.st
  local wasPlaying, oldP = st.playing, st.p
  local paused = not wasPlaying and oldP and st.p1 and oldP < st.p1
  if dir == "in" then
    J.sel, J.mapMode, J.contWhole = { zone = target.zone }, "zone", false
  else
    local first = View.viewFor(J.model, {})
    J.sel = (first and first.continent == target.cont) and {} or { continent = target.cont }
    J.mapMode, J.contWhole = "continent", true
  end
  Frame.refresh(true)
  if paused then
    st.p = max(st.p0, math.min(oldP, st.p1))
    Map.setProgress(J.map, Playback.mapP(st))
    local card = cardFor(Playback.mapP(st))
    if card and J.card.shown ~= card.index then Frame.setCard(card) end
    updateTimeline()
  end
  local scene = J.scene
  if not scene then return false end
  if dir == "in" then return scene.mode == "zone" and scene.zoneID == target.zone end
  return scene.mode == "continent" and scene.contID == target.cont
end

-- Index for the longest day (Index.get: without state it builds in the background, onReady redraws). fromReady: call from
-- onReady -> noRebuild, otherwise a changed state would start the next job (cycle).
local function stationIndex(fromReady)
  local I = Journal.Index
  if not (I and I.get) then return nil end
  local ok, index = pcall(I.get, { noRebuild = fromReady or nil })
  return ok and type(index) == "table" and index or nil
end

function Frame.updateStations(on, fromReady)
  local sb = J.stations
  if not (sb and Stations) then return false end
  if not (on and J.model) then
    Stations.setShown(sb, false)
    return false
  end
  local model = J.model
  if J.stationsFor ~= model then
    local index = stationIndex(fromReady)
    J.stationList = Stations.build(model, index, {
      when = function(t) return View.formatWhen(model, t) end,
      played = function(sec) return View.formatPlayed(sec) end,
      mapName = function(id) return View.mapName(id) end,
    })
    J.stationsFor = model
    if J.stationSel then
      local keep = false
      for _, s in ipairs(J.stationList) do if s.key == J.stationSel then keep = true end end
      if not keep then J.stationSel = nil end
    end
  end
  Stations.set(sb, J.stationList, J.stationSel)
  Stations.setShown(sb, true)
  return true
end

function Frame.placeLower()
  local notes = J.map and J.map.noteList and #J.map.noteList or 0
  local G, SA, free = Frame.TIMELINE.GRID, Frame.STATIONS, Frame.LOWER_FREE
  local top = notes > 0 and G.y or Frame.NOTE.y
  if J.pb then Playback.placeGrid(J.pb, G.x, top, notes > 0 and G.rows or free.gridRows) end
  if J.stations and Stations then Stations.place(J.stations, J.over, SA.x, top, notes > 0 and SA.rows or free.stationRows) end
  return top
end

function Frame.fracAt(t)
  local model, st = J.model, J.st
  if not (model and st) or type(t) ~= "number" or t ~= t then return nil end
  local p = View.playedAt(model, t)
  if type(p) ~= "number" or p ~= p then return nil end
  local q = View.toAxis(model, p)
  if type(q) ~= "number" or q ~= q then return nil end
  if st.p1 <= st.p0 then return 1 end
  return max(0, math.min(1, (q - st.p0) / (st.p1 - st.p0)))
end

function Frame.pickStation(s)
  if type(s) ~= "table" or not J.model then return false end
  local frac = Frame.fracAt(s.t)
  if not frac then return false end
  J.stationSel = s.key
  if J.stations then Stations.set(J.stations, J.stationList or {}, J.stationSel) end
  Frame.seek(frac)
  if Journal.Sound then pcall(Journal.Sound.play, "page") end
  return true
end

function Frame.worldMapTarget()
  local s = J.scene
  if not s then return nil end
  if s.mode == "zone" then return s.zoneID end
  if s.mode == "continent" then return s.contID end
  return s.mapID
end

function Frame.openWorldMap()
  local WL = Journal.WorldLayer
  if not WL then return false end
  local ok, why = WL.openMap(Frame.worldMapTarget())
  if ok and J.frame and J.frame:IsShown() then J.frame:Hide() end
  return ok, why
end

function Frame.togglePlay()
  if not J.model then return end
  local playing = Playback.toggle(J.st)
  if playing then
    Playback.startTicking(J.pb)
  else
    Playback.stopTicking(J.pb)
    Frame.hideLevelHint()
  end
  Map.setProgress(J.map, Playback.mapP(J.st))
  local c = cardFor(Playback.mapP(J.st))
  if c and J.card.shown ~= c.index then Frame.setCard(c) end
  updateTimeline()
end

function Frame.setSpeed(speed)
  if not Playback.SPEED_NAMES[speed] then return false end
  J.st.speed = speed
  View.set("speed", speed)
  if J.model then updateTimeline() end
  return true
end

function Frame.cycleSpeed()
  return Frame.setSpeed(Playback.nextSpeed(J.st.speed))
end

function Frame.seek(frac)
  if not J.model then return end
  Playback.seek(J.st, frac)
  Map.setProgress(J.map, Playback.mapP(J.st))
  local c = cardFor(Playback.mapP(J.st))
  if c and J.card.shown ~= c.index then Frame.setCard(c) end
  updateTimeline()
end

-- Scrubbing on the timeline (dragging the mouse): a running playback pauses for the duration of the drag; position, map and
-- player arrow follow via Frame.seek. After release it continues in the previous state (it played: plays from the new spot;
-- it was paused: stays paused). At the end of the span it stops.
function Frame.scrubStart()
  if not J.model or J.scrub then return false end
  J.scrub = { wasPlaying = J.st.playing and true or false }
  if J.scrub.wasPlaying then
    J.st.playing = false
    Playback.stopTicking(J.pb)
    Frame.hideLevelHint()
  end
  return true
end

function Frame.scrubEnd(aborted)
  local sc = J.scrub
  J.scrub = nil
  if not sc or aborted or not J.model then return false end
  if sc.wasPlaying and J.st.p < J.st.p1 then
    J.st.playing = true
    Playback.startTicking(J.pb)
  end
  Map.setProgress(J.map, Playback.mapP(J.st))
  updateTimeline()
  return J.st.playing
end

local textClock = 0
function Frame.tick(dt)
  local st = J.st
  if not st.playing then
    Playback.stopTicking(J.pb)
    Frame.hideLevelHint()
    return
  end
  local before = st.p
  Playback.step(st, dt)
  local p = Playback.mapP(st)
  Map.setProgress(J.map, p)
  local hit = Playback.crossed(J.axisLevels, before, st.p)
  if hit then Frame.showLevelHint(hit.level) end
  fadeLevelHint(dt)
  textClock = textClock + (dt or 0)
  if textClock >= 0.1 or not st.playing then
    textClock = 0
    local c = cardFor(p)
    if c and J.card.shown ~= c.index then Frame.setCard(c) end
    updateTimeline()
  end
  if not st.playing then
    Playback.stopTicking(J.pb)
    Frame.hideLevelHint()
  end
end
