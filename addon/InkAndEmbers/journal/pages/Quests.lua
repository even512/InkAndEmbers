-- Quests page: the quest book as history of completed quests. Left the table (a click on a column head opens a popup
-- with sort buttons and filter) or the quest text, right the counter, timeline and rewards. Reads only via
-- ns.Journal.QuestBook.
-- Foreign text comes from QuestBook already sanitized (SetText/AddLine only, never a format argument); the name
-- filter's search text is own input and only compared (plain find). Read-aloud buttons via the third-party addon Spoken
-- (journal/Spoken.lua). No ticker, no OnUpdate.
local _, ns = ...

local Journal = ns.Journal
local W, Pages, Book = Journal.Widgets, Journal.Pages, Journal.QuestBook
local D = W and W.Diary
if not (W and Pages and Book and D) then return end

local floor, max, min, pi = math.floor, math.max, math.min, math.pi

local Quests = { needs = { index = true, model = false } }

-- display texts (German): fixed texts only; data comes from QuestBook. Locale scope "p.Quests" (English in
-- locales/enUS_pages.lua), read when drawing
local T = ns.Locale.ns("p.Quests", {
  subHistory = "Historie",
  subHistoryTip = "Abgeschlossene Quests mit Questtext, Lebenslauf und Belohnung",
  subOpen = "Offen",
  subOpenTip = "Quests, die Ihr jetzt annehmen könnt, mit Karte der Questgeber (Daten: QuestieDB)",
  subDungeons = "Dungeons",
  subDungeonsTip = "Alle Dungeon-Quests und ihre Questketten (Daten: QuestieDB)",
  subTrain = "Lehrplan",
  subTrainTip = "Was Euch der Klassenlehrer ab welcher Stufe beibringt (nur WoW Forever)",
  subZones = "Zonen",
  subZonesTip = "Wie weit die Quests jeder Zone erledigt sind, mit der Medaille Zonenkenner (nur WoW Forever)",
  pageOf = "Seite %d von %d", prevPage = "Vorige Seite", nextPage = "Nächste Seite", level = "Stufe %s",
  filterName = "Name „%s“", filterArea = "Gebiet %s", filterLevel = "Stufe %s",
  countOf = "%s von %s Quests", count_one = "%s Quest", count_other = "%s Quests", questLevel = "Questlevel %s",
  goalsMore_one = "+ %s weiteres Ziel", goalsMore_other = "+ %s weitere Ziele", walked = "%s gelaufen", day = "Tag %s",
  after = "nach %s", afterApprox = "nach ca. %s", vanished = "aus dem Questlog verschwunden", itemNo = "Gegenstand Nr. %s",
  chosenOf = "%s (1 von %s)", countX = "%s × · %s", moreItems = "+ %s weitere Gegenstände", choiceItemsUnknown = "Welche Gegenstände zur Wahl standen, ist nicht erfasst.",
  abandonedN = "%s abgebrochen",
  book = "QUESTBUCH", title = "INK & EMBERS", quests = "QUESTS",
  colName = "Name", colArea = "Gebiet", colLevel = "Stufe", colDate = "Abgegeben am",
  search = "Name suchen …", all = "Alle", sortLbl = "Sortieren & filtern",
  sortUpTip = "Aufsteigend sortieren", sortDownTip = "Absteigend sortieren", clearTip = "Filter aufheben",
  headTip = "Klicken: sortieren und filtern", headTipSort = "Klicken: sortieren", filterLbl = "Filter: ",
  toTable = "Zurück zur Tabelle",
  noMatch = "Keine Quest passt zu diesem Filter.",
  sortAsc = "Sortiert: aufsteigend", sortDesc = "Sortiert: absteigend",
  goals = "Questziele", turnIn = "Abgabe", life = "Lebenslauf", rewardHead = "Belohnung",
  noDetail = "Kein Beschreibungstext aufgezeichnet.", noGoals = "Keine Ziele aufgezeichnet.", noReward = "Kein Abgabetext aufgezeichnet.",
  emptyHead = "Noch keine abgeschlossenen Quests.",
  emptyBody = "Sobald Ihr eine Quest abschließt, schreibt die Chronik sie hier auf. Welche Quests es hier noch gibt, seht Ihr unter \"Offen\".",
  emptyRight = "Lebenslauf und Belohnungen erscheinen mit der ersten abgeschlossenen Quest.",
  accepted = "Angenommen", abandoned = "Abgebrochen", turned = "Abgegeben", between = "Unterwegs",
  done = "abgeschlossen",
  stateWord = { done = "abgeschlossen", open = "offen", abandoned = "abgebrochen", seen = "nur gelesen" },
  xpUnit = "EP",
  chosen = "gewählt", notChosen = "nicht gewählt", received = "erhalten", choiceNotRecorded = "Wahl nicht aufgezeichnet", fixed = "Belohnung", choice = "zur Wahl",
  noItems = "keine Gegenstandsbelohnung", noRewardData = "keine Belohnung erfasst",
  partial = "Die anderen Wahlbelohnungen sind nicht bekannt.",
  speakPlay = "Vorlesen (Spoken)", speakStop = "Anhalten", speakNone = "Keine Aufnahme in Spoken",
  partAccept = "Questtext", partProgress = "Rückfrage", partComplete = "Abgabetext",
})

local ITEM_FALLBACK_ICON = 134400 -- question mark icon (file ID) when the client gives no icon
-- item quality as ink (Theme.INK.quality); without Theme the earlier values
local QUALITY_COLOR = (Journal.Theme and Journal.Theme.INK and Journal.Theme.INK.quality) or { [0] = { 0.43, 0.43, 0.43 }, [1] = { 0.17, 0.13, 0.09 },
  [2] = { 0.11, 0.48, 0.16 }, [3] = { 0.12, 0.37, 0.66 }, [4] = { 0.48, 0.18, 0.62 }, [5] = { 0.72, 0.35, 0 },
  [6] = { 0.54, 0.48, 0.16 }, [7] = { 0.18, 0.44, 0.48 } }

-- page measures from the grid (Theme.GRID, docs/raster.md): text block left x 92, right x 44, 402 wide each; fonts from
-- GRID.size, lines from GRID.line, areas from GRID.slots.
-- Alignment only via Theme.gridX / gridFoot.
local Theme0 = Journal.Theme
local G = Theme0.GRID
local LX, LW = Theme0.gridX("L")
local RX, RW = Theme0.gridX("R")
-- table: columns relative to LX (together exactly LW wide)
local COLS = {
  { key = "name", titleKey = "colName", x = 0, w = 148 },
  { key = "area", titleKey = "colArea", x = 152, w = 92 },
  { key = "level", titleKey = "colLevel", x = 248, w = 44, right = true },
  { key = "date", titleKey = "colDate", x = 296, w = 106, right = true },
}
-- column head read late (the language is not yet fixed when the file loads)
for _, c in ipairs(COLS) do
  setmetatable(c, { __index = function(t, k) if k == "title" then return T[t.titleKey] end end })
