-- Note slip building blocks (1.1.0, core): the paper of a small on-screen note in two styles, "pad" (note pad, image or paper
-- fallback) and "plain" (dark box), plus fonts, colours, the small "x" close button and the screen clamp. Shared by the quick
-- note (journal/QuickNote.lua, core: notes belong to the journal) and the to-do note (journal/TodoTracker.lua, module Plans),
-- so the quick note works without the Plans module. Taken over unchanged from TodoTracker (which re-exports them).
local _, ns = ...

local Journal = ns.Journal
local W = Journal and Journal.Widgets
local D = W and W.Diary
if not (W and D) then return end
local Theme = Journal.Theme

local floor, max, min = math.floor, math.max, math.min

local Slip = {}
W.Slip = Slip

Slip.DEFAULT_STYLE = "pad"
Slip.CLOSE_W = 14
Slip.METRICS = {
  pad = { padL = 0.15, padLMin = 30, padR = 16, top = 14, head = 26, bodyGap = 10, padB = 18, icon = 15, gap = 6, rowGap = 5,
    titleSize = 22, textSize = 16, extraSize = 13, moreSize = 13, rule = 27 },
  plain = { padL = 0, padLMin = 9, padR = 9, top = 6, head = 18, bodyGap = 5, padB = 9, icon = 13, gap = 6, rowGap = 4,
    titleSize = 13, textSize = 12, extraSize = 11, moreSize = 11 },
}
Slip.PLAIN = { bg = { 0.04, 0.04, 0.05, 0.55 }, border = { 0.78, 0.68, 0.45, 0.45 }, title = { 1, 0.82, 0.1, 1 },
  text = { 0.94, 0.92, 0.86, 1 }, extra = { 0.72, 0.72, 0.72, 1 }, hover = { 1, 0.86, 0.35, 1 }, done = { 0.6, 0.6, 0.6, 1 } }
Slip.PAD = { title = "red", text = "ink", extra = "sepia", hover = "red", done = "sepia", line = { 0.27, 0.23, 0.19, 0.42 } }
Slip.PAD_SLICE = { top = { 0, 0.16 }, mid = { 0.62, 0.80 }, bottom = { 0.84, 1 }, edge = 38 }

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function screenSize()
  local sw = UIParent and UIParent.GetWidth and num(UIParent:GetWidth()) or nil
  local sh = UIParent and UIParent.GetHeight and num(UIParent:GetHeight()) or nil
  if not sw or sw <= 0 then sw = 1920 end
  if not sh or sh <= 0 then sh = 1080 end
  return sw, sh
end
Slip.screenSize = screenSize

function Slip.clampPos(x, y, w, h)
  local sw, sh = screenSize()
  x, y = num(x) or 0, num(y) or sh
  x = max(0, min(x, sw - w))
  y = min(sh, max(y, h))
  return floor(x + 0.5), floor(y + 0.5)
end

local function setFont(fs, kind, size)
  local FONT = Theme.FONT or {}
  local file = FONT[kind] or FONT.text
  local ok, res = pcall(fs.SetFont, fs, file, size, "")
  if (not ok or res == false) and kind == "hand" then
    pcall(fs.SetFont, fs, FONT.text, floor(size * (D.HAND_FALLBACK_SCALE or 0.72) + 0.5), "")
  end
end

local function fontString(parent, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  fs.inkPlain = true
  setFont(fs, "text", 12)
  fs:SetText("")
  return fs
end

local function colorOf(c, a)
  if type(c) == "string" then return W.color(c, a) end
  if type(c) == "table" then return c[1] or 0, c[2] or 0, c[3] or 0, a or c[4] or 1 end
  return 1, 1, 1, a or 1
end

local function rect(parent, layer, sub)
  local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
  return t
end

local function useTex(t, file)
  if type(file) ~= "string" then return false end
  local ok, res = pcall(t.SetTexture, t, file)
  return ok and res ~= false
end

Slip.fontString, Slip.setFont, Slip.colorOf, Slip.rect, Slip.useTex = fontString, setFont, colorOf, rect, useTex

function Slip.newPad(f)
  local pad = CreateFrame("Frame", nil, f)
  pad:SetAllPoints(f)
  pad:SetFrameLevel((f:GetFrameLevel() or 1))
  pad.pieces = {}
  local img = Theme.HAS_TODO_PAD and Theme.TEX.todoPad and Theme.TODO_PAD_SLICE
  local S = img and Theme.TODO_PAD_SLICE or Slip.PAD_SLICE
  local file = img and Theme.TEX.todoPad or (Theme.paper and select(1, Theme.paper("notizen")) or nil)
  pad.image = img and true or false
  if not pad.image then
    pad.shadow = rect(pad, "BACKGROUND", -2)
    pad.shadow:SetColorTexture(0, 0, 0, 0.35)
    pad.shadow:SetPoint("TOPLEFT", pad, "TOPLEFT", 4, -5)
    pad.shadow:SetPoint("BOTTOMRIGHT", pad, "BOTTOMRIGHT", 4, -5)
  end
  for i, key in ipairs({ "top", "mid", "bottom" }) do
    local t = rect(pad, "BACKGROUND", 0)
    if not useTex(t, file) then t:SetColorTexture(colorOf(Theme.C.card)) end
    t:SetTexCoord(0, 1, S[key][1], S[key][2])
    pad.pieces[i] = t
  end
  local top, mid, bottom = pad.pieces[1], pad.pieces[2], pad.pieces[3]
  top:SetPoint("TOPLEFT", pad, "TOPLEFT", 0, 0)
  top:SetPoint("TOPRIGHT", pad, "TOPRIGHT", 0, 0)
  top:SetHeight(S.edge or 38)
  bottom:SetPoint("BOTTOMLEFT", pad, "BOTTOMLEFT", 0, 0)
  bottom:SetPoint("BOTTOMRIGHT", pad, "BOTTOMRIGHT", 0, 0)
  bottom:SetHeight(S.edge or 38)
  mid:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, 0)
  mid:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT", 0, 0)
  if not pad.image then
    pad.tape = rect(pad, "BORDER", 1)
    if useTex(pad.tape, Theme.HAS_DIARY and Theme.TEX.diaryTape or nil) then
      pad.tape:SetTexCoord(0, 1, 0, 1)
    else
      pad.tape:SetColorTexture(0.89, 0.84, 0.69, 0.8)
    end
    pad.tape:SetSize(76, 20)
    pad.tape:SetPoint("CENTER", pad, "TOP", 0, -2)
  end
  return pad
