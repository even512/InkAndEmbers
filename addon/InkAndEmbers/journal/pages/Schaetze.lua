-- Schaetze page: bag and ledger on the left; gold flow (columns per level, sources, or holdings per level as a staircase),
-- gear over time, the "Erstes Blau" slip and the counters on the right. Data from journal/model/Schaetze.lua (display-ready texts).
-- The equipment finds table (pages/SchaetzeFunde.lua) opens via the sub-bookmark "Ausrüstungsfunde" (Page.subs); the
-- overview sits in its own holders (mainL/mainR). No ticker, no OnUpdate; pools are bounded.
local _, ns = ...

local Journal = ns.Journal
local Pages, Widgets, Schaetze = Journal and Journal.Pages, Journal and Journal.Widgets, Journal and Journal.Schaetze
local D = Widgets and Widgets.Diary -- diary toolkit "diary with stickers"
if not (Pages and Widgets and Schaetze and D) then return end

local Theme = Journal.Theme or {}
local floor, max, min = math.floor, math.max, math.min

local Page = { needs = { index = true } }
Journal.SchaetzePage = Page

local G = Theme.GRID
local L0, LW = Theme.gridX("L")      -- left: edge and width of the text block (92, 402)
local R0, RW = Theme.gridX("R")      -- right (44, 402)

-- gold balance (bag, right-aligned): font xl, line height, coin edge (Texts.bagCoinPx is computed for font 34, scaled
-- here with BAG_FONT / 34),
-- gap after the number / between the places, distance of the baseline to the bottom edge of the line
local BAG_FONT, BAG_LINE = G.size.xl, 34
local BAG_SCALE = BAG_FONT / 34
local BAG_COIN_GAP, BAG_PART_GAP, BAG_BASE = 3, 9, 6
local BAG_Y = G.slots.title.y + 14   -- bag number (label "IM BEUTEL" above it at y 66)

-- ledger (rows: table dense 16 / running text 18 from GRID.line)
local LEDGER_HEAD_Y = 146            -- section head "Haushaltsbuch" (font l), rule below; air to the line "je Spielstunde"
local LEDGER_Y = LEDGER_HEAD_Y + 28
local ROW_POOL = 24
local ROW_H = { head = 20, row = G.line.text, sum = 26, rest = 16, total = 30 }
local SUM_PAD = 6                  -- sum/balance row: rule 2 px under the previous row, text 6 px lower
local COL_K, COL_S = 44, 50        -- distance of the silver and gold columns from the right edge
-- the decorations bottom left (keep-out x 41..154, y 478..601) stay free: the ledger ends here at the latest
local LEDGER_END = 474
local ROW_H_MIN = 14                   -- tightest row height with a full ledger

local FLOW_Y, FLOW_H = G.slots.body.y, Schaetze.FLOW_HEIGHT
local AXIS_W = 64                  -- label of the vertical axis on the left
local PLOT_T, PLOT_B = 18, 122     -- plot area (y from the top, in the area); the levels below
local VALUE_PAD = 14               -- room for amounts at the columns (with few levels)
local VALUE_MAX = 6                -- amounts sit at the columns up to this many levels
local BAR_MAX, BAR_MIN = 30, 2     -- column width
local LINE_MAX = 120               -- upper limit of the spec (lines in the gold flow)
local COL_MAX = Schaetze.LEVEL_COLS or 60

local GEAR_HEAD_Y = FLOW_Y + FLOW_H + G.section.before   -- section head "Ausrüstung im Wandel"
local GEAR_Y, GEAR_ROW = GEAR_HEAD_Y + G.section.h + G.section.after, 18
local STRIP_X = R0 + 70
local STRIP_W = RW - 70 - 8       -- ends at x 438: left of the scale/key (keep-out right x 440..527, y 347..426, page pair v2)
local RUN_POOL, DASH_POOL = 360, 400

-- bottom: first blue left, finds by quality to its right; ends before y 556 (decoration bottom right, x 400..501, y 556..644)
local BOTTOM_Y = GEAR_Y + 7 * GEAR_ROW + 26
local NOTE_W = 140                 -- slip "Erstes Seltenes" (narrower so that the Blizzard quality names fit side by side)
local GEM_X = R0 + NOTE_W + 14     -- finds by quality: four columns up to the text block edge
local GEM_W = floor((R0 + RW - GEM_X - 4) / 4) -- 4 px air to the decoration bottom right

-- locale scope "p.Schaetze" (English in locales/enUS_pages.lua), read when drawing
Page.TEXT = ns.Locale.ns("p.Schaetze", {
  level = "Stufe %s", levels = "Stufe %s–%s", total = "Gesamt %s", gearSub = "%s Wechsel · Stufe 1 bis %s",
  brand = "INK & EMBERS", page = "SCHÄTZE", book = "BEUTEL", bag = "IM BEUTEL",
  ledger = "Haushaltsbuch", flow = "Goldfluss", flowSub = "Woher das Gold kam und wohin es ging",
  toBars = "Quellen", toBand = "Stufen", noMoney = "Noch kein Gold bewegt.",
  -- empty states in handwriting
  bagEmpty = "Leerer Beutel",
  ledgerEmpty = "Noch kein Gold bewegt. Beute, Questlohn und Händler tragen sich hier von selbst ein.",
  flowEmpty = "Noch kein Gold bewegt. Sobald Münzen klimpern, zeigt sich hier, woher sie kamen und wohin sie gingen.",
  gearEmptyHand = "Noch keine Ausrüstung erfasst. Mit jedem angelegten Teil wächst hier die Zeitleiste von Stufe 1 bis %s.",
  qualityEmpty = "Jeder Fund wird hier nach Güte gezählt.",
  flowLevels = "Ein- und Ausgaben je Stufe", income = "Einnahmen", expense = "Ausgaben", net = "Saldo",
  toHold = "Besitz", holdTip = "Besitz je Stufe", holdTip2 = "Das meiste Gold im Beutel in jeder Stufe",
  flowHold = "Höchster Goldbesitz je Stufe", holdPeak = "Höchststand %s · Stufe %s", holdJump = "Größter Sprung +%s · Stufe %s",
  gear = "Ausrüstung im Wandel", gearEmpty = "Noch keine Ausrüstung erfasst.", quality = "FUNDE NACH GÜTE",
  incomeBar = "EINNAHMEN", expenseBar = "AUSGABEN UND BEUTEL", blue = "Erstes Seltenes",
  toOverview = "Übersicht", overviewTip = "Beutel, Haushaltsbuch und Goldfluss",
  toFunde = "Ausrüstungsfunde", fundeTip = "Alle Ausrüstungsfunde ab Güte Ungewöhnlich",
  fundeTipEpic = "Episch zählt epische und legendäre Funde zusammen.",
  fundeTip2 = "Tabelle: woher, wo und auf welcher Stufe",
})

