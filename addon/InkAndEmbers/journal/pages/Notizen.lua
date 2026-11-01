-- Notizen page: own notes with an editor. Left: list, sort, search, paging; right: title, place/time, switch
-- "Bearbeiten | Lesen", checks "Angeheftet" and "Auf der Karte". Saving is automatic (focus loss, 2 s after typing,
-- switching); delete asks first.
-- Data: ns.Journal.Notes, markup/safety: ns.Journal.NoteMarkup; writes only via
-- Notes.create/update/remove/setPinned/setOnMap/toggleCheck. Display via Sanitize.display / NoteMarkup.render only. No
-- ticker/OnUpdate; saving/searching are delayed via C_Timer.After with a counter.
local _, ns = ...

local Journal = ns.Journal
local W, Pages = Journal and Journal.Widgets, Journal and Journal.Pages
local D = W and W.Diary
local Notes, M = Journal and Journal.Notes, Journal and Journal.NoteMarkup
if not (W and Pages and D and Notes and M) then return end

local Theme = Journal.Theme or {}
local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil

local Page = { needs = { index = false, model = false } }
Journal.NotizenPage = Page -- handle for tests, pins (Frame.openNote) and the diagnostics

-- locale scope "p.Notizen" (English in locales/enUS_pages.lua), read when drawing
local T = ns.Locale.ns("p.Notizen", {
  inkTip = "Tinte: %s", inkInsert = "Fügt {%s}…{/} ein.", symInsert = "Fügt {%s} ein.", reopen = "Wieder öffnen", tick = "Abhaken",
  whenFmt = "%d.%m. %H:%M",
  brand = "INK & EMBERS", page = "NOTIZEN",
  note = "Notiz", notes = "Notizen", pinnedN = "%d angeheftet", lastEdit = "zuletzt %s",
  pageOf = "Seite %d von %d", prevTip = "Vorige Seite", nextTip = "Nächste Seite",
  sortNew = "Neueste zuerst", sortOld = "Älteste zuerst", sortTitle = "Nach Titel",
  sortTip = { "Sortierung", "Angeheftete Notizen stehen immer oben." },
  searchHint = "Suchen in Titel und Text …", searchClear = "Suche leeren",
  newNote = "Neue Notiz", newTip = { "Neue Notiz", "Legt eine Notiz mit Ort, Stufe und Zeit von jetzt an." },
  untitled = "Ohne Titel", emptyList = "Noch keine Notizen.", emptyListBody = "Mit „Neue Notiz“ unten legt Ihr die erste an.",
  noMatch = "Keine Notiz passt zur Suche.", noChar = "Für diesen Charakter gibt es noch keine Chronik.",
  pickNote = "Wählt links eine Notiz oder legt eine neue an.",
  edit = "Bearbeiten", read = "Lesen", editTip = { "Bearbeiten", "Text mit Markup schreiben (speichert von selbst)." },
  readTip = { "Lesen", "Die Notiz gestaltet anzeigen; Haken lassen sich anklicken." },
  pin = "Angeheftet", pinTip = { "Anheften", "Angeheftete Notizen stehen oben in der Liste." },
  onMap = "Auf der Karte", onMapTip = { "Auf der Karte zeigen", "Steckt eine Pinnadel an den Ort, an dem die Notiz entstand." },
  noPlace = "Diese Notiz hat keinen Kartenpunkt (beim Anlegen war kein Ort lesbar).",
  titleHint = "Titel …",
  bodyHint = "Hier schreiben … (# Überschrift, - Liste, [ ] Haken)\nUmschalt+Klick auf Gegenstand, Quest oder Zauber fügt einen Link ein.",
  created = "angelegt %s", changed = "geändert %s", levelW = "Stufe %d",
  emptyRead = "Noch leer. „Bearbeiten“ wählen, um zu schreiben.",
  delete = "Löschen", deleteTip = { "Notiz löschen", "Fragt einmal nach." }, confirm = "Wirklich löschen?",
  confirmTip = { "Wirklich löschen?", "Noch einmal klicken löscht die Notiz endgültig." },
  full = "Das Notizbuch ist voll (höchstens %d Notizen).", notReady = "Die Chronik ist noch nicht bereit.",
  tooLong = "Die Notiz ist voll (höchstens %d Zeichen).", linkType = "Nur Gegenstände, Quests und Zauber lassen sich einfügen.",
  chars = "%d / %d",
  quick = "Schnellnotizen",
  quickTip = { "Schnellnotizen", "Zeigt am Bildschirmrand ein kleines Feld: schreiben, Enter, schon liegt die Notiz im Notizbuch." },
  ink = "Tinte", symbols = "Symbole",
  tools = {
    head = { label = "Überschrift", tip = { "Überschrift", "Setzt „# “ vor die Zeile." } },
    emph = { label = "Hervorheben", tip = { "Hervorheben", "Fügt **…** ein (Text dazwischen wird hervorgehoben)." } },
    bullet = { label = "Liste", tip = { "Aufzählung", "Setzt „- “ vor die Zeile." } },
    check = { label = "Haken", tip = { "Häkchen-Liste", "Setzt „[ ] “ vor die Zeile; in „Lesen“ abhakbar." } },
    rule = { label = "Linie", tip = { "Trennlinie", "Fügt eine Zeile „---“ ein." } },
  },
  symbolsTip = { "Symbole", "Raid-Markierungen und Kartensymbole einfügen.", "Links: Umschalt+Klick auf Gegenstand, Quest oder Zauber." },
  truncated = "… (weitere Zeilen nur in „Bearbeiten“)",
})
Page.TEXT = T

local G = Theme.GRID
local LX, LW = Theme.gridX("L")
local RX, RW = Theme.gridX("R")
local TITLE_Y, SUB_Y = G.slots.title.y, G.slots.title.y + 34
local CTRL_Y, CTRL_H = G.slots.ctrl.y, G.slots.ctrl.h
local CTRL_CY = CTRL_Y + CTRL_H / 2
local BODY_Y = G.slots.body.y
local FOOT_Y = G.slots.foot.y

Page.ROWS = 9
Page.ROW_H = 42
Page.LIST_Y = BODY_Y + 34          -- below the search box
Page.SAVE_DELAY = 2                -- seconds after typing
Page.SEARCH_DELAY = 0.25
Page.CONFIRM_TIME = 5              -- seconds "Wirklich löschen?" stays valid
Page.READ_ROWS_MAX = 200           -- row pool of the read view
-- right page: the thumbprint at the bottom (keep-out x 161..296 from y 556) and the edge line (x >= 450) stay free
Page.QUICK_CY = 88                 -- centre of the check "Schnellnotizen" (top left next to the title)
Page.EDIT_TOP = BODY_Y + 64        -- below the two tool lines
Page.EDIT_BOTTOM = 548
Page.READ_TOP = BODY_Y

