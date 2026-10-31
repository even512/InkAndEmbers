-- Debug window for the campfire simulation (/chronik sim): toggle the sim, sit/stand, add/remove fake guests, lines
-- local or loud, test notes, delete trial rounds, live status line. Only a UI: it calls the ns.Campfire interface.
local _, ns = ...

local floor, max, min = math.floor, math.max, math.min
local format = string.format

local SimPanel = {}
ns.SimPanel = SimPanel

SimPanel.NAME = "EveNChronicleSimPanel"
SimPanel.W, SimPanel.H = 344, 486
SimPanel.REFRESH = 0.5
SimPanel.ROUNDS_EVERY = 5

local T = ns.Locale.ns("SimPanel", {
  title = "Lagerfeuer-Simulation",
  simOn = "Simulation an",
  simOnTip = { "Simulation", "Retail hat keine Lagerfeuer-Sitzabfrage. Mit der Simulation zählt Hinsetzen als Probe-Runde. Gilt bis zum Neuladen." },
  sit = "Hinsetzen",
  stand = "Aufstehen",
  guestHead = "Schein-Gast",
  name = "Name",
  random = "Zufall",
  randomTip = { "Zufälliger Name", "Setzt einen Vorschlag ins Namensfeld." },
  class = "Klasse",
  level = "Stufe",
  levelN = "Stufe %s",
  sex = "Geschlecht",
  add = "Gast hinzufügen",
  guests = "Gäste (%d/%d)",
  noGuests = "Noch keine Gäste.",
  remove = "×",
  removeTip = { "Gast entfernen" },
  pick = "Klick wählt den Gast für „Gast sagt etwas“.",
  sayText = "Guten Abend zusammen!",
  sayBtn = "Gast sagt etwas",
  sayWait = { "Gast sagt etwas", "kommt mit dem Gesprächsfluss" },
  sayNeed = { "Gast sagt etwas", "Erst die Simulation einschalten und einen Gast hinzufügen." },
  sayTip = { "Gast sagt etwas", "Der gewählte Gast spricht den Text im Feld daneben." },
  loud = "laut senden",
  loudTip = { "Laut senden", "Aus: Sätze erscheinen nur als lokale Chatzeile [Sim]. An: sie gehen wirklich in /sagen." },
  test = "Testzettel zeigen",
  drop = "Probe-Runden löschen",
  dropAsk = "Alle Probe-Runden wirklich löschen?",
  yes = "Ja",
  no = "Nein",
  close = "Schließen",
  msgNeedSim = "Erst die Simulation einschalten.",
  msgSitOk = "Probe-Runde läuft: Ihr sitzt am (simulierten) Feuer.",
  msgRunning = "Es läuft schon eine Runde.",
  msgSitNo = "Hinsetzen geht gerade nicht (%s).",
  msgStandOk = "Aufgestanden.",
  msgStandNo = "Es läuft keine Runde.",
  msgGuestOk = "Gast %s sitzt mit am Feuer.",
  msgGuestNo = "Gast: %s",
  msgGuestGone = "Gast %s entfernt.",
  msgGoneWait = "Gast entfernen geht erst nach dem Aufstehen.",
  msgSaid = "%s hat etwas gesagt.",
  msgSayNo = "Gast sagt etwas: %s",
  msgDropped = "%d Probe-Runden entfernt, echte Runden bleiben.",
  msgNoCampfire = "Der Sammler Lagerfeuer ist nicht geladen.",
  simOnLabel = "Simulation: an",
  simOffLabel = "Simulation: aus",
  noSession = "Sitzung: keine",
  session = "Sitzung: läuft seit %s",
  people = "Personen am Feuer: %d",
  rounds = "Runden gespeichert: %d (Probe: %d)",
  roundsNone = "Runden gespeichert: -",
  sexAuto = "automatisch",
  sexM = "männlich",
  sexW = "weiblich",
  whyNotReady = "nicht bereit",
  whyCombat = "Kampf",
  whyMounted = "beritten",
  classes = {
    WARRIOR = "Krieger", PALADIN = "Paladin", HUNTER = "Jäger", ROGUE = "Schurke", PRIEST = "Priester",
    DEATHKNIGHT = "Todesritter", SHAMAN = "Schamane", MAGE = "Magier", WARLOCK = "Hexenmeister", MONK = "Mönch",
    DRUID = "Druide", DEMONHUNTER = "Dämonenjäger", EVOKER = "Rufer",
  },
})
SimPanel.TEXT = T

