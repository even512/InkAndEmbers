-- Sub-view "Lehrplan" of the tab Pläne (pages/Plaene.lua; until I12 under Quests; WoW Forever only): the class trainer plan.
-- Left: filter (now · upcoming · learned · all), page arrows and the spell list (icon, name and rank, level, cost, state).
-- Right: what is learnable now with the total cost against the gold in the bag, the next levels, the nearest known trainer
-- (from own visits; "Als To Do" places a to-do at them), free talent points and the training fees paid so far.
-- The same view class also draws the sub-view "Tierausbildung" (View.new(..., "pets"), Journal.TierView; hunters only, or the
-- development preview /chronik sim jaeger): same layout and filters, rows = pet abilities (Lehrplan.evaluate().pets), state of the
-- last pet trainer visit; the right side shows the learnable count, cost, next levels and a note instead of trainer, talents, fees.
-- Data: journal/model/Lehrplan.lua (display-ready). Grid (docs/raster.md): left list ends before y 474 (blot bottom left),
-- right everything stays left of x 446 and above y 578 (keep-outs DecorKeepout quests). No ticker, no OnUpdate; rows pooled.
local _, ns = ...

local Journal = ns.Journal
local W, Pages, LP = Journal and Journal.Widgets, Journal and Journal.Pages, Journal and Journal.Lehrplan
local D = W and W.Diary
if not (W and Pages and LP and D) then return end

local floor, max, min = math.floor, math.max, math.min
local Theme = Journal.Theme
local G = Theme.GRID

local View = {}
View.__index = View
Journal.LehrplanView = View

