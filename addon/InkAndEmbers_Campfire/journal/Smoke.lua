-- Smoke signal: coming within range of a campfire (buff "Campfire Nearby", WoW Forever only) a thread of smoke drifts in from the
-- left, spreads to the right and uncovers the words "Campfire nearby" letter by letter. The smoke then stands over the whole line,
-- flowing within itself, with the words calm and readable; at the end smoke, stream and words fade out together while a small
-- campfire with moving flames and a plume rising from their tip fades in under the line (a true cross-fade, no gap). The campfire
-- stays in the same place for as long as the buff lasts.
-- Trigger: own throttled UNIT_AURA watcher (Campfire.check catches up after combat, which is not wanted here). The buff turning on
-- shows the words unless the player is in combat, sitting, on a taxi, just loaded in, or left a fire on this map within Smoke.LOCK
-- seconds. Unknown values (secret or unreadable) change nothing and trigger nothing. Where only the words are blocked, the plume
-- still shows, as long as the player is not in combat, on a taxi or sitting.
-- Drawing: each strand is a row of cross-fading sprites (Media/SmokeThread.tga: soft window along the strand, dark core and light
-- hem across it, 50 % overlap add up to an even line). OnUpdate runs only while something is visible (30 Hz).
-- Stream: five more strands (Smoke.STREAM) blow in from the left behind the thread and the words, wider at the left edge.
-- Letters: the whole line is one piece of text laid out by the client (single glyphs land apart from each other, Morpheus has wide
-- overhangs). Each letter is a clipped window onto its own copy of that line, so it fades and moves on its own while the line reads exactly as set.
-- Flames: eight distorted phases (Media/CampfireFlames.tga) cross-fade on two textures over the static base (Media/CampfireBase.tga).
-- The reduceMotion setting leaves the words fading in, standing, and fading into the still picture without plume; OnUpdate only for the fades.
-- Position: edit mode element "smoke" via Smoke.hud.place.
-- Settings (EveNChronicleDB.campfire): smoke = false turns it off; the lock lives in memory only.
local _, ns = ...

local Journal = ns.Journal
if not Journal then return end

local sin, floor, max, min = math.sin, math.floor, math.max, math.min

local Smoke = {}
Journal.Smoke = Smoke

Smoke.W, Smoke.H = 660, 208
Smoke.LINE_Y = 92                         -- middle of the text line, from the top edge
Smoke.FONT = "Fonts\\MORPHEUS.TTF"
Smoke.FONT_SIZE = 40
Smoke.TEXT_COLOR = { 0.973, 0.929, 0.851 } -- warm parchment white
Smoke.SHADOW = { color = { 0.04, 0.02, 0.01, 0.95 }, x = 2, y = -2 }
-- Top centre, above Blizzard's ZoneTextFrame (top edge about 640 UI units above the bottom, read from the frame where possible).
-- Smoke.defaultY moves down by up to DEFAULT_DROP where there is room; on the smallest UI (768 units high) the zone name begins 128
-- below the top, the text line ends above that, the long plume and the fire below it reach into that area (no room to avoid it there).
Smoke.ZONE_TOP = 640
Smoke.DEFAULT_DROP = 30

Smoke.LOCK = 300                          -- no words again on a map this many seconds after leaving a fire there
Smoke.LOCK_MAX = 16                       -- maps remembered at most
Smoke.LOAD_GRACE = 5                      -- after a loading screen the buff may arrive late: that is still the starting state
Smoke.COMBAT_GRACE = 1                    -- the first look after combat never counts as arriving
Smoke.AURA_THROTTLE = 1.0                 -- like Campfire.lua
Smoke.CHECK_EVERY = 0.5                   -- taxi and edit mode have no reliable event, look while visible

Smoke.STEP = 1 / 30                       -- OnUpdate rate while anything is visible
-- Timeline in seconds: the head of the smoke arrives at the right end, the smoke stands (about 4.7 s), then smoke and words fade out
-- while the campfire fades in (CROSS seconds), then the campfire alone stays.
Smoke.HEAD_START, Smoke.SWEEP = 0.3, 3.4
Smoke.CROSS_AT, Smoke.CROSS = 8.4, 2.0
Smoke.TEXT_END = Smoke.CROSS_AT + Smoke.CROSS
Smoke.GLOW_FADE, Smoke.SOFT_END = 1.4, 1.6   -- fade-in of the campfire where no words came before; soft end
Smoke.EDGE = 70                           -- soft ends of the thread in px
Smoke.LETTER_IN = 55
Smoke.WOBBLE = 1.2                        -- a slow wave along the line: neighbours stay nearly level, the windows do not shear a glyph
Smoke.WOBBLE_PHASE = 0.3
Smoke.SLOT_H = 90                         -- height of a letter window
Smoke.SLOT_MARGIN = 16                    -- first and last window reach this far past the line (overhangs)
Smoke.REDUCED = { fadeIn = 0.8, crossAt = 3.8, cross = 1.2 }
Smoke.PREVIEW_GLOW = 8                    -- seconds of plume in the /chronik preview
Smoke.PREVIEW_T = 5                       -- moment shown in the edit mode preview (thread lies in the line)

