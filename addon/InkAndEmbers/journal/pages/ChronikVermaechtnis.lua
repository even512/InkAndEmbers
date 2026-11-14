-- Chronik sub-view "Vermächtnis" (WoW Forever only, account-wide), opened via the sub-bookmark (pages/Chronik.lua Page.subs); Esc leads
-- back to the overview. Data: model/Vermaechtnis.lua (read only, outside combat, cached in the SV).
-- Left page: title, points (earned of possible) and the level of the reward track, a thin progress line, the class challenges as a grid
-- (nine classes x Novice / Experienced / Master: done with date when readable, tooltip with the achievement name), the reward bar of
-- the track (rewards at level 15 / 25 / 40 / 55: item tooltip, collected or not). Right page: the three trees (professions, adventure,
-- progression) with node name and rank x/y; nodes without a readable name stay in pale as "Unbekannt".
-- Not readable (combat without cache, API missing): a friendly hint and a sticker "Neu lesen"; with a cache the last state is shown
-- with a note. Works only for the own book (the data is live: hidden in a guest book). Foreign text (item, spell, achievement and class
-- names) only via Sanitize.display. No ticker, no OnUpdate; the frames are built on first open.
local _, ns = ...

local Journal = ns.Journal
local W, Pages = Journal and Journal.Widgets, Journal and Journal.Pages
local D = W and W.Diary
local M = Journal and Journal.Vermaechtnis
local Page = Journal and Journal.ChronikPage
if not (W and Pages and D and M and Page) then return end

local floor, max, min = math.floor, math.max, math.min
local format = string.format

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
Journal.VermaechtnisView = View

View.TEXT = ns.Locale.ns("p.ChronikVermaechtnis", {
  page = "VERMÄCHTNIS", brand = "INK & EMBERS", title = "Vermächtnis",
  subLabel = "Vermächtnis", subTip = "Punkte, Klassen-Herausforderungen, Fertigkeitsbäume und Belohnungen des Vermächtnisses",
  subTip2 = "Gilt für das ganze Konto; nur in WoW Forever",
  points = "Punkte: %s von %s", pointsOnly = "Punkte: %s", pointsMax = "Mögliche Punkte: %s",
  level = "Vermächtnisstrecke: Stufe %s", levelOf = "Vermächtnisstrecke: Stufe %s von %s",
  classesHead = "Klassen-Herausforderungen", tier1 = "Novize", tier2 = "Erfahren", tier3 = "Meister",
  date = "{d}.{m}.{y}", doneShort = "erledigt", openShort = "offen",
  tipDone = "Erledigt am %s", tipDoneNoDate = "Erledigt", tipOpen = "Noch offen", tipPoints_other = "Bringt %s Punkte",
  tipPoints_one = "Bringt %s Punkt", tipOther = "Von einem anderen Charakter Eures Kontos verdient",
  tipTier = "%s · %s", classesUnreadable = "Die Klassen-Herausforderungen sind gerade nicht lesbar.",
  rewardsHead = "Belohnungen der Strecke", rewardLevel = "Stufe %s", rewardFallback = "Gegenstand #%s", rewardUnknown = "Belohnung",
  collected = "eingesammelt", ready = "bereit zum Einsammeln", reached = "erreicht",
  missing_one = "noch %s Punkt", missing_other = "noch %s Punkte", tipNeed = "Erreichbar ab Stufe %s der Vermächtnisstrecke",
  rewardsUnreadable = "Die Belohnungen sind gerade nicht lesbar.",
  treesTitle = "Fertigkeitsbäume", tree_professions = "Berufe", tree_adventure = "Abenteuer", tree_progression = "Fortschritt",
  rank = "%s/%s", tipRank = "Rang %s von %s", unknown = "Unbekannt", treeUnreadable = "Dieser Baum ist gerade nicht lesbar.",
  treeEmpty = "Keine Knoten gefunden.",
  hintCombat = "Im Kampf liest das Buch das Vermächtnis nicht. Schaut nach dem Kampf wieder herein.",
  hintUnreadable = "Das Vermächtnis lässt sich gerade nicht lesen. Versucht es in einem Moment noch einmal.",
  reread = "Neu lesen",
  challengesHead = "Herausforderungen", tabClasses = "Klassen", pageOf = "Seite %s von %s", tipProgress = "Fortschritt: %s von %s",
  progress = "%s/%s", colAch = "Herausforderung", colState = "Stand", colPoints = "Punkte", prevPage = "Vorherige Seite", nextPage = "Nächste Seite",
  staleCombat = "Im Kampf: gespeicherter Stand vom {date}", staleUnreadable = "Gerade nicht lesbar: gespeicherter Stand vom {date}",
})
local T = View.TEXT

View.NAME_W = 118              -- class column of the grid
View.CELL_W = floor((BODY_W - View.NAME_W) / 3)
View.ROW_H = 21                -- grid row
View.CLS_Y = 128               -- section head "Klassen-Herausforderungen"
View.REW_ROW_H = 32
View.NAME_MAX = 60
View.TAB_NAME_MAX = 60         -- a category name in a tab is shown whole up to this many bytes
View.TREES_Y = 102             -- first tree head on the right page (below the title; no sub line there)
View.TREE_HEAD_H = 28
View.TREE_ROW_MIN, View.TREE_ROW_MAX = 14, 20
View.BOTTOM = G.slots.body.bottom
View.NODES_ROWS = 12           -- node rows per tree (= Vermaechtnis.NODES_MAX)
View.LIST_ROWS = 9              -- rows of a challenge list (professions, PvP, ...): same room as the class grid
View.LIST_NAME_W, View.LIST_STATE_X, View.LIST_PTS_W = 236, 244, 46
View.TAB_MAX_W = BODY_W - 160  -- room of the tab switcher right of the head "Herausforderungen" (one row only)
View.TAB_SIZES = { 13, 12, 11 } -- font sizes of the tabs, tried from the largest (a smaller one only when two rows are not enough)
View.TAB_GAP = 12
View.TAB_ROW_H = 24            -- one row of tabs below the head
-- { grid / list row height, reward row height } by number of tab rows below the head (the page below the tabs moves down, so the rows get tighter)
View.LAYOUTS = { [0] = { 21, 32 }, [1] = { 20, 29 }, [2] = { 19, 26 }, [3] = { 17, 26 } }
View.LIST_HEAD_X = { 2, 244 + 18, 398 - 46 - 4 }   -- x of the list column heads (= LIST_STATE_X + 18, BODY_W - LIST_PTS_W - 4)
View.NODES_SHOWN = 9           -- nodes shown per tree (the trees have 9: three of them fill the page at the smallest row height)

