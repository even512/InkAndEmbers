-- Tab "Handwerk" (change "datenbuecher", P5): the professions of the character as a list on the left (primary + cooking, fishing,
-- first aid) with the balance of gathering and crafting underneath; on the right the
-- skill curve of the chosen profession over the play time, the milestones 75/150/225/300 (date, character level), the first
-- craft find and the learned recipes. Sub-bookmarks (change "runde3", package R): "Berufe" (this page) and "Rezeptbuch"
-- (pages/HandwerkRezeptbuch.lua, every recipe of the professions, learned and not yet learned; not in the guest book). Data from journal/model/Handwerk.lua (display-ready texts, all foreign text through
-- Sanitize.display). Works in the own book and in another character's book (read only, nothing live). WoW Forever only:
-- Handwerk.active() hides the tab in Retail (Pages.hideTab). No ticker, no OnUpdate; pools are bounded.
local _, ns = ...

local Journal = ns.Journal
local Pages, Widgets, Handwerk = Journal and Journal.Pages, Journal and Journal.Widgets, Journal and Journal.Handwerk
local D = Widgets and Widgets.Diary -- diary toolkit "diary with stickers"
if not (Pages and Widgets and Handwerk and D) then return end

local Theme = Journal.Theme or {}
local floor, max, min, format = math.floor, math.max, math.min, string.format

local Page = { needs = { index = true } }
Journal.HandwerkPage = Page

local G = Theme.GRID
local L0, LW = Theme.gridX("L")      -- left: edge and width of the text block (92, 402)
local R0, RW = Theme.gridX("R")      -- right (44, 402)
local CW = RW - 8                    -- right content ends at x 438: left of the decorations (keep-out from x 440)

-- left: list (6 rows), balance below (the decorations bottom left, x 36..155 from y 478, stay free)
local LIST_HEAD_Y, LIST_Y, ROW_H, ROWS = 126, 150, 34, 6
local BAL_Y = LIST_Y + ROWS * ROW_H + 18      -- section head "Bilanz"
local TILE_Y, TILE_W = BAL_Y + 26, floor(LW / 5)
local FIRST_Y = TILE_Y + 52                   -- first craft find overall

-- right: curve, milestones, first craft find, recipes
local CHART_Y, CHART_H = 150, 140
local AX, PT, PB = 32, 8, 104        -- chart: x of the axis, plot top and bottom (from the top of the chart)
local MS_Y = 302
local FC_Y = 366
local NEXT_Y = 384                   -- block "Für den nächsten Skillpunkt" (pages/HandwerkSkillpunkt.lua): head, rule, recommendation, two alternatives
local REC_Y = 500
local REC_ROWS, REC_ROW_H = 2, 17
local LINE_MAX, DOT_MAX, SEG_MAX, LABEL_MAX, HIT_COLS = 130, 12, 40, 24, 48
local BUCKET = 3                     -- px per curve bucket (at most plotW / BUCKET line segments)

-- locale scope "p.Handwerk" (English in locales/enUS_pages.lua), read when drawing
Page.TEXT = ns.Locale.ns("p.Handwerk", {
  brand = "INK & EMBERS", book = "BERUFE", page = "HANDWERK", title = "Handwerk",
  prof_one = "%s Beruf", prof_other = "%s Berufe", rec_one = "%s Rezept", rec_other = "%s Rezepte",
  listHead = "BERUFE",
  listEmpty = "Noch kein Beruf gelernt. Sobald Ihr einen Beruf lernt, schreibt sich hier seine Kurve von selbst.",
  primary = "Hauptberuf", secondary = "Nebenberuf",
  skillOf = "%s / %s",
  skillNow = "Fertigkeit %s von %s", skillRank = "%s · %s",
  subBerufe = "Berufe", subBerufeTip = "Skillkurve, Meilensteine und Bilanz Eurer Berufe",
  subRezept = "Rezeptbuch", subRezeptTip = "Alle Rezepte Eurer Berufe, gelernt und noch offen, mit Materialien (nur WoW Forever)",
  balance = "BILANZ",
  mined = "abgebaut", picked = "gepflückt", skinned = "gekürschnert", fished = "geangelt", crafted = "hergestellt",
  minedTip = "Erz und Gestein aus Rohstoffknoten", pickedTip = "Kräuter und Blumen aus Pflanzen",
  skinnedTip = "Leder und Felle von Gegnern (aus den Funden geschätzt)", fishedTip = "Alles, was am Angelhaken hing",
  craftedTip = "Selbst hergestellte Gegenstände, auch die unter Güte Ungewöhnlich",
  balanceEmpty = "Noch nichts gesammelt oder hergestellt.",
  firstCraft = "Erste Herstellung", firstCraftTip = "Der erste selbst hergestellte Gegenstand ab Güte Ungewöhnlich",
  level = "Stufe %s",
  curveHead = "FERTIGKEIT ÜBER DIE SPIELZEIT", recipesHead = "Erlernte Rezepte",
  hours = "%s Std.", minutes = "%s Min.",
  open = "noch offen", milestoneTip = "Fertigkeit %s erreicht",
  tipSkill = "Fertigkeit %s von %s", tipLearned = "Gelernt auf Stufe %s", tipLast = "Zuletzt gestiegen: %s",
  tipWhen = "%s · Stufe %s", tipPlay = "Nach %s Spielzeit",
  noRecipes = "Noch kein Rezept gelernt.",
  recipesUnsure = "Die Rezepte dieses Berufs lassen sich nicht sicher zuordnen. Alle findet Ihr im Rezeptbuch.",
  emptyTitle = "Das Handwerksbuch ist noch leer",
  emptyBody = "Lernt einen Beruf, und jeder Skillpunkt, jedes Rezept und jeder Meilenstein schreibt sich hier von selbst auf.",
  date = "{d}.{m}.{y}",
})
local T = Page.TEXT

