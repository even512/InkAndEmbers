-- Schaetze sub-view "Auktionshaus": the invoices of the auction house as a sortable table on the left (building blocks of the
-- quest table via Quests.kit; column heads sort up/down on click, ruled paper with a tinted every second row, sum row below),
-- on the right the balance (sales, purchases, saldo) independent of the filter. Data: journal/model/Auktionshaus.lua.
-- A missing item name shows "Gegenstand #id"; the client is asked for it and ITEM_DATA_LOAD_RESULT redraws (only while the view
-- is open). No ticker, no OnUpdate.
local _, ns = ...

local Journal = ns.Journal
local W, Pages, Model = Journal and Journal.Widgets, Journal and Journal.Pages, Journal and Journal.Auktionshaus
local D = W and W.Diary
if not (W and Pages and Model and D and Journal.Schaetze) then return end

local View = {}
View.__index = View
Journal.AuktionView = View

-- locale scope "p.SchaetzeAuktion" (English in locales/enUS_pages.lua), read when drawing
local T = ns.Locale.ns("p.SchaetzeAuktion", {
  brand = "INK & EMBERS", book = "AUKTIONSHAUS", page = "BILANZ",
  title = "Auktionshaus", count_one = "%s Rechnung", count_other = "%s Rechnungen", countOf = "%s von %s Rechnungen",
  prevPage = "Vorige Seite", nextPage = "Nächste Seite",
  colTime = "Datum", colKind = "Art", colItem = "Gegenstand", colCount = "Menge", colPrice = "Gesamt", colUnit = "Stück",
  fAll = "Alle", fSold = "Verkäufe", fBought = "Käufe",
  fAllTip = "Alle Rechnungen", fSoldTip = "Nur Verkäufe", fBoughtTip = "Nur Käufe",
  sortAsc = "Sortiert: aufsteigend", sortDesc = "Sortiert: absteigend", headTip = "Klicken: sortieren, nochmals klicken: umkehren",
  tipCount = "Menge: %s", tipTotal = "Preis gesamt: %s", tipUnit = "Pro Stück: %s", tipFee = "Provision: %s", tipNoPrice = "Preis nicht lesbar",
  empty = "Noch keine Rechnung des Auktionshauses.",
  emptyBody = "Sobald Ihr Euren Briefkasten leert und dort Rechnungen über Verkäufe oder Käufe liegen, schreibt die Chronik sie hier auf.",
  noMatch = "Keine Rechnung passt zu diesem Filter.",
  balTitle = "Bilanz", balSub = "Alle Rechnungen, unabhängig vom Filter",
  secSold = "Verkäufe", secBought = "Käufe", secSaldo = "Unterm Strich",
  labSoldN = "Verkaufte Posten", labIncome = "Einnahmen", labFee = "Provision", labBoughtN = "Gekaufte Posten", labSpent = "Ausgaben",
  labSaldo = "Saldo", saldoPlus = "Mehr eingenommen als ausgegeben", saldoMinus = "Mehr ausgegeben als eingenommen", saldoZero = "Ausgeglichen",
  balNote = "Grundlage sind die Rechnungen aus dem Briefkasten. Gebote, Pfand und abgelaufene Auktionen stehen in keiner Rechnung.",
  noPrice = "–",
})
View.TEXT = T

local G = Journal.Theme.GRID
local LX = Journal.Theme.gridX("L")
local RX = Journal.Theme.gridX("R")
local TABLE_W = 402
local LIST_W = TABLE_W + 10
local TITLE_Y = G.slots.title.y
local TITLE_X, TITLE_W = Journal.Theme.gridX("L", 2, 11)
local HEAD_Y, HEAD_H = G.slots.body.y, 20
local ROWS_Y, ROW_H = HEAD_Y + HEAD_H + 4, G.line.row
-- the decoration bottom left (keep-out x 54..154, y 478..582) stays free: rows and sum row end before y 474
local SUM_H = 26
local ROWS_N = math.floor((474 - ROWS_Y - SUM_H) / ROW_H)
local SUM_Y = ROWS_Y + ROWS_N * ROW_H + 2
local ICON = 14
local FONT = G.size.xs
local DW = 392                    -- text block right (the keep-out key/scale starts at x 440)