local function disp(v, n)
  local S = ns.Sanitize
  return S and S.display(v, n or View.NAME_MAX) or nil
end

local function int(n)
  local Tx = Journal.Texts
  if Tx and Tx.int then return Tx.int(n) end
  return tostring(n)
end

local function set(fs, s) W.setText(fs, s) end

local function font(parent, kind, size, color, justify)
  local fs = W.font(parent, kind, size, color)
  if justify then fs:SetJustifyH(justify) end
  return fs
end

local function dateText(t)
  if type(t) ~= "table" or not (t.d and t.m and t.y) then return nil end
  return T("date", { d = format("%02d", t.d), m = format("%02d", t.m), y = format("%04d", t.y) })
end

local function stampText(at)
  if type(at) ~= "number" or at <= 0 or type(date) ~= "function" then return nil end
  local ok, d, m, y = pcall(function() return tonumber(date("%d", at)), tonumber(date("%m", at)), tonumber(date("%Y", at)) end)
  if not (ok and d and m and y) then return nil end
  return dateText({ d = d, m = m, y = y })
end

local function ownClass()
  if type(UnitClass) ~= "function" then return nil end
  local ok, _, file = pcall(UnitClass, "player")
  if ok and type(file) == "string" and not (type(issecretvalue) == "function" and issecretvalue(file)) then return file end
  return nil
end

-- frames ------------------------------------------------------------------------------------------------------------------------

-- Original achievement tooltip: GameTooltip:SetHyperlink(the "achievement:" part of GetAchievementLink(id)), then our lines (state, points) below.
-- Everything in pcall; without a link / on an error the text tooltip of the lines. lines[1] = title, the rest = extra lines.
function View.achTip(owner, id, lines)
  local tt, getLink = rawget(_G, "GameTooltip"), rawget(_G, "GetAchievementLink")
  if type(tt) == "table" and type(getLink) == "function" and type(id) == "number" then
    local ok, shown = pcall(function()
      local link = getLink(id)
      if type(link) ~= "string" or (type(issecretvalue) == "function" and issecretvalue(link)) then return false end
      local h = string.match(link, "|H(achievement:[%w:%-]+)|h")
      if not h or #h > 120 then return false end
      tt:SetOwner(owner, "ANCHOR_RIGHT")
      tt:SetHyperlink(h)
      local n = type(tt.NumLines) == "function" and tt:NumLines() or 1
      if type(n) ~= "number" or n < 1 then return false end
      for i = 2, #lines do tt:AddLine(lines[i], 0.85, 0.8, 0.7, true) end
      tt:Show()
      return true
    end)
    if ok and shown then return true end
    if tt.Hide then pcall(tt.Hide, tt) end
  end
  W.tip(owner, lines)
  return false
end

local function hover(frame, build)
  frame:EnableMouse(true)
  frame:SetScript("OnEnter", function(x)
    local lines = build(x)
    if lines then W.tip(x, lines) end
  end)
  frame:SetScript("OnLeave", function(x) W.hideTip(x) end)
end

local function buildClassRow(self, parent, i)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(BODY_W, View.ROW_H)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", BODY_X, -(self.gridY + (i - 1) * View.ROW_H))
  local line = W.NewRect(row, "sepia", 0.18, "BORDER")
  line:SetHeight(1)
  line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
  line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  row.name = font(row, "text", SZ.s + 1, "ink", "LEFT")
  row.name:SetPoint("LEFT", row, "LEFT", 2, 0)
  row.name:SetWidth(View.NAME_W - 6)
  row.name:SetWordWrap(false)
  row.cells = {}
  for t = 1, M.TIERS do
    local c = CreateFrame("Frame", nil, row)
    c:SetSize(View.CELL_W, View.ROW_H)
    c:SetPoint("LEFT", row, "LEFT", View.NAME_W + (t - 1) * View.CELL_W, 0)
    c.tick = D.mark(c, "tick", 13, "red", "OVERLAY")
    c.tick:SetPoint("LEFT", c, "LEFT", 6, 0)
    c.text = font(c, "text", SZ.xs, "ink", "LEFT")
    c.text:SetPoint("LEFT", c, "LEFT", 24, 0)
    c.text:SetWidth(View.CELL_W - 26)
    c.text:SetWordWrap(false)
    c.tier = t
    c:EnableMouse(true)
    c:SetScript("OnEnter", function(x) if x.tipLines then View.achTip(x, x.tipId, x.tipLines) end end)
    c:SetScript("OnLeave", function(x) W.hideTip(x) end)
    row.cells[t] = c
  end
  return row
end