-- label read late (text = T[key])
local SORTS = {}
for i, s in ipairs({ { value = "new", key = "sortNew" }, { value = "old", key = "sortOld" }, { value = "title", key = "sortTitle" } }) do
  SORTS[i] = setmetatable(s, { __index = function(t, k) if k == "text" then return T[t.key] end end })
end

local function shown(s, maxBytes)
  return ns.Sanitize.display(s, maxBytes or 120)
end

local function when(t)
  if type(t) ~= "number" or t ~= t then return nil end
  local ok, s = pcall(date, T.whenFmt, t)
  return (ok and type(s) == "string") and s or nil
end

local function place(region, parent, x, y, point)
  region:ClearAllPoints()
  region:SetPoint(point or "TOPLEFT", parent, "TOPLEFT", x, -y)
end

local function label(parent, kind, size, color, justify)
  local fs = W.font(parent, kind, size, color)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  return fs
end

local function noteTitle(n)
  if type(n) ~= "table" then return T.untitled end
  local t = (n.title ~= "" and n.title) or M.firstLine(n.body)
  return (t and shown(t, 160)) or T.untitled
end

local function timer(sec, fn)
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then C_Timer.After(sec, fn) end
end

local function buildRow(self, parent, i)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(LW, Page.ROW_H)
  place(row, parent, LX, Page.LIST_Y + (i - 1) * Page.ROW_H)
  local pin = row:CreateTexture(nil, "ARTWORK")
  pin:SetSize(16, 16)
  pin:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -4)
  pin:SetTexture(Theme.TEX.notePin)
  row.pin = pin
  row.label = label(row, "text", G.size.m, "ink")
  row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 20, -5)
  row.label:SetWidth(LW - 24)
  row.sub = label(row, "label", G.size.xs, "sepia")
  row.sub:SetPoint("TOPLEFT", row, "TOPLEFT", 20, -24)
  row.sub:SetWidth(LW - 24)
  D.RowStyle(row, { texts = { row.label } })
  row:SetScript("OnClick", function(r)
    if r.noteId then W.call(self.Select, self, r.noteId) end
  end)
  return row
end

local function buildLeft(self, left)
  local ui = self.ui
  ui.headL = W.NewPageHead(left, { side = "L" })
  ui.headL:SetTexts(T.brand, T.page)
  ui.title = label(left, "title", G.size.xl, "ink")
  ui.title:SetWidth(LW)
  place(ui.title, left, LX, TITLE_Y)
  ui.sub = label(left, "label", G.size.s, "sepia")
  ui.sub:SetWidth(LW)
  place(ui.sub, left, LX, SUB_Y)
  -- check "Schnellnotizen" (same setting as in the cog, journal/QuickNote.lua; default off): right of the title,
  -- below the decoration top right (keep-out down to y 50) and above the control line
  ui.quick = D.NewCheck(left, T.quick, { size = G.size.m, tip = T.quickTip, onChange = function(on) self:SetQuick(on) end })
  ui.quick:SetPoint("RIGHT", left, "TOPLEFT", LX + LW, -(Page.QUICK_CY))

  -- control line: sort (paper slips) left, paging right
  local items = {}
  for i, s in ipairs(SORTS) do items[i] = { text = s.text, value = s.value, active = s.value == self.sort } end
  ui.sortDrop = D.NewDropdown(left, { width = 150, size = G.size.m, text = T.sortNew, items = items, rows = 3, popupWidth = 170,
    tip = T.sortTip, onPick = function(it) self:SetSort(it.value) end })
  ui.sortDrop:SetPoint("LEFT", left, "TOPLEFT", LX, -CTRL_CY)
  ui.pair = D.NewNavPair(left, { onPrev = function() self:Step(-1) end, onNext = function() self:Step(1) end,
    tipPrev = { T.prevTip }, tipNext = { T.nextTip } })
  ui.pair.frame:SetPoint("RIGHT", left, "TOPLEFT", LX + LW, -CTRL_CY)
  ui.nav = label(left, "label", G.size.s, "sepia", "RIGHT")
  ui.nav:SetWidth(110)
  ui.nav:SetPoint("RIGHT", ui.pair.frame, "LEFT", -8, 0)

  -- search box (title + text), the search is delayed
  local sb = CreateFrame("EditBox", nil, left)
  sb:SetSize(LW, 24)
  place(sb, left, LX, BODY_Y)
  sb:SetAutoFocus(false)
  sb:SetMaxLetters(60)
  sb:SetTextInsets(8, 26, 0, 0)
  pcall(sb.SetFont, sb, W.FONT.text, G.size.m, "")
  sb:SetTextColor(W.color("ink"))
  sb.edge = W.NewOutline(sb, LW, 24, "sepia", 0.6)
  sb.edge:SetAllPoints(sb)
  sb.hint = D.font(sb, "text", G.size.m, "sepia")
  sb.hint:SetPoint("LEFT", sb, "LEFT", 8, 0)
  sb.hint:SetText(T.searchHint)
  sb.hint:SetAlpha(0.7)
  sb:SetScript("OnTextChanged", function(box)
    local text = box:GetText()
    local empty = type(text) ~= "string" or text == ""
    box.hint:SetShown(empty)
    ui.clear:SetShown(not empty)
    self.searchSeq = (self.searchSeq or 0) + 1
    local seq = self.searchSeq
    timer(Page.SEARCH_DELAY, function()
      if seq == self.searchSeq then W.call(self.SetQuery, self, box:GetText()) end
    end)
  end)
  sb:SetScript("OnEnterPressed", function(box) box:ClearFocus() W.call(self.SetQuery, self, box:GetText()) end)
  sb:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
  ui.search = sb
  local clear = CreateFrame("Button", nil, sb)
  clear:SetSize(20, 20)
  clear:SetPoint("RIGHT", sb, "RIGHT", -3, 0)
  clear.x = D.font(clear, "label", 18, "sepia")
  clear.x:SetPoint("CENTER", clear, "CENTER", 0, 1)
  clear.x:SetText("×")
  clear:SetScript("OnClick", function() W.call(self.SetQuery, self, "", true) end)
  clear:SetScript("OnEnter", function(b) b.x:SetTextColor(W.color("red")) W.tip(b, { T.searchClear }) end)
  clear:SetScript("OnLeave", function(b) b.x:SetTextColor(W.color("sepia")) W.hideTip(b) end)
  clear:Hide()
  ui.clear = clear

  ui.rows = {}
  for i = 1, Page.ROWS do ui.rows[i] = buildRow(self, left, i) end
  ui.empty = label(left, "title", G.size.l, "ink", "CENTER")
  ui.empty:SetWidth(LW)
  ui.empty:SetPoint("TOP", left, "TOPLEFT", LX + LW / 2, -(Page.LIST_Y + 70))
  ui.emptyBody = label(left, "text", G.size.m, "sepia", "CENTER")
  ui.emptyBody:SetWidth(LW - 40)
  ui.emptyBody:SetWordWrap(true)
  ui.emptyBody:SetPoint("TOP", left, "TOPLEFT", LX + LW / 2, -(Page.LIST_Y + 102))

  -- footer: message left, "Neue Notiz" towards the fold
  local point, fx, fy = Theme.gridFoot("L")
  ui.newBtn = D.NewSticker(left, T.newNote, function() self:New() end, { height = 30, size = 18, tip = T.newTip })
  ui.newBtn:SetPoint(point, left, "TOPLEFT", fx, -(fy - 2))
  ui.msg = label(left, "label", G.size.s, "red")
  ui.msg:SetWidth(LW - 140)
  place(ui.msg, left, LX, FOOT_Y + 7)