-- texts (German here, English in locales/enUS_pages.lua, scope "p.QuestsLehrplan"; read only on build/draw)
local T = ns.Locale.ns("p.QuestsLehrplan", {
  brand = "INK & EMBERS", page = "LEHRPLAN",
  fNow = "Jetzt", fNext = "Kommend", fLearned = "Gelernt", fAll = "Alle",
  fNowTip = { "Jetzt", "Was Ihr auf Eurer Stufe beim Lehrer lernen könnt" },
  fNextTip = { "Kommend", "Was die nächsten Stufen bringen" },
  fLearnedTip = { "Gelernt", "Was Ihr schon gelernt habt" },
  fAllTip = { "Alle", "Der ganze Lehrplan Eurer Klasse" },
  info = "Stufe %s · %s gelernt · %s offen",
  levelWord = "Stufe %s", cost = "%s",
  sNow = "jetzt lernbar", sMissing = "erst Vorgängerrang", sTalent = "Talent nötig", sLater = "ab Stufe %s",
  sLearned = "gelernt", sQuest = "aus Klassenquest", sUnoffered = "Lehrer bot es nicht an",
  free = "ohne Kosten",
  petPage = "TIERAUSBILDUNG", petPreview = "(Vorschau)", petSample = "Vorschau mit Beispielstand, nicht Euer Charakter", sUnknown = "unbekannt",
  petFNowTip = { "Jetzt", "Was Euer Tier auf Eurer Stufe beim Tierausbilder lernen kann" },
  petFNextTip = { "Kommend", "Was die nächsten Stufen bringen" },
  petFLearnedTip = { "Gelernt", "Was Euer Tier schon gelernt hat" },
  petFAllTip = { "Alle", "Alle Tierfähigkeiten und Ränge" },
  petNoteHead = "Tierausbilder",
  petHow = "Einmal beim Tierausbilder kaufen, dann jedem Tier über \"%s\" beibringen.",
  petAbility = "Tierausbildung",
  petTaming = "Fähigkeiten wie Klaue oder Biss lernt Ihr durch Zähmen, nicht hier.",
  petNoneHead = "Keine Tierausbildung", petNoneBody = "Die Tierausbildung gibt es nur für Jäger.",
  petEmptyNow = "Gerade gibt es nichts zu lernen. Besucht den Tierausbilder, damit Ink den Stand kennt.",
  petEmptyNext = "Nichts mehr in Sicht.", petEmptyLearned = "Noch nichts gelernt oder noch nicht gesehen. Besucht den Tierausbilder.",
  petCostNone = "Im Moment gibt es beim Tierausbilder nichts Neues.",
  petSeen = "Stand vom letzten Besuch beim Tierausbilder", petUnseen = "Noch nicht beim Tierausbilder gewesen",
  petTip = "Tipp: Im Fenster des Tierausbilders oben im Filter \"%s\" anhaken, dann sieht Ink auch schon Gelerntes.",
  unknownTip = "Dieser Rang wurde beim Tierausbilder noch nicht gesehen. Ink rät nicht.",
  needs = "Voraussetzung: %s", needsTalent = "Talent: %s", questTip = "Belohnung einer Klassenquest, nicht beim Lehrer",
  unofferedTip = "Beim letzten Besuch auf dieser Stufe stand der Zauber nicht in der Liste des Lehrers.",
  learnable = "jetzt lernbar",
  costLine = "Lehrgeld %s · im Beutel %s",
  costNone = "Im Moment gibt es beim Lehrer nichts Neues.",
  short = "Euch fehlen noch %s.", enough = "Der Beutel reicht für alles.",
  nextHead = "Die nächsten Stufen", nextNone = "Danach ist der Lehrplan erfüllt.",
  nextLine_one = "Stufe %s · %s Zauber · %s", nextLine_other = "Stufe %s · %s Zauber · %s",
  trainerHead = "Nächster Lehrer",
  trainerNone = "Noch kein Lehrer bekannt. Besucht Euren Klassenlehrer einmal, dann steht er hier.",
  trainerFar = "%s · weit weg", trainerDist = "%s · %s", farOnly = "weit weg",
  meters = "%s m", km = "%s km",
  toTodo = "Als To Do", toTodoTip = { "Als To Do", "Legt ein Ort-Ziel beim Lehrer an (Pläne -> To Do)." },
  todoDone = "To Do angelegt.", todoFail = "Kein To Do angelegt.",
  talentHead = "Talente",
  talentFree_one = "%s Talentpunkt ist frei.", talentFree_other = "%s Talentpunkte sind frei.",
  talentNone = "Alle Talentpunkte sind verteilt.", talentEarly = "Talentpunkte bekommt Ihr erst später auf Eurer Reise.", talentUnknown = "Talentpunkte nicht lesbar.",
  fees = "Bisher gezahltes Lehrgeld: %s",
  retailHead = "Nur in WoW Forever",
  retailBody = "In Retail lernt Ihr Klassenzauber von selbst – einen Lehrplan braucht es dort nicht.",
  noDataHead = "Kein Lehrplan",
  noDataBody = "Für diese Klasse gibt es keine Lehrplan-Daten.",
  emptyNow = "Gerade gibt es nichts zu lernen. Mit der nächsten Stufe könnt Ihr wieder zum Lehrer.", emptyNext = "Nichts mehr in Sicht.", emptyLearned = "Noch nichts gelernt. Besucht Euren Klassenlehrer.",
  prevPage = "Vorige Seite", nextPage = "Nächste Seite",
})
View.TEXT = T

local LX, LW = Theme.gridX("L")
local RX, RW = Theme.gridX("R")
local CTRL_CY = G.slots.ctrlTop.y + 26     -- filter and paging; the circled filter stays below the wax drop (keep-out to y 72)
local INFO_Y = CTRL_CY + 18
local ROWS_Y = INFO_Y + 22
local LEFT_END = 474                      -- blot bottom left (keep-out y 478..601) stays free
local ROW_H = 34
local ROWS_N = floor((LEFT_END - ROWS_Y) / ROW_H)
local TITLE_Y = G.slots.title.y
local R_COST_Y = TITLE_Y + 42
local R_SHORT_Y = R_COST_Y + 18
local R_NEXT_Y = R_SHORT_Y + 26
local R_TRAINER_Y = R_NEXT_Y + 30 + 4 * G.line.text + 12
local R_TALENT_Y = R_TRAINER_Y + 30 + 92
local ICON = 18
View.ROWS_N = ROWS_N
View.LAYOUT = { rowsY = ROWS_Y, rowH = ROW_H, leftEnd = LEFT_END, nextY = R_NEXT_Y, trainerY = R_TRAINER_Y, talentY = R_TALENT_Y }

local FILTER_TEXT = { now = "fNow", next = "fNext", learned = "fLearned", all = "fAll" }
local EMPTY_TEXT = { now = "emptyNow", next = "emptyNext", learned = "emptyLearned", all = "emptyNow" }
local PET_EMPTY_TEXT = { now = "petEmptyNow", next = "petEmptyNext", learned = "petEmptyLearned", all = "petEmptyNow" }

