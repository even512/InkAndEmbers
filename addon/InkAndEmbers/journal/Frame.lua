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
Frame.SUBTAB = { x0 = 56, gap = 6, edge = 40, under = 66, out = 14, pull = 9, hover = 3, tip = 20, pad = 11, minW = 58, size = 17,
  dim = 0.62, body0 = 0.02, body1 = 0.32, tip0 = 0.90, tip1 = 0.996, trim = 8, sx = 1, sy = 2, sa = 0.35 }
-- The ribbons hang only on the LEFT page and end before the fold (Frame.W / 2) with a small gap (foldGap), however many there
-- are and in whatever language: if they do not fit, updateSubTabs tries these steps (scale of the font, padding, gap, minimum
-- width) in turn and takes the first that fits; the last step is the tightest.
Frame.SUBTAB.foldGap = 18
Frame.SUBTAB.fit = {
  { scale = 1, pad = 11, gap = 6, minW = 58 },
  { scale = 1, pad = 7, gap = 4, minW = 44 },
  { scale = 0.9, pad = 6, gap = 4, minW = 38 },
  { scale = 0.82, pad = 5, gap = 3, minW = 34 },
  { scale = 0.74, pad = 4, gap = 3, minW = 30 },
}
Frame.SUBTABS_OUT = Frame.SUBTAB.out + Frame.SUBTAB.pull + Frame.SUBTAB.hover
-- most sub-bookmarks of one tab: Chronik has five (Steckbrief, Tagebuch, Weggefährten, Meilensteine, Vermächtnis)
Frame.SUBTABS_MAX = 5
-- Journey subpages from left to right: total journey · chapter journey (= zone map, key "karte", the default view on open
-- even though it sits last). The To Do moved to the tab Pläne (I12, pages/Plaene.lua). The other tabs register theirs via
-- Pages.subs. Label and tooltip come from Frame.TEXT when read (sub_<key>, subTip_<key>; the language is only known at ADDON_LOADED).
local function subtabDef(key)
  return setmetatable({ key = key }, { __index = function(_, k)
    if k == "label" then return Frame.TEXT["sub_" .. key] end
    if k == "tip" then return { Frame.TEXT["sub_" .. key], Frame.TEXT["subTip_" .. key] } end
    return nil
  end })
end
-- K4 (10.11.): "Inhalt" first (default view, key "karte"), then the total journey; I15: then the heat map (journal/HeatmapView.lua)
Frame.SUBTABS_REISE = { subtabDef("karte"), subtabDef("gesamt"), subtabDef("heatmap") }
Frame.SUBTABS_REISE[1].art = "contents"
-- K4: the sub-bookmark "Inhalt" is a painted hanging band (Media/SubContentsDE|EN, scripts/render-media.mjs SUB_CONTENTS) with the
-- word embroidered: no label from the code (the tooltip stays). Texture 256 x 512 (band 256 x 441 at the top), shown 66 px wide
-- (0.0615 px per source pixel); top = how far its top sits above the bottom of the cover, so the page edge (24 px above it) cuts
-- just above the word; the band ends a little below the other ribbons and the tassel hangs lower. out = what hangs below the cover
-- (for the screen clamp).
-- dim / hover: the gold band is dimmed much less than the cloth ribbons (playtest 10.11.: inactive it must stay golden)
Frame.SUB_BAND = { w = 66, h = 132, top = 53, content = 114, page = 24, dim = 0.82, hover = 0.93 }
Frame.SUB_BAND.out = Frame.SUB_BAND.content - Frame.SUB_BAND.top + Frame.SUBTAB.pull
-- Fixed small deviation per tab id (no randomness): dx = sticks out +/- px (max 3), dy = offset down px (max 2), deg = tilt
-- (positive: counter-clockwise, max 2). Neighbours keep room: ribbon gap 12 px minus offset difference (max 4) minus both tilt
-- swings (each max 2.4) stays above 3 px.
Frame.TAB_WOBBLE = {
  reise = { dx = 2, dy = 1, deg = 1.5 },
  chronik = { dx = -2, dy = -1, deg = -1.0 },
  dungeons = { dx = 1, dy = 0, deg = 1.2 },
  kampf = { dx = 3, dy = 2, deg = 2.0 },
  quests = { dx = -3, dy = -1, deg = -1.5 },
  plaene = { dx = -1, dy = 0, deg = -1.2 },
  schaetze = { dx = 2, dy = 1, deg = 1.0 },
  handwerk = { dx = -1, dy = 0, deg = 1.4 },
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
  sub_karte = "Inhalt",
  subTip_karte = "Inhaltsverzeichnis der Reise: Bände, Akte und Kapitel mit der Zonenkarte (Standardansicht)",
  sub_heatmap = "Heatmap",
  subTip_heatmap = "Wo Ihr wie lange wart und wo Ihr gestorben seid: als Glut auf der Zonenkarte",
  -- K2: acts as the first level, their chapters as the second
  actUpper = "AKT %s",
  actStory = "%s Kapitel: %s",
  headAct = "Akt %s",
  -- K4: right page head of a chosen act/chapter ("Akt I · Stufe 1–13 · 17 Std. 52 Min. · 39 Quests")
  headQuests = "%s Quests",
  headChapters = "%s Kapitel",
  row_played = "Spielzeit",
  row_levels = "Stufe",
  row_kills = "Kills",
  row_deaths = "Tode",
  row_quests = "Quests",
  row_moments = "Momente",
  -- zone progress (change "zone-abgeschlossen", journal/model/ZoneProgress.lua)
  row_zone = "Zone erledigt",
  row_zonesDone = "Zonen abgeschlossen",
  zonePct = "%s %% (%s/%s)",
  zoneComplete = "100 % · abgeschlossen",
  zonePartial = "%s …",
  zonesDoneValue = "%s / %s",
  zonesTipTitle = "Abgeschlossene Zonen",
  zonesTipLine = "In %s von %s Zonen sind alle zählbaren Quests erledigt.",
  zonesTipRule = "Gezählt werden Zonen mit mindestens %s zählbaren Quests.",
  tabTip_reise = "Karte mit Eurer Route, als ganze Reise und Akt für Akt.",
  tabTip_chronik = "Steckbrief, Stufenfluss, Tagebuch, Weggefährten samt Lagerfeuer-Gästen und Meilensteine.",
  tabTip_chronikRetail = "Steckbrief, Stufenfluss, Tagebuch und Weggefährten.",
  tabTip_dungeons = "Jeder Dungeon-Durchlauf mit Bossen, Gruppe und Beute, dazu alle Dungeon-Quests mit ihren Ketten.",
  tabTip_dungeonsRetail = "Jeder Dungeon-Durchlauf mit Bossen, Gruppe und Beute.",
  tabTip_kampf = "Kills, Gegner, knappe Siege und Tode.",
  tabTip_quests = "Abgeschlossene Quests mit Questtext und Belohnung, offene Quests der Zone und die Zonenübersicht.",
  tabTip_questsRetail = "Abgeschlossene Quests mit Questtext und Belohnung und die offenen Quests der Zone.",
  tabTip_plaene = "Eure To Dos und der Lehrplan.",
  tabTip_plaeneRetail = "Eure To Dos.",
  tabTip_notizen = "Eure eigenen Notizen, gern mit einem Pin auf der Karte.",
  tabTip_schaetze = "Gold im Beutel, Haushaltsbuch, Goldfluss und Ausrüstung.",
  tabTip_handwerk = "Berufe mit Skillkurve, Meilensteinen und Rezepten, dazu die Bilanz des Sammelns und Herstellens.",
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
  rightTip = "Rechtsklick auf die Karte: erst Zoom aufheben, dann Kontinent; in einem Akt oder Kapitel eine Ebene zurück",
  zone = "Zone",
  zoneTip = "Aufgedeckte Zonenkarte mit der Route",
  colors = "Karten in Originalfarben",
  kills = "Kämpfe zeigen",
  killsTip = "Erlegte Gegner (gekreuzte Schwerter) auf der Karte zeigen oder ausblenden",
  reveal = "Karte aufdecken",
  icons = "Symbole zeigen",
  iconsTip = "Ereignis-Symbole auf der Kontinentkarte (Tode, Stufen, Flugpunkte, Ruhesteine, Instanzen, Momente, Notizen) zeigen oder ausblenden; Route und Pfeil bleiben",
  revealTip = "Ganze Zone zeigen, nicht nur selbst erkundete Gebiete",
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

local Theme, View, Map, Playback, Stations, FlightBook

-- mapMode: "zone" (default: uncovered zone map) | "continent" (continent view with route). contWhole: the continent view shows
-- the WHOLE continent map (button "Continent", right click, continent choice); otherwise (fallback without zone art) the
-- automatic zoom on the route or chapter stays.
local J = { sel = {}, st = nil, page = Frame.HOME, mapMode = "zone", contWhole = false }
Frame.state = J

local updateMode

local function deps()
  Theme, View, Map, Playback, Stations = Journal.Theme, Journal.View, Journal.Map, Journal.Playback, Journal.Stations
  FlightBook = Journal.FlightBook
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
  local ok, s = pcall(date, fmt, floor(t)) -- whole seconds: a scrubbed position is fractional (strict date() in Lua 5.3)
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
  -- "Zone erledigt" (change "zone-abgeschlossen"): an own row under the values, hidden unless there is a share (Frame.updateZoneRow);
  -- while it shows, all rows shrink to Frame.ROW_H_TIGHT so the table keeps its height (margin notes and grid stay in place)
  do
    local zr = CreateFrame("Frame", nil, card)
    zr:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, 0)
    zr:SetSize(Frame.TABLE_W, Frame.ROW_H)
    local l = Theme.fontString(zr, "text", S.m or 14, Theme.C.sepia, "OVERLAY", "LEFT")
    l:SetPoint("LEFT", zr, "LEFT", 0, 0)
    local v = Theme.fontString(zr, "text", S.m or 14, Theme.C.ink, "OVERLAY", "RIGHT")
    v:SetPoint("RIGHT", zr, "RIGHT", 0, 0)
    v:SetWidth(Frame.TABLE_W - 120)
    v:SetWordWrap(false)
    local ln = zr:CreateTexture(nil, "ARTWORK")
    ln:SetColorTexture(Theme.C.sepia[1], Theme.C.sepia[2], Theme.C.sepia[3], 0.2)
    ln:SetPoint("BOTTOMLEFT", zr, "BOTTOMLEFT", 0, 0)
    ln:SetSize(Frame.TABLE_W, 1)
    -- stamp at 100 %: the medal "Zonenkenner" (motif + ring of the earned tier) left of the value
    local motif = zr:CreateTexture(nil, "ARTWORK")
    local ring = zr:CreateTexture(nil, "OVERLAY")
    ring:SetSize(Frame.ZONE_STAMP, Frame.ZONE_STAMP)
    motif:SetPoint("CENTER", ring, "CENTER", 0, 0)
    motif:Hide()
    ring:Hide()
    zr:EnableMouse(true)
    zr:SetScript("OnEnter", function(self)
      local lines, colors = Frame.zoneTip(card.zoneInfo)
      if lines and Journal.Widgets then Journal.Widgets.tip(self, lines, colors) end
    end)
    zr:SetScript("OnLeave", function(self) if Journal.Widgets then Journal.Widgets.hideTip(self) end end)
    zr:Hide()
    card.zoneRow = { frame = zr, label = l, value = v, line = ln, motif = motif, ring = ring }
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
  -- total journey: the page turner of the stations sits in the same spot (P3: fewer rows -> sooner a second page)
  local sb = J.stations
  if reserve == 0 and sb and sb.nav and sb.frame:IsShown() and sb.nav.frame:IsShown() then
    local nw = tonumber(sb.nav.frame:GetWidth()) or 54
    local rw = strWidth(card.measure, sb.range and sb.range:GetText() or "")
    if rw <= 0 then rw = 90 end
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
  if J.tocOn then -- K4: the table of contents holds the left page (its figures sit in the right head and the tooltips)
    card:Hide()
    return
  end
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
    card.chapter = c
    Frame.updateZoneRow()
    card:Show()
    return
  end
  card.label:SetText(c.total and Frame.TEXT.totalLabel
    or (c.isAct and Frame.TEXT("actUpper", c.roman or "")) or Frame.TEXT("chapterUpper", c.roman or ""))
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
  card.chapter = c
  Frame.updateZoneRow()
  card:Show()
