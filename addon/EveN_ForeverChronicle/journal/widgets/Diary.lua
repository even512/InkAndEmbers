-- Diary kit ("diary with stickers"): a fixed set of control widgets, the same on all pages, under ns.Journal.Widgets.Diary (D).
-- Font rule: handwriting (Caveat Bold, Theme.FONT.hand) ONLY for sticker buttons and section heads; everything else in the
-- clean text fonts (Friz "text", Arial Narrow "label").
local _, ns = ...

local Journal = ns.Journal
local W = Journal and Journal.Widgets
if not W then return end

local Theme = Journal.Theme or { C = {}, FONT = {}, TEX = {} }
local floor, max, min, abs, rad, tan = math.floor, math.max, math.min, math.abs, math.rad, math.tan

local D = {}
W.Diary = D

D.TEXT = ns.Locale.ns("w.Diary", {
  back = "Zurück",
  handLoaded = "Handschrift: geladen %s",
  handLeft = " (%d Beschriftungen noch in Friz)",
  handFallback = "Handschrift: Rückfall Friz (%s)",
  reasonNoPath = "kein Pfad im Theme",
  reasonSetFontErr = "SetFont-Fehler: %s",
  reasonSetFontFalse = "SetFont meldet false (Datei nicht ladbar)",
  reasonGetFontEmpty = "GetFont leer nach SetFont",
  reasonNoProbe = "kein Probe-FontString",
})
D.BACK = { x = (Theme.GRID and Theme.GRID.L.x or 92) - 2, y = Theme.GRID and Theme.GRID.slots.back.y or 29 }
D.DISABLED_ALPHA = 0.4
D.HAND_FALLBACK_SCALE = 0.72              -- Caveat looks smaller than Friz: the fallback font is scaled down accordingly
D.ROW_LINE = { color = "blue", alpha = 0.2 }

-- Set the font file. -> true | false, reason (for /chronik diag). res == false: the client reports the file as not loadable;
-- empty GetFont: the font is not there (yet).
local function trySetFont(fs, file, size)
  if type(file) ~= "string" or file == "" then return false, D.TEXT.reasonNoPath end
  local ok, res = pcall(fs.SetFont, fs, file, size, "")
  if not ok then return false, D.TEXT("reasonSetFontErr", tostring(res)) end
  if res == false then return false, D.TEXT.reasonSetFontFalse end
  if type(fs.GetFont) == "function" then
    local got = fs:GetFont()
    if got == nil then return false, D.TEXT.reasonGetFontEmpty end
  end
  return true
end

-- Preload the handwriting and retry late. The client only loads an addon font file on the first SetFont; if that happens only
-- after the loading screen (the journal builds on first open), the attempt can fail or yield no font yet, and the label stayed
-- in the Friz fallback for good. So (1) a probe FontString sets the handwriting while the file loads (loading screen), (2)
-- every label in the fallback remembers its handwriting size and is retried after short waits (HAND_RETRY, seconds); on
-- success it switches to Caveat and its widget re-measures.
D.HAND_RETRY = { 0.5, 1, 2, 4, 8, 15 }
local handWaiting = setmetatable({}, { __mode = "k" })
local handProbe
local retryPending = false
D.handState = { ok = false, reason = "noch nicht versucht" }

local function probeFont()
  if handProbe then return handProbe end
  if type(CreateFrame) ~= "function" then return nil end
  local ok, f = pcall(CreateFrame, "Frame", nil, UIParent)
  if not ok or type(f) ~= "table" or not f.CreateFontString then return nil end
  if f.SetSize then f:SetSize(1, 1) end
  if f.SetPoint and UIParent then f:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", -64, 64) end
  handProbe = f:CreateFontString(nil, "OVERLAY")
  return handProbe
end

function D.probeHand()
  local fs = probeFont()
  if not fs then
    D.handState = { ok = false, reason = D.TEXT.reasonNoProbe }
    return false, D.handState.reason
  end
  local file = (Theme.FONT or {}).hand
  local ok, why = trySetFont(fs, file, 20)
  if ok then
    if fs.SetText then fs:SetText("Aa ÄÖÜ ß") end
    local got = type(fs.GetFont) == "function" and fs:GetFont() or nil
    D.handState = { ok = true, file = got or file }
  else
    D.handState = { ok = false, reason = why }
  end
  return ok, why
end

local function upgradeWaiting()
  local file = (Theme.FONT or {}).hand
  local left = 0
  for fs, size in pairs(handWaiting) do
    if trySetFont(fs, file, size) then
      handWaiting[fs] = nil
      fs.diaryFallback = nil
      if type(fs.diaryRefit) == "function" then W.call(fs.diaryRefit, fs) end
    else
      left = left + 1
    end
  end
  return left
end

local function scheduleRetry(step)
  if retryPending or not (C_Timer and C_Timer.After) then return end
  step = step or 1
  local wait = D.HAND_RETRY[step]
  if not wait then return end
  retryPending = true
  C_Timer.After(wait, function()
    retryPending = false
    if not next(handWaiting) then return end
    if D.probeHand() and upgradeWaiting() == 0 then return end
    scheduleRetry(step + 1)
  end)
end

function D.handWaitingCount()
  local n = 0
  for _ in pairs(handWaiting) do n = n + 1 end
  return n
end

function D.handStatus()
  local ok, why = D.probeHand()
  if ok then
    local left = upgradeWaiting()
    local line = D.TEXT("handLoaded", tostring(D.handState.file))
    if left > 0 then line = line .. D.TEXT("handLeft", left) end
    return line
  end
  return D.TEXT("handFallback", tostring(why))
end

D.probeHand()