local function font(parent, kind, size, color, justify)
  local fs = Widgets.font(parent, kind, size, color)
  if justify then fs:SetJustifyH(justify) end
  return fs
end

local function set(fs, text) Widgets.setText(fs, text) end

local function tex(parent, layer)
  return parent:CreateTexture(nil, layer or "ARTWORK")
end

-- getLines(frame) -> lines, colors
local function hover(frame, getLines)
  frame:EnableMouse(true)
  frame:SetScript("OnEnter", function(self)
    local ok, lines, colors = Widgets.call(getLines, self)
    if ok and type(lines) == "table" then Widgets.tip(self, lines, colors) end
  end)
  frame:SetScript("OnLeave", function(self) Widgets.hideTip(self) end)
end

local function buildRow(left)
  local r = {}
  r.label = font(left, "label", G.size.m, "sepia", "LEFT")
  r.label:SetWordWrap(false)
  r.g = font(left, "title", G.size.m, "ink", "RIGHT")
  r.s = font(left, "title", G.size.m, "ink", "RIGHT")
  r.k = font(left, "title", G.size.m, "ink", "RIGHT")
  r.dots = tex(left, "ARTWORK")
  r.dots:SetColorTexture(Widgets.color("sepia", 0.4))
  r.dots:SetHeight(1)
  r.rule = tex(left, "ARTWORK")
  r.rule:SetColorTexture(Widgets.color("sepia", 0.55))
  r.rule:SetHeight(1)
  r.hit = CreateFrame("Frame", nil, left)
  hover(r.hit, function(f) return f.tipLines end)
  r.hit:Hide()
  for _, e in ipairs({ r.label, r.g, r.s, r.k, r.dots, r.rule }) do e:Hide() end
  return r
end

local function buildLeft(self, left)
  local T = Page.TEXT
  local u = {}
  self.L = u
  u.head = Widgets.NewPageHead(left, { side = "L" })
  u.head:SetTexts(T.brand, T.book)

  -- bag (title block, right-aligned: the wax drops sit top left): label + day, below the big number, below that per hour
  u.day = font(left, "label", G.size.xs, "sepia", "RIGHT")
  u.day:SetPoint("TOPRIGHT", left, "TOPLEFT", L0 + LW, -G.slots.title.y)
  local bl = font(left, "label", G.size.xs, "sepia", "RIGHT")
  bl:SetPoint("BOTTOMRIGHT", u.day, "BOTTOMLEFT", -8, 0)
  set(bl, T.bag)
  u.bag = font(left, "title", BAG_FONT, "ink", "RIGHT")
  u.bag:SetPoint("TOPRIGHT", left, "TOPLEFT", L0 + LW, -BAG_Y)
  u.bag:SetHeight(BAG_LINE)  -- fixed line height for the 28 px number
  u.bag:SetJustifyV("TOP")
  u.bag:SetWidth(LW)
  u.bag:SetWordWrap(false)
  -- gold balance with amount: number and coin separate (number = text, coin = a real texture object of fixed size). A
  -- |T escape in the big font was enlarged many times by the client
  -- (~40 px, pixelated); a texture object has exactly the size SetSize says. u.bag shows only the text without amount
  -- ("Noch kein Gold ...").
  u.bagParts = {}
  for i = 1, 3 do
    local p = {}
    p.num = font(left, "title", BAG_FONT, "ink", "RIGHT")
    p.num:SetHeight(BAG_LINE)
    p.num:SetJustifyV("BOTTOM")
    p.num:SetWordWrap(false)
    p.coin = left:CreateTexture(nil, "OVERLAY")
    p.coin:SetSize(floor(25 * BAG_SCALE + 0.5), floor(25 * BAG_SCALE + 0.5))
    p.num:Hide()
    p.coin:Hide()
    u.bagParts[i] = p
  end
  u.perHour = font(left, "text", G.size.m, "ink", "RIGHT")
  u.perHour:SetPoint("TOPRIGHT", left, "TOPLEFT", L0 + LW, -(BAG_Y + BAG_LINE + 4))
  u.perHour:SetWidth(LW)
  u.perHour:SetWordWrap(false)

  -- ledger section (left at y 124, the rule below across the text block; the rows below)
  local lt = font(left, "title", G.size.l, "ink", "LEFT")
  lt:SetPoint("TOPLEFT", left, "TOPLEFT", L0, -LEDGER_HEAD_Y)
  set(lt, T.ledger)
  Widgets.NewRule(left, L0, LEDGER_HEAD_Y + 24, LW)

  u.rows = {}
  for i = 1, ROW_POOL do u.rows[i] = buildRow(left) end
  u.empty = D.emptyNote(left, LW - 40)
  u.empty:SetPoint("TOP", left, "TOPLEFT", L0 + LW / 2, -(LEDGER_Y + 40))
  -- footnote in the footer (grid: flush with the fold); it stays right of x 154, the decorations bottom left stay free
  local fp, fx, fy = Theme.gridFoot("L")
  u.foot = font(left, "label", G.size.xs, "sepia", "RIGHT")
  u.foot:SetPoint(fp, left, "TOPLEFT", fx, -fy)
  u.foot:SetWidth(LW - 100)
  u.foot:SetJustifyV("TOP")
end

-- height of the single rows (kind "row"): normally ROW_H.row; with all optional rows present (mail, trade, guild bank,
-- other on both sides)
-- it gets tighter so the book does not run into the margin notes
local function rowHeight(rows)
  local fixed, count = 0, 0
  for i, spec in ipairs(rows) do
    if i > ROW_POOL then break end
    if spec.kind == "row" then count = count + 1 else fixed = fixed + (ROW_H[spec.kind] or 17) end
  end
  if count == 0 then return ROW_H.row end
  return max(ROW_H_MIN, min(ROW_H.row, floor((LEDGER_END - LEDGER_Y - fixed) / count)))
end

