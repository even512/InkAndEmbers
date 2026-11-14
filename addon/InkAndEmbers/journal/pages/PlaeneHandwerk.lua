-- Sub-view "Handwerk" of the tab Pläne (pages/Plaene.lua; WoW Forever only): which profession recipes you can learn next.
-- Left: filter (trainer · now · soon), page arrows and the recipe list (icon, name, profession, source, price, state).
-- Right: how many recipes the trainer teaches now with the total price against the gold in the bag, one line per profession
-- (skill, now, soon) and the to-do "Zum Berufslehrer".
-- Data: journal/model/Rezepte.lua (display-ready). Grid (docs/raster.md): left list ends before y 474 (blot bottom left),
-- right everything stays left of x 446 and above y 578 (keep-outs DecorKeepout quests). No ticker, no OnUpdate; rows pooled.
local _, ns = ...

local Journal = ns.Journal
local W, Pages, RZ = Journal and Journal.Widgets, Journal and Journal.Pages, Journal and Journal.Rezepte
local D = W and W.Diary
if not (W and Pages and RZ and D) then return end

local floor = math.floor
local Theme = Journal.Theme
local G = Theme.GRID

local View = {}
View.__index = View
Journal.RezepteView = View

-- texts (German here, English in locales/enUS_pages.lua, scope "p.PlaeneHandwerk"; read only on build/draw)
local T = ns.Locale.ns("p.PlaeneHandwerk", {
  brand = "INK & EMBERS", page = "HANDWERK",
  fTrainer = "Lehrer", fNow = "Jetzt", fSoon = "Bald",
  fTrainerTip = { "Lehrer", "Was Euch ein Berufslehrer jetzt beibringt" },
  fNowTip = { "Jetzt", "Alles, was Ihr auf Eurer Fertigkeit lernen könnt – auch von Händlern, aus Quests und Beute" },
  fSoonTip = { "Bald", "Was in den nächsten 25 Fertigkeitspunkten dazukommt" },
  info = "Berufe: %s · %s jetzt · %s bald",
  skillWord = "Fertigkeit %s",
  free = "ohne Kosten",
  sNow = "jetzt", sSoon = "in %s Punkten", sLevel = "ab Stufe %s", sLater = "ab Fertigkeit %s", sLearned = "gelernt",
  learnable = "beim Lehrer lernbar",
  costLine = "Lehrgeld %s · im Beutel %s",
  costNone = "Im Moment gibt es beim Berufslehrer nichts Neues.",
  short = "Euch fehlen noch %s.", enough = "Der Beutel reicht für alles.",
  profHead = "Eure Berufe",
  profLine = "%s %s/%s · %s jetzt · %s bald",
  profLineNoMax = "%s %s · %s jetzt · %s bald",
  todoOn = "Das To Do \"Zum Berufslehrer\" steht auf Eurer Liste.",
  todoOff = "Sobald ein Lehrer etwas Neues für Euch hat, trägt Ink \"Zum Berufslehrer\" als To Do ein.",
  retailHead = "Nur in WoW Forever",
  retailBody = "Die Rezeptdaten gelten für WoW Forever. In Retail bleibt dieses Blatt leer.",
  noDataHead = "Keine Rezeptdaten",
  noProfHead = "Noch kein Beruf",
  noProfBody = "Lernt einen Beruf. Dann zeigt dieses Blatt, welche Rezepte als Nächstes anstehen.",
  noProfDataHead = "Keine Rezepte für Eure Berufe",
  noProfDataBody = "Für Eure Berufe liegen keine Rezeptdaten vor.",
  noApiBody = "Eure Berufe sind gerade nicht lesbar. Versucht es gleich noch einmal.",
  emptyTrainer = "Beim Berufslehrer wartet gerade nichts Neues. Mit mehr Fertigkeit gibt es neue Rezepte.",
  emptyNow = "Gerade ist nichts lernbar.",
  emptySoon = "In den nächsten 25 Punkten kommt nichts Neues.",
  prevPage = "Vorige Seite", nextPage = "Nächste Seite",
  tipSource = "Quelle: %s", tipCost = "Preis: %s", tipLevel = "Stufe %s nötig", tipRank = "Berufsstufe: %s",
  tipFavor = "Händlergunst: %s", tipNeed = "Noch %s Fertigkeitspunkte",
})
View.TEXT = T