local function font(parent, kind, size, color, justify)
  local fs = Widgets.font(parent, kind, size, color)
  if justify then fs:SetJustifyH(justify) end
  return fs
end

local function set(fs, text) Widgets.setText(fs, text) end

local function int(n) return Journal.Texts and Journal.Texts.int(n) or tostring(floor(tonumber(n) or 0)) end

local function plural(n, key) return T(ns.Locale.plural(n, key .. "_one", key .. "_other"), int(n)) end

local function hover(frame, getLines)
  frame:EnableMouse(true)
  frame:SetScript("OnEnter", function(self)
    local ok, lines = Widgets.call(getLines, self)
    if ok and type(lines) == "table" then Widgets.tip(self, lines) end
  end)
  frame:SetScript("OnLeave", function(self) Widgets.hideTip(self) end)
end

local function dateText(index, t)
  local d, m, y = Journal.Index.dateOf(index, t)
  if not d then return nil end
  return T("date", { d = format("%02d", d), m = format("%02d", m), y = format("%04d", y) })
end

local function levelText(level)
  return level and T("level", int(level)) or nil
end

local function join(parts)
  local out = {}
  for _, p in ipairs(parts) do
    if p and p ~= "" then out[#out + 1] = p end
  end
  return table.concat(out, " · ")
end

-- ---------------------------------------------------------------- left

-- entries of the list: the professions
local function entriesOf(res)
  local list = {}
  for _, p in ipairs(res.professions) do list[#list + 1] = { kind = "prof", key = p.key, p = p } end
  return list
end

local function profTip(self, p)
  local lines = { p.name, T("tipSkill", int(p.rank), int(p.max)) }
  local idx = self.index
  if p.first then
    local d = dateText(idx, p.first.t)
    lines[#lines + 1] = join({ T("tipLearned", p.first.level and int(p.first.level) or "?"), d })
  end
  if p.last and p.last ~= p.first then
    local d = dateText(idx, p.last.t)
    if d then lines[#lines + 1] = T("tipLast", d) end
  end
  return lines
end

local function buildRow(self, row)
  local nm = font(row, "title", G.size.m, "ink", "LEFT")
  nm:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -3)
  nm:SetWidth(LW - 150)
  nm:SetWordWrap(false)
  local sub = font(row, "label", G.size.xs, "sepia", "LEFT")
  sub:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -20)
  sub:SetWidth(LW - 150)
  sub:SetWordWrap(false)
  local val = font(row, "title", G.size.m, "ink", "RIGHT")
  val:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -3)
  val:SetWidth(120)
  val:SetWordWrap(false)
  local bar = Widgets.NewRect(row, "sepia", 0.25, "ARTWORK")
  bar:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -23)
  bar:SetSize(110, 4)
  local fill = Widgets.NewRect(row, "gold", 0.95, "OVERLAY")
  fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
  fill:SetSize(1, 4)
  row.name, row.subline, row.val, row.bar, row.fill = nm, sub, val, bar, fill
  row.label:SetText("")
  row:SetScript("OnEnter", function(r)
    if r.entry and r.entry.kind == "prof" then Widgets.tip(r, profTip(self, r.entry.p)) end
  end)
  row:SetScript("OnLeave", function(r) Widgets.hideTip(r) end)
  D.RowStyle(row, { texts = { nm, val } })
