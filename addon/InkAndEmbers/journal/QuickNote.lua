-- Quick note at the screen edge: a small movable, unprotected input frame. Enter creates a note on the Notes page
-- (first line = title, rest = text). Shift+Enter = new line, Esc clears/leaves the field.
local _, ns = ...

local Journal = ns.Journal
local TT = Journal and Journal.TodoTracker
local D = Journal and Journal.Widgets and Journal.Widgets.Diary
if not (TT and D and TT.newPad) then return end

local floor, max = math.floor, math.max

local QuickNote = {}
Journal.QuickNote = QuickNote

QuickNote.NAME = "EveNChronicleQuickNote"
QuickNote.W, QuickNote.H = 250, 130
QuickNote.CONFIRM = 2.5
QuickNote.MAX_LETTERS = 2000
QuickNote.BTN_W, QuickNote.BTN_H = 18, 16

QuickNote.TEXT = ns.Locale.ns("QuickNote", {
  title = "Schnellnotiz",
  placeholder = "Notiz schreiben … Enter speichert",
  hint = "Erste Zeile = Titel. Umschalt+Enter: neue Zeile. Esc: leeren/verlassen.",
  saved = "Notiert.",
  empty = "Nichts zu notieren.",
  notReady = "Notizen sind noch nicht bereit.",
  full = "Das Notizbuch ist voll.",
  optShown = "Schnellnotizen",
  optShownTip = { "Schnellnotizen", "Zeigt am Bildschirmrand ein kleines Feld: schreiben, Enter, schon liegt die Notiz im Notizbuch." },
  on = "Schnellnotiz eingeblendet. Klickt ins Feld, um zu schreiben.",
  off = "Schnellnotiz ausgeblendet. /chronik notiz blendet sie wieder ein.",
  notReadyChar = "Die Schnellnotiz wartet noch auf Euren Charakter.",
  usage = "/chronik notiz [an|aus] - Schnellnotiz ein-/ausblenden",
  openBook = "Notizen im Buch öffnen",
  openBookLast = "Öffnet das Buch bei Eurer zuletzt gespeicherten Notiz.",
  openBookPage = "Öffnet die Notizen-Seite im Buch.",
})
local T = QuickNote.TEXT

local st = {}
QuickNote.state = st

local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end
local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end
local function say(msg) if ns.Core and ns.Core.print then ns.Core.print(msg) end end
local function safe(fn, ...) if ns.Core then return ns.Core.safe(fn, ...) end return pcall(fn, ...) end

local function charReady()
  local Store = ns.Store
  return Store ~= nil and Store.char ~= nil and type(Store.char()) == "table"
end

-- Per-character settings: { shown = bool, style = "pad"|"plain", pos = { x, y } } (x from left, y from bottom = top-left corner)
local function raw(create)
  local char = charReady() and ns.Store.char() or nil
  if not char then return create and {} or nil end
  local t = char.quickNote
  if type(t) ~= "table" or isSecret(t) then
    if not create then return nil end
    t = {}
    char.quickNote = t
  end
  return t
end

local function validStyle(v) return v == "pad" or v == "plain" end

local function styleValue()
  local r = raw(false)
  if r and validStyle(r.style) and not isSecret(r.style) then return r.style end
  local own = TT.DEFAULTS.style
  if charReady() then
    local c = ns.Store.char()
    local tt = type(c.todoTracker) == "table" and not isSecret(c.todoTracker) and c.todoTracker or nil
    if tt and validStyle(tt.style) and not isSecret(tt.style) then
      own = tt.style
      raw(true).style = own
    end
  end
  return own
end

function QuickNote.settings()
  local r = raw(false) or {}
  local out = { shown = (type(r.shown) == "boolean" and not isSecret(r.shown)) and r.shown or false, style = styleValue() }
  local p = r.pos
  if type(p) == "table" and not isSecret(p) and num(p.x) and num(p.y) and math.abs(p.x) <= 10000 and math.abs(p.y) <= 10000 then
    out.pos = { x = p.x, y = p.y }
  end
  return out
end

local function style() return styleValue() end

function QuickNote.split(text)
  if isSecret(text) or type(text) ~= "string" then return nil end
  text = text:gsub("\r\n?", "\n")
  local title, rest = text:match("^%s*([^\n]*)\n?(.*)$")
  title = title and title:gsub("%s+$", "") or ""
  rest = rest and rest:gsub("^%s+", ""):gsub("%s+$", "") or ""
  if title == "" and rest == "" then return nil end
  if title == "" then title, rest = rest:match("^([^\n]*)\n?(.*)$") end
  return title, rest
end