SimPanel.CLASSES = {
  { "WARRIOR" }, { "PALADIN" }, { "HUNTER" }, { "ROGUE" }, { "PRIEST" }, { "DEATHKNIGHT" }, { "SHAMAN" }, { "MAGE" },
  { "WARLOCK" }, { "MONK" }, { "DRUID" }, { "DEMONHUNTER" }, { "EVOKER" },
}
SimPanel.SEXES = { { nil, "sexAuto" }, { "m", "sexM" }, { "w", "sexW" } }

SimPanel.NAMES = { "Alrik", "Brunhild", "Cedric", "Dorothea", "Eberhard", "Fenja", "Gundolf", "Hilde", "Ingmar", "Jorina",
  "Kaspar", "Liesl", "Mirko", "Nadine", "Oswin", "Perdita", "Quirin", "Rosalind", "Sigurd", "Thea", "Ulfred", "Vanessa",
  "Wulfgar", "Xenia", "Ysolde", "Zorn" }

local ROWS = 5
local st = {}
SimPanel.state = st

local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end
local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end
local function CF() return ns.Campfire end
local function safe(fn, ...)
  if ns.Core and ns.Core.safe then return ns.Core.safe(fn, ...) end
  return pcall(fn, ...)
end
local function display(s)
  if ns.Sanitize and ns.Sanitize.display then return ns.Sanitize.display(s) end
  return tostring(s):gsub("|", "||")
end

local function classText(file)
  local names = T.classes
  return type(names) == "table" and names[file] or tostring(file)
end

local function sexText(key)
  for _, s in ipairs(SimPanel.SEXES) do
    if s[1] == key then return T[s[2]] end
  end
  return T.sexAuto
end

local function uiTable(create)
  local db = rawget(_G, "EveNChronicleDB")
  if type(db) ~= "table" or isSecret(db) then return nil end
  local ui = db.ui
  if type(ui) ~= "table" or isSecret(ui) then
    if not create then return nil end
    ui = {}
    db.ui = ui
  end
  local p = ui.simPanel
  if type(p) ~= "table" or isSecret(p) then
    if not create then return nil end
    p = {}
    ui.simPanel = p
  end
  return p
end

function SimPanel.pos()
  local p = uiTable(false)
  if p and num(p.x) and num(p.y) and math.abs(p.x) <= 10000 and math.abs(p.y) <= 10000 then return p.x, p.y end
  return nil
end

local function screen()
  local w = UIParent and UIParent.GetWidth and num(UIParent:GetWidth()) or 1920
  local h = UIParent and UIParent.GetHeight and num(UIParent:GetHeight()) or 1080
  return w, h
end

local function clampPos(x, y)
  local sw, sh = screen()
  x = max(0, min(x, max(0, sw - SimPanel.W)))
  y = max(SimPanel.H, min(y, sh))
  return x, y
end

function SimPanel.place()
  local f = st.frame
  if not f then return end
  local x, y = SimPanel.pos()
  if not x then
    local sw, sh = screen()
    x, y = 60, sh - 120
    if sw < x + SimPanel.W then x = 0 end
  end
  x, y = clampPos(x, y)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
end

local function savePos(f)
  local l, t = num(f:GetLeft()), num(f:GetTop())
  if not l or not t then return end
  local x, y = clampPos(l, t)
  local p = uiTable(true)
  if p then p.x, p.y = x, y end
end

local function tip(owner, lines)
  if not (GameTooltip and lines) then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:AddLine(lines[1], 1, 0.82, 0)
  if lines[2] then GameTooltip:AddLine(lines[2], 0.8, 0.8, 0.8, true) end
  GameTooltip:Show()
end

local function withTip(frame, lines)
  frame.tipLines = lines
  frame:SetScript("OnEnter", function(self) tip(self, self.tipLines) end)
  frame:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local function label(parent, font, x, y, text, width)
  local fs = parent:CreateFontString(nil, "OVERLAY", font)
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  if width then fs:SetWidth(width) end
  if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
  if text then fs:SetText(text) end
  return fs
end

local function button(parent, text, x, y, w, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, 22)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  b:SetText(text)
  b.enabled = true
  b:SetScript("OnClick", function(self, ...)
    if self.enabled == false then return end
    safe(onClick, self, ...)
  end)
  return b
