-- Chronik sub-view "Meilensteine" (WoW Forever), opened via the sub-bookmark (pages/Chronik.lua Page.subs); Esc leads back to the
-- overview. Data: model/Meilensteine.lua (every ten levels a tally, plus the closing page of the whole journey), the narrator line
-- from journal/Meilenstein.lua (one fixed variant per section, so the page never flickers). Left: the sections "Stufe 1–10" ...
-- "50–60" and "Abschluss" (reached in ink with date and time, the running one with its numbers so far, the coming ones pale);
-- right: the chosen section as a book page (narrator line, then the plain numbers; empty values are left out). The closing page
-- is made only of existing material: narrator portrait in the gold medal ring (Narrator_/NarratorBG_<race>, SealFrames), a strip
-- of diary tape, six columns (time per section) in the style of the level flow. At most seven entries: no paging, no row pool.
-- Nothing is cut off with "...": the narrator text is shown whole (the page flows: sub line -> text -> numbers -> columns; the text
-- font shrinks step by step before anything is dropped), long values shrink and then wrap to two lines, the zone list falls back to
-- "N" with the full list in the tooltip; whatever stays too wide for its place shows its full text on hover.
-- Works with another character's index (guest book, read only). Foreign text (zone, item, player names) only via
-- Sanitize.display. No ticker, no OnUpdate; frames are built on first open.
local _, ns = ...

local Journal = ns.Journal
local W, Pages = Journal and Journal.Widgets, Journal and Journal.Pages
local D = W and W.Diary
local M = Journal and Journal.Meilensteine
if not (W and Pages and D and M) then return end

local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil
local format = string.format
local unpack = unpack or table.unpack

-- grid as in pages/ChronikDungeons.lua (docs/raster.md)
local Theme = Journal.Theme
local G = Theme.GRID
local SZ = G.size
local SL, SR = {}, {}
SL.x, SL.w = Theme.gridX("L")
SR.x, SR.w = Theme.gridX("R")
local IN_X = Theme.gridX("L", 2) + 4
local BODY_X, BODY_W = SL.x + 4, SL.w - 4
local TITLE_Y = G.slots.title.y - 4
local SUB_Y = G.slots.title.y + 34

local View = {}
View.__index = View
Journal.MilestonesView = View

View.TEXT = ns.Locale.ns("p.ChronikMeilensteine", {
  page = "MEILENSTEINE", brand = "INK & EMBERS", title = "Meilensteine",
  reachedOf = "%s von %s erreicht", range = "Stufe %s–%s", final = "Abschluss", finalSub = "Die ganze Reise · Stufe 1–%s",
  date = "{d}.{m}.{y}", dateRange = "{from} – {to}", running = "läuft", runningSince = "läuft seit {date}", open = "noch nicht erreicht",
  before = "vor der Aufzeichnung", noRecord = "keine Aufzeichnung", soFar = "bisher %s", reachedIn = "erreicht in %s",
  openBody = "Diesen Meilenstein habt Ihr noch nicht erreicht. Sobald Ihr die Stufe erreicht, zieht der Erzähler hier Bilanz.",
  beforeBody = "Für diesen Abschnitt gibt es keine Aufzeichnung: Das Buch schreibt erst ab Stufe %s mit.",
  emptyBody = "Für diesen Abschnitt ist nichts aufgezeichnet.",
  truncated = "Sehr lange Reise: Ältere Zeilen sind gekürzt, die Zahlen sind Mindestwerte.",
  kTime = "Zeit (ohne AFK)", kZones = "Neue Zonen", kKills = "Kills", kQuests = "Quests", kDeaths = "Tode", kDungeons = "Dungeons",
  kBest = "Bester Fund", kDays = "Spieltage", kSeals = "Medaillen", kTotal = "Gesamtzeit (ohne AFK)",
  noDeaths = "ohne Tod", runs_one = "%s Durchlauf", runs_other = "%s Durchläufe", bosses_one = "%s Boss", bosses_other = "%s Bosse",
  sealsOf = "%s von %s", about = "etwa %s", roughly = "rund %s", atLeast = "mindestens %s",
  colsHead = "Zeit je Abschnitt", colDur = "%s:%s Std.", colTip = "Stufe %s–%s", colUnknown = "Zeit unbekannt", itemFallback = "Gegenstand #%s",
  zonesMore = "… und %s weitere",
})
local T = View.TEXT