local LX, LW = Theme.gridX("L")
local RX, RW = Theme.gridX("R")
local CTRL_CY = G.slots.ctrlTop.y + 26
local INFO_Y = CTRL_CY + 18
local ROWS_Y = INFO_Y + 22
local LEFT_END = 474
local ROW_H = 34
local ROWS_N = floor((LEFT_END - ROWS_Y) / ROW_H)
local TITLE_Y = G.slots.title.y
local R_COST_Y = TITLE_Y + 42
local R_SHORT_Y = R_COST_Y + 18
local R_PROF_Y = R_SHORT_Y + 26
local PROF_LINES = RZ.MAX_PROFESSIONS
local R_NOTE_Y = R_PROF_Y + 34 + PROF_LINES * G.line.text + 14
local ICON = 18
View.ROWS_N = ROWS_N
View.LAYOUT = { rowsY = ROWS_Y, rowH = ROW_H, leftEnd = LEFT_END, profY = R_PROF_Y, noteY = R_NOTE_Y }

local FILTER_TEXT = { trainer = "fTrainer", now = "fNow", soon = "fSoon" }
local EMPTY_TEXT = { trainer = "emptyTrainer", now = "emptyNow", soon = "emptySoon" }

local function int(n) return Journal.Texts.int(n) end
local function money(c) return Journal.Texts.money(c, "short") end
local function kit() return Journal.QuestsPage and Journal.QuestsPage.kit end

local function label(parent, kind, size, color, justify)
  local fs = W.font(parent, kind, size, color)
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

-- name of a row ("Schmiedekunst: Geselle" for a rank step, else the recipe name)
local function rowName(r)
  local rank = RZ.rankText(r)
  if rank then return r.prof .. ": " .. rank end
  return r.name or tostring(r.id)
end

-- price / Merchant's Favor / reputation of a row (short, for the list)
local function costText(r)
  if r.cost and r.cost > 0 then return money(r.cost) end
  if r.favor then return RZ.TEXT("favor", int(r.favor)) end
  if r.rep and #r.rep > 0 then return RZ.repText(r) end
  if r.trainer then return T.free end
  return nil
end