-- Sprites: SPACING px apart, twice as wide (raised cosine); height = 2 x SPAN x radius x width factor (the texture spans SPAN radii each way).
-- a, f, sp, ph = wave; r = radius; o = opacity at the core; yo = offset below the text line. GAP_MIN: the thinnest a torn place gets.
Smoke.SPAN = 2.4
Smoke.GAP_MIN = 0.45
Smoke.SPACING = 16
Smoke.COUNT = 42
Smoke.STRANDS = {
  { a = 13, f = 0.016, sp = 1.0, ph = 0, r = 7.5, o = 0.68, yo = 10 },
  { a = 18, f = 0.022, sp = 1.35, ph = 1.9, r = 5, o = 0.62, yo = 7 },
  { a = 9, f = 0.031, sp = 1.7, ph = 3.7, r = 3.4, o = 0.62, yo = 13 },
}
-- Stream: smoke that seems to blow in from the left. Several thin strands start far left of the frame (x0; the opacity rises
-- from nothing over edgeIn px), the band is about 2 x as wide as the thread there and tapers over `taper` px (from x0 + 80) into the
-- thin thread, which it joins before the words begin (about 120 px from the left). Many small, weak sprites rather than a few large
-- ones: no single sprite shows as a blotch. The stream lies behind the thread and the words. It fills from the left over inDur seconds
-- from inT0 (its front is soft, front), stays while the words stand and runs out from the left with the tail of the words.
-- Left of the frame nothing is clipped; on a 4:3 screen the faintest first part may reach past the screen edge. d = distance from
-- the middle of the stream (centre = offset below the text line).
Smoke.STREAM = {
  count = 26, spacing = 18, x0 = -260, taper = 420, grow = 1.2, spread = 1.0, centre = 10, edgeIn = 160,
  fadeFrom = 20, fadeTo = 190, ramp = 0.6, inT0 = 0.1, inDur = 2.2, front = 90,
  { a = 8, f = 0.012, sp = 1.1, ph = 0.6, r = 2.8, o = 0.5, d = -12 },
  { a = 11, f = 0.016, sp = 1.4, ph = 2.1, r = 3.2, o = 0.5, d = -6 },
  { a = 6, f = 0.021, sp = 1.0, ph = 4.0, r = 3.6, o = 0.55, d = 0 },
  { a = 11, f = 0.014, sp = 1.6, ph = 5.2, r = 3.2, o = 0.5, d = 6 },
  { a = 8, f = 0.019, sp = 1.25, ph = 1.2, r = 2.8, o = 0.5, d = 12 },
}
-- The fire in the steady phase, y = top edge from the top of the frame. The flame tip sits about 2 px below that edge in the picture.
-- The plume stands inside the frame: its top is about 20 px below the top edge, the fire under it.
Smoke.FIRE = { w = 72, h = 72, y = 126, cols = 4, rows = 2, frameTime = 0.45,
  glow = { size = 90, y = 30, color = { 1, 0.55, 0.2 }, min = 0.24, max = 0.38, speed = 1.3 } }
-- Plume: smoke the way a campfire makes it. h = height above the base (px), u = h / height (0 at the flame, 1 at the top).
-- Narrow, nearly straight and dense right above the flame; from `calm` upwards it starts to meander, the deflections grow with
-- height (env). The deflections are waves that travel UP (sin(k h - k v t + ph)): several waves of unrelated wavelengths and speeds
-- (no visible period) plus a slow random wander, per strand a phase and scale of its own, so the three strands run together at
-- the foot, wind round each other and part again. Gaps and thickenings travel up as well; the higher, the more the smoke tears into
-- faint pieces (tear). The whole column drifts to the left with height (drift * u^driftPow) and keeps rising: no arc.
-- base = y of the foot in the frame (behind the flame tip), step = px between two sprite rows (the sprites overlap by half, length
-- follows the slope so the strand stays closed), rows * strands = 72 sprites. r0/r1 = radius at the foot / at the top (a cone).
Smoke.PLUME = {
  base = 134, rows = 24, step = 5.2, height = 114.4, calm = 0.1, r0 = 1.8, r1 = 7, o = 0.9,
  drift = 76, driftPow = 1.8, wander = { 5, 4, 3 },
  waves = { { lam = 70, v = 14, a = 10 }, { lam = 41, v = 17, a = 3.5 }, { lam = 107, v = 12, a = 8 }, { lam = 190, v = 10, a = 6 } },
  { ph = 0, ks = 1, vs = 1, amp = 1, r = 1, o = 1 },
  { ph = 2.1, ks = 1.25, vs = 0.9, amp = 0.9, r = 0.9, o = 0.9 },
  { ph = 4.3, ks = 0.8, vs = 1.12, amp = 1.1, r = 0.95, o = 0.9 },
}
Smoke.DEFAULTS = { enabled = true }

Smoke.TEXT = ns.Locale.ns("Smoke", {
  label = "Lagerfeuer in der Nähe",
  previewOn = "Lagerfeuer: Vorschau der Rauchzeichen.",
  previewCombat = "Lagerfeuer: Im Kampf gibt es keine Vorschau.",
  previewEdit = "Lagerfeuer: Der Bearbeitungsmodus zeigt die Rauchzeichen schon.",
  previewFail = "Lagerfeuer: Die Rauchzeichen lassen sich gerade nicht anzeigen.",
})
local T = Smoke.TEXT

local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end
local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end
local function safe(fn, ...)
  if ns.Core and ns.Core.safe then return ns.Core.safe(fn, ...) end
  return pcall(fn, ...)
end
local function say(msg)
  if ns.Core and type(ns.Core.print) == "function" then ns.Core.print(msg) end
