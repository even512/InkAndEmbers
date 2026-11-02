-- Sub-view "Offen" of the Quests page (registered by pages/Quests.lua): zone choice, switches and the list on the left;
-- map with pins (zone or continent) and the chosen quest with "Als To Do" on the right. Data:
-- journal/model/OpenQuests.lua (display-ready).
-- A click on a row highlights its pin; a click on a pin selects its first quest and marks all rows of that giver.
-- The map is the travel map component (journal/Map.lua): wheel zoom around the cursor, drag to pan, uncovered zone art
-- (all overlays from the data addon where known), continent <-> zone switch by wheel, hover/click on a continent zone,
-- right/double click back to the continent. Pins live on a layer of the map content and are re-placed on every view
-- change; on a zone map the cluster radius follows the zoom (zooming in splits the bundles).
-- Keep-outs (DecorKeepout quests): the list ends before y 474 on the left; on the right everything stays left of x 446
-- and above y 578. No ticker; OnUpdate only inside Map.lua while dragging/hovering; pins are pooled.
-- Retail client: the list comes from the game's world map (OpenQuestsRetail, results have retail = true): a hint line under
-- the title names the source and what is missing, only the switch "Wiederholbar" stays (nothing locked/group/class/
-- profession is known), the "giver" is the quest line, and the empty list says loading / in combat / nothing offered.
local _, ns = ...

local Journal = ns.Journal
local W, Pages, OQ = Journal and Journal.Widgets, Journal and Journal.Pages, Journal and Journal.OpenQuests
local D = W and W.Diary
if not (W and Pages and OQ and D) then return end

local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local Theme = Journal.Theme
local G = Theme.GRID

local View = {}
View.__index = View
Journal.OpenQuestsView = View

-- texts (German here, English in locales/enUS_pages.lua, scope "p.QuestsOffen"; read only on build/draw)
local T = ns.Locale.ns("p.QuestsOffen", {
  brand = "INK & EMBERS", book = "QUESTBUCH", page = "OFFENE QUESTS",
  allZones = "Alle Zonen", zoneTip = "Zone wählen", zoneTip2 = "Zahl = offene Quests in dieser Zone",
  locked = "Gesperrte", lockedTip = { "Noch gesperrt zeigen", "Quests, die noch nicht annehmbar sind, erscheinen grau mit Grund." },
  group = "Gruppe", groupTip = { "Gruppen-, Dungeon-, Raid-, PvP- und Event-Quests", "Standard: ausgeblendet" },
  repeatable = "Wiederholbar", repeatTip = { "Wiederholbare Quests", "Standard: ausgeblendet" },
  class = "Klasse", classTip = { "Klassenquests", "Standard: gezeigt" },
  category = "Beruf", categoryTip = { "Berufs- und andere Sammelkategorie-Quests", "Standard: ausgeblendet" },
  open = "offen", lockedCount = "gesperrt", hidden = "ausgeblendet",
  empty = "Keine offenen Quests in dieser Zone.", emptyAll = "Keine offenen Quests gefunden.",
  noData = "Questdaten nicht geladen", noDataHint = "Prüfen mit /chronik diag",
  noDataRight = "Die Karte erscheint, sobald die Questdaten geladen sind.",
  retailHead = "Weltkarte ohne Quest-Angebote", retailRight = "Ohne die Weltkarten-Schnittstelle des Spiels gibt es hier keine Karte.",
  retailHint = "Aus der Weltkarte des Spiels: nur annehmbare Quests, ohne Questgeber und Sperrgründe",
  retailLoading = "Quests werden aus der Weltkarte des Spiels geladen …",
  retailCombat = "Im Kampf – die Weltkarte wird danach gefragt.",
  retailEmpty = "Die Weltkarte des Spiels zeigt hier gerade keine annehmbaren Quests.",
  retailEmptyAll = "Die Weltkarte des Spiels zeigt in den geladenen Zonen keine annehmbaren Quests.",
  lineWord = "Questreihe: ",
  noMap = "Für dieses Gebiet liefert der Client keine Karte.", noMapTest = "Testmodus: diese Zone hat keine Retail-Karte.",
  unplaced = "%d Zonen ohne Lage auf dieser Karte",
  pick = "Wählt links eine Quest oder klickt ein ! auf der Karte.",
  levelWord = "Stufe ", levelUnknown = "Stufe ?", minWord = "ab Stufe ",
  toTodo = "Als To Do", toTodoTip = { "Als To Do", "Legt ein Ort-Ziel am Questgeber an (Reise -> To Do)." },
  todoDone = "To Do angelegt.", todoFail = "Kein To Do angelegt: ", todoNoPlace = "Questgeber ohne Kartenpunkt",
  todoReasons = { voll = "To-Do-Liste ist voll", ["nicht-bereit"] = "To Do noch nicht bereit", ["kein-plan"] = "To Do nicht verfügbar",
    ["kein-ort"] = "Questgeber ohne Kartenpunkt" },
  zoneTipOpen = "offen", zoneTipLocked = "gesperrt", zoneTipClick = "Klicken: Zone öffnen",
  pinTipClick = "Klicken: in der Liste zeigen", pinLocked = "(gesperrt)",
  giverWord = "Geber: ", noGiver = "Geber unbekannt",
  more = " und %d weitere",
  prevPage = "Vorige Seite", nextPage = "Nächste Seite",
})
View.TEXT = T