local function placeRow(left, r, spec, y, rowH)
  local kind = spec.kind
  local h = kind == "row" and rowH or ROW_H[kind] or 17
  local big = (kind == "sum" or kind == "total")
  local ruleY = y + 2
  if big then y = y + SUM_PAD end
  r.label:ClearAllPoints()
  r.label:SetPoint("TOPLEFT", left, "TOPLEFT", L0, -y - (kind == "head" and 6 or 0))
  r.label:SetFont(Widgets.FONT[big and "title" or "label"], kind == "total" and G.size.l or (kind == "sum" and G.size.m or (kind == "head" and G.size.xs or G.size.m)), "")
  r.label:SetTextColor(Widgets.color((big or kind == "rest") and "ink" or "sepia"))
  set(r.label, spec.label)
  r.label:Show()
  local size = kind == "total" and G.size.l or G.size.m
  local cols = { { r.k, spec.k, 0 }, { r.s, spec.s, COL_K }, { r.g, spec.g, COL_K + COL_S } }
  local first
  for _, c in ipairs(cols) do
    local fs, text, off = c[1], c[2], c[3]
    fs:ClearAllPoints()
    if kind == "head" then
      set(fs, "")
      fs:Hide()
    else
      fs:SetPoint("TOPRIGHT", left, "TOPLEFT", L0 + LW - off, -y + (big and 0 or 1))
      fs:SetFont(Widgets.FONT.title, size, "")
      local color = spec.neg and "red" or (spec.zero and "sepia" or "ink")
      fs:SetTextColor(Widgets.color(color, spec.zero and 0.6 or 1))
      set(fs, text)
      fs:Show()
      if type(text) == "string" and text ~= "" then first = fs end
    end
  end
  -- dotted line between name and first column (not for head, sum and balance)
  r.dots:ClearAllPoints()
  if kind == "row" or kind == "rest" then
    r.dots:SetPoint("BOTTOMLEFT", r.label, "BOTTOMRIGHT", 6, 3)
    r.dots:SetPoint("BOTTOMRIGHT", first or r.k, "BOTTOMLEFT", -6, 3)
    r.dots:Show()
  else
    r.dots:Hide()
  end
  r.rule:ClearAllPoints()
  if kind == "sum" or kind == "total" then
    r.rule:SetPoint("TOPLEFT", left, "TOPLEFT", L0, -ruleY)
    r.rule:SetWidth(LW)
    r.rule:Show()
  elseif kind == "head" then
    r.rule:SetPoint("TOPLEFT", left, "TOPLEFT", L0, -y - 3)
    r.rule:SetWidth(LW)
    r.rule:Show()
  else
    r.rule:Hide()
  end
  r.hit:ClearAllPoints()
  r.hit:SetPoint("TOPLEFT", left, "TOPLEFT", L0, -y)
  r.hit:SetSize(LW, big and (h - SUM_PAD) or h)
  r.hit.tipLines = spec.tip
  r.hit:EnableMouse(spec.tip ~= nil)
  r.hit:Show()
  return h
end

local function hideRow(r)
  Widgets.hideTip(r.hit)
  r.hit.tipLines = nil
  for _, e in ipairs({ r.label, r.g, r.s, r.k, r.dots, r.rule, r.hit }) do e:Hide() end
end

