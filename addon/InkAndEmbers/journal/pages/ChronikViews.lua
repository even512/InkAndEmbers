-- Chronik sub-views "Tagebuch", "Weggefährten" and "Am Feuer", opened via the sub-bookmarks (pages/Chronik.lua
-- Page.subs); Esc leads back to the overview.
-- Data: model/Days.lua + DiaryTexts.lua, model/Companions.lua, model/FireMates.lua. All foreign text goes through
-- Sanitize.display. No ticker, no OnUpdate; frames are built on first open.
local _, ns = ...

local Journal = ns.Journal
local W, Pages = Journal and Journal.Widgets, Journal and Journal.Pages
local D = W and W.Diary
if not (W and Pages and D) then return end

local floor, max, min = math.floor, math.max, math.min
local format = string.format
local unpack = unpack or table.unpack

-- grid (Theme.GRID / docs/raster.md). Left Chronik page: the wax drop top left reaches to x 127 / y 121, the small blot
-- below it to x 94 (y 128..178), seals/drop bottom left from y 472 to x 198
-- -> title, sub title and control line on the left from IN_X (column 2 + 4), text/list from the text block + 4 and only
-- down to LEFT_BOTTOM. Right page: text down to the ink splash bottom right (y 564).
local Theme = Journal.Theme
local G = Theme.GRID
local SZ = G.size
local SL, SR = {}, {}
SL.x, SL.w = Theme.gridX("L")
SR.x, SR.w = Theme.gridX("R")
local IN_X = Theme.gridX("L", 2) + 4
local IN_W = SL.x + SL.w - IN_X
local BODY_X, BODY_W = SL.x + 4, SL.w - 4          -- left content: 4 px gap to the blot at the text block
local LEFT_BOTTOM = 466                             -- left content ends above the seals bottom left
local RIGHT_BOTTOM = 560                            -- right content ends above the ink splash
local TITLE_Y = G.slots.title.y - 4                 -- handwriting head (frame) at the title position
local SUB_Y = G.slots.title.y + 34                  -- sub title

local function disp(v, n)
  local S = ns.Sanitize
  return S and S.display(v, n) or nil
end

local function int(n) return Journal.Texts.int(n) end

local function set(fs, text) W.setText(fs, text) end

local function font(parent, kind, size, color, justify)
  local fs = W.font(parent, kind, size, color)
  if justify then fs:SetJustifyH(justify) end
  return fs
end

local Diary = {}
Diary.__index = Diary
Journal.DiaryView = Diary

-- locale: one scope "p.ChronikViews.<view>" per view (English in locales/enUS_pages.lua)
Diary.TEXT = ns.Locale.ns("p.ChronikViews.Diary", {
  page = "TAGEBUCH", brand = "INK & EMBERS", prevTip = "Einen Tag zurück", nextTip = "Einen Tag weiter",
  empty = "Noch kein Eintrag", emptyBody = "Sobald Ihr unterwegs seid, schreibt sich hier jeden Tag ein Eintrag.",
  blank = "Die nächste Seite ist noch leer.", blankBody = "Was morgen passiert, steht hier, sobald es passiert ist.",
  dayPair = "Tag %s und %s von %s", dayOne = "Tag 1 von 1",
})
Diary.HEAD_SIZE, Diary.TEXT_SIZE = SZ.xl, SZ.m

-- one day: head (x, w), sub title, text (bx, bw) from the content area of the grid down to bottom. Common title height
-- of all pages (GRID.slots.title, y 66);
-- on the left the head steps aside for the wax drop by indenting (IN_X, column 2). Sub title and paging in the line
-- below, the text from DAY_TEXT_Y
local DAY_TITLE_Y = G.slots.title.y
local DAY_SUB_Y = DAY_TITLE_Y + 34
local DAY_TEXT_Y = DAY_SUB_Y + 24
local function buildDay(parent, x, w, bx, bw, bottom)
  local u = {}
  u.head = D.NewSectionHead(parent, "", { size = Diary.HEAD_SIZE, width = w })
  u.head:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -(DAY_TITLE_Y - 10))
  u.sub = font(parent, "label", SZ.s, "sepia", "LEFT")
  u.sub:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -DAY_SUB_Y)
  u.sub:SetWidth(w - 150)
  u.sub:SetWordWrap(false)
  local top = DAY_TEXT_Y
  u.tv = W.NewTextView(parent, { width = bw, height = bottom - top, size = Diary.TEXT_SIZE, spacing = 5, font = "text", color = "ink" })
  u.tv.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", bx, -top)
  return u
end

function Diary.new(page, left, right)
  local self = setmetatable({ page = page, cache = {} }, Diary)
  local T = Diary.TEXT
  local l, r = CreateFrame("Frame", nil, left), CreateFrame("Frame", nil, right)
  l:SetAllPoints(left)
  r:SetAllPoints(right)
  self.l, self.r = l, r
  local headL = W.NewPageHead(l, { side = "L" })
  headL:SetTexts(T.brand, T.page)
  local headR = W.NewPageHead(r, { side = "R" })
  headR:SetTexts("", T.page)
  D.escKeys(l, function() page:CloseSub() end) -- Esc -> overview (no back label, the sub-bookmark leads back)
  self.left = buildDay(l, IN_X, IN_W, BODY_X, BODY_W, LEFT_BOTTOM)
  self.right = buildDay(r, SR.x, SR.w - 30, SR.x, SR.w, RIGHT_BOTTOM)
  -- paging (grid): right in the sub-title line of the right page, "Tag x und y von n" directly to its left
  self.nav = D.NewNavPair(r, { onPrev = function() self:Step(-1) end, onNext = function() self:Step(1) end,
    tipPrev = { T.prevTip }, tipNext = { T.nextTip } })
  self.nav.frame:SetPoint("RIGHT", r, "TOPLEFT", SR.x + SR.w + 4, -(DAY_SUB_Y + 7))
  self.pos = font(r, "label", SZ.s, "sepia", "RIGHT")
  self.pos:SetPoint("RIGHT", self.nav.frame, "LEFT", -8, 0)
  l:Hide()
  r:Hide()
  return self
end

function Diary:IsOpen() return self.open == true end

