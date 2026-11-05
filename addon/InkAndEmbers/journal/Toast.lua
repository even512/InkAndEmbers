-- Moment toast: a small parchment toast at the top centre when (1) a medal tier was earned (tier image, name, tier; one toast
-- per new tier) or (2) a new area is entered (first ZN line of a zone, no subzones). Fed by the Store observer
-- (Store.observer), also while the journal is closed. No ticker.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Toast = {}
Journal.Toast = Toast

Toast.DURATION = 5
Toast.FADE_IN = 0.35
Toast.FADE_OUT = 0.5
Toast.GAP = 0.5
Toast.MAX_QUEUE = 6      -- above this, queued toasts of the same kind (medals, new zones) are merged into one
Toast.HARD_QUEUE = 14    -- last resort: the oldest zone toast (else the oldest) falls out
Toast.ZONETEXT_WAIT = 5  -- s after ZONE_CHANGED_NEW_AREA during which the game's own zone text is assumed to be showing
Toast.ZONETEXT_MAX = 12  -- never wait longer than this (s) for the zone text
Toast.MAX_AGE = 30
Toast.CHECK_DELAY = 3
-- Size and grid of the parchment strip: Toast.W : Toast.H = aspect ratio of the crop (scripts/render-media.mjs TOAST_CROP,
-- 3062 x 1272 = 2.407), so no distortion. Blot centre in the source image (348 | 668 px), scaled to 288 x 120 = ICON_X/ICON_Y.
-- Frame line in the crop: left x 10, right x 274, top y 7, bottom y 112.
Toast.W, Toast.H = 288, 120
Toast.ICON = 58           -- the blot is about 27 px: the image covers it completely
Toast.ICON_ZONE = 58
Toast.FLECK_X = 28
Toast.ICON_SHIFT = 15
Toast.ICON_X, Toast.ICON_Y = Toast.FLECK_X + Toast.ICON_SHIFT, 59
Toast.TEXT_GAP = 4
Toast.TEXT_SLACK = 8
Toast.TEXT_X = Toast.ICON_X + Toast.ICON / 2 + Toast.TEXT_GAP
Toast.TEXT_RIGHT = 16
Toast.FONT = { head = 13, title = 20, sub = 13 }
Toast.TEXT_Y = { head = 32, title = 48, sub = 73 }
-- Long lines are never cut with "…": first wrap to up to WRAP_LINES lines (the card grows downwards), then shrink the font
-- stepwise (down to MIN_SCALE); if that is not enough the line gets as many lines as needed. WRAP_FILL = usable share per line.
Toast.WRAP_LINES = 2
Toast.MIN_SCALE = 0.75
Toast.WRAP_FILL = 0.9
Toast.LINE_H = 1.25
Toast.TOP = -110
Toast.BELOW_FRAC = 0.12 -- top edge this share of the screen height under the screen centre (default place of every toast)
Toast.BELOW_FALLBACK = 768
function Toast.below()
  local h = type(UIParent) == "table" and UIParent.GetHeight and tonumber(UIParent:GetHeight()) or nil
  if not h or h ~= h or h < 200 then h = Toast.BELOW_FALLBACK end
  return h * Toast.BELOW_FRAC
end
Toast.NAME_MAX = 40
-- Card (welcome, recap): own background Media/WelcomeCard.tga (art/toast/welcome_card_v2.jpg, crop and measures in
-- scripts/render-media.mjs WELCOME_CARD_CROP; scale 640 / 2360 = 0.2712). Everything that depends on the image lives HERE:
-- a new background only needs a new texture (Theme.TEX.welcomeCard) and these constants.
-- w, h = card size (aspect of the crop 1.68 : 1); iconX/Y = centre of the medallion ring (px from top left), iconSize = edge
-- of the zone icon (covers the inner ring, the printed ornament ring stays visible); textX/textW = writing area right of it.
-- Text in Spectral (Theme.FONT.cardTitle / card; FONTKIND, fallback FALLBACK if the client cannot load it). Spectral looks
-- smaller than Friz at the same size (lower x-height), hence one step larger than before.
-- portrait = narrator of the welcome card (Media/Narrator_<id>.tga): circle diameter in px; the painted circle sits in the
-- printed ring (inner free area about 133 px, ornament ring up to 165 px), the figure may reach out of it above.
Toast.CARD = { w = 640, h = 381, iconX = 129, iconY = 175, iconSize = 150, textX = 246, textW = 364,
  textY = { center = 172, top = 34, bottom = 306 }, pitch = 19, gap = 8, entryGap = 5, headH = 18, titleH = 28, wrapLines = 3,
  maxLines = 4, duration = 10, tail = 3, FONT = { head = 13, title = 21, line = 15 }, tex = "welcomeCard",
  FONTKIND = { head = "cardTitle", title = "cardTitle", line = "card" }, FALLBACK = { head = "title", title = "title", line = "text" },
  portrait = { circle = 138 } }

Toast.TEXT = ns.Locale.ns("Toast", {
  medal = "Medaille verdient",
  zone = "Neues Gebiet",
  zoneSub = "Zum ersten Mal betreten",
  zoneUnknown = "Ein unbekanntes Land",
  testMedal = "Questbuch",
  testZone = "Tirisfal",
  on = "Einblendungen eingeschaltet. Neue Medaillen und Gebiete melden sich oben mittig. /chronik toast schaltet sie wieder aus.",
  off = "Einblendungen ausgeschaltet. /chronik toast schaltet sie wieder ein.",
  soundOn = "Ton der Einblendungen eingeschaltet.",
  soundOff = "Ton der Einblendungen ausgeschaltet. /chronik ton schaltet ihn wieder ein.",
  soundIds = "Töne: Gebiet %s, Medaille %s.",
  soundNone = "keiner gefunden",
  medalMany = "%d neue Medaillen", zoneMany = "%d neue Gebiete", andMore = "%s u. a.",
  testQueued = "Beispiel-Einblendungen eingereiht (nie im Kampf).",
  testWaitCombat = "Beispiel-Einblendungen warten: Du bist im Kampf. Sie erscheinen danach.",
  testOff = "Einblendungen sind ausgeschaltet. Mit /chronik toast an einschalten, dann nochmal testen.",
  testKindOff = "Beispiel-Einblendungen nicht eingereiht: Medaillen- und Gebiets-Einblendungen sind einzeln ausgeschaltet.",
  testBusy = "Eine Beispiel-Einblendung läuft schon.",
  usage = "/chronik toast [an|aus|test]",
  usageSound = "/chronik ton [an|aus]",
  noJournal = "Die Einblendungen sind noch nicht bereit.",
})