local function subText(r)
  local parts = { r.prof }
  local src = RZ.sourceText(r)
  if src ~= "" then parts[#parts + 1] = src end
  local c = costText(r)
  if c then parts[#parts + 1] = c end
  return table.concat(parts, " · ")
end

local function stateText(r)
  local s = r.state
  if s == "now" then return T.sNow end
  if s == "learned" then return T.sLearned end
  if s == "soon" then
    if r.levelShort and r.minLevel then return T("sLevel", int(r.minLevel)) end
    return T("sSoon", int(r.need or 0))
  end
  return T("sLater", int(r.skill))
end
View.stateText = stateText

local function rowTip(r)
  local tip = { rowName(r), r.prof, T("skillWord", int(r.skill)) }
  tip[#tip + 1] = T("tipSource", RZ.sourceText(r))
  if r.cost and r.cost > 0 then tip[#tip + 1] = T("tipCost", money(r.cost)) end
  if r.favor then tip[#tip + 1] = T("tipFavor", int(r.favor)) end
  local rep = RZ.repText(r)
  if rep then tip[#tip + 1] = rep end
  if r.minLevel and r.minLevel > 0 then tip[#tip + 1] = T("tipLevel", int(r.minLevel)) end
  if r.state == "soon" and (r.need or 0) > 0 then tip[#tip + 1] = T("tipNeed", int(r.need)) end
  tip[#tip + 1] = stateText(r)
  return tip
end
View.rowTip = rowTip

local function buildRows(self, tab)
  local ui = self.ui
  local nameW = LW - (ICON + 10) - 96
  ui.rowsList = W.NewList(tab, { rows = ROWS_N, rowHeight = ROW_H, width = LW + 10, step = 3, empty = T.emptyTrainer, emptyHand = true,
    build = function(row)
      row.icon = row:CreateTexture(nil, "ARTWORK")
      row.icon:SetSize(ICON, ICON)
      row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)
      row.label:ClearAllPoints()
      row.label:SetPoint("TOPLEFT", row, "TOPLEFT", ICON + 10, -3)
      row.label:SetWidth(nameW)
      row.label:SetWordWrap(false)
      row.lvl = label(row, "label", G.size.s, "sepia", "RIGHT")
      row.lvl:SetWidth(92)
      row.lvl:SetPoint("TOPRIGHT", row, "TOPLEFT", LW - 4, -4)
      row.sub = label(row, "label", G.size.xs, "sepia")
      row.sub:SetWordWrap(false)
      row.sub:SetWidth(LW - (ICON + 14) - 100)
      row.sub:SetPoint("TOPLEFT", row, "TOPLEFT", ICON + 10, -19)
      row.tag = label(row, "label", G.size.xs, "sepia", "RIGHT")
      row.tag:SetWidth(96)
      row.tag:SetWordWrap(false)
      row.tag:SetPoint("TOPRIGHT", row, "TOPLEFT", LW - 4, -19)
      D.RowStyle(row, { texts = { row.label, row.lvl } })
      row:HookScript("OnEnter", function(r) if r.tipLines then W.tip(r, r.tipLines) end end)
      row:HookScript("OnLeave", function(r) W.hideTip(r) end)
    end,
    clear = function(row)
      row:SetSelected(false)
      row.lvl:SetText("")
      row.sub:SetText("")
      row.tag:SetText("")
      row.icon:Hide()
      row.tipLines = nil
      row.label:SetTextColor(W.color("ink"))
    end,
    fill = function(row, r)
      W.setText(row.label, rowName(r))
      row.lvl:SetText(T("skillWord", int(r.skill)))
      local dim = r.state ~= "now"
      row.label:SetTextColor(W.color(dim and "sepia" or "ink", dim and 0.8 or 1))
      W.setText(row.sub, subText(r))
      W.setText(row.tag, stateText(r))
      row.tag:SetTextColor(W.color(r.state == "now" and "ink" or "sepia"))
      if r.icon then
        row.icon:SetTexture(r.icon)
        row.icon:SetDesaturated(dim and true or false)
        row.icon:SetAlpha(dim and 0.7 or 1)
        row.icon:Show()
      end
      row.tipLines = rowTip(r)
      D.rowFilled(row)
    end })
  ui.rowsList.frame:ClearAllPoints()
  ui.rowsList.frame:SetPoint("TOPLEFT", tab, "TOPLEFT", LX, -ROWS_Y)
  local K = kit()
  if K and K.pager then ui.pager = K.pager(tab, ui.rowsList, LX, LW, CTRL_CY, { T.prevPage, T.nextPage }) end
end

local function buildLeft(self, tab)
  local ui = self.ui
  ui.headL = W.NewPageHead(tab, { side = "L" })
  ui.headL:SetTexts(T.brand, T.page)
  local items = {}
  for _, key in ipairs(RZ.FILTERS) do
    local k = FILTER_TEXT[key]
    items[#items + 1] = { key = key, label = T[k], tip = T[k .. "Tip"] }
  end
  ui.filter = D.NewToggle(tab, { items = items, size = 13, gap = 12, onChange = function(key) self:SetFilter(key) end })
  ui.filter.frame:SetPoint("LEFT", tab, "TOPLEFT", LX, -CTRL_CY)
  ui.info = label(tab, "label", G.size.xs, "sepia")
  ui.info:SetWidth(LW)
  ui.info:SetWordWrap(false)
  ui.info:SetPoint("TOPLEFT", tab, "TOPLEFT", LX, -INFO_Y)
  buildRows(self, tab)
  ui.emptyHead = label(tab, "title", G.size.l, "ink", "CENTER")
  ui.emptyHead:SetWidth(LW)
  ui.emptyHead:SetPoint("TOP", tab, "TOPLEFT", LX + LW / 2, -230)
  ui.emptyBody = D.emptyNote(tab, LW - 60)
  ui.emptyBody:SetPoint("TOP", tab, "TOPLEFT", LX + LW / 2, -270)
end

local function section(tabR, y, text)
  local h = D.NewSectionHead(tabR, text, { size = 20, width = RW - 60 })
  h:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX, -y)
  return h
end

local function buildRight(self, tabR)
  local ui = self.ui
  ui.headR = W.NewPageHead(tabR, { side = "R" })
  ui.headR:SetTexts("", T.page)
  ui.num = label(tabR, "title", G.size.xl, "ink")
  ui.num:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX, -TITLE_Y)
  ui.numLbl = label(tabR, "label", G.size.s, "sepia")
  ui.numLbl:SetPoint("BOTTOMLEFT", ui.num, "BOTTOMRIGHT", 8, 5)
  ui.numLbl:SetWordWrap(false)
  ui.costLine = label(tabR, "label", G.size.s, "ink")
  ui.costLine:SetWidth(RW)
  ui.costLine:SetWordWrap(false)
  ui.costLine:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX, -R_COST_Y)
  ui.shortLine = label(tabR, "label", G.size.xs, "sepia")
  ui.shortLine:SetWidth(RW)
  ui.shortLine:SetWordWrap(false)
  ui.shortLine:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX, -R_SHORT_Y)
  ui.profHead = section(tabR, R_PROF_Y, T.profHead)
  ui.profLines = {}
  for i = 1, PROF_LINES do
    local fs = label(tabR, "text", G.size.s, "ink")
    fs:SetWidth(RW)
    fs:SetWordWrap(false)
    fs:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX + 4, -(R_PROF_Y + 34 + (i - 1) * G.line.text))
    ui.profLines[i] = fs
  end
  ui.todoLine = label(tabR, "label", G.size.xs, "sepia")
  ui.todoLine:SetWidth(RW - 8)
  ui.todoLine:SetWordWrap(true)
  ui.todoLine:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX + 4, -(R_NOTE_Y + 4))
  ui.emptyRight = D.emptyNote(tabR, RW - 60)
  ui.emptyRight:SetPoint("TOP", tabR, "TOPLEFT", RX + RW / 2, -290)
  ui.rightParts = { ui.num, ui.numLbl, ui.costLine, ui.shortLine, ui.profHead, ui.todoLine }
  for _, fs in ipairs(ui.profLines) do ui.rightParts[#ui.rightParts + 1] = fs end
end

function View.new(page, left, right)
  local self = setmetatable({ page = page, ui = {} }, View)
  local ui = self.ui
  local tab = CreateFrame("Frame", nil, left)
  tab:SetAllPoints(left)
  tab:SetFrameLevel(left:GetFrameLevel() + 12)
  ui.table = tab
  local tabR = CreateFrame("Frame", nil, right)
  tabR:SetAllPoints(right)
  ui.tableR = tabR
  buildLeft(self, tab)
  buildRight(self, tabR)
  D.escKeys(tab, function() Pages.escape(page.id or "plaene") end) -- Esc -> "To Do", the first sub-bookmark of Pläne
  tab:Hide()
  tabR:Hide()
  return self
end

function View:IsOpen() return self.open == true end

function View:Filter()
  local f = Pages.setting("craftFilter")
  return FILTER_TEXT[f] and f or "trainer"
end

function View:SetFilter(key)
  if not FILTER_TEXT[key] then return false end
  Pages.setSetting("craftFilter", key)
  self.ui.rowsList:SetOffset(0)
  self:Render()
  return true
end

-- the empty page: head and body by reason
local function emptyTexts(view)
  local r = view.reason
  if r == "RETAIL" then return T.retailHead, T.retailBody end
  if r == "NOPROF" then return T.noProfHead, T.noProfBody end
  if r == "NOPROFDATA" then return T.noProfDataHead, T.noProfDataBody end
  if r == "NOAPI" then return T.noProfHead, T.noApiBody end
  return T.noDataHead, RZ.reasonText()
end

function View:Render()
  local ui = self.ui
  if not self.open then return end
  local view = RZ.evaluate()
  self.view = view
  local ok = view.available
  ui.emptyHead:SetShown(not ok)
  ui.emptyBody:SetShown(not ok)
  ui.emptyRight:SetShown(not ok)
  ui.rowsList.frame:SetShown(ok)
  ui.filter.frame:SetShown(ok)
  ui.info:SetShown(ok)
  if ui.pager then
    ui.pager.pair.frame:SetShown(ok)
    ui.pager.label:SetShown(ok)
  end
  for _, f in ipairs(ui.rightParts) do f:SetShown(ok) end
  local player = Journal.Widgets.playerLine and Journal.Widgets.playerLine(self.page and self.page.data) or ""
  ui.headR:SetTexts(player or "", T.page)
  if not ok then
    local head, body = emptyTexts(view)
    W.setText(ui.emptyHead, head)
    W.setText(ui.emptyBody, body)
    W.setText(ui.emptyRight, body)
    return
  end
  local filter = self:Filter()
  ui.filter:SetValue(filter)
  local rows = RZ.rows(view, filter)
  self.items = rows
  ui.rowsList.opts.empty = T[EMPTY_TEXT[filter]]
  ui.rowsList:SetItems(rows)
  ui.rowsList:Refresh()
  W.setText(ui.info, T("info", int(#view.profs), int(view.now.n), int(view.soon.n)))
  -- right: trainer count / price / bag
  ui.num:SetText(int(view.trainer.n))
  W.setText(ui.numLbl, T.learnable)
  if view.trainer.n > 0 then
    W.setText(ui.costLine, T("costLine", money(view.trainer.cost), view.money and money(view.money) or "?"))
    local short = view.short or 0
    W.setText(ui.shortLine, short > 0 and T("short", money(short)) or T.enough)
    ui.shortLine:SetTextColor(W.color(short > 0 and "red" or "sepia"))
  else
    W.setText(ui.costLine, T.costNone)
    W.setText(ui.shortLine, "")
  end
  for i, fs in ipairs(ui.profLines) do
    local pr = view.profs[i]
    if pr then
      if pr.max then
        W.setText(fs, T("profLine", pr.name, int(pr.rank), int(pr.max), int(pr.now), int(pr.soon)))
      else
        W.setText(fs, T("profLineNoMax", pr.name, int(pr.rank), int(pr.now), int(pr.soon)))
      end
    else
      W.setText(fs, "")
    end
  end
  local P = ns.Plans
  local open = P and type(P.findAuto) == "function" and ns.CraftTodo and P.findAuto(ns.CraftTodo.TAG)
  W.setText(ui.todoLine, open and T.todoOn or T.todoOff)
end

function View:Open()
  self.open = true
  self.ui.table:Show()
  self.ui.tableR:Show()
  self:Render()
end

function View:Refresh()
  if self.open then self:Render() end
end

function View:Close()
  local ui = self.ui
  self.open = false
  for _, r in ipairs(ui.rowsList.rows) do W.hideTip(r) end
  ui.table:Hide()
  ui.tableR:Hide()
end