local function int(n) return Journal.Texts.int(n) end
local function money(c) return Journal.Texts.money(c, "short") end
local function kit() return Journal.QuestsPage and Journal.QuestsPage.kit end

local function label(parent, kind, size, color, justify)
  local fs = W.font(parent, kind, size, color)
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

local function pluralKey(n, one, other)
  local LC = ns.Locale
  return LC and LC.plural and LC.plural(n, one, other) or (n == 1 and one or other)
end

local function plural(n, one, other)
  return T(pluralKey(n, one, other), int(n))
end

-- name of the trainer window filter that shows learned rows (client text, fallback "Used")
function View.petFilterName()
  local v = rawget(_G, "TRAINER_FILTER_USED")
  if type(v) == "string" and not (type(issecretvalue) == "function" and issecretvalue(v) == true) and v ~= "" then
    return ns.Sanitize.field(v)
  end
  return "Used"
end

function View.petTip() return T("petTip", View.petFilterName()) end

-- name of the hunter ability that teaches a pet (Beast Training, spell 5149) in the client language; fallback: our own text
function View.petAbilityName()
  local name
  local CS = rawget(_G, "C_Spell")
  if type(CS) == "table" and type(CS.GetSpellName) == "function" then
    local ok, v = pcall(CS.GetSpellName, 5149)
    if ok then name = v end
  end
  if name == nil and type(rawget(_G, "GetSpellInfo")) == "function" then
    local ok, v = pcall(GetSpellInfo, 5149)
    if ok then name = v end
  end
  if type(name) == "string" and name ~= "" and not (type(issecretvalue) == "function" and issecretvalue(name) == true) then
    return ns.Sanitize.field(name)
  end
  return T.petAbility
end

-- how it works in Forever: buy once from the trainer, teach every pet with the ability; family abilities come from taming
function View.petHowText() return T("petHow", View.petAbilityName()) .. "\n\n" .. T.petTaming end

-- state text of a row
function View.stateText(r)
  local s = r.state
  if s == "now" then return r.offered == false and T.sUnoffered or T.sNow end
  if s == "missing" then return T.sMissing end
  if s == "talent" then return T.sTalent end
  if s == "later" then return T("sLater", int(r.level)) end
  if s == "learned" then return T.sLearned end
  if s == "quest" then return T.sQuest end
  if s == "unknown" then return T.sUnknown end
  return ""
end

local function spellName(id)
  local info = LP.spellInfo(id)
  return info and info.name or tostring(id)
end

local function rowName(r)
  local n = r.name or spellName(r.id)
  if r.rank then return n .. " (" .. r.rank .. ")" end
  return n
end

