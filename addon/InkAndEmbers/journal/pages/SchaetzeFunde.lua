-- Schaetze sub-view "Ausrüstungsfunde": finds table on the left (building blocks of the quest table via Quests.kit),
-- detail of the chosen find on the right (icon with original tooltip, values, source, replaced item, slot timeline).
-- Data: journal/model/Funde.lua.
-- A missing item name shows "Gegenstand #id"; the client is asked for it and ITEM_DATA_LOAD_RESULT redraws (only while
-- the view is open). No ticker, no OnUpdate.
local _, ns = ...

local Journal = ns.Journal
local W, Pages, Funde = Journal and Journal.Widgets, Journal and Journal.Pages, Journal and Journal.Funde
local D = W and W.Diary
if not (W and Pages and Funde and D) then return end

local max, min = math.max, math.min

local View = {}
View.__index = View
Journal.FundeView = View

-- locale scope "p.SchaetzeFunde" (English in locales/enUS_pages.lua), read when drawing
local T = ns.Locale.ns("p.SchaetzeFunde", {
  prevPage = "Vorige Seite", nextPage = "Nächste Seite", clock = "%s Uhr", itemNo = "Gegenstand #%s",
  countOf = "%s von %s Funden", count_one = "%s Fund", count_other = "%s Funde",
  brand = "INK & EMBERS", book = "AUSRÜSTUNG", page = "AB UNGEWÖHNLICH",
  title = "Ausrüstungsfunde", sub = "Alles ab Ungewöhnlich, das sich anlegen lässt",
  colItem = "Gegenstand", colSlot = "Platz", colLevel = "Stufe", colTime = "Erhalten",
  back = "Zurück zur Übersicht", all = "Alle", sortLbl = "Sortieren & filtern", sortOnlyLbl = "Sortieren",
  sortUpTip = "Aufsteigend sortieren", sortDownTip = "Absteigend sortieren", clearTip = "Filter aufheben",
  headTip = "Klicken: sortieren und filtern", headTipSort = "Klicken: sortieren", headTipZone = "Klicken: sortieren, nach Gebiet filtern",
  filterWord = { quality = "Güte", slot = "Platz", zone = "Gebiet" },
  pick = "Wählt links einen Fund.", secFound = "Gefunden", secStats = "Werte", secLine = "Zeitleiste",
  labWhen = "Wann", labWhere = "Wo", labSource = "Quelle", labReplaced = "Ersetzt",
  whenNone = "Zeitpunkt unbekannt", whereNone = "Ort unbekannt", levelWord = "Charakterstufe ",
  replacedNone = "kein Gegenstand bekannt", replacedEmpty = "nichts (der Platz war frei)", notWorn = "nicht angelegt",
  statsHint = "Die Werte zeigt der Tooltip: Symbol überfahren.", itemLevelWord = "Itemstufe ",
  lineNone = "Für diesen Platz gibt es keine Stufenangaben.", lineLevel = "Stufe ",
  lineHead = "Zeitleiste: ", lineCount = { " Fund", " Funde" },
  sortAsc = "Sortiert: aufsteigend", sortDesc = "Sortiert: absteigend", filterLbl = "Filter: ",
  empty = "Noch keine Ausrüstung ab Ungewöhnlich gefunden.",
  emptyBody = "Sobald Ihr grüne oder bessere Ausrüstung erhaltet, schreibt die Chronik sie hier auf.",
  noMatch = "Kein Fund passt zu diesem Filter.",
})
View.TEXT = T

-- measures from the grid (Theme.GRID; double page 1076 x 666, fold at 538): table left in the text block (x 92, 402 wide),
-- detail right in the text block (x 44, 402 wide, only 392 on the right: the keep-out key/scale starts at x 440).
local G = Journal.Theme.GRID
local LX = Journal.Theme.gridX("L")
local RX, RW = Journal.Theme.gridX("R")
local TABLE_W = 402
local COLS = {
  { key = "item", titleKey = "colItem", x = 0, w = 188, filter = "quality" },
  { key = "slot", titleKey = "colSlot", x = 192, w = 72, filter = "slot" },
  { key = "level", titleKey = "colLevel", x = 268, w = 40, right = true },
  { key = "time", titleKey = "colTime", x = 312, w = 90, right = true, filter = "zone" },
}
-- column head read late (the language is not yet fixed when the file loads)
for _, c in ipairs(COLS) do
  setmetatable(c, { __index = function(t, k) if k == "title" then return T[t.titleKey] end end })