end

local function toolSticker(self, parent, key, x, y, fn)
  local def = T.tools[key]
  local b = D.NewSticker(parent, def.label, function() W.call(fn) end, { height = 26, size = 15, tip = def.tip, tilt = 0 })
  place(b, parent, x, y)
  b.toolKey = key
  return b
end

local function buildToolbar(self, right)
  local ui = self.ui
  local bar = CreateFrame("Frame", nil, right)
  bar:SetAllPoints(right)
  ui.bar = bar
  ui.tools = {}
  local order = { "head", "emph", "bullet", "check" }
  local acts = {
    head = function() self:LinePrefix("# ") end,
    emph = function() self:InsertText("****", 2) end,
    bullet = function() self:LinePrefix("- ") end,
    check = function() self:LinePrefix("[ ] ") end,
    rule = function() self:InsertRule() end,
  }
  local x = RX
  for _, key in ipairs(order) do
    local b = toolSticker(self, bar, key, x, BODY_Y, acts[key])
    ui.tools[key] = b
    x = x + (tonumber(b:GetWidth()) or 70) + 4
  end
  -- second line: ink colours, rule, symbols (the hint about shift-click is in the empty box and in the tooltip of "Symbole")
  local y2 = BODY_Y + 32
  ui.inkLabel = label(bar, "label", G.size.s, "sepia")
  ui.inkLabel:SetText(T.ink)
  place(ui.inkLabel, bar, RX, y2 + 6)
  ui.inks = {}
  local ix = RX + 34
  for i, key in ipairs(M.COLOR_ORDER) do
    local c = M.COLORS[key]
    local b = CreateFrame("Button", nil, bar)
    b:SetSize(20, 20)
    place(b, bar, ix + (i - 1) * 26, y2 + 2)
    local disc = b:CreateTexture(nil, "ARTWORK")
    disc:SetAllPoints(b)
    disc:SetTexture(Theme.TEX.disc)
    local r, g, bl = tonumber(c.hex:sub(1, 2), 16) / 255, tonumber(c.hex:sub(3, 4), 16) / 255, tonumber(c.hex:sub(5, 6), 16) / 255
    disc:SetVertexColor(r, g, bl, 1)
    b.disc, b.inkKey = disc, key
    b:SetScript("OnClick", function() W.call(self.InsertText, self, "{" .. key .. "}{/}", #key + 2) end)
    b:SetScript("OnEnter", function(btn)
      btn:SetSize(23, 23)
      W.tip(btn, { T("inkTip", c.label), T("inkInsert", key) })
    end)
    b:SetScript("OnLeave", function(btn) btn:SetSize(20, 20) W.hideTip(btn) end)
    ui.inks[i] = b
  end
  local rule = toolSticker(self, bar, "rule", ix + 4 * 26 + 8, y2, acts.rule)
  ui.tools.rule = rule
  ui.symBtn = D.NewSticker(bar, T.symbols, function() self:ToggleSymbols() end, { height = 26, size = 15, tip = T.symbolsTip, tilt = 0 })
  place(ui.symBtn, bar, ix + 4 * 26 + 8 + (tonumber(rule:GetWidth()) or 70) + 4, y2)

  -- symbol slip: raid marks (row 1), map symbols (rows 2-3)
  local pop = CreateFrame("Frame", nil, right)
  pop:SetSize(8 * 30 + 20, 3 * 30 + 20)
  pop:SetPoint("TOPLEFT", ui.symBtn, "BOTTOMLEFT", -4, -2)
  if pop.SetFrameLevel then pop:SetFrameLevel((right:GetFrameLevel() or 1) + 30) end
  pop:EnableMouse(true)
  D.NewSlip(pop)
  D.escKeys(pop, function() self:ToggleSymbols(false) end)
  ui.symPop, ui.symBtns = pop, {}
  local function symButton(i, key, tipName, setTex)
    local b = CreateFrame("Button", nil, pop)
    b:SetSize(24, 24)
    local col, rowN = (i - 1) % 8, floor((i - 1) / 8)
    b:SetPoint("TOPLEFT", pop, "TOPLEFT", 10 + col * 30, -(10 + rowN * 30))
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints(b)
    setTex(t)
    b.tex, b.symKey = t, key
    b:SetScript("OnClick", function()
      W.call(self.InsertText, self, "{" .. key .. "}")
      self:ToggleSymbols(false)
    end)
    b:SetScript("OnEnter", function(btn) btn:SetSize(28, 28) W.tip(btn, { tipName, T("symInsert", key) }) end)
    b:SetScript("OnLeave", function(btn) btn:SetSize(24, 24) W.hideTip(btn) end)
    ui.symBtns[#ui.symBtns + 1] = b
  end
  for i, r in ipairs(M.RAID) do
    symButton(i, r.key, M.RAID_NAMES[i] or r.key, function(t) t:SetTexture(r.path) end)
  end
  for i, it in ipairs(M.ICONS) do
    symButton(8 + i, it.key, it.label, function(t)
      t:SetTexture(Theme.TEX.mapIcons)
      if Theme.mapIconCoords then
        local u0, u1, v0, v1 = Theme.mapIconCoords(it.icon)
        if u0 then t:SetTexCoord(u0, u1, v0, v1) end
      end
    end)
  end
  pop:Hide()
end

local function buildEditor(self, right)
  local ui = self.ui
  local h = Page.EDIT_BOTTOM - Page.EDIT_TOP
  local box = CreateFrame("Frame", nil, ui.bar)
  box:SetSize(RW, h)
  place(box, right, RX, Page.EDIT_TOP)
  box.edge = W.NewOutline(box, RW, h, "sepia", 0.55)
  box.edge:SetAllPoints(box)
  ui.editBox = box
  local sf = CreateFrame("ScrollFrame", nil, box)
  sf:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -6)
  sf:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 6)
  sf:EnableMouseWheel(true)
  ui.editScroll = sf
  local eb = CreateFrame("EditBox", nil, sf)
  eb:SetMultiLine(true)
  eb:SetAutoFocus(false)
  eb:SetMaxLetters(M.BODY_MAX)
  eb:SetWidth(RW - 14)
  eb:SetHeight(h - 12)
  pcall(eb.SetFont, eb, W.FONT.text, G.size.m, "")
  eb:SetTextColor(W.color("ink"))
  if eb.SetSpacing then eb:SetSpacing(3) end
  if eb.SetHyperlinksEnabled then eb:SetHyperlinksEnabled(true) end
  sf:SetScrollChild(eb)
  eb.hint = D.font(box, "text", G.size.m, "sepia")
  eb.hint:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -8)
  eb.hint:SetWidth(RW - 16)
  eb.hint:SetJustifyH("LEFT")
  eb.hint:SetWordWrap(true)
  eb.hint:SetText(T.bodyHint)
  eb.hint:SetAlpha(0.7)
  -- keep the cursor visible (line below/above the window -> scroll)
  eb:SetScript("OnCursorChanged", function(_, _, y, _, ch)
    local top = tonumber(sf:GetVerticalScroll()) or 0
    local viewH = tonumber(sf:GetHeight()) or (h - 12)
    y = -(tonumber(y) or 0)
    ch = tonumber(ch) or 16
    if y < top then sf:SetVerticalScroll(y) elseif y + ch > top + viewH then sf:SetVerticalScroll(y + ch - viewH) end
  end)
  sf:SetScript("OnMouseWheel", function(frame, delta)
    local range = frame.GetVerticalScrollRange and tonumber(frame:GetVerticalScrollRange()) or 0
    local v = (tonumber(frame:GetVerticalScroll()) or 0) - (tonumber(delta) or 0) * 40
    frame:SetVerticalScroll(max(0, min(range, v)))
  end)
  box:EnableMouse(true)
  box:SetScript("OnMouseDown", function() eb:SetFocus() end)
  eb:SetScript("OnTextChanged", function(e, userInput)
    local text = e:GetText()
    e.hint:SetShown(type(text) ~= "string" or text == "")
    self:UpdateCount()
    if userInput then self:ScheduleSave() end
  end)
  eb:SetScript("OnEditFocusLost", function() W.call(self.Save, self) end)
  eb:SetScript("OnEscapePressed", function(e) e:ClearFocus() end)
  ui.edit = eb
  ui.count = label(ui.bar, "label", G.size.xs, "sepia", "RIGHT")
  ui.count:SetWidth(90)
  ui.count:SetPoint("TOPRIGHT", right, "TOPLEFT", RX + RW, -(Page.EDIT_BOTTOM + 2))