function QuickNote.lastNoteId()
  local N = Journal.Notes
  if not N then return nil end
  if st.lastId and type(N.get) == "function" then
    local ok, n = pcall(N.get, st.lastId)
    if ok and type(n) == "table" then return st.lastId end
  end
  if type(N.list) ~= "function" then return nil end
  local ok, list = pcall(N.list, { sort = "new" })
  if not ok or type(list) ~= "table" then return nil end
  local best
  for _, n in ipairs(list) do
    if type(n) == "table" and num(n.id) then
      if not best or (num(n.updated) or 0) > (num(best.updated) or 0)
        or ((num(n.updated) or 0) == (num(best.updated) or 0) and n.id > best.id) then
        best = n
      end
    end
  end
  return best and best.id or nil
end

function QuickNote.openNotes()
  local Access, Frame = Journal.Access, Journal.Frame
  if not Access or not Frame then return false end
  if not Access.isOpen() and not Access.open() then return false end
  local id = QuickNote.lastNoteId()
  if id and Frame.openNote then
    if Frame.openNote(id) then return true end
  end
  return Frame.showPage("notizen") and true or false
end

local function confirm(msg)
  if not st.status then return end
  st.status:SetText(msg)
  st.status:Show()
  st.token = (st.token or 0) + 1
  local token = st.token
  if C_Timer and C_Timer.After then
    C_Timer.After(QuickNote.CONFIRM, function()
      if st.token == token and st.status then st.status:SetText("") st.status:Hide() end
    end)
  end
end

function QuickNote.submit()
  local eb = st.edit
  if not eb then return nil, "kein-feld" end
  local title, body = QuickNote.split(eb:GetText())
  if not title then
    confirm(T.empty)
    return nil, "leer"
  end
  local N = Journal.Notes
  if not N or type(N.create) ~= "function" then
    confirm(T.notReady)
    return nil, "nicht-bereit"
  end
  local ok, id, why = pcall(N.create, { title = title, body = body })
  if not ok or not id then
    why = ok and why or "fehler"
    confirm(why == "voll" and T.full or T.notReady)
    return nil, why
  end
  eb:SetText("")
  eb:ClearFocus()
  st.lastId = id
  QuickNote.paintPlaceholder()
  confirm(T.saved)
  return id
end

local function clampPos(x, y)
  return TT.clampPos(x, y, QuickNote.W, QuickNote.H)
end

function QuickNote.place()
  local f = st.frame
  if not f then return end
  -- HUD hook (journal/EditMode.lua): QuickNote.hud = { place(f), moved(f) }
  if QuickNote.hud and QuickNote.hud.place(f) then return end
  local s = QuickNote.settings()
  local sw = (UIParent and num(UIParent:GetWidth())) or 1920
  local sh = (UIParent and num(UIParent:GetHeight())) or 1080
  local x, y
  if s.pos then x, y = s.pos.x, s.pos.y else x, y = sw - QuickNote.W - 40, sh - 530 end
  x, y = clampPos(x, y)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
end

local function savePos(f)
  if QuickNote.hud and QuickNote.hud.moved(f) then return end
  local l, t = num(f:GetLeft()), num(f:GetTop())
  if not l or not t then return end
  local x, y = clampPos(l, t)
  local r = raw(true)
  r.pos = { x = x, y = y }
end

function QuickNote.paintPlaceholder()
  if not st.edit then return end
  local text = st.edit:GetText()
  st.placeholder:SetShown((type(text) ~= "string" or text == "") and not st.focused)
end