-- entry of day i (cache per key; the newest day is rebuilt on every redraw: it is still growing)
function Diary:Entry(i)
  local d = self.days and self.days[i]
  if not d then return nil end
  local live = i == #self.days
  local e = self.cache[d.key]
  if e and not (live and self.dirty) then return e end
  local f = Journal.Days.facts(self.index, d.key, { now = self.now })
  e = f and Journal.DiaryTexts.entry(f, { dayNo = i }) or nil
  self.cache[d.key] = e
  return e
end

local function fillDay(u, e, emptyHead, emptyBody)
  if e then
    u.head:SetText(e.title)
    set(u.sub, e.sub)
    u.tv:SetText(e.body)
    u.tv.text:SetTextColor(W.color("ink"))
  else
    u.head:SetText(emptyHead)
    set(u.sub, "")
    u.tv:SetText(emptyBody)
    u.tv.text:SetTextColor(W.color("sepia"))
  end
end

function Diary:Render()
  local T = Diary.TEXT
  local n = #self.days
  if n == 0 then
    fillDay(self.left, nil, T.empty, T.emptyBody)
    fillDay(self.right, nil, T.blank, T.blankBody)
    self.nav:SetEnabled(false, false)
    set(self.pos, "")
    return
  end
  local i = self.idx
  if not i or i < 1 or i > max(1, n - 1) then i = max(1, n - 1) end
  self.idx = i
  fillDay(self.left, self:Entry(i), T.empty, T.emptyBody)
  fillDay(self.right, i + 1 <= n and self:Entry(i + 1) or nil, T.blank, T.blankBody)
  self.dirty = false
  self.nav:SetEnabled(i > 1, i + 1 < n)
  set(self.pos, n > 1 and Diary.TEXT("dayPair", int(i), int(i + 1), int(n)) or Diary.TEXT.dayOne)
end

function Diary:Step(delta)
  if not self.open then return end
  local n = #self.days
  local i = (self.idx or max(1, n - 1)) + (tonumber(delta) or 0)
  if i < 1 or i > max(1, n - 1) then return end
  self.idx = i
  self:Render()
end

function Diary:Load(index, now)
  self.index, self.now = index, now
  self.days = Journal.Days.list(index, { now = now })
  self.dirty = true
end

function Diary:Open(index, now)
  self.open = true
  self.cache = {}
  self.idx = nil
  self:Load(index, now)
  self.l:Show()
  self.r:Show()
  self:Render()
end

-- new index (played on): recount the days; a view on the newest days stays there
function Diary:Refresh(index, now)
  if not self.open then return end
  local atEnd = self.idx == nil or self.idx >= max(1, #self.days - 1)
  if index ~= self.index then self.cache = {} end
  self:Load(index, now)
  if atEnd then self.idx = nil end
  self:Render()
end

function Diary:Close()
  self.open = false
  self.l:Hide()
  self.r:Hide()
  W.hideTip(self.nav.prev)
  W.hideTip(self.nav.next)
end

local Mates = {}
Mates.__index = Mates
Journal.CompanionsView = Mates

Mates.TEXT = ns.Locale.ns("p.ChronikViews.Mates", {
  levelRange = "Stufe %s bis %s", level = "Stufe %s", date = "{d}.{m}.{y}", together = "%s zusammen",
  quests_one = "%s Quest", quests_other = "%s Quests", kills_one = "%s Kill", kills_other = "%s Kills",
  firstMet = "zuerst getroffen in %s am %s", pageOf = "Seite %s von %s", persons_one = "%s Person", persons_other = "%s Personen",
  classes = {
    WARRIOR = "Krieger", PALADIN = "Paladin", HUNTER = "Jäger", ROGUE = "Schurke", PRIEST = "Priester", DEATHKNIGHT = "Todesritter",
    SHAMAN = "Schamane", MAGE = "Magier", WARLOCK = "Hexenmeister", MONK = "Mönch", DRUID = "Druide", DEMONHUNTER = "Dämonenjäger",
    EVOKER = "Rufer",
  },
  races = {
    Human = "Mensch", Orc = "Orc", Dwarf = "Zwerg", NightElf = "Nachtelf", Scourge = "Untoter", Tauren = "Tauren", Gnome = "Gnom",
    Troll = "Troll", Goblin = "Goblin", BloodElf = "Blutelf", Draenei = "Draenei", Worgen = "Worgen", Pandaren = "Pandaren",
    Dracthyr = "Dracthyr", EarthenDwarf = "Irdener", VoidElf = "Leerenelf", Nightborne = "Nachtgeborener",
    HighmountainTauren = "Hochbergtauren", LightforgedDraenei = "Lichtgeschmiedeter", ZandalariTroll = "Zandalari",
    KulTiran = "Kul Tiraner", DarkIronDwarf = "Dunkeleisenzwerg", Vulpera = "Vulpera", MagharOrc = "Mag'har", Mechagnome = "Mechagnom",
  },
  page = "WEGGEFÄHRTEN", brand = "INK & EMBERS", title = "Weggefährten", empty = "Noch allein unterwegs.",
  emptyBody = "Wer mit Euch in einer Gruppe reist, wird hier festgehalten.", sortRecent = "zuletzt", sortLong = "am längsten",
  sortRecentTip = "Zuletzt getroffen zuerst", sortLongTip = "Längste gemeinsame Zeit zuerst", pick = "Für Details auf einen Namen klicken.",
  prevTip = "Vorige Seite", nextTip = "Nächste Seite",
  truncated = "Sehr viele Treffen: ältere sind nicht mehr vollständig.", now = "gerade in der Gruppe",
  first = "Zuerst getroffen", last = "Zuletzt gesehen", together = "Zeit zusammen", sessions = "Gemeinsame Sitzungen",
  quests = "Gemeinsame Quests", kills = "Gemeinsame Kills", deaths = "Eigene Tode dabei", unknownZone = "unbekanntem Ort",
  zones = "Gemeinsame Orte", lastQuests = "Zuletzt gemeinsam", noQuests = "Noch keine Quest zusammen abgegeben.",
})
local MT = Mates.TEXT
-- number with plural key (<key>_one / <key>_other)
local function countText(T, n, key) return T(ns.Locale.plural(n, key .. "_one", key .. "_other"), int(n)) end
Mates.ROWS, Mates.ROW_H = 6, 52   -- 6 rows down to above the seals bottom left; paging on the right in the control line

-- class colours for ink on parchment (the game colours, darkened so priest/rogue stay readable)
Mates.CLASS_COLOR = {
  WARRIOR = { 0.55, 0.38, 0.20 }, PALADIN = { 0.78, 0.33, 0.53 }, HUNTER = { 0.38, 0.52, 0.18 }, ROGUE = { 0.66, 0.54, 0.04 },
  PRIEST = { 0.40, 0.38, 0.34 }, DEATHKNIGHT = { 0.68, 0.10, 0.20 }, SHAMAN = { 0.00, 0.38, 0.74 }, MAGE = { 0.10, 0.48, 0.68 },
  WARLOCK = { 0.44, 0.38, 0.74 }, MONK = { 0.00, 0.56, 0.38 }, DRUID = { 0.82, 0.40, 0.04 }, DEMONHUNTER = { 0.55, 0.20, 0.70 },
  EVOKER = { 0.15, 0.50, 0.45 },
}
-- class and race names of the active language (looked up on read)
Mates.CLASS_NAME = setmetatable({}, { __index = function(_, k) return type(k) == "string" and MT.classes[k] or nil end })
Mates.RACE_NAME = setmetatable({}, { __index = function(_, k) return type(k) == "string" and MT.races[k] or nil end })

function Mates.classColor(class)
  return Mates.CLASS_COLOR[class] or { W.color("ink") }
end

-- class name: first the client's name (LOCALIZED_CLASS_NAMES_MALE, the companions' sex is not known), else our own table
function Mates.className(class, sex)
  -- sex 3 = female (campfire guests have a sex): then the client's female form, else the male one.
  -- Client names only if the game language matches the chosen one (else German names would show in the English book)
  local names = ns.Locale.matchesClient() and type(LOCALIZED_CLASS_NAMES_MALE) == "table" and LOCALIZED_CLASS_NAMES_MALE or nil
  if names and sex == 3 and type(LOCALIZED_CLASS_NAMES_FEMALE) == "table" then names = LOCALIZED_CLASS_NAMES_FEMALE end
  local n = names and type(class) == "string" and names[class]
  if type(n) == "string" and n ~= "" then return disp(n, 24) end
  return Mates.CLASS_NAME[class]