end
View.COLS = COLS
local LIST_W = TABLE_W + 10      -- list (the rows are 10 px narrower: exactly TABLE_W)
local TITLE_Y = G.slots.title.y   -- title as on all pages from y 66; the wax drops top left (keep-out to x 111) are avoided by indenting
local TITLE_X, TITLE_W = Journal.Theme.gridX("L", 2, 11)
local HEAD_Y, HEAD_H = G.slots.body.y, 20
local ROWS_Y, ROW_H = HEAD_Y + HEAD_H + 4, G.line.row
-- the decoration bottom left (keep-out x 54..154, y 478..582) stays free: the table ends before y 474
local ROWS_N = math.floor((474 - ROWS_Y) / ROW_H)
local ICON = 16
local POP_W = { item = 200, slot = 200, zone = 230, level = 132, time = 230 }
local SPREAD_R = LX + TABLE_W    -- right edge of the columns (abs.)

local DX, DW = RX, 392           -- text block right, without the keep-out from x 440
local BIG = 56                   -- large icon
local D_TOP = G.slots.bodyTop.y + 2
local D_WHEN_Y = D_TOP + BIG + 16 -- section "Gefunden"
local LAB_W = 70
local D_STATS_Y = D_WHEN_Y + 28 + 4 * 18 + 6
local STATS_N = 6
local D_LINE_Y = 440              -- section "Zeitleiste"
local AXIS_Y = 546
local DOT, DOT_SEL, LANE_H, LANES = 12, 16, 14, 4

local function kit() return Journal.QuestsPage and Journal.QuestsPage.kit end

local function int(n) return Journal.Texts.int(n) end

local function filterOf(key)
  for _, c in ipairs(COLS) do
    if c.key == key then return c.filter, c end
  end
  return nil
end

-- tooltip of a column head: title, set filter, sort, hint
local function headTipLines(self, c, btn)
  local lines = { c.title }
  local f = self.filter
  if btn.filtered then
    if c.filter == "quality" then
      local q = Funde.QUALITY[f.quality]
      lines[#lines + 1] = T.filterLbl .. (q and q.label or "")
    else
      lines[#lines + 1] = T.filterLbl .. (f[c.filter] or "")
    end
  end
  if btn.active then lines[#lines + 1] = btn.desc and T.sortDesc or T.sortAsc end
  lines[#lines + 1] = c.filter == "zone" and T.headTipZone or (c.filter and T.headTip or T.headTipSort)
  return lines
end

-- column heads = Diary.NewColumnHead (same implementation as the quest table; an ink stroke per column, interrupted at the fold)
local function buildHeader(self, tab)
  local K = kit()
  local ui = self.ui
  ui.heads = {}
  for i, c in ipairs(COLS) do
    local b = D.NewColumnHead(tab, { key = c.key, title = c.title, width = c.w, height = HEAD_H, right = c.right, size = G.size.xs,
      onClick = function(btn) self:TogglePopup(btn.key) end,
      tip = function(btn) return headTipLines(self, c, btn) end })
    K.place(b, tab, LX + c.x, HEAD_Y)
    K.airyArrow(b)
    b:Paint()
    ui.heads[i] = b
  end
end

local function buildPopup(self, tab)
  local K = kit()
  local ui = self.ui
  local pop = CreateFrame("Frame", nil, tab)
  pop:SetFrameLevel(tab:GetFrameLevel() + 40)
  pop:EnableMouse(true)
  pop.slip = D.NewSlip(pop) -- slip that unfolds like every dropdown
  pop.sortLbl = K.label(pop, "label", 11, "sepia")
  pop.sortLbl:SetText(T.sortLbl)
  pop.sortLbl:SetPoint("TOPLEFT", pop, "TOPLEFT", 8, -10)
  pop.rule = W.NewRect(pop, "sepia", 0.45, "ARTWORK")
  pop.rule:SetHeight(1)
  pop.rule:SetPoint("TOPLEFT", pop, "TOPLEFT", 6, -K.SORT_H)
  pop.rule:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -6, -K.SORT_H)
  ui.sortDown = K.sortButton(pop, false, function() self:SetSortDir(self.drop, true) end)
  ui.sortDown:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -6, -5)
  ui.sortDown.tipLines = { T.sortDownTip }
  ui.sortUp = K.sortButton(pop, true, function() self:SetSortDir(self.drop, false) end)
  ui.sortUp:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -(6 + K.SORT_BTN + 4), -5)
  ui.sortUp.tipLines = { T.sortUpTip }
  ui.popClear = K.clearButton(pop, function() self:ClearFilter(self.drop) end)
  ui.popClear:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -(6 + 2 * (K.SORT_BTN + 4)), -5)
  ui.popClear.tipLines = { T.clearTip }
  ui.popClear:Hide()
  ui.lists = {
    quality = K.listBox(pop, POP_W.item - 8, function(it) self:SetFilter("quality", it.value) end),
    slot = K.listBox(pop, POP_W.slot - 8, function(it) self:SetFilter("slot", it.value) end),
    zone = K.listBox(pop, POP_W.zone - 8, function(it) self:SetFilter("zone", it.value) end),
  }
  for _, l in pairs(ui.lists) do l.frame:SetPoint("TOPLEFT", pop, "TOPLEFT", 4, -(K.SORT_H + 4)) end
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
  -- catcher frame: a click beside it closes the popup
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
  pop:SetScript("OnHide", function() catcher:Hide() end)
  pop:Hide()