local LX, LW = Theme.gridX("L")
local RX, RW = Theme.gridX("R")
local CTRL_CY = G.slots.ctrlTop.y + 20     -- zone choice and paging
local CHECK_CY = CTRL_CY + 28             -- switches
local ROWS_Y = CHECK_CY + 18
local LEFT_END = 474                      -- blot bottom left (keep-out y 478..601) stays free
local ROW_H = 34
local ROWS_N = floor((LEFT_END - ROWS_Y) / ROW_H)
local TITLE_Y = G.slots.title.y
local TEST_Y = TITLE_Y + 36
local CAP_CY = TITLE_Y + 60
local MAP_Y = CAP_CY + 14
local MAP_H = 262
local PANEL_Y = MAP_Y + MAP_H + 12
local PIN = 18
local PIN_SEL = 26
local PIN_MAX = 160
local WHOLE = { x0 = 0, x1 = 1, y0 = 0, y1 = 1 }
View.PIN_MAX = PIN_MAX
View.CLUSTER_PX = PIN * 0.8               -- cluster radius in screen pixels (zone map)
View.RECLUSTER = 1.12                     -- re-cluster once the zoom changed by this factor
View.PIN_GAP = PIN - 2                    -- continent: zone pins closer than this (pixels) are nudged apart
View.ROWS_N = ROWS_N

local function int(n) return Journal.Texts.int(n) end
local function kit() return Journal.QuestsPage and Journal.QuestsPage.kit end

local function label(parent, kind, size, color, justify)
  local fs = W.font(parent, kind, size, color)
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

local function setMark(tex, grey)
  tex:SetTexture(Theme.TEX.questMark)
  if tex.SetDesaturated then tex:SetDesaturated(grey and true or false) end
  tex:SetVertexColor(1, 1, 1, grey and 0.7 or 1)
end

local function setting(key) return Pages.setting(key) end

local function buildControls(self, tab)
  local ui = self.ui
  ui.zone = D.NewDropdown(tab, { width = 236, text = T.allZones, rows = 12, popupWidth = 260,
    onPick = function(it) self:SetZone(it.value) end, tip = { T.zoneTip, T.zoneTip2 } })
  ui.zone:SetPoint("LEFT", tab, "TOPLEFT", LX, -CTRL_CY)
  local function check(text, key, tip)
    local c = D.NewCheck(tab, text, { size = 12, checked = setting(key) == true, tip = tip,
      onChange = function(on) self:SetOption(key, on) end })
    return c
  end
  ui.checks = {
    { key = "openLocked", b = check(T.locked, "openLocked", T.lockedTip) },
    { key = "openGroup", b = check(T.group, "openGroup", T.groupTip) },
    { key = "openRepeat", b = check(T.repeatable, "openRepeat", T.repeatTip) },
    { key = "openClass", b = check(T.class, "openClass", T.classTip) },
    { key = "openCategory", b = check(T.category, "openCategory", T.categoryTip) },
  }
  local prev
  for _, c in ipairs(ui.checks) do
    if prev then c.b:SetPoint("LEFT", prev, "RIGHT", 11, 0) else c.b:SetPoint("LEFT", tab, "TOPLEFT", LX, -CHECK_CY) end
    prev = c.b
  end
end

-- "Geber: " or (world map source in retail) "Questreihe: "
local function giverWord(g)
  return g.kind == "line" and T.lineWord or T.giverWord
end