end
local function now() return type(GetTime) == "function" and GetTime() or 0 end
local function clamp(v, a, b) return max(a, min(b, v)) end
local function smooth(v)
  v = clamp(v, 0, 1)
  return v * v * (3 - 2 * v)
end

-- state: near = last known buff state (nil = not known yet), base = starting state taken, phase = nil | "text" | "glow",
-- locks = mapID -> GetTime of leaving, map = map where the buff was last seen
local st = { near = nil, base = false, phase = nil, preview = false, reduced = false, combat = false, quietUntil = 0, locks = {},
  map = nil, t0 = 0, endT = nil, acc = 0, lastCheck = 0, auraTimer = false, stage = nil, noStage = false, frame = nil, xfire = nil, noFade = false }
Smoke.state = st

-- WoW Forever only (MapSpace.retailClient: project id AND interface version). Without the check at hand: not Forever-specific, stay off.
function Smoke.active()
  local ms = Journal.MapSpace
  if not ms or type(ms.retailClient) ~= "function" then return false end
  local ok, retail = pcall(ms.retailClient)
  return ok and retail == false
end

local function cfTable(create)
  local db = EveNChronicleDB
  if type(db) ~= "table" or isSecret(db) then return nil end
  local c = db.campfire
  if type(c) ~= "table" or isSecret(c) then
    if not create then return nil end
    c = {}
    db.campfire = c
  end
  return c
end

function Smoke.settings()
  local c = cfTable(false) or {}
  local out = { enabled = Smoke.DEFAULTS.enabled }
  if c.smoke == true or c.smoke == false then out.enabled = c.smoke end
  return out
end

local function reduceMotion()
  local View = Journal.View
  if not View or type(View.peek) ~= "function" then return false end
  local ok, v = pcall(View.peek, "reduceMotion")
  return ok and v == true
end

-- Buff state: true / false / nil (unknown, secret or unreadable)
function Smoke.readNear()
  local C = ns.Campfire
  local id = C and C.NEARBY_SPELL
  local A = rawget(_G, "C_UnitAuras")
  if not id or type(A) ~= "table" or type(A.GetPlayerAuraBySpellID) ~= "function" then return nil end
  local ok, a = pcall(A.GetPlayerAuraBySpellID, id)
  if not ok or isSecret(a) then return nil end
  return a ~= nil
end

local function mapHere()
  if type(C_Map) ~= "table" or type(C_Map.GetBestMapForUnit) ~= "function" then return nil end
  local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
  return ok and num(id) or nil
end

local function inCombat()
  return st.combat or (type(InCombatLockdown) == "function" and InCombatLockdown() and true or false)
end

local function onTaxi()
  if type(UnitOnTaxi) ~= "function" then return false end
  local ok, v = pcall(UnitOnTaxi, "player")
  if not ok then return false end
  return isSecret(v) or v == true
end

local function sitting()
  local C = ns.Campfire
  if not C or type(C.session) ~= "function" then return false end
  local ok, s = pcall(C.session)
  return ok and s ~= nil
end

local function editing()
  local E = Journal.EditMode
  return E ~= nil and type(E.isEditing) == "function" and E.isEditing() == true
end

local function blocked() return inCombat() or onTaxi() or sitting() or editing() end

local function lockMap(id, t)
  if not id then return end
  st.locks[id] = t
  local n, oldest, oldestT = 0, nil, math.huge
  for k, v in pairs(st.locks) do
    if t - v >= Smoke.LOCK then
      st.locks[k] = nil
    else
      n = n + 1
      if v < oldestT then oldest, oldestT = k, v end
    end
  end
  if n > Smoke.LOCK_MAX and oldest then st.locks[oldest] = nil end
end

local function isLocked(id, t)
  local v = st.locks[id]
  return v ~= nil and t - v < Smoke.LOCK
end

function Smoke.defaultY()
  local h = UIParent and UIParent.GetHeight and num(UIParent:GetHeight()) or 768
  local top = Smoke.ZONE_TOP
  local z = rawget(_G, "ZoneTextFrame")
  if type(z) == "table" and type(z.GetTop) == "function" then
    local ok, v = pcall(z.GetTop, z)
    v = ok and num(v) or nil
    if v and v > 0 and v < h then top = v end
  end
  return -clamp(h - top - (Smoke.FIRE.y + Smoke.FIRE.h) - 4, 0, Smoke.DEFAULT_DROP)
end

-- Stage: sprites and letters on one frame, used by the live display and (a second one) by the edit mode preview

local function texPath()
  local Th = Journal.Theme
  return Th and Th.TEX and Th.TEX.smokeThread or "Interface\\AddOns\\InkAndEmbers\\Media\\SmokeThread"
end

local function sprite(f, sub)
  local t = f:CreateTexture(nil, "ARTWORK", nil, sub)
  -- filtered (mipmaps): the sprites are scaled all the time and must not look blocky
  t:SetTexture(texPath(), "CLAMP", "CLAMP", "TRILINEAR")
  -- moves by fractions of a pixel (positions are never rounded), otherwise the thread would jump
  if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
  if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
  t:Hide()
  return t
end