function D.font(parent, kind, size, color, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  local FONT = Theme.FONT or {}
  size = tonumber(size) or 12
  local file = FONT[kind] or FONT.text
  local ok = trySetFont(fs, file, size)
  if not ok and kind == "hand" then
    fs.diaryFallback = true
    handWaiting[fs] = size
    file = FONT.text
    size = floor(size * D.HAND_FALLBACK_SCALE + 0.5)
    ok = trySetFont(fs, file, size)
  end
  if not ok then
    file = nil
    if fs.SetFontObject and GameFontNormal then pcall(fs.SetFontObject, fs, GameFontNormal) end
  end
  W.ink(fs, kind, file, size)
  fs:SetTextColor(W.color(color or "ink"))
  fs:SetText("")
  if fs.diaryFallback then scheduleRetry(1) end
  return fs
end

D.EMPTY_SIZE = 19
function D.emptyNote(parent, width, size)
  local fs = D.font(parent, "hand", size or D.EMPTY_SIZE, "ink")
  fs:SetWidth(width)
  if fs.SetJustifyH then fs:SetJustifyH("CENTER") end
  if fs.SetWordWrap then fs:SetWordWrap(true) end
  return fs
end

function D.upper(s)
  if type(s) ~= "string" then return "" end
  return ns.Journal.Fmt.upper(s)
end

-- Re-check measurements: SetFont reports success, but on the first measurement the client still returns the width of the
-- substitute font while drawing uses Caveat afterwards (the handwriting overhung its stickers on first open). So every
-- measured label with an fs.diaryRefit remembers its measured width (fs.diaryW). After each measurement D.recheck compares
-- the current width with the stored one shortly after (next frame, then D.SETTLE) and on a difference calls diaryRefit, which
-- re-measures the widget.
D.SETTLE = { 0, 0.4, 1.5 }
local tracked = setmetatable({}, { __mode = "k" })
local settleIdx, settlePending, rechecking = 0, false, false

local function rawWidth(fs)
  for _, name in ipairs({ "GetUnboundedStringWidth", "GetStringWidth" }) do
    local fn = fs[name]
    if type(fn) == "function" then
      local ok, w = pcall(fn, fs)
      w = ok and tonumber(w) or nil
      if w and w == w and w >= 0 then return w end
    end
  end
  return 0
end

function D.recheck()
  if rechecking then return 0 end
  rechecking = true
  local list = {}
  for fs in pairs(tracked) do list[#list + 1] = fs end
  local n = 0
  for _, fs in ipairs(list) do
    local w = rawWidth(fs)
    if abs(w - (fs.diaryW or 0)) > 0.5 and type(fs.diaryRefit) == "function" then
      fs.diaryW = w
      n = n + 1
      W.call(fs.diaryRefit, fs)
    end
  end
  rechecking = false
  return n
end

local function settleTick()
  settlePending = false
  D.recheck()
  settleIdx = settleIdx + 1
  local wait = D.SETTLE[settleIdx]
  if wait and C_Timer and C_Timer.After then
    settlePending = true
    C_Timer.After(wait, settleTick)
  end
end

local function startSettle()
  settleIdx = 1
  if settlePending or not (C_Timer and C_Timer.After) then return end
  settlePending = true
  C_Timer.After(D.SETTLE[1], settleTick)
end

function D.measure(fs)
  local w = rawWidth(fs)
  if type(fs.diaryRefit) == "function" then
    fs.diaryW = w
    tracked[fs] = true
    if not rechecking then startSettle() end
  end
  return w
end

local function textWidth(fs, fallbackChars)
  local w = D.measure(fs)
  if w <= 0 then w = (fallbackChars or 0) * 7 end
  return w
end

local function useTex(t, file)
  if not Theme.HAS_DIARY or type(file) ~= "string" then return false end
  local ok, res = pcall(t.SetTexture, t, file)
  return ok and res ~= false
end

function D.mark(parent, name, size, color, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetSize(size or 16, size or 16)
  -- Careful: "f and f(x)" truncates to ONE return value (every mark except the badge got the texcoords (left, nil, nil, nil)
  -- and stayed invisible in game), so fetch the four values separately.
  local u0, u1, v0, v1
  if Theme.diaryCoords then u0, u1, v0, v1 = Theme.diaryCoords(name) end
  if u0 and u1 and v0 and v1 and useTex(t, Theme.TEX.diaryMarks) then
    t:SetTexCoord(u0, u1, v0, v1)
    if color then t:SetVertexColor(W.color(color)) end
    t.diaryOk = true
  else
    t:SetColorTexture(W.color(color or "ink", (name == "box") and 0.25 or 0.9))
    t.diaryOk = false
  end
  t.diaryName = name
  return t
end

function D.NewInkStroke(parent, width, color, alpha, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  if useTex(t, Theme.TEX.diaryStroke) then
    t:SetVertexColor(W.color(color or "ink", alpha or 0.85))
    t:SetHeight(4)
  else
    t:SetColorTexture(W.color(color or "ink", alpha or 0.85))
    t:SetHeight(2)
  end
  if width then t:SetWidth(width) end
  return t
end

local function tipLines(b)
  local o = b.diaryOpts or {}
  local src = (b.disabled and o.disabledTip) or b.tipLines or o.tip
  if type(src) == "function" then
    local ok, lines = pcall(src, b)
    src = ok and lines or nil
  end
  return type(src) == "table" and src or nil
end

local function showTip(b)
  local lines = tipLines(b)
  if lines then W.tip(b, lines) end
end

local function behave(b, opts, paint, click)
  b.diaryOpts = opts
  b.diaryPaint = paint
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp") end
  b:SetScript("OnEnter", function(self)
    self.hover = not self.disabled
    W.call(paint, self)
    showTip(self)
  end)
  b:SetScript("OnLeave", function(self)
    self.hover = false
    W.call(paint, self)
    W.hideTip(self)
  end)
  b:SetScript("OnHide", function(self)
    if self.hover then
      self.hover = false
      W.call(paint, self)
    end
    W.hideTip(self)
  end)
  b:SetScript("OnClick", function(self, ...)
    if self.disabled then return end
    W.call(click, self, ...)
  end)
  function b:SetEnabled(on)
    self.disabled = not on
    if self.disabled then self.hover = false end
    self:SetAlpha(self.disabled and D.DISABLED_ALPHA or 1)
    W.call(paint, self)
  end
  function b:SetTip(lines) self.tipLines = lines end
  return b
end

local function face(b)
  local f = CreateFrame("Frame", nil, b)
  f:SetPoint("CENTER", b, "CENTER", 0, 0)
  return f
end

-- Keyboard: Esc goes to onEsc, everything else to the game. Only outside combat (SetPropagateKeyboardInput is locked there):
-- in combat the keyboard stays off and Esc goes to the game as usual.
local function inCombat() return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false end

local function propagate(f, on)
  if f.SetPropagateKeyboardInput and not inCombat() then pcall(f.SetPropagateKeyboardInput, f, on) end
end

local function escKeys(f, onEsc)
  local function arm(self)
    if inCombat() then
      if self.EnableKeyboard then self:EnableKeyboard(false) end
      return
    end
    propagate(self, true)
    if self.EnableKeyboard then self:EnableKeyboard(true) end
  end
  if f.HookScript then f:HookScript("OnShow", arm) end
  f:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" and not inCombat() and not self.disabled then
      propagate(self, false)
      W.call(onEsc, self)
    else
      propagate(self, true)
    end
  end)
  arm(f)
end
D.escKeys = escKeys

local S = Theme.DIARY_STICKER or { w = 128, h = 64, cap = 32, pad = { l = 6, r = 6, t = 5, b = 9 } }

-- Looks glued in: tilt (degrees) and irregularity round-robin per newly created label (fixed, not random: same order, same
-- picture). jitter = { extra width px, height offset px }.
D.STICKER_TILTS = { -2, 1.5, -1, 2.2, -2.6, 1 }
D.STICKER_JITTER = { { 0, 0 }, { 4, 1 }, { 2, -1 }, { 6, 0 }, { 1, 1 }, { 3, -1 } }
local stickerSeq = 0

-- Slanted without rotating: the three pieces are sheared vertically (same effect as a small rotation, exact across the piece
-- borders). Edge shift at most SHEAR_MAX px so the die-cut edge is not clipped.
local SHEAR_MAX = 2.5

local function layoutSticker(b)
  local w, h = b.faceW, b.faceH
  local cap = floor(h * S.cap / S.h + 0.5)
  local parts = b.parts
  if not parts then return end
  parts[1]:SetWidth(cap)
  parts[3]:SetWidth(cap)
  local slope = 0
  if not b.hover and b.tilt ~= 0 then
    slope = -tan(rad(b.tilt)) -- tilt like CSS rotate(): negative = counter-clockwise (right side higher)
    if abs(slope) * w / 2 > SHEAR_MAX then slope = (slope > 0 and 1 or -1) * SHEAR_MAX / (w / 2) end
  end
  local u = S.cap / S.w
  local xs = { -w / 2, -w / 2 + cap, w / 2 - cap, w / 2 }
  local us = { 0, u, 1 - u, 1 }
  for i = 1, 3 do
    local va, vb = slope * xs[i] / h, slope * xs[i + 1] / h
    parts[i]:SetTexCoord(us[i], va, us[i], 1 + va, us[i + 1], vb, us[i + 1], 1 + vb)
  end
end

local function paintSticker(b)
  b.face:SetScale((b.hover and not b.disabled) and 1.05 or 1)
  layoutSticker(b)
end

function D.NewSticker(parent, text, onClick, opts)
  opts = type(opts) == "table" and opts or {}
  local b = CreateFrame("Button", nil, parent)
  stickerSeq = stickerSeq + 1
  local nT, nJ = #D.STICKER_TILTS, #D.STICKER_JITTER
  b.tilt = tonumber(opts.tilt) or D.STICKER_TILTS[(stickerSeq - 1) % nT + 1]
  local jit = D.STICKER_JITTER[(stickerSeq - 1) % nJ + 1]
  b.extraW = opts.tilt ~= nil and 0 or jit[1]
  b.faceH = tonumber(opts.height) or 40
  local f = face(b)
  if jit[2] ~= 0 and opts.tilt == nil then
    f:ClearAllPoints()
    f:SetPoint("CENTER", b, "CENTER", 0, jit[2])
  end
  b.face = f
  local parts = {}
  for i = 1, 3 do
    local t = f:CreateTexture(nil, "BACKGROUND")
    if not useTex(t, Theme.TEX.diarySticker) then parts = nil break end
    t:SetPoint("TOP", f, "TOP", 0, 0)
    t:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
    parts[i] = t
  end
  if parts then
    parts[1]:SetPoint("LEFT", f, "LEFT", 0, 0)
    parts[3]:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    parts[2]:SetPoint("LEFT", parts[1], "RIGHT", 0, 0)
    parts[2]:SetPoint("RIGHT", parts[3], "LEFT", 0, 0)
    b.parts = parts
  else
    local k = b.faceH / S.h
    local bg = W.NewRect(f, { 0.93, 0.87, 0.74 }, 1, "BACKGROUND")
    bg:SetPoint("TOPLEFT", f, "TOPLEFT", S.pad.l * k, -S.pad.t * k)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -S.pad.r * k, S.pad.b * k)
    b.fallback = bg
  end
  local fs = D.font(f, "hand", tonumber(opts.size) or 20, "ink")
  fs:SetPoint("CENTER", f, "CENTER", 0, floor(b.faceH * (S.pad.b - S.pad.t) / S.h / 2 + 0.5))
  fs:SetWordWrap(false)
  b.text = fs
  fs.diaryRefit = function() b:SetLabel(b.labelText) end
  function b:SetLabel(t)
    self.labelText = t
    W.setText(self.text, t)
    local k = self.faceH / S.h
    local inner = (S.pad.l + S.pad.r) * k + 2 * 14
    self.faceW = floor(max(textWidth(self.text, type(t) == "string" and #t or 0) + inner + (self.extraW or 0), 2 * S.cap * k + 8) + 0.5)
    self:SetSize(self.faceW, self.faceH)
    self.face:SetSize(self.faceW, self.faceH)
    layoutSticker(self)
  end
  behave(b, opts, paintSticker, function(self) if onClick then onClick(self) end end)
  b:SetLabel(text)
  paintSticker(b)
  return b
end

local Toggle = {}
Toggle.__index = Toggle

local function paintOption(b)
  local sel = b.selected
  b.ring:SetShown(sel and true or false)
  local c = sel and "ink" or ((b.hover and not b.disabled) and "red" or "sepia")
  b.text:SetTextColor(W.color(c))
end

function D.NewToggle(parent, opts)
  opts = type(opts) == "table" and opts or {}
  local self = setmetatable({ opts = opts, buttons = {} }, Toggle)
  self.frame = CreateFrame("Frame", nil, parent)
  self.size = tonumber(opts.size) or 14
  self.gap = tonumber(opts.gap) or 18
  self:SetItems(opts.items)
  self:SetValue(opts.value, true)
  return self
end

function Toggle:SetItems(items)
  items = type(items) == "table" and items or {}
  self.items = items
  local x, h = 0, self.size + 10
  for i = 1, max(#items, #self.buttons) do
    local it = items[i]
    local b = self.buttons[i]
    if it and not b then
      b = CreateFrame("Button", nil, self.frame)
      local ring = b:CreateTexture(nil, "BACKGROUND")
      if useTex(ring, Theme.TEX.diaryCircle) then
        ring:SetVertexColor(W.color("red"))
      else
        ring:SetColorTexture(W.color("red", 0.15))
      end
      b.ring = ring
      b.text = D.font(b, "label", self.size, "sepia")
      b.text.diaryRefit = function() self:SetItems(self.items) end
      b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
      ring:SetPoint("TOPLEFT", b, "TOPLEFT", -3, 3)
      ring:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 3, -3)
      behave(b, {}, paintOption, function(btn)
        if btn.item then
          self:SetValue(btn.item.key)
          if type(self.opts.onChange) == "function" then W.call(self.opts.onChange, btn.item.key, btn.item) end
        end
      end)
      self.buttons[i] = b
    end
    if it and b then
      b.item = it
      b.diaryOpts = { tip = it.tip }
      W.setText(b.text, type(it.label) == "string" and it.label or "")
      local w = floor(textWidth(b.text, type(it.label) == "string" and #it.label or 0) + 12 + 0.5)
      b:SetSize(w, h)
      b:ClearAllPoints()
      b:SetPoint("LEFT", self.frame, "LEFT", x + 3, 0)
      b:Show()
      x = x + w + self.gap
    elseif b then
      b.item = nil
      b:Hide()
    end
  end
  self.frame:SetSize(max(1, x - self.gap + 6), h + 6)
  self:Paint()
end

function Toggle:Paint()
  for _, b in ipairs(self.buttons) do
    b.selected = b.item ~= nil and b.item.key == self.value
    paintOption(b)
  end
end

function Toggle:SetValue(key)
  self.value = key
  self:Paint()
end

function Toggle:GetValue() return self.value end

function Toggle:SetEnabled(on, key)
  for _, b in ipairs(self.buttons) do
    if key == nil or (b.item and b.item.key == key) then b:SetEnabled(on) end
  end
end

local function paintNav(b)
  local on = b.hover and not b.disabled
  b.face:SetScale(on and 1.15 or 1)
  b.icon:SetVertexColor(W.color(on and "red" or "ink"))
end

local function navButton(parent, name, size, onClick, tip)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size + 8, size + 6)
  b.face = face(b)
  b.face:SetSize(size, size)
  b.icon = D.mark(b.face, name, size, "ink")
  b.icon:SetAllPoints(b.face)
  if not b.icon.diaryOk then
    b.icon:SetColorTexture(0, 0, 0, 0)
    local fs = D.font(b.face, "text", size, "ink")
    fs:SetPoint("CENTER", b.face, "CENTER", 0, 0)
    fs:SetText(name == "prev" and "‹" or "›")
    b.glyph = fs
    local base = b.icon.SetVertexColor
    b.icon.SetVertexColor = function(t, ...)
      base(t, 0, 0, 0, 0)
      fs:SetTextColor(...)
    end
  end
  behave(b, { tip = tip }, paintNav, function() if onClick then onClick() end end)
  paintNav(b)
  return b
end

function D.NewNavPair(parent, opts)
  opts = type(opts) == "table" and opts or {}
  local size = tonumber(opts.size) or 22
  local nav = { frame = CreateFrame("Frame", nil, parent) }
  nav.prev = navButton(nav.frame, "prev", size, opts.onPrev, opts.tipPrev)
  nav.next = navButton(nav.frame, "next", size, opts.onNext, opts.tipNext)
  nav.prev:SetPoint("LEFT", nav.frame, "LEFT", 0, 0)
  nav.next:SetPoint("LEFT", nav.prev, "RIGHT", 2, 0)
  nav.frame:SetSize(2 * (size + 8) + 2, size + 6)
  function nav:SetEnabled(prevOn, nextOn)
    self.prev:SetEnabled(prevOn and true or false)
    self.next:SetEnabled(nextOn and true or false)
  end
  return nav
end

local function paintOpen(b)
  local on = b.hover and not b.disabled
  b.text:SetTextColor(W.color(on and "red" or "ink"))
end

function D.NewOpenLink(parent, text, onClick, opts)
  opts = type(opts) == "table" and opts or {}
  local b = CreateFrame("Button", nil, parent)
  local size = tonumber(opts.size) or 14
  b:SetHeight(size + 12)
  -- paper strip as base: the texture has a 3 px border (top/sides) and 4 px (bottom, shadow), hence a bit larger
  local tape = b:CreateTexture(nil, "BACKGROUND")
  if useTex(tape, Theme.TEX.diaryTape) then
    tape:SetPoint("TOPLEFT", b, "TOPLEFT", -4, 4)
    tape:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 4, -5)
  else
    tape:SetColorTexture(0.93, 0.87, 0.74, 1)
    tape:SetAllPoints(b)
  end
  b.tape = tape
  b.text = D.font(b, "text", size, "ink")
  b.text:SetPoint("LEFT", b, "LEFT", 12, 0)
  b.text:SetWordWrap(false)
  b.arrow = D.mark(b, "arrow", size - 2, "red")
  b.arrow:SetPoint("LEFT", b.text, "RIGHT", 6, 0)
  b.text.diaryRefit = function() b:SetLabel(b.labelText) end
  function b:SetLabel(t)
    self.labelText = t
    W.setText(self.text, t)
    self:SetWidth(floor(12 + textWidth(self.text, type(t) == "string" and #t or 0) + 6 + (size - 2) + 10 + 0.5))
  end
  behave(b, opts, paintOpen, function(self) if onClick then onClick(self) end end)
  b:SetLabel(text)
  paintOpen(b)
  return b
end

local function paintBack(b)
  b.line:SetShown((b.hover and not b.disabled) and true or false)
end

function D.NewBack(parent, text, onBack, opts)
  opts = type(opts) == "table" and opts or {}
  local b = CreateFrame("Button", nil, parent)
  local size = tonumber(opts.size) or 14
  b:SetHeight(size + 10)
  b.icon = D.mark(b, "back", size + 2, "red")
  b.icon:SetPoint("LEFT", b, "LEFT", 2, 0)
  b.text = D.font(b, "text", size, "red")
  b.text:SetPoint("LEFT", b.icon, "RIGHT", 5, 0)
  b.text:SetWordWrap(false)
  b.line = W.NewRect(b, "red", 0.8, "ARTWORK")
  b.line:SetHeight(1)
  b.line:SetPoint("TOPLEFT", b.text, "BOTTOMLEFT", 0, -1)
  b.line:SetPoint("TOPRIGHT", b.text, "BOTTOMRIGHT", 0, -1)
  local function back(self) if onBack then onBack(self) end end
  b.text.diaryRefit = function() b:SetLabel(b.labelText) end
  function b:SetLabel(t)
    if type(t) ~= "string" or t == "" then t = D.TEXT.back end
    self.labelText = t
    W.setText(self.text, t)
    self:SetWidth(floor(2 + size + 2 + 5 + textWidth(self.text, #t) + 6 + 0.5))
  end
  behave(b, opts, paintBack, back)
  if opts.esc ~= false then escKeys(b, back) end
  b:SetLabel(text)
  paintBack(b)
  return b
end

function D.placeBack(b, page, x, y)
  if not (b and page) then return end
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", page, "TOPLEFT", tonumber(x) or D.BACK.x, -(tonumber(y) or D.BACK.y))
end

-- Paper slip: base of all drop-down lists (dropdown, column-header popups). The paper strip from the approved label sheet
-- (Media/DiaryTape, 128 x 32, torn edges, shadow at the bottom) as nine pieces: corners at original size (D.SLIP.cw x ch
-- pixels = cu x cv of the texture), edges stretched lengthwise only, middle stretched, so the torn edges stay sharp at any
-- size. Without the texture: parchment area with a fine ink border.
D.SLIP = { cw = 12, ch = 9, cu = 12 / 128, cv = 9 / 32, pad = 6 }

function D.NewSlip(f)
  local parts = {}
  local t0 = f:CreateTexture(nil, "BACKGROUND")
  if not useTex(t0, Theme.TEX.diaryTape) then
    t0:SetColorTexture(W.color("parchment", 0.98))
    t0:SetAllPoints(f)
    local edge = W.NewOutline(f, 100, 40, "ink", 0.6)
    edge:SetAllPoints(f)
    return { t0, edge, fallback = true }
  end
  local s = D.SLIP
  local us, vs = { 0, s.cu, 1 - s.cu, 1 }, { 0, s.cv, 1 - s.cv, 1 }
  for row = 1, 3 do
    for col = 1, 3 do
      local t = (row == 1 and col == 1) and t0 or f:CreateTexture(nil, "BACKGROUND")
      if t ~= t0 then useTex(t, Theme.TEX.diaryTape) end
      t:SetTexCoord(us[col], us[col + 1], vs[row], vs[row + 1])
      local L = (col == 1 and 0) or (col == 2 and s.cw) or nil
      local R = (col == 3 and 0) or (col == 2 and -s.cw) or nil
      local T = (row == 1 and 0) or (row == 2 and -s.ch) or nil
      local B = (row == 3 and 0) or (row == 2 and s.ch) or nil
      if L and T then t:SetPoint("TOPLEFT", f, "TOPLEFT", L, T) end
      if R and T then t:SetPoint("TOPRIGHT", f, "TOPRIGHT", R, T) end
      if L and B then t:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", L, B) end
      if R and B then t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", R, B) end
      if not (L and R) then t:SetWidth(s.cw) end
      if not (T and B) then t:SetHeight(s.ch) end
      t.slipPart = (row - 1) * 3 + col
      parts[#parts + 1] = t
    end
  end
  return parts
end

D.SLIP_ROW = { tick = 15, indent = 20, size = 13 }

local function slipUnder(row)
  local w = D.measure(row.label)
  local maxW = tonumber(row.label:GetWidth()) or 0
  if maxW > 0 and w > maxW then w = maxW end
  row.under:SetWidth(max(8, w))
  row.under:SetShown((row.hover and (row.label:GetText() or "") ~= "") and true or false)
end

function D.SlipRow(row)
  local k = D.SLIP_ROW
  local tick = D.mark(row, "tick", k.tick, "red", "OVERLAY")
  tick:SetPoint("LEFT", row, "LEFT", 3, 1)
  tick:Hide()
  row.tick = tick
  local n = W.font(row, "label", 12, "sepia")
  n:SetJustifyH("RIGHT")
  n:SetWidth(40)
  n:SetPoint("RIGHT", row, "RIGHT", -6, 0)
  row.count = n
  row.label:ClearAllPoints()
  pcall(row.label.SetFont, row.label, (W.FONT and W.FONT.text) or Theme.FONT.text, k.size, "")
  row.label:SetPoint("LEFT", row, "LEFT", k.indent, 0)
  row.label:SetPoint("RIGHT", row, "RIGHT", -48, 0)
  row.label:SetTextColor(W.color("ink"))
  local under = D.NewInkStroke(row, nil, "ink", 0.8, "ARTWORK")
  under:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", -1, 1)
  under:Hide()
  row.under = under
  row:HookScript("OnEnter", function(r)
    r.hover = true
    slipUnder(r)
  end)
  row:HookScript("OnLeave", function(r)
    r.hover = false
    slipUnder(r)
  end)
  row:HookScript("OnHide", function(r)
    r.hover = false
    r.under:Hide()
  end)
  return row
end

function D.SlipRowClear(row)
  row.active = false
  row.tick:Hide()
  row.count:SetText("")
  row.under:Hide()
end

function D.SlipRowFill(row, it)
  W.setText(row.label, it.text)
  local c = tonumber(it.count)
  row.count:SetText(c and Journal.Texts and Journal.Texts.int(c) or "")
  row.active = it.active and true or false
  row.tick:SetShown(row.active)
  row.label:SetTextColor(W.color("ink"))
  slipUnder(row)
end

function D.NewSlipList(parent, opts)
  opts = type(opts) == "table" and opts or {}
  local list = W.NewList(parent, { rows = min(W.LIMITS.listRows, tonumber(opts.rows) or 10), rowHeight = tonumber(opts.rowHeight) or 20,
    width = opts.width, step = opts.step,
    build = function(row) D.SlipRow(row) end,
    clear = function(row) D.SlipRowClear(row) end,
    fill = function(row, it) D.SlipRowFill(row, it) end,
    onClick = function(it) if opts.onPick then opts.onPick(it) end end })
  if list.track then list.track:SetColorTexture(W.color("ink", 0.15)) end
  list.frame:ClearAllPoints()
  return list
end

local POP_ROW_H = 20

local function buildPopup(dd)
  local o = dd.diaryOpts
  local pw = tonumber(o.popupWidth) or max(dd:GetWidth() or 0, 160)
  local pop = CreateFrame("Frame", nil, dd:GetParent())
  pop:SetFrameLevel((dd:GetFrameLevel() or 1) + 40)
  pop:EnableMouse(true)
  pop:SetWidth(pw)
  pop.slip = D.NewSlip(pop)
  local P = D.SLIP.pad
  local list = D.NewSlipList(pop, { rows = tonumber(o.rows) or 10, rowHeight = POP_ROW_H, width = pw - 2 * P,
    onPick = function(it) dd:Pick(it) end })
  list.frame:SetPoint("TOPLEFT", pop, "TOPLEFT", P, -P)
  pop.list = list
  escKeys(pop, function() dd:Close() end)
  local catcher = CreateFrame("Button", nil, UIParent)
  catcher:SetAllPoints(UIParent)
  if catcher.SetFrameStrata then catcher:SetFrameStrata("HIGH") end
  if catcher.RegisterForClicks then catcher:RegisterForClicks("AnyUp") end
  catcher:SetScript("OnClick", function() W.call(function() dd:Close() end) end)
  catcher:Hide()
  pop.catcher = catcher
  pop:HookScript("OnShow", function(p)
    catcher:SetFrameLevel(max(1, (p:GetFrameLevel() or 3) - 2))
    catcher:Show()
  end)
  pop:HookScript("OnHide", function()
    catcher:Hide()
    dd.open = false
    W.call(dd.diaryPaint, dd)
  end)
  pop:Hide()
  return pop
end

local function paintDrop(b)
  local on = (b.hover or b.open) and not b.disabled
  b.text:SetTextColor(W.color(on and "red" or "ink"))
end

function D.NewDropdown(parent, opts)
  opts = type(opts) == "table" and opts or {}
  local b = CreateFrame("Button", nil, parent)
  local size = tonumber(opts.size) or 15
  b:SetSize(tonumber(opts.width) or 140, size + 10)
  b.text = D.font(b, "text", size, "ink")
  b.text:SetPoint("LEFT", b, "LEFT", 4, 1)
  b.text:SetPoint("RIGHT", b, "RIGHT", -(size + 6), 1)
  b.text:SetJustifyH("LEFT")
  b.text:SetWordWrap(false)
  b.icon = D.mark(b, "down", size - 3, "ink")
  b.icon:SetPoint("RIGHT", b, "RIGHT", -3, 1)
  b.line = W.NewRect(b, "sepia", 0.85, "ARTWORK")
  b.line:SetHeight(2)
  b.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
  b.line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  b.items = type(opts.items) == "table" and opts.items or {}
  function b:SetText(t) W.setText(self.text, t) end
  function b:SetItems(items)
    self.items = type(items) == "table" and items or {}
    if self.open and self.pop then self:Open() end
  end
  function b:IsOpen() return self.open == true end
  function b:Open()
    if self.disabled then return end
    if type(opts.onOpen) == "function" then
      W.call(opts.onOpen, self)
      return
    end
    self.pop = self.pop or buildPopup(self)
    local pop, n = self.pop, #self.items
    local rows = pop.list.nRows
    pop:SetHeight(max(1, min(n, rows)) * POP_ROW_H + 2 * D.SLIP.pad)
    pop:ClearAllPoints()
    pop:SetPoint("TOPLEFT", self, "BOTTOMLEFT", -D.SLIP.pad, 0)
    self.open = true
    pop:Show()
    pop.list:SetItems(self.items)
    for i, it in ipairs(self.items) do
      if type(it) == "table" and it.active then pop.list:ScrollTo(i) end
    end
    pop.list:Refresh()
    paintDrop(self)
  end
  function b:Close()
    self.open = false
    if self.pop then self.pop:Hide() end
    paintDrop(self)
  end
  function b:Pick(it)
    if type(it) ~= "table" then return end
    self.value = it.value
    if not opts.keepText then self:SetText(it.text) end
    self:Close()
    if type(opts.onPick) == "function" then W.call(opts.onPick, it) end
  end
  behave(b, opts, paintDrop, function(self)
    if self.open then self:Close() else self:Open() end
  end)
  b:HookScript("OnHide", function(self) if self.open then self:Close() end end)
  b:SetText(opts.text)
  paintDrop(b)
  return b
end

local function paintCheck(b)
  local on = b.hover and not b.disabled
  b.text:SetTextColor(W.color(on and "red" or "ink"))
  b.box:SetVertexColor(W.color(on and "red" or "ink", b.box.diaryOk and 1 or 0.25))
  b.tick:SetShown(b.checked and true or false)
end

function D.NewCheck(parent, text, opts)
  opts = type(opts) == "table" and opts or {}
  local b = CreateFrame("Button", nil, parent)
  local size = tonumber(opts.size) or 14
  local box = size + 6
  b:SetHeight(box + 4)
  b.box = D.mark(b, "box", box, "ink")
  b.box:SetPoint("LEFT", b, "LEFT", 0, 0)
  b.tick = D.mark(b, "tick", box + 6, "red", "OVERLAY")
  b.tick:SetPoint("CENTER", b.box, "CENTER", 4, 4)
  b.text = D.font(b, "label", size, "ink")
  b.text:SetPoint("LEFT", b.box, "RIGHT", 8, 0)
  b.text:SetWordWrap(false)
  b.checked = opts.checked and true or false
  b.text.diaryRefit = function() b:SetLabel(b.labelText) end
  function b:SetLabel(t)
    self.labelText = t
    W.setText(self.text, t)
    self:SetWidth(floor(box + 8 + textWidth(self.text, type(t) == "string" and #t or 0) + 4 + 0.5))
  end
  function b:GetChecked() return self.checked end
  function b:SetChecked(on, silent)
    self.checked = on and true or false
    paintCheck(self)
    if not silent and type(opts.onChange) == "function" then W.call(opts.onChange, self.checked, self) end
  end
  behave(b, opts, paintCheck, function(self) self:SetChecked(not self.checked) end)
  b:SetLabel(text)
  paintCheck(b)
  return b
end

local HEAD = { arrow = 11, funnel = 10, pad = 8, padR = 4 }
D.HEAD = HEAD

local function funnel(parent)
  local f = CreateFrame("Frame", nil, parent)
  local s = HEAD.funnel
  f:SetSize(s, s)
  local segs = { { 0, 1, s, 1 }, { 0, 1, s * 0.4, s * 0.55 }, { s, 1, s * 0.6, s * 0.55 }, { s * 0.4, s * 0.55, s * 0.4, s },
    { s * 0.6, s * 0.55, s * 0.6, s } }
  for _, g in ipairs(segs) do
    local l = f:CreateLine(nil, "ARTWORK")
    l:SetThickness(1.6)
    l:SetColorTexture(W.color("blue", 1))
    l:SetStartPoint("TOPLEFT", f, g[1], -g[2])
    l:SetEndPoint("TOPLEFT", f, g[3], -g[4])
  end
  return f
end

local function headLayout(b)
  b.text:ClearAllPoints()
  b.arrow:ClearAllPoints()
  b.funnel:ClearAllPoints()
  local last = b.text
  if b.right then
    b.text:SetPoint("RIGHT", b, "RIGHT", -HEAD.padR, 1)
    if b.active then
      b.arrow:SetPoint("RIGHT", last, "LEFT", -4, 0)
      last = b.arrow
    end
    b.funnel:SetPoint("RIGHT", last, "LEFT", -4, 0)
  else
    b.text:SetPoint("LEFT", b, "LEFT", HEAD.pad, 1)
    if b.active then
      b.arrow:SetPoint("LEFT", last, "RIGHT", 4, 0)
      last = b.arrow
    end
    b.funnel:SetPoint("LEFT", last, "RIGHT", 4, 0)
  end
end

local function paintHead(b)
  local on, filt = b.active, b.filtered
  local color = (b.hover and not b.disabled) and "red" or (filt and "blue" or ((on or b.open) and "ink" or "sepia"))
  b.text:SetTextColor(W.color(color))
  b.arrow:SetShown(on and true or false)
  b.arrow:SetVertexColor(W.color("ink"))
  if on and not b.desc then b.arrow:SetTexCoord(0, 1, 1, 0) else b.arrow:SetTexCoord(0, 1, 0, 1) end
  b.funnel:SetShown(filt and true or false)
  headLayout(b)
end

function D.NewColumnHead(parent, opts)
  opts = type(opts) == "table" and opts or {}
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(tonumber(opts.width) or 100, tonumber(opts.height) or 20)
  b.key, b.right = opts.key, opts.right and true or false
  b.text = D.font(b, "label", tonumber(opts.size) or 12, "sepia")
  b.text:SetJustifyH(b.right and "RIGHT" or "LEFT")
  b.text:SetWordWrap(false)
  W.setText(b.text, D.upper(opts.title))
  b.arrow = b:CreateTexture(nil, "OVERLAY")
  b.arrow:SetSize(HEAD.arrow, HEAD.arrow)
  if Theme.TEX and Theme.TEX.arrow then b.arrow:SetTexture(Theme.TEX.arrow) end
  b.funnel = funnel(b)
  if opts.stroke ~= false then
    b.stroke = D.NewInkStroke(b, nil, "ink", 0.8)
    b.stroke:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, -2)
    b.stroke:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, -2)
  end
  b.Paint = paintHead
  b.Layout = headLayout
  function b:SetState(st)
    st = type(st) == "table" and st or {}
    self.active, self.desc, self.filtered, self.open = st.active and true or false, st.desc and true or false,
      st.filtered and true or false, st.open and true or false
    paintHead(self)
  end
  behave(b, { tip = opts.tip, disabledTip = opts.disabledTip }, paintHead, function(self)
    if type(opts.onClick) == "function" then opts.onClick(self) end
    if self.hover then showTip(self) end
  end)
  paintHead(b)
  return b
end

local function rowPaint(row)
  local st = row.diaryRow
  if not st then return end
  for i, fs in ipairs(st.texts) do
    if row.hover then
      if not st.saved[i] then
        local raw = fs.inkRaw
        st.saved[i] = raw and { raw[1], raw[2], raw[3], raw[4] } or { W.color("ink") }
      end
      fs:SetTextColor(W.color("red"))
    elseif st.saved[i] then
      local c = st.saved[i]
      st.saved[i] = nil
      fs:SetTextColor(c[1], c[2], c[3], c[4])
    end
  end
  st.sel:SetShown(row.selected and true or false)
end

function D.RowStyle(row, opts)
  if type(row) ~= "table" or row.diaryRow then return row end
  opts = type(opts) == "table" and opts or {}
  local texts = {}
  for _, fs in ipairs(type(opts.texts) == "table" and opts.texts or { row.label }) do
    if type(fs) == "table" and fs.SetTextColor then texts[#texts + 1] = fs end
  end
  local st = { texts = texts, saved = {} }
  row.diaryRow = st
  if opts.line ~= false then
    st.line = W.NewRect(row, D.ROW_LINE.color, D.ROW_LINE.alpha, "BACKGROUND")
    st.line:SetHeight(1)
    st.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    st.line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  end
  st.sel = W.NewOutline(row, 10, 10, "red", 0.9)
  st.sel:SetAllPoints(row)
  st.sel:Hide()
  row:HookScript("OnEnter", function(r)
    r.hover = true
    rowPaint(r)
  end)
  row:HookScript("OnLeave", function(r)
    r.hover = false
    rowPaint(r)
  end)
  row:HookScript("OnHide", function(r)
    if r.hover then
      r.hover = false
      rowPaint(r)
    end
  end)
  function row:SetSelected(on)
    self.selected = on and true or false
    rowPaint(self)
  end
  return row
end

function D.rowFilled(row)
  local st = type(row) == "table" and row.diaryRow
  if not st or not row.hover then return end
  local r, g, b = W.color("red")
  for i, fs in ipairs(st.texts) do
    local raw = fs.inkRaw
    if st.saved[i] and raw and not (raw[1] == r and raw[2] == g and raw[3] == b) then
      st.saved[i] = { raw[1], raw[2], raw[3], raw[4] }
    end
  end
  rowPaint(row)
end

local function paintBadge(b)
  b.face:SetScale((b.clickable and b.hover and not b.disabled) and 1.1 or 1)
end

function D.NewBadge(parent, opts)
  opts = type(opts) == "table" and opts or {}
  local red = opts.color == "red"
  local size = tonumber(opts.size) or 34
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b.face = face(b)
  b.face:SetSize(size, size)
  local disc = D.mark(b.face, red and "badgeRed" or "badgeGold", size, nil, "ARTWORK")
  disc:SetAllPoints(b.face)
  if disc.diaryOk and Theme.rotCoords8 then
    local u0, u1, v0, v1 = Theme.diaryCoords(red and "badgeRed" or "badgeGold")
    disc:SetTexCoord(Theme.rotCoords8(u0, u1, v0, v1, size, size, red and 6 or -8))
  elseif not disc.diaryOk then
    disc:SetColorTexture(W.color(red and "red" or "gold", 1))
  end
  b.disc = disc
  b.text = D.font(b.face, "title", tonumber(opts.textSize) or 12, "ink")
  b.text:SetPoint("CENTER", b.face, "CENTER", 0, 1)
  b.clickable = type(opts.onClick) == "function"
  function b:SetValue(v)
    if type(v) == "number" then
      v = Journal.Texts and Journal.Texts.int and Journal.Texts.int(v) or tostring(floor(v))
    end
    W.setText(self.text, v)
  end
  behave(b, opts, paintBadge, function(self) if opts.onClick then opts.onClick(self) end end)
  if not b.clickable and b.EnableMouse and not opts.tip then b:EnableMouse(false) end
  b:SetValue(opts.value)
  paintBadge(b)
  return b
end

function D.NewSectionHead(parent, text, opts)
  opts = type(opts) == "table" and opts or {}
  local f = CreateFrame("Frame", nil, parent)
  local size = tonumber(opts.size) or 22
  f.text = D.font(f, "hand", size, "red")
  f.text:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 4)
  f.text:SetJustifyH("LEFT")
  f.text:SetWordWrap(false)
  f.line = D.NewInkStroke(f, nil, "red", 0.35)
  f.line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
  f.line:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  f.text.diaryRefit = function() f:SetText(f.textValue) end
  function f:SetText(t)
    self.textValue = t
    W.setText(self.text, t)
    local w = tonumber(opts.width) or floor(textWidth(self.text, type(t) == "string" and #t or 0) + 16 + 0.5)
    self:SetSize(w, size + 10)
  end
  f:SetText(text)
  return f
end