end

local function fillRow(self, row, e)
  row.entry = e
  local p = e.p
  set(row.name, p.name)
  set(row.subline, join({ p.kind == "primary" and T.primary or T.secondary, p.rankName }))
  set(row.val, T("skillOf", int(p.rank), int(p.max)))
  row.bar:Show()
  row.fill:Show()
  local share = p.max > 0 and min(1, p.rank / p.max) or 0
  row.fill:SetWidth(max(1, floor(110 * share + 0.5)))
  row:SetSelected(self.sel == e.key)
  D.rowFilled(row)
end

local function buildLeft(self, left)
  local u = {}
  self.L = u
  u.head = Widgets.NewPageHead(left, { side = "L" })
  u.head:SetTexts(T.brand, T.book)
  -- title block right-aligned: the wax drops sit top left
  u.title = font(left, "title", G.size.xl, "ink", "RIGHT")
  u.title:SetPoint("TOPRIGHT", left, "TOPLEFT", L0 + LW, -G.slots.title.y)
  set(u.title, T.title)
  u.sub = font(left, "label", G.size.s, "sepia", "RIGHT")
  u.sub:SetPoint("TOPRIGHT", left, "TOPLEFT", L0 + LW, -(G.slots.title.y + 34))
  u.sub:SetWidth(LW)
  u.sub:SetWordWrap(false)

  u.listHead = font(left, "label", G.size.xs, "sepia", "LEFT")
  u.listHead:SetPoint("TOPLEFT", left, "TOPLEFT", L0, -LIST_HEAD_Y)
  set(u.listHead, T.listHead)
  Widgets.NewRule(left, L0, LIST_HEAD_Y + 18, LW)
  u.list = Widgets.NewList(left, { rows = ROWS, rowHeight = ROW_H, width = LW, step = 2, empty = T.listEmpty, emptyHand = true,
    build = function(row) buildRow(self, row) end,
    clear = function(row)
      row.entry = nil
      for _, k in ipairs({ "name", "subline", "val" }) do set(row[k], "") end
      if row.SetSelected then row:SetSelected(false) end
      Widgets.hideTip(row)
    end,
    fill = function(row, e) fillRow(self, row, e) end,
    onClick = function(e) self:Select(e.key) end })
  u.list.frame:SetPoint("TOPLEFT", left, "TOPLEFT", L0, -LIST_Y)

  -- balance: five tiles (number over its word), without any number a handwritten sentence
  u.balHead = font(left, "label", G.size.xs, "sepia", "LEFT")
  u.balHead:SetPoint("TOPLEFT", left, "TOPLEFT", L0, -BAL_Y)
  set(u.balHead, T.balance)
  u.balRule = Widgets.NewRule(left, L0, BAL_Y + 18, LW)
  u.tiles = {}
  for i, key in ipairs({ "mined", "picked", "skinned", "fished", "crafted" }) do
    local f = CreateFrame("Frame", nil, left)
    f:SetSize(TILE_W, 44)
    f:SetPoint("TOPLEFT", left, "TOPLEFT", L0 + (i - 1) * TILE_W, -TILE_Y)
    local num = font(f, "title", G.size.l, "ink", "CENTER")
    num:SetPoint("TOP", f, "TOP", 0, -2)
    num:SetWidth(TILE_W - 4)
    num:SetWordWrap(false)
    local word = font(f, "label", G.size.xs, "sepia", "CENTER")
    word:SetPoint("TOP", f, "TOP", 0, -26)
    word:SetWidth(TILE_W - 4)
    word:SetWordWrap(false)
    set(word, T[key])
    hover(f, function() return { T[key], T[key .. "Tip"] } end)
    u.tiles[i] = { key = key, frame = f, num = num, word = word }
  end
  u.balEmpty = D.emptyNote(left, LW - 20, 17)
  u.balEmpty:SetPoint("TOPLEFT", left, "TOPLEFT", L0 + 10, -(TILE_Y + 4))
  -- first craft find overall (from the loot lines: only from quality green)
  u.first = font(left, "label", G.size.s, "ink", "LEFT")
  u.first:SetPoint("TOPLEFT", left, "TOPLEFT", L0, -FIRST_Y)
  u.first:SetWidth(LW)
  u.first:SetWordWrap(false)
  u.firstHit = CreateFrame("Frame", nil, left)
  u.firstHit:SetPoint("TOPLEFT", left, "TOPLEFT", L0, -FIRST_Y)
  u.firstHit:SetSize(LW, 14)
  hover(u.firstHit, function() return { T.firstCraft, T.firstCraftTip } end)