end

local function buildReader(self, right)
  local ui = self.ui
  local h = Page.EDIT_BOTTOM - Page.READ_TOP
  local sf = CreateFrame("ScrollFrame", nil, right)
  sf:SetSize(RW, h)
  place(sf, right, RX, Page.READ_TOP)
  sf:EnableMouseWheel(true)
  local content = CreateFrame("Frame", nil, sf)
  content:SetSize(RW, h)
  sf:SetScrollChild(content)
  sf:SetScript("OnMouseWheel", function(frame, delta)
    local range = max(0, (self.readHeight or 0) - h)
    local v = (tonumber(frame:GetVerticalScroll()) or 0) - (tonumber(delta) or 0) * 40
    frame:SetVerticalScroll(max(0, min(range, v)))
  end)
  ui.read, ui.readContent, ui.readRows = sf, content, {}
  ui.readEmpty = label(right, "text", G.size.m, "sepia")
  ui.readEmpty:SetWidth(RW)
  ui.readEmpty:SetWordWrap(true)
  place(ui.readEmpty, right, RX, Page.READ_TOP + 8)
end

-- row of the read view (pool): frame with links (tooltip/click), text, check button, rule
local function readRow(self, i)
  local ui = self.ui
  local row = ui.readRows[i]
  if row then return row end
  if i > Page.READ_ROWS_MAX then return nil end
  row = CreateFrame("Frame", nil, ui.readContent)
  row:SetWidth(RW)
  if row.SetHyperlinksEnabled then row:SetHyperlinksEnabled(true) end
  row:SetScript("OnHyperlinkEnter", function(r, link) self:LinkEnter(r, link) end)
  row:SetScript("OnHyperlinkLeave", function(r) W.hideTip(r) W.hideItemTip(r) end)
  row:SetScript("OnHyperlinkClick", function(_, link, text, button) self:LinkClick(link, text, button) end)
  row.text = W.font(row, "text", G.size.m, "ink")
  row.text:SetJustifyH("LEFT")
  row.text:SetWordWrap(true)
  -- wrap long words without spaces (links, typing chains) instead of cutting them with "..."
  if row.text.SetNonSpaceWrap then row.text:SetNonSpaceWrap(true) end
  if row.text.SetSpacing then row.text:SetSpacing(2) end
  local cb = CreateFrame("Button", nil, row)
  cb:SetSize(22, 22)
  cb:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 2)
  cb.box = D.mark(cb, "box", 18, "ink")
  cb.box:SetPoint("CENTER", cb, "CENTER", 0, 0)
  cb.tick = D.mark(cb, "tick", 24, "red", "OVERLAY")
  cb.tick:SetPoint("CENTER", cb.box, "CENTER", 4, 4)
  cb:SetScript("OnClick", function(b) if b.line then W.call(self.ToggleCheck, self, b.line) end end)
  cb:SetScript("OnEnter", function(b)
    b.box:SetVertexColor(W.color("red", b.box.diaryOk and 1 or 0.25))
    W.tip(b, { b.checked and T.reopen or T.tick })
  end)
  cb:SetScript("OnLeave", function(b)
    b.box:SetVertexColor(W.color("ink", b.box.diaryOk and 1 or 0.25))
    W.hideTip(b)
  end)
  row.check = cb
  row.rule = W.NewRect(row, "sepia", 0.6, "ARTWORK")
  row.rule:SetHeight(1)
  row.rule:SetPoint("LEFT", row, "LEFT", 20, 0)
  row.rule:SetPoint("RIGHT", row, "RIGHT", -20, 0)
  ui.readRows[i] = row
  return row