-- columns: x/w inside the table; sort key of the model; first click descending (newest, biggest first) or ascending
local COLS = {
  { key = "time", titleKey = "colTime", x = 0, w = 46, desc = true },
  { key = "kind", titleKey = "colKind", x = 46, w = 46 },
  { key = "item", titleKey = "colItem", x = 92, w = 112 },
  { key = "count", titleKey = "colCount", x = 204, w = 38, right = true, desc = true },
  { key = "price", titleKey = "colPrice", x = 242, w = 84, right = true, desc = true },
  { key = "unit", titleKey = "colUnit", x = 326, w = 76, right = true, desc = true },
}
for _, c in ipairs(COLS) do
  setmetatable(c, { __index = function(t, k) if k == "title" then return T[t.titleKey] end end })
end
View.COLS = COLS
local ITEM_ROW = 3 -- index of the item column

local function kit() return Journal.QuestsPage and Journal.QuestsPage.kit end
local function int(n) return Journal.Texts.int(n) end
local function money(c, size) return Journal.Schaetze.moneyText(c, true, false, size or FONT) end

local function headTipLines(self, c, btn)
  local lines = { c.title }
  if btn.active then lines[#lines + 1] = btn.desc and T.sortDesc or T.sortAsc end
  lines[#lines + 1] = T.headTip
  return lines
end

local function buildHeader(self, tab)
  local K = kit()
  local ui = self.ui
  ui.heads = {}
  for i, c in ipairs(COLS) do
    local b = D.NewColumnHead(tab, { key = c.key, title = c.title, width = c.w, height = HEAD_H, right = c.right, size = FONT,
      onClick = function(btn) self:SortBy(btn.key) end,
      tip = function(btn) return headTipLines(self, c, btn) end })
    K.place(b, tab, LX + c.x, HEAD_Y)
    K.airyArrow(b)
    b:Paint()
    ui.heads[i] = b
  end
end

-- tooltip of a row: original item tooltip (itemID/link) with kind, date and prices below; without a link the text lines
local function tipFor(r)
  local lines = { r.kindText .. ((r.whenFull or r.when) and (" · " .. (r.whenFull or r.when)) or ""), T("tipCount", int(r.count)) }
  if r.price then
    lines[#lines + 1] = T("tipTotal", money(r.price, 12))
    if r.unit and r.count > 1 then lines[#lines + 1] = T("tipUnit", money(r.unit, 12)) end
    if r.fee and r.fee > 0 then lines[#lines + 1] = T("tipFee", money(r.fee, 12)) end
  else
    lines[#lines + 1] = T.tipNoPrice
  end
  local tip = { Model.label(r) }
  for _, l in ipairs(lines) do tip[#tip + 1] = l end
  if r.link then
    tip.item = r.link
    tip.itemExtra = lines
  end
  return tip
end

local function buildRows(self, tab)
  local K = kit()
  local ui = self.ui
  ui.rowsList = W.NewList(tab, { rows = ROWS_N, rowHeight = ROW_H, width = LIST_W, step = 4, empty = T.noMatch,
    build = function(row)
      -- ruled paper: tint of every second row behind everything, fine vertical rules between the columns
      row.zebra = W.NewRect(row, "sepia", 0.09, "BACKGROUND")
      row.zebra:SetAllPoints(row)
      row.zebra:Hide()
      row.vrules = {}
      for i = 2, #COLS do
        local v = W.NewRect(row, "blue", 0.16, "BACKGROUND")
        v:SetWidth(1)
        v:SetPoint("TOPLEFT", row, "TOPLEFT", COLS[i].x - 2, 0)
        v:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", COLS[i].x - 2, 0)
        row.vrules[#row.vrules + 1] = v
      end
      -- the item name in the small table font (the list's own label is the larger running-text font)
      row.label:Hide()
      row.label = K.label(row, "label", FONT, "ink", "LEFT")
      row.icon = row:CreateTexture(nil, "ARTWORK")
      row.icon:SetSize(ICON, ICON)
      row.icon:SetPoint("LEFT", row, "LEFT", COLS[ITEM_ROW].x + 2, 0)
      row.cells = {}
      for i, c in ipairs(COLS) do
        local fs = i == ITEM_ROW and row.label or K.label(row, "label", FONT, "ink", c.right and "RIGHT" or "LEFT")
        fs:SetWordWrap(false)
        fs:ClearAllPoints()
        if i == ITEM_ROW then
          fs:SetJustifyH("LEFT")
          fs:SetPoint("LEFT", row, "LEFT", c.x + 2 + ICON + 3, 0)
          fs:SetWidth(c.w - 2 - ICON - 3 - 3)
        elseif c.right then
          fs:SetWidth(c.w - 4)
          fs:SetPoint("RIGHT", row, "LEFT", c.x + c.w - 3, 0)
        else
          fs:SetWidth(c.w - 4)
          fs:SetPoint("LEFT", row, "LEFT", c.x + 2, 0)
        end
        row.cells[c.key] = fs
      end
      D.RowStyle(row, { texts = { row.cells.time, row.label, row.cells.count, row.cells.price, row.cells.unit } })
      row:HookScript("OnEnter", function(r)
        if r.tipLines then W.tip(r, r.tipLines) end
      end)
      row:HookScript("OnLeave", function(r) W.hideTip(r) end)
    end,
    clear = function(row)
      row:SetSelected(false)
      row.zebra:Hide()
      row.icon:SetTexture(nil)
      for key, fs in pairs(row.cells) do
        if key ~= "item" then fs:SetText("") end
      end
      row.label:SetText("")
      row.tipLines = nil
    end,
    fill = function(row, r, i)
      row.zebra:SetShown(i % 2 == 0)
      W.setText(row.cells.time, r.when or T.noPrice)
      W.setText(row.cells.kind, r.kindText)
      row.cells.kind:SetTextColor(W.color(r.kind == "bought" and "red" or "ink"))
      W.setText(row.label, Model.label(r))
      row.icon:SetTexture((r.itemID and Journal.Live and Journal.Live.itemIcon(r.itemID)) or K.ITEM_FALLBACK_ICON)
      row.cells.count:SetText(int(r.count))
      W.setText(row.cells.price, r.price and money(r.price) or T.noPrice)
      W.setText(row.cells.unit, r.unit and money(r.unit) or T.noPrice)
      row.tipLines = tipFor(r)
      D.rowFilled(row)
    end })
  ui.rowsList.frame:ClearAllPoints()
  ui.rowsList.frame:SetPoint("TOPLEFT", tab, "TOPLEFT", LX, -ROWS_Y)
  -- control line (y 118): left the filter toggle, right paging
  local cy = G.slots.ctrl.y + G.slots.ctrl.h / 2
  ui.pager = K.pager(tab, ui.rowsList, LX, TABLE_W, cy, { T.prevPage, T.nextPage })
  ui.filter = D.NewToggle(tab, { value = "all", size = G.size.s, gap = 12,
    items = {
      { key = "all", label = T.fAll, tip = { T.fAll, T.fAllTip } },
      { key = "sold", label = T.fSold, tip = { T.fSold, T.fSoldTip } },
      { key = "bought", label = T.fBought, tip = { T.fBought, T.fBoughtTip } },
    },
    onChange = function(key) self:SetFilter(key) end })
  ui.filter.frame:SetPoint("LEFT", tab, "TOPLEFT", LX - 3, -cy)
  ui.sub = K.label(tab, "label", G.size.s, "sepia", "LEFT")
  ui.sub:SetWidth(TITLE_W)
  ui.sub:SetWordWrap(false)
  ui.sub:SetPoint("TOPLEFT", tab, "TOPLEFT", TITLE_X, -(TITLE_Y + 34))
end

-- sum row below the rows: rule on top, label in the item column, values in the columns
local function buildSum(self, tab)
  local K = kit()
  local ui = self.ui
  local sum = CreateFrame("Frame", nil, tab)
  sum:SetSize(TABLE_W, SUM_H)
  sum:SetPoint("TOPLEFT", tab, "TOPLEFT", LX, -SUM_Y)
  sum.back = W.NewRect(sum, "sepia", 0.12, "BACKGROUND")
  sum.back:SetAllPoints(sum)
  sum.rule = W.NewRect(sum, "ink", 0.75, "ARTWORK")
  sum.rule:SetHeight(2)
  sum.rule:SetPoint("TOPLEFT", sum, "TOPLEFT", 0, 0)
  sum.rule:SetPoint("TOPRIGHT", sum, "TOPRIGHT", 0, 0)
  sum.label = K.label(sum, "title", G.size.s, "ink", "LEFT")
  sum.label:SetWordWrap(false)
  sum.label:SetWidth(COLS[4].x - 6)
  sum.label:SetPoint("LEFT", sum, "LEFT", 3, -1)
  sum.cells = {}
  for _, key in ipairs({ "count", "price", "unit" }) do
    local c
    for _, col in ipairs(COLS) do if col.key == key then c = col end end
    local fs = K.label(sum, "label", FONT, "ink", "RIGHT")
    fs:SetWordWrap(false)
    fs:SetWidth(c.w - 4)
    fs:SetPoint("RIGHT", sum, "LEFT", c.x + c.w - 3, -1)
    sum.cells[key] = fs
  end
  sum:Hide()
  ui.sum = sum
end

-- right page: balance with section heads, label left and value right; independent of the filter
local function buildBalance(self, tabR)
  local K = kit()
  local ui = self.ui
  ui.balTitle = K.label(tabR, "title", G.size.xl, "ink")
  ui.balTitle:SetText(T.balTitle)
  ui.balTitle:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX, -TITLE_Y)
  ui.balSub = K.label(tabR, "label", G.size.s, "sepia")
  ui.balSub:SetText(T.balSub)
  ui.balSub:SetWidth(DW)
  ui.balSub:SetWordWrap(false)
  ui.balSub:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX, -(TITLE_Y + 34))
  local det = CreateFrame("Frame", nil, tabR)
  det:SetAllPoints(tabR)
  ui.bal = det
  ui.balRows = {}
  local y = 138
  local function section(titleKey, rows)
    local head = D.NewSectionHead(det, T[titleKey], { size = 18, width = DW })
    K.place(head, det, RX, y)
    y = y + 30
    for _, key in ipairs(rows) do
      local lab = K.label(det, "label", G.size.s, "sepia", "LEFT")
      lab:SetWidth(DW - 150)
      lab:SetWordWrap(false)
      lab:SetText(T[key])
      lab:SetPoint("TOPLEFT", det, "TOPLEFT", RX + 4, -y)
      local val = K.label(det, "label", G.size.m, "ink", "RIGHT")
      val:SetWidth(150)
      val:SetWordWrap(false)
      val:SetPoint("TOPRIGHT", det, "TOPLEFT", RX + DW - 4, -(y - 1))
      ui.balRows[key] = val
      y = y + 22
    end
    y = y + 12
  end
  section("secSold", { "labSoldN", "labIncome", "labFee" })
  section("secBought", { "labBoughtN", "labSpent" })
  section("secSaldo", { "labSaldo" })
  ui.saldoNote = K.label(det, "label", G.size.s, "sepia", "LEFT")
  ui.saldoNote:SetWidth(DW - 8)
  ui.saldoNote:SetWordWrap(false)
  ui.saldoNote:SetPoint("TOPLEFT", det, "TOPLEFT", RX + 4, -(y - 8))
  ui.note = K.label(det, "text", G.size.s, "sepia", "LEFT")
  ui.note:SetWidth(DW - 8)
  ui.note:SetText(T.balNote)
  ui.note:SetPoint("TOPLEFT", det, "TOPLEFT", RX + 4, -(y + 24))
end

function View.new(page, left, right)
  local K = kit()
  if not K then error("Auktionshaus: Tabellen-Bausteine fehlen") end
  local self = setmetatable({ page = page, ui = {} }, View)
  self.sort, self.desc, self.filterKey = "time", true, "all"
  local ui = self.ui
  local tab = CreateFrame("Frame", nil, left)
  tab:SetAllPoints(left)
  tab:SetFrameLevel(left:GetFrameLevel() + 12)
  ui.table = tab
  local tabR = CreateFrame("Frame", nil, right)
  tabR:SetAllPoints(right)
  ui.tableR = tabR
  ui.headL = W.NewPageHead(tab, { side = "L" })
  ui.headR = W.NewPageHead(tabR, { side = "R" })
  ui.headR:SetTexts("", T.page)
  ui.headL:SetTexts(T.brand, T.book)
  ui.title = K.label(tab, "title", G.size.xl, "ink")
  ui.title:SetText(T.title)
  ui.title:SetPoint("TOPLEFT", tab, "TOPLEFT", TITLE_X, -TITLE_Y)
  buildHeader(self, tab)
  buildRows(self, tab)
  buildSum(self, tab)
  buildBalance(self, tabR)
  D.escKeys(tab, function() page:CloseAuktion() end)
  ui.emptyHead = K.label(tab, "title", G.size.l, "ink", "CENTER")
  ui.emptyHead:SetWidth(TABLE_W)
  ui.emptyHead:SetText(T.empty)
  ui.emptyHead:SetPoint("TOP", tab, "TOPLEFT", LX + 201, -250)
  ui.emptyBody = K.label(tab, "text", G.size.m, "sepia", "CENTER")
  ui.emptyBody:SetWidth(380)
  ui.emptyBody:SetText(T.emptyBody)
  ui.emptyBody:SetPoint("TOP", tab, "TOPLEFT", LX + 201, -290)
  -- reload item names: only while the view is open and names are missing
  local ev = CreateFrame("Frame", nil, tab)
  ev:SetScript("OnEvent", function(_, event, itemID)
    if event ~= "ITEM_DATA_LOAD_RESULT" then return end
    W.call(function() self:OnItemData(itemID) end)
  end)
  ui.events = ev
  tab:Hide()
  tabR:Hide()
  return self
end

function View:IsOpen() return self.open == true end

function View:SetFilter(key)
  if not Model.FILTERS[key] then return end
  self.filterKey = key
  self.ui.filter:SetValue(key)
  self:Render()
end

-- click on a column head: another column sorts by its natural direction, the same column reverses
function View:SortBy(key)
  if not Model.SORTS[key] then return end
  if self.sort == key then
    self.desc = not self.desc
  else
    self.sort = key
    local c
    for _, col in ipairs(COLS) do if col.key == key then c = col end end
    self.desc = c and c.desc and true or false
  end
  self:Render()
end

function View:List()
  return Model.list(self.book, { sort = self.sort, desc = self.desc, filter = self.filterKey })
end

function View:OnItemData(itemID)
  local book = self.book
  if not (self.open and book and itemID and book.pending[itemID]) then return end
  if Model.resolve(book) > 0 then self:Render() end
  if not next(book.pending) and self.ui.events.UnregisterEvent then self.ui.events:UnregisterEvent("ITEM_DATA_LOAD_RESULT") end
end

local function renderSum(self, list)
  local ui = self.ui
  local s = Model.sum(list, self.filterKey)
  local sum = ui.sum
  W.setText(sum.label, s.label)
  if s.qty then sum.cells.count:SetText(int(s.qty)) else sum.cells.count:SetText("") end
  local neg = s.filter == "all" and s.price < 0
  W.setText(sum.cells.price, money(s.price))
  sum.cells.price:SetTextColor(W.color(neg and "red" or "ink"))
  W.setText(sum.cells.unit, s.unit and money(s.unit) or "")
  sum:SetShown(#list > 0)
end

local function renderBalance(self)
  local ui, book = self.ui, self.book
  local sold, bought = book.sold, book.bought
  local function set(key, text) W.setText(ui.balRows[key], text) end
  set("labSoldN", int(sold.n))
  set("labIncome", money(sold.price, 14))
  set("labFee", sold.fee > 0 and money(sold.fee, 14) or T.noPrice)
  set("labBoughtN", int(bought.n))
  set("labSpent", money(bought.price, 14))
  local saldo = sold.price - bought.price
  set("labSaldo", money(saldo, 14))
  ui.balRows.labSaldo:SetTextColor(W.color(saldo < 0 and "red" or "ink"))
  W.setText(ui.saldoNote, saldo > 0 and T.saldoPlus or (saldo < 0 and T.saldoMinus or T.saldoZero))
end

function View:Render()
  local ui, book = self.ui, self.book
  if not (self.open and book) then return end
  local view = self.page and self.page.view
  local who = W.playerLine(self.page and self.page.data) or (view and view.head)
  if who then ui.headR:SetTexts(who, T.page) end
  local empty = book.total == 0
  ui.emptyHead:SetShown(empty)
  ui.emptyBody:SetShown(empty)
  ui.filter.frame:SetShown(not empty)
  ui.bal:SetShown(not empty)
  ui.balTitle:SetShown(not empty)
  ui.balSub:SetShown(not empty)
  for _, h in ipairs(ui.heads) do h:SetShown(not empty) end
  ui.rowsList.frame:SetShown(not empty)
  if empty then
    ui.sum:Hide()
    ui.sub:SetText("")
    ui.pager.pair.frame:Hide()
    ui.pager.label:SetText("")
    return
  end
  ui.pager.pair.frame:Show()
  for _, h in ipairs(ui.heads) do
    h.active, h.desc = h.key == self.sort, self.desc
    h:Paint()
  end
  local list = self:List()
  ui.filter:SetValue(self.filterKey)
  W.setText(ui.sub, #list == book.total and T(ns.Locale.plural(#list, "count_one", "count_other"), int(#list))
    or T("countOf", int(#list), int(book.total)))
  ui.rowsList:SetItems(list)
  ui.rowsList:Refresh()
  renderSum(self, list)
  renderBalance(self)
end

function View:Open(index)
  self.book = Model.build(index)
  self.open = true
  self.ui.table:Show()
  self.ui.tableR:Show()
  if next(self.book.pending) then
    Model.resolve(self.book, true)
    if next(self.book.pending) and self.ui.events.RegisterEvent then
      pcall(self.ui.events.RegisterEvent, self.ui.events, "ITEM_DATA_LOAD_RESULT")
    end
  end
  self:Render()
end

-- new index (new invoices) with the view open: table again
function View:Refresh(index)
  if not self.open then return end
  local book = Model.build(index)
  if book ~= self.book then
    self.book = book
    if next(book.pending) then Model.resolve(book, true) end
  end
  self:Render()
end

function View:Close()
  local ui = self.ui
  self.open = false
  ui.table:Hide()
  ui.tableR:Hide()
  if ui.events.UnregisterEvent then ui.events:UnregisterEvent("ITEM_DATA_LOAD_RESULT") end
  for _, h in ipairs(ui.heads) do W.hideTip(h) end
  for _, r in ipairs(ui.rowsList.rows) do W.hideTip(r) end
end