local function newStage(parent)
  local f = CreateFrame("Frame", nil, parent)
  if type(f.CreateTexture) ~= "function" or type(f.CreateFontString) ~= "function" then return nil end
  f:SetSize(Smoke.W, Smoke.H)
  f:EnableMouse(false) -- clicks pass through
  local s = { frame = f, strands = {}, plume = {}, letters = {} }
  for i = 1, #Smoke.STRANDS do
    local row = {}
    for n = 1, Smoke.COUNT do
      row[n] = sprite(f, i - 1)
    end
    s.strands[i] = row
  end
  -- the stream strands follow the thread strands in the same list (hidden together), on lower sublevels: behind the thread
  local SM = Smoke.STREAM
  for j = 1, #SM do
    local row = {}
    for n = 1, SM.count do
      row[n] = sprite(f, j - 1 - #SM)
    end
    s.strands[#Smoke.STRANDS + j] = row
  end
  local P = Smoke.PLUME
  for i = 1, #P do
    local row = {}
    for n = 1, P.rows do
      row[n] = sprite(f, i - 1) -- size and texture coordinates are set by drawPlume (turned along the path)
    end
    s.plume[i] = row
  end
  local Th = Journal.Theme
  local TEX = Th and Th.TEX or {}
  local MEDIA = "Interface\\AddOns\\InkAndEmbers\\Media\\"
  local F = Smoke.FIRE
  local function layer(sub, tex)
    local t = f:CreateTexture(nil, "ARTWORK", nil, sub)
    t:SetTexture(tex)
    t:SetSize(F.w, F.h)
    t:SetPoint("TOP", f, "TOPLEFT", Smoke.W / 2, -F.y)
    t:Hide()
    return t
  end
  -- back to front: glow, plume (sublevels 0, 1), flames, base
  s.fireGlow = layer(-1, TEX.glow or (MEDIA .. "Glow"))
  s.fireGlow:SetBlendMode("ADD")
  s.fireGlow:SetSize(F.glow.size, F.glow.size)
  s.fireGlow:SetPoint("CENTER", f, "TOPLEFT", Smoke.W / 2, -(F.y + F.glow.y))
  s.flameA = layer(3, TEX.campfireFlames or (MEDIA .. "CampfireFlames"))
  s.flameB = layer(4, TEX.campfireFlames or (MEDIA .. "CampfireFlames"))
  s.fireBase = layer(5, TEX.campfireBase or (MEDIA .. "CampfireBase"))
  s.probe = f:CreateFontString(nil, "OVERLAY")
  s.probe:Hide()
  f:Hide()
  return s
end

local function setFont(fs)
  pcall(fs.SetFont, fs, Smoke.FONT, Smoke.FONT_SIZE, "")
end

local function newLetter(s)
  local slot = CreateFrame("Frame", nil, s.frame)
  slot:EnableMouse(false)
  slot:SetClipsChildren(true)
  -- the text on an inner frame: what the window clips is its child
  local inner = CreateFrame("Frame", nil, slot)
  inner:SetAllPoints(slot)
  inner:EnableMouse(false)
  local fs = inner:CreateFontString(nil, "OVERLAY")
  setFont(fs)
  fs:SetTextColor(Smoke.TEXT_COLOR[1], Smoke.TEXT_COLOR[2], Smoke.TEXT_COLOR[3])
  local c = Smoke.SHADOW.color
  fs:SetShadowColor(c[1], c[2], c[3], c[4])
  fs:SetShadowOffset(Smoke.SHADOW.x, Smoke.SHADOW.y)
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  slot:Hide()
  return { frame = slot, inner = inner, fs = fs }
end

-- Windows cut by UTF-8 sequence, their edges from the width of the growing prefix (the client's own spacing). Measured on each start:
-- the size of the font is only sure once it has been used. Nothing measurable or no clipping: one window with the whole line.
local function layoutLetters(s)
  local text = T.label
  setFont(s.probe)
  s.probe:SetText(text)
  local total = num(s.probe:GetStringWidth()) or 0
  local chars = {}
  for ch in string.gmatch(text, "[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
  local edges = { 0 }
  if total > 0 and type(s.frame.SetClipsChildren) == "function" then
    local prefix = ""
    for i, ch in ipairs(chars) do
      prefix = prefix .. ch
      s.probe:SetText(prefix)
      edges[i + 1] = max(edges[i], num(s.probe:GetStringWidth()) or 0)
    end
    total = max(total, edges[#edges])
  else
    edges[2] = max(total, Smoke.W - 2 * Smoke.SLOT_MARGIN)
  end
  local n = #edges - 1
  local x0 = (Smoke.W - edges[n + 1]) / 2
  for i = 1, n do
    local l = s.letters[i]
    if not l then
      l = newLetter(s)
      s.letters[i] = l
    end
    if l.text ~= text then
      l.text = text
      l.fs:SetText(text)
    end
    local left = i == 1 and -Smoke.SLOT_MARGIN or edges[i]
    local right = i == n and edges[i + 1] + Smoke.SLOT_MARGIN or edges[i + 1]
    l.x = x0 + left
    l.c = x0 + (edges[i] + edges[i + 1]) / 2
    l.empty = right - left < 0.5
    l.frame:SetSize(max(right - left, 1), Smoke.SLOT_H)
    l.fs:ClearAllPoints()
    l.fs:SetPoint("LEFT", l.inner, "LEFT", -left, 0)
    l.used = true
  end
  for i = n + 1, #s.letters do
    s.letters[i].used = false
    s.letters[i].frame:Hide()
  end
end

local function hideRows(rows)
  for _, row in ipairs(rows) do
    for _, t in ipairs(row) do t:Hide() end
  end
end

local function hideLetters(s)
  for _, l in ipairs(s.letters) do l.frame:Hide() end
end

local function drawLetter(s, l, x, y, a)
  if a <= 0.002 or l.empty or not l.used then
    l.frame:Hide()
    return
  end
  l.frame:SetPoint("LEFT", s.frame, "TOPLEFT", x, -y)
  l.frame:SetAlpha(a)
  l.frame:Show()
end

-- A sprite of length L and width w turned to the direction (dx, dy), centre unchanged: a square quad (so nothing is cut off) whose
-- texture coordinates are the corners seen from the strand (u along, v across). Outside 0..1 the clamped edge is transparent.
-- (written out without helper functions: this runs about 330 times per frame and must not allocate)
local function aim(spr, L, w, dx, dy)
  local S = math.sqrt(L * L + w * w)
  local h = S / 2
  spr:SetSize(S, S)
  -- u(qx, qy) = 0.5 + (qx dx + qy dy) / L, v(qx, qy) = 0.5 + (qy dx - qx dy) / w, for the corners (-h,-h) (-h,h) (h,-h) (h,h)
  local hx, hy = h * dx, h * dy
  spr:SetTexCoord(0.5 + (-hx - hy) / L, 0.5 + (-hx + hy) / w, 0.5 + (-hx + hy) / L, 0.5 + (hx + hy) / w,
    0.5 + (hx - hy) / L, 0.5 + (-hx - hy) / w, 0.5 + (hx + hy) / L, 0.5 + (hx - hy) / w)
end

-- Height (from the top of the frame) of a thread strand at x
local function strandY(S, x, t)
  return Smoke.LINE_Y + S.yo + sin(x * S.f - t * S.sp + S.ph) * S.a * (0.65 + 0.35 * sin(x * 0.007 + S.ph))
end

local function drawThread(s, t, head, k)
  local W, E = Smoke.W, Smoke.EDGE
  local mid = Smoke.LINE_Y
  for i, S in ipairs(Smoke.STRANDS) do
    local row = s.strands[i]
    local a, f, sp, ph, r, o, yo = S.a, S.f, S.sp, S.ph, S.r, S.o, S.yo
    for n = 1, Smoke.COUNT do
      local x = (n - 1) * Smoke.SPACING - 8
      local ends = smooth((head - x) / E) * smooth(x / E) * smooth((W - x) / E)
      local gap = clamp((0.5 + 0.5 * sin(x * 0.021 - t * 0.8 + ph) + 0.28 * sin(x * 0.053 - t * 1.2 + 2 * ph)) * 1.45, Smoke.GAP_MIN, 1)
      local alpha = o * ends * gap * k
      local spr = row[n]
      if alpha < 0.003 then
        spr:Hide()
      else
        local y = strandY(S, x, t)
        local wf = 0.84 + 0.34 * sin(x * 0.012 - t * 0.9 + ph)
        -- turned along the strand (like the plume): the dark core runs on without steps where the strand is sloped
        local slope = (strandY(S, x + 1, t) - strandY(S, x - 1, t)) / 2
        local dl = math.sqrt(1 + slope * slope)
        aim(spr, 2 * Smoke.SPACING * dl, 2 * Smoke.SPAN * r * wf, 1 / dl, slope / dl)
        spr:SetPoint("CENTER", s.frame, "TOPLEFT", x, -y)
        spr:SetAlpha(alpha)
        spr:Show()
      end
    end
  end
end

-- Height of a stream strand at x, and how wide the stream is there (1 at the start, 0 from x0 + taper on)
local function streamY(SM, S, x, t)
  local wide = 1 - smooth((x - SM.x0 - 80) / (SM.taper - 80))
  return Smoke.LINE_Y + SM.centre + S.d * (1 + SM.spread * wide) + sin(x * S.f - t * S.sp + S.ph) * S.a * (0.65 + 0.35 * sin(x * 0.007 + S.ph)), wide
end

-- The stream: wider the further left, torn like the thread. Its front runs through the whole length of the stream (soft, `front` px).
local function drawStream(s, t, k)
  local SM = Smoke.STREAM
  local E = SM.front
  local xEnd = SM.x0 + (SM.count - 1) * SM.spacing
  local ramp = smooth(t / SM.ramp)
  local fill = smooth((t - SM.inT0) / SM.inDur)
  local head = SM.x0 - E + (xEnd - SM.x0 + 2 * E) * fill
  for j, S in ipairs(SM) do
    local row = s.strands[#Smoke.STRANDS + j]
    local ph = S.ph
    for n = 1, SM.count do
      local x = SM.x0 + (n - 1) * SM.spacing
      local alpha = S.o * ramp * smooth((x - SM.x0) / SM.edgeIn) * (1 - smooth((x - SM.fadeFrom) / (SM.fadeTo - SM.fadeFrom)))
        * smooth((head - x) / E) * k
      local gap = clamp((0.5 + 0.5 * sin(x * 0.021 - t * 0.8 + ph) + 0.28 * sin(x * 0.053 - t * 1.2 + 2 * ph)) * 1.45, Smoke.GAP_MIN, 1)
      alpha = alpha * gap
      local spr = row[n]
      if alpha < 0.003 then
        spr:Hide()
      else
        local y, wide = streamY(SM, S, x, t)
        local wf = 0.84 + 0.34 * sin(x * 0.012 - t * 0.9 + ph)
        local slope = (streamY(SM, S, x + 1, t) - streamY(SM, S, x - 1, t)) / 2
        local dl = math.sqrt(1 + slope * slope)
        aim(spr, 2 * SM.spacing * dl, 2 * Smoke.SPAN * S.r * (1 + SM.grow * wide) * wf, 1 / dl, slope / dl)
        spr:SetPoint("CENTER", s.frame, "TOPLEFT", x, -y)
        spr:SetAlpha(alpha)
        spr:Show()
      end
    end
  end
end

-- One moment of the words with the smoke. k = how much of it is still there (1, falling to 0 in the cross-fade)
local function drawText(s, t, k)
  k = k or 1
  local head = Smoke.W * smooth((t - Smoke.HEAD_START) / Smoke.SWEEP)
  drawThread(s, t, head, k)
  drawStream(s, t, k)
  for i, l in ipairs(s.letters) do
    local fadeIn = smooth((head - l.c) / Smoke.LETTER_IN)
    local wob = sin(t * 1.7 + i * Smoke.WOBBLE_PHASE) * Smoke.WOBBLE
    drawLetter(s, l, l.x, Smoke.LINE_Y + wob, fadeIn * k)
  end
end

local function drawReduced(s, t)
  local R = Smoke.REDUCED
  local a = smooth(t / R.fadeIn) * (1 - smooth((t - R.crossAt) / R.cross))
  for _, l in ipairs(s.letters) do drawLetter(s, l, l.x, Smoke.LINE_Y, a) end
end

local function flameCell(tex, i)
  if tex.cell == i then return end
  tex.cell = i
  local F = Smoke.FIRE
  local cw, ch = 1 / F.cols, 1 / F.rows
  local c, r = i % F.cols, floor(i / F.cols)
  tex:SetTexCoord(c * cw, (c + 1) * cw, r * ch, (r + 1) * ch)
end

-- The steady picture. Moving: phase i and the next one, both solid in the middle of the change, so the outline never pops.
-- still: the first phase alone and an even glow. w = weight of the whole picture (the cross-fade), 1 when it stands.
local function drawFire(s, t, still, w)
  w = w or 1
  local F = Smoke.FIRE
  local G = F.glow
  local glow = still and (G.min + G.max) / 2 or G.min + (G.max - G.min) * (0.5 + 0.5 * sin(t * G.speed))
  s.fireGlow:SetVertexColor(G.color[1], G.color[2], G.color[3], glow * w)
  s.fireGlow:Show()
  s.fireBase:SetAlpha(w)
  s.fireBase:Show()
  local n = F.cols * F.rows
  if still then
    flameCell(s.flameA, 0)
    s.flameA:SetAlpha(w)
    s.flameA:Show()
    s.flameB:Hide()
    return
  end
  local pos = t / F.frameTime
  local whole = floor(pos)
  local part = pos - whole
  flameCell(s.flameA, whole % n)
  flameCell(s.flameB, (whole + 1) % n)
  s.flameA:SetAlpha(min(1, 2 * (1 - part)) * w)
  s.flameB:SetAlpha(min(1, 2 * part) * w)
  s.flameA:Show()
  s.flameB:Show()
end

local function hideFire(s)
  s.fireGlow:Hide()
  s.flameA:Hide()
  s.flameB:Hide()
  s.fireBase:Hide()
end

-- Sideways position of strand S at height h and time t (the waves run up with time)
local function plumeX(P, S, h, t)
  local u = clamp(h / P.height, 0, 1)
  local env = (max(0, u - P.calm) / (1 - P.calm)) ^ 1.35
  local off = 0
  for j, W in ipairs(P.waves) do
    local k = 2 * math.pi / W.lam * S.ks
    off = off + W.a * sin(k * h - k * W.v * S.vs * t + S.ph + j * 1.3)
  end
  local wander = P.wander[1] * sin(t * 0.11 + 0.7) + P.wander[2] * sin(t * 0.047 + 2.9) + P.wander[3] * sin(t * 0.19 + 5)
  return Smoke.W / 2 - P.drift * u ^ P.driftPow + off * S.amp * env + wander * u ^ 1.3
end

-- The plume alone, w = weight (cross-fade)
local function drawPlume(s, t, w)
  local P = Smoke.PLUME
  for i = 1, #P do
    local S = P[i]
    local row = s.plume[i]
    for n = 1, P.rows do
      local h = (n - 2) * P.step -- the first row lies below the foot, behind the flame
      local u = clamp(h / P.height, 0, 1)
      local x = plumeX(P, S, h, t)
      local slope = (plumeX(P, S, h + 1, t) - plumeX(P, S, h - 1, t)) / 2 -- sideways px per px of height
      local dl = math.sqrt(slope * slope + 1)
      -- cone, with thickenings that travel up
      local r = (P.r0 + (P.r1 - P.r0) * u ^ 0.9) * S.r * (1 + 0.3 * sin(h * 0.06 - t * 1.0 + S.ph))
      -- torn more and more with height; none right at the flame
      local tear = clamp((u - 0.15) / 0.7, 0, 1) ^ 1.2
      local raw = clamp((0.5 + 0.5 * sin(h * 0.075 - t * 1.3 + S.ph) + 0.28 * sin(h * 0.17 - t * 2.2 + 2 * S.ph)) * 1.45, 0, 1)
      local dens = (1 - u) ^ 0.95 * (0.8 + 0.2 * sin(h * 0.045 - t * 0.9 + 1.7 + S.ph))
      local alpha = P.o * S.o * (1 - tear * (1 - raw)) * dens * w
      local spr = row[n]
      if alpha < 0.003 then
        spr:Hide()
      else
        aim(spr, 2 * P.step * dl, 2 * Smoke.SPAN * r, slope / dl, -1 / dl)
        spr:SetPoint("CENTER", s.frame, "TOPLEFT", x, -(P.base - h))
        spr:SetAlpha(alpha)
        spr:Show()
      end
    end
  end
end

local function drawGlow(s, t, w)
  w = w or 1
  drawPlume(s, t, w)
  drawFire(s, t, false, w)
end

function Smoke.place()
  local f = st.frame
  if not f then return false end
  local hud = Smoke.hud
  if hud and type(hud.place) == "function" then
    local ok, done = pcall(hud.place, f)
    if ok and done then return true end
  end
  if f:GetParent() ~= UIParent then f:SetParent(UIParent) end
  f:SetFrameStrata("MEDIUM")
  f:ClearAllPoints()
  f:SetPoint("TOP", UIParent, "TOP", 0, Smoke.defaultY())
  return true
end

local function liveStage()
  if st.stage then return st.stage end
  if st.noStage then return nil end
  local ok, s = pcall(newStage, UIParent)
  if not ok or not s then
    st.noStage = true
    return nil
  end
  st.stage, st.frame = s, s.frame
  s.frame:SetFrameStrata("MEDIUM")
  return s
end

local onUpdate

local function run(s)
  st.acc, st.endT, st.lastCheck = 0, nil, now()
  s.frame:SetAlpha(1)
  Smoke.place()
  s.frame:Show()
  s.frame:SetScript("OnUpdate", onUpdate)
end

-- Nothing visible any more: no OnUpdate, no sprites
local function finish()
  local s = st.stage
  st.phase, st.preview, st.endT, st.reduced, st.xfire, st.noFade = nil, false, nil, false, nil, false
  if not s then return end
  s.frame:SetScript("OnUpdate", nil)
  s.frame:Hide()
  hideRows(s.strands)
  hideRows(s.plume)
  hideLetters(s)
  hideFire(s)
end

local function startText(preview)
  local s = liveStage()
  if not s then return false end
  hideRows(s.plume)
  hideFire(s)
  layoutLetters(s)
  st.phase, st.preview, st.t0, st.xfire, st.noFade = "text", preview == true, now(), nil, false
  st.reduced = reduceMotion()
  if st.reduced then
    hideRows(s.strands)
    drawReduced(s, 0)
  else
    drawText(s, 0)
  end
  run(s)
  return true
end

-- fromText: the campfire was already shown at full strength by the cross-fade, so it does not fade in again
local function startGlow(fromText)
  local s = liveStage()
  if not s then return false end
  hideRows(s.strands)
  hideLetters(s)
  st.phase, st.t0, st.noFade = "glow", now(), fromText == true
  st.reduced = reduceMotion()
  if st.reduced then
    hideRows(s.plume) -- the still picture
    drawFire(s, st.t0, true)
  else
    drawGlow(s, st.t0)
  end
  run(s)
  s.frame:SetAlpha(st.noFade and 1 or 0)
  return true
end

local function softEnd()
  if st.endT then return end
  st.endT = now()
  if st.frame then st.frame:SetScript("OnUpdate", onUpdate) end -- the still picture has none while it just stands there
end

local function wantGlow()
  return st.near == true and Smoke.active() and Smoke.settings().enabled and not blocked()
end

-- Brings the display in line with the state: ends what may not show any more, starts the plume where it may. Never starts the words.
function Smoke.sync()
  if st.phase then
    if st.preview then
      if inCombat() then softEnd() end
    elseif st.phase == "text" then
      if blocked() or not Smoke.settings().enabled then softEnd() end
    elseif wantGlow() then
      st.endT = nil
      if st.reduced ~= reduceMotion() then
        finish()
        startGlow()
      end
    else
      softEnd()
    end
    return
  end
  if wantGlow() then startGlow() end
end

-- End of the cross-fade: the campfire stays where it may, otherwise the (already empty or fading) picture ends
local function afterText()
  if st.endT then return end -- already fading away
  if st.xfire then
    startGlow(true)
    if not (st.preview or wantGlow()) then softEnd() end
    return
  end
  finish()
  Smoke.sync()
end

-- Whether the campfire takes part in the cross-fade is decided once, when it begins
local function crossFire()
  if st.xfire == nil then st.xfire = (st.preview or wantGlow()) and true or false end
  return st.xfire
end

-- One visible update
function Smoke.step()
  local t = now()
  if t - st.lastCheck >= Smoke.CHECK_EVERY then
    st.lastCheck = t
    Smoke.sync()
    if not st.phase then return end
  end
  local s = st.stage
  local master = 1
  if st.endT then
    master = 1 - (t - st.endT) / Smoke.SOFT_END
    if master <= 0 then
      finish()
      Smoke.sync()
      return
    end
  end
  local run_t = t - st.t0
  if st.phase == "text" then
    s.frame:SetAlpha(master)
    if st.reduced then
      local R = Smoke.REDUCED
      if run_t >= R.crossAt + R.cross then
        afterText()
        return
      end
      drawReduced(s, run_t)
      if run_t >= R.crossAt and crossFire() then drawFire(s, t, true, smooth((run_t - R.crossAt) / R.cross)) end
    elseif run_t >= Smoke.TEXT_END then
      hideRows(s.strands)
      hideLetters(s)
      afterText()
    else
      local c = smooth((run_t - Smoke.CROSS_AT) / Smoke.CROSS) -- 0 while the smoke stands, then up to 1
      drawText(s, run_t, 1 - c)
      if run_t >= Smoke.CROSS_AT and crossFire() then drawGlow(s, t, c) end
    end
  else
    if st.preview and run_t >= Smoke.PREVIEW_GLOW then softEnd() end
    s.frame:SetAlpha(master * (st.noFade and 1 or smooth(run_t / Smoke.GLOW_FADE)))
    if not st.reduced then
      drawGlow(s, t)
    elseif not st.endT and not st.preview and run_t >= Smoke.GLOW_FADE then
      s.frame:SetAlpha(1)
      s.frame:SetScript("OnUpdate", nil) -- faded in: nothing moves any more
    end
  end
end

onUpdate = function(_, elapsed)
  st.acc = st.acc + (num(elapsed) or 0)
  if st.acc < Smoke.STEP then return end
  st.acc = 0
  safe(Smoke.step)
end

function Smoke.setEnabled(on)
  local c = cfTable(true)
  if not c then return false end
  c.smoke = on and true or false
  safe(Smoke.sync)
  local O = Journal.Options
  if O and type(O.refresh) == "function" then pcall(O.refresh) end
  return true
end

-- A look at the buff: only false -> true is an arrival; what is unknown stays as it was
function Smoke.evaluate()
  if not st.base or not Smoke.active() or inCombat() then return end
  local near = Smoke.readNear()
  local t = now()
  if near == true then
    local arrived = st.near == false
    local map = mapHere()
    st.near = true
    if map then st.map = map end
    if arrived and map and t >= st.quietUntil and not isLocked(map, t) and Smoke.settings().enabled and not blocked()
      and not st.preview then
      startText(false)
    end
  elseif near == false then
    -- flying past a fire is no leaving it: the words stay available for arriving there later
    if st.near == true and not onTaxi() then
      local map = mapHere()
      lockMap(map, t)
      if st.map ~= map then lockMap(st.map, t) end
    end
    st.near, st.map = false, nil
  end
  Smoke.sync()
end

-- Chat preview /chronik feuer rauch: runs in Retail as well and with the option off
function Smoke.preview()
  if inCombat() then
    say(T.previewCombat)
    return false
  end
  if editing() then
    say(T.previewEdit)
    return false
  end
  if not startText(true) then
    say(T.previewFail)
    return false
  end
  say(T.previewOn)
  return true
end

-- Edit mode preview: a still of the thread in the text line, without OnUpdate. While it shows, the live display stays off.
function Smoke.buildPreview(parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetAllPoints(parent)
  function p.refresh()
    if st.phase then finish() end
    if not p.stage then
      p.stage = newStage(p)
      if not p.stage then return end
      p.stage.frame:SetAllPoints(p)
      p.stage.frame:Show()
    end
    layoutLetters(p.stage)
    drawText(p.stage, Smoke.PREVIEW_T)
    drawPlume(p.stage, 0, 0.6) -- shows the room the steady picture takes (plume fainter)
    drawFire(p.stage, 0, true)
  end
  p:SetScript("OnHide", function() safe(Smoke.sync) end)
  p:Hide()
  return p
end

local function onAura()
  if not st.base or st.auraTimer or inCombat() then return end
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    st.auraTimer = true
    C_Timer.After(Smoke.AURA_THROTTLE, function()
      st.auraTimer = false
      safe(Smoke.evaluate)
    end)
  else
    safe(Smoke.evaluate)
  end
end

local function onEvent(_, event, unit)
  if event == "UNIT_AURA" then
    if unit == "player" then onAura() end
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- only the starting state: the buff being there already is no arrival
    st.base = true
    st.quietUntil = now() + Smoke.LOAD_GRACE
    st.near = Smoke.readNear()
    if st.near == true then st.map = mapHere() end
    safe(Smoke.sync)
  elseif event == "PLAYER_REGEN_DISABLED" then
    st.combat = true
    safe(Smoke.sync)
  elseif event == "PLAYER_REGEN_ENABLED" then
    st.combat = false
    st.quietUntil = max(st.quietUntil, now() + Smoke.COMBAT_GRACE)
    safe(Smoke.evaluate)
  else -- PLAYER_CONTROL_LOST / GAINED: taxi; right at the start UnitOnTaxi may not say so yet
    safe(Smoke.evaluate)
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
      C_Timer.After(Smoke.CHECK_EVERY * 2, function() safe(Smoke.evaluate) end)
    end
  end
end

if type(ns.onCampfire) == "function" then
  ns.onCampfire(function(what)
    if what == "start" or what == "end" then safe(Smoke.sync) end
  end)
end

-- In Retail nothing listens at all (the preview needs no events)
if Smoke.active() and type(CreateFrame) == "function" then
  local ev = CreateFrame("Frame")
  ev:SetScript("OnEvent", onEvent)
  if not (type(ev.RegisterUnitEvent) == "function" and pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", "player")) then
    ev:RegisterEvent("UNIT_AURA")
  end
  for _, name in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_CONTROL_LOST",
    "PLAYER_CONTROL_GAINED" }) do
    ev:RegisterEvent(name)
  end
end