end

local function buildRight(self, right)
  local ui = self.ui
  ui.headR = W.NewPageHead(right, { side = "R" })
  ui.headR:SetTexts("", T.page)
  ui.noteTitle = label(right, "title", G.size.xl, "ink")
  ui.noteTitle:SetWidth(RW - 12)
  place(ui.noteTitle, right, RX, TITLE_Y)
  -- title in edit mode
  local tb = CreateFrame("EditBox", nil, right)
  tb:SetSize(RW - 12, 32)
  place(tb, right, RX, TITLE_Y - 2)
  tb:SetAutoFocus(false)
  tb:SetMaxLetters(M.TITLE_MAX)
  tb:SetTextInsets(6, 6, 0, 0)
  pcall(tb.SetFont, tb, W.FONT.title, 22, "")
  tb:SetTextColor(W.color("ink"))
  tb.line = W.NewRect(tb, "sepia", 0.7, "ARTWORK")
  tb.line:SetHeight(1)
  tb.line:SetPoint("BOTTOMLEFT", tb, "BOTTOMLEFT", 0, 0)
  tb.line:SetPoint("BOTTOMRIGHT", tb, "BOTTOMRIGHT", 0, 0)
  tb.hint = D.font(tb, "title", 22, "sepia")
  tb.hint:SetPoint("LEFT", tb, "LEFT", 6, 0)
  tb.hint:SetText(T.titleHint)
  tb.hint:SetAlpha(0.6)
  tb:SetScript("OnTextChanged", function(box, userInput)
    local text = box:GetText()
    box.hint:SetShown(type(text) ~= "string" or text == "")
    if userInput then self:ScheduleSave() end
  end)
  tb:SetScript("OnEditFocusLost", function() W.call(self.Save, self) end)
  tb:SetScript("OnEnterPressed", function() ui.edit:SetFocus() end)
  tb:SetScript("OnTabPressed", function() ui.edit:SetFocus() end)
  tb:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
  ui.titleEdit = tb
  ui.meta = label(right, "label", G.size.s, "sepia")
  ui.meta:SetWidth(RW - 12)
  place(ui.meta, right, RX, SUB_Y)

  ui.mode = D.NewToggle(right, { size = G.size.m, gap = 14, value = self.mode,
    items = { { key = "edit", label = T.edit, tip = T.editTip }, { key = "read", label = T.read, tip = T.readTip } },
    onChange = function(key) self:SetMode(key) end })
  ui.mode.frame:SetPoint("LEFT", right, "TOPLEFT", RX - 3, -CTRL_CY)
  ui.onMap = D.NewCheck(right, T.onMap, { size = G.size.m, tip = T.onMapTip, onChange = function(on, b) self:SetOnMap(on, b) end })
  ui.onMap:SetPoint("RIGHT", right, "TOPLEFT", RX + RW, -CTRL_CY)
  ui.pin = D.NewCheck(right, T.pin, { size = G.size.m, tip = T.pinTip, onChange = function(on) self:SetPinned(on) end })
  ui.pin:SetPoint("RIGHT", ui.onMap, "LEFT", -14, 0)

  buildToolbar(self, right)
  buildEditor(self, right)
  buildReader(self, right)

  -- footer right: delete at the right end (the thumbprint is bottom left)
  ui.del = D.NewSticker(right, T.delete, function() self:Delete() end, { height = 30, size = 18, tip = T.deleteTip })
  ui.del:SetPoint("TOPRIGHT", right, "TOPLEFT", RX + RW, -(FOOT_Y - 2))

  ui.pick = label(right, "title", G.size.l, "sepia", "CENTER")
  ui.pick:SetWidth(RW - 40)
  ui.pick:SetWordWrap(true)
  ui.pick:SetText(T.pickNote)
  ui.pick:SetPoint("TOP", right, "TOPLEFT", RX + RW / 2, -260)
end

-- links: ChatEdit_InsertLink / HandleModifiedItemClick while the note box has focus

local lastLink, lastLinkT
local function onInsertLink(link)
  local ui = Page.ui
  local eb = ui and ui.edit
  if not (eb and eb.HasFocus and eb:HasFocus()) then return end
  if type(link) ~= "string" then return end
  local t = type(GetTime) == "function" and GetTime() or 0
  if link == lastLink and t == lastLinkT then return end -- the same click arrived via both hooks
  lastLink, lastLinkT = link, t
  local canon = M.canonLink(link)
  if not canon then
    Page:Message(T.linkType)
    return
  end
  Page:InsertText(canon)
end
Page.onInsertLink = onInsertLink

local hooked = false
local function hookLinks()
  if hooked or type(hooksecurefunc) ~= "function" then return end
  hooked = true
  if type(ChatEdit_InsertLink) == "function" then
    hooksecurefunc("ChatEdit_InsertLink", function(link) W.call(onInsertLink, link) end)
  end
  if type(HandleModifiedItemClick) == "function" then
    hooksecurefunc("HandleModifiedItemClick", function(link)
      if type(IsModifiedClick) == "function" and not IsModifiedClick("CHATLINK") then return end
      W.call(onInsertLink, link)
    end)
  end
end

function Page:LinkEnter(row, link)
  if type(link) ~= "string" then return end
  local ltype = link:match("^(%a+):")
  if not (ltype and M.LINK_TYPES[ltype]) then return end
  if not W.itemTip(row, link) then W.tip(row, { T.linkType }) end
end

function Page:LinkClick(link, text, button)
  if type(link) ~= "string" then return end
  local ltype = link:match("^(%a+):")
  if not (ltype and M.LINK_TYPES[ltype]) then return end
  if type(SetItemRef) == "function" then pcall(SetItemRef, link, text, button) end
end