-- Sound candidates per kind, in trial order. name = SOUNDKIT constant (Retail), id = fixed SoundKit id as fallback if the
-- constant is missing. If both fail or the client rejects the id, the toast stays silent (no error).
Toast.SOUND = {
  zone = {
    { name = "IG_ABILITY_PAGE_TURN", id = 836 },
    { name = "IG_QUEST_LOG_OPEN", id = 844 },
  },
  medal = {
    { id = 12891 },
    { name = "UI_EPICLOOT_TOAST", id = 31578 },
    { name = "IG_QUEST_LIST_COMPLETE", id = 878 },
  },
}

local floor = math.floor

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function Pages() return Journal.Pages end

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function now()
  return type(GetTime) == "function" and GetTime() or 0
end

function Toast.enabled()
  local P = Pages()
  if not P or type(P.setting) ~= "function" then return true end
  return P.setting("toast") ~= false
end

function Toast.soundOn()
  local P = Pages()
  if not P or type(P.setting) ~= "function" then return true end
  return P.setting("toastSound") ~= false
end

function Toast.setEnabled(on)
  local P = Pages()
  local ok = P and P.setSetting("toast", on and true or false) or false
  if ok and Toast.gate then Toast.gate() end
  return ok
end

function Toast.setSound(on)
  local P = Pages()
  return P and P.setSetting("toastSound", on and true or false) or false
end

local KIND_SETTING = { medal = "toastMedal", zone = "toastZone", todo = "todoToast" }

function Toast.kindOn(kind)
  local key = KIND_SETTING[kind]
  local P = Pages()
  if not key or not P or type(P.setting) ~= "function" then return true end
  return P.setting(key) ~= false
end

function Toast.setKind(kind, on)
  local key = KIND_SETTING[kind]
  local P = Pages()
  if not key or not P then return false end
  return P.setSetting(key, on and true or false)
end