function QuickNote.build()
  if st.frame then return st.frame end
  local f = CreateFrame("Frame", QuickNote.NAME, UIParent)
  f:SetSize(QuickNote.W, QuickNote.H)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  if f.SetDontSavePosition then f:SetDontSavePosition(true) end
  f:EnableMouse(true)
  f:Hide()
  st.pad = TT.newPad(f)
  st.plain = TT.newPlain(f)

  local body = CreateFrame("Frame", nil, f)
  body:SetAllPoints(f)
  body:SetFrameLevel((f:GetFrameLevel() or 1) + 2)

  local head = CreateFrame("Frame", nil, body)
  head:EnableMouse(true)
  head:RegisterForDrag("LeftButton")
  head:SetScript("OnDragStart", function()
    f.moving = true
    f:StartMoving()
  end)
  head:SetScript("OnDragStop", function()
    if not f.moving then return end
    f.moving = false
    f:StopMovingOrSizing()
    savePos(f)
    QuickNote.place()
  end)
  head:SetScript("OnEnter", function(self)
    if GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine(T.title, 1, 0.82, 0)
      GameTooltip:AddLine(T.hint, 0.8, 0.8, 0.8, true)
      GameTooltip:Show()
    end
  end)
  head:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  st.head = head
  st.title = TT.fontString(head)
  st.title:SetJustifyH("LEFT")
  st.title:SetWordWrap(false)
  local btn = CreateFrame("Button", nil, head)
  btn:SetSize(QuickNote.BTN_W, QuickNote.BTN_H)
  btn:RegisterForClicks("LeftButtonUp")
  btn.parts = {}
  local function piece(w, h, x, y, role)
    local t = btn:CreateTexture(nil, "ARTWORK")
    t:SetSize(w, h)
    t:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", x, y)
    t.role = role
    btn.parts[#btn.parts + 1] = t
    return t
  end
  piece(14, 1, 2, 3, "ink")
  piece(14, 1, 2, 12, "ink")
  piece(1, 10, 2, 3, "ink")
  piece(1, 10, 15, 3, "ink")
  piece(1, 10, 8, 3, "ink")
  piece(4, 1, 10, 9, "ink")
  piece(4, 1, 10, 6, "ink")
  piece(3, 6, 4, 0, "mark")
  btn:SetScript("OnClick", function()
    if GameTooltip then GameTooltip:Hide() end
    safe(QuickNote.openNotes)
  end)
  btn:SetScript("OnEnter", function(self)
    self.hover = true
    QuickNote.paintButton()
    if GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine(T.openBook, 1, 0.82, 0)
      GameTooltip:AddLine(QuickNote.lastNoteId() and T.openBookLast or T.openBookPage, 0.8, 0.8, 0.8, true)
      GameTooltip:Show()
    end
  end)
  btn:SetScript("OnLeave", function(self)
    self.hover = false
    QuickNote.paintButton()
    if GameTooltip then GameTooltip:Hide() end
  end)
  st.button = btn
  st.status = TT.fontString(head)
  st.status:SetJustifyH("RIGHT")
  st.status:SetWordWrap(false)
  st.status:Hide()

  local eb = CreateFrame("EditBox", nil, body)
  eb:SetAutoFocus(false)
  eb:SetMultiLine(true)
  eb:SetMaxLetters(QuickNote.MAX_LETTERS)
  if eb.SetTextInsets then eb:SetTextInsets(2, 2, 2, 2) end
  eb:EnableMouse(true)
  eb:SetScript("OnEnterPressed", function(self)
    if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then
      self:Insert("\n")
      return
    end
    safe(QuickNote.submit)
  end)
  eb:SetScript("OnEscapePressed", function(self)
    local text = self:GetText()
    if type(text) == "string" and text ~= "" then self:SetText("") end
    self:ClearFocus()
    QuickNote.paintPlaceholder()
  end)
  eb:SetScript("OnEditFocusGained", function()
    st.focused = true
    QuickNote.paintPlaceholder()
  end)
  eb:SetScript("OnEditFocusLost", function()
    st.focused = false
    QuickNote.paintPlaceholder()
  end)
  eb:SetScript("OnTextChanged", function() QuickNote.paintPlaceholder() end)
  st.edit = eb
  f:SetScript("OnMouseDown", function() eb:SetFocus() end)
  f:SetScript("OnHide", function()
    eb:ClearFocus()
    if f.moving then
      f.moving = false
      f:StopMovingOrSizing()
    end
  end)
  st.placeholder = TT.fontString(body)
  st.placeholder:SetJustifyH("LEFT")
  st.placeholder:SetWordWrap(true)
  st.frame = f
  QuickNote.applyStyle()
  QuickNote.place()
  return f
end

function QuickNote.applyStyle()
  local f = st.frame
  if not f then return end
  local s = style()
  local isPad = s == "pad"
  local M = TT.METRICS[s]
  local w, h = QuickNote.W, QuickNote.H
  st.pad:SetShown(isPad)
  st.plain:SetShown(not isPad)
  local top = M.top
  local padL = max(M.padLMin, floor(w * M.padL + 0.5)) + (isPad and 8 or 0)
  local padB = M.padB
  if isPad and st.pad.image then
    TT.sizePad(st.pad, w, h)
    padB = max(M.padB, floor(w * 0.1 + 0.5))
    local S = Journal.Theme.TODO_PAD_SLICE
    if S and S.tab then top = max(top, floor((TT.padY(st.pad, S.tab[3]) or 0) + 2.5)) end
    if S and S.edge then top = max(top, floor((TT.padY(st.pad, S.edge) or 0) + 2.5)) end
  end
  local P = isPad and TT.PAD or TT.PLAIN
  local c = TT.colorOf
  TT.setFont(st.title, isPad and "hand" or "text", isPad and 19 or 12)
  st.title:SetTextColor(c(P.title))
  st.title:SetText(T.title)
  TT.setFont(st.status, isPad and "hand" or "text", isPad and 16 or 11)
  st.status:SetTextColor(c(isPad and "red" or TT.PLAIN.hover))
  local textKind, size = isPad and "hand" or "text", isPad and 16 or 12
  local Theme = Journal.Theme
  local file = (Theme.FONT and Theme.FONT[textKind]) or (Theme.FONT and Theme.FONT.text)
  local ok, res = pcall(st.edit.SetFont, st.edit, file, size, "")
  if (not ok or res == false) and isPad then pcall(st.edit.SetFont, st.edit, Theme.FONT.text, 12, "") end
  st.edit:SetTextColor(c(P.text))
  TT.setFont(st.placeholder, isPad and "hand" or "text", size)
  st.placeholder:SetTextColor(c(P.extra, 0.8))
  st.placeholder:SetText(T.placeholder)
  for _, fs in ipairs({ st.title, st.status, st.placeholder }) do
    if fs.SetShadowOffset then fs:SetShadowOffset(isPad and 0 or 1, isPad and 0 or -1) end
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, isPad and 0 or 0.9) end
  end
  local headH = isPad and 24 or 16
  st.head:ClearAllPoints()
  st.head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  st.head:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  st.head:SetHeight(top + headH)
  st.title:ClearAllPoints()
  st.title:SetPoint("TOPLEFT", f, "TOPLEFT", padL, -top)
  st.title:SetHeight(headH)
  if st.title.SetJustifyV then st.title:SetJustifyV("MIDDLE") end
  st.button:ClearAllPoints()
  st.button:SetPoint("TOPRIGHT", f, "TOPRIGHT", -M.padR + 2, -(top + floor((headH - QuickNote.BTN_H) / 2)))
  st.status:ClearAllPoints()
  st.status:SetPoint("RIGHT", st.button, "LEFT", -5, 0)
  st.status:SetHeight(headH)
  local y = top + headH + 4
  st.edit:ClearAllPoints()
  st.edit:SetPoint("TOPLEFT", f, "TOPLEFT", padL, -y)
  st.edit:SetSize(w - padL - M.padR, max(20, h - y - padB))
  st.placeholder:ClearAllPoints()
  st.placeholder:SetPoint("TOPLEFT", st.edit, "TOPLEFT", 2, -2)
  st.placeholder:SetWidth(w - padL - M.padR - 4)
  st.style = s
  QuickNote.paintButton()
  QuickNote.paintPlaceholder()