-- row of a challenge list: name, state (tick + date / progress / "offen"), points
local function buildListRow(self, parent, i)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(BODY_W, View.ROW_H)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", BODY_X, -(self.gridY + (i - 1) * View.ROW_H))
  local line = W.NewRect(row, "sepia", 0.18, "BORDER")
  line:SetHeight(1)
  line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
  line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  row.name = font(row, "text", SZ.s + 1, "ink", "LEFT")
  row.name:SetPoint("LEFT", row, "LEFT", 2, 0)
  row.name:SetWidth(View.LIST_NAME_W - 4)
  row.name:SetWordWrap(false)
  row.tick = D.mark(row, "tick", 13, "red", "OVERLAY")
  row.tick:SetPoint("LEFT", row, "LEFT", View.LIST_STATE_X, 0)
  row.state = font(row, "text", SZ.xs, "ink", "LEFT")
  row.state:SetPoint("LEFT", row, "LEFT", View.LIST_STATE_X + 18, 0)
  row.state:SetWidth(BODY_W - View.LIST_STATE_X - 18 - View.LIST_PTS_W - 4)
  row.state:SetWordWrap(false)
  row.pts = font(row, "text", SZ.xs, "ink", "RIGHT")
  row.pts:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  row.pts:SetWidth(View.LIST_PTS_W)
  row.pts:SetWordWrap(false)
  row:EnableMouse(true)
  row:SetScript("OnEnter", function(x) if x.tipLines then View.achTip(x, x.tipId, x.tipLines) end end)
  row:SetScript("OnLeave", function(x) W.hideTip(x) end)
  row:Hide()
  return row
end

local function buildRewardRow(self, parent, i)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(BODY_W, View.REW_ROW_H)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", BODY_X, -(self.rewY + (i - 1) * View.REW_ROW_H))
  local line = W.NewRect(row, "sepia", 0.18, "BORDER")
  line:SetHeight(1)
  line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
  line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  row.level = font(row, "title", SZ.m, "red", "LEFT")
  row.level:SetPoint("LEFT", row, "LEFT", 2, 0)
  row.level:SetWidth(64)
  row.level:SetWordWrap(false)
  row.name = font(row, "text", SZ.s + 1, "ink", "LEFT")
  row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 70, -4)
  row.name:SetWidth(BODY_W - 78 - 26)
  row.name:SetWordWrap(false)
  row.status = font(row, "label", SZ.xs, "sepia", "LEFT")
  row.status:SetPoint("TOPLEFT", row, "TOPLEFT", 70, -19)
  row.status:SetWidth(BODY_W - 100)
  row.status:SetWordWrap(false)
  row.tick = D.mark(row, "tick", 14, "red", "OVERLAY")
  row.tick:SetPoint("RIGHT", row, "RIGHT", -6, 0)
  hover(row, function(x) return x.tipLines end)
  return row
end

-- Original game tooltip of a tree node: GameTooltip:SetSpellByID(spellID) (the spell id comes from the node data and the cache), the rank
-- as an extra line. Everything in pcall; the tooltip counts only when it holds a line of text. -> true when shown
function View.spellTip(owner, node)
  local tt = rawget(_G, "GameTooltip")
  if type(tt) ~= "table" or type(tt.SetSpellByID) ~= "function" or not node.spell then return false end
  local ok, shown = pcall(function()
    tt:SetOwner(owner, "ANCHOR_RIGHT")
    tt:SetSpellByID(node.spell)
    local lines = type(tt.NumLines) == "function" and tt:NumLines() or 1
    local first = rawget(_G, "GameTooltipTextLeft1")
    local head = type(first) == "table" and type(first.GetText) == "function" and first:GetText() or "x"
    if type(lines) ~= "number" or lines < 1 or type(head) ~= "string" or head == "" then return false end
    tt:AddLine(T("tipRank", int(node.rank), int(node.max)), 0.85, 0.8, 0.7, true)
    tt:Show()
    return true
  end)
  if ok and shown then return true end
  if tt.Hide then pcall(tt.Hide, tt) end
  return false
end

local function buildTreeRow(self, parent, y)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(SR.w, View.TREE_ROW_MIN)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", SR.x, -y)
  local line = W.NewRect(row, "sepia", 0.16, "BORDER")
  line:SetHeight(1)
  line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
  line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  row.name = font(row, "text", SZ.xs + 1, "ink", "LEFT")
  row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
  row.name:SetWidth(SR.w - 70)
  row.name:SetWordWrap(false)
  row.rank = font(row, "text", SZ.xs + 1, "ink", "RIGHT")
  row.rank:SetPoint("RIGHT", row, "RIGHT", -6, 0)
  row.rank:SetWidth(56)
  row.rank:SetWordWrap(false)
  row:EnableMouse(true)
  row:SetScript("OnEnter", function(x)
    if x.node and View.spellTip(x, x.node) then return end
    if x.tipLines then W.tip(x, x.tipLines) end
  end)
  row:SetScript("OnLeave", function(x) W.hideTip(x) end)
  row:Hide()
  return row
end