end

local function setEnabled(b, on, tipOn, tipOff)
  on = on and true or false
  if b.SetEnabled then b:SetEnabled(on) end
  b.enabled = on
  b.tipLines = on and tipOn or tipOff or tipOn
end

local function check(parent, text, x, y, onClick)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  cb.enabled = true
  cb.checked = false
  local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  fs:SetText(text)
  cb.label = fs
  cb:SetScript("OnClick", function(self)
    if self.enabled == false then return end
    safe(onClick, self)
  end)
  return cb
end

local function setChecked(cb, on)
  cb.checked = on and true or false
  if cb.SetChecked then cb:SetChecked(cb.checked) end
end

local function editBox(parent, x, y, w, maxLetters)
  local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  eb:SetSize(w, 20)
  eb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  eb:SetAutoFocus(false)
  eb:SetMaxLetters(maxLetters)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return eb
end

local function message(text)
  st.msg = text
  if st.msgFs then st.msgFs:SetText(text or "") end
end

local refresh

local function needCampfire()
  if CF() then return true end
  message(T.msgNoCampfire)
  return false
end

function SimPanel.setSim(on)
  if not needCampfire() then return end
  CF().setSim(on == true)
  refresh(true)
end

function SimPanel.sit()
  if not needCampfire() then return end
  local C = CF()
  if not C.isSim() then message(T.msgNeedSim) return end
  local ok, why = C.simSit()
  if ok then
    message(T.msgSitOk)
  elseif why == "läuft" then
    message(T.msgRunning)
  elseif why == "aus" then
    message(T.msgNeedSim)
  else
    local whyKey = (why == "nicht bereit" and "whyNotReady") or (why == "Kampf" and "whyCombat")
      or (why == "beritten" and "whyMounted") or nil
    message(T("msgSitNo", whyKey and T[whyKey] or tostring(why)))
  end
  refresh(true)
end

function SimPanel.stand()
  if not needCampfire() then return end
  message(CF().simStand() and T.msgStandOk or T.msgStandNo)
  refresh(true)
end