end

local function tabAvailable(id)
  local P = Journal.Pages
  -- another character's book (read only) leaves out what belongs to the logged-in character (Pages.guestAllows)
  if P and P.guestAllows and not P.guestAllows(id) then return false end
  if P and P.tabHidden and P.tabHidden(id) then return false end -- a client without this tab (Handwerk in Retail)
  if id == Frame.HOME then return true end
  return P ~= nil and P.isAvailable(id) == true
end

-- the open guest book ({ guid, name, lastSeen }) or nil in the own book
local function guestNow()
  local P = Journal.Pages
  return P and type(P.guest) == "function" and P.guest() or nil
end

-- ---------------------------------------------------------------- "Zone erledigt" (change "zone-abgeschlossen")

Frame.ROW_H_TIGHT = 18 -- row height while the zone row shows: 7 x 18 <= 6 x 22, the table does not grow
Frame.ZONE_STAMP = 18  -- stamp (medal "Zonenkenner") in the zone row

-- what the zone row shows for a card: nil (no row) or { kind = "zone"|"total", label, value, complete, partial, mapID, res|summary }.
-- No row: unexplored zone, another character's book (the quest state is the logged-in character's), Retail / no data /
-- not loaded yet / in combat without a cached value (ZoneProgress answers nil), zones with fewer than ZoneProgress.MIN_QUESTS
-- countable quests; total journey: only after a sweep with at least one zone (decision F8).
function Frame.zoneRowInfo(c)
  local ZP = Journal.ZoneProgress
  if type(c) ~= "table" or c.unexplored or not ZP or guestNow() then return nil end
  local T = Frame.TEXT
  if c.total then
    local s = ZP.summary()
    if type(s) ~= "table" or (s.zones or 0) < 1 then return nil end
    return { kind = "total", label = T.row_zonesDone, value = T("zonesDoneValue", int(s.complete), int(s.zones)),
      complete = s.complete > 0 and s.complete == s.zones, summary = s }
  end
  local ok, res = pcall(ZP.of, c.zoneID)
  if not ok or type(res) ~= "table" or res.small or not res.pct then return nil end
  local value = res.complete and T.zoneComplete or T("zonePct", int(res.pct), int(res.done), int(res.total))
  if res.partial then value = T("zonePartial", value) end
  return { kind = "zone", label = T.row_zone, value = value, complete = res.complete, partial = res.partial, mapID = res.mapID, res = res }
end

-- tooltip of the zone row (display-ready lines from ZoneProgress; total journey: count and rule)
function Frame.zoneTip(info)
  local ZP = Journal.ZoneProgress
  if type(info) ~= "table" or not ZP then return nil end
  if info.kind == "zone" then return ZP.tooltip(info.mapID) end
  local T, s = Frame.TEXT, info.summary
  local label = ZP.TIP_COLOR and ZP.TIP_COLOR.label or nil
  return { T.zonesTipTitle, T("zonesTipLine", int(s.complete), int(s.zones)), T("zonesTipRule", int(ZP.MIN_QUESTS)) },
    { [3] = label }
end

-- tier of the medal "Zonenkenner" for the stamp (earned tier, else bronze)
local function zoneStampTier()
  local C = Journal.Chronik
  local char = ns.Store and ns.Store.current or nil
  local v = C and C.counterValue and C.counterValue("zone_master", char) or 0
  local n = C and C.stepsFor and C.stepsFor("zone_master", v) or 0
  return (C and C.TIER_ORDER and C.TIER_ORDER[n]) or "bronze"
end

-- rows of the values table at their height: tight while the zone row shows
local function layoutRows(card, tight)
  local h = tight and Frame.ROW_H_TIGHT or Frame.ROW_H
  for _, r in ipairs(card.rows) do r.frame:SetHeight(h) end
  card.zoneRow.frame:SetHeight(h)
end

-- (re)draws the zone row of the shown card; called by setCard and on every change of the quest state (ZoneProgress.onChange)
function Frame.updateZoneRow()
  local card = J.card
  local zr = card and card.zoneRow
  if not zr then return end
  local c = card.chapter
  local info = Frame.zoneRowInfo(c)
  card.zoneInfo = info
  local show = info ~= nil and card.rows[1] ~= nil and card.rows[1].frame:IsShown()
  layoutRows(card, show)
  if not show then
    zr.frame:Hide()
    return
  end
  zr.label:SetText(info.label)
  zr.value:SetText(info.value)
  zr.value:SetTextColor(Journal.Widgets.color(info.complete and "gold" or "ink"))
  local stamp = info.complete and info.kind == "zone"
  if stamp then
    local w = strWidth(zr.value, info.value) -- right-aligned value: the stamp sits just left of its text
    zr.ring:ClearAllPoints()
    zr.ring:SetPoint("RIGHT", zr.frame, "RIGHT", -(w + 6), 0)
    Frame.paintStamp(zr.motif, zr.ring)
  else
    zr.motif:Hide()
    zr.ring:Hide()
  end
  zr.frame:Show()