-- gold balance: numbers as text, coins as texture objects (BAG_COIN px) on the baseline right of the number
local function drawBag(u, beutel)
  local Texts = Journal.Texts
  local parts = beutel.copper and Texts and Texts.moneyParts and Texts.moneyParts(beutel.copper) or nil
  for _, p in ipairs(u.bagParts) do
    p.num:Hide(); p.coin:Hide(); p.num:ClearAllPoints(); p.coin:ClearAllPoints()
  end
  if not parts then
    set(u.bag, beutel.copper and beutel.text or Page.TEXT.bagEmpty)
    return
  end
  set(u.bag, "")
  -- from right to left: the last coin at the right edge, its number before it, then the next coin ... (baselines as before)
  local n = min(#parts, #u.bagParts)
  for i = n, 1, -1 do
    local part, p = parts[i], u.bagParts[i]
    p.coin:ClearAllPoints()
    p.num:ClearAllPoints()
    if i == n then
      p.coin:SetPoint("BOTTOMRIGHT", u.bag, "BOTTOMRIGHT", 0, BAG_BASE)
    else
      p.coin:SetPoint("BOTTOMRIGHT", u.bagParts[i + 1].num, "BOTTOMLEFT", -BAG_PART_GAP, BAG_BASE)
    end
    p.num:SetPoint("BOTTOMRIGHT", p.coin, "BOTTOMLEFT", -BAG_COIN_GAP, -BAG_BASE)
    set(p.num, part.n)
    p.num:Show()
    -- source (Texts.coinSource): higher-resolution atlas, otherwise the MoneyFrame file (then at most COIN_FILE_MAX px)
    local kind, name = Texts.coinSource(part.unit)
    local size = Texts.bagCoinPx(part.unit)
    if kind == "atlas" and p.coin.SetAtlas then
      p.coin:SetAtlas(name, false)
    else
      size = min(size, Texts.COIN_FILE_MAX)
      p.coin:SetTexture(Texts.COIN_FILE[part.unit])
    end
    size = floor(size * BAG_SCALE + 0.5)
    p.coin:SetSize(size, size)
    p.coin:Show()
  end
end

local function drawLeft(self, view)
  local u = self.L
  local T = Page.TEXT
  set(u.day, view.beutel.dayText)
  drawBag(u, view.beutel)
  set(u.perHour, view.perHour and view.perHour.text or "")
  local ledger = view.ledger
  local n = 0
  local y = LEDGER_Y
  if not ledger.empty then
    local rowH = rowHeight(ledger.rows)
    for _, spec in ipairs(ledger.rows) do
      n = n + 1
      local r = u.rows[n]
      if not r then break end
      y = y + placeRow(self.left, r, spec, y, rowH)
    end
  end
  for i = n + 1, ROW_POOL do hideRow(u.rows[i]) end
  set(u.empty, ledger.empty and T.ledgerEmpty or "")
  set(u.foot, ledger.notes and table.concat(ledger.notes, " ") or "")
end

local function flowPools(self, flow)
  local u = self.R
  -- lines only if the client knows CreateLine (otherwise the balance dots stay unconnected)
  if self.canLine then
    u.lines = Widgets.Pool(function() return flow:CreateLine(nil, "OVERLAY") end, nil, LINE_MAX)
  else
    u.lines = Widgets.Pool(function() return nil end, nil, 0)
  end
  u.nodes = Widgets.Pool(function() return flow:CreateTexture(nil, "OVERLAY") end, nil, COL_MAX + 8)
  u.segs = Widgets.Pool(function() return flow:CreateTexture(nil, "ARTWORK") end, nil, 2 * COL_MAX + 32)
  u.labels = Widgets.Pool(function()
    local fs = font(flow, "label", G.size.xs, "ink", "LEFT")
    fs:SetWordWrap(false)
    return fs
  end, function(fs) fs:SetText("") end, 48)
  u.hits = Widgets.Pool(function()
    local h = CreateFrame("Frame", nil, flow)
    hover(h, function(f) return f.tipLines end)
    return h
  end, function(h)
    Widgets.hideTip(h)
    h.tipLines = nil
  end, COL_MAX + 8)
end

local function buildRight(self, right)
  local T = Page.TEXT
  local u = {}
  self.R = u
  u.head = Widgets.NewPageHead(right, { side = "R" })
  u.head:SetTexts("", T.page)

  -- title (xl) and sub title; control line y 118: left the toggle Stufen / Quellen, right the level range
  local ft = font(right, "title", G.size.xl, "ink", "LEFT")
  ft:SetPoint("TOPLEFT", right, "TOPLEFT", R0, -G.slots.title.y)
  set(ft, T.flow)
  u.flowSub = font(right, "label", G.size.s, "sepia", "LEFT")
  u.flowSub:SetPoint("TOPLEFT", right, "TOPLEFT", R0, -(G.slots.title.y + 34))
  set(u.flowSub, T.flowSub)
  u.flowTotal = font(right, "label", G.size.s, "sepia", "RIGHT")
  u.flowTotal:SetPoint("RIGHT", right, "TOPLEFT", R0 + RW, -(G.slots.ctrl.y + G.slots.ctrl.h / 2))
  -- toggle Stufen / Quellen (chosen view circled); onChange only on click
  u.toggle = D.NewToggle(right, { value = "levels", size = G.size.s, gap = 14,
    items = { { key = "levels", label = T.toBand }, { key = "bars", label = T.toBars } },
    onChange = function(key)
      local ok, err = pcall(Page.SetFlow, self, key)
      if not ok then Pages.fail("schaetze", err) end
    end })
  u.toggle.frame:SetPoint("LEFT", right, "TOPLEFT", R0 - 3, -(G.slots.ctrl.y + G.slots.ctrl.h / 2))

  local flow = CreateFrame("Frame", nil, right)
  flow:SetSize(RW, FLOW_H)
  flow:SetPoint("TOPLEFT", right, "TOPLEFT", R0, -FLOW_Y)
  u.flow = flow
  flowPools(self, flow)
  u.flowEmpty = D.emptyNote(flow, RW - 60)
  u.flowEmpty:SetPoint("CENTER", flow, "CENTER", 0, 0)
  u.barHeads = {}
  for i = 1, 2 do
    u.barHeads[i] = font(flow, "label", G.size.xs, "sepia", "LEFT")
    u.barHeads[i]:Hide()
  end
  u.legend = Widgets.Pool(function()
    local item = {}
    item.swatch = tex(flow, "ARTWORK")
    item.swatch:SetSize(8, 8)
    item.text = font(flow, "label", G.size.xs, "ink", "LEFT")
    item.text:SetWordWrap(false)
    function item:Show() self.swatch:Show() self.text:Show() end
    function item:Hide() self.swatch:Hide() self.text:Hide() end
    function item:ClearAllPoints() self.swatch:ClearAllPoints() self.text:ClearAllPoints() end
    return item
  end, function(item) item.text:SetText("") end, 24)

  -- gear: section head left, on the same line right the number of changes
  local gt = font(right, "title", G.size.l, "ink", "LEFT")
  gt:SetPoint("TOPLEFT", right, "TOPLEFT", R0, -GEAR_HEAD_Y)
  set(gt, T.gear)
  u.gearSub = font(right, "label", G.size.s, "sepia", "RIGHT")
  u.gearSub:SetPoint("BOTTOMRIGHT", right, "TOPLEFT", R0 + RW, -(GEAR_HEAD_Y + 22))
  -- without gear no empty timeline but a handwritten sentence (ends left of the scale)
  u.gearEmpty = D.emptyNote(right, STRIP_X + STRIP_W - R0 - 30)
  u.gearEmpty:SetPoint("TOP", right, "TOPLEFT", R0 + (STRIP_X + STRIP_W - R0) / 2, -(GEAR_Y + 2 * GEAR_ROW))
  local nSlots = #Schaetze.GEAR_SLOTS
  u.slotLbl, u.track = {}, {}
  for i, def in ipairs(Schaetze.GEAR_SLOTS) do
    local y = GEAR_Y + (i - 1) * GEAR_ROW
    -- label only (slots not clickable, no explanatory text below); hover sits on the strips
    local b = font(right, "label", G.size.xs, "ink", "LEFT")
    b:SetPoint("TOPLEFT", right, "TOPLEFT", R0 + 2, -(y + 2))
    set(b, def.label)
    u.slotLbl[i] = b
    local tr = tex(right, "BORDER")
    tr:SetColorTexture(Widgets.color("sepia", 0.07))
    tr:SetPoint("TOPLEFT", right, "TOPLEFT", STRIP_X, -(y + 3))
    tr:SetSize(STRIP_W, 12)
    u.track[i] = tr
  end
  -- ticks every 10 levels up to the client's highest level (Forever 60: 6 ticks; Retail 80/90: 8/9 ticks, cells >= 3 px)
  u.ticks, u.tickLabels = {}, {}
  local top = Schaetze.maxLevel()
  u.gearTop = top
  local cell = STRIP_W / top
  for L = 10, top, 10 do
    local x = STRIP_X + L * cell
    local t = tex(right, "BORDER")
    t:SetColorTexture(Widgets.color("sepia", 0.18))
    t:SetPoint("TOPLEFT", right, "TOPLEFT", x, -(GEAR_Y + 1))
    t:SetSize(1, nSlots * GEAR_ROW - 4)
    local l = font(right, "label", G.size.xs, "sepia", "CENTER")
    l:SetPoint("TOP", right, "TOPLEFT", x, -(GEAR_Y + nSlots * GEAR_ROW))
    set(l, tostring(L))
    u.ticks[#u.ticks + 1], u.tickLabels[#u.tickLabels + 1] = t, l
  end
  u.runs = Widgets.Pool(function() return right:CreateTexture(nil, "ARTWORK") end, nil, RUN_POOL)
  u.dashes = Widgets.Pool(function() return right:CreateTexture(nil, "ARTWORK") end, nil, DASH_POOL)
  u.runHits = Widgets.Pool(function()
    local h = CreateFrame("Frame", nil, right)
    -- original item tooltip, below it "Stufe(n) von-bis" (extra line only on show, saves memory in the evaluator)
    hover(h, function(f)
      local t = f.tipLines
      if type(t) == "table" and t.item and not t.itemExtra then t.itemExtra = { t[2] } end
      return t
    end)
    return h
  end, function(h)
    Widgets.hideTip(h)
    h.tipLines = nil
  end, RUN_POOL)

  -- first blue (left) and quality counters (right of it); all below y 556 or left of x 400 (decoration bottom right)
  u.note = Widgets.NewNote(right, { width = NOTE_W, titleSize = G.size.m, textSize = G.size.xs })
  u.note.frame:SetPoint("TOPLEFT", right, "TOPLEFT", R0, -BOTTOM_Y)
  -- hover on the slip: original tooltip of the first blue piece (blueTip.item), else nothing
  hover(u.note.frame, function() return self.blueTip end)
  local qh = font(right, "label", G.size.xs, "sepia", "LEFT")
  qh:SetPoint("TOPLEFT", right, "TOPLEFT", GEM_X, -BOTTOM_Y)
  set(qh, T.quality)
  u.gems = {}
  for i = 1, 4 do
    local x = GEM_X + (i - 1) * GEM_W
    local g = {}
    g.frame = CreateFrame("Frame", nil, right)
    g.frame:SetSize(14, 14)
    g.frame:SetPoint("TOP", right, "TOPLEFT", x + GEM_W / 2, -(BOTTOM_Y + 18))
    g.shape = Theme.roundRect and Theme.roundRect(g.frame, { 0.4, 0.4, 0.4 }, 1, 5, "ARTWORK") or nil
    g.count = font(right, "title", G.size.m, "ink", "CENTER")
    g.count:SetPoint("TOP", right, "TOPLEFT", x + GEM_W / 2, -(BOTTOM_Y + 34))
    g.name = font(right, "label", G.size.xs, "sepia", "CENTER")
    g.name:SetPoint("TOP", right, "TOPLEFT", x + GEM_W / 2, -(BOTTOM_Y + 52))
    u.gems[i] = g
  end
  u.grey = font(right, "label", G.size.xs, "sepia", "LEFT")
  u.grey:SetPoint("TOPLEFT", right, "TOPLEFT", GEM_X, -(BOTTOM_Y + 69))
  u.grey:SetWidth(RW - NOTE_W - 14 - GEM_W)
  u.grey:SetWordWrap(false)
  u.gemEmpty = D.emptyNote(right, RW - NOTE_W - 14 - 10, 17)
  u.gemEmpty:SetPoint("TOP", right, "TOPLEFT", GEM_X + (RW - NOTE_W - 14) / 2, -(BOTTOM_Y + 20))
  -- the block "Funde nach Güte" (fundeHit) has only its hover tooltip; the table of equipment finds opens via the
  -- sub-bookmark, the footer stays free
  u.fundeHit = CreateFrame("Frame", nil, right)
  u.fundeHit:SetPoint("TOPLEFT", right, "TOPLEFT", GEM_X - 4, -(BOTTOM_Y - 4))
  u.fundeHit:SetSize(RW - NOTE_W - 14 + 4, 88)
  hover(u.fundeHit, function() return { T.fundeTip, T.fundeTip2, T.fundeTipEpic } end)
end

function Page:Build(left, right)
  -- overview in its own holders so the sub-view "Ausrüstungsfunde" (pages/SchaetzeFunde.lua) can hide it
  local mainL, mainR = CreateFrame("Frame", nil, left), CreateFrame("Frame", nil, right)
  mainL:SetAllPoints(left)
  mainR:SetAllPoints(right)
  self.mainL, self.mainR = mainL, mainR
  self.holderL, self.holderR = left, right
  self.left, self.right = mainL, mainR
  self.flowMode = "levels"
  self.canLine = type(mainR.CreateLine) == "function"
  buildLeft(self, mainL)
  buildRight(self, mainR)
  self.built = true
end

-- sub-view "Ausrüstungsfunde": via the sub-bookmark, Esc leads to the overview; every change goes to Pages.subChanged
-- (update the sub-bookmarks)

function Page.OpenFunde(self)
  local View = Journal.FundeView
  if not (self.built and View and self.index) then return end
  if not self.funde then self.funde = View.new(self, self.holderL, self.holderR) end
  Widgets.hideTip(self.R.fundeHit)
  self.mainL:Hide()
  self.mainR:Hide()
  self.fundeOpen = true
  self.funde:Open(self.index)
  Pages.subChanged("schaetze")
end

function Page.CloseFunde(self)
  local was = self.fundeOpen
  if self.funde then self.funde:Close() end
  self.fundeOpen = false
  if self.mainL then
    self.mainL:Show()
    self.mainR:Show()
  end
  if was then Pages.subChanged("schaetze") end
end

-- sub-bookmarks (contract journal/Pages.lua): overview · equipment finds. Labels are read late (the language is not yet
-- fixed when the file loads)
local function subTab(key, label, tip1, tip2)
  return setmetatable({ key = key }, { __index = function(_, k)
    if k == "label" then return Page.TEXT[label] end
    if k == "tip" then return { Page.TEXT[tip1], Page.TEXT[tip2] } end
  end })
end
Page.subs = {
  subTab("uebersicht", "toOverview", "toOverview", "overviewTip"),
  subTab("funde", "toFunde", "fundeTip", "fundeTip2"),
}

function Page:GetSub() return self.fundeOpen and "funde" or "uebersicht" end

function Page:ShowSub(key)
  if key == self:GetSub() then return end
  if key == "funde" then Page.OpenFunde(self) else Page.CloseFunde(self) end
end

local function clearFlow(self)
  local u = self.R
  u.lines:ReleaseAll()
  u.nodes:ReleaseAll()
  u.segs:ReleaseAll()
  u.labels:ReleaseAll()
  u.hits:ReleaseAll()
  u.legend:ReleaseAll()
  for _, h in ipairs(u.barHeads) do h:Hide() end
end

local function nodeHit(u, x, y, w, h, tip)
  local hit = u.hits:Acquire()
  if not hit then return end
  hit:SetPoint("TOPLEFT", u.flow, "TOPLEFT", x, -y)
  hit:SetSize(max(w, 1), max(h, 1))
  hit.tipLines = tip
end

local function flowRect(u, x, y, w, h, color, alpha, pool)
  local t = (pool or u.segs):Acquire()
  if not t then return nil end
  t:SetColorTexture(Widgets.color(color, alpha or 1))
  t:SetPoint("TOPLEFT", u.flow, "TOPLEFT", x, -y)
  t:SetSize(max(w, 1), max(h, 1))
  return t
end

local function flowLabel(u, text, x, y, justify, color, width)
  local fs = u.labels:Acquire()
  if not fs then return nil end
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWidth(width or 60)
  fs:SetTextColor(Widgets.color(color or "sepia"))
  local anchor = justify == "RIGHT" and "TOPRIGHT" or (justify == "CENTER" and "TOP" or "TOPLEFT")
  fs:SetPoint(anchor, u.flow, "TOPLEFT", x, -y)
  set(fs, text)
  return fs
end

-- legend on top: income, expenses, balance
local function levelLegend(u)
  local T = Page.TEXT
  local x = AXIS_W
  for _, e in ipairs({ { T.income, "gold" }, { T.expense, "red" }, { T.net, "ink" } }) do
    local item = u.legend:Acquire()
    if item then
      item.swatch:SetColorTexture(Widgets.color(e[2], 0.9))
      item.swatch:SetPoint("TOPLEFT", u.flow, "TOPLEFT", x, -2)
      item.text:SetPoint("LEFT", item.swatch, "RIGHT", 4, 0)
      item.text:SetTextColor(Widgets.color("sepia"))
      set(item.text, e[1])
      local sw = item.text.GetStringWidth and tonumber(item.text:GetStringWidth()) or 0
      x = x + 8 + 4 + (sw > 0 and sw or #e[1] * 5) + 14
    end
  end
end

-- columns per level around a horizontal zero axis: income up (gold), expenses down (red), same scale for both sides.
-- Balance per level as an ink dot joined with straight lines (CreateLine only).
-- Few levels: wide columns (at most BAR_MAX), amounts right at the column.
local function drawLevels(self, series)
  local u = self.R
  local cols = series.cols
  local n = #cols
  local maxG, maxL = series.maxGain, series.maxLoss
  local showValues = n <= VALUE_MAX
  local top = PLOT_T + (showValues and VALUE_PAD or 0)
  local bottom = PLOT_B - ((showValues and maxL > 0) and VALUE_PAD or 0)
  local h = bottom - top
  -- position of the zero axis: income share of the span, both sides visible (if present)
  local share = 1
  if maxL > 0 and maxG > 0 then
    share = min(0.85, max(0.25, maxG / (maxG + maxL)))
  elseif maxL > 0 then
    share = 0.15
  end
  local y0 = floor(top + h * share + 0.5)
  local sc = math.huge
  if maxG > 0 then sc = min(sc, (y0 - top) / maxG) end
  if maxL > 0 then sc = min(sc, (bottom - y0) / maxL) end
  if sc == math.huge then sc = 0 end
  local x0, plotW = AXIS_W, RW - AXIS_W
  local slot = plotW / max(n, 1)
  local barW = floor(min(BAR_MAX, max(BAR_MIN, slot * 0.62)))

  levelLegend(u)
  -- vertical axis: guide lines at the maxima, the zero axis strong
  if maxG > 0 then
    flowRect(u, x0, top, plotW, 1, "sepia", 0.18)
    flowLabel(u, "+" .. series.maxGainText, x0 - 6, top - 5, "RIGHT", "sepia", AXIS_W - 6)
  end
  if maxL > 0 then
    flowRect(u, x0, bottom, plotW, 1, "sepia", 0.18)
    flowLabel(u, "-" .. series.maxLossText, x0 - 6, bottom - 5, "RIGHT", "sepia", AXIS_W - 6)
  end
  flowRect(u, x0, y0, plotW, 1, "ink", 0.7)
  flowLabel(u, "0", x0 - 6, y0 - 5, "RIGHT", "sepia", AXIS_W - 6)

  -- level labels: all with few levels, otherwise every 5th/10th and the last
  local step = n <= 12 and 1 or (n <= 30 and 5 or 10)
  local lastLabel
  local points = {}
  local dot = n <= 20 and 5 or 2
  for i, c in ipairs(cols) do
    local cx = x0 + (i - 0.5) * slot
    local bx = floor(cx - barW / 2 + 0.5)
    if c.gain > 0 then
      local bh = max(1, floor(c.gain * sc + 0.5))
      flowRect(u, bx, y0 - bh, barW, bh, "gold", 0.9)
      if showValues then
        flowLabel(u, Schaetze.moneyText(c.gain, true, false, Schaetze.FONT.label), cx, y0 - bh - 15, "CENTER", "ink", max(slot, 60))
      end
    end
    if c.loss > 0 then
      local bh = max(1, floor(c.loss * sc + 0.5))
      flowRect(u, bx, y0 + 1, barW, bh, "red", 0.8)
      if showValues then
        flowLabel(u, Schaetze.moneyText(c.loss, true, false, Schaetze.FONT.label), cx, y0 + 1 + bh + 4, "CENTER", "red", max(slot, 60))
      end
    end
    local py = y0 - c.net * sc
    points[i] = { cx, py }
    -- dots with few levels (or without lines); with many levels the line alone carries
    if n <= 20 or not self.canLine then flowRect(u, floor(cx - dot / 2 + 0.5), py - dot / 2, dot, dot, "ink", 1, u.nodes) end
    local L = c.level
    if step == 1 or (L % step == 0) or (i == n and (not lastLabel or i - lastLabel >= step / 2)) then
      flowLabel(u, Journal.Texts.int(L), cx, PLOT_B + 4, "CENTER", "sepia", 30)
      lastLabel = i
    end
    nodeHit(u, x0 + (i - 1) * slot, PLOT_T - 2, slot, PLOT_B - PLOT_T + 14, c.tip)
  end
  -- balance line: straight segments between the dots
  if self.canLine and n >= 2 then
    local r, g, b = Widgets.color("ink")
    for i = 2, n do
      local ln = u.lines:Acquire()
      if not ln then break end
      ln:SetThickness(1.5)
      ln:SetColorTexture(r, g, b, 0.85)
      ln:SetStartPoint("TOPLEFT", u.flow, points[i - 1][1], -points[i - 1][2])
      ln:SetEndPoint("TOPLEFT", u.flow, points[i][1], -points[i][2])
    end
  end
end

-- fallback: two stacked bars (income, expenses and bag) with legend
local function drawBars(self, flow)
  local u = self.R
  local blocks = {
    { nodes = flow.left, title = Page.TEXT.incomeBar, y = 0 },
    { nodes = flow.right, title = Page.TEXT.expenseBar, y = 72 },
  }
  for i, bl in ipairs(blocks) do
    local head = u.barHeads[i]
    head:ClearAllPoints()
    head:SetPoint("TOPLEFT", u.flow, "TOPLEFT", 0, -bl.y)
    local sum = 0
    for _, n in ipairs(bl.nodes) do sum = sum + n.copper end
    set(head, bl.title .. " · " .. Schaetze.moneyText(sum, true, false, 11))
    head:Show()
    local bg = u.segs:Acquire()
    if bg then
      bg:SetColorTexture(Widgets.color("sepia", 0.12))
      bg:SetPoint("TOPLEFT", u.flow, "TOPLEFT", 0, -(bl.y + 16))
      bg:SetSize(RW, 20)
    end
    local x = 0
    local lx, ly = 0, bl.y + 42
    for _, n in ipairs(bl.nodes) do
      local w = RW * n.pct
      if w > 0 then
        local seg = u.segs:Acquire()
        if seg then
          seg:SetColorTexture(Widgets.color(n.color, 0.9))
          seg:SetPoint("TOPLEFT", u.flow, "TOPLEFT", x, -(bl.y + 16))
          seg:SetSize(max(w, 1), 20)
        end
        nodeHit(u, x, bl.y + 16, max(w, 1), 20, n.tip)
        x = x + w
      end
      local item = u.legend:Acquire()
      if item then
        local color = n.color
        item.swatch:SetColorTexture(Widgets.color(color, 0.9))
        local text = n.label .. " " .. (n.pctText or "")
        set(item.text, text)
        local sw = item.text.GetStringWidth and tonumber(item.text:GetStringWidth()) or #text * 5
        local iw = 8 + 4 + (sw > 0 and sw or #text * 5) + 12
        if lx > 0 and lx + iw > RW then lx, ly = 0, ly + 13 end
        item.swatch:SetPoint("TOPLEFT", u.flow, "TOPLEFT", lx, -(ly + 2))
        item.text:SetPoint("LEFT", item.swatch, "RIGHT", 4, 0)
        lx = lx + iw
      end
    end
  end
end

-- legend on top (holdings): peak (gold) and, if it fits, the biggest leap between two levels
local function holdLegend(u, hold)
  local T = Page.TEXT
  local int = Journal.Texts.int
  local x = 0
  local entries = { { T("holdPeak", hold.maxText, int(hold.maxLevel or hold.to)), "gold" } }
  if hold.jump then
    entries[2] = { T("holdJump", hold.jump.text, int(hold.jump.level)), "sepia" }
  end
  for i, e in ipairs(entries) do
    local item = u.legend:Acquire()
    if item then
      local sw = 0
      item.swatch:SetColorTexture(Widgets.color(e[2], e[2] == "gold" and 1 or 0.55))
      item.swatch:SetPoint("TOPLEFT", u.flow, "TOPLEFT", x, -2)
      item.text:SetPoint("LEFT", item.swatch, "RIGHT", 4, 0)
      item.text:SetTextColor(Widgets.color("ink"))
      set(item.text, e[1])
      sw = item.text.GetStringWidth and tonumber(item.text:GetStringWidth()) or 0
      sw = sw > 0 and sw or #e[1] * 5
      if i > 1 and x + 8 + 4 + sw > RW then -- does not fit: leave the leap out
        item:Hide() -- stays in the pool's used list, ReleaseAll resets it
        break
      end
      x = x + 8 + 4 + sw + 16
    end
  end
end

-- staircase of holdings: one column per level from the zero line up (same scale for all), the highest one in gold.
-- Few levels: wide columns with the amount above; many: narrow and without gaps, the maximum on the axis.
local function drawHold(self, hold)
  local u = self.R
  local cols = hold.cols
  local n = #cols
  local showValues = n <= VALUE_MAX
  local top = PLOT_T + (showValues and VALUE_PAD or 0)
  local bottom = PLOT_B
  local h = bottom - top
  local x0, plotW = AXIS_W, RW - AXIS_W
  local slot = plotW / max(n, 1)
  local barW = floor(min(BAR_MAX, max(BAR_MIN, slot - (n <= 12 and 4 or 1))))
  local sc = hold.max > 0 and h / hold.max or 0

  holdLegend(u, hold)
  flowRect(u, x0, top, plotW, 1, "sepia", 0.18)
  flowLabel(u, hold.maxText, x0 - 6, top - 5, "RIGHT", "sepia", AXIS_W - 6)
  flowRect(u, x0, bottom, plotW, 1, "ink", 0.7)
  flowLabel(u, "0", x0 - 6, bottom - 5, "RIGHT", "sepia", AXIS_W - 6)

  local step = n <= 12 and 1 or (n <= 30 and 5 or 10)
  local lastLabel
  for i, c in ipairs(cols) do
    local cx = x0 + (i - 0.5) * slot
    local bx = floor(cx - barW / 2 + 0.5)
    local bh = c.top > 0 and max(1, floor(c.top * sc + 0.5)) or 0
    if bh > 0 then
      flowRect(u, bx, bottom - bh, barW, bh, c.peak and "gold" or "sepia", c.peak and 1 or 0.5)
      flowRect(u, bx, bottom - bh, barW, 1, "ink", 0.7) -- sharp stair edge
    end
    if showValues and c.top > 0 then
      flowLabel(u, Schaetze.moneyText(c.top, true, false, Schaetze.FONT.label), cx, bottom - bh - 15, "CENTER",
        c.peak and "ink" or "sepia", max(slot, 60))
    end
    local L = c.level
    if step == 1 or (L % step == 0) or (i == n and (not lastLabel or i - lastLabel >= step / 2)) then
      flowLabel(u, Journal.Texts.int(L), cx, PLOT_B + 4, "CENTER", "sepia", 30)
      lastLabel = i
    end
    nodeHit(u, x0 + (i - 1) * slot, PLOT_T - 2, slot, PLOT_B - PLOT_T + 14, c.tip)
  end
end

local function flowItems(withHold)
  local T = Page.TEXT
  local items = { { key = "levels", label = T.toBand }, { key = "bars", label = T.toBars } }
  if withHold then items[3] = { key = "hold", label = T.toHold, tip = { T.holdTip, T.holdTip2 } } end
  return items
end

local function drawFlow(self, view)
  local u = self.R
  local flow = view.flow
  clearFlow(self)
  set(u.flowEmpty, "")
  local T = Page.TEXT
  local int = Journal.Texts.int
  local series = not flow.empty and flow.levels or nil
  local hold = (not flow.empty and not self.holdError) and flow.hold or nil
  local mode = "bars"
  if self.flowMode == "hold" and hold and not self.levelError then
    mode = "hold"
  elseif (self.flowMode == "levels" or self.flowMode == "hold") and series and not self.levelError then
    mode = "levels"
  end
  -- the third entry (holdings) only while there is a series for it
  local withHold = hold ~= nil
  if self.toggleHold ~= withHold then
    self.toggleHold = withHold
    u.toggle:SetItems(flowItems(withHold))
  end
  u.toggle.frame:SetShown((series ~= nil or hold ~= nil) and not self.levelError)
  u.toggle:SetValue(mode)
  if flow.empty then
    set(u.flowEmpty, T.flowEmpty)
    set(u.flowSub, T.flowSub)
    set(u.flowTotal, "")
    return
  end
  if mode == "hold" then
    set(u.flowSub, T.flowHold)
    set(u.flowTotal, hold.from == hold.to and T("level", int(hold.from)) or T("levels", int(hold.from), int(hold.to)))
    local ok, err = pcall(drawHold, self, hold)
    if ok then return end
    -- staircase cannot be drawn: back to the columns per level, the entry disappears
    self.holdError, self.flowMode = err, "levels"
    return drawFlow(self, view)
  end
  if mode == "levels" then
    set(u.flowSub, T.flowLevels)
    set(u.flowTotal, series.from == series.to and T("level", int(series.from))
      or T("levels", int(series.from), int(series.to)))
    local ok, err = pcall(drawLevels, self, series)
    if ok then return end
    -- columns cannot be drawn: fall back to the bars per source permanently
    self.levelError, self.flowMode = err, "bars"
    clearFlow(self)
    u.toggle.frame:Hide()
  end
  set(u.flowSub, T.flowSub)
  set(u.flowTotal, T("total", flow.totalText))
  drawBars(self, flow)
end

function Page.SetFlow(self, mode)
  if not self.view or (mode ~= "levels" and mode ~= "bars" and mode ~= "hold") then return end
  self.flowMode = mode
  drawFlow(self, self.view)
end

function Page.ToggleFlow(self)
  Page.SetFlow(self, self.flowMode == "levels" and "bars" or "levels")
end

function Page:DrawGear(view)
  local u = self.R
  u.runs:ReleaseAll()
  u.dashes:ReleaseAll()
  u.runHits:ReleaseAll()
  local gear = view.gear
  local cell = STRIP_W / (u.gearTop or Schaetze.maxLevel()) -- same scale as the ticks built with the page
  local empty = not gear or gear.empty
  for _, list in ipairs({ u.slotLbl, u.track, u.ticks, u.tickLabels }) do
    for _, e in ipairs(list) do e:SetShown(not empty) end
  end
  if empty then
    set(u.gearSub, "")
    set(u.gearEmpty, Page.TEXT("gearEmptyHand", Journal.Texts.int(u.gearTop or Schaetze.maxLevel())))
    return
  end
  set(u.gearEmpty, "")
  set(u.gearSub, Page.TEXT("gearSub", gear.changesText, Journal.Texts.int(gear.level)))
  for i, row in ipairs(gear.rows) do
    local y = GEAR_Y + (i - 1) * GEAR_ROW
    for _, run in ipairs(row.runs) do
      local x = STRIP_X + (run.from - 1) * cell
      local w = (run.to - run.from + 1) * cell
      if run.empty or run.unknown then
        -- dashed: short strokes in sepia
        local dx = 0
        while dx < w - 1 do
          local d = u.dashes:Acquire()
          if not d then break end
          d:SetColorTexture(Widgets.color("sepia", run.unknown and 0.25 or 0.5))
          d:SetPoint("TOPLEFT", self.right, "TOPLEFT", x + dx, -(y + 8))
          d:SetSize(min(4, w - 1 - dx), 2)
          dx = dx + 7
        end
      else
        local t = u.runs:Acquire()
        if t then
          t:SetColorTexture(Widgets.color(run.color, 0.92))
          t:SetPoint("TOPLEFT", self.right, "TOPLEFT", x, -(y + 3))
          t:SetSize(max(w - 1, 1), 12)
        end
      end
      local hit = u.runHits:Acquire()
      if hit then
        hit:SetPoint("TOPLEFT", self.right, "TOPLEFT", x, -(y + 1))
        hit:SetSize(max(w, 2), 16)
        hit.tipLines = run.tip
      end
    end
  end
end

local function drawBottom(self, view)
  local u = self.R
  local blue = view.blue
  if blue then
    u.note:SetContent(blue.title, blue.body)
    self.blueTip = blue.item and { blue.title, item = blue.item } or nil
  else
    u.note:SetContent(Page.TEXT.blue, Schaetze.TEXT.noBlue)
    self.blueTip = nil
  end
  -- title "Erstes Seltenes" in the rare quality colour (parchment tone, Fmt.QUALITY; text colour instead of a |c code)
  local fr, fg, fb = Journal.Fmt.qualityRGB(3)
  if u.note.title and u.note.title.SetTextColor then u.note.title:SetTextColor(fr, fg, fb) end
  local q = view.quality
  -- no find yet -> sentence in handwriting instead of four zeros
  local none = not q or (tonumber(q.total) or 0) == 0
  set(u.gemEmpty, none and Page.TEXT.qualityEmpty or "")
  for i, g in ipairs(u.gems) do
    local gem = (not none) and q and q.gems[i]
    if gem then
      if g.shape then g.shape.color(gem.color, 1) end
      g.frame:Show()
      set(g.count, gem.text)
      set(g.name, gem.label)
      local qr, qg, qb = Journal.Fmt.qualityRGB(gem.q) -- quality name in the quality colour (parchment tone)
      if qr and g.name.SetTextColor then g.name:SetTextColor(qr, qg, qb) end
    else
      g.frame:Hide()
      set(g.count, "")
      set(g.name, "")
    end
  end
  set(u.grey, q and q.greyText or "")
end

function Page:Refresh(data)
  if not self.built then return end
  self.data = data -- head line of the finds list (Widgets.playerLine)
  local view = Schaetze.evaluate(data.index, { live = data.live, now = data.now })
  if not view then error("Schaetze: keine Auswertung") end
  self.view = view
  self.index = data.index
  self.R.head:SetTexts(Widgets.playerLine(data) or view.head, Page.TEXT.page)
  drawLeft(self, view)
  drawFlow(self, view)
  self:DrawGear(view)
  drawBottom(self, view)
  if self.fundeOpen and self.funde then self.funde:Refresh(data.index) end
end

function Page:OnHide()
  local L, R = self.L, self.R
  if L then for _, r in ipairs(L.rows) do Widgets.hideTip(r.hit) end end
  if R then
    for _, pool in ipairs({ R.hits, R.runHits }) do
      for _, h in ipairs(pool.used) do Widgets.hideTip(h) end
    end
    if R.note then Widgets.hideTip(R.note.frame) end
    if R.fundeHit then Widgets.hideTip(R.fundeHit) end
  end
  -- the next open starts with the overview again (filter and sort of the finds stay)
  if self.fundeOpen then Page.CloseFunde(self) end
end

Pages.register("schaetze", Page)