View.ROWS, View.ROW_H = 7, 46       -- six sections plus the closing page: no paging
View.DETAIL_ROWS, View.DETAIL_H = 9, G.line.row
View.TEXT_Y = G.slots.ctrl.y        -- narrator line below the title
View.TEXT_SIZES = { 14, 13, 12, 11 } -- narrator text: font sizes tried from the largest, the text is never cut
View.TEXT_GAP = 10                   -- between the narrator text and the numbers
View.DETAIL_H_BOOK = 24              -- row height of the numbers (room for a value of two lines)
View.DETAIL_H_FINAL = { 20, 18 }     -- closing page: denser rows, the columns follow below
View.BODY_BOTTOM = G.slots.body.bottom
View.COLS_Y, View.COLS_H = 478, 60  -- closing page: time per section (duration written small above each column); COLS_Y moves with the text
View.COLS_HEAD = 48                 -- from the end of the numbers to the top of the columns (head + gap)
View.COLS_MAX_Y = 499               -- lowest top of the columns: bars, axis numbers and the foot stay on the page
View.COLS_FLOOR = 0.3               -- the shortest column keeps this share of the span below it, so it never vanishes
View.RING = 64                      -- closing page: gold medal ring with the narrator portrait, left of the title

View.NAME_MAX = 64 -- bytes of a zone / item / place name kept whole

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

local function count(n, key) return T(ns.Locale.plural(n, key .. "_one", key .. "_other"), int(n)) end

local function dateText(index, t)
  local d, m, y = Journal.Index.dateOf(index, t)
  if not d then return nil end
  return T("date", { d = format("%02d", d), m = format("%02d", m), y = format("%04d", y) })
end

local function amount(n, sec, rough)
  local s = int(n)
  if sec.truncated then return T("atLeast", s) end
  if rough then return T("roughly", s) end
  return s
end

local function duration(sec)
  local Ms = Journal.Meilenstein
  return Ms and Ms.durationText(sec.seconds, sec.secondsApprox) or nil
end

-- texts of an entry ---------------------------------------------------------------------------------------------------------

function View.label(sec)
  if sec.final then return T.final end
  return T("range", int(sec.from), int(sec.to))
end