end

function Slip.sizePad(pad, w, h)
  if not pad or not pad.image then return nil end
  local S = Theme.TODO_PAD_SLICE
  local a = S.aspect or 1
  local top = (S.top[2] - S.top[1]) * a * w
  local bottom = (S.bottom[2] - S.bottom[1]) * a * w
  local room = h - 8
  if top + bottom > room and top + bottom > 0 then
    local k = room / (top + bottom)
    top, bottom = top * k, bottom * k
  end
  top, bottom = floor(top + 0.5), floor(bottom + 0.5)
  pad.pieces[1]:SetHeight(top)
  pad.pieces[3]:SetHeight(bottom)
  pad.geo = { w = w, h = h, top = top, bottom = bottom }
  return top, bottom
end

function Slip.padY(pad, v)
  local g = pad and pad.image and pad.geo
  if not g then return nil end
  local S = Theme.TODO_PAD_SLICE
  local t0, t1, b0 = S.top[1], S.top[2], S.bottom[1]
  if v <= t1 then return (v - t0) / (t1 - t0) * g.top end
  if v >= b0 then return g.h - (S.bottom[2] - v) / (S.bottom[2] - b0) * g.bottom end
  return g.top + (v - t1) / (b0 - t1) * (g.h - g.top - g.bottom)
end

function Slip.newPlain(f)
  local plain = CreateFrame("Frame", nil, f)
  plain:SetAllPoints(f)
  plain:SetFrameLevel((f:GetFrameLevel() or 1))
  plain.bg = rect(plain, "BACKGROUND", 0)
  plain.bg:SetColorTexture(colorOf(Slip.PLAIN.bg))
  plain.bg:SetAllPoints(plain)
  plain.edges = {}
  for i, spec in ipairs({ { "TOPLEFT", "TOPRIGHT", "h" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "h" }, { "TOPLEFT", "BOTTOMLEFT", "v" },
    { "TOPRIGHT", "BOTTOMRIGHT", "v" } }) do
    local t = rect(plain, "BORDER", 0)
    t:SetColorTexture(colorOf(Slip.PLAIN.border))
    t:SetPoint(spec[1], plain, spec[1], 0, 0)
    t:SetPoint(spec[2], plain, spec[2], 0, 0)
    if spec[3] == "h" then t:SetHeight(1) else t:SetWidth(1) end
    plain.edges[i] = t
  end
  return plain
end

-- Small "x" in the head: hides the note; paint with Slip.paintClose(b, isPad).
function Slip.newClose(parent, onClick, title, hint)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(Slip.CLOSE_W, 16)
  b:RegisterForClicks("LeftButtonUp")
  b.label = fontString(b, "ARTWORK")
  b.label:SetPoint("CENTER", b, "CENTER", 0, 1)
  b.label:SetText("x")
  b:SetScript("OnClick", function()
    if GameTooltip then GameTooltip:Hide() end
    if ns.Core then ns.Core.safe(onClick) else onClick() end
  end)
  b:SetScript("OnEnter", function(self)
    self.hover = true
    Slip.paintClose(self, self.isPad)
    if GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine(title, 1, 0.82, 0)
      if hint then GameTooltip:AddLine(hint, 0.8, 0.8, 0.8, true) end
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function(self)
    self.hover = false
    Slip.paintClose(self, self.isPad)
    if GameTooltip then GameTooltip:Hide() end
  end)
  return b
end

function Slip.paintClose(b, isPad)
  if not b then return end
  b.isPad = isPad
  setFont(b.label, isPad and "hand" or "text", isPad and 18 or 12)
  local c = isPad and "sepia" or Slip.PLAIN.extra
  if b.hover then c = isPad and "red" or Slip.PLAIN.hover end
  b.label:SetTextColor(colorOf(c))
  if b.label.SetShadowOffset then b.label:SetShadowOffset(isPad and 0 or 1, isPad and 0 or -1) end
  if b.label.SetShadowColor then b.label:SetShadowColor(0, 0, 0, isPad and 0 or 0.9) end
end