end

local function drawLeft(self, res)
  local u = self.L
  local entries = self.entries
  u.list:SetItems(entries)
  set(u.sub, join({ #res.professions > 0 and plural(#res.professions, "prof") or nil,
    #res.recipes > 0 and plural(#res.recipes, "rec") or nil }))
  local b = res.balance
  local any = false
  for i, tile in ipairs(u.tiles) do
    local n = b[tile.key] or 0
    if n > 0 then any = true end
    set(tile.num, int(n))
    tile.num:SetTextColor(Widgets.color(n > 0 and "ink" or "sepia"))
  end
  for _, tile in ipairs(u.tiles) do tile.frame:SetShown(any) end
  set(u.balEmpty, any and "" or T.balanceEmpty)
  local fc = res.firstCraft
  if fc then
    set(u.first, T.firstCraft .. ": " .. join({ fc.name, dateText(self.index, fc.t), levelText(fc.level) }))
    u.firstHit:Show()
  else
    set(u.first, "")
    u.firstHit:Hide()
  end
end

-- ---------------------------------------------------------------- right: curve

-- tick step (seconds) of the play-time axis: at most five ticks
local STEPS = { 300, 600, 900, 1800, 3600, 7200, 10800, 18000, 36000, 72000, 108000, 180000, 360000, 720000 }
local function tickStep(total)
  for _, s in ipairs(STEPS) do
    if total / s <= 5 then return s end
  end
  local s = 720000
  while total / s > 5 do s = s * 2 end
  return s
end

local function tickText(s)
  if s < 3600 then return T("minutes", int(floor(s / 60 + 0.5))) end
  return T("hours", int(floor(s / 3600 + 0.5)))
end

local function playText(sec)
  if sec < 3600 then return T("minutes", int(floor(sec / 60 + 0.5))) end
  local h = sec / 3600
  return T("hours", h < 10 and format("%.1f", h) or int(floor(h + 0.5)))
end

local function chartRect(u, x, y, w, h, color, alpha, pool)
  local t = (pool or u.segs):Acquire()
  if not t then return nil end
  t:SetColorTexture(Widgets.color(color, alpha or 1))
  t:SetPoint("TOPLEFT", u.chart, "TOPLEFT", x, -y)
  t:SetSize(max(w, 1), max(h, 1))
  return t
end

local function chartLabel(u, text, x, y, justify, color, width)
  local fs = u.labels:Acquire()
  if not fs then return nil end
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWidth(width or 60)
  fs:SetTextColor(Widgets.color(color or "sepia"))
  local anchor = justify == "RIGHT" and "TOPRIGHT" or (justify == "CENTER" and "TOP" or "TOPLEFT")
  fs:SetPoint(anchor, u.chart, "TOPLEFT", x, -y)
  set(fs, text)
  return fs
end

-- index of the last point with x <= v (0 if none)
local function lastByX(points, v)
  local lo, hi, found = 1, #points, 0
  while lo <= hi do
    local mid = floor((lo + hi) / 2)
    if points[mid].x <= v then found, lo = mid, mid + 1 else hi = mid - 1 end
  end
  return found
end

local function pointTip(self, p, pt)
  local idx = self.index
  local lines = { p.name, T("tipSkill", int(pt.rank), int(p.max)) }
  lines[#lines + 1] = join({ dateText(idx, pt.t), pt.level and levelText(pt.level) or nil })
  if pt.x and pt.x > 0 then lines[#lines + 1] = T("tipPlay", playText(pt.x)) end
  return lines
end

local function drawChart(self, p, res)
  local u = self.R
  for _, pool in ipairs({ u.segs, u.labels, u.lines, u.dots, u.hits }) do pool:ReleaseAll() end
  local plotW, plotH = CW - AX - 8, PB - PT
  local top = max(p.max, p.rank, 75)
  -- play-time axis: from shortly before the first to shortly after the last skill rise of this profession (a profession learned
  -- early and finished soon would otherwise be squeezed into a corner of a long journey); the ticks show the play time of the journey
  local fx, lx = p.first.x or 0, p.last.x or 0
  local span = max(lx - fx, 600)
  local x0 = max(0, fx - span * 0.05)
  local total = lx + span * 0.05 - x0
  local function yOf(rank) return PT + (1 - min(rank, top) / top) * plotH end
  local function xOf(x) return AX + max(0, min(x - x0, total)) / total * plotW end

  -- skill axis: guide lines (every 25 up to 75, otherwise every rank step of 75), zero axis strong
  local gstep = top <= 75 and 25 or 75
  local v = gstep
  while v <= top + 0.001 do
    local y = yOf(v)
    chartRect(u, AX, y, plotW, 1, "sepia", 0.2)
    chartLabel(u, int(v), AX - 6, y - 6, "RIGHT", "sepia", AX - 6)
    v = v + gstep
  end
  chartRect(u, AX, PB, plotW, 1, "ink", 0.7)
  chartLabel(u, "0", AX - 6, PB - 6, "RIGHT", "sepia", AX - 6)
  -- play-time axis
  local step = tickStep(total)
  local s = math.ceil(x0 / step) * step
  while s <= x0 + total + 0.001 do
    local x = xOf(s)
    chartRect(u, x, PB, 1, 4, "ink", 0.7)
    chartLabel(u, s == 0 and "0" or tickText(s), x, PB + 6, "CENTER", "sepia", 56)
    s = s + step
  end

  -- curve: last point of every bucket (rank only rises), straight segments between them
  local pts, lastB = {}, nil
  for i, pt in ipairs(p.points) do
    local px = xOf(pt.x or 0)
    local b = floor(px / BUCKET)
    local item = { px, yOf(pt.rank), pt }
    if b == lastB and i > 1 then pts[#pts] = item else pts[#pts + 1] = item end
    lastB = b
  end
  if p.points[1] and pts[1] and pts[1][3] ~= p.points[1] then table.insert(pts, 1, { xOf(p.points[1].x or 0), yOf(p.points[1].rank), p.points[1] }) end
  if self.canLine and #pts >= 2 then
    local r, g, b = Widgets.color("ink")
    for i = 2, #pts do
      local ln = u.lines:Acquire()
      if not ln then break end
      ln:SetThickness(1.6)
      ln:SetColorTexture(r, g, b, 0.9)
      ln:SetStartPoint("TOPLEFT", u.chart, pts[i - 1][1], -pts[i - 1][2])
      ln:SetEndPoint("TOPLEFT", u.chart, pts[i][1], -pts[i][2])
    end
  end
  if not self.canLine or #pts == 1 then
    for _, q in ipairs(pts) do chartRect(u, q[1] - 1.5, q[2] - 1.5, 3, 3, "ink", 0.9, u.dots) end
  end
  -- milestones as gold dots, the current state as a red one
  for _, m in ipairs(p.milestones) do
    if m.t and m.x then chartRect(u, xOf(m.x) - 3, yOf(m.rank) - 3, 6, 6, "gold", 1, u.dots) end
  end
  chartRect(u, xOf(p.last.x or 0) - 3, yOf(p.last.rank) - 3, 6, 6, "red", 1, u.dots)

  -- hover columns: the skill at that time
  local colW = plotW / HIT_COLS
  for j = 1, HIT_COLS do
    local at = x0 + (j - 0.5) / HIT_COLS * total
    local i = lastByX(p.points, at)
    if i > 0 then
      local hit = u.hits:Acquire()
      if not hit then break end
      hit:SetPoint("TOPLEFT", u.chart, "TOPLEFT", AX + (j - 1) * colW, -(PT - 2))
      hit:SetSize(max(colW, 1), plotH + 4)
      hit.tipLines = pointTip(self, p, p.points[i])
    end
  end
end

-- ---------------------------------------------------------------- right: page

local function buildRight(self, right)
  local u = {}
  self.R = u
  u.head = Widgets.NewPageHead(right, { side = "R" })
  u.head:SetTexts("", T.page)
  u.title = font(right, "title", G.size.xl, "ink", "LEFT")
  u.title:SetPoint("TOPLEFT", right, "TOPLEFT", R0, -G.slots.title.y)
  u.title:SetWidth(CW)
  u.title:SetWordWrap(false)
  u.sub = font(right, "label", G.size.s, "sepia", "LEFT")
  u.sub:SetPoint("TOPLEFT", right, "TOPLEFT", R0, -(G.slots.title.y + 34))
  u.sub:SetWidth(CW)
  u.sub:SetWordWrap(false)

  -- curve section
  u.curveHead = font(right, "label", G.size.xs, "sepia", "LEFT")
  u.curveHead:SetPoint("TOPLEFT", right, "TOPLEFT", R0, -LIST_HEAD_Y)
  set(u.curveHead, T.curveHead)
  u.curveRule = Widgets.NewRule(right, R0, LIST_HEAD_Y + 18, CW)
  local chart = CreateFrame("Frame", nil, right)
  chart:SetSize(CW, CHART_H)
  chart:SetPoint("TOPLEFT", right, "TOPLEFT", R0, -CHART_Y)
  u.chart = chart
  self.canLine = type(chart.CreateLine) == "function"
  u.segs = Widgets.Pool(function() return chart:CreateTexture(nil, "ARTWORK") end, nil, SEG_MAX)
  u.dots = Widgets.Pool(function() return chart:CreateTexture(nil, "OVERLAY") end, nil, DOT_MAX + 160)
  u.lines = Widgets.Pool(function()
    if self.canLine then return chart:CreateLine(nil, "OVERLAY") end
    return nil
  end, nil, self.canLine and LINE_MAX or 0)
  u.labels = Widgets.Pool(function()
    local fs = font(chart, "label", G.size.xs, "sepia", "LEFT")
    fs:SetWordWrap(false)
    return fs
  end, function(fs) fs:SetText("") end, LABEL_MAX)
  u.hits = Widgets.Pool(function()
    local h = CreateFrame("Frame", nil, chart)
    hover(h, function(f) return f.tipLines end)
    return h
  end, function(h)
    Widgets.hideTip(h)
    h.tipLines = nil
  end, HIT_COLS)

  -- milestones: four columns
  u.ms = {}
  local cellW = floor(CW / 4)
  u.msRule = Widgets.NewRule(right, R0, MS_Y - 6, CW, 0.2)
  for i, step in ipairs(Handwerk.STEPS) do
    local f = CreateFrame("Frame", nil, right)
    f:SetSize(cellW, 56)
    f:SetPoint("TOPLEFT", right, "TOPLEFT", R0 + (i - 1) * cellW, -MS_Y)
    local num = font(f, "title", G.size.l, "ink", "LEFT")
    num:SetPoint("TOPLEFT", f, "TOPLEFT", 2, 0)
    set(num, int(step))
    local rank = font(f, "label", G.size.xs, "sepia", "LEFT")
    rank:SetPoint("BOTTOMLEFT", num, "BOTTOMRIGHT", 5, 2)
    rank:SetWidth(cellW - 40)
    rank:SetWordWrap(false)
    local date = font(f, "label", G.size.s, "ink", "LEFT")
    date:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -24)
    date:SetWidth(cellW - 6)
    date:SetWordWrap(false)
    local lvl = font(f, "label", G.size.xs, "sepia", "LEFT")
    lvl:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -40)
    lvl:SetWidth(cellW - 6)
    lvl:SetWordWrap(false)
    hover(f, function() return f.tipLines end)
    u.ms[i] = { step = step, frame = f, num = num, rank = rank, date = date, lvl = lvl }
  end
  -- first craft find of the profession
  u.first = font(right, "label", G.size.s, "ink", "LEFT")
  u.first:SetPoint("TOPLEFT", right, "TOPLEFT", R0, -FC_Y)
  u.first:SetWidth(CW)
  u.first:SetWordWrap(false)
  -- best learned recipes for the next skill point (own file; nil if it did not load)
  local HS = Journal.HandwerkSkillpunkt
  u.next = HS and HS.build(right, R0, NEXT_Y, CW) or nil

  -- recipes (below the milestones)
  u.recHead = font(right, "title", G.size.l, "ink", "LEFT")
  u.recHead:SetPoint("TOPLEFT", right, "TOPLEFT", R0, -REC_Y)
  set(u.recHead, T.recipesHead)
  u.recCount = font(right, "label", G.size.s, "sepia", "RIGHT")
  u.recCount:SetPoint("TOPRIGHT", right, "TOPLEFT", R0 + CW, -(REC_Y + 4))
  u.recCount:SetWidth(160)
  u.recRule = Widgets.NewRule(right, R0, REC_Y + 24, CW)
  local function recList(rows, y, empty)
    local list = Widgets.NewList(right, { rows = rows, rowHeight = REC_ROW_H, width = CW + 10, step = 3, empty = empty, emptyHand = true,
      build = function(row)
        local dt = font(row, "label", G.size.xs, "sepia", "RIGHT")
        dt:SetWidth(120)
        dt:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.dt = dt
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -130, 0)
        D.RowStyle(row, { texts = { row.label, dt } })
      end,
      clear = function(row)
        row.dt:SetText("")
        if row.SetSelected then row:SetSelected(false) end
      end,
      fill = function(row, r)
        set(row.label, r.label)
        set(row.dt, join({ r.date, levelText(r.level) }))
        D.rowFilled(row)
      end })
    list.frame:SetPoint("TOPLEFT", right, "TOPLEFT", R0, -y)
    return list
  end
  u.recList = recList(REC_ROWS, REC_Y + 30, "")
  u.recEmpty = D.emptyNote(right, CW - 40, 14) -- smaller: only three list rows fit above the page foot since the skill point block
  u.recEmpty:SetPoint("TOP", right, "TOPLEFT", R0 + CW / 2, -(REC_Y + 34))
  -- nothing recorded at all
  u.empty = D.emptyNote(right, CW - 60, 19)
  u.empty:SetPoint("CENTER", right, "TOPLEFT", R0 + CW / 2, -(CHART_Y + 110))
  u.emptyTitle = font(right, "title", G.size.l, "ink", "CENTER")
  u.emptyTitle:SetPoint("BOTTOM", u.empty, "TOP", 0, 14)
  u.emptyTitle:SetWidth(CW - 20)
end

-- recipes with their dates, newest first
local function recipeRows(self, list)
  local out = {}
  for i = #list, 1, -1 do
    local r = list[i]
    out[#out + 1] = { label = r.label, date = dateText(self.index, r.t), level = r.level }
  end
  return out
end

local function showCurveParts(u, on)
  for _, e in ipairs({ u.curveRule, u.msRule, u.chart, u.first, u.recHead, u.recRule, u.recList.frame }) do
    if e.SetShown then e:SetShown(on) end
  end
  for _, m in ipairs(u.ms) do m.frame:SetShown(on) end
  if not on and u.next then Journal.HandwerkSkillpunkt.show(u.next, false) end
end

local function drawProfession(self, p)
  local u, res = self.R, self.res
  set(u.title, p.name)
  set(u.sub, join({ T("skillNow", int(p.rank), int(p.max)), p.rankName,
    p.kind == "primary" and T.primary or T.secondary }))
  set(u.curveHead, T.curveHead)
  showCurveParts(u, true)
  u.empty:SetText("")
  set(u.emptyTitle, "")
  drawChart(self, p, res)
  for i, m in ipairs(u.ms) do
    local ms = p.milestones[i]
    local got = ms and ms.t ~= nil
    m.num:SetTextColor(Widgets.color(got and "ink" or "sepia"))
    set(m.rank, Handwerk.TEXT["rank_" .. m.step])
    set(m.date, got and (dateText(self.index, ms.t) or "?") or T.open)
    m.date:SetTextColor(Widgets.color(got and "ink" or "sepia"))
    set(m.lvl, got and (levelText(ms.level) or "") or "")
    m.frame.tipLines = got and { p.name, T("milestoneTip", int(m.step)),
      join({ dateText(self.index, ms.t), levelText(ms.level) }) } or nil
  end
  local fc = p.firstCraft
  set(u.first, fc and (T.firstCraft .. ": " .. join({ fc.name, dateText(self.index, fc.t), levelText(fc.level) })) or "")
  -- best recipes for the next skill point (own book: live bag counts and the shopping list button)
  if u.next then
    local idx = self.index
    local own = type(idx) == "table" and idx.char ~= nil and ns.Store and ns.Store.char and idx.char == ns.Store.char() or false
    Journal.HandwerkSkillpunkt.draw(u.next, { line = p.line, char = idx and idx.char or nil, own = own })
  end
  -- recipes of this profession
  local n = #p.recipes
  set(u.recCount, n > 0 and plural(n, "rec") or "")
  u.recList:SetItems(recipeRows(self, p.recipes))
  if n == 0 then
    set(u.recEmpty, T.noRecipes) -- (the long "recipes cannot be assigned" hint is gone: the recipe book is its own sub-bookmark)
  else
    set(u.recEmpty, "")
  end
end

local function drawNothing(self)
  local u = self.R
  set(u.title, T.title)
  set(u.sub, "")
  set(u.curveHead, "")
  showCurveParts(u, false)
  u.curveRule:Hide()
  for _, pool in ipairs({ u.segs, u.labels, u.lines, u.dots, u.hits }) do pool:ReleaseAll() end
  set(u.recCount, "")
  set(u.recEmpty, "")
  set(u.emptyTitle, T.emptyTitle)
  set(u.empty, T.emptyBody)
end

function Page:Redraw()
  local res = self.res
  if not (self.built and res) then return end
  if self.L then self.L.list:Refresh() end
  local entry
  for _, e in ipairs(self.entries) do
    if e.key == self.sel then entry = e end
  end
  if not entry then
    drawNothing(self)
  else
    drawProfession(self, entry.p)
  end
end

-- chosen entry of the list (profession key)
function Page:Select(key)
  if not self.built or type(key) ~= "string" then return false end
  for _, e in ipairs(self.entries or {}) do
    if e.key == key then
      self.sel = key
      self:Redraw()
      return true
    end
  end
  return false
end

function Page:Build(left, right)
  -- the professions in their own holders so the sub-view "Rezeptbuch" (pages/HandwerkRezeptbuch.lua) can hide them
  local mainL, mainR = CreateFrame("Frame", nil, left), CreateFrame("Frame", nil, right)
  mainL:SetAllPoints(left)
  mainR:SetAllPoints(right)
  self.mainL, self.mainR = mainL, mainR
  self.holderL, self.holderR = left, right
  self.left, self.right = mainL, mainR
  self.entries = {}
  buildLeft(self, mainL)
  buildRight(self, mainR)
  self.built = true
end

-- sub-bookmarks (contract journal/Pages.lua): professions · recipe book. Labels are read late (the language is not yet fixed when
-- the file loads). The recipe book belongs to the logged-in character (cache and live data): not in the guest book.
local function subTab(key, label, tip)
  return setmetatable({ key = key }, { __index = function(_, k)
    if k == "label" then return T[label] end
    if k == "tip" then return { T[label], T[tip] } end
  end })
end
Page.subs = { subTab("berufe", "subBerufe", "subBerufeTip"), subTab("rezeptbuch", "subRezept", "subRezeptTip") }

function Page:GetSub()
  return self.rezOpen and "rezeptbuch" or "berufe"
end

function Page.OpenRezept(self)
  local View = Journal.RezeptbuchView
  if not (self.built and View) then return end
  if not Pages.guestAllows("handwerk", "rezeptbuch") then return end
  if not self.rez then self.rez = View.new(self, self.holderL, self.holderR) end
  self:HideTips()
  self.mainL:Hide()
  self.mainR:Hide()
  self.rezOpen = true
  self.rez:Open()
  Pages.subChanged("handwerk")
end

function Page.CloseRezept(self)
  local was = self.rezOpen
  if self.rez then self.rez:Close() end
  self.rezOpen = false
  if self.mainL then
    self.mainL:Show()
    self.mainR:Show()
  end
  if was then Pages.subChanged("handwerk") end
end

function Page:ShowSub(key)
  if key == "rezeptbuch" then
    if not self.rezOpen then Page.OpenRezept(self) end
  elseif self.rezOpen then
    Page.CloseRezept(self)
  end
end

function Page:Refresh(data)
  if not self.built then return end
  self.data = data
  self.index = data.index
  local res = Handwerk.aggregate(data.index)
  if not res then error("Handwerk: keine Auswertung") end
  self.res = res
  self.entries = entriesOf(res)
  -- keep the choice; first profession otherwise (or the recipe book when there is no profession)
  local ok = false
  for _, e in ipairs(self.entries) do
    if e.key == self.sel then ok = true end
  end
  if not ok then self.sel = self.entries[1] and self.entries[1].key or nil end
  self.R.head:SetTexts(Widgets.playerLine(data) or "", T.page)
  drawLeft(self, res)
  self:Redraw()
  if self.rezOpen and self.rez then
    if Pages.guestAllows("handwerk", "rezeptbuch") then
      self.rez:Refresh()
    else
      Page.CloseRezept(self) -- a guest book has no recipe cache of the logged-in character
    end
  end
end

function Page:HideTips()
  local L, R = self.L, self.R
  if L then
    for _, tile in ipairs(L.tiles) do Widgets.hideTip(tile.frame) end
    Widgets.hideTip(L.firstHit)
    for _, row in ipairs(L.list.rows) do Widgets.hideTip(row) end
  end
  if R then
    for _, h in ipairs(R.hits.used) do Widgets.hideTip(h) end
    for _, m in ipairs(R.ms) do Widgets.hideTip(m.frame) end
  end
end

-- leaving the tab: the next show starts with the professions again
function Page:OnHide()
  self:HideTips()
  if self.rezOpen then Page.CloseRezept(self) end
end

Pages.register("handwerk", Page)

-- the recipe book needs the view and the recipe model; never in Retail (cache and data are Forever's)
Pages.hideSub("handwerk", "rezeptbuch", function()
  local RB = Journal.Rezeptbuch
  return not (RB ~= nil and Journal.RezeptbuchView ~= nil and type(RB.active) == "function" and RB.active() == true)
end)

-- Retail: the Classic skill curve (75/150/225/300) and the skill lines do not exist there in this form: no tab, nothing is drawn
if Pages.hideTab then
  Pages.hideTab("handwerk", function() return not Handwerk.active() end)
end