local function rowTip(r)
  local tip = { rowName(r), T("levelWord", int(r.level)) }
  if r.state ~= "quest" then tip[#tip + 1] = r.cost > 0 and money(r.cost) or T.free end
  for _, id in ipairs(r.req or {}) do tip[#tip + 1] = T("needs", spellName(id)) end
  if r.talent then tip[#tip + 1] = T("needsTalent", spellName(r.talent)) end
  if r.state == "quest" then tip[#tip + 1] = T.questTip end
  if r.state == "now" and r.offered == false then tip[#tip + 1] = T.unofferedTip end
  tip[#tip + 1] = View.stateText(r)
  if r.state == "unknown" then
    tip[#tip + 1] = T.unknownTip
    tip[#tip + 1] = View.petTip()
  end
  return tip
end
View.rowTip = rowTip

local function buildRows(self, tab)
  local ui = self.ui
  local nameW = LW - (ICON + 10) - 74
  ui.rowsList = W.NewList(tab, { rows = ROWS_N, rowHeight = ROW_H, width = LW + 10, step = 3, empty = T.emptyNow, emptyHand = true,
    build = function(row)
      row.icon = row:CreateTexture(nil, "ARTWORK")
      row.icon:SetSize(ICON, ICON)
      row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)
      row.label:ClearAllPoints()
      row.label:SetPoint("TOPLEFT", row, "TOPLEFT", ICON + 10, -3)
      row.label:SetWidth(nameW)
      row.label:SetWordWrap(false)
      row.lvl = label(row, "label", G.size.s, "sepia", "RIGHT")
      row.lvl:SetWidth(70)
      row.lvl:SetPoint("TOPRIGHT", row, "TOPLEFT", LW - 4, -4)
      row.sub = label(row, "label", G.size.xs, "sepia")
      row.sub:SetWordWrap(false)
      row.sub:SetWidth(LW - (ICON + 14) - 150)
      row.sub:SetPoint("TOPLEFT", row, "TOPLEFT", ICON + 10, -19)
      row.tag = label(row, "label", G.size.xs, "sepia", "RIGHT")
      row.tag:SetWidth(146)
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
      row.lvl:SetText(T("levelWord", int(r.level)))
      local dim = r.state == "learned" or r.state == "later"
      row.label:SetTextColor(W.color(dim and "sepia" or "ink", dim and 0.8 or 1))
      W.setText(row.sub, r.state == "quest" and "" or (r.cost > 0 and money(r.cost) or T.free))
      local warn = r.state == "missing" or r.state == "talent" or (r.state == "now" and r.offered == false)
      W.setText(row.tag, View.stateText(r))
      row.tag:SetTextColor(W.color(warn and "red" or "sepia", warn and 0.9 or 1))
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
  ui.headL:SetTexts(T.brand, self.pets and T.petPage or T.page)
  local items = {}
  for _, key in ipairs(LP.FILTERS) do
    local k = FILTER_TEXT[key]
    items[#items + 1] = { key = key, label = T[k], tip = T[self.pets and ("pet" .. k:gsub("^f", "F") .. "Tip") or (k .. "Tip")] }
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

local function section(self, tabR, y, text)
  local h = D.NewSectionHead(tabR, text, { size = 20, width = RW - 60 })
  h:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX, -y)
  return h
end

local function buildRight(self, tabR)
  local ui = self.ui
  ui.headR = W.NewPageHead(tabR, { side = "R" })
  ui.headR:SetTexts("", self.pets and T.petPage or T.page)
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
  ui.nextHead = section(self, tabR, R_NEXT_Y, T.nextHead)
  ui.nextLines = {}
  for i = 1, LP.NEXT_LEVELS do
    local fs = label(tabR, "text", G.size.s, "ink")
    fs:SetWidth(RW)
    fs:SetWordWrap(false)
    fs:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX + 4, -(R_NEXT_Y + 34 + (i - 1) * G.line.text))
    ui.nextLines[i] = fs
  end
  ui.trainerHead = section(self, tabR, R_TRAINER_Y, self.pets and T.petNoteHead or T.trainerHead)
  ui.trainerName = label(tabR, "title", G.size.m, "ink")
  ui.trainerName:SetWidth(RW)
  ui.trainerName:SetWordWrap(false)
  ui.trainerName:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX + 4, -(R_TRAINER_Y + 36))
  ui.trainerSub = label(tabR, "label", G.size.xs, "sepia")
  ui.trainerSub:SetWidth(RW - 8)
  ui.trainerSub:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX + 4, -(R_TRAINER_Y + 56))
  ui.todo = D.NewSticker(tabR, T.toTodo, function() self:AddTodo() end, { tip = T.toTodoTip, height = 30 })
  ui.todo:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX, -(R_TRAINER_Y + 74))
  ui.todoMsg = label(tabR, "label", G.size.xs, "sepia")
  ui.todoMsg:SetWidth(RW - 150)
  ui.todoMsg:SetWordWrap(false)
  ui.todoMsg:SetPoint("LEFT", ui.todo, "RIGHT", 14, 0)
  ui.talentHead = section(self, tabR, R_TALENT_Y, T.talentHead)
  ui.talentLine = label(tabR, "text", G.size.s, "ink")
  ui.talentLine:SetWidth(RW)
  ui.talentLine:SetWordWrap(false)
  ui.talentLine:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX + 4, -(R_TALENT_Y + 34))
  ui.fees = label(tabR, "label", G.size.xs, "sepia")
  ui.fees:SetWidth(RW)
  ui.fees:SetWordWrap(false)
  ui.fees:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX + 4, -(R_TALENT_Y + 34 + G.line.text + 4))
  ui.emptyRight = D.emptyNote(tabR, RW - 60)
  ui.emptyRight:SetPoint("TOP", tabR, "TOPLEFT", RX + RW / 2, -290)
  ui.rightParts = { ui.num, ui.numLbl, ui.costLine, ui.shortLine, ui.nextHead, ui.trainerHead, ui.trainerName, ui.trainerSub,
    ui.todo, ui.todoMsg, ui.talentHead, ui.talentLine, ui.fees }
  for _, fs in ipairs(ui.nextLines) do ui.rightParts[#ui.rightParts + 1] = fs end
end

function View.new(page, left, right, mode)
  local self = setmetatable({ page = page, ui = {}, pets = mode == "pets" }, View)
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
  local f = Pages.setting("trainFilter")
  return FILTER_TEXT[f] and f or "now"
end

function View:SetFilter(key)
  if not FILTER_TEXT[key] then return false end
  Pages.setSetting("trainFilter", key)
  self.ui.rowsList:SetOffset(0)
  self:Render()
  return true
end

function View:AddTodo()
  local t = self.trainer
  local P = ns.Plans
  self.todoText = nil
  if not (t and P and type(P.add) == "function") then
    self.todoText = T.todoFail
  else
    local id = P.add({ kind = "place", mapID = t.mapID, x = t.x, y = t.y, text = t.name })
    -- remember it: the login to-do "Zum Lehrer" (collectors/Trainer.lua) must not add a second one while this is open
    if id and ns.Trainer and type(ns.Trainer.markPlace) == "function" then ns.Trainer.markPlace(id) end
    self.todoText = id and T.todoDone or T.todoFail
  end
  W.setText(self.ui.todoMsg, self.todoText)
  return self.todoText == T.todoDone
end

local function distText(m)
  if not m then return nil end
  if m >= 1000 then return T("km", string.format("%.1f", m / 1000)) end
  return T("meters", int(floor(m / 10 + 0.5) * 10))
end

function View:Render()
  local ui = self.ui
  if not self.open then return end
  local view = LP.evaluate()
  self.view = view
  local ok = view.available and (not self.pets or view.pets ~= nil)
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
  ui.headR:SetTexts(player or "", self.pets and T.petPage or T.page)
  if not ok then
    local retail = view.reason == "RETAIL"
    local none = self.pets and view.available -- trainer plan on, but this is no hunter: no pet training
    W.setText(ui.emptyHead, none and T.petNoneHead or (retail and T.retailHead or T.noDataHead))
    W.setText(ui.emptyBody, none and T.petNoneBody or (retail and T.retailBody or T.noDataBody))
    W.setText(ui.emptyRight, none and T.petNoneBody or (retail and T.retailBody or T.noDataBody))
    return
  end
  if self.pets then return self:RenderPets(view, view.pets) end
  -- left: filter and list
  local filter = self:Filter()
  ui.filter:SetValue(filter)
  local rows = LP.rows(view, filter)
  self.items = rows
  ui.rowsList.opts.empty = T[EMPTY_TEXT[filter]]
  ui.rowsList:SetItems(rows)
  ui.rowsList:Refresh()
  local open = view.now.n + view.missing.n + view.talent.n + view.later.n
  W.setText(ui.info, T("info", int(view.level), int(view.learned.n), int(open)))
  -- right: now / cost / bag
  ui.num:SetText(int(view.now.n))
  W.setText(ui.numLbl, T.learnable)
  if view.now.n > 0 then
    W.setText(ui.costLine, T("costLine", money(view.now.cost), view.money and money(view.money) or "?"))
    local short = view.short or 0
    W.setText(ui.shortLine, short > 0 and T("short", money(short)) or T.enough)
    ui.shortLine:SetTextColor(W.color(short > 0 and "red" or "sepia"))
  else
    W.setText(ui.costLine, T.costNone)
    W.setText(ui.shortLine, "")
  end
  for i, fs in ipairs(ui.nextLines) do
    local nb = view.next[i]
    if nb then
      W.setText(fs, T(pluralKey(nb.n, "nextLine_one", "nextLine_other"), int(nb.level), int(nb.n),
        nb.cost > 0 and money(nb.cost) or T.free))
    else
      W.setText(fs, i == 1 and T.nextNone or "")
    end
  end
  -- trainer
  local t = LP.nearestTrainer()
  self.trainer = t
  if t then
    W.setText(ui.trainerName, t.name)
    local where = t.zone
    local d = distText(t.dist)
    if where then
      W.setText(ui.trainerSub, d and T("trainerDist", where, d) or T("trainerFar", where))
    else
      W.setText(ui.trainerSub, d or T.farOnly)
    end
    ui.todo:SetEnabled(ns.Plans ~= nil)
    ui.todo:Show()
  else
    W.setText(ui.trainerName, "")
    W.setText(ui.trainerSub, T.trainerNone)
    ui.todo:Hide()
  end
  W.setText(ui.todoMsg, self.todoText or "")
  -- talents and fees
  local free = LP.unspentTalents()
  if free == nil then
    W.setText(ui.talentLine, T.talentUnknown)
  elseif free > 0 then
    W.setText(ui.talentLine, plural(free, "talentFree_one", "talentFree_other"))
  else
    W.setText(ui.talentLine, (tonumber(view.level) or 0) < 10 and T.talentEarly or T.talentNone)
  end
  ui.talentLine:SetTextColor(W.color(free and free > 0 and "red" or "ink"))
  W.setText(ui.fees, T("fees", money(LP.feesPaid())))
end

-- pet training (mode "pets"): the same layout with the pet abilities; right side without trainer, talents and fees
function View:RenderPets(view, pv)
  local ui = self.ui
  local filter = self:Filter()
  ui.filter:SetValue(filter)
  local rows = LP.petRows(pv, filter)
  self.items = rows
  ui.rowsList.opts.empty = T[PET_EMPTY_TEXT[filter]]
  ui.rowsList:SetItems(rows)
  ui.rowsList:Refresh()
  local open = pv.now.n + pv.missing.n + pv.later.n + pv.unknown.n
  local info = T("info", int(view.level), int(pv.learned.n), int(open))
  if pv.preview then info = info .. " · " .. T.petPreview end
  W.setText(ui.info, info)
  ui.num:SetText(int(pv.now.n))
  W.setText(ui.numLbl, T.learnable)
  if pv.now.n > 0 then
    W.setText(ui.costLine, T("costLine", money(pv.now.cost), view.money and money(view.money) or "?"))
    local short = (view.money and pv.now.cost > view.money) and (pv.now.cost - view.money) or 0
    W.setText(ui.shortLine, short > 0 and T("short", money(short)) or T.enough)
    ui.shortLine:SetTextColor(W.color(short > 0 and "red" or "sepia"))
  else
    W.setText(ui.costLine, T.petCostNone)
    W.setText(ui.shortLine, "")
  end
  for i, fs in ipairs(ui.nextLines) do
    local nb = pv.next[i]
    if nb then
      W.setText(fs, T(pluralKey(nb.n, "nextLine_one", "nextLine_other"), int(nb.level), int(nb.n),
        nb.cost > 0 and money(nb.cost) or T.free))
    else
      W.setText(fs, i == 1 and T.nextNone or "")
    end
  end
  -- note: state of the last visit (or the preview mark) and the hint where the filter sits
  W.setText(ui.trainerName, pv.preview and T.petPreview or "")
  local seen = pv.preview and T.petSample or (pv.seen and T.petSeen or T.petUnseen)
  W.setText(ui.trainerSub, seen .. ". " .. View.petTip() .. "\n\n" .. View.petHowText())
  for _, f in ipairs({ ui.todo, ui.todoMsg, ui.talentHead, ui.talentLine, ui.fees }) do f:Hide() end
end

function View:Open()
  self.open = true
  self.todoText = nil
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

-- sub-view "Tierausbildung": the same view in pet mode (pages/Plaene.lua)
Journal.TierView = { new = function(page, left, right) return View.new(page, left, right, "pets") end }

-- /chronik lehrplan: open the book, tab Pläne, sub-bookmark "Lehrplan". The book stays closed in combat.
function LP.openPage()
  local A, F = Journal.Access, Journal.Frame
  if not (A and F and type(F.showPage) == "function") then return false end
  if type(A.isOpen) == "function" and type(A.open) == "function" and not A.isOpen() then pcall(A.open) end
  if not F.showPage("plaene") then return false end
  local P = Journal.PlaenePage
  if P and P:GetSub() ~= "lehrplan" and type(F.showSub) == "function" then F.showSub("lehrplan") end
  if P and P.trainView and P.trainOpen then P.trainView:Refresh() end
  return P ~= nil and P.trainOpen == true
end