function Page.Build(self, left, right)
  self.left, self.right = left, right
  self.ui = {}
  self.sort, self.query, self.pageNo, self.mode = "new", "", 1, "read"
  buildLeft(self, left)
  buildRight(self, right)
  left:EnableMouseWheel(true)
  left:SetScript("OnMouseWheel", function(_, delta)
    delta = tonumber(delta) or 0
    if delta == 0 then return end
    local ok, err = pcall(self.Step, self, delta < 0 and 1 or -1)
    if not ok then Pages.fail("notizen", err) end
  end)
  hookLinks()
  local QN = Journal.QuickNote
  if QN and QN.listeners then QN.listeners[#QN.listeners + 1] = function() self:PaintQuick() end end
  -- changes to the notes (also from outside, e.g. quick note): redraw the visible page at once. Render writes nothing
  -- back (no loop);
  -- in edit mode only the list, so input and cursor stay
  if not self.notesHooked and type(Notes.onChange) == "function" then
    self.notesHooked = true
    Notes.onChange(function() self:OnNotesChanged() end)
  end
end

function Page:OnNotesChanged()
  if self.rendering or not self.ui then return end
  if not (Pages.current and Pages.current() == "notizen") then return end
  if not (self.left and self.left.IsVisible and self.left:IsVisible()) then return end
  self.rendering = true
  local ok, err
  if self.mode == "edit" then
    ok, err = pcall(self.RenderList, self)
  else
    if not self.sel and Notes.ready() then
      local list = self:List()
      if list[1] then self.sel, self.mode = list[1].id, "read" end
    end
    ok, err = pcall(self.Render, self)
  end
  self.rendering = false
  if not ok then Pages.fail("notizen", err) end
end

function Page:Message(text)
  if self.ui and self.ui.msg then W.setText(self.ui.msg, text or "") end
end

function Page:List()
  return Notes.list({ query = self.query, sort = self.sort })
end

function Page:Pages(list)
  return max(1, ceil(#(list or self:List()) / Page.ROWS))
end

function Page:Step(dir)
  local pages = self:Pages()
  self.pageNo = max(1, min(pages, (self.pageNo or 1) + dir))
  self:RenderList()
end

function Page:SetSort(value)
  self.sort = (value == "old" or value == "title") and value or "new"
  self.pageNo = 1
  self:RenderList()
end

function Page:SetQuery(text, clearField)
  if type(text) ~= "string" then text = "" end
  self.query = text
  self.pageNo = 1
  if clearField and self.ui.search then
    self.ui.search:SetText("")
    self.ui.search.hint:Show()
    self.ui.clear:Hide()
  end
  self:RenderList()
end

-- show a note (click in the list); saves the previous one
function Page:Select(id, mode)
  self:Save()
  self:ResetConfirm()
  self.sel = id
  self.mode = mode or "read"
  self:ToggleSymbols(false)
  self:Render()
end

-- from outside (pin): open note id, clear the search, show the sheet with it
function Page:Open(id)
  if not self.ui or not Notes.get(id) then return false end
  self:SetQuery("", true)
  local list = self:List()
  for i, n in ipairs(list) do
    if n.id == id then self.pageNo = ceil(i / Page.ROWS) end
  end
  self:Select(id, "read")
  return true
end

function Page:New()
  self:Save()
  local id, why = Notes.create({})
  if not id then
    self:Message(why == "voll" and string.format(T.full, Notes.MAX) or T.notReady)
    return false
  end
  self:Message("")
  if self.query ~= "" then self:SetQuery("", true) end
  self.pageNo = 1
  self:Select(id, "edit")
  local list = self:List()
  for i, n in ipairs(list) do
    if n.id == id then self.pageNo = ceil(i / Page.ROWS) end
  end
  self:RenderList()
  if self.ui.edit and self.ui.edit.SetFocus then self.ui.edit:SetFocus() end
  return true
end

function Page:SetMode(key)
  if key ~= "edit" and key ~= "read" then return end
  self:Save()
  self.mode = key
  self:ToggleSymbols(false)
  self:RenderNote()
end

function Page:ScheduleSave()
  self.saveSeq = (self.saveSeq or 0) + 1
  self.dirty = true
  local seq = self.saveSeq
  timer(Page.SAVE_DELAY, function()
    if seq == self.saveSeq then W.call(self.Save, self) end
  end)
end

-- save the edit content (edit mode only and only with a change); update the list, the box stays untouched
function Page:Save()
  if not (self.ui and self.sel and self.mode == "edit" and self.dirty) then return false end
  self.dirty = false
  self.saveSeq = (self.saveSeq or 0) + 1
  local ok = Notes.update(self.sel, { title = self.ui.titleEdit:GetText() or "", body = self.ui.edit:GetText() or "" })
  if ok then
    self:RenderList()
    self:RenderMeta(Notes.get(self.sel))
  end
  return ok
end

function Page:UpdateCount()
  local ui = self.ui
  local n = M.chars(ui.edit:GetText() or "")
  W.setText(ui.count, string.format(T.chars, n, M.BODY_MAX))
  ui.count:SetTextColor(W.color(n >= M.BODY_MAX and "red" or "sepia"))
end

-- insert text at the cursor; cursorAt = cursor after it relative to the insertion point (default: behind the text)
function Page:InsertText(text, cursorAt)
  local ui = self.ui
  if not (ui and self.sel and self.mode == "edit" and type(text) == "string") then return false end
  local eb = ui.edit
  local cur = eb:GetText() or ""
  if M.chars(cur) + M.chars(text) > M.BODY_MAX then
    self:Message(string.format(T.tooLong, M.BODY_MAX))
    return false
  end
  local pos = tonumber(eb:GetCursorPosition()) or #cur
  pos = max(0, min(#cur, floor(pos)))
  eb:SetText(cur:sub(1, pos) .. text .. cur:sub(pos + 1))
  eb:SetCursorPosition(pos + (cursorAt or #text))
  eb:SetFocus()
  self:Message("")
  self:UpdateCount()
  self:ScheduleSave()
  return true
end

-- line start of the cursor: set the prefix or remove it again (already there); other line prefixes are replaced
local PREFIXES = { "# ", "- ", "[ ] ", "[x] ", "[X] " }
function Page:LinePrefix(prefix)
  local ui = self.ui
  if not (ui and self.sel and self.mode == "edit") then return false end
  local eb = ui.edit
  local cur = eb:GetText() or ""
  local pos = max(0, min(#cur, floor(tonumber(eb:GetCursorPosition()) or #cur)))
  local start = 1
  for i = pos, 1, -1 do
    if cur:sub(i, i) == "\n" then start = i + 1 break end
  end
  local rest = cur:sub(start)
  local had
  for _, p in ipairs(PREFIXES) do
    if rest:sub(1, #p) == p then had = p break end
  end
  local newLine
  if had == prefix or (had and prefix == "[ ] " and had:match("^%[")) then
    newLine = rest:sub(#had + 1)
  else
    newLine = prefix .. (had and rest:sub(#had + 1) or rest)
  end
  local text = cur:sub(1, start - 1) .. newLine
  if M.chars(text) > M.BODY_MAX then
    self:Message(string.format(T.tooLong, M.BODY_MAX))
    return false
  end
  eb:SetText(text)
  eb:SetCursorPosition(max(start - 1, pos + (#text - #cur)))
  eb:SetFocus()
  self:UpdateCount()
  self:ScheduleSave()
  return true
end

function Page:InsertRule()
  local eb = self.ui and self.ui.edit
  if not eb then return false end
  local cur = eb:GetText() or ""
  local pos = max(0, min(#cur, floor(tonumber(eb:GetCursorPosition()) or #cur)))
  local atStart = pos == 0 or cur:sub(pos, pos) == "\n"
  return self:InsertText((atStart and "" or "\n") .. "---\n")
end

function Page:ToggleSymbols(on)
  local pop = self.ui and self.ui.symPop
  if not pop then return end
  if on == nil then on = not pop:IsShown() end
  pop:SetShown(on and self.mode == "edit" and self.sel ~= nil)
end

function Page:SetPinned(on)
  if not self.sel then return end
  Notes.setPinned(self.sel, on)
  self:RenderList()
end

function Page:SetOnMap(on, box)
  if not self.sel then return end
  local ok, why = Notes.setOnMap(self.sel, on)
  if not ok then
    if box then box:SetChecked(false, true) end
    if why == "kein-ort" then self:Message(T.noPlace) end
    return
  end
  self:Message("")
end

function Page:ToggleCheck(line)
  if not self.sel then return end
  if Notes.toggleCheck(self.sel, line) then
    self:RenderNote()
    self:RenderList()
  end
end

function Page:ResetConfirm()
  self.confirmUntil = nil
  if self.ui and self.ui.del then
    self.ui.del:SetLabel(T.delete)
    self.ui.del:ClearAllPoints()
    self.ui.del:SetPoint("TOPRIGHT", self.right, "TOPLEFT", RX + RW, -(FOOT_Y - 2))
  end
end

-- delete: the first click asks ("Wirklich löschen?"), a second within Page.CONFIRM_TIME deletes
function Page:Delete()
  if not self.sel then return false end
  local t = type(GetTime) == "function" and GetTime() or 0
  if not self.confirmUntil or t > self.confirmUntil then
    self.confirmUntil = t + Page.CONFIRM_TIME
    self.ui.del:SetLabel(T.confirm)
    local seq = (self.confirmSeq or 0) + 1
    self.confirmSeq = seq
    timer(Page.CONFIRM_TIME, function() if self.confirmSeq == seq and self.confirmUntil then self:ResetConfirm() end end)
    return false
  end
  local id = self.sel
  local list = self:List()
  local nextId
  for i, n in ipairs(list) do
    if n.id == id then nextId = (list[i + 1] or list[i - 1] or {}).id end
  end
  self.dirty = false
  Notes.remove(id)
  self:ResetConfirm()
  self.sel = nextId
  self.mode = "read"
  self:Render()
  return true
end

function Page:RenderList()
  local ui = self.ui
  if not ui then return end
  local ready = Notes.ready()
  local list = ready and self:List() or {}
  local total = ready and Notes.count() or 0
  local pages = max(1, ceil(#list / Page.ROWS))
  self.pageNo = max(1, min(pages, self.pageNo or 1))
  local pinned, last = 0, nil
  for _, n in ipairs(list) do
    if n.pinned then pinned = pinned + 1 end
    if not last or (n.updated or 0) > last then last = n.updated end
  end
  W.setText(ui.title, ready and (tostring(total) .. " " .. (total == 1 and T.note or T.notes)) or T.notes)
  local bits = {}
  if pinned > 0 then bits[#bits + 1] = string.format(T.pinnedN, pinned) end
  if last and self.query == "" then bits[#bits + 1] = string.format(T.lastEdit, when(last) or "") end
  W.setText(ui.sub, table.concat(bits, " · "))
  local from = (self.pageNo - 1) * Page.ROWS
  for i, row in ipairs(ui.rows) do
    local n = list[from + i]
    if n then
      row.noteId = n.id
      W.setText(row.label, noteTitle(n))
      local sub = {}
      local d = when(n.updated or n.created)
      if d then sub[#sub + 1] = d end
      local z = n.zone and shown(n.zone, 60)
      if z then sub[#sub + 1] = z end
      W.setText(row.sub, table.concat(sub, " · "))
      row.pin:SetShown(n.pinned)
      row:SetSelected(n.id == self.sel)
      row:Show()
      D.rowFilled(row)
    else
      row.noteId = nil
      row:SetSelected(false)
      row:Hide()
    end
  end
  local none = #list == 0
  ui.empty:SetShown(none)
  ui.emptyBody:SetShown(none and (not ready or total == 0))
  W.setText(ui.empty, (not ready and T.noChar) or (total == 0 and T.emptyList) or T.noMatch)
  W.setText(ui.emptyBody, ready and T.emptyListBody or "")
  ui.pair.frame:SetShown(pages > 1)
  ui.nav:SetShown(pages > 1)
  ui.pair:SetEnabled(self.pageNo > 1, self.pageNo < pages)
  W.setText(ui.nav, string.format(T.pageOf, self.pageNo, pages))
  ui.search:SetShown(ready and (total > 0 or self.query ~= ""))
  ui.sortDrop:SetShown(ready and total > 1)
  if ui.newBtn.SetEnabled then ui.newBtn:SetEnabled(ready) end
  local items = {}
  for i, s in ipairs(SORTS) do
    items[i] = { text = s.text, value = s.value, active = s.value == self.sort }
    if s.value == self.sort then ui.sortDrop:SetText(s.text) end
  end
  ui.sortDrop:SetItems(items)
end

function Page:RenderMeta(n)
  local ui = self.ui
  if not n then W.setText(ui.meta, "") return end
  local bits = {}
  local c = when(n.created)
  if c then bits[#bits + 1] = string.format(T.created, c) end
  local z = n.zone and shown(n.zone, 60)
  if z then bits[#bits + 1] = z end
  if type(n.level) == "number" then bits[#bits + 1] = string.format(T.levelW, floor(n.level)) end
  if (n.updated or 0) > (n.created or 0) + 59 then
    local u = when(n.updated)
    if u then bits[#bits + 1] = string.format(T.changed, u) end
  end
  W.setText(ui.meta, table.concat(bits, " · "))
end

-- read view: blocks from NoteMarkup.render one under the other (pool), height from text measurement
function Page:RenderRead(n)
  local ui = self.ui
  local blocks = M.render(n.body)
  local y, k = 0, 0
  local size = G.size.m
  local any = false
  for _, b in ipairs(blocks) do
    local row = readRow(self, k + 1)
    if not row then
      local tail = readRow(self, k)
      if tail then
        tail.text:SetText((tail.text:GetText() or "") .. "\n" .. T.truncated)
      end
      break
    end
    k = k + 1
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", ui.readContent, "TOPLEFT", 0, -y)
    row.check:Hide()
    row.rule:Hide()
    row.text:ClearAllPoints()
    local h
    if b.kind == "rule" then
      row.text:SetText("")
      row.rule:Show()
      h = 14
    elseif b.kind == "blank" then
      row.text:SetText("")
      h = floor(size * 0.7)
    else
      any = true
      local indent, fsize, font = 0, size, W.FONT.text
      local text = b.display
      if b.kind == "head" then
        fsize, font = G.size.l, W.FONT.title
      elseif b.kind == "bullet" then
        text = "–  " .. text -- bullet: en dash (exists in all client fonts)
        indent = 8
      elseif b.kind == "check" then
        indent = 26
        row.check.line, row.check.checked = b.line, b.checked
        row.check.tick:SetShown(b.checked and true or false)
        row.check:Show()
      end
      pcall(row.text.SetFont, row.text, font, fsize, "")
      row.text:SetTextColor(W.color((b.kind == "check" and b.checked) and "sepia" or "ink"))
      row.text:SetPoint("TOPLEFT", row, "TOPLEFT", indent, 0)
      row.text:SetWidth(RW - indent - 6)
      row.text:SetText(text)
      local sh = tonumber(row.text:GetStringHeight()) or fsize
      h = max(sh, b.kind == "check" and 20 or fsize) + (b.kind == "head" and 8 or 4)
    end
    row:SetHeight(h)
    row:Show()
    y = y + h
  end
  for i = k + 1, #ui.readRows do ui.readRows[i]:Hide() end
  self.readHeight = y
  ui.readContent:SetHeight(max(y, 10))
  ui.read:SetVerticalScroll(0)
  ui.readEmpty:SetShown(not any)
  W.setText(ui.readEmpty, any and "" or T.emptyRead)
end

function Page:RenderNote()
  local ui = self.ui
  local n = self.sel and Notes.get(self.sel) or nil
  if self.sel and not n then self.sel = nil end
  local has = n ~= nil
  local edit = has and self.mode == "edit"
  ui.pick:SetShown(not has and Notes.ready())
  ui.mode.frame:SetShown(has)
  ui.pin:SetShown(has)
  ui.onMap:SetShown(has)
  ui.del:SetShown(has)
  ui.noteTitle:SetShown(has and not edit)
  ui.titleEdit:SetShown(edit)
  ui.bar:SetShown(edit)
  ui.read:SetShown(has and not edit)
  ui.readEmpty:SetShown(false)
  if not has then
    W.setText(ui.noteTitle, "")
    self:RenderMeta(nil)
    if ui.edit.ClearFocus then ui.edit:ClearFocus() end
    return
  end
  ui.mode:SetValue(self.mode)
  ui.pin:SetChecked(n.pinned, true)
  ui.onMap:SetChecked(n.onMap, true)
  ui.onMap:SetEnabled(type(n.mapID) == "number" and type(n.x) == "number")
  W.setText(ui.noteTitle, noteTitle(n))
  self:RenderMeta(n)
  if edit then
    -- stored form into the box (links/"||" stay, as the client writes them itself)
    ui.titleEdit:SetText(n.title or "")
    ui.titleEdit.hint:SetShown((n.title or "") == "")
    ui.edit:SetText(n.body or "")
    ui.edit.hint:SetShown((n.body or "") == "")
    if ui.edit.SetCursorPosition then ui.edit:SetCursorPosition(#(n.body or "")) end
    ui.editScroll:SetVerticalScroll(0)
    self.dirty = false
    self:UpdateCount()
  else
    if ui.edit.ClearFocus then ui.edit:ClearFocus() end
    if ui.titleEdit.ClearFocus then ui.titleEdit:ClearFocus() end
    self:RenderRead(n)
  end
end

local function playerLine(self)
  local Store = ns.Store
  local char = Store and Store.char and Store.char() or nil
  return W.playerLine({ char = char, live = self.data and self.data.live }) or ""
end

-- check "Schnellnotizen" per the setting (QuickNote.settings); without the module it does not exist
function Page:PaintQuick()
  local b = self.ui and self.ui.quick
  if not b then return end
  local QN = Journal.QuickNote
  local ok = QN ~= nil and type(QN.settings) == "function"
  b:SetShown(ok)
  if ok then b:SetChecked(QN.settings().shown == true, true) end
end

function Page:SetQuick(on)
  local QN = Journal.QuickNote
  if QN and type(QN.setShown) == "function" then QN.setShown(on and true or false) end
  self:PaintQuick()
end

function Page:Render()
  if not self.ui then return end
  self:PaintQuick()
  self.ui.headR:SetTexts(playerLine(self), T.page)
  self:RenderList()
  self:RenderNote()
end

function Page.Refresh(self, data)
  self.data = data
  -- on open: preselect the first note of the list
  if not self.sel and Notes.ready() then
    local list = self:List()
    if list[1] then self.sel, self.mode = list[1].id, "read" end
  end
  self:Render()
end

function Page.OnHide(self)
  local ui = self.ui
  if not ui then return end
  W.call(self.Save, self)
  self:ResetConfirm()
  self:ToggleSymbols(false)
  if ui.edit.ClearFocus then ui.edit:ClearFocus() end
  if ui.titleEdit.ClearFocus then ui.titleEdit:ClearFocus() end
  if ui.search.ClearFocus then ui.search:ClearFocus() end
  if ui.sortDrop:IsOpen() then ui.sortDrop:Close() end
  for _, row in ipairs(ui.rows) do W.hideTip(row) end
  for _, row in ipairs(ui.readRows) do W.hideTip(row) W.hideItemTip(row) end
  W.hideTip(ui.pair.prev)
  W.hideTip(ui.pair.next)
end

Pages.register("notizen", Page)