function View.new(page, left, right)
  local self = setmetatable({ page = page }, View)
  local l, r = CreateFrame("Frame", nil, left), CreateFrame("Frame", nil, right)
  l:SetAllPoints(left)
  r:SetAllPoints(right)
  self.l, self.r = l, r
  W.NewPageHead(l, { side = "L" }):SetTexts(T.brand, T.page)
  W.NewPageHead(r, { side = "R" }):SetTexts("", T.page)
  D.escKeys(l, function() page:CloseSub() end) -- Esc -> overview

  -- left page: title, points line, progress line
  local head = D.NewSectionHead(l, T.title, { size = SZ.xl })
  head:SetPoint("TOPLEFT", l, "TOPLEFT", IN_X, -(TITLE_Y - 6))
  self.sub = font(l, "label", SZ.s, "sepia", "LEFT")
  self.sub:SetPoint("TOPLEFT", l, "TOPLEFT", IN_X, -SUB_Y)
  self.sub:SetWidth(SL.x + SL.w - IN_X)
  self.sub:SetWordWrap(false)
  self.note = font(l, "label", SZ.xs, "sepia", "RIGHT")
  local pt, fx, fy = Theme.gridFoot("L")
  self.note:SetPoint(pt, l, "TOPLEFT", fx, -(fy + 6))
  self.note:SetWidth(SL.x + SL.w - Theme.gridX("L", 2))
  self.note:SetWordWrap(false)

  -- hint (nothing readable) with the sticker "Neu lesen"
  self.hint = D.emptyNote(l, BODY_W - 40)
  self.hint:SetPoint("TOP", l, "TOPLEFT", SL.x + SL.w / 2, -(G.slots.body.y + 40))
  self.reread = D.NewSticker(l, T.reread, function() self:Reload(true) end, { height = 40 })
  self.reread:SetPoint("TOP", l, "TOPLEFT", SL.x + SL.w / 2, -(G.slots.body.y + 130))
  self.reread:Hide()

  -- content of the left page
  local lc = CreateFrame("Frame", nil, l)
  lc:SetAllPoints(l)
  self.lc = lc
  self.bar = W.NewRect(lc, "sepia", 0.22, "ARTWORK")
  self.bar:SetPoint("TOPLEFT", lc, "TOPLEFT", IN_X, -(SUB_Y + 17))
  self.bar:SetSize(SL.x + SL.w - IN_X - 4, 5)
  self.barFill = W.NewRect(lc, "red", 0.75, "OVERLAY")
  self.barFill:SetPoint("TOPLEFT", self.bar, "TOPLEFT", 0, 0)
  self.barFill:SetSize(1, 5)
  self.barFill:Hide()

  local ch = D.NewSectionHead(lc, T.classesHead, { width = BODY_W, size = 18 })
  ch:SetPoint("TOPLEFT", lc, "TOPLEFT", BODY_X, -View.CLS_Y)
  self.classesHead = ch
  local tierY = View.CLS_Y + 30
  self.tierHeads = {}
  for t = 1, M.TIERS do
    local fs = font(lc, "label", SZ.xs, "sepia", "LEFT")
    fs:SetPoint("TOPLEFT", lc, "TOPLEFT", BODY_X + View.NAME_W + (t - 1) * View.CELL_W + 24, -tierY)
    fs:SetWidth(View.CELL_W - 26)
    fs:SetWordWrap(false)
    set(fs, T["tier" .. t])
    self.tierHeads[t] = fs
  end
  self.gridY = tierY + 16
  self.classRows = {}
  for i = 1, #M.CLASSES do self.classRows[i] = buildClassRow(self, lc, i) end
  self.classesNote = font(lc, "text", SZ.s, "sepia", "LEFT")
  self.classesNote:SetPoint("TOPLEFT", lc, "TOPLEFT", BODY_X + 2, -(self.gridY + 6))
  self.classesNote:SetWidth(BODY_W - 8)
  self.classesNote:SetWordWrap(true)

  -- challenge lists (the other groups): rows, column heads, paging; the tab switcher sits right of the head
  self.listRows = {}
  for i = 1, View.LIST_ROWS do self.listRows[i] = buildListRow(self, lc, i) end
  self.listHeads = {}
  for i, spec in ipairs({ { "colAch", 2, View.LIST_NAME_W - 4, "LEFT" }, { "colState", View.LIST_STATE_X + 18, 80, "LEFT" },
    { "colPoints", BODY_W - View.LIST_PTS_W - 4, View.LIST_PTS_W, "RIGHT" } }) do
    local fs = font(lc, "label", SZ.xs, "sepia", spec[4])
    fs:SetPoint("TOPLEFT", lc, "TOPLEFT", BODY_X + spec[2], -tierY)
    fs:SetWidth(spec[3])
    fs:SetWordWrap(false)
    set(fs, T[spec[1]])
    fs:Hide()
    self.listHeads[i] = fs
  end
  self.nav = D.NewNavPair(lc, { size = 16, onPrev = function() self:StepPage(-1) end, onNext = function() self:StepPage(1) end,
    tipPrev = { T.prevPage }, tipNext = { T.nextPage } })
  self.nav.frame:SetPoint("TOPRIGHT", lc, "TOPLEFT", BODY_X + BODY_W, -(tierY - 6))
  self.nav.frame:Hide()
  self.pageText = font(lc, "label", SZ.xs, "sepia", "RIGHT")
  self.pageText:SetPoint("RIGHT", self.nav.frame, "LEFT", -4, 0)
  self.pageText:SetWidth(120)
  self.pageText:SetWordWrap(false)
  self.group, self.pageNo = "classes", 1
  self.tabSets, self.tabRows = {}, 0
  self.rowH, self.rewH = View.ROW_H, View.REW_ROW_H

  self.rewHeadY = self.gridY + #M.CLASSES * View.ROW_H + 12
  local rh = D.NewSectionHead(lc, T.rewardsHead, { width = BODY_W, size = 18 })
  rh:SetPoint("TOPLEFT", lc, "TOPLEFT", BODY_X, -self.rewHeadY)
  self.rewardsHead = rh
  self.rewBarY = self.rewHeadY + 34
  self.rewBar = W.NewRect(lc, "sepia", 0.22, "ARTWORK")
  self.rewBar:SetPoint("TOPLEFT", lc, "TOPLEFT", BODY_X + 2, -self.rewBarY)
  self.rewBar:SetSize(BODY_W - 4, 6)
  self.rewFill = W.NewRect(lc, "red", 0.75, "OVERLAY")
  self.rewFill:SetPoint("TOPLEFT", self.rewBar, "TOPLEFT", 0, 0)
  self.rewFill:SetSize(1, 6)
  self.rewFill:Hide()
  self.rewTicks = {}
  local top = M.REWARD_LEVELS[#M.REWARD_LEVELS]
  for i, lvl in ipairs(M.REWARD_LEVELS) do
    local tk = W.NewRect(lc, "ink", 0.8, "OVERLAY")
    tk:SetSize(2, 12)
    tk:SetPoint("TOPLEFT", self.rewBar, "TOPLEFT", floor((BODY_W - 4) * lvl / top + 0.5) - (lvl == top and 2 or 1), 3)
    self.rewTicks[i] = tk
  end
  self.rewY = self.rewBarY + 20
  self.rewRows = {}
  for i = 1, #M.REWARD_LEVELS do self.rewRows[i] = buildRewardRow(self, lc, i) end
  self.rewNote = font(lc, "text", SZ.s, "sepia", "LEFT")
  self.rewNote:SetPoint("TOPLEFT", lc, "TOPLEFT", BODY_X + 2, -(self.rewY + 6))
  self.rewNote:SetWidth(BODY_W - 8)
  self.rewNote:SetWordWrap(true)

  -- right page: trees
  local rc = CreateFrame("Frame", nil, r)
  rc:SetAllPoints(r)
  self.rc = rc
  self.treesTitle = font(rc, "title", SZ.xl, "ink", "LEFT")
  self.treesTitle:SetPoint("TOPLEFT", rc, "TOPLEFT", SR.x, -G.slots.title.y)
  self.treesTitle:SetWidth(SR.w)
  self.treesTitle:SetWordWrap(false)
  set(self.treesTitle, T.treesTitle)
  self.trees = {}
  for i, def in ipairs(M.TREES) do
    local h = D.NewSectionHead(rc, T["tree_" .. def.key], { width = SR.w, size = 18 })
    local u = { head = h, rows = {}, key = def.key }
    for k = 1, View.NODES_ROWS do u.rows[k] = buildTreeRow(self, rc, View.TREES_Y) end
    u.note = font(rc, "text", SZ.s, "sepia", "LEFT")
    u.note:SetWidth(SR.w - 8)
    u.note:SetWordWrap(true)
    self.trees[i] = u
  end
  self:Relayout(0)
  -- a finished discovery scan (model) brings the new groups
  M.onScanDone(function() if self.open then self:Reload(true) end end)
  l:Hide()
  r:Hide()
  return self
end

function View:IsOpen() return self.open == true end

-- drawing -----------------------------------------------------------------------------------------------------------------------

local function pointsLine(d)
  local parts = {}
  if d.points and d.pointsMax then
    parts[#parts + 1] = T("points", int(d.points), int(d.pointsMax))
  elseif d.points then
    parts[#parts + 1] = T("pointsOnly", int(d.points))
  elseif d.pointsMax then
    parts[#parts + 1] = T("pointsMax", int(d.pointsMax))
  end
  if d.level and d.levelMax then
    parts[#parts + 1] = T("levelOf", int(d.level), int(d.levelMax))
  elseif d.level then
    parts[#parts + 1] = T("level", int(d.level))
  end
  return table.concat(parts, " · ")
end

function View:DrawHeader(d)
  set(self.sub, pointsLine(d))
  W.fitLine(self.sub, SL.x + SL.w - IN_X, 11)
  local full = BODY_W - 4 - (IN_X - BODY_X)
  local frac = (d.points and d.pointsMax and d.pointsMax > 0) and min(1, d.points / d.pointsMax) or nil
  self.bar:SetWidth(max(1, full))
  if frac and frac > 0 then
    self.barFill:SetWidth(max(2, floor(full * frac + 0.5)))
    self.barFill:Show()
  else
    self.barFill:Hide()
  end
end

local function tierLabel(t) return T["tier" .. t] end

-- text lines of an achievement tooltip (also the fallback without the client tooltip): title, state, other character, points, progress
local function achLines(tr, title)
  local lines = { title }
  if tr.done then
    local dt = dateText(tr)
    lines[#lines + 1] = dt and T("tipDone", dt) or T.tipDoneNoDate
    if not tr.mine then lines[#lines + 1] = T.tipOther end
  else
    lines[#lines + 1] = T.tipOpen
  end
  if tr.pts then lines[#lines + 1] = T(ns.Locale.plural(tr.pts, "tipPoints_one", "tipPoints_other"), int(tr.pts)) end
  if not tr.done and tr.cur and tr.tot then lines[#lines + 1] = T("tipProgress", int(tr.cur), int(tr.tot)) end
  return lines
end

-- state text of a cell / row: date or "erledigt", progress or "offen"
local function stateText(tr)
  if tr.done then return dateText(tr) or T.doneShort end
  if tr.cur and tr.tot then return T("progress", int(tr.cur), int(tr.tot)) end
  return T.openShort
end

function View:DrawClasses(d)
  local mine = ownClass()
  local byFile = {}
  for _, c in ipairs(d.classes) do byFile[c.file] = c end
  local any = false
  for i, def in ipairs(M.CLASSES) do
    local row = self.classRows[i]
    local c = byFile[def.file]
    if c and #c.tiers > 0 then any = true end
    row:Show()
    set(row.name, (c and disp(c.name) or disp(def.file)) or "")
    W.fitLine(row.name, View.NAME_W - 6, 10)
    row.name:SetTextColor(W.color(mine == def.file and "red" or "ink"))
    for t = 1, M.TIERS do
      local cell = row.cells[t]
      local tr = c and c.tiers[t]
      cell.tipLines, cell.tipId = nil, nil
      if not tr then
        cell.tick:Hide()
        set(cell.text, "")
      else
        local title = disp(tr.name) or T("tipTier", disp(c.name) or disp(def.file) or "", tierLabel(t))
        cell.tick:SetShown(tr.done == true)
        set(cell.text, stateText(tr))
        cell.text:SetTextColor(W.color(tr.done and "ink" or "faint"))
        cell.tipLines, cell.tipId = achLines(tr, title), tr.id
      end
    end
  end
  for _, fs in ipairs(self.tierHeads) do fs:Show() end
  set(self.classesNote, "")
  if not any then
    for _, row in ipairs(self.classRows) do row:Hide() end
    for _, fs in ipairs(self.tierHeads) do fs:Hide() end
    set(self.classesNote, T.classesUnreadable)
  end
end

-- a challenge list (professions, PvP, ...), nine rows per page
function View:DrawList(g)
  local items = g.items
  local pages = max(1, math.ceil(#items / View.LIST_ROWS))
  self.pageNo = max(1, min(self.pageNo or 1, pages))
  for i, row in ipairs(self.listRows) do
    local it = items[(self.pageNo - 1) * View.LIST_ROWS + i]
    if it then
      local name = disp(it.name) or ("#" .. format("%.0f", it.id))
      row:Show()
      set(row.name, name)
      W.fitLine(row.name, View.LIST_NAME_W - 4, 10)
      row.tick:SetShown(it.done == true)
      set(row.state, stateText(it))
      row.state:SetTextColor(W.color(it.done and "ink" or "faint"))
      set(row.pts, it.pts and ("+" .. int(it.pts)) or "")
      row.tipLines, row.tipId = achLines(it, name), it.id
    else
      row.tipLines, row.tipId = nil, nil
      row:Hide()
    end
  end
  if pages > 1 then
    self.nav.frame:Show()
    self.nav:SetEnabled(self.pageNo > 1, self.pageNo < pages)
    set(self.pageText, T("pageOf", int(self.pageNo), int(pages)))
  else
    self.nav.frame:Hide()
    set(self.pageText, "")
  end
end

-- Positions of everything below the head "Herausforderungen" for a number of tab rows (0 = tabs beside the head or none). Rows of the grid / list
-- and of the rewards get tighter the more rows of tabs push the page down, so the rewards still end on the page.
function View:Relayout(tabRows)
  tabRows = max(0, min(3, tabRows or 0))
  local lc = self.lc
  local lay = View.LAYOUTS[tabRows]
  local rowH, rewH = lay[1], lay[2]
  local tierY = View.CLS_Y + 30 + tabRows * View.TAB_ROW_H
  local gridY = tierY + 16
  self.tierY, self.gridY, self.rowH, self.rewH = tierY, gridY, rowH, rewH
  local function at(f, x, y, point)
    f:ClearAllPoints()
    f:SetPoint(point or "TOPLEFT", lc, "TOPLEFT", x, -y)
  end
  for t, fs in ipairs(self.tierHeads) do at(fs, BODY_X + View.NAME_W + (t - 1) * View.CELL_W + 24, tierY) end
  for i, fs in ipairs(self.listHeads) do at(fs, BODY_X + View.LIST_HEAD_X[i], tierY) end
  for i, row in ipairs(self.classRows) do
    row:SetHeight(rowH)
    at(row, BODY_X, gridY + (i - 1) * rowH)
    for _, c in ipairs(row.cells) do c:SetHeight(rowH) end
  end
  for i, row in ipairs(self.listRows) do
    row:SetHeight(rowH)
    at(row, BODY_X, gridY + (i - 1) * rowH)
  end
  at(self.classesNote, BODY_X + 2, gridY + 6)
  at(self.nav.frame, BODY_X + BODY_W, tierY - 6, "TOPRIGHT")
  local rewHeadY = gridY + #M.CLASSES * rowH + 12
  local rewBarY = rewHeadY + 34
  local rewY = rewBarY + 20
  self.rewHeadY, self.rewBarY, self.rewY = rewHeadY, rewBarY, rewY
  at(self.rewardsHead, BODY_X, rewHeadY)
  at(self.rewBar, BODY_X + 2, rewBarY)
  for i, row in ipairs(self.rewRows) do
    row:SetHeight(rewH)
    at(row, BODY_X, rewY + (i - 1) * rewH)
    -- the two text lines (name, status) move closer together in a tighter row
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 70, -(rewH >= 32 and 4 or 2))
    row.status:ClearAllPoints()
    row.status:SetPoint("TOPLEFT", row, "TOPLEFT", 70, -(rewH - 12))
  end
  at(self.rewNote, BODY_X + 2, rewY + 6)
end

local function tabItems(list)
  local out = {}
  for i, it in ipairs(list) do out[i] = { key = it.key, label = it.name, tip = { it.name } } end
  return out
end

-- the toggles of one font size: a hidden one to measure, one per row (made when needed)
function View:TabSet(size)
  local set = self.tabSets[size]
  if not set then
    set = { size = size, rows = {} }
    self.tabSets[size] = set
    set.measure = D.NewToggle(self.lc, { size = size, gap = View.TAB_GAP, items = {} })
    set.measure.frame:Hide()
  end
  return set
end

function View:TabRow(set, n)
  local tg = set.rows[n]
  if not tg then
    tg = D.NewToggle(self.lc, { size = set.size, gap = View.TAB_GAP, items = {}, onChange = function(key) self:SelectGroup(key) end })
    tg.frame:Hide()
    set.rows[n] = tg
  end
  return tg
end

-- fills rows from the left, a tab goes to the next row when it does not fit any more (names are never shortened)
local function fillRows(set, full, maxW)
  local rows, cur = {}, {}
  for _, it in ipairs(full) do
    cur[#cur + 1] = it
    set.measure:SetItems(tabItems(cur))
    if #cur > 1 and (tonumber(set.measure.frame:GetWidth()) or 0) > maxW then
      cur[#cur] = nil
      rows[#rows + 1] = cur
      cur = { it }
    end
  end
  if #cur > 0 then rows[#rows + 1] = cur end
  return rows
end

function View:HideTabs()
  for _, set in pairs(self.tabSets) do
    for _, tg in ipairs(set.rows) do tg.frame:Hide() end
  end
  self.tabRows, self.tabsShown, self.tabList = 0, false, {}
end

-- all shown tab buttons in reading order
function View:TabButtons()
  local out = {}
  for _, b in ipairs(self.tabList or {}) do out[#out + 1] = b end
  return out
end

-- tab switcher: "Klassen" plus one tab per found group. One row beside the head when everything fits there; otherwise the tabs go below the
-- head in rows of the full width (two at most; only when that is not enough the font gets a size smaller, three rows only at the smallest).
function View:DrawTabs(d)
  local full = { { key = "classes", name = T.tabClasses } }
  for _, g in ipairs(d.groups) do full[#full + 1] = { key = g.key, name = disp(g.name, View.TAB_NAME_MAX) or "?" } end
  self:HideTabs()
  self.classesHead:SetText(T.challengesHead)
  local set = self:TabSet(View.TAB_SIZES[1])
  local rows = fillRows(set, full, View.TAB_MAX_W)
  local below = #rows > 1
  if below then
    for _, size in ipairs(View.TAB_SIZES) do
      set = self:TabSet(size)
      rows = fillRows(set, full, BODY_W)
      if #rows <= 2 then break end
    end
  end
  for r, list in ipairs(rows) do
    local tg = self:TabRow(set, r)
    tg:SetItems(tabItems(list))
    tg:SetValue(self.group)
    tg.frame:ClearAllPoints()
    if below then
      tg.frame:SetPoint("TOPLEFT", self.lc, "TOPLEFT", BODY_X, -(View.CLS_Y + 28 + (r - 1) * View.TAB_ROW_H))
    else
      tg.frame:SetPoint("TOPRIGHT", self.lc, "TOPLEFT", BODY_X + BODY_W, -(View.CLS_Y + 4))
    end
    tg.frame:Show()
    for _, btn in ipairs(tg.buttons) do
      if btn.item then self.tabList[#self.tabList + 1] = btn end
    end
  end
  self.tabsShown = true
  self.tabRows = below and #rows or 0
end

function View:DrawChallenges(d)
  local chosen
  for _, g in ipairs(d.groups) do
    if g.key == self.group then chosen = g end
  end
  if not chosen then self.group = "classes" end
  local tabs = #d.groups > 0
  if tabs then
    self:DrawTabs(d)
  else
    self.classesHead:SetText(T.classesHead)
    self:HideTabs()
  end
  self:Relayout(self.tabRows)
  if chosen then
    for _, row in ipairs(self.classRows) do row:Hide() end
    for _, fs in ipairs(self.tierHeads) do fs:Hide() end
    set(self.classesNote, "")
    for _, fs in ipairs(self.listHeads) do fs:Show() end
    self:DrawList(chosen)
  else
    for _, fs in ipairs(self.listHeads) do fs:Hide() end
    for _, row in ipairs(self.listRows) do row:Hide() end
    self.nav.frame:Hide()
    set(self.pageText, "")
    self:DrawClasses(d)
  end
end

function View:SelectGroup(key)
  self.group, self.pageNo = key, 1
  if self.data then self:DrawChallenges(self.data) end
end

function View:StepPage(delta)
  self.pageNo = (self.pageNo or 1) + delta
  if self.data then self:DrawChallenges(self.data) end
end

function View:DrawRewards(d)
  local byLevel = {}
  for _, r in ipairs(d.rewards) do byLevel[r.level] = r end
  local level = d.level or d.points or 0
  local top = M.REWARD_LEVELS[#M.REWARD_LEVELS]
  local full = BODY_W - 4
  if level > 0 then
    self.rewFill:SetWidth(max(2, floor(full * min(1, level / top) + 0.5)))
    self.rewFill:Show()
  else
    self.rewFill:Hide()
  end
  local any = false
  for i, lvl in ipairs(M.REWARD_LEVELS) do
    local row = self.rewRows[i]
    local r = byLevel[lvl]
    if r and (r.itemID or r.name) then any = true end
    row:Show()
    set(row.level, T("rewardLevel", int(lvl)))
    local name = r and (disp(r.name) or (r.itemID and T("rewardFallback", int(r.itemID)))) or T.rewardUnknown
    set(row.name, name)
    W.fitLine(row.name, BODY_W - 78 - 26, 10)
    local reached = (d.level or d.points) ~= nil and level >= lvl
    local status, got
    -- isCollected alone is not reliable (the probe reported true for a reward far above the level): "collected" only from the reached level on
    if reached and r and r.collected == true then
      status, got = T.collected, true
    elseif reached then
      status = (r and r.collected == false) and T.ready or T.reached
    else
      local n = lvl - level
      status = T(ns.Locale.plural(n, "missing_one", "missing_other"), int(n))
    end
    set(row.status, status)
    row.status:SetTextColor(W.color(reached and "ink" or "faint"))
    row.name:SetTextColor(W.color(reached and "ink" or "sepia"))
    row.tick:SetShown(got == true)
    local lines = { name, status }
    if not reached then lines[#lines + 1] = T("tipNeed", int(lvl)) end
    if r and r.itemID then
      lines.item = "item:" .. format("%.0f", r.itemID)
      lines.itemExtra = { status, lines[3] }
    end
    row.tipLines = lines
  end
  set(self.rewNote, "")
  if not any then
    for _, row in ipairs(self.rewRows) do row:Hide() end
    set(self.rewNote, T.rewardsUnreadable)
  end
end

function View:DrawTrees(d)
  local byKey = {}
  for _, t in ipairs(d.trees) do byKey[t.key] = t end
  -- row height from the number of rows to show (an unreadable / empty tree takes one note line)
  local rows = 0
  for _, def in ipairs(M.TREES) do
    local t = byKey[def.key]
    rows = rows + ((t and #t.nodes > 0) and min(#t.nodes, View.NODES_SHOWN) or 2)
  end
  local avail = View.BOTTOM - View.TREES_Y - #M.TREES * View.TREE_HEAD_H - (#M.TREES - 1) * 4
  local rowH = max(View.TREE_ROW_MIN, min(View.TREE_ROW_MAX, floor(avail / max(1, rows))))
  local y = View.TREES_Y
  for i, def in ipairs(M.TREES) do
    local u = self.trees[i]
    local t = byKey[def.key]
    u.head:ClearAllPoints()
    u.head:SetPoint("TOPLEFT", self.rc, "TOPLEFT", SR.x, -y)
    u.head:Show()
    y = y + View.TREE_HEAD_H
    local nodes = t and t.nodes or {}
    local shown = min(#nodes, View.NODES_SHOWN)
    for k, row in ipairs(u.rows) do
      local n = k <= shown and nodes[k] or nil
      if n then
        row:SetHeight(rowH)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.rc, "TOPLEFT", SR.x, -(y + (k - 1) * rowH))
        local name = disp(n.name)
        set(row.name, name or T.unknown)
        W.fitLine(row.name, SR.w - 70, 10)
        row.name:SetTextColor(W.color((name and n.rank > 0) and "ink" or (name and "sepia" or "faint")))
        set(row.rank, T("rank", int(n.rank), int(n.max)))
        row.rank:SetTextColor(W.color(n.rank >= n.max and "red" or (n.rank > 0 and "ink" or "faint")))
        row.node = n
        -- text fallback; an unknown node shows a tooltip only when the game tooltip has something sensible
        row.tipLines = name and { name, T("tipRank", int(n.rank), int(n.max)) } or nil
        row:Show()
      else
        row.tipLines, row.node = nil, nil
        row:Hide()
      end
    end
    if shown > 0 then
      set(u.note, "")
      y = y + shown * rowH + 4
    else
      u.note:ClearAllPoints()
      u.note:SetPoint("TOPLEFT", self.rc, "TOPLEFT", SR.x + 4, -(y + 2))
      set(u.note, (t and t.readable) and T.treeEmpty or T.treeUnreadable)
      y = y + 2 * rowH + 4
    end
  end
end

function View:Render()
  local d, st, why = self.data, self.status, self.why
  local has = d ~= nil
  self.lc:SetShown(has)
  self.rc:SetShown(has)
  if not has then
    set(self.sub, "")
    set(self.note, "")
    set(self.hint, st == "combat" and T.hintCombat or (st == "off" and "" or T.hintUnreadable))
    self.reread:SetShown(st ~= "combat" and st ~= "off")
    return
  end
  set(self.hint, "")
  self.reread:Hide()
  local stamp = st == "stale" and stampText(d.at) or nil
  if st == "stale" then
    set(self.note, T(why == "combat" and "staleCombat" or "staleUnreadable", { date = stamp or "?" }))
  else
    set(self.note, "")
  end
  self:DrawHeader(d)
  self:DrawChallenges(d)
  self:DrawRewards(d)
  self:DrawTrees(d)
end

function View:Reload(force)
  local d, st, why = M.get(force == true)
  self.data, self.status, self.why = d, st, why
  self:Render()
end

-- While the page is open: a new achievement / criterion changes the state of the challenges. Events are registered only then and
-- debounced (CRITERIA_UPDATE comes in bursts): one re-read two seconds after the last event, not in combat (the model refuses there).
View.EVENTS = { "ACHIEVEMENT_EARNED", "CRITERIA_UPDATE" }
View.EVENT_DELAY = 2

function View:WatchEvents(on)
  if on then
    if not self.events then
      local f = CreateFrame("Frame")
      f:SetScript("OnEvent", function()
        if self.pending or not self.open then return end
        self.pending = true
        local T = rawget(_G, "C_Timer")
        local ok = type(T) == "table" and type(T.After) == "function" and pcall(T.After, View.EVENT_DELAY, function()
          self.pending = false
          if self.open then self:Reload(true) end
        end)
        if not ok then self.pending = false end
      end)
      self.events = f
    end
    for _, e in ipairs(View.EVENTS) do pcall(self.events.RegisterEvent, self.events, e) end
  elseif self.events then
    pcall(self.events.UnregisterAllEvents, self.events)
  end
end

function View:Open()
  self.open = true
  self.l:Show()
  self.r:Show()
  self:WatchEvents(true)
  self:Reload(false)
end

function View:Refresh()
  if not self.open then return end
  self:Reload(false)
end

function View:Close()
  self.open = false
  self:WatchEvents(false)
  self.l:Hide()
  self.r:Hide()
  for _, row in ipairs(self.classRows) do
    for _, c in ipairs(row.cells) do W.hideTip(c) end
  end
  for _, row in ipairs(self.rewRows) do W.hideTip(row) end
  for _, row in ipairs(self.listRows) do W.hideTip(row) end
  for _, u in ipairs(self.trees) do
    for _, row in ipairs(u.rows) do W.hideTip(row) end
  end
end

-- sub-bookmark: label and tooltip are read late (the language is not yet fixed when the file loads); the bookmark exists only in
-- WoW Forever and not in a guest book (live data of the logged-in account)
Page.subs[#Page.subs + 1] = setmetatable({ key = "vermaechtnis" }, { __index = function(_, k)
  if k == "label" then return T.subLabel end
  if k == "tip" then return { T.subTip, T.subTip2 } end
end })

Pages.hideSub("chronik", "vermaechtnis", function() return not M.active() end)