end

function QuickNote.paintButton()
  local b = st.button
  if not b then return end
  local isPad = style() == "pad"
  local ink = isPad and "sepia" or TT.PLAIN.extra
  local mark = isPad and "red" or TT.PLAIN.title
  if b.hover then ink = isPad and "red" or TT.PLAIN.hover end
  for _, t in ipairs(b.parts) do t:SetColorTexture(TT.colorOf(t.role == "mark" and mark or ink)) end
end

function QuickNote.refresh()
  if st.preview then return true end
  local s = QuickNote.settings()
  if not (s.shown and charReady()) then
    if st.frame then st.frame:Hide() end
    return false
  end
  local f = QuickNote.build()
  if st.style ~= style() then QuickNote.applyStyle() end
  f:Show()
  return true
end

function QuickNote.isShown()
  return st.frame ~= nil and st.frame:IsShown() and true or false
end

QuickNote.listeners = {}

function QuickNote.setShown(on)
  local r = raw(true)
  r.shown = on and true or false
  QuickNote.refresh()
  if QuickNote.hud and QuickNote.hud.sync then pcall(QuickNote.hud.sync) end
  for _, fn in ipairs(QuickNote.listeners) do pcall(fn) end
  return r.shown
end

TT.beforeStyle = function()
  if charReady() then raw(true).style = styleValue() end
end

function QuickNote.setStyle(value)
  if not validStyle(value) or not charReady() then return false end
  raw(true).style = value
  if st.frame then QuickNote.applyStyle() end
  QuickNote.refresh()
  if QuickNote.hud and QuickNote.hud.sync then pcall(QuickNote.hud.sync) end
  for _, fn in ipairs(QuickNote.listeners) do pcall(fn) end
  return true
end

function QuickNote.slash(arg)
  arg = type(arg) == "string" and string.lower(arg) or ""
  if not charReady() then
    say(T.notReadyChar)
    return false
  end
  local on
  on = ns.Core and ns.Core.onOff(arg)
  if on ~= nil then
  elseif arg == "" then on = not QuickNote.settings().shown
  else
    say(T.usage)
    return false
  end
  QuickNote.setShown(on)
  say(on and T.on or T.off)
  return on
end

if ns.Core and ns.Core.on then
  ns.Core.on("PLAYER_ENTERING_WORLD", function() safe(QuickNote.refresh) end)
end