function SimPanel.randomName()
  local used = {}
  if CF() and CF().simGuests then
    for _, g in ipairs(CF().simGuests()) do used[g.name] = true end
  end
  local pool = {}
  for _, n in ipairs(SimPanel.NAMES) do
    if not used[n] then pool[#pool + 1] = n end
  end
  if #pool == 0 then pool = SimPanel.NAMES end
  local name = pool[(math.random(#pool))]
  if st.nameBox then st.nameBox:SetText(name) end
  return name
end

function SimPanel.addGuest()
  if not needCampfire() then return end
  local C = CF()
  if not C.isSim() then message(T.msgNeedSim) return end
  local name = st.nameBox and st.nameBox:GetText() or ""
  local level = st.levelBox and st.levelBox:GetText() or ""
  local g, err = C.simGuest(name, st.class, level, st.sex)
  if g then
    st.selected = g.name
    message(T("msgGuestOk", display(g.full or g.name)))
    if st.nameBox then st.nameBox:SetText("") end
  else
    message(T("msgGuestNo", tostring(err)))
  end
  refresh(true)
end

-- Remove a guest via simGuestRemove(name) if present; otherwise sim off/on and recreate the rest, but only when no round
-- is running (it would end it).
function SimPanel.removeGuest(name)
  if not needCampfire() then return end
  local C = CF()
  if type(C.simGuestRemove) == "function" then
    local ok, err = C.simGuestRemove(name)
    if not ok and err then
      message(T("msgGuestNo", tostring(err)))
      return
    end
  else
    if C.session() then message(T.msgGoneWait) return end
    local keep = {}
    for _, g in ipairs(C.simGuests()) do
      if g.name ~= name then keep[#keep + 1] = g end
    end
    local loud = C.simLoud()
    C.setSim(false)
    C.setSim(true)
    C.setSimLoud(loud)
    for _, g in ipairs(keep) do
      C.simGuest(g.name, g.class, g.level, g.sex == 3 and "w" or "m")
    end
  end
  if st.selected == name then st.selected = nil end
  message(T("msgGuestGone", display(name)))
  refresh(true)
end

local function selectedGuest()
  local C = CF()
  if not (C and C.simGuests) then return nil end
  local list = C.simGuests()
  for _, g in ipairs(list) do
    if g.name == st.selected then return g end
  end
  return list[1]
end

function SimPanel.guestSay()
  if not needCampfire() then return end
  local C = CF()
  if type(C.simGuestSay) ~= "function" then return end
  local g = selectedGuest()
  if not g then message(T.msgNeedSim) return end
  local text = st.sayBox and st.sayBox:GetText() or ""
  local ok, err = C.simGuestSay(g.name, text)
  if not ok then
    message(T("msgSayNo", tostring(err or "?")))
  else
    message(T("msgSaid", display(g.name)))
  end
  refresh(true)
end

function SimPanel.setLoud(on)
  if not needCampfire() then return end
  CF().setSimLoud(on == true)
  refresh(true)
end

function SimPanel.testNotes()
  if not needCampfire() then return end
  CF().slash("test")
  refresh(true)
end

function SimPanel.askDrop(on)
  st.asking = on and true or false
  if st.confirm then st.confirm:SetShown(st.asking) end
end

function SimPanel.dropRounds()
  if not needCampfire() then return end
  SimPanel.askDrop(false)
  local n = CF().dropSimRounds() or 0
  st.roundsAt = nil
  message(T("msgDropped", n))
  refresh(true)
end

local function setClass(file)
  st.class = file
  if st.classBtn then st.classBtn:SetText(classText(file)) end
  if st.popup then st.popup:Hide() end
end

local function buildPopup(parent)
  local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  local per = 7
  p:SetSize(2 * 104 + 12, per * 20 + 12)
  p:SetPoint("TOPLEFT", st.classBtn, "BOTTOMLEFT", 0, 0)
  p:SetFrameStrata("FULLSCREEN_DIALOG")
  p:EnableMouse(true)
  if p.SetBackdrop then
    p:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    p:SetBackdropColor(0, 0, 0, 0.95)
  end
  p.items = {}
  for i, c in ipairs(SimPanel.CLASSES) do
    local col, row = floor((i - 1) / per), (i - 1) % per
    local b = CreateFrame("Button", nil, p)
    b:SetSize(104, 20)
    b:SetPoint("TOPLEFT", p, "TOPLEFT", 6 + col * 104, -6 - row * 20)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", b, "LEFT", 4, 0)
    fs:SetText(classText(c[1]))
    b.label, b.file = fs, c[1]
    b:SetScript("OnClick", function() safe(setClass, c[1]) end)
    p.items[i] = b
  end
  p:Hide()
  return p
end

local function clock(sec)
  sec = max(0, floor(sec))
  return format("%d:%02d", floor(sec / 60), sec % 60)
end

local function roundsCount()
  local C = CF()
  if not (C and C.rounds and ns.Store and ns.Store.char) then return nil end
  local ok, list = pcall(C.rounds, ns.Store.char())
  if not ok or type(list) ~= "table" then return nil end
  local probe = 0
  for _, r in ipairs(list) do
    if r.sim then probe = probe + 1 end
  end
  return #list, probe
end

function SimPanel.statusText()
  local C = CF()
  if not C then return T.msgNoCampfire, "" end
  local line1 = C.isSim() and T.simOnLabel or T.simOffLabel
  local s = C.session()
  local now = type(GetTime) == "function" and num(GetTime()) or nil
  if s then
    local since = now and num(s.startGT) and clock(now - s.startGT) or "?"
    line1 = line1 .. "  |  " .. T("session", since)
  else
    line1 = line1 .. "  |  " .. T.noSession
  end
  local sure = 0
  if s and type(s.people) == "table" then
    for _, p in ipairs(s.people) do
      if p.sure then sure = sure + 1 end
    end
  end
  line1 = line1 .. "  |  " .. T("people", sure)
  local total, probe = st.roundsTotal, st.roundsProbe
  local line2 = total and T("rounds", total, probe or 0) or T.roundsNone
  return line1, line2
end

local function refreshRounds(force)
  local t = type(GetTime) == "function" and num(GetTime()) or 0
  if not force and st.roundsAt and t - st.roundsAt < SimPanel.ROUNDS_EVERY then return end
  st.roundsAt = t
  st.roundsTotal, st.roundsProbe = roundsCount()
end

refresh = function(force)
  local f = st.frame
  if not f then return end
  local C = CF()
  local sim = C and C.isSim() or false
  local session = C and C.session() or nil
  local guests = C and C.simGuests and C.simGuests() or {}
  refreshRounds(force)

  setChecked(st.simCheck, sim)
  setEnabled(st.sitBtn, C ~= nil and sim and not session)
  setEnabled(st.standBtn, session ~= nil)
  setEnabled(st.addBtn, C ~= nil and sim)
  setChecked(st.loudCheck, sim and C.simLoud())
  st.loudCheck.enabled = C ~= nil and sim
  if st.loudCheck.SetEnabled then st.loudCheck:SetEnabled(st.loudCheck.enabled) end

  local hasSay = C ~= nil and type(C.simGuestSay) == "function"
  if not hasSay then
    setEnabled(st.sayBtn, false, nil, T.sayWait)
  elseif not (sim and #guests > 0) then
    setEnabled(st.sayBtn, false, nil, T.sayNeed)
  else
    setEnabled(st.sayBtn, true, T.sayTip)
  end

  st.guestHead:SetText(T("guests", #guests, C and C.SIM_GUEST_MAX or ROWS))
  local sel = selectedGuest()
  for i = 1, ROWS do
    local row = st.rows[i]
    local g = guests[i]
    if g then
      row.guest = g.name
      local mark = (sel and sel.name == g.name) and "› " or ""
      row.text:SetText(mark .. display(g.name) .. " - " .. classText(g.class) .. ", " .. T("levelN", tostring(g.level)))
      row:Show()
      row.removeBtn:Show()
    else
      row.guest = nil
      row:Hide()
      row.removeBtn:Hide()
    end
  end
  st.noGuests:SetShown(#guests == 0)

  local l1, l2 = SimPanel.statusText()
  st.status1:SetText(l1)
  st.status2:SetText(l2)
  if st.msgFs then st.msgFs:SetText(st.msg or "") end
  if st.confirm then st.confirm:SetShown(st.asking == true) end
end
SimPanel.refresh = refresh

function SimPanel.build()
  if st.frame then return st.frame end
  local f = CreateFrame("Frame", SimPanel.NAME, UIParent, "BackdropTemplate")
  f:SetSize(SimPanel.W, SimPanel.H)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  if f.SetDontSavePosition then f:SetDontSavePosition(true) end
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.9)
  end
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self)
    self.moving = true
    self:StartMoving()
  end)
  f:SetScript("OnDragStop", function(self)
    if not self.moving then return end
    self.moving = false
    self:StopMovingOrSizing()
    savePos(self)
    SimPanel.place()
  end)
  f:Hide()
  st.frame = f

  st.class, st.sex = "WARRIOR", nil

  label(f, "GameFontNormal", 12, -10, T.title)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function() SimPanel.hide() end)
  st.closeBtn = close

  st.simCheck = check(f, T.simOn, 8, -30, function(cb) SimPanel.setSim(not cb.checked) end)
  withTip(st.simCheck, T.simOnTip)
  st.sitBtn = button(f, T.sit, 12, -60, 100, SimPanel.sit)
  st.standBtn = button(f, T.stand, 118, -60, 100, SimPanel.stand)

  label(f, "GameFontNormal", 12, -92, T.guestHead)
  label(f, "GameFontHighlightSmall", 12, -118, T.name)
  st.nameBox = editBox(f, 66, -114, 150, 24)
  local rnd = button(f, T.random, 222, -113, 70, function() SimPanel.randomName() end)
  withTip(rnd, T.randomTip)
  st.randomBtn = rnd

  label(f, "GameFontHighlightSmall", 12, -146, T.class)
  st.classBtn = button(f, classText(st.class), 62, -141, 150, function()
    if st.popup then st.popup:SetShown(not st.popup:IsShown()) end
  end)
  label(f, "GameFontHighlightSmall", 222, -146, T.level)
  st.levelBox = editBox(f, 258, -142, 40, 3)
  if st.levelBox.SetNumeric then st.levelBox:SetNumeric(true) end
  local lvl = type(UnitLevel) == "function" and num(UnitLevel("player")) or nil
  st.levelBox:SetText(tostring(lvl and lvl >= 1 and floor(lvl) or 10))

  label(f, "GameFontHighlightSmall", 12, -174, T.sex)
  st.sexBtn = button(f, sexText(st.sex), 62, -169, 150, function(_, mouse)
    local idx = 1
    for i, s in ipairs(SimPanel.SEXES) do
      if s[1] == st.sex then idx = i end
    end
    idx = idx % #SimPanel.SEXES + 1
    st.sex = SimPanel.SEXES[idx][1]
    st.sexBtn:SetText(T[SimPanel.SEXES[idx][2]])
  end)
  st.addBtn = button(f, T.add, 222, -169, 110, SimPanel.addGuest)

  st.guestHead = label(f, "GameFontNormal", 12, -202, "")
  st.noGuests = label(f, "GameFontDisableSmall", 18, -224, T.noGuests)
  st.rows = {}
  for i = 1, ROWS do
    local row = CreateFrame("Button", nil, f)
    row:SetSize(296, 20)
    row:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -220 - (i - 1) * 21)
    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", row, "LEFT", 4, 0)
    fs:SetWidth(280)
    if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    row.text = fs
    row:SetScript("OnClick", function(self)
      if self.guest then
        st.selected = self.guest
        refresh(false)
      end
    end)
    withTip(row, { T.pick })
    local x = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    x:SetSize(22, 20)
    x:SetPoint("LEFT", row, "RIGHT", 4, 0)
    x:SetText(T.remove)
    x:SetScript("OnClick", function() if row.guest then safe(SimPanel.removeGuest, row.guest) end end)
    withTip(x, T.removeTip)
    row.removeBtn = x
    st.rows[i] = row
  end

  st.sayBox = editBox(f, 16, -330, 200, 120)
  st.sayBox:SetText(T.sayText)
  st.sayBtn = button(f, T.sayBtn, 222, -327, 110, SimPanel.guestSay)
  withTip(st.sayBtn, T.sayWait)

  st.loudCheck = check(f, T.loud, 8, -356, function(cb) SimPanel.setLoud(not cb.checked) end)
  withTip(st.loudCheck, T.loudTip)

  st.testBtn = button(f, T.test, 12, -388, 150, SimPanel.testNotes)
  st.dropBtn = button(f, T.drop, 168, -388, 164, function() SimPanel.askDrop(true) end)

  local c = CreateFrame("Frame", nil, f)
  c:SetSize(SimPanel.W - 24, 24)
  c:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -414)
  label(c, "GameFontNormal", 0, -5, T.dropAsk)
  st.yesBtn = button(c, T.yes, 214, 0, 50, SimPanel.dropRounds)
  st.noBtn = button(c, T.no, 268, 0, 50, function() SimPanel.askDrop(false) end)
  c:Hide()
  st.confirm = c

  st.status1 = label(f, "GameFontHighlightSmall", 12, -444, "", SimPanel.W - 24)
  st.status2 = label(f, "GameFontHighlightSmall", 12, -458, "", SimPanel.W - 24)
  st.msgFs = label(f, "GameFontNormalSmall", 12, -472, "", SimPanel.W - 24)

  st.popup = buildPopup(f)

  local acc = 0
  f:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (num(elapsed) or 0)
    if acc < SimPanel.REFRESH then return end
    acc = 0
    safe(refresh, false)
  end)
  f:SetScript("OnShow", function() safe(refresh, true) end)
  f:SetScript("OnHide", function(self)
    if self.moving then
      self.moving = false
      self:StopMovingOrSizing()
    end
    if st.popup then st.popup:Hide() end
    SimPanel.askDrop(false)
    for _, eb in ipairs({ st.nameBox, st.levelBox, st.sayBox }) do eb:ClearFocus() end
  end)

  if type(ns.onCampfire) == "function" then
    ns.onCampfire(function()
      st.roundsAt = nil
      if f:IsShown() then safe(refresh, true) end
    end)
  end

  if type(UISpecialFrames) == "table" then
    local found = false
    for _, n in ipairs(UISpecialFrames) do
      if n == SimPanel.NAME then found = true end
    end
    if not found then UISpecialFrames[#UISpecialFrames + 1] = SimPanel.NAME end
  end

  SimPanel.place()
  return f
end

function SimPanel.show()
  local f = SimPanel.build()
  SimPanel.place()
  f:Show()
  refresh(true)
  return f
end

function SimPanel.hide()
  if st.frame then st.frame:Hide() end
end

function SimPanel.isShown()
  return st.frame ~= nil and st.frame:IsShown() and true or false
end

function SimPanel.toggle()
  if SimPanel.isShown() then
    SimPanel.hide()
  else
    SimPanel.show()
  end
end