end

-- the stamp of the medal "Zonenkenner" (earned tier, else bronze) on two textures; the caller places the ring, the motif centres on it
function Frame.paintStamp(motifTex, ringTex)
  local Chronik = Journal.Chronik
  local seal = Chronik and Chronik.SEAL_BY_ID and Chronik.SEAL_BY_ID.zone_master
  local motif, ring = Theme.sealLayers(seal, zoneStampTier())
  for _, pair in ipairs({ { motifTex, motif }, { ringTex, ring } }) do
    local t, layer = pair[1], pair[2]
    if layer and layer.tex then
      t:SetTexture(layer.tex)
      local co = layer.coords
      if co then t:SetTexCoord(co[1], co[2], co[3], co[4]) else t:SetTexCoord(0, 1, 0, 1) end
      local px = floor(Frame.ZONE_STAMP * (layer.scale or 1) + 0.5)
      t:SetSize(px, px)
      local col = layer.color or { 1, 1, 1 }
      t:SetVertexColor(col[1], col[2], col[3], 1)
      t:Show()
    else
      t:Hide()
    end
  end
end

-- K4: zone progress in the head of the right page (chapter: its zone, act: the anchor zone), right end of the title line
function Frame.buildHeadZone(tb)
  local z = CreateFrame("Frame", nil, tb)
  z:SetSize(160, 20)
  z:SetPoint("TOPRIGHT", tb, "TOPRIGHT", 0, -6)
  z.value = Theme.fontString(z, "label", 12, Theme.C.ink, "OVERLAY", "RIGHT")
  z.value:SetPoint("RIGHT", z, "RIGHT", 0, 0)
  z.value:SetWordWrap(false)
  z.ring = z:CreateTexture(nil, "ARTWORK", nil, 1)
  z.motif = z:CreateTexture(nil, "ARTWORK", nil, 2)
  z.motif:SetPoint("CENTER", z.ring, "CENTER", 0, 0)
  z.ring:Hide()
  z.motif:Hide()
  z:EnableMouse(true)
  z:SetScript("OnEnter", function(self)
    local lines, colors = Frame.zoneTip(self.info)
    if lines and Journal.Widgets then Journal.Widgets.tip(self, lines, colors) end
  end)
  z:SetScript("OnLeave", function(self) if Journal.Widgets then Journal.Widgets.hideTip(self) end end)
  z:Hide()
  return z
end

-- zone of the chosen act/chapter for the zone progress; nil without a selection in the table of contents
function Frame.tocZone()
  local model = J.model
  local a = J.tocOn and J.sel.act and model and model.acts[J.sel.act]
  if not a then return nil end
  local c = J.sel.chapter and model.chapters[J.sel.chapter]
  return (c and c.zoneID) or a.zoneID
end

-- -> width used (0 = hidden)
function Frame.updateHeadZone()
  local z = J.headZone
  if not z then return 0 end
  local zone = Frame.tocZone()
  local info = zone and Frame.zoneRowInfo({ zoneID = zone }) or nil
  z.info = info
  if not info then
    z:Hide()
    return 0
  end
  local text = info.label .. " " .. info.value
  z.value:SetText(text)
  z.value:SetTextColor(Journal.Widgets.color(info.complete and "gold" or "ink"))
  local w = strWidth(z.value, text)
  local stamp = info.complete and info.kind == "zone"
  if stamp then
    z.ring:ClearAllPoints()
    z.ring:SetPoint("RIGHT", z, "RIGHT", -(w + 6), 0)
    Frame.paintStamp(z.motif, z.ring)
    w = w + 6 + Frame.ZONE_STAMP
  else
    z.ring:Hide()
    z.motif:Hide()
  end
  z:SetWidth(w)
  z:Show()
  return w
end

function Frame.updateTabs()
  if not J.tabs then return end
  local slot = 0 -- visible bookmarks close the gaps of the hidden ones (guest book, Retail without Handwerk)
  for _, b in ipairs(J.tabs) do
    local current = J.page == b.tabId
    local available = tabAvailable(b.tabId)
    local P = Journal.Pages
    -- guest book / client without this tab: the bookmark is gone, not dimmed
    local gone = P ~= nil and ((P.guestAllows ~= nil and not P.guestAllows(b.tabId)) or (P.tabHidden ~= nil and P.tabHidden(b.tabId)))
    b:SetShown(not gone)
    if not gone then
      b.baseY = -(Frame.TAB.y0 + slot * Frame.TAB.pitch + b.wobble.dy)
      slot = slot + 1
    end
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

Frame.TAB_TIP_IDS = { reise = true, chronik = true, dungeons = true, kampf = true, quests = true, plaene = true, schaetze = true,
  handwerk = true, momente = true, notizen = true }