local function rowTip(q)
  local tip = { q.name }
  tip[#tip + 1] = q.level and (T.levelWord .. int(q.level)) or T.levelUnknown
  if q.minLevel and q.minLevel > 0 then tip[#tip + 1] = T.minWord .. int(q.minLevel) end
  local g = q.givers and q.givers[1]
  if g then tip[#tip + 1] = giverWord(g) .. g.name .. " · " .. (OQ.mapName(g.mapID) or "") end
  for _, r in ipairs(q.reasons or {}) do tip[#tip + 1] = r.text end
  for _, n in ipairs(q.notes or {}) do tip[#tip + 1] = n end
  if q.unsure then tip[#tip + 1] = OQ.unsureLabel .. ": " .. OQ.unsureTip end
  return tip
end
View.rowTip = rowTip

-- second line: locked -> reasons; otherwise giver (with zone for "Alle Zonen"); notes appended
local function subLine(self, q)
  local parts = {}
  if q.state == "locked" and q.reasons and #q.reasons > 0 then
    for _, r in ipairs(q.reasons) do parts[#parts + 1] = r.text end
  else
    local g = q.givers and q.givers[1]
    if g then
      parts[#parts + 1] = self.zone == "all" and (g.name .. " · " .. (OQ.mapName(g.mapID) or "")) or g.name
    else
      parts[#parts + 1] = T.noGiver
    end
  end
  for _, n in ipairs(q.notes or {}) do parts[#parts + 1] = n end
  return table.concat(parts, " · ")
end

local function buildRows(self, tab)
  local ui = self.ui
  local nameW = LW - 22 - 70
  ui.rowsList = W.NewList(tab, { rows = ROWS_N, rowHeight = ROW_H, width = LW + 10, step = 3, empty = T.empty, emptyHand = true,
    build = function(row)
      row.pinBg = W.NewRect(row, "gold", 0.22, "BACKGROUND")
      row.pinBg:SetAllPoints(row)
      row.pinBg:Hide()
      row.mark = row:CreateTexture(nil, "ARTWORK")
      row.mark:SetSize(13, 13)
      row.mark:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)
      row.label:ClearAllPoints()
      row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 22, -3)
      row.label:SetWidth(nameW)
      row.label:SetWordWrap(false)
      row.lvl = label(row, "label", G.size.s, "sepia", "RIGHT")
      row.lvl:SetWidth(66)
      row.lvl:SetPoint("TOPRIGHT", row, "TOPLEFT", LW - 4, -4)
      row.sub = label(row, "label", G.size.xs, "sepia")
      row.sub:SetWordWrap(false)
      row.sub:SetPoint("TOPLEFT", row, "TOPLEFT", 22, -19)
      row.tag = label(row, "label", G.size.xs - 1, "red", "RIGHT")
      row.tag:SetWidth(104)
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
      row.pinBg:Hide()
      row.mark:Hide()
      row.tipLines = nil
      row.label:SetTextColor(W.color("ink"))
    end,
    fill = function(row, q)
      W.setText(row.label, q.name)
      row.lvl:SetText(q.level and (T.levelWord .. int(q.level)) or T.levelUnknown)
      local locked = q.state == "locked"
      row.label:SetTextColor(W.color(locked and "sepia" or "ink", locked and 0.75 or 1))
      W.setText(row.sub, subLine(self, q))
      row.sub:SetTextColor(W.color(locked and "red" or "sepia", locked and 0.85 or 1))
      row.tag:SetText(q.unsure and OQ.unsureLabel or "")
      row.sub:SetWidth(LW - 26 - (q.unsure and 108 or 0))
      setMark(row.mark, locked)
      row.mark:Show()
      row.pinBg:SetShown(self.pinSet ~= nil and self.pinSet[q.id] == true)
      row:SetSelected(q.id == self.sel)
      row.tipLines = rowTip(q)
      D.rowFilled(row)
    end,
    onClick = function(q) self:SelectQuest(q.id, false) end })
  ui.rowsList.frame:ClearAllPoints()
  ui.rowsList.frame:SetPoint("TOPLEFT", tab, "TOPLEFT", LX, -ROWS_Y)
  local K = kit()
  if K and K.pager then ui.pager = K.pager(tab, ui.rowsList, LX, LW, CTRL_CY, { T.prevPage, T.nextPage }) end
end

local function buildMap(self, tabR)
  local ui = self.ui
  local Map = Journal.Map
  local m = Map.create(tabR, RX, MAP_Y, RW, MAP_H, { noteMax = 0 })
  ui.mapObj = m
  ui.map = m.viewport
  m.onView = function() W.call(function() self:PlaceMapPins() end) end
  m.onPoint = function(vx, vy) W.call(function() self:MapClick(vx, vy) end) end
  m.onBack = function() W.call(function() self:MapBack() end) end
  m.zoneAt = function(vx, vy) return self:ZoneAt(vx, vy) end
  m.zoomTarget = function(dir, vx, vy) return self:ZoomTarget(dir, vx, vy) end
  m.zoomApply = function(dir, target) return self:ZoomApply(dir, target) end
  local layer = CreateFrame("Frame", nil, m.content)
  layer:SetAllPoints(m.content)
  if layer.SetFrameLevel and m.content.GetFrameLevel then layer:SetFrameLevel(m.content:GetFrameLevel() + 6) end
  ui.pinLayer = layer
  ui.pins = W.Pool(function()
    local b = CreateFrame("Button", nil, layer)
    b:SetSize(PIN, PIN)
    b.glow = b:CreateTexture(nil, "BACKGROUND")
    b.glow:SetTexture(Theme.TEX.glow)
    b.glow:SetVertexColor(W.color("gold", 0.9))
    b.glow:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.glow:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b.disc = b:CreateTexture(nil, "OVERLAY")
    b.disc:SetTexture(Theme.TEX.disc)
    b.disc:SetVertexColor(W.color("parchment", 0.95))
    b.disc:SetSize(14, 14)
    b.disc:SetPoint("CENTER", b, "BOTTOMRIGHT", 0, 3)
    b.count = label(b, "title", 10, "ink", "CENTER")
    b.count:SetPoint("CENTER", b.disc, "CENTER", 0, 0)
    b:SetScript("OnEnter", function(f) if f.tipLines then W.tip(f, f.tipLines) end end)
    b:SetScript("OnLeave", function(f) W.hideTip(f) end)
    b:SetScript("OnClick", function(f) W.call(function() self:ClickPin(f.data) end) end)
    -- wheel over a pin zooms the map like the map itself
    if b.EnableMouseWheel then b:EnableMouseWheel(true) end
    b:SetScript("OnMouseWheel", function(_, delta) W.call(function() Map.wheel(m, delta) end) end)
    return b
  end, function(b)
    W.hideTip(b)
    b.tipLines, b.data = nil, nil
  end, PIN_MAX)
  ui.mapNote = label(tabR, "text", G.size.s, "sepia", "CENTER")
  ui.mapNote:SetWidth(RW - 40)
  ui.mapNote:SetPoint("CENTER", m.viewport, "CENTER", 0, 0)
end

local function buildRight(self, tabR)
  local ui = self.ui
  ui.headR = W.NewPageHead(tabR, { side = "R" })
  ui.headR:SetTexts("", T.page)
  ui.num = label(tabR, "title", G.size.xl, "ink")
  ui.num:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX, -TITLE_Y)
  ui.numLbl = label(tabR, "label", G.size.s, "sepia")
  ui.numLbl:SetPoint("BOTTOMLEFT", ui.num, "BOTTOMRIGHT", 8, 5)
  ui.numLbl:SetText(T.open)
  ui.numMore = label(tabR, "label", G.size.s, "sepia")
  ui.numMore:SetAlpha(0.8)
  ui.numMore:SetWordWrap(false)
  ui.numMore:SetPoint("BOTTOMLEFT", ui.numLbl, "BOTTOMRIGHT", 12, 0)
  ui.test = label(tabR, "label", G.size.xs, "red")
  ui.test:SetWidth(RW)
  ui.test:SetWordWrap(false)
  ui.test:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX, -TEST_Y)
  ui.caption = label(tabR, "title", G.size.m, "ink")
  ui.caption:SetWidth(RW - 200)
  ui.caption:SetWordWrap(false)
  ui.caption:SetPoint("LEFT", tabR, "TOPLEFT", RX, -CAP_CY)
  local items = {}
  for _, c in ipairs(OQ.continents()) do items[#items + 1] = { key = c.id, label = c.name } end
  ui.cont = D.NewToggle(tabR, { items = items, size = 13, gap = 14, onChange = function(key) self:SetContinent(key) end })
  ui.cont.frame:SetPoint("RIGHT", tabR, "TOPLEFT", RX + RW, -CAP_CY)
  ui.contItems = items
  buildMap(self, tabR)
  -- selection below the map
  ui.selName = label(tabR, "title", G.size.m, "ink")
  ui.selName:SetWidth(RW)
  ui.selName:SetWordWrap(false)
  ui.selName:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX, -PANEL_Y)
  ui.selSub = label(tabR, "label", G.size.xs, "sepia")
  ui.selSub:SetWidth(RW)
  ui.selSub:SetWordWrap(false)
  ui.selSub:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX, -(PANEL_Y + 20))
  ui.selWhy = label(tabR, "label", G.size.xs, "red")
  ui.selWhy:SetWidth(RW)
  ui.selWhy:SetWordWrap(false)
  ui.selWhy:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX, -(PANEL_Y + 35))
  ui.todo = D.NewSticker(tabR, T.toTodo, function() self:AddTodo() end, { tip = T.toTodoTip, height = 36 })
  ui.todo:SetPoint("TOPLEFT", tabR, "TOPLEFT", RX, -(PANEL_Y + 54))
  ui.todoMsg = label(tabR, "label", G.size.xs, "sepia")
  ui.todoMsg:SetWidth(RW - 150)
  ui.todoMsg:SetWordWrap(false)
  ui.todoMsg:SetPoint("LEFT", ui.todo, "RIGHT", 14, 0)
  ui.emptyRight = D.emptyNote(tabR, RW - 60)
  ui.emptyRight:SetPoint("TOP", tabR, "TOPLEFT", RX + RW / 2, -290)
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
  ui.headL = W.NewPageHead(tab, { side = "L" })
  ui.headL:SetTexts(T.brand, T.book)
  buildControls(self, tab)
  buildRows(self, tab)
  buildRight(self, tabR)
  ui.emptyHead = label(tab, "title", G.size.l, "ink", "CENTER")
  ui.emptyHead:SetWidth(LW)
  ui.emptyHead:SetPoint("TOP", tab, "TOPLEFT", LX + LW / 2, -230)
  ui.emptyBody = D.emptyNote(tab, LW - 60)
  ui.emptyBody:SetPoint("TOP", tab, "TOPLEFT", LX + LW / 2, -270)
  D.escKeys(tab, function() page:ShowSub("historie") Pages.subChanged("quests") end)
  -- quest titles arriving from the client cache: redraw the open view once
  if OQ.onNames then OQ.onNames(function() if self.open then self:Render() end end) end
  tab:Hide()
  tabR:Hide()
  return self
end

function View:IsOpen() return self.open == true end

function View:Opts()
  return { locked = setting("openLocked") == true,
    kinds = { group = setting("openGroup") == true, repeatable = setting("openRepeat") == true, class = setting("openClass") == true,
      category = setting("openCategory") == true } }
end

-- the player's current zone in the client's map space (nil in combat/without API)
local function playerMap()
  if type(C_Map) ~= "table" or type(C_Map.GetBestMapForUnit) ~= "function" then return nil end
  local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
  if not ok or type(id) ~= "number" or (type(issecretvalue) == "function" and issecretvalue(id)) then return nil end
  return id
end

function View:SetZone(value)
  if value ~= "all" then
    value = tonumber(value)
    if not value then return end
    value = floor(value)
  end
  self.zone = value
  Pages.setSetting("openZone", value)
  self.sel, self.pinSel, self.pinSet, self.todoText = nil, nil, nil, nil
  self.ui.rowsList:SetOffset(0)
  self:Render()
end

function View:SetOption(key, on)
  Pages.setSetting(key, on and true or false)
  self.pinSel, self.pinSet = nil, nil
  self:Render()
end

function View:SetContinent(id)
  self.cont = tonumber(id)
  self.pinSel = nil
  self:Render()
end

local function indexOf(list, id)
  for i, q in ipairs(list or {}) do
    if q.id == id then return i end
  end
  return nil
end

function View:SelectQuest(id, scroll, noRender)
  self.sel = id
  self.todoText = nil
  -- find the pin of the quest (zone map) or its zone (continent map)
  self.pinSel = nil
  for i, p in ipairs(self.pinData or {}) do
    if p.quests then
      for _, q in ipairs(p.quests) do
        if q.id == id then self.pinSel = i break end
      end
    end
    if self.pinSel then break end
  end
  if not self.pinSel and self.zone == "all" then
    local q = self.items and self.items[indexOf(self.items, id) or 0]
    local g = q and q.givers and q.givers[1]
    for i, p in ipairs(self.pinData or {}) do
      if g and p.mapID == g.mapID then self.pinSel = i break end
    end
  end
  self.pinSet = nil
  if scroll then
    local pos = indexOf(self.items, id)
    if pos then self.ui.rowsList:ScrollTo(pos) end
  end
  if not noRender then self:Render(true) end
end

function View:ClickPin(data)
  if type(data) ~= "table" then return end
  if data.zonePin then
    self:SetZone(data.mapID)
    return
  end
  local set, first = {}, nil
  for _, q in ipairs(data.quests or {}) do
    set[q.id] = true
    first = first or q.id
  end
  if not first then return end
  self:SelectQuest(first, true, true)
  for i, p in ipairs(self.pinData or {}) do
    if p == data then self.pinSel = i end
  end
  self.pinSet = set
  self:Render(true)
end

function View:Selected()
  local pos = self.sel and indexOf(self.items, self.sel)
  return pos and self.items[pos] or nil
end

function View:AddTodo()
  local q = self:Selected()
  if not q then return end
  local opts
  local pin = self.pinSel and self.pinData and self.pinData[self.pinSel]
  if pin and not self.zonePins and pin.x and pin.y then
    -- at the chosen pin: the giver of this quest on the map that is nearest to the pin
    local best, bd
    for _, g in ipairs(q.givers or {}) do
      for _, pt in ipairs(g.points or {}) do
        local d = (pt[1] - pin.x) ^ 2 + (pt[2] - pin.y) ^ 2
        if g.mapID == pin.mapID and (not bd or d < bd) then best, bd = { mapID = g.mapID, x = pt[1], y = pt[2] }, d end
      end
    end
    if best then opts = best end
  end
  local id, why = OQ.addTodo(q, opts)
  if id then
    self.todoText = T.todoDone
  else
    self.todoText = T.todoFail .. (T.todoReasons[why] or T.todoReasons["kein-plan"])
  end
  self:Render(true)
end

local function artOf(mapID)
  local V = Journal.View
  local function valid(a) return type(a) == "table" and tonumber(a.w) and tonumber(a.h) and a.w > 0 and a.h > 0 end
  for _, fn in ipairs({ V and V.zoneArt or false, V and V.mapArt or false }) do
    if type(fn) == "function" then
      local ok, a = pcall(fn, mapID)
      if ok and valid(a) then
        -- uncovered map: all exploration overlays from the data addon (Forever), else the client's explored ones
        local all = OQ.overlays and OQ.overlays(mapID) or nil
        if all and V.overlayTiles and tonumber(a.tileW) and tonumber(a.tileH) then
          local okT, tiles = pcall(V.overlayTiles, all, a.tileW, a.tileH)
          if okT and type(tiles) == "table" then a.overlays = tiles end
        end
        return a
      end
    end
  end
  return nil
end
View.artOf = artOf

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

-- continent of a (client) zone map: client chain, else the fixed assignment of MapSpace (both map spaces)
local function continentOfZone(mapID)
  local G = Journal.Geo
  if G and G.continentOf then
    local ok, c = pcall(G.continentOf, mapID)
    if ok and num(c) then return c end
  end
  local M = Journal.MapSpace
  return M and M.continentOf and num(M.continentOf(mapID)) or nil
end
View.continentOfZone = continentOfZone

local function pinTip(p)
  local tip = {}
  if p.zonePin then
    tip[1] = p.name
    tip[2] = int(p.open) .. " " .. T.zoneTipOpen .. (p.locked > 0 and (" · " .. int(p.locked) .. " " .. T.zoneTipLocked) or "")
    tip[3] = T.zoneTipClick
    return tip
  end
  local names = p.givers or {}
  local head = names[1] or T.noGiver
  if #names > 1 then head = head .. T("more", #names - 1) end
  tip[1] = head
  local shown = min(#(p.quests or {}), OQ.TOOLTIP_LINES)
  for i, l in ipairs(OQ.tooltipLines(p, OQ.TOOLTIP_LINES)) do
    local q = i <= shown and p.quests[i] or nil -- the line "… und n weitere" is not a quest
    tip[#tip + 1] = (q and q.state == "locked") and (l .. " " .. T.pinLocked) or l
  end
  tip[#tip + 1] = T.pinTipClick
  return tip
end
View.pinTip = pinTip

-- zone map: cluster the givers with a radius of View.CLUSTER_PX screen pixels at the current zoom
local function zonePins(self, res)
  local T = self.ui.mapObj.T
  local sx = (T and num(T.sx) and T.sx > 0) and T.sx or RW
  self.clusterSx = sx
  return OQ.pins(res, { radius = View.CLUSTER_PX / sx, maxPins = PIN_MAX - 10 }).pins
end
View.zonePins = zonePins

-- after re-clustering: the pin of the selected quest (or the first pin of the marked set) stays selected
local function reselect(self)
  self.pinSel = nil
  for i, p in ipairs(self.pinData or {}) do
    for _, q in ipairs(p.quests or {}) do
      if q.id == self.sel then self.pinSel = i break end
    end
    if self.pinSel then break end
  end
end

-- place the pins at the current view of the map (pixels = Map.toPixel); pins outside the visible map are not drawn. On a
-- zone map a zoom change of View.RECLUSTER re-clusters first.
function View:PlaceMapPins()
  local ui = self.ui
  local m = ui.mapObj
  ui.pins:ReleaseAll()
  if not (self.open and m and m.T and self.res) then return end
  local T = m.T
  if not self.zonePins and self.clusterSx and num(T.sx) then
    local f = T.sx / self.clusterSx
    if f > View.RECLUSTER or f < 1 / View.RECLUSTER then
      self.pinData = zonePins(self, self.res)
      reselect(self)
    end
  end
  local Map = Journal.Map
  local placed = {}
  for i, p in ipairs(self.pinData or {}) do
    local px, py = Map.toPixel(T, p.x, p.y)
    if self.zonePins then
      -- continent: zone pins closer than PIN_GAP are nudged downwards (a city next to its zone)
      for _ = 1, 6 do
        local hit = false
        for _, o in ipairs(placed) do
          if abs(o[1] - px) < View.PIN_GAP and abs(o[2] - py) < View.PIN_GAP then hit = true break end
        end
        if not hit then break end
        py = py + View.PIN_GAP
      end
      placed[#placed + 1] = { px, py }
    end
    if px >= -PIN and py >= 0 and px <= RW + PIN and py <= MAP_H + PIN then
      local b = ui.pins:Acquire()
      if not b then break end
      local sel = i == self.pinSel
      local size = sel and PIN_SEL or PIN
      b:SetSize(size, size)
      b.glow:SetSize(size * 2.2, size * 2.2)
      b.glow:SetShown(sel)
      setMark(b.icon, p.grey)
      local n = p.count or 0
      b.disc:SetShown(n > 1)
      b.count:SetText(n > 1 and (n > 99 and "99+" or tostring(n)) or "")
      b.data = p
      b.tipLines = pinTip(p)
      if b.SetFrameLevel and ui.pinLayer.GetFrameLevel then b:SetFrameLevel(ui.pinLayer:GetFrameLevel() + (sel and 3 or 1)) end
      -- the foot of the ! stands on the giver (tip pointing down)
      b:ClearAllPoints()
      b:SetPoint("BOTTOM", m.content, "TOPLEFT", px, -py + 2)
    end
  end
end

-- zone under a continent point (hover/click/wheel): cities and zones stay themselves, sub-maps (caves, districts) become
-- their zone. -> { id, name, mapID = continent } or nil
function View:ZoneAt(vx, vy)
  local cont = self.zonePins and self.cont or nil
  if not (cont and num(vx) and num(vy)) then return nil end
  if type(C_Map) ~= "table" or type(C_Map.GetMapInfoAtPosition) ~= "function" then return nil end
  local ok, info = pcall(C_Map.GetMapInfoAtPosition, cont, vx, vy)
  if not ok or type(info) ~= "table" or isSecret(info) then return nil end
  local id, kind = num(info.mapID), num(info.mapType)
  if not id or id == cont or (kind and kind < 3) then return nil end
  if kind ~= 3 then
    local Geo = Journal.Geo
    if Geo and Geo.zoneOf then
      local okZ, z = pcall(Geo.zoneOf, id)
      if okZ and num(z) then id = z end
    end
  end
  if id == cont then return nil end
  return { id = id, name = OQ.mapName(id), mapID = cont }
end

function View:MapClick(vx, vy)
  if not self.zonePins then return false end
  local z = self:ZoneAt(vx, vy)
  if not z then return false end
  self:SetZone(z.id)
  return true
end

-- right/double click: zone -> its continent; continent zoomed -> whole continent
function View:MapBack()
  if self.zonePins then
    local Map = Journal.Map
    return Map.resetView(self.ui.mapObj)
  end
  local c = type(self.zone) == "number" and continentOfZone(self.zone) or nil
  for _, x in ipairs(OQ.continents()) do
    if x.id == c then self.cont = c end
  end
  self:SetZone("all")
  return true
end

-- wheel switch continent <-> zone (Map.zoomSwitchWheel): "in" = zone under the cursor with art, "out" = the shown zone on
-- its continent. -> { zone, cont, a, b, c, d, artW, artH } or nil
function View:ZoomTarget(dir, vx, vy)
  local Geo = Journal.Geo
  if not (Geo and Geo.affine) then return nil end
  local zone, cont, art
  if dir == "in" then
    local z = self:ZoneAt(vx, vy)
    if not z then return nil end
    zone, cont = z.id, self.cont
    art = artOf(zone)
    if not art then return nil end
  elseif dir == "out" then
    if self.zonePins or type(self.zone) ~= "number" then return nil end
    zone, cont = self.zone, continentOfZone(self.zone)
    local known = false
    for _, x in ipairs(OQ.continents()) do if x.id == cont then known = true end end
    if not known then return nil end
  else
    return nil
  end
  if not zone or not cont or zone == cont then return nil end
  local a, b, c, d = Geo.affine(zone, cont)
  if not a then return nil end
  return { zone = zone, cont = cont, a = a, b = b, c = c, d = d, artW = art and art.w, artH = art and art.h }
end

function View:ZoomApply(dir, target)
  if type(target) ~= "table" then return false end
  self.cont = target.cont
  if dir == "in" then
    self:SetZone(target.zone)
    return self.zone == target.zone and not self.zonePins
  end
  self:SetZone("all")
  return self.zonePins == true and self.cont == target.cont
end

local function hiddenText(res)
  local h = res.hidden or {}
  if (h.total or 0) == 0 then return nil end
  return int(h.total) .. " " .. T.hidden
end

-- fetch content again (list/zones/pins) and draw everything; keepData = only selection/highlight again (same data)
function View:Render(keepData)
  local ui = self.ui
  if not self.open then return end
  local opts = self:Opts()
  local zones = OQ.zones(opts)
  local res = OQ.list(self.zone, opts)
  local unavailable = res.unavailable or zones.unavailable
  self.res = res
  -- list: open ones, then (switch) locked ones
  local items = {}
  for _, q in ipairs(res.open) do items[#items + 1] = q end
  for _, q in ipairs(res.locked) do items[#items + 1] = q end
  self.items = items
  if self.sel and not indexOf(items, self.sel) then self.sel, self.pinSet = nil, nil end
  ui.emptyHead:SetShown(unavailable and true or false)
  ui.emptyBody:SetShown(unavailable and true or false)
  ui.rowsList.frame:SetShown(not unavailable)
  ui.zone:SetShown(not unavailable)
  -- retail world map: only "Wiederholbar" means something; the shown switches are chained again
  local prevCheck
  for _, c in ipairs(ui.checks) do
    local shown = not unavailable and (not res.retail or c.key == "openRepeat")
    c.b:SetShown(shown)
    c.b:SetChecked(setting(c.key) == true, true)
    if shown then
      c.b:ClearAllPoints()
      if prevCheck then c.b:SetPoint("LEFT", prevCheck, "RIGHT", 11, 0) else c.b:SetPoint("LEFT", ui.table, "TOPLEFT", LX, -CHECK_CY) end
      prevCheck = c.b
    end
  end
  if ui.pager then
    ui.pager.pair.frame:SetShown(not unavailable)
    ui.pager.label:SetShown(not unavailable)
  end
  if unavailable then
    local reason = res.reason or zones.reason
    local retailReason = reason == "RETAIL" or reason == "NO_QUESTLINE"
    W.setText(ui.emptyHead, retailReason and T.retailHead or T.noData)
    W.setText(ui.emptyBody, OQ.reasonText(reason) .. "." .. (retailReason and "" or " " .. T.noDataHint))
  else
    local zItems = { { text = T.allZones, count = zones.total.open, value = "all", active = self.zone == "all" } }
    local zoneName
    for _, z in ipairs(zones.zones) do
      zItems[#zItems + 1] = { text = z.name, count = z.open, value = z.mapID, active = z.mapID == self.zone }
      if z.mapID == self.zone then zoneName = z.name end
    end
    ui.zone:SetItems(zItems)
    ui.zone:SetText(self.zone == "all" and T.allZones or zoneName or OQ.mapName(self.zone))
    if res.retail then
      ui.rowsList.opts.empty = res.combat and T.retailCombat or res.loading and T.retailLoading
        or (self.zone == "all" and T.retailEmptyAll or T.retailEmpty)
    else
      ui.rowsList.opts.empty = self.zone == "all" and T.emptyAll or T.empty
    end
    ui.rowsList:SetItems(items)
    ui.rowsList:Refresh()
  end
  ui.emptyRight:SetShown(unavailable and true or false)
  local why = res.reason or zones.reason
  local retail = why == "RETAIL" or why == "NO_QUESTLINE"
  W.setText(ui.emptyRight, unavailable and (retail and T.retailRight or T.noDataRight) or "")
  for _, f in ipairs({ ui.num, ui.numLbl, ui.numMore, ui.caption, ui.map, ui.selName, ui.selSub, ui.selWhy, ui.todo, ui.todoMsg }) do
    f:SetShown(not unavailable)
  end
  local testText = OQ.testLabel()
  W.setText(ui.test, testText or (res.retail and T.retailHint) or "")
  ui.test:SetTextColor(W.color(testText and "red" or "sepia"))
  if unavailable then
    ui.cont.frame:Hide()
    ui.pins:ReleaseAll()
    return
  end
  ui.num:SetText(int(res.openCount))
  local more = {}
  if res.lockedCount > 0 then more[#more + 1] = int(res.lockedCount) .. " " .. T.lockedCount end
  local hid = hiddenText(res)
  if hid then more[#more + 1] = hid end
  W.setText(ui.numMore, table.concat(more, " · "))
  local mapID, note
  self.zonePins = self.zone == "all"
  if self.zonePins then
    local conts = OQ.continents()
    if not self.cont then
      -- default: the continent of the player's position, else the one with more zones
      local here, best, bestN = playerMap(), nil, -1
      for _, c in ipairs(conts) do
        local zp = OQ.zonePins(res, c.id, {})
        for _, p in ipairs(zp.pins) do
          if here and p.mapID == here then best, bestN = c.id, math.huge end
        end
        if #zp.pins > bestN then best, bestN = c.id, #zp.pins end
      end
      self.cont = best or (conts[1] and conts[1].id)
    end
    mapID = self.cont
    local zp = OQ.zonePins(res, mapID, {})
    for _, p in ipairs(zp.pins) do p.zonePin = true end
    self.pinData = zp.pins
    if zp.unplaced > 0 and #zp.pins == 0 then note = string.format(T.unplaced, zp.unplaced) end
    ui.cont:SetValue(self.cont)
    ui.cont.frame:Show()
    local cname
    for _, c in ipairs(conts) do if c.id == self.cont then cname = c.name end end
    W.setText(ui.caption, cname or T.allZones)
  else
    mapID = self.zone
    ui.cont.frame:Hide()
    W.setText(ui.caption, OQ.mapName(mapID))
    if res.unmapped then note = T.noMapTest end
  end
  local art = mapID and artOf(mapID) or nil
  if not art then note = note or (OQ.test() and T.noMapTest or T.noMap) end
  local Map, Vw = Journal.Map, Journal.View
  local scene = self.zonePins and { mode = "continent", contID = mapID, key = "oq:c:" .. tostring(mapID), focus = WHOLE }
    or { mode = "zone", zoneID = mapID, key = "oq:z:" .. tostring(mapID), focus = WHOLE }
  local aspect = (not art and Vw and Vw.mapAspect) and Vw.mapAspect(mapID) or nil
  ui.mapStats = Map.render(ui.mapObj, scene, { art = art, aspect = aspect, clip = not self.zonePins and WHOLE or nil,
    color = Vw and Vw.peek and Vw.peek("mapColor") or nil, reduceMotion = Vw and Vw.peek and Vw.peek("reduceMotion") or nil,
    showKills = false, pad = 6, keepView = true })
  if not self.zonePins and (not keepData or not self.pinData) then
    self.pinData = zonePins(self, res)
    reselect(self)
  end
  W.setText(ui.mapNote, note or "")
  self:PlaceMapPins()
  local q = self:Selected()
  ui.todo:SetShown(q ~= nil)
  if q then
    W.setText(ui.selName, q.name)
    local g = q.givers and q.givers[1]
    local sub = { q.level and (T.levelWord .. int(q.level)) or T.levelUnknown }
    if g then sub[#sub + 1] = giverWord(g) .. g.name .. " · " .. (OQ.mapName(g.mapID) or "") end
    if q.unsure then sub[#sub + 1] = OQ.unsureLabel end
    W.setText(ui.selSub, table.concat(sub, " · "))
    local why = {}
    for _, r in ipairs(q.reasons or {}) do why[#why + 1] = r.text end
    for _, n in ipairs(q.notes or {}) do why[#why + 1] = n end
    W.setText(ui.selWhy, table.concat(why, " · "))
    ui.todo:SetEnabled(not q.noLocation and q.givers and #q.givers > 0)
  else
    W.setText(ui.selName, "")
    W.setText(ui.selSub, T.pick)
    W.setText(ui.selWhy, "")
  end
  W.setText(ui.todoMsg, q and self.todoText or "")
end

function View:Open()
  self.open = true
  if self.zone == nil then
    local z = setting("openZone")
    -- saved zone from another map space (retail: a previously saved Forever ID 1411) into the client's
    if type(z) == "number" and OQ.clientZone then z = OQ.clientZone(z) or "all" end
    if z == nil then
      -- first visit: the player's zone if quests are open there, else all
      local here = playerMap()
      z = "all"
      if here then
        for _, e in ipairs(OQ.zones(self:Opts()).zones or {}) do
          if e.mapID == here then z = here end
        end
      end
    end
    self.zone = z
  end
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
  if ui.zone.Close then ui.zone:Close() end
  ui.pins:ReleaseAll()
  for _, r in ipairs(ui.rowsList.rows) do W.hideTip(r) end
  ui.table:Hide()
  ui.tableR:Hide()
end

-- /chronik offene: open the book, tab Quests, sub-bookmark "Offen" (hook of OpenQuests.slash). The book stays closed in combat.
function OQ.openPage()
  local A, F = Journal.Access, Journal.Frame
  if not (A and F and type(F.showPage) == "function") then return false end
  if type(A.isOpen) == "function" and type(A.open) == "function" and not A.isOpen() then pcall(A.open) end
  if not F.showPage("quests") then return false end
  local P = Journal.QuestsPage
  if P and P:GetSub() ~= "offen" and type(F.showSub) == "function" then F.showSub("offen") end
  if P and P.openView and P.openOpen then P.openView:Refresh() end
  return P ~= nil and P.openOpen == true
end