-- info line of the list row: "9 Std. 12 Min. · 4 Zonen · 2 Tode" / "läuft · bisher 3 Std." / "noch nicht erreicht"
function View.infoText(sec)
  if sec.state == "open" then return T.open end
  if sec.nodata then return T.before end
  if sec.empty then return T.noRecord end
  local parts = {}
  local dur = duration(sec)
  if sec.state == "running" then
    parts[#parts + 1] = T.running
    if dur then parts[#parts + 1] = T("soFar", dur) end
  elseif dur then
    parts[#parts + 1] = dur
  end
  if (sec.deaths or 0) > 0 then
    local CT = Journal.DungeonsView and Journal.DungeonsView.TEXT
    parts[#parts + 1] = CT and CT(ns.Locale.plural(sec.deaths, "deaths_one", "deaths_other"), int(sec.deaths)) or int(sec.deaths)
  end
  return table.concat(parts, " · ")
end

function View.dateOf(index, sec)
  if sec.state == "done" and sec.at then return dateText(index, sec.at) end
  return nil
end

-- the narrator's portrait: the own book follows the option "Erzähler" (random -> own race), a guest book the guest's race
function View.narratorId(index, guest)
  local B = Journal.Begleiter
  if not B then return nil end
  local info = type(index) == "table" and type(index.char) == "table" and type(index.char.info) == "table" and index.char.info or {}
  local choice = (not guest) and B.narratorChoice() or "own"
  if choice ~= "own" and choice ~= "random" then return choice end
  if not guest then return B.narrator("own") end
  local faction = info.faction == "Horde" and "Horde" or nil
  return B.narratorForRace(info.raceFile, info.race, faction)
end

local function head(text) return { kind = "head", text = text } end
local function kv(k, v, tip) return { kind = "kv", k = k, v = v, tip = tip } end

local function bestItem(self, best)
  local Fmt = Journal.Fmt
  local name = disp(best.name, View.NAME_MAX) or (self.names and best.itemID and self.names.name(best.itemID)) or T("itemFallback", format("%.0f", best.itemID or 0))
  local it = kv(T.kBest, name)
  if best.quality and Fmt and Fmt.qualityRGB then
    local r, g, b = Fmt.qualityRGB(best.quality)
    if r then it.color = { r, g, b } end
  end
  it.tip = { name }
  if best.link then
    it.tip.item = best.link
    it.tip.itemExtra = {}
  end
  return it
end

local function zonesLine(sec)
  local names = {}
  for _, nm in ipairs(sec.zoneNamesAll or sec.zoneNames or {}) do
    local s = disp(nm, View.NAME_MAX)
    if s then names[#names + 1] = s end
  end
  local n = sec.zonesNew or 0
  local value = amount(n, sec)
  if #names > 0 then value = value .. " · " .. table.concat(names, ", ") end
  local tip = { T.kZones .. ": " .. amount(n, sec) }
  for _, s in ipairs(names) do tip[#tip + 1] = s end
  if n > #names and #names > 0 then tip[#tip + 1] = T("zonesMore", int(n - #names)) end
  local it = kv(T.kZones, value, tip)
  it.alt = amount(n, sec) -- shown instead of the list when it does not fit on one line (the list stays in the tooltip)
  return it
end

function View:Items(sec)
  local out = {}
  if sec.state == "open" or sec.nodata or sec.empty then return out end
  local dur = duration(sec)
  if dur then out[#out + 1] = kv(sec.final and T.kTotal or T.kTime, sec.state == "running" and T("soFar", dur) or dur) end
  if sec.final and (sec.days or 0) > 0 then out[#out + 1] = kv(T.kDays, int(sec.days)) end
  if (sec.zonesNew or 0) > 0 then out[#out + 1] = zonesLine(sec) end
  if (sec.kills or 0) > 0 then out[#out + 1] = kv(T.kKills, amount(sec.kills, sec, not sec.killsExact)) end
  if (sec.quests or 0) > 0 then out[#out + 1] = kv(T.kQuests, amount(sec.quests, sec)) end
  out[#out + 1] = kv(T.kDeaths, (sec.deaths or 0) > 0 and int(sec.deaths) or T.noDeaths)
  local dg = sec.dungeons
  if dg and dg.runs > 0 then
    local v = count(dg.runs, "runs")
    if dg.bosses > 0 then v = v .. " · " .. count(dg.bosses, "bosses") end
    out[#out + 1] = kv(T.kDungeons, v)
  end
  if sec.final and sec.seals and sec.seals.total > 0 then
    out[#out + 1] = kv(T.kSeals, T("sealsOf", int(sec.seals.broken), int(sec.seals.total)))
  end
  if sec.best then out[#out + 1] = bestItem(self, sec.best) end
  return out
end

-- frames ----------------------------------------------------------------------------------------------------------------------

local function buildRow(self, row)
  local nm = font(row, "title", SZ.m, "ink", "LEFT")
  nm:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)
  nm:SetWidth(BODY_W - 130)
  nm:SetWordWrap(false)
  local dt = font(row, "label", SZ.s, "sepia", "RIGHT")
  dt:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6)
  dt:SetWidth(120)
  local info = font(row, "label", SZ.s, "sepia", "LEFT")
  info:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -24)
  info:SetWidth(BODY_W - 16)
  info:SetWordWrap(false)
  row.label:SetText("")
  row.name, row.date, row.info = nm, dt, info
  D.RowStyle(row, { texts = { info } })
  row:HookScript("OnEnter", function(x)
    if x.cut then W.tip(x, { x.cutTitle or "", x.cut }) end
  end)
  row:HookScript("OnLeave", function(x) W.hideTip(x) end)
end

local function width(fs) return tonumber(fs:GetStringWidth()) or 0 end

local function setSize(fs, size)
  local file, _, flags = fs:GetFont()
  if file then fs:SetFont(file, size, flags or "") end
end

-- Value of a numbers row, never cut: the key takes the width it needs, the value the rest; too wide -> the font shrinks (not below
-- 11 on one line); still too wide -> the short form (zone count, the list is in the tooltip) or two lines at 10; whatever does not
-- fit even then (not expected) is cut and shows its full text on hover (row.cut).
function View.fillValue(row, it)
  local k, v = row.k, row.v
  k:SetWidth(SR.w)
  local kw = min(floor(SR.w / 2), floor(width(k)) + 8)
  k:SetWidth(kw)
  local maxW = SR.w - 10 - 2 - kw - 4 - 8
  v:SetWidth(maxW)
  v.fitBase = v.fitBase or select(2, v:GetFont()) or SZ.s + 1
  local base = v.fitBase
  v:SetWordWrap(false)
  if v.SetMaxLines then v:SetMaxLines(0) end
  setSize(v, base)
  set(v, it.v)
  local size = base
  while size > 11 and width(v) > maxW do
    size = size - 1
    setSize(v, size)
  end
  row.cut = nil
  if width(v) <= maxW then return end
  if it.alt then
    setSize(v, base)
    set(v, it.alt)
    return
  end
  setSize(v, 10)
  local long = width(v) > maxW * 2 - 12 -- unwrapped width: more than two lines
  v:SetWordWrap(true)
  if v.SetMaxLines then v:SetMaxLines(2) end
  if long then row.cut = true end
end

local function buildDetailRow(row)
  local k = font(row, "label", SZ.s, "sepia", "LEFT")
  k:SetPoint("LEFT", row, "LEFT", 2, 0)
  k:SetWidth(140)
  k:SetWordWrap(false)
  local v = font(row, "text", SZ.s + 1, "ink", "RIGHT")
  v:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  v:SetWidth(SR.w - 150)
  v:SetWordWrap(false)
  local line = W.NewRect(row, "sepia", 0.18, "BORDER")
  line:SetHeight(1)
  line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
  line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  row.label:SetText("")
  row.k, row.v = k, v
  row:SetScript("OnEnter", function(x)
    local it = x.item
    if it and it.tip then
      W.tip(x, it.tip)
    elseif it and x.cut then
      W.tip(x, { it.k, it.v })
    end
  end)
  row:SetScript("OnLeave", function(x) W.hideTip(x) end)
end

-- closing page: narrator portrait in the gold medal ring, a strip of diary tape, the columns
local function buildFinal(self, r)
  local u = {}
  local ring = CreateFrame("Frame", nil, r)
  ring:SetSize(View.RING, View.RING)
  ring:SetPoint("TOPLEFT", r, "TOPLEFT", SR.x - 4, -(G.slots.title.y - 14))
  -- the ring opening is 0.664 of the edge (Theme.SEAL_MOTIF_SCALE); the narrator texture's circle is 352 of 512 px
  local open = floor(View.RING * 0.664 + 0.5)
  local ps = floor(open * 512 / 352 + 0.5)
  u.bg = ring:CreateTexture(nil, "BACKGROUND")
  u.bg:SetSize(ps, ps)
  u.bg:SetPoint("CENTER", ring, "CENTER", 0, -floor(6 * ps / 512 + 0.5))
  u.portrait = ring:CreateTexture(nil, "ARTWORK")
  u.portrait:SetSize(ps, ps)
  u.portrait:SetPoint("CENTER", ring, "CENTER", 0, -floor(6 * ps / 512 + 0.5))
  u.frame = ring:CreateTexture(nil, "OVERLAY")
  u.frame:SetAllPoints(ring)
  if Theme.SEAL_LAYERED and Theme.TEX.sealFrames then
    u.frame:SetTexture(Theme.TEX.sealFrames)
    u.frame:SetTexCoord(Theme.sealFrameCoords("gold"))
  elseif Theme.TEX.disc then
    u.frame:SetTexture(Theme.TEX.disc)
  end
  u.tape = ring:CreateTexture(nil, "OVERLAY", nil, 2)
  u.tape:SetSize(54, 16)
  u.tape:SetPoint("CENTER", ring, "TOPLEFT", 10, -8)
  if Theme.TEX.diaryTape then u.tape:SetTexture(Theme.TEX.diaryTape) end
  u.tape:SetAlpha(0.85)
  u.ring = ring
  local ch = D.NewSectionHead(r, T.colsHead, { width = SR.w - 120 })
  ch:SetPoint("TOPLEFT", r, "TOPLEFT", SR.x, -(View.COLS_Y - 44))
  u.colsHead = ch
  local cols = W.NewColumns(r, { width = SR.w, height = View.COLS_H, gap = 10, color = "ink", markColor = "red", sketch = true,
    tip = function(item) return item.tip end })
  cols.frame:SetPoint("TOPLEFT", r, "TOPLEFT", SR.x, -View.COLS_Y)
  u.cols = cols
  local base = W.NewRect(r, "sepia", 0.5, "BORDER")
  base:SetHeight(1)
  base:SetPoint("TOPLEFT", r, "TOPLEFT", SR.x, -(View.COLS_Y + View.COLS_H))
  base:SetWidth(SR.w)
  u.base = base
  u.axis = {}
  for i = 1, 6 do
    local a = font(r, "label", SZ.xs, "sepia", "CENTER")
    a:SetWidth(40)
    u.axis[i] = a
    local d = font(r, "label", SZ.xs, "ink", "CENTER")
    d:SetWidth(60)
    d:SetWordWrap(false)
    u.dur = u.dur or {}
    u.dur[i] = d
  end
  self.fin = u
end

function View.new(page, left, right)
  local self = setmetatable({ page = page }, View)
  local l, r = CreateFrame("Frame", nil, left), CreateFrame("Frame", nil, right)
  l:SetAllPoints(left)
  r:SetAllPoints(right)
  self.l, self.r = l, r
  -- finds without a stored name: name from the client, loaded later and the page redrawn once (Live.itemNames)
  if Journal.Live and Journal.Live.itemNames then
    self.names = Journal.Live.itemNames(r, function() if self.open then self:RenderCard() end end, View.NAME_MAX)
  end
  W.NewPageHead(l, { side = "L" }):SetTexts(T.brand, T.page)
  W.NewPageHead(r, { side = "R" }):SetTexts("", T.page)
  D.escKeys(l, function() page:CloseSub() end) -- Esc -> overview
  local headL = D.NewSectionHead(l, T.title, { size = SZ.xl })
  headL:SetPoint("TOPLEFT", l, "TOPLEFT", IN_X, -(TITLE_Y - 6))
  self.count = font(l, "label", SZ.s, "sepia", "LEFT")
  self.count:SetPoint("TOPLEFT", l, "TOPLEFT", IN_X, -SUB_Y)
  self.list = W.NewList(l, { rows = View.ROWS, rowHeight = View.ROW_H, width = BODY_W, empty = "", emptyHand = true,
    build = function(row) buildRow(self, row) end,
    clear = function(row)
      row.sec = nil
      for _, k in ipairs({ "name", "date", "info" }) do set(row[k], "") end
      row.cut, row.cutTitle = nil, nil
      if row.SetSelected then row:SetSelected(false) end
      W.hideTip(row)
    end,
    fill = function(row, sec)
      row.sec = sec
      local pale = sec.state == "open"
      row.name:SetTextColor(W.color(pale and "faint" or "ink"))
      set(row.name, View.label(sec))
      set(row.date, View.dateOf(self.index, sec) or "")
      set(row.info, View.infoText(sec))
      W.fitLine(row.info, BODY_W - 16)
      if (tonumber(row.info:GetStringWidth()) or 0) > BODY_W - 16 then
        row.cut, row.cutTitle = View.infoText(sec), View.label(sec)
      end
      if row.SetSelected then row:SetSelected(self.sel ~= nil and self.sel == sec.key) end
      D.rowFilled(row)
    end,
    onClick = function(sec) self:Select(sec) end })
  self.list.frame:SetPoint("TOPLEFT", l, "TOPLEFT", BODY_X, -G.slots.body.y)
  self.note = font(l, "label", SZ.xs, "sepia", "RIGHT")
  local pt, fx, fy = Theme.gridFoot("L")
  self.note:SetPoint(pt, l, "TOPLEFT", fx, -(fy + 6))
  self.note:SetWidth(SL.x + SL.w - Theme.gridX("L", 2))

  -- right page: title, sub line, narrator line, the numbers
  local u = {}
  u.name = font(r, "title", SZ.xl, "ink", "LEFT")
  u.name:SetPoint("TOPLEFT", r, "TOPLEFT", SR.x, -G.slots.title.y)
  u.name:SetWidth(SR.w)
  u.name:SetWordWrap(false)
  u.sub = font(r, "text", SZ.s, "sepia", "LEFT")
  u.sub:SetPoint("TOPLEFT", r, "TOPLEFT", SR.x, -SUB_Y)
  u.sub:SetWidth(SR.w)
  u.sub:SetWordWrap(true) -- a long place name wraps to a second line, the text below moves down
  u.sub:SetJustifyV("TOP")
  u.text = font(r, "text", SZ.m, "ink", "LEFT")
  u.text:SetPoint("TOPLEFT", r, "TOPLEFT", SR.x, -View.TEXT_Y)
  u.text:SetWidth(SR.w)
  u.text:SetJustifyV("TOP")
  if u.text.SetWordWrap then u.text:SetWordWrap(true) end
  if u.text.SetMaxLines then u.text:SetMaxLines(0) end
  if u.text.SetSpacing then u.text:SetSpacing(2) end
  -- hover area over the text: full text, only needed in the last resort (text taller than the page leaves room for)
  u.textHit = CreateFrame("Frame", nil, r)
  u.textHit:EnableMouse(true)
  u.textHit:SetScript("OnEnter", function(x) if x.full then W.tip(x, { x.full }) end end)
  u.textHit:SetScript("OnLeave", function(x) W.hideTip(x) end)
  u.textHit:Hide()
  u.hint = D.emptyNote(r, SR.w - 40)
  u.hint:SetPoint("TOP", r, "TOPLEFT", SR.x + SR.w / 2, -(G.slots.body.y + 40))
  u.detail = W.NewList(r, { rows = View.DETAIL_ROWS, rowHeight = View.DETAIL_H, width = SR.w, empty = "",
    build = buildDetailRow,
    clear = function(row)
      row.item, row.cut = nil, nil
      set(row.k, "")
      set(row.v, "")
      W.hideTip(row)
    end,
    fill = function(row, it)
      row.item = it
      set(row.k, it.k)
      row.v:SetTextColor(unpack(it.color or { W.color("ink") }))
      View.fillValue(row, it)
    end })
  u.detail.frame:SetPoint("TOPLEFT", r, "TOPLEFT", SR.x, -(View.TEXT_Y + 118))
  self.card = u
  buildFinal(self, r)
  l:Hide()
  r:Hide()
  return self
end

function View:IsOpen() return self.open == true end

-- all entries of the list: the sections and the closing page
function View:Entries()
  local res = self.res
  if not res then return {} end
  local out = {}
  for _, s in ipairs(res.sections) do out[#out + 1] = s end
  out[#out + 1] = res.final
  return out
end

-- default: the last milestone reached (else the running section)
function View:DefaultKey()
  local res = self.res
  if not res then return nil end
  if res.final.state == "done" then return "final" end
  if res.latest then return res.latest end
  for _, s in ipairs(res.sections) do
    if s.state == "running" then return s.n end
  end
  return res.sections[1] and res.sections[1].n or nil
end

function View:Chosen()
  for _, s in ipairs(self:Entries()) do
    if s.key == self.sel then return s end
  end
  return nil
end

function View:Select(sec)
  self.sel = sec and sec.key or nil
  self.list:Refresh()
  self:RenderCard()
end

-- select by key (10, 20, ... or "final"), e.g. from the click on the narrator note
function View:SelectKey(key)
  for _, s in ipairs(self:Entries()) do
    if s.key == key then return self:Select(s) end
  end
end

local function subText(index, sec)
  if sec.final then
    local parts = { T("finalSub", int(sec.to)) }
    if sec.state == "done" and sec.at then parts[#parts + 1] = dateText(index, sec.at) end
    return table.concat(parts, " · ")
  end
  if sec.state == "open" then return T.open end
  if sec.nodata then return T.before end
  local from, to = dateText(index, sec.t0), dateText(index, sec.t1)
  local parts = {}
  if sec.state == "running" then
    parts[#parts + 1] = from and T("runningSince", { date = from }) or T.running
  elseif from and to then
    parts[#parts + 1] = from == to and from or T("dateRange", { from = from, to = to })
  end
  local place = sec.state == "done" and disp(sec.placeEnd, View.NAME_MAX) or nil
  if place then parts[#parts + 1] = T("reachedIn", place) end
  return table.concat(parts, " · ")
end

local function hideFinal(self)
  local u = self.fin
  u.ring:Hide()
  u.colsHead:Hide()
  u.cols.frame:Hide()
  u.base:Hide()
  for _, a in ipairs(u.axis) do set(a, "") end
  for _, d in ipairs(u.dur) do set(d, "") end
end

-- column heights relative to the span of the times (shortest .. longest), so differences show; the shortest keeps COLS_FLOOR of
-- the span as its height. Equal times (or a single known one): all full. -> value per column (0 = unknown)
function View.colValues(cols)
  local lo, hi
  for _, c in ipairs(cols or {}) do
    if c.seconds then
      lo = (not lo or c.seconds < lo) and c.seconds or lo
      hi = (not hi or c.seconds > hi) and c.seconds or hi
    end
  end
  local out = {}
  for i, c in ipairs(cols or {}) do
    if not c.seconds then
      out[i] = 0
    elseif hi > lo then
      local span = hi - lo
      out[i] = c.seconds - lo + span * View.COLS_FLOOR
    else
      out[i] = 1
    end
  end
  return out
end

-- short duration above a column: "16:23 Std."
function View.colDuration(seconds)
  local m = floor((tonumber(seconds) or 0) / 60 + 0.5)
  return T("colDur", int(floor(m / 60)), format("%02d", m % 60))
end

local function drawFinal(self, sec)
  local u = self.fin
  local Th = Journal.Theme
  local id = View.narratorId(self.index, self.page and self.page.guest)
  local bg = id and Th.TEX["narratorBG_" .. id] or nil
  local tex = id and Th.narratorTex and Th.narratorTex(id) or nil
  if bg then u.bg:SetTexture(bg) u.bg:Show() else u.bg:Hide() end
  if tex then u.portrait:SetTexture(tex) u.portrait:Show() else u.portrait:Hide() end
  u.ring:Show()
  -- the columns sit below the numbers (the page flows, see View:RenderCard)
  local colsY = self.colsY or View.COLS_Y
  u.colsHead:ClearAllPoints()
  u.colsHead:SetPoint("TOPLEFT", self.r, "TOPLEFT", SR.x, -(colsY - 44))
  u.cols.frame:ClearAllPoints()
  u.cols.frame:SetPoint("TOPLEFT", self.r, "TOPLEFT", SR.x, -colsY)
  u.base:ClearAllPoints()
  u.base:SetPoint("TOPLEFT", self.r, "TOPLEFT", SR.x, -(colsY + View.COLS_H))
  u.colsHead:Show()
  u.cols.frame:Show()
  u.base:Show()
  local items, values, top = {}, View.colValues(sec.cols), 0
  for _, v in ipairs(values) do top = max(top, v) end
  for i, c in ipairs(sec.cols or {}) do
    local known = c.seconds ~= nil
    local tip = { T("colTip", int(max(1, c.n - 10)), int(c.n)) }
    if known then
      tip[#tip + 1] = Journal.Meilenstein.durationText(c.seconds, false) or ""
    else
      tip[#tip + 1] = c.state == "open" and T.open or T.colUnknown
    end
    items[i] = { value = values[i], color = c.state == "running" and "red" or "ink", tip = tip }
  end
  u.cols:SetData(items)
  local n = #items
  local gap = 10
  local colW = n > 0 and (SR.w - gap * (n - 1)) / n or SR.w
  for i, a in ipairs(u.axis) do
    local c = sec.cols and sec.cols[i]
    if c then
      a:ClearAllPoints()
      a:SetPoint("TOP", self.r, "TOPLEFT", SR.x + (i - 1) * (colW + gap) + colW / 2, -(colsY + View.COLS_H + 4))
      set(a, int(c.n))
      -- the bar height as Columns:SetData draws it (height minus the mark row), the duration sits just above it
      local markSize = min(6, max(3, floor(colW)))
      local h = top > 0 and values[i] / top * (View.COLS_H - markSize - 2) or 0
      local d = u.dur[i]
      d:ClearAllPoints()
      d:SetPoint("BOTTOM", self.r, "TOPLEFT", SR.x + (i - 1) * (colW + gap) + colW / 2, -(colsY + View.COLS_H - h + 2))
      set(d, c.seconds and View.colDuration(c.seconds) or "")
      W.fitLine(d, colW + gap - 2, 9)
    else
      set(a, "")
      set(u.dur[i], "")
    end
  end
end

-- row height of the numbers list (rows, list frame and row anchors)
local function setRowHeight(list, h)
  if list.rowHeight == h then return end
  list.rowHeight = h
  list.frame:SetHeight(list.nRows * h)
  for i, row in ipairs(list.rows) do
    row:SetHeight(h)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", list.frame, "TOPLEFT", 0, -(i - 1) * h)
  end
end

local function sizeText(fs, size) -- the narrator text at a font size, wrapped to the page width, no line limit
  setSize(fs, size)
  fs:SetWidth(SR.w)
  if fs.SetMaxLines then fs:SetMaxLines(0) end
end

-- The page flows from top to bottom: sub line (may wrap) -> narrator text (whole) -> numbers -> (closing page) columns. The text
-- takes the height it needs: the largest font size at which text, numbers (and columns) still fit on the page; only when even
-- the smallest does not fit, the text is limited to the room left and shows in full on hover. -> text height, numbers Y, row height
function View:Flow(sec, text, nItems, textY, final)
  local u = self.card
  local limit = final and (View.COLS_MAX_Y - View.COLS_HEAD) or View.BODY_BOTTOM
  local heights = final and View.DETAIL_H_FINAL or { View.DETAIL_H_BOOK }
  u.text:SetWidth(SR.w)
  set(u.text, text or "")
  u.textHit.full = nil
  u.textHit:Hide()
  if not text or text == "" then return 0, textY, heights[1] end
  u.text.fitBase = u.text.fitBase or select(2, u.text:GetFont()) or SZ.m
  local sizes = {}
  for _, z in ipairs(View.TEXT_SIZES) do
    if z <= u.text.fitBase then sizes[#sizes + 1] = z end
  end
  if #sizes == 0 then sizes[1] = u.text.fitBase end
  for _, z in ipairs(sizes) do
    sizeText(u.text, z)
    local th = tonumber(u.text:GetStringHeight()) or 0
    for _, rh in ipairs(heights) do
      if textY + th + View.TEXT_GAP + nItems * rh <= limit then return th, textY + th + View.TEXT_GAP, rh end
    end
  end
  -- last resort: smallest size and rows, the text limited to the room left (never expected with real data), full text on hover
  local z, rh = sizes[#sizes], heights[#heights]
  sizeText(u.text, z)
  local room = limit - (textY + View.TEXT_GAP + nItems * rh)
  local line = ceil(z * 1.2) + 2
  local lines = max(1, floor(room / line))
  if u.text.SetMaxLines then u.text:SetMaxLines(lines) end
  u.textHit.full = text
  u.textHit:ClearAllPoints()
  u.textHit:SetPoint("TOPLEFT", self.r, "TOPLEFT", SR.x, -textY)
  u.textHit:SetSize(SR.w, lines * line)
  u.textHit:Show()
  return lines * line, textY + lines * line + View.TEXT_GAP, rh
end

function View:RenderCard()
  local u = self.card
  local sec = self:Chosen()
  hideFinal(self)
  u.textHit.full = nil
  u.textHit:Hide()
  if not sec then
    set(u.name, "")
    set(u.sub, "")
    set(u.text, "")
    set(u.hint, "")
    u.detail:SetItems({})
    return
  end
  -- the closing page has the narrator ring left of the title: title and sub line move right
  local inset = (sec.final and sec.state ~= "open") and (View.RING + 8) or 0
  u.name:ClearAllPoints()
  u.name:SetPoint("TOPLEFT", self.r, "TOPLEFT", SR.x + inset, -G.slots.title.y)
  u.sub:ClearAllPoints()
  u.sub:SetPoint("TOPLEFT", self.r, "TOPLEFT", SR.x + inset, -SUB_Y)
  set(u.name, View.label(sec))
  W.fitLine(u.name, SR.w - inset, 18)
  u.sub:SetWidth(SR.w - inset)
  set(u.sub, subText(self.index, sec))
  local subH = tonumber(u.sub:GetStringHeight()) or 0
  local hint
  if sec.state == "open" then
    hint = T.openBody
  elseif sec.nodata then
    hint = T("beforeBody", int(self.res and self.res.start or 1))
  elseif sec.empty then
    hint = T.emptyBody
  end
  local Ms = Journal.Meilenstein
  local info = type(self.index) == "table" and type(self.index.char) == "table" and type(self.index.char.info) == "table"
    and self.index.char.info or {}
  local name = disp(info.name, View.NAME_MAX)
  local seed = Journal.Texts and Journal.Texts.seed(info.firstSeen) or "0"
  local text = (not hint and Ms) and Ms.pageText(sec, self.res, seed, name) or nil
  local items = self:Items(sec)
  -- a second sub line pushes the text down by its height
  local textY = View.TEXT_Y
  if subH > ceil(SZ.s * 1.2) + 2 then textY = max(textY, SUB_Y + subH + 6) end
  local final = sec.final and not hint
  local _, detailY, rowH = self:Flow(sec, text, #items, textY, final)
  u.text:ClearAllPoints()
  u.text:SetPoint("TOPLEFT", self.r, "TOPLEFT", SR.x, -textY)
  set(u.hint, hint or "")
  setRowHeight(u.detail, rowH)
  u.detail.frame:ClearAllPoints()
  u.detail.frame:SetPoint("TOPLEFT", self.r, "TOPLEFT", SR.x, -detailY)
  u.detail:SetItems(items)
  u.detail:SetOffset(0)
  u.detail:Refresh()
  self.colsY = min(View.COLS_MAX_Y, detailY + #items * rowH + View.COLS_HEAD)
  if final then drawFinal(self, sec) end
end

function View:Render()
  local res = self.res
  local entries = self:Entries()
  local reached = 0
  for _, s in ipairs(res and res.sections or {}) do
    if s.state == "done" then reached = reached + 1 end
  end
  set(self.count, res and T("reachedOf", int(reached), int(#res.sections)) or "")
  set(self.note, (res and res.final and res.final.truncated) and T.truncated or "")
  local want = self.page and self.page.milestoneSel
  if self.page then self.page.milestoneSel = nil end
  if want ~= nil then self.sel = want end
  if not self:Chosen() then self.sel = self:DefaultKey() end
  self.list:SetItems(entries)
  self.list:Refresh()
  self:RenderCard()
end

function View:Load(index)
  self.index = index
  self.res = M.build(index)
end

function View:Open(index)
  self.open = true
  self:Load(index)
  self.l:Show()
  self.r:Show()
  self.list:SetOffset(0)
  self:Render()
end

function View:Refresh(index)
  if not self.open then return end
  self:Load(index)
  self:Render()
end

function View:Close()
  self.open = false
  if self.names then self.names.stop() end
  self.l:Hide()
  self.r:Hide()
  for _, row in ipairs(self.list.rows) do W.hideTip(row) end
  for _, row in ipairs(self.card.detail.rows) do W.hideTip(row) end
  local hits = self.fin.cols.hits and self.fin.cols.hits.used
  if type(hits) == "table" then for _, h in ipairs(hits) do W.hideTip(h) end end
end