Frame.TAB_TIP = setmetatable({}, { __index = function(_, id)
  if Frame.TAB_TIP_IDS[id] then
    -- Retail: no campfire guests (switch "Am Feuer" hidden) and none of the WoW Forever parts (Lehrplan, Zonen, Dungeon-Quests)
    local ms, lp = Journal.MapSpace, Journal.Lehrplan
    local noFire = id == "chronik" and ms ~= nil and type(ms.fireTalkHidden) == "function" and ms.fireTalkHidden() == true
    local noPlan = (id == "quests" or id == "plaene" or id == "dungeons") and lp ~= nil and type(lp.active) == "function"
      and lp.active() == false
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
    if guestNow() then -- another character's book: only what Pages.guestAllows leaves
      local P, out = Journal.Pages, {}
      for _, s in ipairs(Frame.SUBTABS_REISE) do
        if not P or P.guestAllows(Frame.HOME, s.key) then out[#out + 1] = s end
      end
      return out
    end
    return Frame.SUBTABS_REISE
  end
  local P = Journal.Pages
  return P and P.subs and P.subs(id) or nil
end

function Frame.reiseSub()
  if J.reiseHeat then return "heatmap" end
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
  if key == "heatmap" then
    if not J.reiseHeat then
      J.reiseHeat = true
      Frame.render(View.status, View.model, View.stale)
    end
    return
  end
  if J.reiseHeat then
    -- leaving the heat map: back to the journey view the bookmark asks for (the journey parts were hidden, full redraw)
    J.reiseHeat = false
    local HV = Journal.HeatmapView
    if HV and J.heat then HV.hide(J.heat) end
    if (key == "gesamt") ~= Frame.isTotal() then
      J.sel, J.contWhole = {}, false
      J.mapMode = key == "gesamt" and "continent" or "zone"
      Frame.clearFollow()
      J.tocBand = nil
    end
    J.over:Show()
    Frame.render(View.status, View.model, View.stale)
    return
  end
  local total = Frame.isTotal()
  if (key == "gesamt") ~= total then
    J.sel, J.contWhole = {}, false
    J.mapMode = key == "gesamt" and "continent" or "zone"
    Frame.clearFollow() -- the replay's zone/flight view never carries over into the other sub-page
    J.tocBand = nil
    Frame.refresh()
  end
end

local function inList(list, key)
  for _, s in ipairs(list or {}) do
    if s.key == key then return true end
  end
  return false
end

function Frame.showSub(key)
  local list = Frame.subList(J.page)
  if not (J.frame and J.frame:IsShown() and type(key) == "string") then return false end
  -- a sub-page of the old order (I12, e.g. "vorhaben" on Reise): follow it to its new tab instead of doing nothing
  if not inList(list, key) then
    local P = Journal.Pages
    local id, sub = J.page, key
    if P and type(P.resolve) == "function" then id, sub = P.resolve(J.page, key) end
    if id == J.page or not Frame.showPage(id) then return false end
    list = Frame.subList(J.page)
    -- the tab changed: that counts as done even if it has no sub-bookmarks here (Retail, guest book) or already shows the sub-page
    if not inList(list, sub) or sub == Frame.currentSub() then return true end
    key = sub
  end
  if not list or key == Frame.currentSub() then return false end
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

-- Cross-tab jump (I12: Lehrplan-/Dungeon-Sprünge, Dungeon-Quest -> Questtext): shows tab id (and sub-bookmark sub) and remembers
-- where it came from; Frame.jumpBack(id) leads back there once, as long as the target still shows that sub-bookmark.
function Frame.jump(id, sub)
  local fromId, fromSub = J.page, Frame.currentSub()
  if not Frame.showPage(id) then return false end
  if sub and Frame.currentSub() ~= sub then Frame.showSub(sub) end
  if sub and Frame.subList(J.page) and Frame.currentSub() ~= sub then return false end
  J.returnTo = (fromId and fromId ~= id) and { at = id, atSub = Frame.currentSub(), id = fromId, sub = fromSub } or nil
  return true
end

function Frame.jumpBack(id)
  local r = J.returnTo
  if not (r and r.at == id and J.page == id and J.frame and J.frame:IsShown()) then return false end
  J.returnTo = nil
  if r.atSub and Frame.currentSub() ~= r.atSub then return false end
  if not Frame.showPage(r.id) then return false end
  if r.sub and Frame.currentSub() ~= r.sub then Frame.showSub(r.sub) end
  return true
end

-- To Do of the tab Pläne (pins on the map, tracker, companion note)
function Frame.openTodo()
  if not Frame.showPage("plaene") then return false end
  if Frame.currentSub() ~= "vorhaben" then Frame.showSub("vorhaben") end
  return Frame.currentSub() == "vorhaben"
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

-- Sets the label font to scale x its base size (base = size at first sight or after somebody else, e.g. the handwriting upgrade,
-- reset it); returns nothing, the width is measured afterwards.
local function subTabScale(b, scale)
  local fs = b.text
  if type(fs.GetFont) ~= "function" or type(fs.SetFont) ~= "function" then return end
  local file, size, flags = fs:GetFont()
  if not file or not tonumber(size) then return end
  if b.fitSize and size ~= b.fitSize then b.baseSize = nil end
  if not b.baseSize then b.baseSize = size end
  local want = scale >= 1 and b.baseSize or math.max(8, floor(b.baseSize * scale + 0.5))
  if want ~= size then pcall(fs.SetFont, fs, file, want, flags or "") end
  b.fitSize = (want ~= b.baseSize) and want or nil
end

function Frame.updateSubTabs()
  if not J.subTabs then return end
  local k = Frame.SUBTAB
  local list = Frame.subList(J.page)
  local cur = list and Frame.currentSub()
  local D = Journal.Widgets and Journal.Widgets.Diary
  local shown = {}
  for i, b in ipairs(J.subTabs) do
    local s = list and list[i]
    if s then
      b.subKey, b.sub = s.key, s
      if b.labelText ~= s.label then
        b.labelText = s.label
        b.text:SetText(s.label)
      end
      shown[#shown + 1] = b
    else
      b.subKey, b.sub, b.current = nil, nil, false
      b:Hide()
    end
  end
  -- widths: first step of k.fit whose last ribbon ends before the fold (left page only), else the tightest
  local xmax = Frame.W / 2 - k.foldGap
  local widths, step = {}, k.fit[#k.fit]
  for n, f in ipairs(k.fit) do
    local x = k.x0
    for i, b in ipairs(shown) do
      subTabScale(b, f.scale)
      local tw = (D and D.measure(b.text)) or 0
      if tw <= 0 then tw = #b.sub.label * 7 * f.scale end
      widths[i] = math.max(f.minW, floor(tw + 2 * f.pad + 0.5))
      if b.sub.art then widths[i] = Frame.SUB_BAND.w end
      x = x + widths[i] + (i < #shown and f.gap or 0)
    end
    step = f
    if x <= xmax then break end
  end
  local x = k.x0
  for i, b in ipairs(shown) do
    local s, w = b.sub, widths[i]
    if b.cell ~= J.page then subTabSetCell(b, J.page) end
    local current = s.key == cur
    local lift = (not current and b.hover) and k.hover or 0
    local extra = current and k.pull or lift
    local v = current and 1 or (b.hover and 0.8 or k.dim)
    local art = Frame.subArt(b, s)
    if art then
      local B = Frame.SUB_BAND
      b:SetSize(w, B.h)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", b.owner, "BOTTOMLEFT", x, B.top - extra)
      -- clickable from the page edge down (the part under the page is not the band's)
      if b.SetHitRectInsets then b:SetHitRectInsets(0, 0, math.max(0, B.top - extra - B.page), B.h - B.content) end
      local va = current and 1 or (b.hover and B.hover or B.dim)
      b.art:SetVertexColor(va, va, va)
    else
      b:SetSize(w, k.under + k.out)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", b.owner, "BOTTOMLEFT", x, k.under - extra)
      if b.SetHitRectInsets then b:SetHitRectInsets(0, 0, math.max(0, k.under - extra - k.edge), 0) end
    end
    b.body:SetVertexColor(v, v, v)
    b.tip:SetVertexColor(v, v, v)
    b.text:SetTextColor(SUB_LABEL[1], SUB_LABEL[2], SUB_LABEL[3], current and 1 or 0.82)
    b.current = current
    b:Show()
    x = x + w + step.gap
  end
  Frame.updateSubEsc()
end

-- painted band instead of ribbon + label (sub.art, only "Inhalt" on the journey): texture by the book's language (German -> DE,
-- else EN). -> true while the band shows on button b
function Frame.subArt(b, s)
  local on = s and s.art == "contents" and J.page == Frame.HOME
  if not b.art then
    if not on then return false end
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    t:SetSize(Frame.SUB_BAND.w, Frame.SUB_BAND.h)
    b.art = t
  end
  if on then
    local L = ns.Locale
    local tex = (L and L.active == "deDE") and Theme.TEX.subContentsDE or Theme.TEX.subContentsEN
    if b.art.texFile ~= tex then
      b.art:SetTexture(tex)
      b.art.texFile = tex
    end
  end
  b.art:SetShown(on and true or false)
  for _, t in ipairs({ b.body, b.tip, b.bodyShadow, b.tipShadow, b.text }) do t:SetShown(not on) end
  return on and true or false
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
      -- quiet save status (computed now, no ticker); the save button itself sits in the settings
      local S = ns.Save
      local ok, line = pcall(function() return S and S.statusText() end)
      if ok and type(line) == "string" then GameTooltip:AddLine(line, 0.6, 0.6, 0.6, true) end
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
  local HV = Journal.HeatmapView
  if HV and J.heat then HV.hide(J.heat) end
  View.setActive(false)
  Frame.clearFollow() -- closing the book or leaving the journey: next time the map starts from the selection again
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
  J.returnTo = nil -- a page change by hand forgets a cross-tab jump (Frame.jump sets it again afterwards)
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

-- Another character's book opens or closes (Pages.onGuestChange, fired before the pages redraw): the journey view starts from
-- scratch for the other character, the To Do sheet closes, band and button follow, and a page that the guest book leaves out
-- (Notizen, Pläne) gives way to the journey map (Pages.setGuest itself only redraws pages that stay allowed).
function Frame.onGuestChange(guid)
  deps()
  J.sel, J.contWhole, J.mapMode = {}, false, "zone"
  J.reiseHeat = false
  if Journal.HeatmapView and J.heat then Journal.HeatmapView.reset(J.heat) end
  if J.over and J.frame and J.frame:IsShown() and J.page == Frame.HOME then J.over:Show() end
  Frame.clearFollow()
  J.actCardsFor, J.actCards, J.tocBand = nil, nil, nil
  J.zoneCards, J.stationsFor, J.stationList, J.stationSel, J.axisModel = nil, nil, nil, nil, nil
  if J.st then J.st.playing = false end
  if J.pb then Playback.stopTicking(J.pb) end
  local V = Journal.Vorhaben
  if guid ~= nil and V then
    if V.cancelPick then pcall(V.cancelPick, true) end
    if V.isOpen() then pcall(V.close) end
  end
  J.model, J.scene = nil, nil
  if J.map then J.map.scene = nil end
  if J.here then J.here:Hide() end
  local Tw = Journal.Twinks
  if Tw and Tw.onGuest then pcall(Tw.onGuest, guid) end
  local f = J.frame
  if not (f and f:IsShown()) then return end
  if not tabAvailable(J.page) then
    applyPage(Frame.HOME)
  elseif J.page == Frame.HOME then
    local _, _, changed = View.request()
    if not changed then Frame.render(View.status, View.model, View.stale) end
  end
  Frame.updateTabs()
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
  if f.SetClampRectInsets then f:SetClampRectInsets(0, Frame.TABS_OUT, 0, -math.max(Frame.SUBTABS_OUT, Frame.SUB_BAND.out)) end
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
      Frame.openTodo()
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
  -- To Do sheet (journal/Vorhaben.lua) of the tab Pläne: over the whole double page, above the page holders; hidden unless the
  -- sub-bookmark "To Do" is shown (pages/Plaene.lua opens and closes it, and closes it when the tab is left)
  if Journal.Vorhaben then
    J.vorhaben = Journal.Vorhaben.build(pgLeft)
    Journal.Vorhaben.onChange = function()
      local Pg = Journal.Pages
      if Pg and Pg.subChanged then Pg.subChanged("plaene") end
    end
  end
  local P = Journal.Pages
  if P then
    P.attach(pgLeft, pgRight)
    P.onChange(Frame.updateTabs)
    if P.onGuestChange then P.onGuestChange(Frame.onGuestChange) end
    if P.onSubChange then P.onSubChange(function() Frame.updateSubTabs() end) end
  end

  local over = CreateFrame("Frame", nil, spread)
  over:SetAllPoints(spread)
  over:SetFrameLevel(map.viewport:GetFrameLevel() + 12)
  J.over = over
  local W = Journal.Widgets

  local card, tableEnd = buildCard(over)
  -- K4: table of contents of the acts and chapters (journal/Contents.lua), on the left page instead of the value card
  local Cn = Journal.Contents
  if Cn then
    J.contents = Cn.create(over, Frame.LEFT.x, Frame.CARD_Y, Frame.LEFT.w, Frame.CONTENTS_BOTTOM - Frame.CARD_Y, {
      onBand = safe(function(b) Frame.openBand(b) end),
      onAct = safe(function(n) Frame.selectAct(n) end),
      onChapter = safe(function(i) Frame.selectChapter(i) end),
      -- zone progress of the line's zone in its tooltip (act: anchor zone)
      tipExtra = function(kind, index)
        local model = J.model
        local e = model and (kind == "act" and model.acts[index] or model.chapters[index])
        local info = e and Frame.zoneRowInfo({ zoneID = e.zoneID })
        return info and { info.label .. ": " .. info.value } or nil
      end,
    })
  end
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
  J.headZone = Frame.buildHeadZone(tb)

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
  -- K4: inside a chapter Esc leads back to its act (invisible catcher; the table of contents is the navigation)
  local levelEsc = CreateFrame("Frame", nil, over)
  levelEsc:SetSize(1, 1)
  levelEsc:SetPoint("TOPLEFT", over, "TOPLEFT", 0, 0)
  D.escKeys(levelEsc, safe(function() Frame.back() end))
  levelEsc:Hide()
  J.levelEsc = levelEsc
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
      -- compared with the chosen mode: a flight while replaying shows the continent although the zone map is chosen (K2)
      if J.scene and key ~= J.mapMode then Frame.toggleMapMode() elseif J.scene then updateMode(J.scene) end
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
  local rb = D.NewCheck(ctrl, Frame.TEXT.reveal, { size = Frame.CTRL_SIZE, checked = Frame.revealShown(),
    tip = { Frame.TEXT.reveal, Frame.TEXT.revealTip },
    onChange = safe(function(on) Frame.setRevealMap(on) end) })
  rb:Hide()
  J.revealBox = rb
  -- continent map: show/hide all event symbols (route and arrow always stay); setting showIcons like showKills
  local ib = D.NewCheck(ctrl, Frame.TEXT.icons, { size = Frame.CTRL_SIZE, checked = Frame.iconsShown(),
    tip = { Frame.TEXT.icons, Frame.TEXT.iconsTip },
    onChange = safe(function(on) Frame.setShowIcons(on) end) })
  ib:Hide()
  J.iconBox = ib
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
      if i == 0 then Frame.selectTotal() else Frame.selectChapter(i) end
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
  -- K2 (playtest 10.11.): the page turner of the stickers sits directly under the sticker grid (Playback.layoutGrid)
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
    -- P3 flight and hearthstone book: own block above the stations (Frame.updateFlightBook / Frame.placeLower)
    if FlightBook then
      J.flightBook = FlightBook.create(over, SA.x, SA.y, SA.w)
    end
    local I = Journal.Index
    if I and I.onReady then
      I.onReady(function()
        J.stationsFor = nil
        if J.frame and J.frame:IsShown() and J.page == Frame.HOME and J.model and Frame.isTotal() then Frame.updateStations(true, true) end
      end)
    end
    if I and I.onGuestReady then -- the guest's index finished in the background: stations of the guest book
      I.onGuestReady(function(_, guid)
        local g = guestNow()
        if not (g and guid == g.guid) then return end
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
  if Journal.Twinks and Journal.Twinks.build then pcall(Journal.Twinks.build, f, over, J.gear) end
  if Journal.Share and Journal.Share.build then pcall(Journal.Share.build, J.pb.frame) end

  f:SetScript("OnShow", safe(function(self)
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("UI_SCALE_CHANGED")
    self:RegisterEvent("DISPLAY_SIZE_CHANGED")
    Frame.applyScale()
    local P = Journal.Pages
    applyPage((P and P.initial()) or Frame.HOME)
    if Journal.Twinks then pcall(Journal.Twinks.updateButton) end
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
    J.returnTo = nil -- a cross-tab jump never outlives the open book
    local P = Journal.Pages
    if P then pcall(P.close or P.hide) end -- closing the book always goes back to the own book (frees a guest)
    if Journal.Twinks then pcall(Journal.Twinks.onClose) end
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
      if P then pcall(P.close or P.hide) end
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
  return J.mapMode == "continent" and not (J.sel.chapter or J.sel.zone or J.sel.act)
end

-- K2 levels of the zone map ("Akte"): "acts" = the acts as stickers (default), "act" = one act, its chapters as stickers,
-- "chapter" = one chapter of that act
function Frame.level()
  if J.sel.chapter then return "chapter" end
  if J.sel.act then return "act" end
  return "acts"
end

-- act index at axis position p (end / nil: the last act); nil without acts
local function actIndexAt(p)
  local model = J.model
  local acts = model and model.acts
  if type(acts) ~= "table" or #acts == 0 then return nil end
  if J.sel.act and acts[J.sel.act] then return J.sel.act end
  if p == huge or not p then return #acts end
  local t = View.timeAt(model, View.fromAxis(model, p))
  local n = t and View.actAt(model, t)
  if type(n) ~= "number" or not acts[n] then return #acts end
  return n
end

-- Card of an act (cached per model; right head and continent title): label "AKT I", title the anchor zone, subtitle "Stufe 1–13 · 17 Std.",
-- story "5 Kapitel: Dun Morogh, Loch Modan, …" (zone names of its chapters in order, repeats merged), values like a chapter.
function Frame.actCard(model, n)
  if type(model) ~= "table" or type(model.acts) ~= "table" then return nil end
  if J.actCardsFor ~= model then J.actCardsFor, J.actCards = model, {} end
  local c = J.actCards[n]
  if c then return c end
  local a = model.acts[n]
  if not a then return nil end
  local names, last = {}, nil
  for _, i in ipairs(a.chapters or {}) do
    local ch = model.chapters[i]
    local nm = ch and ch.zoneName
    if nm and nm ~= last then names[#names + 1] = nm end
    last = nm or last
  end
  local story = Frame.TEXT("actStory", int(#(a.chapters or {})), table.concat(names, ", "))
  local S = ns.Sanitize
  if S and S.display then story = S.display(story, 160) or story end
  c = { isAct = true, index = "a" .. int(n), actIndex = n, roman = a.roman, title = a.title,
    zoneName = a.zoneName, zoneID = a.zoneID, subtitle = a.subtitle, story = story, stats = a.stats,
    levelFrom = a.levelFrom, levelTo = a.levelTo, t0 = a.t0, t1 = a.t1, p0 = a.p0, p1 = a.p1 }
  J.actCards[n] = c
  return c
end


local function zoneChapterIndex(zone)
  local chapters = J.model and J.model.chapters
  if type(chapters) ~= "table" or type(zone) ~= "number" then return nil end
  for i = #chapters, 1, -1 do
    if chapters[i] and chapters[i].zoneID == zone then return i end
  end
  -- visited only as a detour (K2: short visits without weight): the chapter that holds it, not "unexplored"
  for i = #chapters, 1, -1 do
    for _, d in ipairs(chapters[i] and chapters[i].detours or {}) do
      if d.zoneID == zone then return i end
    end
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
  if J.sel.chapter then return model.chapters[J.sel.chapter] end
  -- K2: the zone map shows acts (the chosen act, else the act at the playback position); the total journey keeps its chapters
  if not Frame.isTotal() then
    local n = actIndexAt(p)
    local c = n and Frame.actCard(model, n)
    if c then return c end
  end
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
  local c = (scene.chapter and model.chapters[scene.chapter]) or (scene.act and Frame.actCard(model, scene.act)) or nil
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
  -- K4: a chosen act/chapter names itself in the head ("Kapitel III · Dun Morogh"), below the shown map and its figures
  local head = Frame.tocHead(scene)
  if head then
    J.titleName:SetText(head.title)
    J.titleLabel:SetText(head.label or "")
    J.titleStats:SetText(head.stats or "")
  end
  local zw = Frame.updateHeadZone()
  -- 28 pt title: shrinks down to 18 pt before it would be cut; full text on hover when it had to shrink
  local size = Journal.Widgets.fitLine(J.titleName, Frame.TITLE_W - (zw > 0 and (zw + 12) or 0), 18)
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
  local show = scene.mode == "continent" and not (J.sel.chapter or J.sel.zone or J.sel.act) and not scene.flight and #list > 1
    and not scene.empty
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
    if scene.mode == "zone" or scene.flight then
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
    J.killBox:SetShown(not scene.empty and (scene.mode ~= "continent" or scene.flight) and true or false)
    J.killBox:SetChecked(Frame.killsShown(), true)
  end
  if J.revealBox then
    J.revealBox:SetShown(not scene.empty and (scene.mode ~= "continent" or scene.flight) and true or false)
    J.revealBox:SetChecked(Frame.revealShown(), true)
  end
  if J.iconBox then
    -- wherever the continent map shows (total journey, the continent view of the contents page), not during a replayed flight
    J.iconBox:SetShown(not scene.empty and scene.mode == "continent" and not scene.flight)
    J.iconBox:SetChecked(Frame.iconsShown(), true)
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
function Frame.iconsShown()
  deps()
  return View.peek("showIcons") ~= false
end

function Frame.setShowIcons(on)
  deps()
  on = on and true or false
  View.set("showIcons", on)
  if J.iconBox then J.iconBox:SetChecked(on, true) end
  if J.model then Frame.refresh(true) end
  return on
end

-- continent map without symbols: markers, gaps, level-ups, kill marks and the note/to-do pins go; the margin notes keep their
-- text but lose the number on the map. Route and arrow stay.
function Frame.stripIcons(scene)
  if scene.mode ~= "continent" or Frame.iconsShown() then return scene end
  scene.markers, scene.gaps, scene.levelUps, scene.kills, scene.pins = {}, {}, {}, nil, {}
  local notes = {}
  for i, n in ipairs(scene.notes or {}) do
    notes[i] = { text = n.text, kind = n.kind, p = n.p, t = n.t, score = n.score }
  end
  scene.notes = notes
  scene.iconsHidden = true
  return scene
end

function Frame.revealShown()
  deps()
  return View.peek("revealMap") == true
end

function Frame.setRevealMap(on)
  deps()
  on = on and true or false
  View.set("revealMap", on)
  if J.revealBox then J.revealBox:SetChecked(on, true) end
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
  -- inside an act/chapter the table of contents navigates (Esc via J.levelEsc: chapter -> act); Back stays for a zone picked on
  -- the continent, the zoom and a replay's zone on the overview
  local inAct = J.sel.act ~= nil and J.tocOn and true or false
  local showBack = (not inAct) and (J.sel.chapter or J.sel.zone or J.sel.act or J.showZone or J.showCont
    or (J.map and Map.zoomed(J.map))) and J.model ~= nil and true or false
  Frame.backLabel()
  J.back:SetShown(showBack)
  if J.levelEsc then J.levelEsc:SetShown(inAct and J.sel.chapter ~= nil and J.model ~= nil and J.page == Frame.HOME) end
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
  -- "Reveal map" sits right of "Show fights" (both only in the zone view); the "updating" hint on the right gives way when
  -- the two would touch
  local rb, used = J.revealBox, lx
  if rb and rb:IsShown() then
    rb:ClearAllPoints()
    local rx = lx + ((kb and kb:IsShown()) and (width(kb) + 16) or 0)
    rb:SetPoint("LEFT", ctrl, "LEFT", rx, 0)
    used = rx + width(rb)
  end
  local sh = J.staleHint
  if sh then
    local room = width(ctrl) - (tonumber(sh:GetStringWidth()) or 0) - 8
    sh:SetShown(J.staleOn and not (rb and rb:IsShown() and width(ctrl) > 0 and used > room) and true or false)
  end
  J.contToggle.frame:ClearAllPoints()
  J.contToggle.frame:SetPoint("LEFT", ctrl, "LEFT", lx, 0)
  local ib = J.iconBox
  if ib and ib:IsShown() then
    ib:ClearAllPoints()
    local cx = lx + (J.contToggle.frame:IsShown() and (width(J.contToggle.frame) + 16) or 0)
    ib:SetPoint("LEFT", ctrl, "LEFT", cx, 0)
  end
  Frame.updateSubEsc()
  Frame.updateHere()
  return n
end
Frame.layoutTitle = Frame.layoutControls

function Frame.obstacles()
  return {}
end

-- Guest book: the map arrow is the other character's last known place, not a live position. A small hover area over the arrow
-- says so ("Last here", with the last-seen date). Own book: no area.
function Frame.updateHere()
  local g, m = guestNow(), J.map
  local shown = g ~= nil and m ~= nil and m.current ~= nil and m.current:IsShown() and J.page == Frame.HOME
  if not shown then
    if J.here then J.here:Hide() end
    return false
  end
  local Tw = Journal.Twinks
  local TX = Tw and Tw.TEXT
  if not TX then return false end
  if not J.here then
    local h = CreateFrame("Frame", nil, J.over)
    h:SetSize(24, 24)
    h:SetFrameLevel(J.over:GetFrameLevel() + 3)
    h:EnableMouse(true)
    h:SetScript("OnEnter", function(self)
      if Journal.Widgets and self.lines then Journal.Widgets.tip(self, self.lines) end
    end)
    h:SetScript("OnLeave", function(self) if Journal.Widgets then Journal.Widgets.hideTip(self) end end)
    J.here = h
  end
  local S = ns.Sanitize
  local name = (S and S.display(g.fullName or g.name, 40)) or TX.unknownName
  local lines = { TX.hereTitle, TX("hereText", name) }
  local d = Tw.dateText and Tw.dateText(g.lastSeen)
  if d then lines[#lines + 1] = TX("standDate", d) end
  J.here.lines = lines
  J.here:ClearAllPoints()
  J.here:SetPoint("CENTER", m.current, "CENTER", 0, 0)
  J.here:Show()
  return true
end

function Frame.rightClick()
  -- K2: inside an act or chapter the right click leads one level back (as the Back tooltip says); only the acts overview
  -- keeps the map toggle (unzoom, then continent)
  if J.sel.chapter and J.sel.act then return Frame.back() and "back" or nil end
  -- K4: on an act the right click only removes a zoom (Kapitel -> Akt -> nichts; the table of contents navigates)
  if J.sel.act then return (J.map and Map.resetView(J.map)) and "unzoom" or nil end
  local scene = J.scene
  if scene and scene.mode == "zone" then
    if J.map and Map.resetView(J.map) then return "unzoom" end
    Frame.toggleMapMode()
    return "continent"
  end
  return Frame.back() and "back" or nil
end

-- label and tooltip of "Back" (only outside an act/chapter since K4)
function Frame.backLabel()
  local b = J.back
  if not b then return nil end
  local TX = Frame.TEXT
  if b.labelText ~= TX.back and b.SetLabel then b:SetLabel(TX.back) end
  if type(b.diaryOpts) == "table" then b.diaryOpts.tip = { TX.backTitle, TX.backTip } end
  return TX.back
end

-- Back (button, Esc, right click, double click): chapter -> its act, act -> the acts, zone -> overview, then the zoom, then
-- the zone a replay moved to -> the default view
function Frame.back()
  local model = J.model
  if J.sel.chapter and J.sel.act and model and model.acts and model.acts[J.sel.act] then
    Frame.select({ act = J.sel.act })
    return true
  end
  if J.sel.chapter or J.sel.zone or J.sel.act then
    Frame.select(nil)
    return true
  end
  if J.map and Map.resetView(J.map) then return true end
  if J.showZone or J.showCont then
    Frame.clearFollow()
    Frame.refresh()
    return true
  end
  return false
end

-- Reise > Heatmap (I15): the journey parts (overlay, map, replay) rest, the heat map panel (journal/HeatmapView.lua) shows the
-- zone list and the embers of the same journey model; status texts as on the journey map
function Frame.renderHeat(status, model)
  local HV = Journal.HeatmapView
  if J.st then J.st.playing = false end
  if J.pb then Playback.stopTicking(J.pb) end
  Theme.hideTooltip()
  J.over:Hide()
  J.map.viewport:Hide()
  J.model, J.scene, J.map.scene = nil, nil, nil
  if not J.heat then J.heat = HV.build(J.spread, J.over:GetFrameLevel()) end
  local msg = (status ~= "ready" or not model) and (Frame.TEXT[status] or Frame.TEXT.loading) or nil
  HV.show(J.heat, model, msg)
  Frame.updateSubTabs()
end

function Frame.render(status, model, stale)
  if not J.frame or J.page ~= Frame.HOME then return end
  if J.reiseHeat then
    if Journal.HeatmapView then return Frame.renderHeat(status, model) end
    J.reiseHeat = false
    J.over:Show()
  end
  J.staleOn = stale and true or false
  J.staleHint:SetShown(J.staleOn)
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
    J.tocOn = false
    if J.contents and Journal.Contents then Journal.Contents.setShown(J.contents, false) end
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
    local selBefore = J.sel
    if J.sel.chapter and not (model.chapters and model.chapters[J.sel.chapter]) then J.sel = {} end
    -- K2: act numbers can shift when a chapter grows into an anchor; a chosen act that is gone (or no longer holds the chosen
    -- chapter) falls back to the acts
    local acts = model.acts
    if J.sel.act and not (type(acts) == "table" and acts[J.sel.act]) then J.sel = {} end
    if J.sel.chapter and J.sel.act and model.chapters[J.sel.chapter].act ~= J.sel.act then J.sel = {} end
    if J.sel ~= selBefore then Frame.clearFollow() end -- the selection was dropped: its replay view goes too
  end
  J.model = model
  J.titleBox:Show()
  J.ctrl:Show()
  if J.worldLink then J.worldLink:SetShown(guestNow() == nil) end -- the world map layer always shows the logged-in character
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
  -- J.showZone / J.showCont: the zone (or, during a flight, the continent) the replay is in (K2 zone change, Frame.followZone)
  local scene = View.scene(model, J.sel, { mode = J.showCont and "continent" or J.mapMode, whole = J.contWhole,
    zone = J.showZone, continent = J.showCont, flightP = J.showFlightP })
  J.scene = scene
  if scene.flight then
    J.curKey = J.showKey
  else
    J.curKey = scene.mode == "zone" and scene.zoneID and ("z:" .. int(scene.zoneID)) or nil
  end
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
  local wasPlaying, oldP, oldP1 = J.st.playing, J.st.p, J.st.p1
  local function axis(p) return View.toAxis(model, p) end
  local r0, r1 = axis(scene.range[1]), axis(scene.range[2])
  Playback.setRange(J.st, r0, r1)
  if keepPlay then Playback.resume(J.st, oldP, wasPlaying) end
  -- K2: a paused position inside the range (e.g. the start an act/chapter click jumped to) survives a redraw with new data
  -- (only a real pause before the old end: at the end the view stays "everything", also when live data move the end)
  local paused = keepPlay and not wasPlaying and type(oldP) == "number" and type(oldP1) == "number" and oldP < oldP1
    and oldP < r1 and oldP >= r0
  if paused then J.st.p = oldP end
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
  -- Runde 3: no red margin notes on the total journey ("Tag 3 · erster Tod" ...); flight book and stations move up under the table
  if total then scene.notes = {} end
  Playback.setGridShown(J.pb, false) -- K4: no stickers; acts and chapters are in the table of contents (Frame.updateContents)
  Frame.updateContents()
  Frame.updateStations(total)
  Frame.updateFlightBook(total)
  Frame.setCard(cardFor(J.st.playing and Playback.mapP(J.st) or huge))
  updateTitle(scene)
  updateContinents(scene)
  updateMode(scene)
  scene.pins = Frame.notePins(scene)
  Frame.stripIcons(scene)
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
  elseif paused then
    Map.setProgress(J.map, Playback.mapP(J.st))
  end
end

function Frame.notePins(scene)
  local N = Journal.Notes
  local P = Journal.Pages
  local out = {}
  if not (N and N.onMap and scene and type(scene.project) == "function") then return out end
  -- another character's book: neither the notes nor the To Do pins of the logged-in character (Pages.guestAllows)
  local notesOk = not P or P.guestAllows("notizen")
  local todoOk = not P or P.guestAllows("plaene")
  local okList, list = true, {}
  if notesOk then okList, list = pcall(N.onMap) end
  if not okList or type(list) ~= "table" then return out end
  local S = ns.Sanitize
  for _, n in ipairs(list) do
    local ok, vx, vy = pcall(scene.project, n.mapID, n.x, n.y)
    if ok and type(vx) == "number" and type(vy) == "number" and vx == vx and vy == vy then
      out[#out + 1] = { id = n.id, vx = vx, vy = vy, title = (S and S.display(n.title, 120)) or Frame.TEXT.noteUntitled }
    end
  end
  local V = Journal.Vorhaben
  if todoOk and V and type(V.mapPins) == "function" then
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

function Frame.clearFollow()
  J.showZone, J.showCont, J.showFlightP, J.showKey = nil, nil, nil, nil
end

-- sel = nil | { act = n } | { chapter = i } (its act is added) | { act = n, chapter = i } | { zone = id } | { continent = id }.
-- An act or chapter does NOT play (10.11.): the map jumps to its start (zone of the first station, timeline at the start,
-- arrow on the start point); play or scrub from there.
function Frame.select(sel)
  sel = sel or {}
  local model = J.model
  if sel.chapter and not sel.act and model and model.chapters and model.chapters[sel.chapter] then
    sel = { chapter = sel.chapter, act = model.chapters[sel.chapter].act }
  end
  J.sel = sel
  J.tocBand = nil -- the table of contents opens the volume of the new selection
  J.tocFollow = true
  if J.sel.chapter or J.sel.zone or J.sel.act then J.mapMode = "zone" end
  J.contWhole = J.mapMode == "continent" and J.sel.continent ~= nil
  Frame.clearFollow()
  local t0 = model and (J.sel.chapter or J.sel.act) and View.selStart(model, J.sel) or nil
  local want = t0 and Frame.playTarget(t0)
  if want then J.showZone, J.showCont, J.showFlightP, J.showKey = want.zone, want.cont, want.fp, want.key end
  Frame.refresh()
  if t0 and J.model then
    local st = J.st
    st.p, st.playing = st.p0, false
    Playback.stopTicking(J.pb)
    Frame.hideLevelHint()
    Map.setProgress(J.map, Playback.mapP(st))
    updateTimeline()
  end
end

function Frame.selectAct(n)
  local acts = J.model and J.model.acts
  if not (type(acts) == "table" and acts[n]) then return false end
  Frame.select({ act = n })
  if Journal.Sound then pcall(Journal.Sound.play, "page") end
  return true
end

function Frame.selectChapter(i)
  local chapters = J.model and J.model.chapters
  if not (type(chapters) == "table" and chapters[i]) then return false end
  Frame.select({ chapter = i, act = chapters[i].act or J.sel.act })
  if Journal.Sound then pcall(Journal.Sound.play, "page") end
  return true
end

-- K2 zone change: what the replay at epoch t shows. A flight (TF -> TL): its continent if that map has art, else the zone of
-- departure; otherwise the main zone at t (Model.zoneAt: flown-over zones and border flicker skipped), if it has zone art.
-- -> { key, zone } | { key, cont, fp = { p0, p1 } } | nil (keep the map)
local artOk, contOk = {}, {}
local function hasZoneArt(z)
  if artOk[z] == nil then artOk[z] = View.zoneArt(z) ~= nil end
  return artOk[z]
end
local function hasContArt(c)
  if contOk[c] == nil then contOk[c] = View.mapArt(c) ~= nil end
  return contOk[c]
end
function Frame.resetArtCache() artOk, contOk = {}, {} end

function Frame.playTarget(t)
  local model = J.model
  if not model or type(t) ~= "number" then return nil end
  local z = View.zoneAtTime(model, t)
  local f0, f1 = View.flightAt(model, t)
  if f0 then
    local cont = View.continentOf(z)
    local p0, p1 = View.playedAt(model, f0), View.playedAt(model, f1)
    if cont and hasContArt(cont) and type(p0) == "number" and type(p1) == "number" then
      return { key = "c:" .. int(cont) .. ":" .. int(f0), cont = cont, fp = { p0, p1 } }
    end
  end
  if z and hasZoneArt(z) then return { key = "z:" .. int(z), zone = z } end
  return nil
end

-- While playing and scrubbing (act, chapter, and the acts level): if the position lies in another zone than the map shows,
-- the map switches there (only on a change, never per frame), and back. Not on the total journey, a zone picked on the
-- continent, the chosen continent map, or without zone art (Retail fallback). Pause/stop keeps the zone. -> true on a switch
function Frame.followZone(p)
  local model, scene = J.model, J.scene
  if not (model and scene) or p == nil or p == huge then return false end
  if Frame.isTotal() or J.sel.zone or J.sel.continent or J.mapMode ~= "zone" then return false end
  if scene.mode ~= "zone" and not scene.flight then return false end
  local t = View.timeAt(model, View.fromAxis(model, p))
  local want = t and Frame.playTarget(t)
  if not want or want.key == J.curKey then return false end
  J.showZone, J.showCont, J.showFlightP, J.showKey = want.zone, want.cont, want.fp, want.key
  local st = J.st
  local keepP, playing = st.p, st.playing
  Frame.refresh(true)
  st.p = max(st.p0, math.min(keepP, st.p1))
  st.playing = (playing and st.p < st.p1) and true or false
  if st.playing then Playback.startTicking(J.pb) end
  Map.setProgress(J.map, Playback.mapP(st))
  updateTimeline()
  Map.fadeIn(J.map)
  J.switches = (J.switches or 0) + 1
  return true
end

function Frame.selectTotal()
  J.sel = {}
  Frame.clearFollow()
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
  Frame.clearFollow()
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
  if not scene or not model or scene.mode ~= "continent" or not scene.contID or scene.flight then return nil end
  if J.sel.chapter or J.sel.zone or J.sel.act then return nil end
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
    art = View.zoneArt(zone, View.peek("revealMap") == true)
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
  local g = guestNow()
  local ok, index = pcall(I.get, { noRebuild = fromReady or nil, guid = g and g.guid or nil })
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

-- P3 flight and hearthstone book: fills the block from model.total.flightBook (total journey only; nothing to show -> hidden,
-- placeLower then gives the space back to the stations). -> true when the block shows
function Frame.updateFlightBook(on)
  local fb = J.flightBook
  if not (fb and FlightBook) then return false end
  local model = J.model
  local data = on and model and type(model.total) == "table" and model.total.flightBook or nil
  local h = FlightBook.set(fb, data)
  FlightBook.setShown(fb, on and h > 0)
  return on and h > 0 or false
end

-- K4 table of contents ------------------------------------------------------------------------------------------------
Frame.CONTENTS_BOTTOM = 604

-- the left page shows the table of contents on the sub-page "Akte" (not the total journey, not a zone picked on the continent)
function Frame.tocActive()
  local model = J.model
  return J.page == Frame.HOME and model ~= nil and not Frame.isTotal() and not J.sel.zone and not J.sel.continent
    and not model.empty and type(model.acts) == "table" and #model.acts > 0
end

-- accordion: the volume of the chosen (else the current, last) act is open, or the volume clicked last; the chosen act, else the
-- current one when its volume is open
function Frame.tocState()
  local model = J.model
  local C = Journal.Contents
  local cur = (J.sel.act and model.acts[J.sel.act]) and J.sel.act or #model.acts
  local curBand = C.bandOf(model.acts[cur] and model.acts[cur].levelFrom)
  local band = J.tocBand or curBand
  return { band = band, act = (band == curBand) and cur or nil, selAct = J.sel.act, selChapter = J.sel.chapter, follow = J.tocFollow }
end

function Frame.updateContents()
  local C, ui = Journal.Contents, J.contents
  if not (C and ui) then return false end
  local on = Frame.tocActive()
  J.tocOn = on
  if not on then
    C.setShown(ui, false)
    return false
  end
  C.set(ui, J.model, Frame.tocState())
  J.tocFollow = nil -- the scroll fallback follows the selection once (select/open), never on a live redraw
  C.setShown(ui, true)
  if J.card then J.card:Hide() end
  return true
end

function Frame.openBand(b)
  if not J.model then return false end
  J.tocBand = b
  J.tocFollow = true
  Frame.updateContents()
  Frame.placeNotes()
  if Journal.Sound then pcall(Journal.Sound.play, "page") end
  return true
end

-- margin notes: under the value card as before; with the table of contents right under its last line, if they fit
function Frame.placeNotes()
  local nb = J.noteBox
  if not nb then return end
  local y = Frame.NOTE.y
  local show = J.model ~= nil
  if J.tocOn and J.contents then
    y = Frame.CARD_Y + (J.contents.height or 0) + 10
    show = show and y + Frame.NOTE.h <= Frame.CONTENTS_BOTTOM
  end
  nb:ClearAllPoints()
  nb:SetPoint("TOPLEFT", J.over, "TOPLEFT", Frame.NOTE.x, -y)
  nb:SetShown(show and true or false)
end

-- head of the right page for a chosen act/chapter: { title, label (the shown map), stats } or nil
function Frame.tocHead(scene)
  local model = J.model
  local a = J.tocOn and J.sel.act and model and model.acts[J.sel.act]
  if not a then return nil end
  local C = Journal.Contents
  local c = J.sel.chapter and model.chapters[J.sel.chapter]
  local e = c or a
  local st = e.stats or {}
  local bits = {}
  if c then bits[#bits + 1] = Frame.TEXT("headAct", a.roman or "") end
  bits[#bits + 1] = C.TEXT("levels", C.span(e.levelFrom, e.levelTo))
  if st.playedText then bits[#bits + 1] = st.playedText end
  bits[#bits + 1] = Frame.TEXT("headQuests", int(st.quests))
  if not c then bits[#bits + 1] = Frame.TEXT("headChapters", int(#(a.chapters or {}))) end
  local shown = scene and ((scene.mode == "zone" and View.mapName(scene.zoneID)) or (scene.contID and View.mapName(scene.contID)))
  return { title = c and C.TEXT("chapter", c.roman or int(J.sel.chapter), c.zoneName or "") or (a.title or ""),
    label = shown or nil, stats = table.concat(bits, " · ") }
end

function Frame.placeLower()
  local notes = J.map and J.map.noteList and #J.map.noteList or 0
  local G, SA, free = Frame.TIMELINE.GRID, Frame.STATIONS, Frame.LOWER_FREE
  local top = notes > 0 and G.y or Frame.NOTE.y
  if J.pb then Playback.placeGrid(J.pb, G.x, top, notes > 0 and G.rows or free.gridRows) end
  Frame.placeNotes()
  local stTop, stRows = top, notes > 0 and SA.rows or free.stationRows
  -- P3: the flight and hearthstone book takes the top of the stations' space; the stations keep the rows that still fit above
  -- the page foot (Frame.CONTENTS_BOTTOM)
  local fb = J.flightBook
  if fb and FlightBook and fb.frame:IsShown() and (fb.height or 0) > 0 then
    FlightBook.place(fb, J.over, SA.x, top)
    stTop = top + fb.height
    stRows = max(1, math.min(stRows, floor((Frame.CONTENTS_BOTTOM - stTop - Stations.HEAD_H - 4) / Stations.ROW_H)))
  end
  if J.stations and Stations then Stations.place(J.stations, J.over, SA.x, stTop, stRows) end
  -- the row count decides whether the stations page (nav + "Page x of y" at the top of the page): fit the card's sub line again
  local card = J.card
  local c = card and card.chapter
  if c and c.total and card:IsShown() and not c.unexplored then Frame.fitCardLine(card, c.subtitle or c.label or "") end
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
  Frame.followZone(Playback.mapP(J.st))
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
  Frame.followZone(Playback.mapP(J.st))
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
  Frame.followZone(p)
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

-- quest state changed or a sweep finished (journal/model/ZoneProgress.lua): redraw the zone row of the open book (no ticker)
if Journal.ZoneProgress and type(Journal.ZoneProgress.onChange) == "function" then
  Journal.ZoneProgress.onChange(function()
    if J.frame and J.frame:IsShown() and J.card and J.card:IsShown() then Frame.updateZoneRow() end
  end)
end