end

-- quality name as in game (Fmt.qualityName); colored: in the quality colour (onDark: tooltip, otherwise parchment tone)
local function qualityLabel(q, colored, onDark)
  local F = Journal.Fmt
  local name = (F and F.qualityName(q)) or (Funde.QUALITY[q] or {}).label or ""
  if colored and F and name ~= "" then return F.colorize(name, q, onDark) end
  return name
end

-- tooltip of a find: original item tooltip with the origin below; without a readable link the text lines
local function tipFor(r)
  local where = {}
  if r.zone then where[#where + 1] = r.zone end
  if r.level then where[#where + 1] = T.lineLevel .. int(r.level) end
  local extra = { r.origin }
  if #where > 0 then extra[#extra + 1] = table.concat(where, " · ") end
  if r.when then extra[#extra + 1] = r.when end
  local tip = { Funde.label(r), r.slot .. " · " .. qualityLabel(r.quality, true, true), item = r.link, itemExtra = extra }
  for _, l in ipairs(extra) do tip[#tip + 1] = l end
  return tip
end

local function buildRows(self, tab)
  local K = kit()
  local ui = self.ui
  ui.rowsList = W.NewList(tab, { rows = ROWS_N, rowHeight = ROW_H, width = LIST_W, step = 4, empty = T.noMatch,
    build = function(row)
      row.icon = row:CreateTexture(nil, "ARTWORK")
      row.icon:SetSize(ICON, ICON)
      row.icon:SetPoint("LEFT", row, "LEFT", K.TPAD, 0)
      row.label:ClearAllPoints()
      row.label:SetPoint("LEFT", row, "LEFT", K.TPAD + ICON + 6, 0)
      row.label:SetWidth(COLS[1].w - K.TPAD - ICON - 10)
      row.cells = {}
      for i = 2, #COLS do
        local c = COLS[i]
        local fs = K.label(row, "label", G.size.s, "sepia", c.right and "RIGHT" or "LEFT")
        fs:SetWordWrap(false)
        fs:SetWidth(c.w - (c.right and K.CELL_PAD_R + 4 or K.TPAD + 2))
        if c.right then
          fs:SetPoint("RIGHT", row, "LEFT", c.x + c.w - K.CELL_PAD_R, 0)
        else
          fs:SetPoint("LEFT", row, "LEFT", c.x + K.TPAD, 0)
        end
        row.cells[c.key] = fs
      end
      -- ruled-paper row: hover = text red, selection = outlined red (Diary.RowStyle)
      D.RowStyle(row, { texts = { row.label, row.cells.slot, row.cells.level, row.cells.time } })
      row:HookScript("OnEnter", function(r)
        if r.tipLines then W.tip(r, r.tipLines) end
      end)
      row:HookScript("OnLeave", function(r) W.hideTip(r) end)
    end,
    clear = function(row)
      row:SetSelected(false)
      row.icon:SetTexture(nil)
      for _, fs in pairs(row.cells) do fs:SetText("") end
      row.tipLines = nil
      row.label:SetTextColor(W.color("ink"))
    end,
    fill = function(row, r, i)
      local name = Funde.label(r)
      W.setText(row.label, r.count and (name .. " ×" .. int(r.count)) or name)
      local qc = K.QUALITY_COLOR[r.quality]
      if qc then row.label:SetTextColor(qc[1], qc[2], qc[3]) else row.label:SetTextColor(W.color("ink")) end
      row.icon:SetTexture((Journal.Live and Journal.Live.itemIcon(r.itemID)) or K.ITEM_FALLBACK_ICON)
      W.setText(row.cells.slot, r.slot)
      row.cells.level:SetText(r.level and int(r.level) or "–")
      W.setText(row.cells.time, r.when or "–")
      row:SetSelected(r.id == self.sel)
      -- short text tooltip (full names, origin); the original tooltip comes with the icon in the detail
      local tip = { name, r.slot .. " · " .. qualityLabel(r.quality, true, true), r.origin }
      if r.zone then tip[#tip + 1] = r.zone end
      row.tipLines = tip
      D.rowFilled(row)
    end,
    onClick = function(r) self:Select(r, false) end })
  ui.rowsList.frame:ClearAllPoints()
  ui.rowsList.frame:SetPoint("TOPLEFT", tab, "TOPLEFT", LX, -ROWS_Y)
  -- control line (y 118): left count, right paging ("Seite x von y", arrow pair); set filters under the title
  local cy = G.slots.ctrl.y + G.slots.ctrl.h / 2
  ui.pager = K.pager(tab, ui.rowsList, LX, TABLE_W, cy, { T.prevPage, T.nextPage })
  ui.count = K.label(tab, "label", G.size.s, "sepia", "LEFT")
  ui.count:SetWidth(150)
  ui.count:SetWordWrap(false)
  ui.count:SetPoint("LEFT", tab, "TOPLEFT", LX, -cy)
  ui.filterInfo = K.label(tab, "label", G.size.xs, "sepia", "LEFT")
  ui.filterInfo:SetWidth(TITLE_W)
  ui.filterInfo:SetWordWrap(false)
  ui.filterInfo:SetPoint("TOPLEFT", tab, "TOPLEFT", TITLE_X, -(TITLE_Y + 34))
end

local function place(region, parent, x, y, point)
  region:ClearAllPoints()
  region:SetPoint(point or "TOPLEFT", parent, "TOPLEFT", x, -y)
end

-- frame of four lines (thickness thick), colour changeable later via rim:SetRimColor(r, g, b, a)
local function newRim(parent, w, h, thick, r, g, b, a)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  f.edges = {}
  for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" },
    { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local e = f:CreateTexture(nil, "OVERLAY")
    e:SetPoint(p[1], f, p[1], 0, 0)
    e:SetPoint(p[2], f, p[2], 0, 0)
    if i <= 2 then e:SetHeight(thick) else e:SetWidth(thick) end
    f.edges[i] = e
  end
  function f:SetRimColor(cr, cg, cb, ca)
    for _, e in ipairs(self.edges) do e:SetColorTexture(cr, cg, cb, ca or 1) end
  end
  f:SetRimColor(r, g, b, a)
  return f
end

local function buildDetail(self, tabR)
  local K = kit()
  local ui = self.ui
  local det = CreateFrame("Frame", nil, tabR)
  det:SetAllPoints(tabR)
  ui.detail = det
  ui.pick = K.label(tabR, "title", G.size.l, "sepia", "CENTER")
  ui.pick:SetWidth(DW)
  ui.pick:SetText(T.pick)
  ui.pick:SetPoint("TOP", tabR, "TOPLEFT", DX + DW / 2, -250)
  -- large icon (hover = original item tooltip), frame in the quality tone
  local icon = CreateFrame("Button", nil, det)
  icon:SetSize(BIG, BIG)
  place(icon, det, DX, D_TOP)
  icon.tex = icon:CreateTexture(nil, "ARTWORK")
  icon.tex:SetAllPoints(icon)
  icon.rim = newRim(icon, BIG + 4, BIG + 4, 2, W.color("ink", 0.9))
  icon.rim:SetPoint("CENTER", icon, "CENTER", 0, 0)
  icon:SetScript("OnEnter", function(b)
    if b.tipLines then W.tip(b, b.tipLines) end
  end)
  icon:SetScript("OnLeave", function(b) W.hideTip(b) end)
  ui.icon = icon
  ui.name = K.label(det, "title", G.size.l, "ink", "LEFT")
  ui.name:SetWidth(DW - BIG - 20)
  if ui.name.SetMaxLines then ui.name:SetMaxLines(2) end
  place(ui.name, det, DX + BIG + 14, D_TOP)
  ui.meta = K.label(det, "label", G.size.s, "sepia", "LEFT")
  ui.meta:SetWidth(DW - BIG - 20)
  ui.meta:SetWordWrap(false)
  ui.meta:SetPoint("BOTTOMLEFT", det, "TOPLEFT", DX + BIG + 14, -(D_TOP + BIG))
  -- section "Gefunden": Wann / Wo / Quelle / Ersetzt
  ui.secFound = D.NewSectionHead(det, T.secFound, { size = 18, width = DW })
  place(ui.secFound, det, DX, D_WHEN_Y)
  ui.facts = {}
  for i, key in ipairs({ "labWhen", "labWhere", "labSource", "labReplaced" }) do
    local y = D_WHEN_Y + 28 + (i - 1) * 18
    local lab = K.label(det, "label", G.size.s, "sepia", "LEFT")
    lab:SetWidth(LAB_W)
    lab:SetText(T[key])
    place(lab, det, DX + 4, y)
    local val = K.label(det, "label", G.size.s, "ink", "LEFT")
    val:SetWidth(DW - LAB_W - 8)
    val:SetWordWrap(false)
    place(val, det, DX + 4 + LAB_W, y)
    ui.facts[i] = val
  end
  -- section "Werte" (tooltip lines)
  ui.secStats = D.NewSectionHead(det, T.secStats, { size = 18, width = DW })
  place(ui.secStats, det, DX, D_STATS_Y)
  ui.stats = {}
  for i = 1, STATS_N do
    local fs = K.label(det, "label", G.size.s, "ink", "LEFT")
    fs:SetWidth(DW - 8)
    fs:SetWordWrap(false)
    place(fs, det, DX + 4, D_STATS_Y + 32 + (i - 1) * 16)
    ui.stats[i] = fs
  end
  ui.statsHint = K.label(det, "label", G.size.s, "sepia", "LEFT")
  ui.statsHint:SetWidth(DW - 8)
  ui.statsHint:SetWordWrap(false)
  place(ui.statsHint, det, DX + 4, D_STATS_Y + 32)
  -- section "Zeitleiste": axis, levels at the ends, dots
  ui.secLine = D.NewSectionHead(det, T.lineHead, { size = 18, width = DW })
  place(ui.secLine, det, DX, D_LINE_Y)
  ui.axis = W.NewRule(det, DX + 4, AXIS_Y, DW - 8, 0.7)
  ui.loLabel = K.label(det, "label", G.size.xs, "sepia", "LEFT")
  ui.loLabel:SetWidth(120)
  place(ui.loLabel, det, DX + 4, AXIS_Y + 4)
  ui.hiLabel = K.label(det, "label", G.size.xs, "sepia", "RIGHT")
  ui.hiLabel:SetWidth(120)
  place(ui.hiLabel, det, DX + DW - 4 - 120, AXIS_Y + 4)
  ui.lineNone = K.label(det, "label", G.size.s, "sepia", "LEFT")
  ui.lineNone:SetWidth(DW - 8)
  ui.lineNone:SetWordWrap(false)
  place(ui.lineNone, det, DX + 4, AXIS_Y - 24)
  ui.dots = {}
  det:Hide()
  ui.pick:Hide()
end

local function dotAt(self, i)
  local ui = self.ui
  local d = ui.dots[i]
  if d then return d end
  d = CreateFrame("Button", nil, ui.detail)
  d:SetFrameLevel(ui.detail:GetFrameLevel() + 3)
  d.tex = d:CreateTexture(nil, "ARTWORK")
  d.tex:SetAllPoints(d)
  d.rim = newRim(d, DOT, DOT, 1, W.color("ink", 0.8))
  d.rim:SetAllPoints(d)
  d.sel = newRim(d, DOT_SEL + 4, DOT_SEL + 4, 2, W.color("red", 1))
  d.sel:SetPoint("CENTER", d, "CENTER", 0, 0)
  d:SetScript("OnClick", function(b) if b.fund then W.call(function() self:Select(b.fund, true) end) end end)
  d:SetScript("OnEnter", function(b) if b.tipLines then W.tip(b, b.tipLines) end end)
  d:SetScript("OnLeave", function(b) W.hideTip(b) end)
  ui.dots[i] = d
  return d
end

-- timeline of the equipment slot of row: dots by level (x) and, at the same place, stacked (tracks)
local function renderLine(self, row)
  local K = kit()
  local ui = self.ui
  local tl = Funde.timeline(self.book, row)
  local n = #tl.rows
  ui.secLine:SetText(T.lineHead .. row.slot .. " (" .. int(n) .. (n == 1 and T.lineCount[1] or T.lineCount[2]) .. ")")
  local none = n == 0
  W.setText(ui.lineNone, none and T.lineNone or "")
  ui.axis:SetShown(not none)
  W.setText(ui.loLabel, none and "" or (T.lineLevel .. int(tl.lo)))
  W.setText(ui.hiLabel, (none or tl.hi == tl.lo) and "" or (T.lineLevel .. int(tl.hi)))
  local x0, x1 = DX + 12, DX + DW - 12
  local lanes = {}
  for i = 1, max(n, #ui.dots) do
    local r = tl.rows[i]
    if not r then
      if ui.dots[i] then
        W.hideTip(ui.dots[i])
        ui.dots[i]:Hide()
      end
    else
      local d = dotAt(self, i)
      local x = tl.hi == tl.lo and (x0 + x1) / 2 or (x0 + (x1 - x0) * (r.level - tl.lo) / (tl.hi - tl.lo))
      local lane = 0
      while lane < LANES - 1 and lanes[lane + 1] and x - lanes[lane + 1] < DOT + 3 do lane = lane + 1 end
      lanes[lane + 1] = x
      local isSel = r.id == row.id
      local size = isSel and DOT_SEL or DOT
      d:SetSize(size, size)
      d:ClearAllPoints()
      d:SetPoint("CENTER", ui.detail, "TOPLEFT", x, -(AXIS_Y - 3 - DOT_SEL / 2 - lane * LANE_H))
      local qc = K.QUALITY_COLOR[r.quality]
      if qc then d.tex:SetColorTexture(qc[1], qc[2], qc[3], 1) else d.tex:SetColorTexture(W.color("sepia")) end
      d.sel:SetShown(isSel)
      d:SetFrameLevel(ui.detail:GetFrameLevel() + (isSel and 5 or 3))
      d.fund = r
      d.tipLines = { Funde.label(r), r.when or "", (r.level and (T.lineLevel .. int(r.level)) or "") }
      d:Show()
    end
  end
end

local function renderDetail(self)
  local K = kit()
  local ui, book, row = self.ui, self.book, self.selRow
  local show = row ~= nil and book ~= nil and book.total > 0
  ui.detail:SetShown(show)
  ui.pick:SetShown(not show and book ~= nil and book.total > 0)
  if not show then
    W.hideTip(ui.icon)
    return
  end
  local qc = K.QUALITY_COLOR[row.quality]
  local r, g, b = W.color("ink")
  if qc then r, g, b = qc[1], qc[2], qc[3] end
  ui.icon.tex:SetTexture((Journal.Live and Journal.Live.itemIcon(row.itemID)) or K.ITEM_FALLBACK_ICON)
  ui.icon.tipLines = tipFor(row)
  ui.icon.rim:SetRimColor(r, g, b, 0.95)
  local name = Funde.label(row)
  W.setText(ui.name, row.count and (name .. " ×" .. int(row.count)) or name)
  ui.name:SetTextColor(r, g, b)
  local meta = { qualityLabel(row.quality, true), row.slot }
  local ilvl = Funde.itemLevel(row)
  if ilvl then meta[#meta + 1] = T.itemLevelWord .. int(ilvl) end
  W.setText(ui.meta, table.concat(meta, " · "))
  local when = row.when and T("clock", row.when) or T.whenNone
  W.setText(ui.facts[1], when)
  local where = {}
  if row.zone then where[#where + 1] = row.zone end
  if row.level then where[#where + 1] = T.levelWord .. int(row.level) end
  W.setText(ui.facts[2], #where > 0 and table.concat(where, " · ") or T.whereNone)
  W.setText(ui.facts[3], row.origin)
  local rep = row.replaced
  local v = ui.facts[4]
  if rep then
    local label = rep.name or T("itemNo", string.format("%.0f", rep.itemID))
    W.setText(v, label)
    local qc2 = rep.quality and K.QUALITY_COLOR[rep.quality]
    if qc2 then v:SetTextColor(qc2[1], qc2[2], qc2[3]) else v:SetTextColor(W.color("ink")) end
  else
    W.setText(v, rep == false and T.replacedEmpty or (row.equippedT and T.replacedNone or T.notWorn))
    v:SetTextColor(W.color("sepia"))
  end
  -- values (tooltip lines), otherwise the hint
  local lines = Funde.statLines(row, STATS_N)
  for i, fs in ipairs(ui.stats) do W.setText(fs, lines[i]) end
  W.setText(ui.statsHint, #lines == 0 and T.statsHint or "")
  renderLine(self, row)
end

function View.new(page, left, right)
  local K = kit()
  if not K then error("Funde: Tabellen-Bausteine fehlen") end
  local self = setmetatable({ page = page, ui = {} }, View)
  self.sort, self.desc = "time", true
  self.filter = { quality = nil, slot = nil, zone = nil }
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
  ui.title = K.label(tab, "title", G.size.xl, "ink")
  ui.title:SetText(T.title)
  ui.title:SetPoint("TOPLEFT", tab, "TOPLEFT", TITLE_X, -TITLE_Y)
  ui.sub = K.label(tab, "label", G.size.s, "sepia")
  ui.sub:SetText(T.sub)
  ui.sub:SetWidth(TITLE_W)
  ui.sub:SetWordWrap(false)
  ui.sub:SetPoint("TOPLEFT", tab, "TOPLEFT", TITLE_X, -(TITLE_Y + 34))
  buildHeader(self, tab)
  buildRows(self, tab)
  buildDetail(self, tabR)
  buildPopup(self, tab)
  -- no back label (the sub-bookmark "Übersicht" leads back); Esc leads to the overview. An open column head popup
  -- catches Esc itself (own keyboard, lies above).
  ui.headL:SetTexts(T.brand or "INK & EMBERS", T.book)
  D.escKeys(tab, function() page:CloseFunde() end)
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

function View:SetFilter(key, value)
  if key == "quality" then
    self.filter.quality = type(value) == "number" and value or nil
  elseif key == "slot" or key == "zone" then
    self.filter[key] = type(value) == "string" and value or nil
  else
    return
  end
  self.drop = nil
  self:Render()
end

function View:ClearFilter(key)
  local f = (key == "quality" or key == "slot" or key == "zone") and key or filterOf(key) -- filter name or column
  if not f then return end
  self.filter[f] = nil
  self.drop = nil
  self:Render()
end

function View:SetSortDir(key, desc)
  if not Funde.SORTS[key] then return end
  self.sort, self.desc = key, desc and true or false
  self.drop = nil
  self:Render()
end

function View:TogglePopup(key)
  self.drop = self.drop ~= key and key or nil
  self:Render()
end

function View:ClosePopup()
  if not self.drop then return end
  self.drop = nil
  self:Render()
end

function View:List()
  local f = self.filter
  return Funde.list(self.book, { sort = self.sort, desc = self.desc, quality = f.quality, slot = f.slot, zone = f.zone })
end

-- item data loaded by the client: fill in the names and redraw (only for missing names)
function View:OnItemData(itemID)
  local book = self.book
  if not (self.open and book and itemID and book.pending[itemID]) then return end
  if Funde.resolve(book) > 0 then self:Render() end
  if not next(book.pending) and self.ui.events.UnregisterEvent then self.ui.events:UnregisterEvent("ITEM_DATA_LOAD_RESULT") end
end

local function renderPopup(self)
  local K = kit()
  local ui, f, book = self.ui, self.filter, self.book
  local key = self.drop
  local pop = ui.pop
  if not key then
    pop:Hide()
    return
  end
  local fkey, c = filterOf(key)
  W.setText(pop.sortLbl, fkey and T.sortLbl or T.sortOnlyLbl) -- columns without filter (level, found): sort only
  local w = POP_W[key] or 132
  local h = K.SORT_H + 6
  local list = fkey and ui.lists[fkey]
  if list then
    local items = { { text = T.all, count = book.total, value = nil, active = f[fkey] == nil } }
    local src = fkey == "quality" and book.qualities or (fkey == "slot" and book.slots or book.zones)
    for _, e in ipairs(src) do items[#items + 1] = { text = e.text, count = e.count, value = e.value, active = e.value == f[fkey] } end
    h = K.SORT_H + 4 + min(K.DROP_ROWS, #items) * K.DROP_ROW_H + 8
    K.openList(list, items)
  end
  pop:SetSize(w, h)
  K.place(pop, ui.table, min(LX + c.x, SPREAD_R - w), HEAD_Y + HEAD_H + 3)
  for k, l in pairs(ui.lists) do l.frame:SetShown(k == fkey) end
  ui.popClear:SetShown(fkey ~= nil and f[fkey] ~= nil)
  local on = self.sort == key
  ui.sortUp:SetActive(on and not self.desc)
  ui.sortDown:SetActive(on and self.desc)
  pop:Show()
end

-- find with id in a list
local function indexIn(list, id)
  for i, r in ipairs(list) do
    if r.id == id then return i, r end
  end
  return nil
end

local function newest(list)
  local best
  for _, r in ipairs(list) do
    if not best or (r.t or 0) > (best.t or 0) or ((r.t or 0) == (best.t or 0) and r.id > best.id) then best = r end
  end
  return best
end

-- choose the selection: one click (table, timeline dot); scroll = the find becomes visible in the table
function View:Select(row, scroll)
  if not (self.open and self.book and type(row) == "table") then return end
  self.sel, self.selRow = row.id, row
  local list = self:List()
  if scroll then
    local i = indexIn(list, row.id)
    if i then self.ui.rowsList:ScrollTo(i) end
  end
  self.ui.rowsList:SetItems(list)
  self.ui.rowsList:Refresh()
  renderDetail(self)
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
  for _, h in ipairs(ui.heads) do h:SetShown(not empty) end
  ui.rowsList.frame:SetShown(not empty)
  if empty then
    self.drop, self.sel, self.selRow = nil, nil, nil
    ui.pop:Hide()
    ui.sub:SetShown(false)
    W.setText(ui.count, "")
    W.setText(ui.filterInfo, "")
    renderDetail(self)
    return
  end
  local f = self.filter
  for _, h in ipairs(ui.heads) do
    local fkey = filterOf(h.key)
    h.active, h.desc = h.key == self.sort, self.desc
    h.filtered = fkey ~= nil and f[fkey] ~= nil
    h.open = self.drop == h.key
    h:Paint()
  end
  renderPopup(self)
  local list = self:List()
  local info = {}
  if f.quality then info[#info + 1] = T.filterWord.quality .. " " .. qualityLabel(f.quality, true) end
  if f.slot then info[#info + 1] = T.filterWord.slot .. " " .. f.slot end
  if f.zone then info[#info + 1] = T.filterWord.zone .. " " .. f.zone end
  local filtered = #info > 0
  W.setText(ui.filterInfo, filtered and (T.filterLbl .. table.concat(info, " · ")) or "")
  ui.sub:SetShown(not filtered)
  W.setText(ui.count, filtered and T("countOf", int(#list), int(book.total))
    or T(ns.Locale.plural(#list, "count_one", "count_other"), int(#list)))
  -- selection: the chosen find stays (fresh row from the book), otherwise the newest find of the list
  local _, cur = indexIn(list, self.sel)
  if not cur then
    local n = newest(book.rows)
    if self.sel == nil and n and indexIn(list, n.id) then cur = n else cur = newest(list) end
  end
  self.sel, self.selRow = cur and cur.id or nil, cur
  ui.rowsList:SetItems(list)
  ui.rowsList:Refresh()
  renderDetail(self)
end

function View:Open(index)
  self.book = Funde.build(index)
  self.open = true
  self.drop = nil
  self.sel, self.selRow = nil, nil -- on open: newest find
  self.ui.table:Show()
  self.ui.tableR:Show()
  if next(self.book.pending) then
    Funde.resolve(self.book, true)
    if next(self.book.pending) and self.ui.events.RegisterEvent then
      pcall(self.ui.events.RegisterEvent, self.ui.events, "ITEM_DATA_LOAD_RESULT")
    end
  end
  self:Render()
end

-- new index (new finds) with the view open: table again
function View:Refresh(index)
  if not self.open then return end
  local book = Funde.build(index)
  if book ~= self.book then
    self.book = book
    if next(book.pending) then Funde.resolve(book, true) end
  end
  self:Render()
end

function View:Close()
  local ui = self.ui
  self.open, self.drop = false, nil
  ui.pop:Hide()
  W.hideTip(ui.icon)
  for _, d in ipairs(ui.dots) do W.hideTip(d) end
  ui.table:Hide()
  ui.tableR:Hide()
  if ui.events.UnregisterEvent then ui.events:UnregisterEvent("ITEM_DATA_LOAD_RESULT") end
  for _, h in ipairs(ui.heads) do W.hideTip(h) end
  for _, r in ipairs(ui.rowsList.rows) do W.hideTip(r) end
end