end

-- "Orc-Krieger" or the sanitized raw values if no translation is known; nil if nothing readable
function Mates.kindText(p)
  local race = Mates.RACE_NAME[p.race] or disp(p.race, 24)
  local cls = Mates.className(p.class) or disp(p.class, 24)
  if race and cls then return race .. " · " .. cls end
  return race or cls
end

local function levelText(p)
  local a, b = tonumber(p.level0), tonumber(p.level1)
  if a and b and a ~= b then return MT("levelRange", int(a), int(b)) end
  if b or a then return MT("level", int(b or a)) end
  return nil
end

-- date in the active language's format ("28.10.2026" | "10/28/2026")
local function dateText(index, t)
  local d, m, y = Journal.Index.dateOf(index, t)
  if not d then return "?" end
  return MT("date", { d = format("%02d", d), m = format("%02d", m), y = format("%04d", y) })
end

function Mates:DateText(t)
  return dateText(self.index, t)
end

local function duration(seconds)
  return Journal.DiaryTexts.duration(seconds) or ""
end

-- line "8 min zusammen · 2 Quests · 14 Kills"; zero values are dropped
function Mates.statsText(p)
  local parts = { MT("together", duration(p.seconds)) }
  local q, k = tonumber(p.quests) or 0, tonumber(p.kills) or 0
  if q > 0 then parts[#parts + 1] = countText(MT, q, "quests") end
  if k > 0 then parts[#parts + 1] = countText(MT, k, "kills") end
  return table.concat(parts, " · ")
end

-- display-ready texts of a person (all foreign values via Sanitize.display)
function Mates:Lines(p)
  local T = Mates.TEXT
  local name = disp(p.name, 48) or "?"
  local zone = disp(p.firstZone, 40) or T.unknownZone
  local out = {
    name = name,
    level = levelText(p) or "",
    kind = Mates.kindText(p),
    first = MT("firstMet", zone, self:DateText(p.firstT)),
    stats = Mates.statsText(p),
    lastZone = disp(p.lastZone, 40),
  }
  return out
end

function Mates:Tip(p)
  local T = Mates.TEXT
  local s = self:Lines(p)
  local lines = { s.name }
  if s.kind or s.level ~= "" then lines[#lines + 1] = table.concat({ s.kind or "", s.level }, (s.kind and s.level ~= "") and " · " or "") end
  lines[#lines + 1] = T.first .. ": " .. self:DateText(p.firstT) .. (disp(p.firstZone, 40) and (", " .. disp(p.firstZone, 40)) or "")
  lines[#lines + 1] = T.last .. ": " .. (p.active and T.now or (self:DateText(p.lastT) .. (s.lastZone and (", " .. s.lastZone) or "")))
  lines[#lines + 1] = T.together .. ": " .. duration(p.seconds)
  if (tonumber(p.sessions) or 0) > 1 then lines[#lines + 1] = T.sessions .. ": " .. int(p.sessions) end
  local qk = {}
  if (tonumber(p.quests) or 0) > 0 then qk[#qk + 1] = T.quests .. ": " .. int(p.quests) end
  if (tonumber(p.kills) or 0) > 0 then qk[#qk + 1] = T.kills .. ": " .. int(p.kills) end
  if #qk > 0 then lines[#lines + 1] = table.concat(qk, " · ") end
  if (tonumber(p.deaths) or 0) > 0 then lines[#lines + 1] = T.deaths .. ": " .. int(p.deaths) end
  return lines, { Mates.classColor(p.class) }
end

local function buildRow(self, row)
  local nm = font(row, "title", SZ.m, "ink", "LEFT")
  nm:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)
  nm:SetWidth(BODY_W - 120)
  nm:SetWordWrap(false)
  local lv = font(row, "label", SZ.s, "sepia", "RIGHT")
  lv:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6)
  lv:SetWidth(110)
  local first = font(row, "label", SZ.s, "sepia", "LEFT")
  first:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -23)
  first:SetWidth(BODY_W - 16)
  first:SetWordWrap(false)
  local stats = font(row, "label", SZ.s, "ink", "LEFT")
  stats:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -37)
  stats:SetWidth(BODY_W - 16)
  stats:SetWordWrap(false)
  row.label:SetText("")
  row.name, row.lv, row.first, row.stats = nm, lv, first, stats
  -- set own hover scripts before RowStyle: RowStyle hooks in behind them with HookScript (hover red, selection frame)
  row:SetScript("OnEnter", function(r)
    if r.person then
      local lines, colors = self:Tip(r.person)
      W.tip(r, lines, colors)
    end
  end)
  row:SetScript("OnLeave", function(r) W.hideTip(r) end)
  D.RowStyle(row, { texts = { stats } })
end

function Mates.new(page, left, right)
  local self = setmetatable({ page = page, sort = "recent" }, Mates)
  local T = Mates.TEXT
  local l, r = CreateFrame("Frame", nil, left), CreateFrame("Frame", nil, right)
  l:SetAllPoints(left)
  r:SetAllPoints(right)
  self.l, self.r = l, r
  W.NewPageHead(l, { side = "L" }):SetTexts(T.brand, T.page)
  W.NewPageHead(r, { side = "R" }):SetTexts("", T.page)
  D.escKeys(l, function() page:CloseSub() end) -- Esc -> overview
  local head = D.NewSectionHead(l, T.title, { size = SZ.xl })
  head:SetPoint("TOPLEFT", l, "TOPLEFT", IN_X, -(TITLE_Y - 6))
  self.count = font(l, "label", SZ.s, "sepia", "LEFT")
  self.count:SetPoint("TOPLEFT", l, "TOPLEFT", IN_X, -SUB_Y)
  -- control line (grid): sort left (toggle), paging right ("Seite x von y" + arrow pair)
  local cy = -(G.slots.ctrl.y + G.slots.ctrl.h / 2)
  self.toggle = D.NewToggle(l, { size = SZ.m, gap = 12, value = "recent",
    items = { { key = "recent", label = T.sortRecent, tip = { T.sortRecentTip } }, { key = "minutes", label = T.sortLong, tip = { T.sortLongTip } } },
    onChange = function(key) self:SetSort(key) end })
  self.toggle.frame:SetPoint("LEFT", l, "TOPLEFT", IN_X - 3, cy)
  self.nav = D.NewNavPair(l, { onPrev = function() self:Page(-1) end, onNext = function() self:Page(1) end,
    tipPrev = { T.prevTip }, tipNext = { T.nextTip } })
  self.nav.frame:SetPoint("RIGHT", l, "TOPLEFT", SL.x + SL.w + 4, cy)
  self.pos = font(l, "label", SZ.s, "sepia", "RIGHT")
  self.pos:SetPoint("RIGHT", self.nav.frame, "LEFT", -6, 0)
  self.list = W.NewList(l, { rows = Mates.ROWS, rowHeight = Mates.ROW_H, width = BODY_W, empty = T.empty, emptyHand = true,
    build = function(row) buildRow(self, row) end,
    clear = function(row)
      row.person = nil
      for _, k in ipairs({ "name", "lv", "first", "stats" }) do set(row[k], "") end
      if row.SetSelected then row:SetSelected(false) end
      W.hideTip(row)
    end,
    fill = function(row, p)
      row.person = p
      local s = self:Lines(p)
      set(row.name, s.name)
      row.name:SetTextColor(unpack(Mates.classColor(p.class)))
      set(row.lv, s.level)
      set(row.first, s.first)
      set(row.stats, s.stats)
      if row.SetSelected then row:SetSelected(self.sel ~= nil and self.sel == p.name) end
      D.rowFilled(row)
    end,
    onClick = function(p) self:Select(p) end })
  self.list.frame:SetPoint("TOPLEFT", l, "TOPLEFT", BODY_X, -G.slots.body.y)
  -- page display follows every refill of the list (arrows, mouse wheel, bar)
  local refresh = self.list.Refresh
  self.list.Refresh = function(list)
    refresh(list)
    self:UpdatePager()
  end
  -- note "very many encounters": footer, flush with the fold (seals sit bottom left)
  self.note = font(l, "label", SZ.xs, "sepia", "RIGHT")
  local pt, fx, fy = Theme.gridFoot("L")
  self.note:SetPoint(pt, l, "TOPLEFT", fx, -(fy + 6))
  self.note:SetWidth(SL.x + SL.w - Theme.gridX("L", 4))

  local u = {}
  -- right: profile of the selected person (title/sub title on the grid, lines from the content area)
  u.name = font(r, "title", SZ.xl, "ink", "LEFT")
  u.name:SetPoint("TOPLEFT", r, "TOPLEFT", SR.x, -G.slots.title.y)
  u.name:SetWidth(SR.w - 30)
  u.name:SetWordWrap(false)
  u.kind = font(r, "text", SZ.s, "sepia", "LEFT")
  u.kind:SetPoint("TOPLEFT", r, "TOPLEFT", SR.x, -SUB_Y)
  u.kind:SetWidth(SR.w)
  u.leads = {}
  for i, key in ipairs({ "first", "last", "together", "sessions", "quests", "kills", "deaths" }) do
    local y = -G.slots.body.y - (i - 1) * 28
    local k = font(r, "label", SZ.s, "sepia", "LEFT")
    k:SetPoint("TOPLEFT", r, "TOPLEFT", SR.x, y)
    set(k, T[key])
    local v = font(r, "title", SZ.m, "ink", "RIGHT")
    v:SetPoint("TOPRIGHT", r, "TOPLEFT", SR.x + SR.w, y + 1)
    v:SetWidth(SR.w - 170)
    v:SetWordWrap(false)
    u.leads[key] = { k = k, v = v }
  end
  -- hint/empty state in handwriting
  u.hint = D.emptyNote(r, SR.w - 40)
  u.hint:SetPoint("TOP", r, "TOPLEFT", SR.x + SR.w / 2, -(G.slots.body.y + 40))
  -- below it shared places (left) and the latest shared quests (right), up to 4 lines each
  local half = floor((SR.w - 16) / 2)
  u.blocks = {}
  for i, key in ipairs({ "zones", "lastQuests" }) do
    local bx = SR.x + (i - 1) * (half + 16)
    local head = D.NewSectionHead(r, T[key], { width = half, size = 18 })
    local lines = {}
    for j = 1, 4 do
      local fs = font(r, "text", SZ.s, "ink", "LEFT")
      fs:SetWidth(half)
      fs:SetWordWrap(false)
      lines[j] = fs
    end
    u.blocks[key] = { head = head, lines = lines, x = bx }
  end
  self.card = u
  l:Hide()
  r:Hide()
  return self
end

function Mates:IsOpen() return self.open == true end

-- page by page (Mates.ROWS rows per page); "Seite x von y" follows the list offset
function Mates:Page(delta)
  local list = self.list
  if not list then return end
  list:SetOffset(list:GetOffset() + (tonumber(delta) or 0) * Mates.ROWS)
end

function Mates:UpdatePager()
  local list = self.list
  if not (list and self.nav) then return end
  local n = #(list.items or {})
  local pages = max(1, math.ceil(n / Mates.ROWS))
  local off = list:GetOffset()
  local p = (off >= list:MaxOffset()) and pages or min(pages, floor(off / Mates.ROWS) + 1)
  self.nav:SetEnabled(off > 0, off < list:MaxOffset())
  self.nav.frame:SetShown(pages > 1)
  set(self.pos, pages > 1 and MT("pageOf", int(p), int(pages)) or "")
end

function Mates:SetSort(key)
  self.sort = key == "minutes" and "minutes" or "recent"
  self.toggle:SetValue(self.sort)
  self.list:SetOffset(0)
  self:Render()
end

function Mates:Select(p)
  self.sel = p and p.name or nil
  self.list:Refresh()
  self:RenderCard()
end

function Mates:RenderCard()
  local T, u = Mates.TEXT, self.card
  local p
  for _, x in ipairs(self.items or {}) do if x.name == self.sel then p = x end end
  local show = p ~= nil
  for _, l in pairs(u.leads) do
    l.k:SetShown(show)
    l.v:SetShown(show)
  end
  for _, b in pairs(u.blocks) do
    b.head:SetShown(show)
    for _, fs in ipairs(b.lines) do set(fs, "") end
  end
  if not p then
    set(u.name, "")
    set(u.kind, "")
    set(u.hint, (#(self.items or {}) == 0) and T.emptyBody or T.pick)
    return
  end
  set(u.hint, "")
  local s = self:Lines(p)
  set(u.name, s.name)
  u.name:SetTextColor(unpack(Mates.classColor(p.class)))
  local kind = s.kind or ""
  set(u.kind, (kind ~= "" and s.level ~= "") and (kind .. " · " .. s.level) or (kind .. s.level))
  local fz = disp(p.firstZone, 40)
  set(u.leads.first.v, self:DateText(p.firstT) .. (fz and (", " .. fz) or ""))
  set(u.leads.last.v, p.active and T.now or (self:DateText(p.lastT) .. (s.lastZone and (", " .. s.lastZone) or "")))
  set(u.leads.together.v, duration(p.seconds))
  set(u.leads.sessions.v, int(p.sessions or 0))
  set(u.leads.quests.v, int(p.quests or 0))
  set(u.leads.kills.v, int(p.kills or 0))
  set(u.leads.deaths.v, int(p.deaths or 0))
  -- drop zero values (one session is a given), the other lines move up
  local hide = { sessions = (tonumber(p.sessions) or 0) <= 1, quests = (tonumber(p.quests) or 0) <= 0,
    kills = (tonumber(p.kills) or 0) <= 0, deaths = (tonumber(p.deaths) or 0) <= 0 }
  local row = 0
  for _, key in ipairs({ "first", "last", "together", "sessions", "quests", "kills", "deaths" }) do
    local l = u.leads[key]
    if hide[key] then
      l.k:Hide()
      l.v:Hide()
    else
      local y = -G.slots.body.y - row * 28
      l.k:ClearAllPoints()
      l.k:SetPoint("TOPLEFT", self.r, "TOPLEFT", SR.x, y)
      l.v:ClearAllPoints()
      l.v:SetPoint("TOPRIGHT", self.r, "TOPLEFT", SR.x + SR.w, y + 1)
      row = row + 1
    end
  end
  -- shared places and quests below the lines
  local det = Journal.Companions.detail and Journal.Companions.detail(self.index, p, 4) or { zones = {}, quests = {} }
  local top = G.slots.body.y + row * 28 + 14
  for key, list in pairs({ zones = det.zones, lastQuests = det.quests }) do
    local b = u.blocks[key]
    b.head:ClearAllPoints()
    b.head:SetPoint("TOPLEFT", self.r, "TOPLEFT", b.x, -top)
    if #list == 0 and key == "zones" then b.head:Hide() end
    if #list == 0 and key == "lastQuests" then set(b.lines[1], T.noQuests) end
    for j, fs in ipairs(b.lines) do
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", self.r, "TOPLEFT", b.x, -(top + 30 + (j - 1) * G.line.text))
      if list[j] then set(fs, disp(list[j], 40) or "") end
      W.fitLine(fs, fs:GetWidth()) -- "Noch keine Quest zusammen abgegeben." etc.: the font shrinks before the "..."
    end
  end
end

function Mates:Render()
  local res = self.res
  self.items = Journal.Companions.sorted(res, self.sort)
  local n = #self.items
  set(self.count, n == 0 and "" or countText(MT, n, "persons"))
  self.toggle.frame:SetShown(n > 1) -- sort only when there is something to sort
  set(self.note, (res and res.truncated) and Mates.TEXT.truncated or "")
  if self.sel == nil and n > 0 then self.sel = self.items[1].name end
  self.list:SetItems(self.items)
  self.list:Refresh()
  self:RenderCard()
end

function Mates:Open(index, now)
  self.open = true
  self.index = index
  self.res = Journal.Companions.aggregate(index, { now = now }) or { list = {}, count = 0 }
  self.l:Show()
  self.r:Show()
  self:Render()
end

function Mates:Refresh(index, now)
  if not self.open then return end
  self.index = index
  self.res = Journal.Companions.aggregate(index, { now = now }) or { list = {}, count = 0 }
  self:Render()
end

function Mates:Close()
  self.open = false
  self.l:Hide()
  self.r:Hide()
  for _, row in ipairs(self.list.rows) do W.hideTip(row) end
  for _, b in ipairs(self.toggle.buttons) do W.hideTip(b) end
  W.hideTip(self.nav.prev)
  W.hideTip(self.nav.next)
end

-- Companions at the fire: like "Weggefährten" but for the people from the campfire (log line LF, model/FireMates.lua):
-- sort "zuletzt" / "am häufigsten", profile of the selected person with their latest fires. Also the tooltip of the
-- diary entries "Am Lagerfeuer in <Zone> mit ..." (Fire.entryTip).
-- Trial rounds (retail simulation) carry "(Probe)". A running round (ns.Campfire.session()) shows as "läuft gerade"
-- with its guests first (FireMates.withLive); with the view open, ns.onCampfire redraws at once, the end fetches the
-- new index (Pages.refresh).

local Fire = {}
Fire.__index = Fire
Journal.FireMatesView = Fire

Fire.TEXT = ns.Locale.ns("p.ChronikViews.Fire", {
  page = "AM FEUER", brand = "INK & EMBERS", title = "Weggefährten am Feuer", empty = "Noch kein Feuer geteilt.",
  emptyBody = "Setzt Euch an ein Lagerfeuer: Wer eine Weile mit Euch dort verweilt, wird hier festgehalten.",
  sortRecent = "zuletzt", sortCount = "am häufigsten", sortRecentTip = "Zuletzt am Feuer gesehen zuerst",
  sortCountTip = "Meiste gemeinsame Feuer zuerst", pick = "Für Details auf einen Namen klicken.",
  prevTip = "Vorige Seite", nextTip = "Nächste Seite", truncated = "Sehr viele Gäste: ältere sind nicht mehr aufgeführt.",
  fires = "Gemeinsame Feuer", first = "Zuerst am Feuer", last = "Zuletzt am Feuer", visits = "Die letzten Feuer",
  unknownZone = "unbekanntem Ort", tipMore = "und %s weitere", oneFire = "1 Feuer", manyFires = "%s Feuer",
  level = "Stufe %s", lastIn = "zuletzt in %s am %s", lastAt = "zuletzt am %s",
  probe = " (Probe)", live = "läuft gerade", liveIn = "läuft gerade in %s", liveRound = "Runde läuft gerade",
})
Fire.ROWS, Fire.ROW_H = Mates.ROWS, Mates.ROW_H
Fire.VISITS_MAX = 6

function Fire.fireCount(n)
  n = tonumber(n) or 0
  return n == 1 and Fire.TEXT.oneFire or Fire.TEXT("manyFires", int(n))
end

-- "Orc · Krieger" with the class form by sex (sex 3 = female) if the client knows it
function Fire.kindText(p)
  local race = Mates.RACE_NAME[p.race] or disp(p.race, 24)
  local cls = Mates.className(p.class, p.sex) or disp(p.class, 24)
  if race and cls then return race .. " · " .. cls end
  return race or cls
end

-- a person in the diary entry tooltip: "Kuno · Orc · Krieger · Stufe 12" (raw values from the log, all via display)
function Fire.personLine(p)
  local raw = p.name or p.full
  local first = type(raw) == "string" and (string.match(raw, "^([^%-]+)") or raw) or nil
  local parts = { disp(first, 48) or "?" }
  local kind = Fire.kindText(p)
  if kind then parts[#parts + 1] = kind end
  local lv = tonumber(p.level)
  if lv then parts[#parts + 1] = Fire.TEXT("level", int(lv)) end
  return table.concat(parts, " · ")
end

-- tooltip of a diary entry "Am Lagerfeuer ...": time, sentence, then one line per person in class colour
function Fire.entryTip(e, text)
  local ctx = type(e) == "table" and e.ctx
  if type(ctx) ~= "table" or type(ctx.people) ~= "table" or #ctx.people == 0 then return nil end
  local lines, colors = { e.clock or "", text or "" }, {}
  for _, p in ipairs(ctx.people) do
    lines[#lines + 1] = Fire.personLine(p)
    colors[#lines] = Mates.classColor(p.class)
  end
  local more = (tonumber(ctx.n) or #ctx.people) - #ctx.people
  if more > 0 then lines[#lines + 1] = Fire.TEXT("tipMore", int(more)) end
  return lines, colors
end

function Fire:DateText(t)
  return dateText(self.index, t)
end

local function levelOf(p)
  local lv = tonumber(p.level)
  return lv and Fire.TEXT("level", int(lv)) or ""
end

-- display-ready texts of a person
function Fire:Lines(p)
  local T = Fire.TEXT
  if p.live then
    local lz = disp(p.liveZone, 40)
    return {
      name = disp(p.name or p.full, 48) or "?",
      level = levelOf(p),
      kind = Fire.kindText(p),
      fires = Fire.fireCount(p.n),
      last = (lz and T("liveIn", lz) or T.live) .. (p.liveSim and T.probe or ""),
      lastZone = lz,
      lastText = T.live .. (p.liveSim and T.probe or ""),
    }
  end
  local zone = disp(p.lastZone, 40)
  local probe = p.lastSim and T.probe or ""
  return {
    name = disp(p.name or p.full, 48) or "?",
    level = levelOf(p),
    kind = Fire.kindText(p),
    fires = Fire.fireCount(p.n),
    last = (zone and Fire.TEXT("lastIn", zone, self:DateText(p.lastT)) or Fire.TEXT("lastAt", self:DateText(p.lastT))) .. probe,
    lastZone = zone,
    lastText = self:DateText(p.lastT) .. (zone and (", " .. zone) or "") .. probe,
  }
end

function Fire:Tip(p)
  local T = Fire.TEXT
  local s = self:Lines(p)
  local lines = { s.name }
  if s.kind or s.level ~= "" then lines[#lines + 1] = table.concat({ s.kind or "", s.level }, (s.kind and s.level ~= "") and " · " or "") end
  lines[#lines + 1] = T.fires .. ": " .. int(p.n or 0)
  local fz = disp(p.firstZone, 40)
  lines[#lines + 1] = T.first .. ": " .. self:DateText(p.firstT) .. (fz and (", " .. fz) or "")
  lines[#lines + 1] = T.last .. ": " .. s.lastText
  return lines, { Mates.classColor(p.class) }
end

local function buildFireRow(self, row)
  local nm = font(row, "title", SZ.m, "ink", "LEFT")
  nm:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)
  nm:SetWidth(BODY_W - 120)
  nm:SetWordWrap(false)
  local lv = font(row, "label", SZ.s, "sepia", "RIGHT")
  lv:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6)
  lv:SetWidth(110)
  local kind = font(row, "label", SZ.s, "sepia", "LEFT")
  kind:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -23)
  kind:SetWidth(BODY_W - 16)
  kind:SetWordWrap(false)
  local stats = font(row, "label", SZ.s, "ink", "LEFT")
  stats:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -37)
  stats:SetWidth(BODY_W - 16)
  stats:SetWordWrap(false)
  row.label:SetText("")
  row.name, row.lv, row.kind, row.stats = nm, lv, kind, stats
  -- set own hover scripts before RowStyle (RowStyle hooks in behind them with HookScript)
  row:SetScript("OnEnter", function(r)
    if r.person then
      local lines, colors = self:Tip(r.person)
      W.tip(r, lines, colors)
    end
  end)
  row:SetScript("OnLeave", function(r) W.hideTip(r) end)
  D.RowStyle(row, { texts = { stats } })
end

function Fire.new(page, left, right)
  local self = setmetatable({ page = page, sort = "recent" }, Fire)
  local T = Fire.TEXT
  local l, r = CreateFrame("Frame", nil, left), CreateFrame("Frame", nil, right)
  l:SetAllPoints(left)
  r:SetAllPoints(right)
  self.l, self.r = l, r
  W.NewPageHead(l, { side = "L" }):SetTexts(T.brand, T.page)
  W.NewPageHead(r, { side = "R" }):SetTexts("", T.page)
  D.escKeys(l, function() page:CloseSub() end) -- Esc -> overview
  local head = D.NewSectionHead(l, T.title, { size = SZ.xl })
  head:SetPoint("TOPLEFT", l, "TOPLEFT", IN_X, -(TITLE_Y - 6))
  self.count = font(l, "label", SZ.s, "sepia", "LEFT")
  self.count:SetPoint("TOPLEFT", l, "TOPLEFT", IN_X, -SUB_Y)
  local cy = -(G.slots.ctrl.y + G.slots.ctrl.h / 2)
  self.toggle = D.NewToggle(l, { size = SZ.m, gap = 12, value = "recent",
    items = { { key = "recent", label = T.sortRecent, tip = { T.sortRecentTip } }, { key = "count", label = T.sortCount, tip = { T.sortCountTip } } },
    onChange = function(key) self:SetSort(key) end })
  self.toggle.frame:SetPoint("LEFT", l, "TOPLEFT", IN_X - 3, cy)
  self.nav = D.NewNavPair(l, { onPrev = function() self:Page(-1) end, onNext = function() self:Page(1) end,
    tipPrev = { T.prevTip }, tipNext = { T.nextTip } })
  self.nav.frame:SetPoint("RIGHT", l, "TOPLEFT", SL.x + SL.w + 4, cy)
  self.pos = font(l, "label", SZ.s, "sepia", "RIGHT")
  self.pos:SetPoint("RIGHT", self.nav.frame, "LEFT", -6, 0)
  self.list = W.NewList(l, { rows = Fire.ROWS, rowHeight = Fire.ROW_H, width = BODY_W, empty = T.empty, emptyHand = true,
    build = function(row) buildFireRow(self, row) end,
    clear = function(row)
      row.person = nil
      for _, k in ipairs({ "name", "lv", "kind", "stats" }) do set(row[k], "") end
      if row.SetSelected then row:SetSelected(false) end
      W.hideTip(row)
    end,
    fill = function(row, p)
      row.person = p
      local s = self:Lines(p)
      set(row.name, s.name)
      row.name:SetTextColor(unpack(Mates.classColor(p.class)))
      set(row.lv, s.level)
      set(row.kind, s.kind or "")
      set(row.stats, s.fires .. " · " .. s.last)
      if row.SetSelected then row:SetSelected(self.sel ~= nil and self.sel == p.key) end
      D.rowFilled(row)
    end,
    onClick = function(p) self:Select(p) end })
  self.list.frame:SetPoint("TOPLEFT", l, "TOPLEFT", BODY_X, -G.slots.body.y)
  local refresh = self.list.Refresh
  self.list.Refresh = function(list)
    refresh(list)
    self:UpdatePager()
  end
  self.note = font(l, "label", SZ.xs, "sepia", "RIGHT")
  local pt, fx, fy = Theme.gridFoot("L")
  self.note:SetPoint(pt, l, "TOPLEFT", fx, -(fy + 6))
  self.note:SetWidth(SL.x + SL.w - Theme.gridX("L", 4))

  -- right page: profile of the selected person
  local u = {}
  u.name = font(r, "title", SZ.xl, "ink", "LEFT")
  u.name:SetPoint("TOPLEFT", r, "TOPLEFT", SR.x, -G.slots.title.y)
  u.name:SetWidth(SR.w - 30)
  u.name:SetWordWrap(false)
  u.kind = font(r, "text", SZ.s, "sepia", "LEFT")
  u.kind:SetPoint("TOPLEFT", r, "TOPLEFT", SR.x, -SUB_Y)
  u.kind:SetWidth(SR.w)
  u.leads = {}
  for i, key in ipairs({ "fires", "first", "last" }) do
    local y = -G.slots.body.y - (i - 1) * 28
    local k = font(r, "label", SZ.s, "sepia", "LEFT")
    k:SetPoint("TOPLEFT", r, "TOPLEFT", SR.x, y)
    set(k, T[key])
    local v = font(r, "title", SZ.m, "ink", "RIGHT")
    v:SetPoint("TOPRIGHT", r, "TOPLEFT", SR.x + SR.w, y + 1)
    v:SetWidth(SR.w - 170)
    v:SetWordWrap(false)
    u.leads[key] = { k = k, v = v }
  end
  u.hint = D.emptyNote(r, SR.w - 40)
  u.hint:SetPoint("TOP", r, "TOPLEFT", SR.x + SR.w / 2, -(G.slots.body.y + 40))
  -- below it the latest fires of this person (date · zone · level), newest first
  local vy = G.slots.body.y + 3 * 28 + 14
  u.visitsHead = D.NewSectionHead(r, T.visits, { width = SR.w, size = 18 })
  u.visitsHead:SetPoint("TOPLEFT", r, "TOPLEFT", SR.x, -vy)
  u.visits = {}
  for j = 1, Fire.VISITS_MAX do
    local fs = font(r, "text", SZ.s, "ink", "LEFT")
    fs:SetWidth(SR.w)
    fs:SetWordWrap(false)
    fs:SetPoint("TOPLEFT", r, "TOPLEFT", SR.x, -(vy + 30 + (j - 1) * G.line.text))
    u.visits[j] = fs
  end
  self.card = u
  l:Hide()
  r:Hide()
  return self
end

function Fire:IsOpen() return self.open == true end

function Fire:Page(delta)
  local list = self.list
  if not list then return end
  list:SetOffset(list:GetOffset() + (tonumber(delta) or 0) * Fire.ROWS)
end

function Fire:UpdatePager()
  local list = self.list
  if not (list and self.nav) then return end
  local n = #(list.items or {})
  local pages = max(1, math.ceil(n / Fire.ROWS))
  local off = list:GetOffset()
  local p = (off >= list:MaxOffset()) and pages or min(pages, floor(off / Fire.ROWS) + 1)
  self.nav:SetEnabled(off > 0, off < list:MaxOffset())
  self.nav.frame:SetShown(pages > 1)
  set(self.pos, pages > 1 and MT("pageOf", int(p), int(pages)) or "")
end

function Fire:SetSort(key)
  self.sort = key == "count" and "count" or "recent"
  self.toggle:SetValue(self.sort)
  self.list:SetOffset(0)
  self:Render()
end

function Fire:Select(p)
  self.sel = p and p.key or nil
  self.list:Refresh()
  self:RenderCard()
end

function Fire:RenderCard()
  local T, u = Fire.TEXT, self.card
  local p
  for _, x in ipairs(self.items or {}) do if x.key == self.sel then p = x end end
  local show = p ~= nil
  for _, l in pairs(u.leads) do
    l.k:SetShown(show)
    l.v:SetShown(show)
  end
  u.visitsHead:SetShown(show)
  for _, fs in ipairs(u.visits) do set(fs, "") end
  if not p then
    set(u.name, "")
    set(u.kind, "")
    set(u.hint, (#(self.items or {}) == 0) and T.emptyBody or T.pick)
    return
  end
  set(u.hint, "")
  local s = self:Lines(p)
  set(u.name, s.name)
  u.name:SetTextColor(unpack(Mates.classColor(p.class)))
  local kind = s.kind or ""
  set(u.kind, (kind ~= "" and s.level ~= "") and (kind .. " · " .. s.level) or (kind .. s.level))
  set(u.leads.fires.v, int(p.n or 0))
  local fz = disp(p.firstZone, 40)
  set(u.leads.first.v, self:DateText(p.firstT) .. (fz and (", " .. fz) or ""))
  set(u.leads.last.v, s.lastText)
  -- the latest fires, newest first (up to VISITS_MAX)
  local n = #(p.visits or {})
  for j = 1, min(n, Fire.VISITS_MAX) do
    local v = p.visits[n - j + 1]
    local parts = { self:DateText(v.t), disp(v.zone, 40) or T.unknownZone }
    if tonumber(v.level) then parts[#parts + 1] = Fire.TEXT("level", int(v.level)) end
    set(u.visits[j], table.concat(parts, " · ") .. (v.sim and T.probe or ""))
  end
end

function Fire:Render()
  local res = self.res
  self.items = Journal.FireMates.sorted(res, self.sort)
  local n = #self.items
  local fires = res and tonumber(res.rounds) or 0
  local count = n == 0 and "" or (countText(MT, n, "persons") .. " · " .. Fire.fireCount(fires))
  local live = res and res.live
  if live then
    local T = Fire.TEXT
    count = count .. (count ~= "" and " · " or "") .. T.liveRound .. (live.sim and T.probe or "")
  end
  set(self.count, count)
  self.toggle.frame:SetShown(n > 1)
  set(self.note, (res and res.truncated) and Fire.TEXT.truncated or "")
  local found = false
  for _, x in ipairs(self.items) do if x.key == self.sel then found = true end end
  if not found then self.sel = n > 0 and self.items[1].key or nil end
  self.list:SetItems(self.items)
  self.list:Refresh()
  self:RenderCard()
end

function Fire:Load(index)
  self.index = index
  local FM = Journal.FireMates
  local res = FM.aggregate(index) or { list = {}, count = 0, rounds = 0 }
  local C = ns.Campfire
  local ok, live = pcall(function() return C and C.session and C.session() end)
  self.res = FM.withLive(res, ok and live or nil)
end

function Fire:Open(index)
  self.open = true
  self:Load(index)
  self.l:Show()
  self.r:Show()
  self:Render()
end

function Fire:Refresh(index)
  if not self.open then return end
  self:Load(index)
  self:Render()
end

-- a campfire round starts/changes/ends while the view is open: redraw at once; the end wrote a new LF line, so fetch fresh data
-- (Pages.refresh: old state at once, the new one via onReady after the background build).
function Fire.onCampfire(what)
  local pg = Journal.ChronikPage
  local v = pg and pg.fireView
  if not (v and v:IsOpen()) or (what ~= "start" and what ~= "update" and what ~= "end") then return end
  if what == "end" and Pages and type(Pages.refresh) == "function" then
    Pages.refresh()
  else
    v:Refresh(v.index)
  end
end
if type(ns.onCampfire) == "function" then
  ns.onCampfire(function(what)
    local ok, err = pcall(Fire.onCampfire, what)
    if not ok and Pages and type(Pages.fail) == "function" then Pages.fail("chronik", err) end
  end)
end

function Fire:Close()
  self.open = false
  self.l:Hide()
  self.r:Hide()
  for _, row in ipairs(self.list.rows) do W.hideTip(row) end
  for _, b in ipairs(self.toggle.buttons) do W.hideTip(b) end
  W.hideTip(self.nav.prev)
  W.hideTip(self.nav.next)
end

-- Retail: the campfire talk never starts there (MapSpace.fireTalkHidden), so the bookmark "Am Feuer" stays out of the Chronik tab
Pages.hideSub("chronik", "feuer", function()
  local ms = Journal.MapSpace
  return ms ~= nil and ms.fireTalkHidden() == true
end)