end
local TPAD = 8 -- inner padding left (first column, column heads): nothing is cut off at the edge
local CELL_PAD_R = 4 -- inner padding right for right-aligned cells
local CTRL_CY = G.slots.ctrlTop.y + 16 -- centre of the control line of the table view (no title; text below the wax drop top left)
local HEAD_Y, HEAD_H = G.slots.bodyTop.y, 20
-- the decoration bottom left (blot, keep-out x 40..154, y 478..601) stays free: table and quest text end before y 474
local LEFT_END = 474
local ROW_H = G.line.row
local ROWS_Y = HEAD_Y + HEAD_H + 4
local ROWS_N = math.floor((LEFT_END - ROWS_Y) / ROW_H)
local FILTER_H = 22 -- search box in the popup
local DROP_ROWS, DROP_ROW_H = 12, 20
local SORT_H, SORT_BTN = 30, 20 -- popup: height of the sort row, edge length of its buttons
local POP_W = { name = 210, area = 230, level = 150, date = 132 }
local ARROW = 9 -- sort arrow in the popup buttons
local SEC_SIZE = G.size.l -- section head (handwriting, Diary.NewSectionHead): font size; height = font + 10 (= head 20 + 8 after)
local SEC_H = SEC_SIZE + 10
local TITLE_H = 34 -- counter in font step xl
local LIFE_HEAD_Y = G.slots.title.y + TITLE_H + G.section.before
local LIFE_Y = G.slots.body.y
local NODE_H, LINE_H = 44, 16
local SLOT_N, SLOT_H = 6, 30
local SLOT_W = floor((RW - 8) / 2)
local REWARD_BOX_H = 34 -- experience/gold: number or coins only, no label
local SLOT_Y = 18 + REWARD_BOX_H + 8 -- first item row below the reward head (REWARD_Y = top edge of the boxes - 18)
-- the reward sits fixed at the bottom (boxes at REWARD_Y + 18, the block ends with the note at the content end y 574);
-- a very long timeline pushes it down (self.rewardY)
local REWARD_Y = G.slots.body.bottom - 166
-- quest text left: running text in the standard client font (Friz Quadrata, like the game's quest book), generous line spacing.
-- Morpheus ("title") stays reserved for titles and section heads.
local BODY_FONT, BODY_SIZE, BODY_SPACING = "text", G.size.m, 4

local function int(n) return Journal.Texts.int(n) end

local function label(parent, kind, size, color, justify)
  local fs = W.font(parent, kind, size, color)
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

local rect = W.NewRect

local function disc(parent, layer)
  local Theme = Journal.Theme
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetTexture(Theme.TEX.markers)
  t:SetTexCoord(Theme.atlasCoords(Theme.ATLAS.disc))
  return t
end

local function place(region, parent, x, y, point)
  region:ClearAllPoints()
  region:SetPoint(point or "TOPLEFT", parent, point or "TOPLEFT", x, -y)
end

-- line between two points (relative to TOPLEFT of parent, y positive downward)
local function line(parent, color, alpha, thick)
  local l = parent:CreateLine(nil, "ARTWORK")
  l:SetThickness(thick or 1.5)
  l:SetColorTexture(W.color(color, alpha))
  return l
end

local function setLine(l, parent, x1, y1, x2, y2)
  l:SetStartPoint("TOPLEFT", parent, x1, -y1)
  l:SetEndPoint("TOPLEFT", parent, x2, -y2)
end

-- check mark of two lines in a box of size s (top left = 0,0)
local function tick(parent, s, color, thick)
  local a, b = line(parent, color, 1, thick or 2.2), line(parent, color, 1, thick or 2.2)
  setLine(a, parent, s * 0.19, s * 0.53, s * 0.42, s * 0.78)
  setLine(b, parent, s * 0.42, s * 0.78, s * 0.83, s * 0.19)
  return { a, b }
end

-- small arrow (Media/Arrow: triangle pointing down); up = mirrored upward
local function arrow(parent)
  local a = parent:CreateTexture(nil, "OVERLAY")
  a:SetSize(ARROW, ARROW)
  local Theme = Journal.Theme
  if Theme and Theme.TEX and Theme.TEX.arrow then a:SetTexture(Theme.TEX.arrow) end
  a:SetVertexColor(W.color("sepia"))
  return a
end

local function setArrowUp(a, up)
  if up then a:SetTexCoord(0, 1, 1, 0) else a:SetTexCoord(0, 1, 0, 1) end
end

-- reward money with coin icons at running-text height (centrally Texts.money, only non-zero places)
local COIN_SIZE = 13
local function moneyText(copper)
  local m = Book.money(copper)
  if not m or (m.g == 0 and m.s == 0 and m.k == 0) then return nil end
  return Journal.Texts.money(m.g * 10000 + m.s * 100 + m.k, "compact", COIN_SIZE)
end

-- paragraphs of a long text with exactly one blank line between them (QuestBook returns paragraphs separated by "\n",
-- not always blank lines);
-- whitespace at the paragraph edge and empty paragraphs drop out. No text -> nil.
local function paragraphs(text)
  if type(text) ~= "string" then return nil end
  local out = {}
  for para in string.gmatch(text .. "\n", "([^\n]*)\n") do
    local p = string.match(para, "^%s*(.-)%s*$")
    if p ~= "" then out[#out + 1] = p end
  end
  if #out == 0 then return nil end
  return table.concat(out, "\n\n")
end
Quests.paragraphs = paragraphs

-- sort button in the popup: small box with an arrow (texture Media/Arrow, up = mirrored upward); sorted that way =
-- selected (like the slip entries: red ink, box tinted red instead of filled blue).
-- Hover as for all toolkit parts (Diary): frame and arrow red.
local function sortButton(parent, up, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(SORT_BTN, SORT_BTN)
  b.up = up
  b.fill = rect(b, "red", 0.16, "BACKGROUND")
  b.fill:SetAllPoints(b)
  b.edge = W.NewOutline(b, SORT_BTN, SORT_BTN, "sepia", 0.75)
  b.edge:SetAllPoints(b)
  b.edgeHot = W.NewOutline(b, SORT_BTN, SORT_BTN, "red", 0.9)
  b.edgeHot:SetAllPoints(b)
  b.edgeHot:Hide()
  b.icon = arrow(b)
  b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
  setArrowUp(b.icon, up)
  function b:Paint()
    self.fill:SetShown(self.active and true or false)
    self.edgeHot:SetShown((self.hover or self.active) and true or false)
    self.icon:SetVertexColor(W.color((self.hover or self.active) and "red" or "ink"))
  end
  function b:SetActive(on)
    self.active = on and true or false
    self:Paint()
  end
  b:SetScript("OnClick", function() if onClick then W.call(onClick) end end)
  b:SetScript("OnEnter", function(self)
    self.hover = true
    self:Paint()
    if self.tipLines then W.tip(self, self.tipLines) end
  end)
  b:SetScript("OnLeave", function(self)
    self.hover = false
    self:Paint()
    W.hideTip(self)
  end)
  b:Paint()
  return b
end

-- "×" button in the popup: clears the filter of this column (hover red like the other popup buttons)
local function clearButton(parent, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(SORT_BTN, SORT_BTN)
  b.edge = W.NewOutline(b, SORT_BTN, SORT_BTN, "sepia", 0.75)
  b.edge:SetAllPoints(b)
  b.edgeHot = W.NewOutline(b, SORT_BTN, SORT_BTN, "red", 0.9)
  b.edgeHot:SetAllPoints(b)
  b.edgeHot:Hide()
  b.text = label(b, "label", 15, "ink", "CENTER")
  b.text:SetPoint("CENTER", b, "CENTER", 0, 1)
  b.text:SetText("×")
  b:SetScript("OnClick", function() if onClick then W.call(onClick) end end)
  b:SetScript("OnEnter", function(self)
    self.hover = true
    self.edgeHot:Show()
    self.text:SetTextColor(W.color("red"))
    if self.tipLines then W.tip(self, self.tipLines) end
  end)
  b:SetScript("OnLeave", function(self)
    self.hover = false
    self.edgeHot:Hide()
    self.text:SetTextColor(W.color("ink"))
    W.hideTip(self)
  end)
  return b
end

-- selection list in the popup: entries { text (display-ready), count|nil, value, active }. Slip rows like every
-- dropdown (Diary.NewSlipList: ink, hover = ink stroke, selection = red tick)
local function listBox(parent, w, onPick)
  return D.NewSlipList(parent, { rows = DROP_ROWS, rowHeight = DROP_ROW_H, width = w, step = 3, onPick = onPick })
end

local function openList(list, items)
  list:SetItems(items)
  local pos
  for i, it in ipairs(items) do
    if it.active then pos = i end
  end
  if pos then list:ScrollTo(pos) end
  list:Refresh()
end

-- read-aloud button: small button with Spoken's own texture (play, or stop while reading) next to the heading of a
-- quest text. Without a loaded Spoken no button at all;
-- without a recording pale (desaturated, alpha 0.33), no click effect, the tooltip says why. Journal.Spoken wraps the
-- connection (third-party interface, all via pcall); only drawing and click here.
local SPEAK_ICON, SPEAK_HOT, SPEAK_BOX, SPEAK_DIM = 16, 18, 20, 0.33
local SPEAK_INSET = SPEAK_BOX + 4 -- right indent of the text when its read-aloud button is shown

local function speakTip(b)
  local first = (not b.has) and T.speakNone or (b.playing and T.speakStop or T.speakPlay)
  return { first, b.part }
end

local function speakButton(parent, event, part)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(SPEAK_BOX, SPEAK_BOX)
  if b.SetFrameLevel and parent.GetFrameLevel then b:SetFrameLevel(parent:GetFrameLevel() + 20) end
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp") end
  b.event, b.part = event, part
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(SPEAK_ICON, SPEAK_ICON)
  b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
  function b:Paint()
    local S = Journal.Spoken
    if not (self.questID and S and S.available()) then
      self:Hide()
      return
    end
    self.has = S.has(self.questID, self.event)
    self.playing = self.has and S.isPlaying(self.questID, self.event) or false
    self.icon:SetTexture(self.playing and S.TEX_STOP or S.TEX_PLAY)
    if self.icon.SetDesaturated then self.icon:SetDesaturated(not self.has) end
    self:SetAlpha(self.has and 1 or SPEAK_DIM)
    local s = (self.hover and self.has) and SPEAK_HOT or SPEAK_ICON
    self.icon:SetSize(s, s)
    self:Show()
  end
  -- set the record (questID nil = no button)
  function b:Bind(questID, title, giver)
    self.questID, self.title, self.giver = questID, title, giver
    self:Paint()
  end
  b:SetScript("OnClick", function(self)
    W.call(function()
      if not (self.questID and self.has) then return end -- without a recording the button does nothing
      local S = Journal.Spoken
      if S then S.toggle(self.questID, self.event, self.title, function() self:Paint() end, self.giver) end
      self:Paint()
    end)
  end)
  b:SetScript("OnEnter", function(self)
    self.hover = true
    W.call(self.Paint, self)
    W.tip(self, speakTip(self))
  end)
  b:SetScript("OnLeave", function(self)
    self.hover = false
    W.call(self.Paint, self)
    W.hideTip(self)
  end)
  b:SetScript("OnHide", function(self)
    self.hover = false
    W.hideTip(self)
  end)
  b:Hide()
  return b
end

-- paging in the control line (grid): right "Seite x von y" directly left of the arrow pair (Diary.NewNavPair), which
-- pages the row list; the list itself keeps the mouse wheel,
-- its narrow bar is dropped (the page number replaces it). parent = page frame, x/w = text block of this page
-- (Theme.gridX), cy = centre of the control line. -> p (p.pair, p.label, p:Update())
local function newPager(parent, list, x, w, cy, tips)
  local p = { list = list }
  tips = tips or {}
  p.pair = D.NewNavPair(parent, { onPrev = function() p:Step(-1) end, onNext = function() p:Step(1) end,
    tipPrev = { tips[1] or T.prevPage }, tipNext = { tips[2] or T.nextPage } })
  p.pair.frame:SetPoint("RIGHT", parent, "TOPLEFT", x + w, -cy)
  p.label = label(parent, "label", G.size.s, "sepia", "RIGHT")
  p.label:SetWidth(110)
  p.label:SetPoint("RIGHT", p.pair.frame, "LEFT", -8, 0)
  -- page of the list start; the last page shows the last rows (offset at the end)
  function p:Page()
    local n = list.nRows
    local pages = max(1, math.ceil(#list.items / n))
    local off = list:GetOffset()
    local page = (off > 0 and off >= list:MaxOffset()) and pages or (floor(off / n) + 1)
    return min(page, pages), pages
  end
  function p:Step(dir)
    local page, pages = self:Page()
    local to = page + dir
    if to < 1 or to > pages then return end
    list:SetOffset((to - 1) * list.nRows)
  end
  function p:Update()
    local page, pages = self:Page()
    self.label:SetText(T("pageOf", page, pages))
    self.pair:SetEnabled(page > 1, page < pages)
  end
  -- after every drawing of the list (scrolling, new entries) update the page number; bar gone
  local base = list.Refresh
  list.Refresh = function(self) base(self) p:Update() end
  list.UpdateThumb = function(self)
    self.track:Hide()
    self.thumb:Hide()
  end
  list:UpdateThumb()
  p:Update()
  return p
end

local function filterActive(f, key)
  if key == "name" then return f.name ~= nil and f.name ~= "" end
  if key == "area" then return f.area ~= nil end
  if key == "level" then return f.level ~= nil end
  return false
end

-- tooltip of a column head: title, set filter, sort, hint
local function headTipLines(self, c, btn)
  local lines = { c.title }
  local f = self.filter
  if btn.filtered then
    if c.key == "name" then
      lines[#lines + 1] = T.filterLbl .. (string.gsub(f.name or "", "|", "||"))
    elseif c.key == "area" then
      lines[#lines + 1] = T.filterLbl .. (f.area or "")
    elseif c.key == "level" then
      lines[#lines + 1] = T.filterLbl .. T("filterLevel", f.level and int(f.level) or "")
    end
  end
  if btn.active then lines[#lines + 1] = btn.desc and T.sortDesc or T.sortAsc end
  lines[#lines + 1] = c.key == "date" and T.headTipSort or T.headTip
  return lines
end

-- sort arrow of the column head with more air to the title (Diary sets 4 px; here 8): re-anchor after every paint
local ARROW_GAP = 8
local function airyArrow(b)
  local base = b.Paint
  b.Paint = function(self)
    base(self)
    if self.active then
      self.arrow:ClearAllPoints()
      self.arrow:SetPoint(self.right and "RIGHT" or "LEFT", self.text, self.right and "LEFT" or "RIGHT", self.right and -ARROW_GAP or ARROW_GAP, 0)
    end
  end
  return b
end

-- column heads = Diary.NewColumnHead (capitals, ink stroke; arrow BEHIND the title = sort, blue funnel = filter;
-- active/desc/filtered/open are set by renderTable, drawn with b:Paint())
local function buildHeader(self, tab)
  local ui = self.ui
  ui.heads = {}
  for i, c in ipairs(COLS) do
    local b = D.NewColumnHead(tab, { key = c.key, title = c.title, width = c.w, height = HEAD_H, right = c.right, size = G.size.xs,
      onClick = function(btn) self:TogglePopup(btn.key) end,
      tip = function(btn) return headTipLines(self, c, btn) end })
    place(b, tab, LX + c.x, HEAD_Y)
    airyArrow(b)
    b:Paint()
    ui.heads[i] = b
  end
end

-- popup under the column head: sort buttons on top (ascending/descending) and, with a filter set, "×"; below it per
-- column a search box (Name), selection list (Gebiet, Stufe) or nothing (Abgegeben am).
-- An invisible catcher frame behind the popup closes it on every click beside it; Esc closes it (only the popup, not the book).
local function buildPopup(self, tab)
  local ui = self.ui
  local pop = CreateFrame("Frame", nil, tab)
  pop:SetFrameLevel(tab:GetFrameLevel() + 40)
  pop:EnableMouse(true)
  pop.slip = D.NewSlip(pop) -- slip that unfolds like every dropdown
  pop.sortLbl = label(pop, "label", 11, "sepia")
  pop.sortLbl:SetText(T.sortLbl)
  pop.sortLbl:SetPoint("TOPLEFT", pop, "TOPLEFT", 8, -10)
  pop.rule = rect(pop, "sepia", 0.45, "ARTWORK")
  pop.rule:SetHeight(1)
  pop.rule:SetPoint("TOPLEFT", pop, "TOPLEFT", 6, -SORT_H)
  pop.rule:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -6, -SORT_H)
  ui.sortDown = sortButton(pop, false, function() self:SetSortDir(self.drop, true) end)
  ui.sortDown:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -6, -5)
  ui.sortDown.tipLines = { T.sortDownTip }
  ui.sortUp = sortButton(pop, true, function() self:SetSortDir(self.drop, false) end)
  ui.sortUp:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -(6 + SORT_BTN + 4), -5)
  ui.sortUp.tipLines = { T.sortUpTip }
  ui.popClear = clearButton(pop, function() self:ClearFilter(self.drop) end)
  ui.popClear:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -(6 + 2 * (SORT_BTN + 4)), -5)
  ui.popClear.tipLines = { T.clearTip }
  ui.popClear:Hide()

  -- name: search box (own input, only for comparing)
  local eb = CreateFrame("EditBox", nil, pop)
  eb:SetSize(POP_W.name - 16, FILTER_H)
  eb:SetPoint("TOPLEFT", pop, "TOPLEFT", 8, -(SORT_H + 6))
  eb:SetAutoFocus(false)
  eb:SetMaxLetters(40)
  eb:SetTextInsets(6, 6, 0, 0)
  local Theme = Journal.Theme
  pcall(eb.SetFont, eb, (W.FONT and W.FONT.label) or (Theme and Theme.FONT.label), 12, "")
  eb:SetTextColor(W.color("ink"))
  eb.edge = W.NewOutline(eb, POP_W.name - 16, FILTER_H, "sepia", 0.75)
  eb.edge:SetAllPoints(eb)
  eb.hint = label(eb, "label", 12, "sepia")
  eb.hint:SetPoint("LEFT", eb, "LEFT", 6, 0)
  eb.hint:SetText(T.search)
  eb.hint:SetAlpha(0.7)
  eb:SetScript("OnTextChanged", function(box)
    local text = box:GetText()
    if type(text) ~= "string" then text = "" end
    box.hint:SetShown(text == "")
    if text ~= (self.filter.name or "") then
      W.call(function() self:SetNameFilter(text) end)
    end
  end)
  eb:SetScript("OnEscapePressed", function() W.call(function() self:ClosePopup() end) end)
  eb:SetScript("OnEnterPressed", function() W.call(function() self:ClosePopup() end) end)
  ui.search = eb

  ui.lists = {
    area = listBox(pop, POP_W.area - 8, function(it) self:SetAreaFilter(it.value) end),
    level = listBox(pop, POP_W.level - 8, function(it) self:SetLevelFilter(it.value) end),
  }
  for _, l in pairs(ui.lists) do l.frame:SetPoint("TOPLEFT", pop, "TOPLEFT", 4, -(SORT_H + 4)) end

  pop:EnableKeyboard(true)
  pop:SetScript("OnKeyDown", function(p, key)
    if key == "ESCAPE" then
      if p.SetPropagateKeyboardInput then p:SetPropagateKeyboardInput(false) end
      W.call(function() self:ClosePopup() end)
    elseif p.SetPropagateKeyboardInput then
      p:SetPropagateKeyboardInput(true)
    end
  end)
  ui.pop = pop

  -- catcher frame: hangs on the screen, lies just under the popup (but above everything else in the book) and follows the popup
  local catcher = CreateFrame("Button", nil, UIParent)
  catcher:SetAllPoints(UIParent)
  if catcher.SetFrameStrata then catcher:SetFrameStrata("HIGH") end
  if catcher.RegisterForClicks then catcher:RegisterForClicks("AnyUp") end
  catcher:SetScript("OnClick", function() W.call(function() self:ClosePopup() end) end)
  catcher:Hide()
  ui.catcher = catcher
  pop:SetScript("OnShow", function(p)
    catcher:SetFrameLevel(max(1, p:GetFrameLevel() - 2))
    catcher:Show()
  end)
  pop:SetScript("OnHide", function()
    catcher:Hide()
    eb:ClearFocus()
  end)
  pop:Hide()
end


local function buildRows(self, tab)
  local ui = self.ui
  -- width LW + 10: the rows are 10 px narrower than the list, so exactly as wide as the text block
  ui.rowsList = W.NewList(tab, { rows = ROWS_N, rowHeight = ROW_H, width = LW + 10, step = 4, empty = T.noMatch,
    build = function(row)
      row.label:ClearAllPoints()
      row.label:SetPoint("LEFT", row, "LEFT", COLS[1].x + TPAD, 0)
      row.label:SetWidth(COLS[1].w - TPAD - 4)
      row.cells = {}
      for i = 2, #COLS do
        local c = COLS[i]
        local fs = label(row, "label", G.size.s, "sepia", c.right and "RIGHT" or "LEFT")
        fs:SetWordWrap(false)
        fs:SetWidth(c.w - (c.right and CELL_PAD_R + 4 or TPAD + 2))
        if c.right then
          fs:SetPoint("RIGHT", row, "LEFT", c.x + c.w - CELL_PAD_R, 0)
        else
          fs:SetPoint("LEFT", row, "LEFT", c.x + TPAD, 0)
        end
        row.cells[c.key] = fs
      end
      -- ruled-paper row: hover = text red (all cells), selection = outlined red (Diary.RowStyle)
      D.RowStyle(row, { texts = { row.label, row.cells.area, row.cells.level, row.cells.date } })
      row:HookScript("OnEnter", function(r)
        if r.tipLines then W.tip(r, r.tipLines) end
      end)
      row:HookScript("OnLeave", function(r) W.hideTip(r) end)
    end,
    clear = function(row)
      row:SetSelected(false)
      for _, fs in pairs(row.cells) do fs:SetText("") end
      row.faint = false
      row.tipLines = nil
      row.label:SetTextColor(W.color("ink"))
    end,
    fill = function(row, q, i)
      W.setText(row.label, q.title)
      W.setText(row.cells.area, q.area or "–")
      row.cells.level:SetText(q.level and int(q.level) or "–")
      local date = q.turnT and Book.dateText(self.data and self.data.index, q.turnT) or nil
      W.setText(row.cells.date, date or "–")
      row.faint = q.state ~= "done"
      local a = row.faint and 0.6 or 1
      row.label:SetTextColor(W.color(row.faint and "sepia" or "ink", row.faint and 0.7 or 1))
      for _, fs in pairs(row.cells) do fs:SetAlpha(a) end
      row:SetSelected(q.id == self.sel)
      local tip = { q.title }
      if q.area then tip[#tip + 1] = q.area end
      tip[#tip + 1] = T.stateWord[q.state] or ""
      row.tipLines = tip
      D.rowFilled(row)
    end,
    onClick = function(q) self:Select(q.id, true) end })
  ui.rowsList.frame:ClearAllPoints()
  ui.rowsList.frame:SetPoint("TOPLEFT", tab, "TOPLEFT", LX, -ROWS_Y)
  -- control line (no title, y 66): left count and set filters, right paging
  ui.pager = newPager(tab, ui.rowsList, LX, LW, CTRL_CY, { T.prevPage, T.nextPage })
  ui.count = label(tab, "label", G.size.s, "sepia", "LEFT")
  ui.count:SetWidth(112)
  ui.count:SetWordWrap(false)
  ui.count:SetPoint("LEFT", tab, "TOPLEFT", LX, -CTRL_CY)
  -- filter (only with an active filter): which values filter right now; right of the count, before the paging
  ui.filterInfo = label(tab, "label", G.size.xs, "sepia")
  ui.filterInfo:SetWidth(LW - 112 - 8 - 150)
  ui.filterInfo:SetWordWrap(false)
  ui.filterInfo:SetPoint("LEFT", ui.count, "RIGHT", 8, 0)
end

local function buildView(self, left)
  local ui = self.ui
  local v = CreateFrame("Frame", nil, left)
  v:SetAllPoints(left)
  ui.view = v

  -- title block (y 72: below the wax drop top left): title (xl, long -> l, at most 2 lines), quest giver and meta
  -- (renderView sets the heights).
  -- Quest giver: name only, small and muted (WoW has no italics, so none is faked)
  ui.title = label(v, "title", G.size.xl, "ink")
  ui.title:SetWidth(LW)
  ui.title:SetWordWrap(false)
  if ui.title.SetMaxLines then ui.title:SetMaxLines(2) end
  ui.title:SetJustifyV("TOP")
  ui.giver = label(v, "label", G.size.xs, "sepia")
  ui.giver:SetWidth(LW)
  ui.giver:SetWordWrap(false)
  ui.giver:SetAlpha(0.8)
  ui.meta = label(v, "label", G.size.s, "sepia")
  ui.meta:SetWidth(LW)
  ui.meta:SetWordWrap(false)
  ui.orn = { rect(v, "sepia", 0.6), rect(v, "sepia", 0.6), rect(v, "sepia", 0.85) }
  ui.orn[1]:SetSize(LW / 2 - 12, 1)
  ui.orn[2]:SetSize(LW / 2 - 12, 1)
  ui.orn[3]:SetSize(7, 7)
  ui.orn[3]:SetRotation(pi / 4)

  -- measuring field for the line height of the running text: the text windows are always a multiple of it high (no half-cut line)
  ui.probe = label(v, "text", BODY_SIZE, "ink")
  ui.probe:SetAlpha(0)
  ui.probe:SetText("A")
  ui.probe:SetPoint("TOPLEFT", v, "TOPLEFT", 0, 0)

  -- description: plain running text across the full column width (no initial, no quotation marks)
  ui.detail = W.NewTextView(v, { width = LW, height = 110, size = BODY_SIZE, spacing = BODY_SPACING, color = "ink",
    font = BODY_FONT, empty = T.noDetail })

  -- block "Questziele": heading with rule, check box, objective text
  ui.goalsHead = D.NewSectionHead(v, T.goals, { size = SEC_SIZE, width = LW })
  ui.check = CreateFrame("Frame", nil, v)
  ui.check:SetSize(18, 18) -- check box
  ui.check:EnableMouse(true)
  local cb = W.NewOutline(ui.check, 18, 18, "ink", 0.8)
  cb:SetAllPoints(ui.check)
  ui.tick = tick(ui.check, 18, "blue")
  ui.check:SetScript("OnEnter", function(f)
    if f.tipLines then W.tip(f, f.tipLines) end
  end)
  ui.check:SetScript("OnLeave", function(f) W.hideTip(f) end)
  ui.goals = W.NewTextView(v, { width = LW - 28, height = 36, size = G.size.m, spacing = 3, color = "ink", empty = T.noGoals })

  -- block "Abgabe": the turn-in question (if archived), then the closing text; both like the running text, only
  -- separated by spacing
  ui.turnHead = D.NewSectionHead(v, T.turnIn, { size = SEC_SIZE, width = LW })
  ui.prog = W.NewTextView(v, { width = LW, height = 36, size = BODY_SIZE, spacing = BODY_SPACING, color = "ink",
    font = BODY_FONT })
  ui.rewardText = W.NewTextView(v, { width = LW, height = 80, size = BODY_SIZE, spacing = BODY_SPACING, color = "ink",
    font = BODY_FONT, empty = T.noReward })

  -- read-aloud buttons (Spoken): one each right of the first line of exactly its text block (anchored to the text,
  -- moves when scrolling);
  -- the text leaves SPEAK_INSET free on the right while the button is shown (renderSpeak)
  ui.speak = { speakButton(v, 1, T.partAccept), speakButton(v, 2, T.partProgress), speakButton(v, 3, T.partComplete) }
  ui.speakText = { ui.detail, ui.prog, ui.rewardText }
  for i, tv in ipairs(ui.speakText) do tv:SetAccessory(ui.speak[i], SPEAK_INSET) end
end

local function buildLeft(self, left)
  local ui = self.ui
  ui.headL = W.NewPageHead(left, { side = "L" })
  ui.headL:SetTexts(T.title, T.book)
  buildView(self, left)
  local tab = CreateFrame("Frame", nil, left)
  tab:SetAllPoints(left)
  tab:SetFrameLevel(left:GetFrameLevel() + 12)
  ui.table = tab
  buildHeader(self, tab)
  buildRows(self, tab)
  buildPopup(self, tab)
  tab:Hide()
  -- table -> text: a click on a row (the label "Zum Questtext" is gone, the footer stays empty); in the text "Zurück
  -- zur Tabelle" top left leads back
  -- (replaces the left head line there, Esc leads back too)
  ui.toTable = D.NewBack(ui.view, T.toTable, function() self:ToggleTable() end, { size = G.size.m })
  D.placeBack(ui.toTable, ui.view)

  ui.emptyHead = label(left, "title", G.size.l, "ink", "CENTER")
  ui.emptyHead:SetWidth(LW)
  ui.emptyHead:SetText(T.emptyHead)
  ui.emptyHead:SetPoint("TOP", left, "TOPLEFT", LX + LW / 2, -250)
  ui.emptyBody = D.emptyNote(left, LW - 60) -- empty state in handwriting
  ui.emptyBody:SetText(T.emptyBody)
  ui.emptyBody:SetPoint("TOP", left, "TOPLEFT", LX + LW / 2, -290)
end

local function buildSlot(self, parent, i)
  local s = CreateFrame("Frame", nil, parent)
  s:SetSize(SLOT_W, SLOT_H - 2)
  local col, row = (i - 1) % 2, floor((i - 1) / 2)
  place(s, parent, RX + col * (SLOT_W + 8), REWARD_Y + SLOT_Y + row * SLOT_H)
  s.edge = rect(s, "sepia", 0.8, "BACKGROUND")
  s.edge:SetSize(28, 28)
  s.edge:SetPoint("LEFT", s, "LEFT", 0, 0)
  s.icon = s:CreateTexture(nil, "ARTWORK")
  s.icon:SetSize(26, 26)
  s.icon:SetPoint("CENTER", s.edge, "CENTER", 0, 0)
  -- tick of the chosen reward: small blue disc with a light check mark bottom right of the icon
  s.badge = CreateFrame("Frame", nil, s)
  s.badge:SetSize(14, 14)
  s.badge:SetPoint("CENTER", s.edge, "BOTTOMRIGHT", -1, 2)
  s.badge:SetFrameLevel(s:GetFrameLevel() + 2)
  s.badgeDisc = disc(s.badge, "ARTWORK")
  s.badgeDisc:SetAllPoints(s.badge)
  s.badgeDisc:SetVertexColor(W.color("blue", 1))
  s.badgeTick = tick(s.badge, 14, "parchment", 1.8)
  s.name = label(s, "text", G.size.m, "ink")
  s.name:SetWidth(SLOT_W - 38)
  s.name:SetWordWrap(false)
  s.name:SetPoint("TOPLEFT", s, "TOPLEFT", 36, -1)
  s.sub = label(s, "label", G.size.xs, "sepia")
  s.sub:SetWidth(SLOT_W - 38)
  s.sub:SetWordWrap(false)
  s.sub:SetPoint("TOPLEFT", s, "TOPLEFT", 36, -16)
  s:EnableMouse(true)
  s:SetScript("OnEnter", function(f)
    if f.tipLines then W.tip(f, f.tipLines) end
  end)
  s:SetScript("OnLeave", function(f) W.hideTip(f) end)
  s:Hide()
  return s
end

local function buildRight(self, right)
  local ui = self.ui
  ui.headR = W.NewPageHead(right, { side = "R" })
  ui.headR:SetTexts("", T.quests)
  local v = CreateFrame("Frame", nil, right)
  v:SetAllPoints(right)
  ui.rview = v

  -- counter as page title (grid: title from y 66, step xl): "600 abgeschlossen · 38 abgebrochen" in one line (abandoned muted)
  ui.doneNum = label(v, "title", G.size.xl, "ink", "LEFT")
  ui.doneNum:SetPoint("TOPLEFT", v, "TOPLEFT", RX, -G.slots.title.y)
  ui.doneLbl = label(v, "label", G.size.s, "sepia", "LEFT")
  ui.doneLbl:SetPoint("BOTTOMLEFT", ui.doneNum, "BOTTOMRIGHT", 8, 5)
  ui.doneLbl:SetText(T.done)
  ui.abandonedLbl = label(v, "label", G.size.s, "sepia", "LEFT")
  ui.abandonedLbl:SetAlpha(0.7)
  ui.abandonedLbl:SetPoint("BOTTOMLEFT", ui.doneLbl, "BOTTOMRIGHT", 12, 0)

  -- timeline: nodes with time, dot, title, sub line and (Unterwegs) several lines for objectives or distance
  ui.lifeHead = D.NewSectionHead(v, T.life, { size = SEC_SIZE, width = RW })
  place(ui.lifeHead, v, RX, LIFE_HEAD_Y)
  ui.rows = {}
  for i = 1, Book.EVENT_MAX do
    local r = CreateFrame("Frame", nil, v)
    r:SetSize(RW, NODE_H)
    r.time = label(r, "title", G.size.m, "blue", "RIGHT")
    r.time:SetWidth(58)
    r.time:SetPoint("TOPRIGHT", r, "TOPLEFT", 58, -1)
    r.line = rect(r, "ink", 0.5)
    r.line:SetWidth(1.5)
    r.dot = disc(r, "ARTWORK")
    r.hole = disc(r, "OVERLAY")
    r.title = label(r, "text", G.size.m, "ink")
    r.title:SetWidth(RW - 90)
    r.title:SetWordWrap(false)
    r.title:SetPoint("TOPLEFT", r, "TOPLEFT", 90, 0)
    r.lines = {}
    for k = 1, Book.GOAL_MAX + 2 do
      local l = label(r, "label", G.size.s, "sepia")
      l:SetWidth(RW - 90)
      l:SetWordWrap(false)
      l:SetPoint("TOPLEFT", r, "TOPLEFT", 90, -(17 + (k - 1) * LINE_H))
      r.lines[k] = l
    end
    r:Hide()
    ui.rows[i] = r
  end

  -- reward: experience, gold, then up to six items
  ui.rewardLife = D.NewSectionHead(v, T.rewardHead, { size = SEC_SIZE, width = RW })
  place(ui.rewardLife, v, RX, REWARD_Y + 18 - SEC_H)
  local function box(x, w)
    local b = CreateFrame("Frame", nil, v)
    b:SetSize(w, REWARD_BOX_H)
    W.NewRule(b, 0, 0, w, 0.5)
    place(b, v, x, REWARD_Y + 18)
    b.num = label(b, "title", G.size.l, "ink")
    b.num:SetPoint("TOPLEFT", b, "TOPLEFT", 10, -6)
    return b
  end
  ui.xpBox = box(RX, 150)
  ui.xpNum = ui.xpBox.num
  ui.goldBox = box(RX + 160, 200)
  ui.goldNum = ui.goldBox.num
  ui.slots = {}
  for i = 1, SLOT_N do ui.slots[i] = buildSlot(self, v, i) end
  ui.itemNote = label(v, "label", G.size.xs, "sepia")
  ui.itemNote:SetWidth(RW)
  ui.itemNote:SetWordWrap(false)
  place(ui.itemNote, v, RX, REWARD_Y + SLOT_Y + 3 * SLOT_H + 2)

  ui.emptyRight = D.emptyNote(right, RW - 60) -- handwriting
  ui.emptyRight:SetText(T.emptyRight)
  ui.emptyRight:SetPoint("TOP", right, "TOPLEFT", RX + RW / 2, -290)
end

function Quests.Build(self, left, right)
  -- history in its own holders so the sub-view "Offen" (pages/QuestsOffen.lua) can hide it
  local mainL, mainR = CreateFrame("Frame", nil, left), CreateFrame("Frame", nil, right)
  mainL:SetAllPoints(left)
  mainR:SetAllPoints(right)
  self.mainL, self.mainR, self.holderL, self.holderR = mainL, mainR, left, right
  left, right = mainL, mainR
  self.left, self.right = left, right
  self.ui = {}
  self.sel, self.tableOpen, self.drop = nil, true, nil
  self.sort, self.desc = "date", true
  self.filter = { name = "", area = nil, level = nil }
  if Journal.Live and Journal.Live.itemNames then
    self.names = Journal.Live.itemNames(mainR, function()
      if self.openOpen or self.trainOpen or self.dungeonOpen then return end
      self:Render()
    end, Book.NAME_MAX)
  end
  buildLeft(self, left)
  buildRight(self, right)
  -- no mouse wheel on the pages (it changed the quest). The wheel only scrolls where a list or text window is
  -- scrollable itself (table, quest text, popups).
end

function Quests:List()
  local f = self.filter
  return Book.table(self.book, { sort = self.sort, desc = self.desc, name = f.name, area = f.area, level = f.level })
end

function Quests:Select(id, closeTable)
  local q = self.book and self.book.byId[id]
  if not (q and (q.state == "done" or q.state == "abandoned")) then return end
  self.sel = id
  if closeTable then self.tableOpen = false end
  self.drop = nil
  self:Render()
end

function Quests:Step(dir)
  local book = self.book
  if not book or #book.history == 0 or self.tableOpen then return end
  local list = self:List()
  local pos = Book.position(list, self.sel)
  if not pos then return end
  local to = pos + dir
  if to < 1 or to > #list then return end
  self.sel = list[to].id
  self:Render()
end

function Quests:SetSort(key)
  if key == self.sort then
    self.desc = not self.desc
  else
    self.sort, self.desc = key, key == "date" -- date: newest first, otherwise ascending
  end
  self.drop = nil
  self:Render()
end

function Quests:SetNameFilter(text)
  self.filter.name = type(text) == "string" and text or ""
  self:Render()
end

function Quests:SetAreaFilter(area)
  self.filter.area = type(area) == "string" and area or nil
  self.drop = nil
  self:Render()
end

function Quests:SetLevelFilter(level)
  self.filter.level = type(level) == "number" and level or nil
  self.drop = nil
  self:Render()
end

function Quests:ResetFilters()
  self.filter.name, self.filter.area, self.filter.level = "", nil, nil
  self.drop = nil
  local eb = self.ui and self.ui.search
  if eb then
    eb:SetText("")
    eb.hint:Show()
    eb:ClearFocus()
  end
  self:Render()
end

-- sort from the popup: column and direction are fixed (desc = descending); the popup closes
function Quests:SetSortDir(key, desc)
  if not (key == "name" or key == "area" or key == "level" or key == "date") then return end
  self.sort, self.desc = key, desc and true or false
  self.drop = nil
  self:Render()
end

function Quests:ClearFilter(key)
  if key == "name" then
    self.filter.name = ""
    local eb = self.ui and self.ui.search
    if eb then
      eb:SetText("")
      eb.hint:Show()
      eb:ClearFocus()
    end
  elseif key == "area" then
    self.filter.area = nil
  elseif key == "level" then
    self.filter.level = nil
  else
    return
  end
  self.drop = nil
  self:Render()
end

-- a click on a column head opens that column's popup, a second closes it; click beside it/Esc: ClosePopup
function Quests:TogglePopup(key)
  self.drop = self.drop ~= key and key or nil
  self:Render()
end
Quests.ToggleDrop = Quests.TogglePopup

function Quests:ClosePopup()
  if not self.drop then return end
  self.drop = nil
  self:Render()
end

function Quests:ToggleTable()
  -- came from the Dungeons page ("Questtext lesen"): "Zurück" leads back there once, then everything is as usual
  if self.returnTo and not self.tableOpen then
    local to = self.returnTo
    self.returnTo, self.tableOpen = nil, true
    self:ShowSub(to)
    Pages.subChanged("quests")
    return
  end
  self.tableOpen = not self.tableOpen
  self.drop = nil
  self:Render()
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

-- set up the popup of the chosen column (self.drop): position under the head, sort buttons (active blue), "×" with a
-- filter, search box or selection list; without an open popup everything is closed
local function renderPopup(self, book)
  local ui, f = self.ui, self.filter
  local key = self.tableOpen and self.drop or nil
  local pop = ui.pop
  if not key then
    pop:Hide()
    self.popKey = nil
    return
  end
  local w = POP_W[key]
  local c
  for _, col in ipairs(COLS) do
    if col.key == key then c = col end
  end
  local h = SORT_H + 6
  local isName, list = key == "name", ui.lists[key]
  local filtered = filterActive(f, key)
  if isName then
    h = h + FILTER_H + 8
  elseif list then
    local items
    if key == "area" then
      items = { { text = T.all, count = #book.history, value = nil, active = f.area == nil } }
      for _, z in ipairs(book.areas) do
        items[#items + 1] = { text = z.name, count = z.count, value = z.name, active = z.name == f.area }
      end
    else
      items = { { text = T.all, count = #book.history, value = nil, active = f.level == nil } }
      for _, z in ipairs(book.levels) do
        items[#items + 1] = { text = T("level", int(z.level)), count = z.count, value = z.level, active = z.level == f.level }
      end
    end
    h = SORT_H + 4 + min(DROP_ROWS, #items) * DROP_ROW_H + 8
    openList(list, items)
  end
  pop:SetSize(w, h)
  place(pop, ui.table, LX + min(c.x, LW - w), HEAD_Y + HEAD_H + 3)
  ui.search:SetShown(isName)
  for k, l in pairs(ui.lists) do l.frame:SetShown(k == key) end
  ui.popClear:SetShown(filtered)
  local on = self.sort == key
  ui.sortUp:SetActive(on and not self.desc)
  ui.sortDown:SetActive(on and self.desc)
  local opening = self.popKey ~= key
  self.popKey = key
  pop:Show()
  if isName and opening then -- freshly opened: search box with the current filter, focus at once
    ui.search:SetText(f.name or "")
    ui.search.hint:SetShown((f.name or "") == "")
    ui.search:SetFocus()
  end
end

local function renderTable(self, book, list)
  local ui = self.ui
  ui.table:SetShown(self.tableOpen)
  ui.view:SetShown(not self.tableOpen)
  local f = self.filter
  for _, h in ipairs(ui.heads) do
    h.active, h.desc = h.key == self.sort, self.desc
    h.filtered = filterActive(f, h.key)
    h.open = self.tableOpen and self.drop == h.key
    h:Paint()
  end
  local filtered = filterActive(f, "name") or filterActive(f, "area") or filterActive(f, "level")
  renderPopup(self, book)
  if not self.tableOpen then return end
  -- filter line below: only the filters that are set
  local info = {}
  if filterActive(f, "name") then info[#info + 1] = T("filterName", (string.gsub(f.name, "|", "||"))) end
  if f.area then info[#info + 1] = T("filterArea", f.area) end
  if f.level then info[#info + 1] = T("filterLevel", int(f.level)) end
  W.setText(ui.filterInfo, #info > 0 and (T.filterLbl .. table.concat(info, " · ")) or "")
  W.setText(ui.count, filtered and T("countOf", int(#list), int(#book.history))
    or T(ns.Locale.plural(#list, "count_one", "count_other"), int(#list)))
  ui.rowsList:SetItems(list)
  local pos = self.sel and Book.position(list, self.sel)
  if pos and (self.tableLast ~= self.sel or self.tableLastOpen ~= true) then
    ui.rowsList:SetOffset(max(0, pos - floor(ROWS_N / 2)))
  end
  ui.rowsList:Refresh()
end

local function setBlock(tv, text, color, keep)
  tv.text:SetTextColor(W.color(text and color or "sepia"))
  tv:SetText(text, keep)
end

-- read-aloud buttons for the shown quest text: only for texts the page really shows. Each button sits at the text block
-- it reads (quest text, turn-in question, closing text);
-- when shown, the text indents on the right. Must run BEFORE the texts are set.
local function renderSpeak(self, d)
  local ui = self.ui
  local b = ui.speak
  if not b then return end
  local has = { paragraphs(d.texts.detail) ~= nil, paragraphs(d.texts.progress) ~= nil, paragraphs(d.texts.reward) ~= nil }
  local qid = type(d.id) == "number" and d.id or nil
  for ev = 1, 3 do
    local on = has[ev] and qid ~= nil
    W.call(b[ev].Bind, b[ev], on and qid or nil, d.title, d.giver)
    ui.speakText[ev]:SetInset(b[ev]:IsShown() and SPEAK_INSET or 0)
  end
end

local TITLE_TOP = 72 -- title of the quest text: below the wax drop top left (keep-out y 13..72, x 128..196)

local function renderView(self, d)
  local ui = self.ui
  local v = ui.view
  local meta = {}
  if d.zone then meta[#meta + 1] = d.zone end
  if d.level then meta[#meta + 1] = T("questLevel", int(d.level)) end
  meta[#meta + 1] = T.stateWord[d.state]
  W.setText(ui.meta, table.concat(meta, " · "))
  W.setText(ui.title, d.title)
  W.setText(ui.giver, d.giver or "")

  -- head as before: quest giver and meta small above the title (first line y 72, below the wax drop). Title: step xl;
  -- if it does not fit one line, step l and up to two lines
  place(ui.giver, v, LX, TITLE_TOP)
  place(ui.meta, v, LX, TITLE_TOP + 14)
  local ty = TITLE_TOP + 14 + 15 + 3
  local TH = W.FONT and W.FONT.title
  ui.title:SetWordWrap(false)
  if TH then ui.title:SetFont(TH, G.size.xl, "") end
  local size, wrap = G.size.xl, false
  if (tonumber(ui.title:GetStringWidth()) or 0) > LW then
    size, wrap = G.size.l, true
    if TH then ui.title:SetFont(TH, size, "") end
    ui.title:SetWordWrap(true)
    if (tonumber(ui.title:GetStringWidth()) or 0) <= LW then wrap = false end
  end
  local th = wrap and max(math.ceil(size * 1.2), tonumber(ui.title:GetStringHeight()) or 0) or math.ceil(size * 1.2)
  th = min(th, 2 * math.ceil(size * 1.2))
  ui.title:SetHeight(th)
  place(ui.title, v, LX, ty)
  local oy = ty + th + 4
  place(ui.orn[1], v, LX, oy)
  place(ui.orn[2], v, LX + LW / 2 + 12, oy)
  ui.orn[3]:ClearAllPoints()
  ui.orn[3]:SetPoint("CENTER", v, "TOPLEFT", LX + LW / 2, -oy)

  renderSpeak(self, d)
  local hasProg = d.texts.progress ~= nil
  local keep = self.shownId == d.id and self.shownIndex == self.bookIndex
  -- vertical layout down to LEFT_END (a decoration sits bottom left): description, objectives, turn-in; the windows scroll
  local y = max(G.slots.body.y, oy + 8)
  local line = tonumber(ui.probe:GetStringHeight()) or 0
  local pitch = (line > 0 and line or 14) + BODY_SPACING -- one line of running text
  local function snap(h, p) return max(2 * p, floor(h / p) * p) end
  local hGoals, hProg = snap(36, pitch - 1), hasProg and snap(36, pitch) or 0
  local flex = LEFT_END - y - 2 * (G.section.before + SEC_H) - hGoals - hProg - (hasProg and 8 or 0)
  local hDesc = snap(floor(flex * (hasProg and 0.5 or 0.55)), pitch)
  local hReward = snap(flex - hDesc, pitch)
  -- description: running text across the full width, paragraphs with a blank line
  place(ui.detail.frame, v, LX, y)
  ui.detail:Resize(LW, hDesc)
  setBlock(ui.detail, paragraphs(d.texts.detail), "ink", keep)
  y = y + hDesc + G.section.before
  place(ui.goalsHead, v, LX, y)
  y = y + SEC_H
  place(ui.check, v, LX, y + 1)
  place(ui.goals.frame, v, LX + 28, y)
  ui.goals:Resize(LW - 28, hGoals)
  setBlock(ui.goals, d.texts.objectives, "ink", keep)
  local done = d.state == "done"
  for _, l in ipairs(ui.tick) do l:SetShown(done) end
  ui.check.tipLines = { done and "abgegeben" or "abgebrochen" }
  y = y + hGoals + G.section.before
  place(ui.turnHead, v, LX, y)
  y = y + SEC_H
  ui.prog.frame:SetShown(hasProg)
  if hasProg then
    place(ui.prog.frame, v, LX, y)
    ui.prog:Resize(LW, hProg)
    setBlock(ui.prog, paragraphs(d.texts.progress), "ink", keep)
    y = y + hProg + 8 -- plain separation: spacing instead of a rule
  end
  place(ui.rewardText.frame, v, LX, y)
  ui.rewardText:Resize(LW, hReward)
  setBlock(ui.rewardText, paragraphs(d.texts.reward), "ink", keep)
end

-- node "Unterwegs": final state per objective, otherwise the distance walked; neither -> no node
local function wayNode(d)
  local lines = {}
  for _, g in ipairs(d.goals or {}) do lines[#lines + 1] = { text = g.text, done = g.done } end
  if d.goalsMore and d.goalsMore > 0 then
    lines[#lines + 1] = { text = T(ns.Locale.plural(d.goalsMore, "goalsMore_one", "goalsMore_other"), int(d.goalsMore)) }
  end
  if #lines == 0 then
    local dist = Book.distance(d.walked)
    if dist then lines[1] = { text = T("walked", dist) } end
  end
  if #lines == 0 then return nil end
  return { kind = "between", time = "", title = T.between, lines = lines }
end

local function renderLife(self, d)
  local ui = self.ui
  local nodes = {}
  local function sub(ev)
    local bits = {}
    if ev.day then bits[#bits + 1] = T("day", int(ev.day)) end
    if ev.level then bits[#bits + 1] = T("level", int(ev.level)) end
    if ev.zone then bits[#bits + 1] = ev.zone end
    return table.concat(bits, " · ")
  end
  for i, ev in ipairs(d.events) do
    local n = { kind = ev.kind, time = ev.clock or "", title = T[ev.kind], lines = { { text = sub(ev) } } }
    if ev.kind == "turned" then
      local way = d.way
      if way and not way.open then
        local dur = Book.duration(way.active)
        if dur then
          local s = n.lines[1].text
          n.lines[1].text = T(way.activeExact and "after" or "afterApprox", dur) .. (s ~= "" and (" · " .. s) or "")
        end
      end
    elseif ev.kind == "abandoned" and not ev.confirmed then
      n.lines[2] = { text = T.vanished }
    end
    nodes[#nodes + 1] = n
    if i == 1 then -- "Unterwegs" right after the first accept
      local w = wayNode(d)
      if w then nodes[#nodes + 1] = w end
    end
  end
  local count = min(#nodes, Book.EVENT_MAX)
  local y = LIFE_Y
  for i, r in ipairs(ui.rows) do
    local n = i <= count and nodes[i] or nil
    if n then
      r:Show()
      local nl = min(#n.lines, #r.lines)
      local h = max(NODE_H, 17 + nl * LINE_H + 8)
      r:SetSize(RW, h)
      place(r, ui.rview, RX, y)
      y = y + h
      W.setText(r.time, n.time)
      W.setText(r.title, n.title)
      for k, l in ipairs(r.lines) do
        local it = k <= nl and n.lines[k] or nil
        W.setText(l, it and it.text or "")
        local between = n.kind == "between"
        l:SetTextColor(W.color(between and it and it.done and "ink" or "sepia"))
        l:SetAlpha((k > 1 and not between) and 0.85 or 1)
      end
      local big = n.kind ~= "between"
      local size = big and 12 or 8
      r.dot:ClearAllPoints()
      r.dot:SetPoint("CENTER", r, "TOPLEFT", 71, -9)
      r.dot:SetSize(size, size)
      r.hole:ClearAllPoints()
      r.hole:SetPoint("CENTER", r.dot, "CENTER", 0, 0)
      if n.kind == "turned" then
        r.dot:SetVertexColor(W.color("blue", 1))
        r.hole:Hide()
      elseif n.kind == "between" then
        r.dot:SetVertexColor(W.color("ink", 1))
        r.hole:Hide()
      else
        r.dot:SetVertexColor(W.color(n.kind == "abandoned" and "sepia" or "ink", 1))
        r.hole:SetSize(size * 0.55, size * 0.55)
        r.hole:SetVertexColor(W.color("parchment", 1))
        r.hole:Show()
      end
      r.line:ClearAllPoints()
      r.line:SetPoint("TOP", r.dot, "BOTTOM", 0, -2)
      r.line:SetHeight(h - 12)
      r.line:SetShown(i < count)
    else
      r:Hide()
    end
  end
  self.rewardY = max(REWARD_Y, y + G.section.before + SEC_H - 18)
end

-- stored name, else live from the client (asked for once, redraw when it arrives, and added to snapshots.items); placeholder only until then
local function itemLabel(self, it)
  return it.name or (self.names and self.names.name(it.itemID)) or T("itemNo", int(it.itemID))
end

local function renderReward(self, d)
  local ui = self.ui
  local ry = self.rewardY or REWARD_Y
  place(ui.rewardLife, ui.rview, RX, ry + 18 - SEC_H)
  place(ui.xpBox, ui.rview, RX, ry + 18)
  for i, s in ipairs(ui.slots) do
    place(s, ui.rview, RX + ((i - 1) % 2) * (SLOT_W + 8), ry + SLOT_Y + floor((i - 1) / 2) * SLOT_H)
  end
  local r = d.reward
  -- without a label: "1.250 EP" and the coins; what is missing stays out and the gold moves left
  local hasXp = r and r.xp and r.xp > 0
  local gold = r and r.money and moneyText(r.money) or nil
  ui.xpBox:SetShown(hasXp and true or false)
  ui.goldBox:SetShown(gold ~= nil)
  ui.xpNum:SetText(hasXp and (int(r.xp) .. " " .. T.xpUnit) or "")
  W.fitLine(ui.xpNum, 138, 12) -- box 150 wide, the gold beside it: "2 500 experience" (English) shrinks instead of running into the gold
  ui.goldNum:SetText(gold or "")
  place(ui.goldBox, ui.rview, hasXp and (RX + 160) or RX, ry + 18)
  local items = r and r.items or {}
  local shown = min(#items, SLOT_N)
  if #items > SLOT_N then shown = SLOT_N - 1 end -- the last field then carries the note
  local hasChoice = false
  for _, it in ipairs(items) do
    if it.kind == "choice" then hasChoice = true end
  end
  for i, s in ipairs(ui.slots) do
    local it = i <= shown and items[i] or nil
    if it then
      s:Show()
      local icon = Journal.Live and Journal.Live.itemIcon(it.itemID)
      s.icon:SetTexture(icon or ITEM_FALLBACK_ICON)
      -- choice not recorded: no item is greyed out as "not chosen"
      local off = it.kind == "choice" and not it.chosen and not r.choiceNotRecorded
      if s.icon.SetDesaturated then s.icon:SetDesaturated(off) end
      s.icon:SetAlpha(off and 0.45 or 1)
      s.edge:SetAlpha(off and 0.4 or 1)
      s.badge:SetShown(it.chosen and true or false)
      local name = itemLabel(self, it)
      W.setText(s.name, name)
      local qc = it.quality and QUALITY_COLOR[it.quality]
      if off then
        s.name:SetTextColor(W.color("sepia", 0.65))
      elseif qc then
        s.name:SetTextColor(qc[1], qc[2], qc[3])
      else
        s.name:SetTextColor(W.color("ink"))
      end
      local sub
      if it.kind == "fixed" then
        sub = T.fixed
      elseif it.chosen then
        local word = r.inferred and T.received or T.chosen -- derived afterwards from the received items
        sub = (r.choices and r.choices > 1) and T("chosenOf", word, int(r.choices)) or word
      elseif r.choiceNotRecorded then
        sub = T.choiceNotRecorded
      else
        sub = T.notChosen
      end
      if it.count then sub = T("countX", int(it.count), sub) end
      W.setText(s.sub, sub)
      s.sub:SetAlpha(off and 0.65 or 1)
      s.tipLines = { name, sub, item = Journal.Texts.itemString(it.itemID) } -- original item tooltip (fallback: lines)
    else
      s:Hide()
      s.tipLines = nil
    end
  end
  local note = ""
  if #items > shown then
    note = T("moreItems", int(#items - shown))
  elseif r and r.partial and hasChoice then
    note = T.partial
  elseif #items == 0 then
    if r and r.choices and r.choices > 0 then
      note = T.choiceItemsUnknown
    elseif r and d.state == "done" then
      note = T.noItems
    else
      note = T.noRewardData
    end
  end
  W.setText(ui.itemNote, note)
  -- without items the note sits directly under experience/gold
  place(ui.itemNote, ui.rview, RX, #items == 0 and (ry + SLOT_Y) or (ry + SLOT_Y + math.ceil(shown / 2) * SLOT_H + 2))
end

-- show/hide everything by empty state
local function setEmpty(self, empty)
  local ui = self.ui
  ui.rview:SetShown(not empty)
  ui.emptyHead:SetShown(empty)
  ui.emptyBody:SetShown(empty)
  ui.emptyRight:SetShown(empty)
  if empty then
    ui.headL:SetTexts(T.title, T.book)
    ui.view:Hide()
    ui.table:Hide()
    ui.pop:Hide()
    self.popKey = nil
  end
end

function Quests:Render()
  local data, ui = self.data, self.ui
  if not (data and ui and self.book) then return end
  local book = self.book
  ui.headR:SetTexts(playerLine(data), T.quests)
  ui.doneNum:SetText(int(book.counts.done))
  W.setText(ui.abandonedLbl, book.counts.abandoned > 0 and T("abandonedN", int(book.counts.abandoned)) or "")
  if #book.history == 0 then
    self.drop = nil
    setEmpty(self, true)
    return
  end
  setEmpty(self, false)
  ui.headL:SetTexts(self.tableOpen and T.title or "", T.book) -- in the text the back button is top left instead of the name
  -- selection: stays as long as it is in the history (even if the filter hides it right now); otherwise the newest
  -- completed quest (abandoned ones only if there is nothing else)
  local q = self.sel and book.byId[self.sel]
  if not (q and (q.state == "done" or q.state == "abandoned")) then
    local hist = book.history
    q = hist[#hist]
    for i = #hist, 1, -1 do
      if hist[i].state == "done" then
        q = hist[i]
        break
      end
    end
    self.sel = q and q.id or nil
  end
  if not q then
    setEmpty(self, true)
    return
  end
  local list = self:List()
  renderTable(self, book, list)
  local d = self.detail
  if not (d and d.id == q.id and self.shownIndex == self.bookIndex) then
    d = Book.detail(data.index, q, data.now)
  end
  renderView(self, d)
  renderLife(self, d)
  renderReward(self, d)
  self.tableLast, self.tableLastOpen = self.sel, self.tableOpen
  self.shownId, self.shownIndex = d.id, self.bookIndex
  self.detail = d
end

function Quests.Refresh(self, data)
  self.data = data
  if self.bookIndex ~= data.index or not self.book then
    self.book = Book.build(data.index)
    self.bookIndex = data.index
    self.detail = nil
  end
  self:Render()
  if self.openView and self.openOpen then self.openView:Refresh() end
  if self.trainView and self.trainOpen then self.trainView:Refresh() end
  if self.dungeonView and self.dungeonOpen then self.dungeonView:Refresh() end
  if self.zoneView and self.zoneOpen then self.zoneView:Refresh() end
end

-- sub-bookmarks (contract journal/Pages.lua): history · open (open quests, pages/QuestsOffen.lua) · dungeons · trainer plan ·
-- zones (pages/QuestsZonen.lua, last). Labels are read late
-- (the language is not yet fixed when the file loads)
local function subTab(key, label, tip)
  return setmetatable({ key = key }, { __index = function(_, k)
    if k == "label" then return T[label] end
    if k == "tip" then return { T[label], T[tip] } end
  end })
end
Quests.subs = {
  subTab("historie", "subHistory", "subHistoryTip"),
  subTab("offen", "subOpen", "subOpenTip"),
  subTab("dungeons", "subDungeons", "subDungeonsTip"),
  subTab("lehrplan", "subTrain", "subTrainTip"),
  subTab("zonen", "subZones", "subZonesTip"),
}

function Quests:GetSub()
  if self.zoneOpen then return "zonen" end
  if self.trainOpen then return "lehrplan" end
  if self.dungeonOpen then return "dungeons" end
  return self.openOpen and "offen" or "historie"
end

function Quests:ShowSub(key)
  if key == self:GetSub() then return end
  self.returnTo = nil
  -- zone overview (pages/QuestsZonen.lua): its own view over the table, like "Dungeons"
  if key == "zonen" then
    local V = Journal.ZonesView
    if not (V and self.mainL) then return end
    if self.openView and self.openOpen then self.openView:Close() end
    self.openOpen = false
    if self.trainView and self.trainOpen then self.trainView:Close() end
    self.trainOpen = false
    if self.dungeonView and self.dungeonOpen then self.dungeonView:Close() end
    self.dungeonOpen = false
    if not self.zoneView then self.zoneView = V.new(self, self.holderL, self.holderR) end
    self.drop = nil
    if self.ui and self.ui.pop then self.ui.pop:Hide() end
    self.mainL:Hide()
    self.mainR:Hide()
    self.zoneOpen = true
    self.zoneView:Open()
    return
  end
  if self.zoneView and self.zoneOpen then self.zoneView:Close() end
  self.zoneOpen = false
  -- dungeon quests (pages/QuestsDungeons.lua): its own view over the table, like "Offen"
  if key == "dungeons" then
    local V = Journal.DungeonQuestsView
    if not (V and self.mainL) then return end
    if self.openView and self.openOpen then self.openView:Close() end
    self.openOpen = false
    if self.trainView and self.trainOpen then self.trainView:Close() end
    self.trainOpen = false
    if not self.dungeonView then self.dungeonView = V.new(self, self.holderL, self.holderR) end
    self.drop = nil
    if self.ui and self.ui.pop then self.ui.pop:Hide() end
    self.mainL:Hide()
    self.mainR:Hide()
    self.dungeonOpen = true
    self.dungeonView:Open()
    return
  end
  if self.dungeonView and self.dungeonOpen then self.dungeonView:Close() end
  self.dungeonOpen = false
  -- trainer plan (pages/QuestsLehrplan.lua): its own view over the table, like "Offen"
  if key == "lehrplan" then
    local V = Journal.LehrplanView
    if not (V and self.mainL) then return end
    if self.openView and self.openOpen then self.openView:Close() end
    self.openOpen = false
    if not self.trainView then self.trainView = V.new(self, self.holderL, self.holderR) end
    self.drop = nil
    if self.ui and self.ui.pop then self.ui.pop:Hide() end
    self.mainL:Hide()
    self.mainR:Hide()
    self.trainOpen = true
    self.trainView:Open()
    return
  end
  if self.trainView and self.trainOpen then self.trainView:Close() end
  self.trainOpen = false
  if key == "offen" then
    local V = Journal.OpenQuestsView
    if not (V and self.mainL) then return end
    if not self.openView then self.openView = V.new(self, self.holderL, self.holderR) end
    self.drop = nil
    if self.ui and self.ui.pop then self.ui.pop:Hide() end
    self.mainL:Hide()
    self.mainR:Hide()
    self.openOpen = true
    self.openView:Open()
  else
    if self.openView then self.openView:Close() end
    self.openOpen = false
    if self.mainL then
      self.mainL:Show()
      self.mainR:Show()
    end
    self:Render()
  end
end

-- "Questtext lesen" of the Dungeons page: the quest text in the history; "Zurück" leads back to the Dungeons page once
function Quests:OpenFromDungeons(id)
  local q = self.book and self.book.byId[id]
  if not (q and (q.state == "done" or q.state == "abandoned")) then return false end
  self:ShowSub("historie")
  Pages.subChanged("quests")
  self:Select(id, true)
  self.returnTo = "dungeons"
  return true
end

-- on leaving: tooltips off, selection lists closed, search box without focus; the next open starts with the table again
-- (filter and sort stay)
function Quests.OnHide(self)
  local ui = self.ui
  if not ui then return end
  if self.trainView then
    for _, r in ipairs(self.trainView.ui.rowsList.rows) do W.hideTip(r) end
  end
  if self.openView then
    for _, r in ipairs(self.openView.ui.rowsList.rows) do W.hideTip(r) end
    self.openView.ui.pins:ReleaseAll()
    self.openView.pinData = nil
  end
  if self.dungeonView then self.dungeonView:OnPageHide() end
  if self.zoneView then self.zoneView:OnPageHide() end
  if self.names then self.names.stop() end
  self.returnTo = nil
  self.tableOpen, self.drop, self.popKey = true, nil, nil
  if ui.pop then ui.pop:Hide() end
  if ui.search then ui.search:ClearFocus() end
  W.hideTip(ui.check)
  for _, s in ipairs(ui.speak or {}) do W.hideTip(s) end
  if Journal.Spoken then Journal.Spoken.reset() end -- recordings may have loaded in the meantime: ask again on the next open
  for _, h in ipairs(ui.heads or {}) do W.hideTip(h) end
  for _, s in ipairs(ui.slots or {}) do W.hideTip(s) end
  for _, r in ipairs(ui.rowsList and ui.rowsList.rows or {}) do W.hideTip(r) end
end

-- table building blocks for other pages (equipment finds on the Schaetze page), same look without duplicate code.
-- Column heads, rows and back button come from widgets/Diary.lua;
-- here only what Diary does not offer (popup buttons/list).
Quests.kit = { pager = newPager, airyArrow = airyArrow, label = label, sortButton = sortButton, clearButton = clearButton, listBox = listBox, openList = openList,
  place = place, QUALITY_COLOR = QUALITY_COLOR, ITEM_FALLBACK_ICON = ITEM_FALLBACK_ICON, DROP_ROWS = DROP_ROWS,
  DROP_ROW_H = DROP_ROW_H, SORT_H = SORT_H, SORT_BTN = SORT_BTN, TPAD = TPAD, CELL_PAD_R = CELL_PAD_R }

Journal.QuestsPage = Quests -- handle for tests and the diagnostics (ui, book, sel, filter, sort)
Pages.register("quests", Quests)

-- Another character's book (read only): "Offen", "Dungeons", "Lehrplan" and "Zonen" depend on the logged-in character, so only the
-- history stays (Pages.subs then returns no bookmarks and does not switch by itself): an open view makes way for it before the
-- redraw (Pages.setGuest calls this listener first).
if Pages.onGuestChange then
  Pages.onGuestChange(function(guid)
    if guid ~= nil and (Quests.openOpen or Quests.dungeonOpen or Quests.trainOpen or Quests.zoneOpen) then
      Quests:ShowSub("historie")
    end
  end)
end

-- Retail: the trainer plan (Lehrplan) exists only in WoW Forever, so its bookmark stays out ("Offen" stays: own retail source)
Pages.hideSub("quests", "lehrplan", function()
  local L = Journal.Lehrplan
  return L ~= nil and type(L.active) == "function" and L.active() == false
end)

-- Retail: the dungeon quests exist only in WoW Forever (no bookmark, nothing is loaded); the test mode keeps them like the model
Pages.hideSub("quests", "dungeons", function()
  local OQ = Journal.OpenQuests
  if not (OQ and OQ.retailClient()) then return false end
  return not (OQ.test() ~= nil or OQ.ALLOW_RETAIL)
end)

-- Retail: the zone overview exists only in WoW Forever like the zone share of the chapter card (journal/model/ZoneProgress.lua)
Pages.hideSub("quests", "zonen", function()
  local OQ = Journal.OpenQuests
  if not (OQ and OQ.retailClient()) then return false end
  return not (OQ.test() ~= nil or OQ.ALLOW_RETAIL)
end)