function Toast.soundIds(kind)
  local list = Toast.SOUND[kind]
  local out = {}
  if type(list) ~= "table" then return out end
  local kit = type(SOUNDKIT) == "table" and SOUNDKIT or nil
  for _, c in ipairs(list) do
    local id = kit and c.name and kit[c.name] or nil
    if isSecret(id) or type(id) ~= "number" then id = c.id end
    if type(id) == "number" and id > 0 and id == floor(id) then
      local dup = false
      for _, x in ipairs(out) do dup = dup or x == id end
      if not dup then out[#out + 1] = id end
    end
  end
  return out
end

function Toast.playSound(kind)
  local S = Journal.Sound
  if S and type(S.playChoice) == "function" then
    local r = S.playChoice(kind)
    if r == "off" then return nil end
    if r then return r end
  end
  return Toast.playDefault(kind)
end

function Toast.playDefault(kind)
  if type(PlaySound) ~= "function" then return nil end
  for _, id in ipairs(Toast.soundIds(kind)) do
    local ok, willPlay = pcall(PlaySound, id)
    if ok and willPlay ~= false then return id end
  end
  return nil
end

local frame, anim
local current
local token = 0
local fading = nil
local pumpPlanned = false
local hovering = false
local expired = false
local restSeq = 0
local tipShown = false
Toast.queue = {}

function Toast.getFrame() return frame end
function Toast.getCurrent() return current end

-- HUD hook (journal/EditMode.lua): Toast.hud = { place(f, item) -> true, duration(item) -> s | nil }
local function place(f, item)
  if Toast.hud and Toast.hud.place(f, item) then return end
  f:ClearAllPoints()
  f:SetScale(0.64) -- without the edit-mode holder: 80 % of the HUD base size, like EditMode.SCALE_DEFAULTS
  f:SetPoint("TOP", UIParent, "CENTER", 0, -Toast.below() / 0.64)
end

-- Card font: Spectral from Media/Fonts (Theme.FONT.card / cardTitle). The client loads an addon font file on the first SetFont;
-- if that fails (SetFont false or no font afterwards) the FontString gets the Theme fallback and fillCard tries again next time.
local function setCardFont(fs, part, size)
  local Theme = Journal.Theme
  local C = Toast.CARD
  fs.cardPart, fs.cardSize = part, size
  local file = Theme.FONT[C.FONTKIND[part]]
  if type(file) == "string" then
    local ok, res = pcall(fs.SetFont, fs, file, size, "")
    local got = ok and res ~= false and type(fs.GetFont) == "function" and fs:GetFont() or nil
    if got then
      fs.cardFontOk = true
      return true
    end
  end
  fs.cardFontOk = false
  Theme.font(fs, C.FALLBACK[part], size)
  return false
end
Toast.setCardFont = setCardFont

local function cardFontsRetry(f)
  local list = { f.cardHead, f.cardTitle }
  for _, fs in ipairs(f.cardLines) do list[#list + 1] = fs end
  for _, fs in pairs(f.probe) do list[#list + 1] = fs end
  for _, fs in ipairs(list) do
    if not fs.cardFontOk and fs.cardPart then setCardFont(fs, fs.cardPart, fs.cardSize) end
  end
end

-- Preload while the loading screen runs, so the first card already measures and draws in Spectral.
local function preloadCardFonts()
  local Theme = Journal.Theme
  if type(CreateFrame) ~= "function" or not Theme or not Theme.FONT then return end
  local f = CreateFrame("Frame", nil, UIParent)
  f:Hide()
  for _, kind in ipairs({ "card", "cardTitle" }) do
    local fs = f:CreateFontString(nil, "OVERLAY")
    if type(Theme.FONT[kind]) == "string" then pcall(fs.SetFont, fs, Theme.FONT[kind], 14, "") end
    fs:SetText("Äa")
  end
end
pcall(preloadCardFonts)

local function build()
  local Theme = Journal.Theme
  local f = CreateFrame("Button", nil, UIParent)
  f:SetSize(Toast.W, Toast.H)
  f:SetFrameStrata("DIALOG")
  f:EnableMouse(true)
  f:RegisterForClicks("LeftButtonUp")
  local paper = f:CreateTexture(nil, "BACKGROUND")
  paper:SetAllPoints(f)
  paper:SetTexture(Theme.TEX.toast)
  local icon = f:CreateTexture(nil, "ARTWORK")
  icon:SetSize(Toast.ICON, Toast.ICON)
  icon:SetPoint("CENTER", f, "TOPLEFT", Toast.ICON_X, -Toast.ICON_Y)
  local icon2 = f:CreateTexture(nil, "OVERLAY")
  icon2:SetPoint("CENTER", icon, "CENTER", 0, 0)
  icon2:Hide()
  f.icon2 = icon2
  local textW = Toast.W - Toast.TEXT_X - Toast.TEXT_RIGHT
  local function line(kind, size, color, y)
    local fs = Theme.fontString(f, kind, size, color, "OVERLAY", "CENTER", true)
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", Toast.TEXT_X, -y)
    fs:SetWidth(textW)
    fs:SetWordWrap(false)
    local okF, file, fsize, flags = pcall(fs.GetFont, fs)
    fs.baseFont = okF and type(file) == "string" and { file, tonumber(fsize) or size, flags } or nil
    fs.baseSize = size
    return fs
  end
  local head = line("title", Toast.FONT.head, Theme.C.sepia, Toast.TEXT_Y.head)
  local title = line("title", Toast.FONT.title, Theme.C.ink, Toast.TEXT_Y.title)
  local sub = line("text", Toast.FONT.sub, Theme.C.sepia, Toast.TEXT_Y.sub)
  f.paper, f.icon, f.head, f.title, f.sub = paper, icon, head, title, sub
  local C = Toast.CARD
  local function cardLine(part, color, y)
    local fs = Theme.fontString(f, C.FALLBACK[part], C.FONT[part], color, "OVERLAY", "CENTER", true)
    setCardFont(fs, part, C.FONT[part])
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", C.textX, -y)
    fs:SetWidth(C.textW)
    fs:SetWordWrap(false)
    fs:Hide()
    return fs
  end
  f.cardHead = cardLine("head", Theme.C.sepia, C.textY.center)
  f.cardTitle = cardLine("title", Theme.C.ink, C.textY.center)
  f.cardLines = {}
  for i = 1, C.maxLines do
    f.cardLines[i] = cardLine("line", i == 1 and Theme.C.ink or Theme.C.sepia, C.textY.center)
    f.cardLines[i]:SetJustifyV("TOP")
  end
  f.probe = {}
  for _, part in ipairs({ "head", "title", "line" }) do
    local fs = Theme.fontString(f, C.FALLBACK[part], C.FONT[part], Theme.C.ink, "OVERLAY", "LEFT", true)
    setCardFont(fs, part, C.FONT[part])
    fs:SetWordWrap(false)
    fs:Hide()
    f.probe[part] = fs
  end
  f.textX, f.textW = Toast.TEXT_X, textW

  anim = nil
  local inGroup = f:CreateAnimationGroup()
  local outGroup = f:CreateAnimationGroup()
  if type(inGroup) == "table" and type(outGroup) == "table" then
    local a = inGroup:CreateAnimation("Alpha")
    local o = outGroup:CreateAnimation("Alpha")
    if type(a) == "table" and type(o) == "table" then
      inGroup:SetToFinalAlpha(true)
      a:SetFromAlpha(0)
      a:SetToAlpha(1)
      a:SetDuration(Toast.FADE_IN)
      a:SetOrder(1)
      outGroup:SetToFinalAlpha(true)
      o:SetFromAlpha(1)
      o:SetToAlpha(0)
      o:SetDuration(Toast.FADE_OUT)
      o:SetOrder(1)
      -- Stop() can fire OnFinished: only a running fade-out ends the toast (never a stray finish(nil))
      outGroup:SetScript("OnFinished", function()
        if fading == nil then return end
        Toast.finish(fading)
      end)
      anim = { inGroup = inGroup, outGroup = outGroup, fadeIn = a, fadeOut = o }
    end
  end

  f:SetScript("OnClick", function() Toast.activate() end)
  f:SetScript("OnEnter", function() Toast.hover(true) end)
  f:SetScript("OnLeave", function() Toast.hover(false) end)
  f:Hide()
  return f
end

-- width of a line without limit (Retail: GetUnboundedStringWidth, else GetStringWidth)
local function textWidth(fs)
  for _, name in ipairs({ "GetUnboundedStringWidth", "GetStringWidth" }) do
    local fn = fs[name]
    if type(fn) == "function" then
      local ok, w = pcall(fn, fs)
      if ok and type(w) == "number" and w > 0 then return w end
    end
  end
  return 0
end

local function probeFor(kind)
  if not frame then
    local ok, f = pcall(build)
    if not ok then return nil end
    frame = f
  end
  return frame.probe and frame.probe[kind] or nil
end

function Toast.stringWidth(kind, text)
  local fs = probeFor(kind)
  if not fs then return nil end
  fs:SetText(text)
  local w = textWidth(fs)
  return w > 0 and w or nil
end

local function dropChar(s)
  local i = #s
  while i > 1 do
    local b = string.byte(s, i)
    if b >= 0x80 and b < 0xC0 then i = i - 1 else break end
  end
  return string.sub(s, 1, i - 1)
end

local function tidy(s)
  s = string.gsub(s, "[%s,;:%-]+$", "")
  local bars = string.match(s, "|+$")
  if bars and #bars % 2 == 1 then s = string.sub(s, 1, -2) end
  return s
end

function Toast.fit(kind, prefix, name, suffix, maxW)
  prefix, suffix = prefix or "", suffix or ""
  if type(name) ~= "string" then return prefix .. suffix end
  local full = prefix .. name .. suffix
  maxW = maxW or Toast.CARD.textW
  local w = Toast.stringWidth(kind, full)
  if not w or w <= maxW then return full end
  local ell = "…"
  local function ok(s)
    local x = Toast.stringWidth(kind, prefix .. s .. ell .. suffix)
    return not x or x <= maxW
  end
  local words = {}
  for word in string.gmatch(name, "%S+") do words[#words + 1] = word end
  for k = #words - 1, 1, -1 do
    local cand = tidy(table.concat(words, " ", 1, k))
    if cand ~= "" and ok(cand) then return prefix .. cand .. ell .. suffix end
  end
  local cut = words[1] or name
  while #cut > 1 do
    cut = tidy(dropChar(cut))
    if cut ~= "" and ok(cut) then return prefix .. cut .. ell .. suffix end
  end
  return prefix .. string.sub(cut, 1, #cut) .. ell .. suffix
end

function Toast.wrap(kind, text, maxW, maxLines)
  maxW = maxW or Toast.CARD.textW
  maxLines = maxLines or Toast.CARD.wrapLines
  if type(text) ~= "string" then return { "" } end
  local w = Toast.stringWidth(kind, text)
  if not w or w <= maxW then return { text } end
  local lines, rest = {}, text
  while rest ~= "" do
    if #lines == maxLines - 1 then
      lines[#lines + 1] = Toast.fit(kind, "", rest, "", maxW)
      break
    end
    local words = {}
    for word in string.gmatch(rest, "%S+") do words[#words + 1] = word end
    local k = 0
    for n = 1, #words do
      local x = Toast.stringWidth(kind, table.concat(words, " ", 1, n))
      if x and x > maxW then break end
      k = n
    end
    if k >= #words then
      lines[#lines + 1] = rest
      break
    elseif k > 0 then
      lines[#lines + 1] = table.concat(words, " ", 1, k)
      rest = table.concat(words, " ", k + 1)
    else
      local head = words[1]
      while #head > 1 do
        local x = Toast.stringWidth(kind, head)
        if not x or x <= maxW then break end
        head = dropChar(head)
      end
      local bars = string.match(head, "|+$")
      if bars and #bars % 2 == 1 then head = string.sub(head, 1, -2) end
      lines[#lines + 1] = head
      rest = string.sub(rest, #head + 1)
      rest = string.gsub(rest, "^%s+", "")
    end
  end
  return lines
end

local function setSize(fs, size)
  local b = fs.baseFont
  if not b or type(fs.SetFont) ~= "function" then return fs.baseSize or size end
  pcall(fs.SetFont, fs, b[1], size, b[3])
  return size
end

function Toast.fitLine(fs, maxW)
  local base = fs.baseSize or 13
  local size = setSize(fs, base)
  local function wrapMode(on)
    fs:SetWordWrap(on)
    if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(on) end
  end
  wrapMode(false)
  if fs.SetMaxLines then fs:SetMaxLines(0) end
  local w = textWidth(fs)
  if w <= maxW then return 1, size, w end
  local per = maxW * Toast.WRAP_FILL
  local lines = math.ceil(w / per)
  if lines > Toast.WRAP_LINES and fs.baseFont then
    local minSize = math.ceil(base * Toast.MIN_SCALE)
    while lines > Toast.WRAP_LINES and size > minSize do
      size = setSize(fs, size - 1)
      w = textWidth(fs)
      lines = math.max(1, math.ceil(w / per))
    end
  end
  if w <= maxW then return 1, size, w end
  lines = math.max(2, lines)
  wrapMode(true)
  return lines, size, w
end

local function layout(f)
  local maxW = Toast.W - Toast.TEXT_X - Toast.TEXT_RIGHT
  for _, fs in ipairs({ f.head, f.title, f.sub }) do fs:SetWidth(maxW) end
  local tw, extra = 0, {}
  local order = { { "head", f.head }, { "title", f.title }, { "sub", f.sub } }
  for _, e in ipairs(order) do
    local fs = e[2]
    local lines, size, w = Toast.fitLine(fs, maxW)
    fs.lines = lines
    extra[e[1]] = (lines - 1) * math.ceil(size * Toast.LINE_H)
    tw = math.max(tw, lines > 1 and maxW or w)
  end
  tw = math.min(maxW, math.max(40, math.ceil(tw) + 4))
  local x = Toast.TEXT_X + math.min(Toast.TEXT_SLACK, floor((maxW - tw) / 4))
  local shift = 0
  for _, e in ipairs(order) do
    local key, fs = e[1], e[2]
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", x, -(Toast.TEXT_Y[key] + shift))
    fs:SetWidth(tw)
    shift = shift + extra[key]
  end
  f.textX, f.textW, f.grow = x, tw, shift
  f:SetSize(Toast.W, Toast.H + shift)
end

local function paintTop(f, icon, size)
  local top = icon and icon.top
  if not (f.icon2 and top and top.tex) then
    if f.icon2 then f.icon2:Hide() end
    return
  end
  local px = floor(size * (top.scale or 1) + 0.5)
  f.icon2:SetSize(px, px)
  f.icon2:SetTexture(top.tex)
  local c = top.coords
  if c then f.icon2:SetTexCoord(c[1], c[2], c[3], c[4]) else f.icon2:SetTexCoord(0, 1, 0, 1) end
  local col = top.color or { 1, 1, 1 }
  f.icon2:SetVertexColor(col[1], col[2], col[3], 1)
  f.icon2:Show()
end

local function fillCard(f, item)
  local C = Toast.CARD
  local Theme = Journal.Theme
  f:SetSize(C.w, C.h)
  f.paper:SetTexture(Theme.TEX[C.tex] or Theme.TEX.toast)
  cardFontsRetry(f)
  for _, fs in ipairs({ f.head, f.title, f.sub }) do fs:Hide() end
  local slack = 4
  local headText = Toast.fit("head", "", item.head or "", "", C.textW - slack)
  local headH = headText ~= "" and C.headH or 0
  -- up to C.wrapLines lines per entry; if the block would leave top..bottom, fewer lines per entry (down to 2, "…" only then)
  local entries, total, titleLines
  for lim = C.wrapLines, 2, -1 do
    titleLines = Toast.wrap("title", item.title or "", C.textW - slack, lim)
    entries, total = {}, headH + #titleLines * C.titleH
    for i = 1, #f.cardLines do
      local t = item.lines[i]
      if type(t) == "string" then
        local ls = Toast.wrap("line", t, C.textW - slack, lim)
        entries[i] = ls
        total = total + #ls * C.pitch + (i > 1 and C.entryGap or 0)
      end
    end
    total = total + (next(entries) and C.gap or 0)
    if total <= C.textY.bottom - C.textY.top then break end
  end
  local titleText = table.concat(titleLines, "\n")
  local y = math.max(C.textY.top, math.min(C.textY.center - total / 2, C.textY.bottom - total))
  local function place(fs, text, h)
    fs:SetText(text)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", C.textX, -floor(y + 0.5))
    fs:SetSize(C.textW, h)
    fs:Show()
  end
  if headH > 0 then
    place(f.cardHead, headText, headH)
    y = y + headH
  else
    f.cardHead:SetText("")
    f.cardHead:Show()
  end
  place(f.cardTitle, titleText, #titleLines * C.titleH)
  y = y + #titleLines * C.titleH + (next(entries) and C.gap or 0)
  for i, fs in ipairs(f.cardLines) do
    local ls = entries[i]
    if ls then
      if i > 1 then y = y + C.entryGap end
      place(fs, table.concat(ls, "\n"), #ls * C.pitch)
      y = y + #ls * C.pitch
    else
      fs:SetText("")
      fs:Hide()
    end
  end
  local icon = item.icon
  if icon and icon.tex then
    local size, dy = C.iconSize, 0
    local NT = Theme.NARRATOR_TEX
    if icon.portrait and NT then
      -- narrator: painted circle (NT.r around NT.cx/cy of the texture) on the ring centre, texture larger (pop-out room)
      size = floor(C.portrait.circle * NT.size / (2 * NT.r) + 0.5)
      dy = (NT.size / 2 - NT.cy) * size / NT.size
    end
    f.icon:ClearAllPoints()
    f.icon:SetPoint("CENTER", f, "TOPLEFT", C.iconX, -(C.iconY + dy))
    f.icon:SetSize(size, size)
    f.icon:SetTexture(icon.tex)
    if icon.coords then
      f.icon:SetTexCoord(icon.coords[1], icon.coords[2], icon.coords[3], icon.coords[4])
    else
      f.icon:SetTexCoord(0, 1, 0, 1)
    end
    if icon.color then f.icon:SetVertexColor(icon.color[1], icon.color[2], icon.color[3], 1) else f.icon:SetVertexColor(1, 1, 1, 1) end
    f.icon:Show()
    paintTop(f, icon, size)
  else
    f.icon:Hide()
    paintTop(f, nil)
  end
end

local function fill(f, item)
  f:SetSize(Toast.W, Toast.H)
  f.paper:SetTexture(Journal.Theme.TEX.toast)
  f.cardHead:Hide()
  f.cardTitle:Hide()
  for _, fs in ipairs(f.cardLines) do fs:Hide() end
  for _, fs in ipairs({ f.head, f.title, f.sub }) do fs:Show() end
  f.icon:ClearAllPoints()
  f.icon:SetPoint("CENTER", f, "TOPLEFT", Toast.ICON_X, -Toast.ICON_Y)
  if type(item.lines) == "table" then return fillCard(f, item) end
  f.head:SetText(item.head or "")
  f.title:SetText(item.title or "")
  f.sub:SetText(item.sub or "")
  local c = item.subColor or Journal.Theme.C.sepia
  f.sub:SetTextColor(c[1], c[2], c[3], 1)
  layout(f)
  local icon = item.icon
  if icon and icon.tex then
    local size = icon.size or Toast.ICON
    f.icon:SetSize(size, size)
    f.icon:SetTexture(icon.tex)
    if icon.coords then
      f.icon:SetTexCoord(icon.coords[1], icon.coords[2], icon.coords[3], icon.coords[4])
    else
      f.icon:SetTexCoord(0, 1, 0, 1) -- the image is reused: reset the tex coords
    end
    if icon.color then f.icon:SetVertexColor(icon.color[1], icon.color[2], icon.color[3], 1) else f.icon:SetVertexColor(1, 1, 1, 1) end
    f.icon:Show()
    paintTop(f, icon, size)
  else
    f.icon:Hide()
    paintTop(f, nil)
  end
end

local function hideTip()
  if not tipShown then return end
  tipShown = false
  if GameTooltip and (type(GameTooltip.GetOwner) ~= "function" or GameTooltip:GetOwner() == frame) then pcall(GameTooltip.Hide, GameTooltip) end
end

local function showTip(item)
  local tip = item.tooltip
  if type(tip) ~= "table" or not GameTooltip or not frame then return end
  local ok = pcall(function()
    GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
    GameTooltip:SetText(tip.title or "", 1, 0.82, 0)
    for _, l in ipairs(tip.lines or {}) do GameTooltip:AddLine(l, 1, 1, 1) end
    if tip.more then GameTooltip:AddLine(tip.more, 0.7, 0.7, 0.7) end
    GameTooltip:Show()
  end)
  tipShown = ok
end

function Toast.finish(t)
  if t ~= nil and t ~= token then return end
  token = token + 1
  fading = nil
  current = nil
  hovering, expired = false, false
  restSeq = restSeq + 1
  hideTip()
  if frame then
    if anim then
      anim.inGroup:Stop()
      anim.outGroup:Stop()
    end
    frame:Hide()
    frame:SetAlpha(1)
  end
  if #Toast.queue > 0 and not pumpPlanned and type(C_Timer) == "table" then
    pumpPlanned = true
    C_Timer.After(Toast.GAP, function()
      pumpPlanned = false
      Toast.pump()
    end)
  end
end

local function fadeOut(my)
  if my ~= token or not current then return end
  fading = my
  if frame and anim then
    frame:SetAlpha(1)
    anim.outGroup:Play()
    C_Timer.After(Toast.FADE_OUT + 0.15, function() Toast.finish(my) end) -- fallback if OnFinished never fires
  else
    Toast.finish(my)
  end
end

function Toast.hover(on)
  local item = current
  if not item or not item.hold or fading ~= nil then
    if not on then hideTip() end
    return
  end
  local my = token
  if on then
    hovering = true
    restSeq = restSeq + 1
    showTip(item)
    return
  end
  hovering = false
  hideTip()
  if expired then
    restSeq = restSeq + 1
    local seq = restSeq
    C_Timer.After(Toast.CARD.tail, function()
      if seq == restSeq and not hovering and my == token then fadeOut(my) end
    end)
  end
end

local zoneItemFor

local function present(item)
  if item.lazy then item = zoneItemFor(item) end   -- look up the name only now (never in combat)
  if not frame then frame = build() end
  fill(frame, item)
  current = item
  token = token + 1
  fading = nil
  local my = token
  if anim then
    anim.inGroup:Stop()
    anim.outGroup:Stop()
  end
  place(frame, item)
  frame:SetAlpha(anim and 0 or 1)
  frame:Show()
  if anim then anim.inGroup:Play() end
  if Toast.soundOn() and not item.silent then
    if item.sound then
      if Journal.Sound then Journal.Sound.play(item.sound) end
    else
      Toast.playSound(item.kind == "medal" and "medal" or "zone")
    end
  end
  hovering, expired = false, false
  restSeq = restSeq + 1
  C_Timer.After((Toast.hud and Toast.hud.duration(item)) or tonumber(item.duration) or Toast.DURATION, function()
    if my ~= token then return end
    if item.hold and hovering then
      expired = true
      return
    end
    fadeOut(my)
  end)
end

local function dropStale()
  local t = now()
  local q = Toast.queue
  for i = #q, 1, -1 do
    if t - (q[i].born or t) > (tonumber(q[i].maxAge) or Toast.MAX_AGE) then table.remove(q, i) end
  end
end

-- The game's own zone text (ZoneTextFrame / SubZoneTextFrame) comes first: while it shows, or for ZONETEXT_WAIT seconds after
-- ZONE_CHANGED_NEW_AREA, the queue waits (at most ZONETEXT_MAX seconds per toast, nothing is lost).
local zoneChangeAt = nil

local function frameShown(name)
  local f = rawget(_G, name)
  if type(f) ~= "table" or type(f.IsShown) ~= "function" then return false end
  local ok, shown = pcall(f.IsShown, f)
  if not ok or shown ~= true then return false end
  -- the game's FadingFrame can stay "shown" with alpha 0 after fading out: only visible and opaque counts
  if type(f.IsVisible) == "function" then
    local okV, vis = pcall(f.IsVisible, f)
    if okV and vis ~= true then return false end
  end
  if type(f.GetAlpha) == "function" then
    local okA, a = pcall(f.GetAlpha, f)
    if okA and type(a) == "number" and a <= 0.05 then return false end
  end
  return true
end

function Toast.zoneTextBusy()
  if frameShown("ZoneTextFrame") or frameShown("SubZoneTextFrame") then return true end
  return zoneChangeAt ~= nil and now() - zoneChangeAt < Toast.ZONETEXT_WAIT
end

local waitPlanned = false

-- Why the queue is not showing right now: "off" | "combat" | "zonetext" | nil (free)
function Toast.waitReason()
  if not Toast.enabled() then return "off" end
  if inCombat() then return "combat" end
  local first = Toast.queue[1]
  if first and not first.immediate and Toast.zoneTextBusy() then return "zonetext" end
  return nil
end

function Toast.pump()
  if current then return end
  dropStale()
  if not Toast.enabled() then
    local keep = {}
    for _, q in ipairs(Toast.queue) do
      if q.always then keep[#keep + 1] = q end
    end
    Toast.queue = keep
    if #keep == 0 then return end
  end
  if inCombat() then return end
  local first = Toast.queue[1]
  if first and not first.immediate and Toast.zoneTextBusy() and now() - (first.born or now()) < Toast.ZONETEXT_MAX then
    if not waitPlanned and type(C_Timer) == "table" then
      waitPlanned = true
      C_Timer.After(0.5, function()
        waitPlanned = false
        Toast.pump()
      end)
    end
    return
  end
  local item = table.remove(Toast.queue, 1)
  if not item then return end
  local ok = pcall(present, item)
  if not ok then
    current = nil
    if ns.Core and ns.Core.coreError then ns.Core.coreError("Einblendung konnte nicht angezeigt werden") end
  end
end

-- Merge queued toasts of one kind into a single one ("3 neue Medaillen"); nothing is dropped, only combined.
local function mergeKind(q, kind)
  local idx = {}
  for i, x in ipairs(q) do
    if x.kind == kind then idx[#idx + 1] = i end
  end
  if #idx < 2 then return false end
  local n, names = 0, {}
  for _, i in ipairs(idx) do
    local x = q[i]
    n = n + (x.count or 1)
    if kind == "medal" and type(x.title) == "string" and #names < 3 then names[#names + 1] = x.title end
  end
  local first = q[idx[1]]
  local merged
  if kind == "medal" then
    local sub = table.concat(names, ", ")
    if n > #names then sub = Toast.TEXT("andMore", sub) end
    merged = { kind = "medal", key = "merge:medal", open = "chronik", count = n, born = first.born, head = Toast.TEXT.medal,
      title = Toast.TEXT("medalMany", n), sub = sub, icon = first.icon }
  else
    merged = { kind = "zone", key = "merge:zone", open = "reise", count = n, born = first.born, head = Toast.TEXT.zone,
      title = Toast.TEXT("zoneMany", n), sub = Toast.TEXT.zoneSub, icon = Toast.zoneIcon() }
  end
  for k = #idx, 2, -1 do table.remove(q, idx[k]) end
  q[idx[1]] = merged
  return true
end

function Toast.enqueue(item)
  if type(item) ~= "table" or (not Toast.enabled() and not item.always) then return false end
  if not item.always and not Toast.kindOn(item.kind) then return false end
  if current and current.key ~= nil and current.key == item.key then return false end
  for _, q in ipairs(Toast.queue) do
    if q.key ~= nil and q.key == item.key then return false end
  end
  item.born = now()
  local q = Toast.queue
  if item.immediate then
    local at = 1
    while q[at] and q[at].immediate do at = at + 1 end
    table.insert(q, at, item)
  else
    q[#q + 1] = item
  end
  if #q > Toast.MAX_QUEUE then
    mergeKind(q, "medal")
    if #q > Toast.MAX_QUEUE then mergeKind(q, "zone") end
  end
  while #q > Toast.HARD_QUEUE do
    -- full: sacrifice the oldest zone toast first (medals are rarer and more valuable), else the oldest
    local drop = 1
    for i, x in ipairs(q) do
      if x.kind == "zone" then drop = i break end
    end
    table.remove(q, drop)
  end
  Toast.pump()
  return true
end

function Toast.activate()
  local item = current
  if not item then return false end
  Toast.finish(token)
  if item.noOpen then return true end
  local Access, Frame = Journal.Access, Journal.Frame
  if not Access or not Frame then return false end
  if not Access.isOpen() and not Access.open() then return false end
  Frame.showPage(item.open or "chronik")
  if type(item.after) == "function" then pcall(item.after) end
  return true
end

local function zoneName(mapID)
  local name
  local Store = ns.Store
  local char = Store and Store.char and Store.char()
  local snaps = type(char) == "table" and char.snapshots
  local maps = type(snaps) == "table" and snaps.maps
  local e = type(maps) == "table" and (maps[mapID] or maps[string.format("%.0f", mapID)]) or nil
  if type(e) == "table" then name = e.name end
  if isSecret(name) or type(name) ~= "string" or name == "" then
    local info = ns.Zone and ns.Zone.info(mapID)
    name = info and info.name or nil
  end
  if isSecret(name) or type(name) ~= "string" then return nil end
  return ns.Sanitize.display(name, Toast.NAME_MAX)
end

function Toast.zoneIcon()
  local Theme = Journal.Theme
  if Theme.TEX.zoneSeal then return { tex = Theme.TEX.zoneSeal, size = Toast.ICON_ZONE } end
  return { tex = Theme.TEX.markers, coords = { Theme.atlasCoords(Theme.ATLAS.milestone) }, color = Theme.C.sepia, size = 40 }
end

function Toast.zoneItem(mapID, name)
  return {
    kind = "zone", key = "zone:" .. tostring(mapID), open = "reise",
    head = Toast.TEXT.zone, title = name or Toast.TEXT.zoneUnknown, sub = Toast.TEXT.zoneSub,
    icon = Toast.zoneIcon(),
  }
end

function Toast.zoneStub(mapID)
  return { kind = "zone", key = "zone:" .. tostring(mapID), open = "reise", mapID = mapID, lazy = true }
end

zoneItemFor = function(stub)
  local item = Toast.zoneItem(stub.mapID, zoneName(stub.mapID))
  item.born = stub.born
  return item
end

function Toast.medalItem(i, seal, tier)
  local Theme, Chronik = Journal.Theme, Journal.Chronik
  tier = tier or seal.tier or (seal.steps and "bronze") or "bronze"
  local t = Chronik.TIERS[tier]
  local base, top = Theme.sealLayers(seal, tier)
  local bs = base.scale or 1
  local icon = { tex = base.tex, coords = base.coords, color = base.color, size = floor(Toast.ICON * bs + 0.5) }
  if top then
    icon.top = { tex = top.tex, coords = top.coords, color = top.color, scale = (top.scale or 1) / bs }
  end
  return {
    kind = "medal", key = "medal:" .. tostring(seal.id) .. ":" .. tostring(tier), open = "chronik",
    head = Toast.TEXT.medal, title = seal.title, sub = t and t.label or nil, subColor = t and t.color or nil,
    icon = icon,
  }
end

local known = {}
local baseGuid = nil
local dirty = false
local checkPlanned = false
local rerun = false
local silent = false
local wasOn = true
local savedGuid = nil
-- Pre-filter state of the last evaluation per medal: open[id] = a tier is still open; need[id] = amount missing to the next
-- tier (counting medals), next[id] = next threshold (value medals), pend[id] = lines counted / values summed since;
-- evalAt = time of the evaluation (time medals)
local watchState = nil

local function loginAt()
  local Store = ns.Store
  return Store and tonumber(Store.loginAt) or nil
end

local function now_()
  return type(time) == "function" and time() or 0
end

-- Start state of an existing character: on its first login with the addon the collectors write what the character already
-- has (gold balance GD 'start', played time PL with the level, professions, guild 'seen', gear). Medal tiers proven by
-- that within Toast.START_GRACE seconds are earned quietly (in the book, no toast). Only if the character came in above
-- level 1 (Store.fresh.level): a new character (level 1, e.g. every new one in Forever) behaves exactly as before.
Toast.START_GRACE = 120
local function quietUntil()
  local Store = ns.Store
  local f = Store and Store.fresh
  if type(f) ~= "table" then return nil end
  local at, level = tonumber(f.at), tonumber(f.level)
  if not at or not level or level <= 1 then return nil end
  return at + Toast.START_GRACE
end

-- proof time of a tier (s.at) or, for tiers without one (counters), the time of the evaluation
local function fromStart(s, untilT)
  if not untilT then return false end
  local t = type(s.at) == "number" and s.at or now_()
  return t < untilT
end

function Toast.rebase()
  known, baseGuid = {}, nil
  watchState = nil
  silent = true
  dirty = true
end

local schedule
local function gate()
  local on = Toast.enabled()
  if on and not wasOn then
    wasOn = true
    Toast.rebase()
    schedule()
  end
  wasOn = on
  return on
end

local function noteWatch(seals)
  local Chronik = Journal.Chronik
  local st = { open = {}, need = {}, next = {}, pend = {}, evalAt = now_() }
  for i, e in ipairs(seals.list) do
    local def = Chronik.SEALS[i]
    if def and e.id == def.id then
      local open = (def.steps and e.nextK ~= nil) or (not def.steps and not e.broken)
      st.open[def.id] = open or nil
      if open and def.steps and e.nextNeed then
        st.need[def.id] = e.left or (e.nextNeed - (tonumber(e.value) or 0))
        st.next[def.id] = e.watchNext or e.nextNeed
      end
    end
  end
  watchState = st
end

-- Store tiers (snapshots.medals["<id>:<tier>"] = { t, level }), logged-in character only. The first save of a session is the
-- data baseline: tiers without a timestamp (counters) get none then (legacy); later ones get now as their date.
function Toast.remember(index, seals)
  local Store, Chronik = ns.Store, Journal.Chronik
  if not (Store and Store.putSnapshot and Chronik and Chronik.unsavedSteps) then return 0 end
  if type(index) ~= "table" or index.stale or not index.char or Store.current ~= index.char then return 0 end
  seals = seals or Chronik.sealsOf(index)
  local first = savedGuid ~= index.guid
  savedGuid = index.guid
  local Live = Journal.Live
  local level = Live and Live.level and Live.level() or nil
  local n = 0
  for _, u in ipairs(Chronik.unsavedSteps(seals, index.char, { now = (not first) and now_() or nil, level = level })) do
    if Store.putSnapshot("medals", u.key, { t = u.t, level = u.level, seen = true }) then n = n + 1 end
  end
  return n
end

function Toast.evaluate(index)
  local Chronik = Journal.Chronik
  if type(index) ~= "table" or not Chronik or not Chronik.sealsOf then return 0 end
  if not gate() then return 0 end
  if inCombat() then
    dirty = true
    return 0
  end
  local seals = Chronik.sealsOf(index)
  if type(seals) ~= "table" or type(seals.list) ~= "table" then return 0 end
  local n = 0
  local baseline = baseGuid ~= index.guid
  local since = loginAt()
  local quiet = quietUntil()
  if baseline then
    baseGuid = index.guid
    known = {}
  end
  for i, e in ipairs(seals.list) do
    for k = 1, (e.max or 1) do
      local s = e.steps and e.steps[k]
      if s then
        local key = e.id .. ":" .. s.tier
        if not known[key] then
          known[key] = true
          local announce = not (baseline and silent) and (not baseline or (since ~= nil and type(s.at) == "number" and s.at >= since))
          if announce and fromStart(s, quiet) then announce = false end
          if announce and Chronik.SEALS[i] and Toast.enqueue(Toast.medalItem(i, Chronik.SEALS[i], s.tier)) then n = n + 1 end
        end
      end
    end
  end
  if baseline then silent = false end
  noteWatch(seals)
  Toast.remember(index, seals)
  return n
end

local function runCheck()
  checkPlanned = false
  if not dirty then return end
  if not gate() then
    dirty = false
    return
  end
  if inCombat() then return end
  local Index = Journal.Index
  if not Index then return end
  dirty = false
  local busy = Index.building()
  local ok, index = pcall(Index.get, {})
  if not ok or type(index) ~= "table" then
    rerun = busy
    return
  end
  if index.stale then
    rerun = busy
    return
  end
  rerun = false
  Toast.evaluate(index)
end

schedule = function()
  if checkPlanned or type(C_Timer) ~= "table" then return end
  checkPlanned = true
  C_Timer.After(Toast.CHECK_DELAY, function() Toast.safe(runCheck) end)
end

function Toast.safe(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok and ns.Core and ns.Core.coreError then ns.Core.coreError(err) end
  return ok
end

local function onReady(index)
  if not gate() then
    if not inCombat() then Toast.remember(index) end
    return
  end
  Toast.evaluate(index)
  if rerun then
    rerun = false
    dirty = true
    schedule()
  end
end

-- Observer: which lines can complete a medal tier? Only a pre-filter; Chronik.sealsOf decides. Based on the watch entries of
-- the catalog: a line counts for a medal (test), its value is measured against the next threshold (value), summed (add) or
-- elapsed time counts (elapsed). Evaluated only when the line CAN reach the next open tier, not on every kill.

local watchByCode = nil
local function watches(code)
  if not watchByCode then
    local Chronik = Journal.Chronik
    if not Chronik then return nil end
    watchByCode = {}
    for _, seal in ipairs(Chronik.SEALS) do
      for _, w in ipairs(seal.watch or {}) do
        for _, c in ipairs(w.codes or { w.code }) do
          local l = watchByCode[c]
          if not l then
            l = {}
            watchByCode[c] = l
          end
          l[#l + 1] = { seal = seal, w = w }
        end
      end
    end
  end
  return watchByCode[code]
end
Toast.watches = watches

local function num(v) return tonumber(v) end

local function accessor(code, f)
  local Index = Journal.Index
  local pos = Index and Index.fields and Index.fields(code)
  return function(name)
    local i = pos and pos[name]
    local v = i and f[i]
    if v == nil or isSecret(v) then return nil end
    return tostring(v)
  end
end

local LIVE_CHECK = { KF = true, RA = true, ZN = true }
local function liveCrossed()
  local Chronik, Store = Journal.Chronik, ns.Store
  if not (Chronik and Store and watchState) then return false end
  for _, seal in ipairs(Chronik.SEALS) do
    if seal.live and watchState.open[seal.id] and watchState.next[seal.id] then
      local v = Chronik.counterValue(seal.id, Store.current)
      if v and v >= watchState.next[seal.id] then return true end
    end
  end
  return false
end

function Toast.relevant(code, f)
  if LIVE_CHECK[code] and liveCrossed() then return true end
  local list = watches(code)
  if not list then return false end
  local st = watchState
  local F
  local hit = false
  for _, x in ipairs(list) do
    local id, w = x.seal.id, x.w
    if st == nil then
      F = F or accessor(code, f)
      if w.value then
        local first = w.first
        if first == nil then first = x.seal.steps and x.seal.steps[1] or Journal.Chronik.maxLevel() end
        local v = first and w.value(F)
        if v and v >= first then return true end
      elseif not w.elapsed and (w.always or not w.test or w.test(F)) then
        return true
      end
    elseif st.open[id] then
      F = F or accessor(code, f)
      if w.always then
        hit = true
      elseif w.elapsed then
        local need = st.need[id]
        if need and (now_() - st.evalAt) >= need then hit = true end
      elseif not w.test or w.test(F) then
        if w.value then
          local v = w.value(F)
          if v and st.next[id] and v >= st.next[id] then hit = true end
        else
          local add = w.add and (w.add(F) or 0) or 1
          st.pend[id] = (st.pend[id] or 0) + add
          if st.need[id] == nil or st.pend[id] >= st.need[id] then hit = true end
        end
      end
    end
  end
  return hit
end

function Toast.onLine(code, f)
  if type(f) ~= "table" then return end
  if not gate() then return end
  if code == "ZN" then
    -- First entry into a zone (mapType 3); subzones, caves and city maps do not count. Only the stub is queued; the name is
    -- looked up on show (never in combat).
    if f[2] == "3" then
      local id = num(f[1])
      if id and id > 0 and id == floor(id) then Toast.enqueue(Toast.zoneStub(id)) end
    end
  end
  if Toast.relevant(code, f) then
    dirty = true
    schedule()
  end
end

local function install()
  local Store = ns.Store
  if not Store or Toast.installed then return end
  Toast.installed = true
  local prev = Store.observer
  Store.observer = function(code, fields)
    if type(prev) == "function" then pcall(prev, code, fields) end
    Toast.onLine(code, fields)
  end
end

function Toast.reset()
  known, baseGuid = {}, nil
  watchState, savedGuid = nil, nil
  dirty, rerun, silent = false, false, false
  wasOn = Toast.enabled()
  Toast.queue = {}
  if current then Toast.finish(token) end
end

Toast.gate = gate

function Toast.slash(cmd, rest)
  local print_ = ns.Core and ns.Core.print or function() end
  rest = type(rest) == "string" and string.lower(rest) or ""
  if cmd == "toast" or cmd == "zettel" then
    local res
    local function test()
      local Chronik = Journal.Chronik
      if Chronik then
        local m = Toast.medalItem(Chronik.SEAL_BY_ID.quests.index, Chronik.SEAL_BY_ID.quests, "silver")
        m.key = "test:medal"
        m.immediate, m.maxAge = true, 120
        res[#res + 1] = Toast.enqueue(m)
      end
      local z = Toast.zoneItem(0, Toast.TEXT.testZone)
      z.key = "test:zone"
      z.immediate, z.maxAge = true, 120
      res[#res + 1] = Toast.enqueue(z)
    end
    if rest == "test" then
      if not Toast.enabled() then
        print_(Toast.TEXT.testOff)
        return true
      end
      res = {}
      test()
      local why = Toast.waitReason()
      if #res == 0 or not (res[1] or res[2]) then
        print_((not Toast.kindOn("medal") and not Toast.kindOn("zone")) and Toast.TEXT.testKindOff or Toast.TEXT.testBusy)
      elseif why == "combat" then print_(Toast.TEXT.testWaitCombat)
      else print_(Toast.TEXT.testQueued) end
      return true
    elseif rest ~= "" and ns.Core.onOff(rest) == nil then
      print_(Toast.TEXT.usage)
      return true
    end
    local on = ns.Core.onOff(rest)
    if on == nil then on = not Toast.enabled() end
    Toast.setEnabled(on)
    if not on then Toast.queue = {} end
    print_(on and Toast.TEXT.on or Toast.TEXT.off)
    return true
  elseif cmd == "ton" then
    if rest ~= "" and ns.Core.onOff(rest) == nil then
      print_(Toast.TEXT.usageSound)
      return true
    end
    local on = ns.Core.onOff(rest)
    if on == nil then on = not Toast.soundOn() end
    Toast.setSound(on)
    print_(on and Toast.TEXT.soundOn or Toast.TEXT.soundOff)
    if on then
      local z = Toast.playSound("zone")
      local function report(m)
        print_(string.format(Toast.TEXT.soundIds, z and tostring(z) or Toast.TEXT.soundNone, m and tostring(m) or Toast.TEXT.soundNone))
      end
      if type(C_Timer) == "table" then
        C_Timer.After(1.2, function() report(Toast.playSound("medal")) end)
      else
        report(Toast.playSound("medal"))
      end
    end
    return true
  end
  return false
end

install()
if Journal.Index and Journal.Index.onReady then Journal.Index.onReady(function(index) Toast.safe(onReady, index) end) end
if ns.Core and ns.Core.on then
  ns.Core.on("PLAYER_LOGIN", function() Toast.reset() end)
  ns.Core.on("ZONE_CHANGED_NEW_AREA", function() zoneChangeAt = now() end)
  ns.Core.on("PLAYER_REGEN_DISABLED", function()
    if current then
      local item = current
      Toast.finish(token)
      if Toast.enabled() or item.always then table.insert(Toast.queue, 1, item) end
    end
  end)
  ns.Core.on("PLAYER_REGEN_ENABLED", function()
    if dirty then schedule() end
    if #Toast.queue > 0 then Toast.pump() end
  end)
end
