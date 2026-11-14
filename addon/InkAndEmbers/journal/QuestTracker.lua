-- Own quest tracker window (change "quest-tracker", E4 after the Claude Design template "Ausfahrbar klassisch", D1-D9, D11, D12;
-- WoW Forever only, option "questTracker", default off). A slide-out panel at the right screen edge: thin grip strip with a badge
-- (quests ready to turn in), hover opens it (option), it closes after a delay (option), the pin keeps it open, panel scale 0.8-1.4, the grip has its own size 0.7-1.6.
-- Inside: head (count, gear = inline settings, pin), focus card (title, level, zone, elite, compass + distance, objectives with
-- bars, quest giver, rewards, "? Abgeben: NPC"), to-do section (top or bottom), zone groups with quest rows. While the panel is in,
-- progress shows as a short hint next to the grip (D9).
--
-- Clicks (design decision 5 + D6): title left click = world map on the quest's place (QuestTrack.actions.showOnMap), right click
-- = context menu (MenuUtil.CreateContextMenu) with every action; fold a quest = click on its type symbol (left of the title,
-- turns into a chevron on hover) or Shift + left click on the title (both also in the menu). Target = set/clear the focus quest.
-- Zone head = fold the zone, to-do row = open the journal on the to-do page.
--
-- Combat (D11): the panel keeps its state (open stays open, closed stays closed), no rebuild; counts, distances and hints update in
-- place. Fold/focus/pin clicks wait for PLAYER_REGEN_ENABLED. There are no secure frames in this window (the item buttons live on
-- the own item bar, journal/QuestItemBar.lua, D10), so nothing here can block.
-- Security: every foreign text (quest titles, objectives, NPC/item names) arrives display-safe from QuestTrack (Sanitize.display)
-- and is only put into FontStrings / menu entries; the menu builds its own labels.
--
-- PUBLIC API: QTR.active() -> bool, QTR.request() (bundled redraw), QTR.render(), QTR.step(dt) (animation/hover tick; the driver
--   frame calls it), QTR.setOpen(bool), QTR.isOpen(), QTR.togglePin(), QTR.toggleSettings(), QTR.place(), QTR.openMenu(owner, rec),
--   QTR.status() -> table. Animations follow "Bewegung reduzieren" (View.peek("reduceMotion")).
local _, ns = ...

local Journal = ns.Journal
if not Journal then return end
local Theme = Journal.Theme

local QTR = {}
Journal.QuestTracker = QTR

local floor, max, min, abs, sin, cos, pi, sqrt = math.floor, math.max, math.min, math.abs, math.sin, math.cos, math.pi, math.sqrt
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

QTR.NAME = "EveNChronicleQuestTracker"
QTR.W = 290
QTR.PAD = { top = 40, right = 22, bottom = 30, left = 44 }
-- the open panel spans the full screen height and covers minimap and bars on purpose (a glance at the log);
-- INSET only limits the hover zone at the right edge, so the minimap/bar area does not open it by accident
QTR.INSET = { top = 210, bottom = 150 }
QTR.STRATA = "HIGH" -- above minimap/bars (MEDIUM/LOW), below dialogs, popups, map (DIALOG/FULLSCREEN) and tooltips
QTR.FADE = 36 -- width of the transparent run-out on the left, outside the text area (text starts at PAD.left = 44)
QTR.EDGE = 20
-- Grip: a thin, nearly transparent strip at the right screen edge (no texture). w = width at rest, wHover = a little wider on hover, h = minimum height
-- (the log-fill pill may make it taller); the pill (QTR.BADGE_*) sticks out a few px to the left of the strip.
QTR.HANDLE = { w = 12, wHover = 14, h = 84, out = 36 }
QTR.BADGE_WARN, QTR.BADGE_FONT = 0.9, 9 -- pill warns orange from 90 % of the log, red when full; digits as small as is still readable
QTR.CW = QTR.W - QTR.PAD.left - QTR.PAD.right -- content width (230)
QTR.TICK = 0.1
QTR.TOAST_W = 220
QTR.TOAST_H = 56 -- height of the toast with a one-line objective; grows with every further text line
QTR.SHINE_W = 44 -- width of the shine strip that runs over the progress toast
QTR.ANIM = { slide = 0.45, fade = 0.3, stagger = 0.06, stagIn = 0.4, toast = 3.6, toastIn = 0.38, flashOn = 0.15, flashOff = 0.4, shineAt = 0.22, shine = 0.55, barAt = 0.12, bar = 0.55, ping = 0.9, beckon = 2.6, bump = 0.45,
  pop = 0.45, qflash = 1.3, qpulse = 1.8, chev = 0.25, gear = 0.4, hold = 1.6, gripFade = 0.25 }
QTR.FONT = { head = "Fonts\\FRIZQT__.TTF", text = "Fonts\\ARIALN.TTF" }

local function rgb(hex, a)
  local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
  return { r / 255, g / 255, b / 255, a or 1 }
end
QTR.C = {
  gold = rgb("e8c77a"), goldLight = rgb("f1dfae"), title = rgb("f3d77a"), titleHover = rgb("ffe7a0"), turnin = rgb("ffe6a0"),
  text = rgb("ece6d8"), dim = rgb("d6ccb6"), muted = rgb("a89d86"), faint = rgb("bfb49c"), zone = rgb("d4b878"),
  done = rgb("8f887a"), check = rgb("8fdc7a"), elite = rgb("ffcf8a"), eliteEdge = rgb("a8752e"), xp = rgb("c9b8ff"),
  coin = rgb("f3d77a"), bg = rgb("06080c"), dark = rgb("14100a"), focusTitle = rgb("fbf3df"), sub = rgb("cfc4ad"),
  tgt = rgb("7d7462"), sym = rgb("bfa772"), symReady = rgb("7fbf6e"), warn = rgb("f09a3a"), full = rgb("d9483b"), fullText = rgb("fff4e6"), white = { 1, 1, 1, 1 }, info = rgb("c9bfa8"), toastDone = rgb("b6e8a0"),
}
-- item quality colours (Blizzard's standard values; no secret source)
QTR.QUALITY = { [0] = rgb("9d9d9d"), [1] = rgb("ffffff"), [2] = rgb("1eff00"), [3] = rgb("0070dd"), [4] = rgb("a335ee"),
  [5] = rgb("ff8000"), [6] = rgb("e6cc80"), [7] = rgb("00ccff"), [8] = rgb("00ccff") }

QTR.TEXT = ns.Locale.ns("QuestTracker", {
  title = "Questlog",
  handle = "QUESTS",
  count = "%d bereit · %d/%d",
  filtered = " · %d gefiltert",
  sSort = "Sortierung",
  sort = { zones = "Zone", distance = "Entfernung", level = "Stufe" },
  sFilter = "Filter",
  fDone = "Abgeschlossene ausblenden",
  fGroup = "Gruppenquests ausblenden",
  fZone = "Nur aktuelle Zone",
  sList = "Liste",
  lObjs = "Ziele anzeigen",
  lDist = "Entfernung anzeigen",
  lIcons = "Questtyp-Symbole",
  sFocus = "Fokus-Quest",
  fShow = "Fokus-Bereich anzeigen",
  fDist = "Kompass & Entfernung",
  fBar = "Fortschrittsbalken",
  fGiver = "Questgeber",
  fRew = "Belohnungen",
  sHints = "Hinweise",
  hNotify = "Hinweis bei Fortschritt (eingefahren)",
  focus = "Fokus",
  unfocus = "Fokus lösen",
  noFocus = "Keine Fokus-Quest – Zielscheibe neben einer Quest antippen.",
  level = "Stufe %d",
  elite = "ELITE",
  eliteTag = "Elite",
  groupTag = "Gruppe (%d)",
  groupTagPlain = "Gruppe",
  xp = "%s EP",
  gold = "%d G",
  silver = "%d S",
  copper = "%d K",
  turnin = "Abgeben: %s",
  turninPlain = "Abgeben",
  zoneNone = "Ohne Zone",
  groupTurnin = "Abgeben",
  groupDist = "Nach Entfernung",
  groupLevel = "Nach Stufe",
  empty = { tracked = "Keine verfolgten Quests.", log = "Das Questlog ist leer.", zone = "Keine Quests in dieser Zone." },
  emptyHint = "Die Auswahl stellst du in den Optionen um: AddOns -> Ink & Embers -> Quest-Tracker.",
  filteredAll = "Alle weiteren Quests sind ausgefiltert.",
  noZoneQuests = "Keine Quests in dieser Zone.",
  reading = "Das Questlog wird gelesen …",
  todo = "To Do",
  ready = "Bereit zur Abgabe",
  toastObj = "%s  %d/%d",
  progress = "Fortschritt",
  testTitle = "Testquest",
  testObj = "Testziel",
  testOff = "Quest-Tracker ist aus (oder nicht in WoW Forever). Erst \"/chronik quests an\".",
  testPinned = "Das Panel ist angeheftet und bleibt offen, deshalb gibt es keinen Hinweis am Griff. Erst lösen (Reißzwecke).",
  testNoFrames = "Der Tracker ist noch nicht aufgebaut. Gleich noch einmal versuchen.",
  combat = "Im Kampf bleibt der Tracker, wie er ist. Das holt er nach dem Kampf nach.",
  menu = { map = "Auf Karte zeigen", details = "Questlog-Details", share = "Teilen", watch = "Verfolgen", unwatch = "Nicht mehr verfolgen",
    focus = "Als Fokus setzen", unfocus = "Fokus lösen",
    hide = "Im Tracker ausblenden", abandon = "Quest abbrechen …", title = "Quest" },
  kind = { collect = "Sammeln", kill = "Besiegen", explore = "Erkunden", talk = "Gespräch" },
})
local T = QTR.TEXT

-- ---------------------------------------------------------------- state

local st = {
  frames = nil, open = false, p = 0, pinned = nil, hover = false, leaveAt = nil, settingsOpen = false, gearT = 1,
  sig = nil, laidOut = false, pending = false, queue = {}, renderQueued = false, installed = false, prog = nil, fx = {},
  toast = nil, ping = nil, openedAt = nil, tickAcc = 0, flatFolded = {}, rows = {}, blocks = {}, scroll = 0, contentH = 0,
  combat = false, view = nil, todos = {}, active = false, chevAngle = {},
}
QTR.state = st

local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end
local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end
local function now() return type(GetTime) == "function" and (num(GetTime()) or 0) or 0 end
local function inCombat()
  if type(InCombatLockdown) ~= "function" then return false end
  local ok, v = pcall(InCombatLockdown)
  return ok and not isSecret(v) and v == true
end
local function safe(fn, ...)
  if ns.Core and ns.Core.safe then return ns.Core.safe(fn, ...) end
  return pcall(fn, ...)
end
local function say(msg) if ns.Core and ns.Core.print then ns.Core.print(msg) end end

-- ---------------------------------------------------------------- pixel grid
-- Everything in the panel lands on whole physical pixels (requirement: text and icons absolutely sharp). One UI unit is
-- effectiveScale * physicalHeight / 768 pixels (the same factor as Blizzard's PixelUtil); the panel and the grip keep their own
-- SetScale (option), so every offset and size is rounded with the effective scale of the region it belongs to. Each region
-- remembers its wanted (unrounded) points and sizes; after a change of scale, UI scale or resolution QTR.resnap() rounds them
-- again (the native SetRoundLayoutToNearestPixel is protected, add-ons must not call it). Texts get whole pixel font heights
-- and a shadow of exactly one pixel (applyFont); textures snap to the pixel grid (crisp).
local SNAP = setmetatable({}, { __mode = "k" }) -- region -> { pts = { {point, rel, relPoint, x, y}, ... }, w, h, wpx, hpx }

local function pixelFactor()
  local f = rawget(_G, "GetPhysicalScreenSize")
  if type(f) == "function" then
    local ok, _, h = pcall(f)
    h = ok and num(h) or nil
    if h and h > 0 then return h / 768 end
  end
  return 1
end

-- physical pixels per UI unit of a region
local function ppu(r)
  local es = r and r.GetEffectiveScale and num(r:GetEffectiveScale()) or nil
  if not es or es <= 0 then es = 1 end
  if not st.pxf then st.pxf = pixelFactor() end
  return es * st.pxf
end
QTR.ppu = ppu

-- an offset rounded to whole pixels; a length to whole pixels, at least minPx (0 stays 0: "no fixed width")
local function snapOff(v, p) return floor((v or 0) * p + 0.5) / p end
local function snapLen(v, p, minPx)
  if type(v) ~= "number" or v <= 0 then return v end
  return max(minPx or 1, floor(v * p + 0.5)) / p
end
-- an even number of pixels (centred icons: the centre falls on a pixel edge)
local function snapEven(v, p) return max(2, floor(v * p / 2 + 0.5) * 2) / p end
QTR.snapOff, QTR.snapLen, QTR.snapEven = snapOff, snapLen, snapEven

local function spec(r)
  local s = SNAP[r]
  if not s then
    s = { pts = {} }
    SNAP[r] = s
  end
  return s
end

-- SetPoint on whole pixels (remembered for QTR.resnap)
local function pt(r, point, rel, relPoint, x, y)
  local s = spec(r)
  relPoint = relPoint or point
  s.pts[#s.pts + 1] = { point, rel, relPoint, x or 0, y or 0 }
  local p = ppu(r)
  r:SetPoint(point, rel, relPoint, snapOff(x or 0, p), snapOff(y or 0, p))
end

local function clear(r)
  r:ClearAllPoints()
  local s = SNAP[r]
  if s then s.pts = {} end
end

-- sizes on whole pixels (nil = leave that side alone); even = an even number of pixels (centred icons)
local function size(r, w, h, even)
  local s = spec(r)
  local p = ppu(r)
  s.even = even == true
  local f = s.even and snapEven or snapLen
  if w ~= nil then s.w, s.wpx = w, nil end
  if h ~= nil then s.h, s.hpx = h, nil end
  if w ~= nil and h ~= nil then r:SetSize(f(w, p), f(h, p))
  elseif w ~= nil then r:SetWidth(f(w, p))
  elseif h ~= nil then r:SetHeight(f(h, p)) end
end
local function width(r, w) size(r, w, nil) end
local function height(r, h) size(r, nil, h) end

-- a hairline: exactly n physical pixels wide / high (separators, box edges)
local function hair(r, wPx, hPx)
  local s = spec(r)
  local p = ppu(r)
  if wPx then s.wpx, s.w = wPx, nil r:SetWidth(wPx / p) end
  if hPx then s.hpx, s.h = hPx, nil r:SetHeight(hPx / p) end
end

-- textures snap to the pixel grid (moving/rotating ones switch it off, like Blizzard does for status bars)
local function crisp(t, on)
  if not t then return t end
  if on == false then
    if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
    if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
  elseif t.SetSnapToPixelGrid then
    t:SetSnapToPixelGrid(true)
  end
  return t
end
QTR.crisp = crisp

local function tex(parent, name, layer, tmpl, sub)
  return crisp(parent:CreateTexture(name, layer, tmpl, sub))
end

-- round everything again (scale, UI scale or resolution changed); fonts follow (applyFonts) and the layout is redone
function QTR.resnap()
  st.pxf = nil
  for r, s in pairs(SNAP) do
    local p = ppu(r)
    if #s.pts > 0 then
      r:ClearAllPoints()
      for _, a in ipairs(s.pts) do r:SetPoint(a[1], a[2], a[3], snapOff(a[4], p), snapOff(a[5], p)) end
    end
    local f = s.even and snapEven or snapLen
    if s.w ~= nil then r:SetWidth(f(s.w, p)) end
    if s.h ~= nil then r:SetHeight(f(s.h, p)) end
    if s.wpx then r:SetWidth(s.wpx / p) end
    if s.hpx then r:SetHeight(s.hpx / p) end
  end
  if QTR.applyFonts then QTR.applyFonts() end
  st.sig = nil
end
QTR.pt, QTR.clear, QTR.size, QTR.hair = pt, clear, size, hair

local function QT() return Journal.QuestTrack end
local function QTH() return Journal.QuestTrackerHide end
local function TT() return Journal.TodoTracker end
local function Bar() return Journal.QuestItemBar end

local function settings()
  local Q = QT()
  local ok, s = pcall(Q.settings)
  if ok and type(s) == "table" then return s end
  return Q.DEFAULTS
end

local function reduceMotion()
  local V = Journal.View
  if not V or type(V.peek) ~= "function" then return false end
  local ok, v = pcall(V.peek, "reduceMotion")
  return ok and v == true
end

-- the own tracker is on and applied (QuestTrackerHide active = foreign trackers hidden, mini note resting); never in Retail
function QTR.active()
  local Q, H = QT(), QTH()
  if not (Q and Q.enabled and Q.enabled() and H and type(H.active) == "function") then return false end
  return H.active() == true
end

-- upper case with the common Latin-1 letters (ä -> Ä ...); string.upper only knows ASCII
local function upper(s)
  s = string.upper(s or "")
  return (s:gsub("\195([\160-\190])", function(c)
    local b = c:byte()
    if b == 183 then return "\195" .. c end
    return "\195" .. string.char(b - 32)
  end))
end
QTR.upper = upper

local function ease(t) -- cubic-bezier(.2,.8,.2,1) is close to an ease-out quint
  t = max(0, min(1, t))
  return 1 - (1 - t) ^ 4
end

-- ---------------------------------------------------------------- small widgets

local function setColor(region, c, a)
  if not region then return end
  if region.qtText then
    region:SetTextColor(c[1], c[2], c[3], a or c[4] or 1)
  elseif region.SetVertexColor then
    region:SetVertexColor(c[1], c[2], c[3], a or c[4] or 1)
  end
end

-- ---- fonts: size factor and the two font choices (options panel.fontScale / fontHead / fontText). Every text made by font() is noted
-- (weak table) so a change of the options can re-apply file and size to all of them at once.
local FONT_REG = setmetatable({}, { __mode = "k" })
QTR.BUILTIN_FONTS = { { "Friz Quadrata TT", "Fonts\\FRIZQT__.TTF" }, { "Arial Narrow", "Fonts\\ARIALN.TTF" }, { "Morpheus", "Fonts\\MORPHEUS.TTF" },
  { "Skurri", "Fonts\\SKURRI.TTF" } }

local function lsm()
  local LS = rawget(_G, "LibStub")
  if type(LS) ~= "table" and type(LS) ~= "function" then return nil end
  local ok, lib = pcall(LS, "LibSharedMedia-3.0", true)
  if ok and type(lib) == "table" and type(lib.Fetch) == "function" then return lib end
  return nil
end

-- file of a chosen font name, nil when it is not (or no longer) available
function QTR.fontFile(name)
  if type(name) ~= "string" or name == "" then return nil end
  local lib = lsm()
  if lib then
    local ok, path = pcall(lib.Fetch, lib, "font", name, true)
    if ok and type(path) == "string" and path ~= "" and not (issecretvalue and issecretvalue(path)) then return path end
  end
  for _, f in ipairs(QTR.BUILTIN_FONTS) do
    if f[1] == name then return f[2] end
  end
  return nil
end

-- names for the options dropdowns: the game's own fonts plus everything registered at LibSharedMedia (also by other add-ons)
function QTR.fontList()
  local seen, out = {}, {}
  local function add(n)
    if type(n) == "string" and n ~= "" and #n <= 80 and not seen[n] and QT().fontName(n) then seen[n] = true out[#out + 1] = n end
  end
  for _, f in ipairs(QTR.BUILTIN_FONTS) do add(f[1]) end
  local lib = lsm()
  if lib and type(lib.List) == "function" then
    local ok, list = pcall(lib.List, lib, "font")
    if ok and type(list) == "table" then
      for i = 1, min(#list, 600) do add(list[i]) end
    end
  end
  table.sort(out, function(a, b) return a:lower() < b:lower() end)
  return out
end

local function fontSettings()
  local p = settings().panel
  return p.fontScale or 1, p.fontHead or "", p.fontText or ""
end

-- the file for a role ("head" | "text"): the chosen font, else the default one (also when the chosen one is gone)
function QTR.rolePath(role)
  local _, h, t = fontSettings()
  local name = role == "head" and h or t
  return QTR.fontFile(name) or QTR.FONT[role] or QTR.FONT.text
end

-- font height on whole screen pixels (the client draws the glyphs at height * pixels per unit; a fractional height blurs them) and
-- a shadow of exactly one pixel down-right (1 UI unit would be 1.4-1.9 pixels and smear the edges); no OUTLINE (thickens small text)
QTR.SHADOW_A = 0.8
function QTR.fontHeight(fs, sz)
  local p = ppu(fs)
  local scale = fontSettings()
  return max(1, floor(max(6, sz * scale) * p + 0.5)) / p, p
end

local function applyFont(fs, role, sz)
  local h, p = QTR.fontHeight(fs, sz)
  local ok = pcall(fs.SetFont, fs, QTR.rolePath(role), h, "")
  if not ok then ok = pcall(fs.SetFont, fs, QTR.FONT[role] or QTR.FONT.text, h, "") end
  if not ok and fs.SetFontObject and GameFontNormalSmall then fs:SetFontObject(GameFontNormalSmall) end
  if fs.SetShadowOffset then fs:SetShadowOffset(1 / p, -1 / p) end
  if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, QTR.SHADOW_A) end
end

-- line height factor for the fixed rows (never below 1: a smaller font keeps the rows)
function QTR.lineK()
  return max(1, (fontSettings()))
end

-- boxed list layout (option "Entfernung anzeigen"): every quest sits in a faint box, the distance gets its own meta line
-- padInset = inner left offset of the compact list: gap between the gold focus line and the type symbol
-- (nothing may reach x < 0, the scroll frame clips there)
QTR.BOX = { padX = 6, padInset = 5, padTop = 5, padBot = 6, gap = 5, metaH = 14 }
-- ready-to-turn-in mark: alpha of the green frame (1 physical pixel) and of the green surface
QTR.READY = { edge = 0.5, fill = 0.07 }

-- re-apply file and size to every text; true when something was touched
function QTR.applyFonts()
  local n = 0
  for fs, d in pairs(FONT_REG) do
    applyFont(fs, d.role, d.size)
    local txt = fs.GetText and fs:GetText()
    if txt and fs.SetText then fs:SetText(txt) end -- the client measures again
    n = n + 1
  end
  return n > 0
end

local function font(parent, role, size, color, justify, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  fs.inkPlain, fs.qtText = true, true
  FONT_REG[fs] = { role = role, size = size }
  applyFont(fs, role, size)
  fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
  if justify then fs:SetJustifyH(justify) end
  if fs.SetJustifyV then fs:SetJustifyV("TOP") end
  fs:SetText("")
  return fs
end

local function solid(parent, c, layer, sub)
  local t = tex(parent, nil, layer or "ARTWORK", nil, sub)
  t:SetColorTexture(1, 1, 1, 1)
  setColor(t, c)
  return t
end

-- gradient (left -> right or bottom -> top); a plain tint where the client has no SetGradient with colours
local function gradient(t, orient, c1, c2)
  local CC = rawget(_G, "CreateColor")
  if type(CC) == "function" and t.SetGradient then
    local ok = pcall(t.SetGradient, t, orient, CC(c1[1], c1[2], c1[3], c1[4]), CC(c2[1], c2[2], c2[3], c2[4]))
    if ok then return end
  end
  t:SetColorTexture(c2[1], c2[2], c2[3], (c1[4] + c2[4]) / 2)
end

local function plate(parent, c, a, r, ring)
  if not (Theme and Theme.roundRect) then return nil end
  r = r or 8
  local p = Theme.roundRect(parent, { 1, 1, 1 }, 1, r, "BACKGROUND", ring and Theme.TEX and Theme.TEX.ring or nil)
  -- corners on whole pixels (the 3 x 3 pieces of Theme.roundRect hang on them), every piece snapped to the grid
  for i, t in ipairs(p.parts or {}) do
    crisp(t)
    local col, row = (i - 1) % 3 + 1, floor((i - 1) / 3) + 1
    if col ~= 2 then width(t, r) end
    if row ~= 2 then height(t, r) end
  end
  p.color(c, a)
  return p
end

-- Line icons after the SVG paths of the template (16 x 16 view box): every stroke is a thin white texture, rotated and tinted.
local function seg(g, x1, y1, x2, y2, thick, ext)
  local k, w = g.k, thick or g.w
  local t = g:CreateTexture(nil, "ARTWORK")
  t:SetColorTexture(1, 1, 1, 1)
  local dx, dy = (x2 - x1) * k, (y2 - y1) * k
  local len = sqrt(dx * dx + dy * dy)
  t:SetSize(len + (ext or w * 0.6), w)
  t.def = { mx = (x1 + x2) / 2, my = (y1 + y2) / 2, ang = atan2(-dy, dx) }
  t:SetPoint("CENTER", g, "TOPLEFT", t.def.mx * k, -t.def.my * k)
  if t.SetRotation then pcall(t.SetRotation, t, t.def.ang) end
  g.parts[#g.parts + 1] = t
end

local function arc(g, cx, cy, r, a0, a1, n)
  n = n or 10
  local px, py
  for i = 0, n do
    local a = a0 + (a1 - a0) * i / n
    local x, y = cx + r * cos(a), cy - r * sin(a)
    if px then seg(g, px, py, x, y) end
    px, py = x, y
  end
end

local function dot(g, cx, cy, r)
  local t = g:CreateTexture(nil, "ARTWORK")
  if Theme and Theme.TEX and Theme.TEX.disc then t:SetTexture(Theme.TEX.disc) else t:SetColorTexture(1, 1, 1, 1) end
  t:SetSize(r * 2 * g.k + 1, r * 2 * g.k + 1)
  t.def = { mx = cx, my = cy }
  t:SetPoint("CENTER", g, "TOPLEFT", cx * g.k, -cy * g.k)
  g.parts[#g.parts + 1] = t
end

local GLYPHS = {
  ring = function(g) arc(g, 8, 8, 7.2, 0, 2 * pi, 20) end,
  chevL = function(g) seg(g, 10, 3, 5, 8) seg(g, 5, 8, 10, 13) end,
  chevD = function(g) seg(g, 2.7, 5.3, 8, 10.7) seg(g, 8, 10.7, 13.3, 5.3) end,
  gear = function(g)
    arc(g, 8, 8, 2.4, 0, 2 * pi, 8)
    seg(g, 8, 1.5, 8, 3.5) seg(g, 8, 12.5, 8, 14.5) seg(g, 1.5, 8, 3.5, 8) seg(g, 12.5, 8, 14.5, 8)
    seg(g, 3.4, 3.4, 4.8, 4.8) seg(g, 11.2, 11.2, 12.6, 12.6) seg(g, 3.4, 12.6, 4.8, 11.2) seg(g, 11.2, 4.8, 12.6, 3.4)
  end,
  pin = function(g)
    seg(g, 6, 2, 10, 2) seg(g, 10, 2, 9.5, 7) seg(g, 9.5, 7, 12, 9.5) seg(g, 12, 9.5, 4, 9.5) seg(g, 4, 9.5, 6.5, 7)
    seg(g, 6.5, 7, 6, 2) seg(g, 8, 9.5, 8, 14.5)
  end,
  target = function(g) arc(g, 8, 8, 6, 0, 2 * pi, 14) dot(g, 8, 8, 2.2) end,
  close = function(g) seg(g, 4, 4, 12, 12) seg(g, 12, 4, 4, 12) end,
  check = function(g) seg(g, 2.7, 8.7, 6.7, 12) seg(g, 6.7, 12, 13.3, 4) end,
  collect = function(g)
    seg(g, 3.5, 6, 12.5, 6) seg(g, 12.5, 6, 11.5, 14) seg(g, 11.5, 14, 4.5, 14) seg(g, 4.5, 14, 3.5, 6)
    seg(g, 6, 6, 6, 4.5) seg(g, 10, 6, 10, 4.5) arc(g, 8, 4.5, 2, 0, pi, 5)
  end,
  kill = function(g)
    seg(g, 3, 3, 11, 11) seg(g, 13, 3, 5, 11) seg(g, 9.5, 12.5, 12.5, 9.5) seg(g, 6.5, 12.5, 3.5, 9.5)
    seg(g, 11.5, 11.5, 13.5, 13.5) seg(g, 4.5, 11.5, 2.5, 13.5)
  end,
  explore = function(g) arc(g, 7, 7, 4, 0, 2 * pi, 12) seg(g, 10, 10, 14, 14) end,
  talk = function(g)
    seg(g, 2, 3, 14, 3) seg(g, 14, 3, 14, 11) seg(g, 14, 11, 7.5, 11) seg(g, 7.5, 11, 4.5, 14) seg(g, 4.5, 14, 4.5, 11)
    seg(g, 4.5, 11, 2, 11) seg(g, 2, 11, 2, 3)
  end,
  turnin = function(g) seg(g, 2.5, 8, 13, 8) seg(g, 9, 4, 13, 8) seg(g, 9, 12, 13, 8) end,
  person = function(g) arc(g, 8, 5, 3, 0, 2 * pi, 10) arc(g, 8, 14.5, 5.5, 0.2, pi - 0.2, 8) end,
  dotSmall = function(g) dot(g, 8, 8, 2) end,
  -- direction arrow after the template path "M10 2 L15 16 L10 12.5 L5 16 Z" (long tip, notched base), filled with thin horizontal
  -- rows: tip (8,1), base corners (3.5,15) and (12.5,15), notch (8,11.7). Points up; the glyph rotation turns it.
  arrowhead = function(g)
    local n = max(8, min(16, floor(g.size)))
    local step = 13.4 / (n - 1)
    local thick = max(1, step * g.k * 1.35)
    for i = 1, n do
      local y = 1.3 + (i - 1) * step
      local outer = 4.5 * (y - 1) / 14
      if y <= 11.7 then
        seg(g, 8 - outer, y, 8 + outer, y, thick, 0.4)
      else
        local inner = 4.5 * (y - 11.7) / 3.3
        seg(g, 8 + inner, y, 8 + outer, y, thick, 0.4)
        seg(g, 8 - outer, y, 8 - inner, y, thick, 0.4)
      end
    end
  end,
  place = function(g) arc(g, 8, 6.5, 3.5, -0.5, pi + 0.5, 8) seg(g, 4.8, 8.2, 8, 14) seg(g, 11.2, 8.2, 8, 14) dot(g, 8, 6.5, 1.2) end,
}

local function glyph(parent, name, size, color, stroke)
  local g = CreateFrame("Frame", nil, parent)
  g:SetSize(size, size)
  g.k, g.w, g.parts, g.name, g.size = size / 16, max(1, (stroke or 1.7) * size / 16), {}, name, size
  local fn = GLYPHS[name] or GLYPHS.dotSmall
  fn(g)
  function g.color(c, a)
    for _, t in ipairs(g.parts) do setColor(t, c, a) end
  end
  g.color(color or QTR.C.gold)
  -- turn the whole symbol around its centre (radians, counter-clockwise): frames cannot rotate, so every stroke moves
  g.angle = 0
  function g.rotate(a)
    a = a or 0
    if a == g.angle then return end
    g.angle = a
    local ca, sa = cos(a), sin(a)
    for _, t in ipairs(g.parts) do
      local d = t.def
      if d then
        local dx, dy = d.mx - 8, -(d.my - 8)
        t:ClearAllPoints()
        t:SetPoint("CENTER", g, "CENTER", (dx * ca - dy * sa) * g.k, (dx * sa + dy * ca) * g.k)
        if d.ang and t.SetRotation then pcall(t.SetRotation, t, d.ang + a) end
      end
    end
  end
  if g.EnableMouse then g:EnableMouse(false) end
  return g
end
QTR.glyph = glyph

-- direction arrow: a filled arrowhead with a long tip and a notched base (see GLYPHS.arrowhead), built from rotated rows because no
-- texture file is used; turn(rad) rotates it counter-clockwise (0 = up = straight ahead), the tip points exactly along the bearing
-- ---- sharp icons: Blizzard atlases instead of the line icons above (playtest: the rotated thin strokes fray). Every name is used by
-- Blizzard's own Retail UI (Gethe/wow-ui-source, live) and is still checked at runtime with C_Texture.GetAtlasInfo; the first one
-- that exists wins, without any the line icon stays (fallback, no error). The art is desaturated and tinted with the panel colours,
-- keeps its aspect ratio inside the icon box and the box is an even number of pixels (centred = exactly on the pixel grid).
QTR.ICON_ATLAS = {
  check = { "common-icon-checkmark" },
  gear = { "questlog-icon-setting", "GM-icon-settings" },
  pin = { "Waypoint-MapPin-Untracked" },
  close = { "common-icon-redx" },
  chevL = { "common-dropdown-icon-back" },
  kill = { "UI-HUD-UnitFrame-Player-CombatIcon" },
  explore = { "common-search-magnifyingglass" },
  collect = { "ParagonReputation_Bag" },
  -- "talk" = speech bubble (the voice-chat speaker was the wrong picture); without a bubble atlas the line bubble stays
  talk = { "communities-icon-chat" },
  -- ready to turn in: a soft arrow to the right; first atlas that exists wins, else the line arrow (GLYPHS.turnin)
  turnin = { "common-dropdown-icon-next", "common-icon-forwardarrow", "NPE_ArrowRight" },
  target = { "common-dropdown-icon-radialtick-yellow" },
  person = { "QuestNormal" },
  place = { "Waypoint-MapPin-Untracked" },
  arrowhead = { "Navigation-Tracked-Arrow" }, -- points up unturned (SuperTrackedFrame turns it the same way)
  dotSmall = { "WhiteCircle-RaidBlips" },
}
-- head chevron: the two arrows of the settings list (open = down, folded = right), so both rest states are drawn unturned;
-- only the 0.25 s turn in between rotates the folded one
QTR.CHEV_ATLAS = { open = "Options_ListExpand_Right_Expanded", folded = "Options_ListExpand_Right" }
-- share of the icon box a glyph fills (the dot is small, the arrow fills its box)
QTR.ICON_FILL = { dotSmall = 0.4 }

local atlasCache = {}
local function atlasInfo(name)
  local c = atlasCache[name]
  if c ~= nil then return c or nil end
  local info
  local CT = rawget(_G, "C_Texture")
  if type(CT) == "table" and type(CT.GetAtlasInfo) == "function" then
    local ok, v = pcall(CT.GetAtlasInfo, name)
    if ok and type(v) == "table" then info = v end
  end
  atlasCache[name] = info or false
  return info
end
QTR.atlasInfo = atlasInfo

-- the atlas a symbol uses in this client (nil = line icon)
function QTR.pickAtlas(name)
  if name == "chevD" then
    if atlasInfo(QTR.CHEV_ATLAS.open) and atlasInfo(QTR.CHEV_ATLAS.folded) then return QTR.CHEV_ATLAS.open, atlasInfo(QTR.CHEV_ATLAS.open) end
    return nil
  end
  for _, n in ipairs(QTR.ICON_ATLAS[name] or {}) do
    local info = atlasInfo(n)
    if info then return n, info end
  end
  return nil
end

local function setAtlas(t, name)
  if t.qtAtlas == name then return true end
  local ok, res = pcall(t.SetAtlas, t, name, false)
  if ok and res ~= false then
    t.qtAtlas = name
    return true
  end
  return false
end

local function icon(parent, name, sz, color, stroke)
  local an, info = QTR.pickAtlas(name)
  if not (an and parent and type(CreateFrame) == "function") then return glyph(parent, name, sz, color, stroke) end
  local g = CreateFrame("Frame", nil, parent)
  local t = tex(g, nil, "ARTWORK")
  if not (t.SetAtlas and setAtlas(t, an)) then
    g:Hide()
    return glyph(parent, name, sz, color, stroke)
  end
  if t.SetDesaturated then t:SetDesaturated(true) end
  g.parts, g.name, g.size, g.tex, g.atlas, g.angle = { t }, name, sz, t, an, 0
  local fill = QTR.ICON_FILL[name] or 1
  local aw, ah = num(info.width) or 1, num(info.height) or 1
  if aw <= 0 then aw = 1 end
  if ah <= 0 then ah = 1 end
  local w, h = sz * fill, sz * fill
  if aw > ah then h = h * ah / aw elseif ah > aw then w = w * aw / ah end
  size(g, sz, sz, true)
  size(t, w, h, true)
  pt(t, "CENTER", g, "CENTER", 0, 0)
  function g.color(c, a) setColor(t, c, a) end
  g.color(color or QTR.C.gold)
  -- turn around the centre (radians, counter-clockwise, 0 = as drawn); unturned = snapped to the pixel grid
  local function turnTex(r)
    if t.SetRotation then pcall(t.SetRotation, t, r) end
    crisp(t, not g.free and abs(r) < 1e-4)
  end
  function g.rotate(a)
    a = a or 0
    if a == g.angle and g.turned then return end
    g.angle, g.turned = a, true
    if name == "chevD" then
      local C = QTR.CHEV_ATLAS
      if abs(a) < 1e-4 then
        setAtlas(t, C.open)
        turnTex(0)
      elseif abs(a - QTR.CHEV_FOLDED) < 1e-4 then
        setAtlas(t, C.folded)
        turnTex(0)
      else
        setAtlas(t, C.folded)
        turnTex(a - QTR.CHEV_FOLDED)
      end
    else
      turnTex(a)
    end
  end
  if g.EnableMouse then g:EnableMouse(false) end
  return g
end
QTR.icon = icon

-- direction arrow: Blizzard's navigation arrow (fallback: the filled arrowhead of rows); turn(rad) rotates it counter-clockwise
-- (0 = up = straight ahead). It turns all the time, so it is not snapped (smooth instead of jumping pixels).
local function arrowTex(parent, sz, color)
  local g = icon(parent, "arrowhead", sz, color or QTR.C.gold)
  if g.tex then
    g.free = true
    crisp(g.tex, false)
  end
  g.turn = function(rad) g.rotate(rad or 0) end
  return g
end

-- no hover tooltips in the panel (design requirement): hover only changes colours / glow

-- formatting -------------------------------------------------------------------------------------------------------------------------

local function dist(m)
  local TTr = TT()
  if TTr and TTr.formatDist then return TTr.formatDist(m) end
  return nil
end

local function thousands(n)
  local sep = ns.Locale.get("Fmt", "thousands") or "."
  local s = tostring(floor(n))
  local out = s:reverse():gsub("(%d%d%d)", "%1" .. sep:reverse()):reverse()
  if out:sub(1, #sep) == sep then out = out:sub(#sep + 1) end
  return out
end
QTR.thousands = thousands

local function money(c)
  c = floor(c)
  local g, s, k = floor(c / 10000), floor(c / 100) % 100, c % 100
  if g > 0 then
    if s > 0 then return T("gold", g) .. " " .. T("silver", s) end
    return T("gold", g)
  end
  if s > 0 then return T("silver", s) end
  return T("copper", k)
end
QTR.money = money

local function diffColor(rec)
  local c = type(rec.color) == "table" and rec.color or nil
  if c and num(c.r) and num(c.g) and num(c.b) then return { c.r, c.g, c.b, 1 } end
  return QTR.C.title
end

-- read-aloud button (third-party addon Spoken via journal/Spoken.lua, same textures and rules as the Quests page): small
-- play/stop icon right of a quest's type symbol / next to the focus title. Without a loaded Spoken it is hidden and reserves no
-- room; without a recording it is pale and does nothing. NO tooltip (panel rule). Event: open quest = accept text, ready to
-- turn in = complete text if recorded, else accept text.
QTR.SPEAK_W, QTR.SPEAK_ICON, QTR.SPEAK_HOT, QTR.SPEAK_DIM = 16, 12, 14, 0.33

local function speakOn()
  local S = Journal.Spoken
  return S ~= nil and S.available() == true
end

local function speakEvent(S, rec)
  if rec.complete and S.has(rec.questID, S.COMPLETE) then return S.COMPLETE end
  return S.ACCEPT
end

local function speakButton(parent, h)
  local b = CreateFrame("Button", nil, parent)
  size(b, QTR.SPEAK_W, h)
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp") end
  b.icon = tex(b, nil, "ARTWORK")
  size(b.icon, QTR.SPEAK_ICON, QTR.SPEAK_ICON, true)
  pt(b.icon, "CENTER", b, "CENTER", 0, 0)
  function b:Paint()
    local S = Journal.Spoken
    local rec = self.rec
    if not (rec and rec.questID and S and S.available()) then
      self:Hide()
      return
    end
    self.event = speakEvent(S, rec)
    self.has = S.has(rec.questID, self.event)
    self.playing = self.has and S.isPlaying(rec.questID, self.event) or false
    self.icon:SetTexture(self.playing and S.TEX_STOP or S.TEX_PLAY)
    if self.icon.SetDesaturated then self.icon:SetDesaturated(not self.has) end
    self:SetAlpha(self.has and 1 or QTR.SPEAK_DIM)
    local sz = (self.hover and self.has) and QTR.SPEAK_HOT or QTR.SPEAK_ICON
    size(self.icon, sz, sz, true)
    self:Show()
  end
  -- bind a quest record (nil = no button)
  function b:Bind(rec)
    self.rec = rec
    self:Paint()
  end
  b:SetScript("OnClick", function(self)
    safe(function()
      self:Paint() -- ask again: the voice packs may have loaded since the last paint (the answer is cached, so this is cheap)
      if not (self.rec and self.has) then return end -- without a recording the button does nothing
      local S = Journal.Spoken
      if S then S.toggle(self.rec.questID, self.event, self.rec.title, function() self:Paint() end, self.rec.starter) end
      self:Paint()
    end)
  end)
  b:SetScript("OnEnter", function(self)
    self.hover = true
    safe(self.Paint, self)
  end)
  b:SetScript("OnLeave", function(self)
    self.hover = false
    safe(self.Paint, self)
  end)
  b:SetScript("OnHide", function(self) self.hover = false end)
  return b
end

-- ---------------------------------------------------------------- frames

local function makeButton(parent, w, h)
  local b = CreateFrame("Button", nil, parent)
  size(b, w, h)
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  return b
end

local function iconButton(parent, name, size)
  local b = makeButton(parent, 22, 22)
  b.bg = plate(b, QTR.C.gold, 0, 5)
  b.glyph = icon(b, name, size or 12, QTR.C.sub)
  pt(b.glyph, "CENTER", b, "CENTER", 0, 0)
  b:SetScript("OnEnter", function(self)
    if not self.on then self.glyph.color(QTR.C.white) if self.bg then self.bg.color(QTR.C.gold, 0.12) end end
  end)
  b:SetScript("OnLeave", function(self)
    if not self.on then self.glyph.color(QTR.C.sub) if self.bg then self.bg.color(QTR.C.gold, 0) end end
  end)
  function b.setOn(on)
    b.on = on
    if b.bg then b.bg.color(QTR.C.gold, on and 1 or 0) end
    b.glyph.color(on and QTR.C.dark or QTR.C.sub)
  end
  return b
end

-- The look of the grip lives only here: a thin strip at the right edge (rounded on the left only: the skin reaches 8 px past the screen edge, so the
-- right corners are cut off), very dark and translucent, with a hairline warm edge; a small chevron appears on hover only. The opacity of the whole
-- grip including the pill (option "Griff-Deckkraft") is driven by QTR.step.
-- Contract: h.glow, h.skin, h.edge, h.bg (with .color), h.chev (hover only); h.letters stays empty (no lettering).
local function paintGrip(h)
  h.glow = tex(h, nil, "BACKGROUND", nil, -2)
  if Theme and Theme.TEX and Theme.TEX.glow then h.glow:SetTexture(Theme.TEX.glow) end
  pt(h.glow, "TOPLEFT", h, "TOPLEFT", -14, 14)
  pt(h.glow, "BOTTOMRIGHT", h, "BOTTOMRIGHT", 14, -14)
  setColor(h.glow, QTR.C.gold, 0)
  h.letters = {}
  h.skin = CreateFrame("Frame", nil, h)
  pt(h.skin, "TOPLEFT", h, "TOPLEFT", 0, 0)
  pt(h.skin, "BOTTOMRIGHT", h, "BOTTOMRIGHT", 8, 0)
  if h.skin.SetFrameLevel then h.skin:SetFrameLevel(31) end
  h.edge = plate(h.skin, QTR.C.gold, 0.2, 6, true)
  h.bg = plate(h.skin, QTR.C.bg, 0.85, 6)
  h.chev = icon(h, "chevL", 8, QTR.C.gold, 2)
  h.chev.color(QTR.C.gold, 0)
end
QTR.paintGrip = paintGrip

local function handleFrame()
  local h = makeButton(UIParent, QTR.HANDLE.w, QTR.HANDLE.h)
  h:SetFrameStrata(QTR.STRATA)
  h:SetFrameLevel(30)
  if h.SetClampedToScreen then h:SetClampedToScreen(true) end
  paintGrip(h)
  -- log-fill pill: upright, current quest count over a thin line over the maximum (e.g. 25 / 40)
  h.badge = CreateFrame("Frame", nil, h)
  size(h.badge, 16, 26)
  if h.badge.SetFrameLevel then h.badge:SetFrameLevel(33) end
  h.badge.bg = plate(h.badge, QTR.C.gold, 1, 6)
  h.badge.cur = font(h.badge, "text", QTR.BADGE_FONT, QTR.C.dark, "CENTER")
  h.badge.max = font(h.badge, "text", QTR.BADGE_FONT, QTR.C.dark, "CENTER")
  h.badge.sep = tex(h.badge, nil, "OVERLAY")
  h.badge.sep:SetColorTexture(1, 1, 1, 1)
  hair(h.badge.sep, nil, 1)
  h.badge.text = h.badge.cur -- the filled count (compat)
  -- layout: chevron at the top (hover only), the pill in the middle, flush with the right edge of the strip and sticking out to the left
  local function stack()
    local bh = num(h.badge:GetHeight()) or 26
    size(h, QTR.HANDLE.w, max(QTR.HANDLE.h, bh + 2 * 24))
    clear(h.chev)
    pt(h.chev, "TOP", h, "TOP", 0, -8)
    clear(h.badge)
    pt(h.badge, "RIGHT", h, "RIGHT", 0, -4)
  end
  h.stack = stack
  stack()
  h:SetScript("OnClick", function() safe(QTR.togglePin) end)
  h:SetScript("OnEnter", function(self)
    st.handleHover = true
  end)
  h:SetScript("OnLeave", function()
    st.handleHover = false
  end)
  return h
end

local function toastFrame()
  local t = CreateFrame("Frame", nil, UIParent)
  size(t, QTR.TOAST_W, QTR.TOAST_H)
  t:SetFrameStrata(QTR.STRATA)
  t:SetFrameLevel(40)
  t.edge = plate(t, QTR.C.gold, 0.5, 8, true)
  t.bg = plate(t, QTR.C.bg, 0.9, 8)
  t.icon = nil
  t.title = font(t, "text", 10, QTR.C.gold, "LEFT")
  pt(t.title, "TOPLEFT", t, "TOPLEFT", 27, -8)
  width(t.title, QTR.TOAST_W - 37)
  if t.title.SetWordWrap then t.title:SetWordWrap(false) end
  if t.title.SetMaxLines then t.title:SetMaxLines(1) end -- a too long title ends with "..." on its one line
  t.text = font(t, "text", 12, QTR.C.white, "LEFT")
  pt(t.text, "TOPLEFT", t, "TOPLEFT", 10, -22)
  width(t.text, QTR.TOAST_W - 20)
  if t.text.SetWordWrap then t.text:SetWordWrap(true) end -- the objective may break into up to 2 lines (QTR.fitToast)
  if t.text.SetMaxLines then t.text:SetMaxLines(2) end
  t.track = solid(t, QTR.C.white, "ARTWORK")
  setColor(t.track, QTR.C.white, 0.1)
  pt(t.track, "BOTTOMLEFT", t, "BOTTOMLEFT", 10, 8)
  size(t.track, QTR.TOAST_W - 20, 2)
  t.bar = solid(t, QTR.C.gold, "OVERLAY")
  pt(t.bar, "LEFT", t.track, "LEFT", 0, 0)
  size(t.bar, 1, 2)
  -- flash plate (additive, over everything) and a clipped shine strip (two gradient halves) running once across the toast
  t.fx = CreateFrame("Frame", nil, t)
  t.fx:SetAllPoints(t)
  t.fx:SetFrameLevel(t:GetFrameLevel() + 5)
  t.flash = plate(t.fx, QTR.C.white, 0, 8)
  for _, part in ipairs(t.flash and t.flash.parts or {}) do
    if part.SetBlendMode then part:SetBlendMode("ADD") end
  end
  t.clip = CreateFrame("Frame", nil, t)
  t.clip:SetFrameLevel(t:GetFrameLevel() + 6)
  if t.clip.SetClipsChildren then t.clip:SetClipsChildren(true) end
  pt(t.clip, "TOPLEFT", t, "TOPLEFT", 3, -3)
  pt(t.clip, "BOTTOMRIGHT", t, "BOTTOMRIGHT", -3, 3)
  t.shineL = tex(t.clip, nil, "OVERLAY")
  t.shineR = tex(t.clip, nil, "OVERLAY")
  for _, sh in ipairs({ t.shineL, t.shineR }) do
    sh:SetColorTexture(1, 1, 1, 1)
    if sh.SetBlendMode then sh:SetBlendMode("ADD") end
    crisp(sh, false)
    width(sh, QTR.SHINE_W / 2)
    sh:Hide()
  end
  t:EnableMouse(false)
  t:Hide()
  return t
end

-- panel: background gradient (transparent left -> dark right), fixed head, scrolling body
local function panelFrame()
  local p = CreateFrame("Frame", QTR.NAME, UIParent)
  size(p, QTR.W, 300)
  p:SetFrameStrata(QTR.STRATA)
  p:SetFrameLevel(20)
  if p.SetDontSavePosition then p:SetDontSavePosition(true) end
  p:EnableMouse(true)
  local bgR = tex(p, nil, "BACKGROUND")
  bgR:SetColorTexture(1, 1, 1, 1)
  pt(bgR, "TOPRIGHT", p, "TOPRIGHT", 0, 0)
  pt(bgR, "BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
  width(bgR, QTR.W - QTR.FADE)
  local bgL = tex(p, nil, "BACKGROUND")
  bgL:SetColorTexture(1, 1, 1, 1)
  pt(bgL, "TOPLEFT", p, "TOPLEFT", 0, 0)
  pt(bgL, "BOTTOMRIGHT", bgR, "BOTTOMLEFT", 0, 0)
  p.bgL, p.bgR = bgL, bgR -- no golden edge line at the right: a stripe is not wanted at the screen edge
  QTR.applyLook(p)

  -- head (fixed)
  local hd = CreateFrame("Frame", nil, p)
  size(hd, QTR.CW, 30)
  pt(hd, "TOPLEFT", p, "TOPLEFT", QTR.PAD.left, -QTR.PAD.top)
  hd.eyebrow = font(hd, "head", 11, QTR.C.gold, "LEFT")
  pt(hd.eyebrow, "LEFT", hd, "LEFT", 0, 2)
  hd.eyebrow:SetText(upper(T.title))
  hd.pin = iconButton(hd, "pin", 11)
  pt(hd.pin, "RIGHT", hd, "RIGHT", 0, 2)
  hd.pin:SetScript("OnClick", function() safe(QTR.togglePin) end)
  hd.gear = iconButton(hd, "gear", 12)
  pt(hd.gear, "RIGHT", hd.pin, "LEFT", -6, 0)
  hd.gear:SetScript("OnClick", function() safe(QTR.toggleSettings) end)
  hd.count = font(hd, "text", 10, QTR.C.dim, "RIGHT")
  pt(hd.count, "RIGHT", hd.gear, "LEFT", -6, 0)
  if hd.count.SetWordWrap then hd.count:SetWordWrap(false) end
  if hd.count.SetMaxLines then hd.count:SetMaxLines(1) end
  hd.line = solid(hd, QTR.C.gold, "ARTWORK")
  setColor(hd.line, QTR.C.gold, 0.28)
  pt(hd.line, "BOTTOMLEFT", hd, "BOTTOMLEFT", 0, 0)
  pt(hd.line, "BOTTOMRIGHT", hd, "BOTTOMRIGHT", 0, 0)
  hair(hd.line, nil, 1)
  p.head = hd

  -- body: scroll frame + content
  local sf = CreateFrame("ScrollFrame", nil, p)
  pt(sf, "TOPLEFT", hd, "BOTTOMLEFT", 0, 0)
  pt(sf, "BOTTOMLEFT", p, "BOTTOMLEFT", QTR.PAD.left, QTR.PAD.bottom)
  width(sf, QTR.CW) -- fixed content width = panel width - paddings (nothing may reach the right edge)
  if sf.SetClipsChildren then sf:SetClipsChildren(true) end
  local content = CreateFrame("Frame", nil, sf)
  size(content, QTR.CW, 10)
  sf:SetScrollChild(content)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(_, delta) safe(QTR.scrollBy, -(delta or 0) * 40) end)
  local thumb = solid(p, QTR.C.gold, "OVERLAY")
  setColor(thumb, QTR.C.gold, 0.3)
  width(thumb, 2)
  thumb:Hide()
  p.scroll, p.content, p.thumb = sf, content, thumb
  p:Hide()
  return p
end

-- background look (options "panel.bgAlpha" = opacity at the right edge, "panel.fadeWidth" = width of the transparent run-out on the left;
-- the dark part keeps 0.96 : 0.92 between its two ends). Re-applied whenever one of them changes.
function QTR.applyLook(p, s)
  p = p or (st.frames and st.frames.panel)
  if not p then return end
  s = s or settings()
  local a = s.panel.bgAlpha or 0.96
  local fw = s.panel.fadeWidth or QTR.FADE
  local c = QTR.C.bg
  width(p.bgR, QTR.W - fw)
  gradient(p.bgR, "HORIZONTAL", { c[1], c[2], c[3], a * 0.92 / 0.96 }, { c[1], c[2], c[3], a })
  p.bgL:SetShown(fw > 0)
  if fw > 0 then gradient(p.bgL, "HORIZONTAL", { c[1], c[2], c[3], 0 }, { c[1], c[2], c[3], a * 0.92 / 0.96 }) end
  p.lookKey = a .. "|" .. fw
end

local function driverFrame()
  local d = CreateFrame("Frame", nil, UIParent)
  size(d, 1, 1)
  d:SetScript("OnUpdate", function(_, elapsed) safe(QTR.step, elapsed) end)
  return d
end

local function ensureFrames()
  if st.frames then return st.frames end
  local f = { handle = handleFrame(), panel = panelFrame(), toast = toastFrame(), driver = driverFrame() }
  st.frames = f
  QTR.place()
  return f
end
QTR.ensureFrames = ensureFrames

-- ---------------------------------------------------------------- pools

local pools = {}
local function pool(kind, make)
  local p = pools[kind]
  if not p then
    p = { free = {}, used = {}, make = make }
    pools[kind] = p
  end
  return p
end

local function acquire(kind, make, parent)
  local p = pool(kind, make)
  local o = table.remove(p.free)
  if not o then o = p.make(parent) end
  if o.GetParent and o:GetParent() ~= parent and o.SetParent then o:SetParent(parent) end
  p.used[#p.used + 1] = o
  clear(o)
  o:SetAlpha(1) -- a block reused in the middle of the fade-in keeps no half alpha
  o.stagger = nil
  o:Show()
  return o
end

local function releasePools()
  for _, p in pairs(pools) do
    for _, o in ipairs(p.used) do
      o:Hide()
      p.free[#p.free + 1] = o
    end
    p.used = {}
  end
end

-- ---------------------------------------------------------------- blocks (body content)

local CW = QTR.CW

local function newBlock(parent)
  local b = CreateFrame("Frame", nil, parent)
  size(b, CW, 10)
  return b
end

-- a switch row (label + knob), D4
local function newSwitch(parent)
  local b = makeButton(parent, CW - 20, 22)
  b.label = font(b, "text", 11, QTR.C.text, "LEFT")
  pt(b.label, "LEFT", b, "LEFT", 0, 0)
  width(b.label, CW - 56)
  if b.label.SetWordWrap then b.label:SetWordWrap(false) end
  b.track = CreateFrame("Frame", nil, b)
  size(b.track, 24, 13)
  pt(b.track, "RIGHT", b, "RIGHT", 0, 0)
  b.track.bg = plate(b.track, QTR.C.white, 0.18, 6)
  b.knob = tex(b.track, nil, "OVERLAY")
  if Theme and Theme.TEX and Theme.TEX.disc then b.knob:SetTexture(Theme.TEX.disc) else b.knob:SetColorTexture(1, 1, 1, 1) end
  size(b.knob, 9, 9)
  function b.set(on)
    b.on = on
    if b.track.bg then b.track.bg.color(on and QTR.C.gold or QTR.C.white, on and 0.6 or 0.18) end
    setColor(b.knob, on and QTR.C.white or QTR.C.faint)
    clear(b.knob)
    pt(b.knob, "LEFT", b.track, "LEFT", on and 13 or 2, 0)
  end
  b:SetScript("OnClick", function(self) if self.toggle then safe(self.toggle) end end)
  return b
end

local function newSeg(parent)
  local b = makeButton(parent, 70, 22)
  b.bg = plate(b, QTR.C.gold, 0, 4)
  b.label = font(b, "text", 11, QTR.C.dim, "CENTER")
  pt(b.label, "CENTER", b, "CENTER", 0, 0)
  function b.set(on)
    b.on = on
    if b.bg then b.bg.color(QTR.C.gold, on and 1 or 0) end
    setColor(b.label, on and QTR.C.dark or QTR.C.dim)
  end
  b:SetScript("OnClick", function(self) if self.pick then safe(self.pick) end end)
  return b
end

local function newHeading(parent)
  local fs = font(parent, "text", 9, QTR.C.zone, "LEFT")
  return fs
end

-- settings block (D4)
local SETTINGS = {
  { head = "sSort", seg = { "zones", "distance", "level" } },
  { head = "sFilter", sw = { { "filter.done", "fDone" }, { "filter.group", "fGroup" }, { "filter.zoneOnly", "fZone" } } },
  { head = "sList", sw = { { "look.objs", "lObjs" }, { "look.dist", "lDist" }, { "look.icons", "lIcons" } } },
  { head = "sFocus", sw = { { "focus.show", "fShow" }, { "focus.dist", "fDist" }, { "focus.bar", "fBar" }, { "focus.giver", "fGiver" },
    { "focus.rewards", "fRew" } } },
  { head = "sHints", sw = { { "panel.notify", "hNotify" } } },
}
QTR.SETTINGS = SETTINGS

local function getKey(s, key)
  local g, k = key:match("^(%a+)%.(%a+)$")
  return s[g] and s[g][k]
end

local function setKey(key, value)
  local Q = QT()
  if Q.set(key, value) then QTR.request() end
end

local function layoutSettings(block)
  local s = settings()
  local y = 8
  local inner = block
  if not block.plate then
    block.edge = plate(block, QTR.C.gold, 0.2, 8, true)
    block.plate = plate(block, QTR.C.white, 0.04, 8)
  end
  for _, sec in ipairs(SETTINGS) do
    local h = acquire("heading", function(par) local f = CreateFrame("Frame", nil, par) size(f, CW - 20, 14) f.fs = newHeading(f) pt(f.fs, "LEFT", f, "LEFT", 0, 0) return f end, inner)
    h.fs:SetText(upper(T[sec.head]))
    y = y + (y > 8 and 8 or 0)
    pt(h, "TOPLEFT", inner, "TOPLEFT", 10, -y)
    y = y + 14
    if sec.seg then
      local strip = acquire("segstrip", function(par)
        local f = CreateFrame("Frame", nil, par)
        size(f, CW - 20, 26)
        f.bg = plate(f, { 0, 0, 0 }, 0.35, 6)
        return f
      end, inner)
      pt(strip, "TOPLEFT", inner, "TOPLEFT", 10, -y)
      local w = (CW - 20 - 4 - 4) / 3
      for i, key in ipairs(sec.seg) do
        local b = acquire("seg", newSeg, strip)
        size(b, w, 22)
        pt(b, "TOPLEFT", strip, "TOPLEFT", 2 + (i - 1) * (w + 2), -2)
        b.label:SetText(T.sort[key])
        b.set(s.order == key)
        b.pick = function() setKey("order", key) end
      end
      y = y + 26 + 2
    else
      for _, it in ipairs(sec.sw) do
        local b = acquire("switch", newSwitch, inner)
        pt(b, "TOPLEFT", inner, "TOPLEFT", 10, -y)
        b.label:SetText(T[it[2]])
        local key = it[1]
        b.set(getKey(s, key) == true)
        b.toggle = function() setKey(key, not (getKey(settings(), key) == true)) end
        y = y + 22
      end
    end
  end
  y = y + 8
  height(block, y)
  return y
end

-- one objective line (marker + count + text); bar optional (focus card)
local function newObj(parent, asButton)
  local f = asButton and makeButton(parent, CW, 15) or CreateFrame("Frame", nil, parent)
  size(f, CW, 15)
  f.mark = font(f, "text", 11, QTR.C.muted, "LEFT")
  f.mark:SetText("·")
  f.check = icon(f, "check", 9, QTR.C.check, 2.4)
  f.count = font(f, "text", 11, QTR.C.white, "LEFT")
  f.text = font(f, "text", 11, QTR.C.text, "LEFT")
  if f.text.SetWordWrap then f.text:SetWordWrap(true) end
  f.track = solid(f, QTR.C.white, "ARTWORK")
  setColor(f.track, QTR.C.white, 0.08)
  height(f.track, 2)
  f.bar = solid(f, QTR.C.gold, "OVERLAY")
  height(f.bar, 2)
  return f
end

-- a material line of a shopping list in the to-do section: an objective line that is a button (click opens the slip)
local function newShopObj(parent)
  local f = newObj(parent, true)
  f:SetScript("OnClick", function(self)
    local Tr = TT()
    if Tr and Tr.openRow then Tr.openRow({ shop = true, id = self.planId }) end
  end)
  return f
end

local function fillObj(f, o, indent, wid, withBar, quest)
  local done = o.done == true
  local multi = o.need ~= nil and o.need > 1
  clear(f.mark)
  pt(f.mark, "TOPLEFT", f, "TOPLEFT", indent, 0)
  clear(f.check)
  pt(f.check, "TOPLEFT", f, "TOPLEFT", indent, -3)
  f.mark:SetShown(not done)
  f.check:SetShown(done)
  f.check:SetScale(1)
  f.check:SetAlpha(1)
  local x = indent + 9 + 6
  local countText = multi and string.format("%d/%d", min(o.have or 0, o.need), o.need) or nil
  f.count:SetShown(countText ~= nil)
  if countText then
    f.count:SetText(countText)
    clear(f.count)
    pt(f.count, "TOPLEFT", f, "TOPLEFT", x, 0)
    x = x + max(26, (num(f.count:GetStringWidth()) or 26) + 4)
  end
  local label = o.label or o.text or ""
  f.text:SetText(label)
  clear(f.text)
  pt(f.text, "TOPLEFT", f, "TOPLEFT", x, 0)
  width(f.text, max(40, wid - x))
  local c = done and QTR.C.done or QTR.C.text
  setColor(f.text, c)
  setColor(f.count, done and QTR.C.done or QTR.C.white)
  local h = max(15, (num(f.text:GetStringHeight()) or 13) + 2)
  if withBar then
    clear(f.track)
    pt(f.track, "TOPLEFT", f, "TOPLEFT", indent + 15, -(h + 2))
    width(f.track, max(10, wid - indent - 15))
    local pct = (o.need and o.need > 0) and min(1, (o.have or 0) / o.need) or (done and 1 or 0)
    clear(f.bar)
    pt(f.bar, "LEFT", f.track, "LEFT", 0, 0)
    width(f.bar, max(0.01, (wid - indent - 15) * pct))
    f.bar:SetShown(pct > 0)
    f.track:Show()
    h = h + 6
  else
    f.track:Hide()
    f.bar:Hide()
  end
  size(f, wid, h)
  f.quest, f.obj, f.done = quest, o, done
  return h
end

local function newTurnin(parent)
  local f = CreateFrame("Frame", nil, parent)
  size(f, CW, 16)
  f.q = font(f, "head", 12, QTR.C.gold, "LEFT")
  f.q:SetText("?")
  pt(f.q, "TOPLEFT", f, "TOPLEFT", 0, 0)
  f.text = font(f, "text", 11, QTR.C.turnin, "LEFT")
  pt(f.text, "TOPLEFT", f, "TOPLEFT", 12, -1)
  if f.text.SetWordWrap then f.text:SetWordWrap(false) end
  return f
end

local function turninText(rec)
  if rec.finisher and rec.finisher ~= "" then return T("turnin", rec.finisher) end
  return T.turninPlain
end

-- zone head (D6): name, line, count, chevron
local function newZone(parent)
  local b = makeButton(parent, CW, 20)
  b.name = font(b, "text", 9, QTR.C.zone, "LEFT")
  pt(b.name, "LEFT", b, "LEFT", 0, 0)
  if b.name.SetWordWrap then b.name:SetWordWrap(false) end
  b.chev = icon(b, "chevD", 8, QTR.C.muted, 2.2)
  pt(b.chev, "RIGHT", b, "RIGHT", 0, 0)
  b.count = font(b, "text", 9, QTR.C.muted, "RIGHT")
  pt(b.count, "RIGHT", b.chev, "LEFT", -6, 0)
  b.line = tex(b, nil, "ARTWORK")
  b.line:SetColorTexture(1, 1, 1, 1)
  hair(b.line, nil, 1)
  gradient(b.line, "HORIZONTAL", { QTR.C.zone[1], QTR.C.zone[2], QTR.C.zone[3], 0.45 }, { QTR.C.zone[1], QTR.C.zone[2], QTR.C.zone[3], 0 })
  b:SetScript("OnClick", function(self) if self.toggle then QTR.whenFree(self.toggle) end end)
  return b
end

-- quest row (D6)
local function newQuest(parent)
  local q = CreateFrame("Frame", nil, parent)
  size(q, CW, 22)
  q.flash = solid(q, QTR.C.gold, "BACKGROUND")
  setColor(q.flash, QTR.C.gold, 0)
  q.flash:SetAllPoints(q)
  -- faint box (only in the boxed layout): a few percent of light surface and a fine line
  q.box = { fill = solid(q, QTR.C.gold, "BACKGROUND"), top = solid(q, QTR.C.gold, "BACKGROUND"), bottom = solid(q, QTR.C.gold, "BACKGROUND"),
    left = solid(q, QTR.C.gold, "BACKGROUND"), right = solid(q, QTR.C.gold, "BACKGROUND") }
  q.box.fill:SetAllPoints(q)
  pt(q.box.top, "TOPLEFT", q, "TOPLEFT", 0, 0)
  pt(q.box.top, "TOPRIGHT", q, "TOPRIGHT", 0, 0)
  hair(q.box.top, nil, 1)
  pt(q.box.bottom, "BOTTOMLEFT", q, "BOTTOMLEFT", 0, 0)
  pt(q.box.bottom, "BOTTOMRIGHT", q, "BOTTOMRIGHT", 0, 0)
  hair(q.box.bottom, nil, 1)
  pt(q.box.left, "TOPLEFT", q, "TOPLEFT", 0, 0)
  pt(q.box.left, "BOTTOMLEFT", q, "BOTTOMLEFT", 0, 0)
  hair(q.box.left, 1)
  pt(q.box.right, "TOPRIGHT", q, "TOPRIGHT", 0, 0)
  pt(q.box.right, "BOTTOMRIGHT", q, "BOTTOMRIGHT", 0, 0)
  hair(q.box.right, 1)
  setColor(q.box.fill, QTR.C.gold, 0.05)
  for _, k in ipairs({ "top", "bottom", "left", "right" }) do setColor(q.box[k], QTR.C.gold, 0.16) end
  -- focus quest stays in the list: warm gold surface + a fine gold line on the left edge (the only focus mark)
  q.focusFill = solid(q, QTR.C.gold, "BACKGROUND")
  q.focusFill:SetAllPoints(q)
  setColor(q.focusFill, QTR.C.gold, 0.11)
  -- ready to turn in (design requirement): a muted green 1-pixel frame + a faint green surface around the whole row / box, in both layouts;
  -- the gold focus line lies above it (focus + ready = gold line left, green frame around)
  q.ready = { fill = solid(q, QTR.C.check, "BACKGROUND", 1), top = solid(q, QTR.C.check, "BORDER"), bottom = solid(q, QTR.C.check, "BORDER"),
    left = solid(q, QTR.C.check, "BORDER"), right = solid(q, QTR.C.check, "BORDER") }
  q.ready.fill:SetAllPoints(q)
  pt(q.ready.top, "TOPLEFT", q, "TOPLEFT", 0, 0)
  pt(q.ready.top, "TOPRIGHT", q, "TOPRIGHT", 0, 0)
  hair(q.ready.top, nil, 1)
  pt(q.ready.bottom, "BOTTOMLEFT", q, "BOTTOMLEFT", 0, 0)
  pt(q.ready.bottom, "BOTTOMRIGHT", q, "BOTTOMRIGHT", 0, 0)
  hair(q.ready.bottom, nil, 1)
  pt(q.ready.left, "TOPLEFT", q, "TOPLEFT", 0, 0)
  pt(q.ready.left, "BOTTOMLEFT", q, "BOTTOMLEFT", 0, 0)
  hair(q.ready.left, 1)
  pt(q.ready.right, "TOPRIGHT", q, "TOPRIGHT", 0, 0)
  pt(q.ready.right, "BOTTOMRIGHT", q, "BOTTOMRIGHT", 0, 0)
  hair(q.ready.right, 1)
  setColor(q.ready.fill, QTR.C.check, QTR.READY.fill)
  for _, k in ipairs({ "top", "bottom", "left", "right" }) do setColor(q.ready[k], QTR.C.check, QTR.READY.edge) end
  for _, r in pairs(q.ready) do r:Hide() end
  q.focusBar = solid(q, QTR.C.gold, "BORDER", 2)
  width(q.focusBar, 2)
  pt(q.focusBar, "TOPLEFT", q, "TOPLEFT", 0, 0)
  pt(q.focusBar, "BOTTOMLEFT", q, "BOTTOMLEFT", 0, 0)
  setColor(q.focusBar, QTR.C.gold, 0.95)
  q.focusFill:Hide()
  q.focusBar:Hide()
  -- type symbol = focus switch (with "Questtyp-Symbole" off the target stands in the same place)
  q.sym = makeButton(q, 16, 20)
  pt(q.sym, "TOPLEFT", q, "TOPLEFT", 0, 0)
  q.sym.icons = {}
  for _, k in ipairs({ "collect", "kill", "explore", "talk", "turnin" }) do
    local g = icon(q.sym, k, 12, QTR.C.title, 1.6)
    pt(g, "CENTER", q.sym, "CENTER", -1, 0)
    q.sym.icons[k] = g
  end
  q.sym.target = icon(q.sym, "target", 11, QTR.C.tgt, 1.7)
  pt(q.sym.target, "CENTER", q.sym, "CENTER", -1, 0)
  -- no ring around the symbol any more (playtest: circle + line was a double mark); the focus is the gold line + the warm row
  q.sym:SetScript("OnEnter", function(self)
    self.hover = true
    QTR.paintSym(q)
  end)
  q.sym:SetScript("OnLeave", function(self) self.hover = false QTR.paintSym(q) end)
  q.sym:SetScript("OnClick", function() if q.rec then QTR.whenFree(function() QT().toggleFocus(q.rec.questID) end) end end)
  -- read-aloud button right of the symbol (only with Spoken)
  q.speak = speakButton(q, 20)
  pt(q.speak, "TOPLEFT", q, "TOPLEFT", 16, 0)
  q.speak:Hide()
  -- title button
  q.title = makeButton(q, 120, 20)
  q.title.text = font(q.title, "text", 12, QTR.C.title, "LEFT")
  pt(q.title.text, "LEFT", q.title, "LEFT", 0, 0)
  if q.title.text.SetWordWrap then q.title.text:SetWordWrap(false) end
  if q.title.text.SetMaxLines then q.title.text:SetMaxLines(1) end
  q.title.lv = font(q.title, "text", 10, QTR.C.title, "LEFT")
  q.title.el = CreateFrame("Frame", nil, q.title)
  size(q.title.el, 30, 11)
  q.title.el.edge = solid(q.title.el, QTR.C.eliteEdge, "BORDER")
  q.title.el.edge:SetAllPoints(q.title.el)
  q.title.el.fill = solid(q.title.el, QTR.C.bg, "ARTWORK")
  pt(q.title.el.fill, "TOPLEFT", q.title.el, "TOPLEFT", 1, -1)
  pt(q.title.el.fill, "BOTTOMRIGHT", q.title.el, "BOTTOMRIGHT", -1, 1)
  q.title.el.text = font(q.title.el, "text", 8, QTR.C.elite, "CENTER")
  pt(q.title.el.text, "CENTER", q.title.el, "CENTER", 0, 0)
  q.title.el.text:SetText(T.elite)
  q.title:SetScript("OnClick", function(self, button) QTR.rowClick(q, button) end)
  q.title:SetScript("OnEnter", function(self)
    if q.rec then setColor(self.text, QTR.C.titleHover) end
  end)
  q.title:SetScript("OnLeave", function(self)
    if q.rec then setColor(self.text, q.rec.complete and QTR.C.turnin or QTR.C.title) end
  end)
  -- distance (optional)
  q.dist = CreateFrame("Frame", nil, q)
  size(q.dist, 50, 20)
  q.dist.arrow = arrowTex(q.dist, 12)
  q.dist.text = font(q.dist, "text", 10, QTR.C.faint, "LEFT")
  pt(q.dist.arrow, "LEFT", q.dist, "LEFT", 0, 0)
  pt(q.dist.text, "LEFT", q.dist, "LEFT", 15, 0)
  q.objs = {}
  return q
end

function QTR.paintSym(q)
  local rec = q.rec
  if not rec then return end
  local s = settings()
  local icons = s.look.icons == true
  local hover = q.sym.hover == true
  -- type symbol: one neutral muted gold for every quest (never the difficulty colour; only level and title carry colours)
  -- ready to turn in: a muted green arrow to the right replaces the type symbol (still the focus switch)
  local want = rec.complete == true and "turnin" or (rec.kind or "explore")
  local c = hover and QTR.C.white or (want == "turnin" and QTR.C.symReady or QTR.C.sym)
  for k, g in pairs(q.sym.icons) do
    g:SetShown(icons and k == want)
    g.color(c)
  end
  q.sym.target:SetShown(not icons)
  q.sym.target.color(hover and QTR.C.gold or QTR.C.sym)
end

local function fillQuest(q, rec, s, view)
  q.rec = rec
  local c = diffColor(rec)
  local B = QTR.BOX
  local boxed = s.look.dist == true
  local k = QTR.lineK()
  local ox = boxed and B.padX or B.padInset -- inner left offset (never 0: the symbol keeps a gap to the gold focus line)
  local oy = boxed and B.padTop or 0 -- inner top offset
  q.boxed = boxed
  local ready = rec.complete == true
  -- ready to turn in: the green frame replaces the gold box lines (no double edge), in the compact list it is the only frame
  for key, r in pairs(q.box) do r:SetShown(boxed and not (ready and key ~= "fill")) end
  for _, r in pairs(q.ready) do r:SetShown(ready) end
  local isFocus = QT().focus() == rec.questID
  q.focusFill:SetShown(isFocus)
  q.focusBar:SetShown(isFocus)
  clear(q.sym)
  pt(q.sym, "TOPLEFT", q, "TOPLEFT", ox, -oy)
  QTR.paintSym(q)
  -- distance only exists in the boxed list (own meta line below the title, placed after the title)
  local d = boxed and dist(rec.dist) or nil
  q.dist:SetShown(d ~= nil)
  if d then
    q.dist.text:SetText(d)
    size(q.dist, (num(q.dist.text:GetStringWidth()) or 30) + 17, math.ceil(B.metaH * k))
    local b = QT().bearing(rec)
    q.dist.arrow:SetShown(b ~= nil)
    if b then q.dist.arrow.turn(b) end
  end
  -- title: [level] text, elite tag
  local tb = q.title
  clear(tb)
  q.speak:Bind(speakOn() and rec or nil)
  clear(q.speak)
  pt(q.speak, "TOPLEFT", q, "TOPLEFT", ox + 16, -oy)
  local sp = q.speak:IsShown() and QTR.SPEAK_W or 0 -- room only when the button is there
  local tx = ox + 14 + 6 + sp
  pt(tb, "TOPLEFT", q, "TOPLEFT", tx, -oy)
  local avail = CW - tx - (boxed and B.padX or 0)
  size(tb, avail, 20)
  -- level in brackets in front of the title, in the difficulty colour; only the title is ever shortened, never the level
  tb.lv:SetText(rec.level and ("[" .. tostring(rec.level) .. "]") or "")
  setColor(tb.lv, c)
  clear(tb.lv)
  pt(tb.lv, "LEFT", tb, "LEFT", 0, 0)
  local lw = rec.level and ((num(tb.lv:GetStringWidth()) or 18) + 4) or 0
  local ew = rec.elite and 36 or 0
  width(tb.text, 0) -- drop the earlier width first: a text that was cut short would otherwise measure its cut-off width again
  tb.text:SetText(rec.title or "")
  setColor(tb.text, rec.complete and QTR.C.turnin or QTR.C.title)
  local tw = min(num(tb.text:GetStringWidth()) or avail, max(30, avail - lw - ew))
  width(tb.text, tw)
  clear(tb.text)
  pt(tb.text, "LEFT", tb, "LEFT", lw, 0)
  tb.el:SetShown(rec.elite == true)
  clear(tb.el)
  pt(tb.el, "LEFT", tb.text, "RIGHT", 6, 0)
  -- meta line (boxed list): direction arrow + distance under the title
  local y
  if boxed then
    y = oy + math.ceil(20 * k)
    if d then
      clear(q.dist)
      pt(q.dist, "TOPLEFT", q, "TOPLEFT", tx, -y)
      y = y + math.ceil(B.metaH * k) + 1
    else
      y = y + 2
    end
  end
  -- objectives / turn-in line
  y = y or math.ceil((rec.complete and 20 or 22) * k) -- ready: the row is just the title line
  q.objs = {} -- the pooled children were released (hidden) at the start of the layout
  if rec.complete then
    -- ready to turn in: one compact row (green frame, arrow, level, title) WITHOUT the "Abgeben ..." line; the focus card keeps it
  elseif s.look.objs then
    for _, o in ipairs(rec.objectives or {}) do
      if not (o.done and s.look.doneObj == "hide") then
        local f = acquire("obj", newObj, q)
        pt(f, "TOPLEFT", q, "TOPLEFT", ox, -y)
        y = y + fillObj(f, o, 18, CW - 2 * ox, false, rec) + 1
        q.objs[#q.objs + 1] = f
      end
    end
  end
  local h = y + (boxed and B.padBot or 3)
  height(q, h)
  return h
end

local function newTodo(parent)
  local b = makeButton(parent, CW, 18)
  b.icons = {}
  for _, k in ipairs({ "dotSmall", "place", "kill", "collect" }) do
    local g = icon(b, k, 11, QTR.C.gold, 1.6)
    pt(g, "TOPLEFT", b, "TOPLEFT", 2, -2)
    b.icons[k] = g
  end
  b.text = font(b, "text", 11, QTR.C.text, "LEFT")
  pt(b.text, "TOPLEFT", b, "TOPLEFT", 18, -1)
  if b.text.SetWordWrap then b.text:SetWordWrap(true) end
  if b.text.SetMaxLines then b.text:SetMaxLines(2) end
  b.extra = font(b, "text", 10, QTR.C.faint, "RIGHT")
  pt(b.extra, "TOPRIGHT", b, "TOPRIGHT", 0, -1)
  b:SetScript("OnClick", function()
    local Tr = TT()
    if Tr and Tr.openBook then safe(Tr.openBook) end
  end)
  b:SetScript("OnEnter", function(self) setColor(self.text, QTR.C.titleHover) end)
  b:SetScript("OnLeave", function(self) setColor(self.text, self.done and QTR.C.done or QTR.C.text) end)
  return b
end

local TODO_ICON = { free = "dotSmall", place = "place", kill = "kill", item = "collect" }

-- Line breaks of a to-do made here (playtest: "Zum Lehrer: 8 neue Zauber (3 G 06 S 00 K)" broke inside the money): only at spaces
-- between words; a bare number stays with the word after it ("8 neue", "3 G"), a bracket "( ... )" stays in one piece when it fits
-- on a line. The following line starts under the text (same left-aligned FontString). Longer than the room: the client still wraps.
function QTR.wrapLine(fs, text, w)
  if type(text) ~= "string" or text == "" or not (fs and fs.GetStringWidth and fs.SetText) or not w or w <= 0 then return text end
  local function measure(s)
    fs:SetText(s)
    return num(fs:GetStringWidth()) or 0
  end
  width(fs, 0) -- measure unbounded
  if text:find("\n", 1, true) or measure(text) <= w then return text end
  local words = {}
  for wd in text:gmatch("%S+") do words[#words + 1] = wd end
  -- atoms: a bare number (also "(3") joins the next word
  local atoms, i = {}, 1
  while i <= #words do
    local a = words[i]
    while words[i + 1] and a:find("^%(?[%d%.,]+$") do
      i = i + 1
      a = a .. " " .. words[i]
    end
    atoms[#atoms + 1] = a
    i = i + 1
  end
  -- units: a bracket group as one piece (its atoms as fallback when it is too wide)
  local units, j = {}, 1
  while j <= #atoms do
    local a = atoms[j]
    if a:find("^%(") and not a:find("%)[%p]*$") then
      local parts, k = { a }, j
      while k < #atoms and not atoms[k]:find("%)[%p]*$") do
        k = k + 1
        parts[#parts + 1] = atoms[k]
      end
      local whole = table.concat(parts, " ")
      if measure(whole) <= w then units[#units + 1] = whole else for _, p in ipairs(parts) do units[#units + 1] = p end end
      j = k + 1
    else
      units[#units + 1] = a
      j = j + 1
    end
  end
  local lines, cur = {}, ""
  for _, u in ipairs(units) do
    local cand = cur == "" and u or (cur .. " " .. u)
    if cur ~= "" and measure(cand) > w then
      lines[#lines + 1] = cur
      cur = u
    else
      cur = cand
    end
  end
  if cur ~= "" then lines[#lines + 1] = cur end
  return table.concat(lines, "\n")
end

local function fillTodo(b, r)
  for k, g in pairs(b.icons) do g:SetShown(k == (TODO_ICON[r.kind] or "dotSmall")) end
  b.done = r.done
  b.extra:SetText(r.extra or "")
  local ew = (r.extra and (num(b.extra:GetStringWidth()) or 30) + 6) or 0
  local tw = CW - 18 - ew
  b.text:SetText(QTR.wrapLine(b.text, r.text or "", tw))
  width(b.text, tw)
  setColor(b.text, r.done and QTR.C.done or QTR.C.text)
  local h = max(18, (num(b.text:GetStringHeight()) or 13) + 5)
  height(b, h)
  return h
end

-- focus card (D5)
local function newFocus(parent)
  local f = CreateFrame("Frame", nil, parent)
  size(f, CW, 80)
  f.edge = plate(f, QTR.C.gold, 0.42, 8, true)
  f.plate = plate(f, QTR.C.gold, 0.09, 8)
  f.label = CreateFrame("Frame", nil, f)
  size(f.label, CW - 20, 18)
  pt(f.label, "TOPLEFT", f, "TOPLEFT", 10, -6)
  f.label.icon = icon(f.label, "target", 9, QTR.C.gold, 2)
  pt(f.label.icon, "LEFT", f.label, "LEFT", 0, 0)
  f.label.text = font(f.label, "text", 9, QTR.C.gold, "LEFT")
  pt(f.label.text, "LEFT", f.label, "LEFT", 14, 0)
  f.label.text:SetText(upper(T.focus))
  f.unf = makeButton(f.label, 18, 18)
  pt(f.unf, "RIGHT", f.label, "RIGHT", 0, 0)
  f.unf.glyph = icon(f.unf, "close", 9, QTR.C.faint, 2.2)
  pt(f.unf.glyph, "CENTER", f.unf, "CENTER", 0, 0)
  f.unf:SetScript("OnClick", function() QTR.whenFree(function() QT().setFocus(nil) end) end)
  f.unf:SetScript("OnEnter", function(self) self.glyph.color(QTR.C.white) end)
  f.unf:SetScript("OnLeave", function(self) self.glyph.color(QTR.C.faint) end)
  f.titleBtn = makeButton(f, CW - 60, 18)
  f.title = font(f.titleBtn, "head", 13, QTR.C.focusTitle, "LEFT")
  pt(f.title, "TOPLEFT", f.titleBtn, "TOPLEFT", 0, 0)
  if f.title.SetWordWrap then f.title:SetWordWrap(true) end
  f.titleBtn:SetScript("OnClick", function(_, button) if f.rec then QTR.rowClick({ rec = f.rec, title = f.titleBtn }, button) end end)
  f.speak = speakButton(f, 18)
  -- the button lies inside the area of the title button (short title): it must always be the one that gets the mouse, so it sits
  -- two frame levels above it (fillFocus also cuts the title button's hit area at the end of the title text)
  if f.speak.SetFrameLevel and f.titleBtn.GetFrameLevel then f.speak:SetFrameLevel(f.titleBtn:GetFrameLevel() + 2) end
  f.speak:Hide()
  f.sub = font(f, "text", 10, QTR.C.sub, "LEFT")
  if f.sub.SetWordWrap then f.sub:SetWordWrap(false) end
  -- compass
  f.comp = CreateFrame("Frame", nil, f)
  size(f.comp, 40, 42)
  -- compass ring: the four corners of the rounded ring texture with radius = half the size give a smooth circle on whole pixels
  -- (instead of 20 rotated thin strokes); without Theme the line ring stays
  local ring = CreateFrame("Frame", nil, f.comp)
  size(ring, 28, 28, true)
  ring.plate = plate(ring, QTR.C.gold, 0.55, 14, true)
  if ring.plate then
    function ring.color(c, a) ring.plate.color(c, a) end
  else
    ring:Hide()
    ring = glyph(f.comp, "target", 28, QTR.C.gold, 0.9)
    for i, t in ipairs(ring.parts) do if i == #ring.parts then t:Hide() end end
  end
  f.comp.ring = ring
  f.comp.ring.color(QTR.C.gold, 0.55)
  pt(f.comp.ring, "TOP", f.comp, "TOP", 0, 0)
  f.comp.arrow = arrowTex(f.comp, 18)
  pt(f.comp.arrow, "CENTER", f.comp.ring, "CENTER", 0, 0)
  f.comp.dist = font(f.comp, "text", 9, rgb("efe4c8"), "CENTER")
  pt(f.comp.dist, "TOP", f.comp.ring, "BOTTOM", 0, -1)
  -- info lines
  f.giver = CreateFrame("Frame", nil, f)
  size(f.giver, CW - 20, 14)
  f.giver.icon = icon(f.giver, "person", 9, QTR.C.info, 1.8)
  pt(f.giver.icon, "LEFT", f.giver, "LEFT", 0, 0)
  f.giver.text = font(f.giver, "text", 10, QTR.C.info, "LEFT")
  pt(f.giver.text, "LEFT", f.giver, "LEFT", 13, 0)
  width(f.giver.text, CW - 33)
  if f.giver.text.SetWordWrap then f.giver.text:SetWordWrap(false) end
  f.rew = CreateFrame("Frame", nil, f)
  size(f.rew, CW - 20, 14)
  f.rew.xp = font(f.rew, "text", 10, QTR.C.xp, "LEFT")
  f.rew.coin = tex(f.rew, nil, "OVERLAY")
  if Theme and Theme.TEX and Theme.TEX.disc then f.rew.coin:SetTexture(Theme.TEX.disc) else f.rew.coin:SetColorTexture(1, 1, 1, 1) end
  size(f.rew.coin, 7, 7)
  setColor(f.rew.coin, QTR.C.gold)
  f.rew.gold = font(f.rew, "text", 10, QTR.C.coin, "LEFT")
  f.rew.item = font(f.rew, "text", 10, QTR.C.white, "LEFT")
  if f.rew.item.SetWordWrap then f.rew.item:SetWordWrap(false) end
  f.objs = {}
  return f
end

local function fillFocus(f, rec, s, view)
  f.rec = rec
  local x, w = 10, CW - 20
  local compW = s.focus.dist and 44 or 0
  clear(f.titleBtn)
  pt(f.titleBtn, "TOPLEFT", f, "TOPLEFT", x, -25)
  f.speak:Bind(speakOn() and rec or nil)
  local sp = f.speak:IsShown() and QTR.SPEAK_W or 0 -- room only when the button is there
  local tw = w - compW - sp
  width(f.title, 0) -- measure the full text, not an earlier cut-off
  f.title:SetText(rec.title or "")
  width(f.title, tw)
  local th = max(16, (num(f.title:GetStringHeight()) or 15) + 1)
  size(f.titleBtn, tw, th)
  local hitCut = 0
  if sp > 0 then
    local lineW = min(tw, num(f.title:GetStringWidth()) or tw)
    clear(f.speak)
    pt(f.speak, "TOPLEFT", f, "TOPLEFT", x + lineW + 2, -25)
    hitCut = max(0, tw - lineW) -- the title button reacts only on the title text, never on the read-aloud button
  end
  if f.titleBtn.SetHitRectInsets then f.titleBtn:SetHitRectInsets(0, hitCut, 0, 0) end
  -- sub line: level (difficulty colour) · zone · tag
  local c = diffColor(rec)
  local hex = string.format("|cff%02x%02x%02x", floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5))
  local parts = {}
  if rec.level then parts[#parts + 1] = hex .. T("level", rec.level) .. "|r" end
  local Q = QT()
  local zoneName = rec.zone and Q.mapName and Q.mapName(rec.zone) or rec.header
  if zoneName then parts[#parts + 1] = zoneName end
  local tag
  if rec.elite then tag = T.eliteTag end
  if rec.group and rec.groupSize then tag = (tag and (tag .. " · ") or "") .. T("groupTag", rec.groupSize)
  elseif rec.group and not rec.elite then tag = T.groupTagPlain end
  if tag then parts[#parts + 1] = "|cffffcf8a" .. tag .. "|r" end
  f.sub:SetText(table.concat(parts, " · "))
  clear(f.sub)
  pt(f.sub, "TOPLEFT", f, "TOPLEFT", x, -(25 + th + 1))
  width(f.sub, w - compW)
  local y = 25 + th + 1 + 14
  -- compass + distance (arrow only when the facing is readable, D5)
  f.comp:SetShown(s.focus.dist == true)
  if s.focus.dist then
    clear(f.comp)
    pt(f.comp, "TOPRIGHT", f, "TOPRIGHT", -8, -24)
    local d = dist(rec.dist)
    f.comp.dist:SetText(d or "–")
    local b = Q.bearing(rec)
    f.comp.arrow:SetShown(b ~= nil)
    if b then f.comp.arrow.turn(b) end
    y = max(y, 24 + 42 + 2)
  end
  -- objectives with bars
  f.objs = {}
  y = y + 3
  if not rec.complete then
    for _, o in ipairs(rec.objectives or {}) do
      if not (o.done and s.look.doneObj == "hide") then
        local of = acquire("obj", newObj, f)
        pt(of, "TOPLEFT", f, "TOPLEFT", x, -y)
        y = y + fillObj(of, o, 0, w, s.focus.bar == true, rec) + 3
        f.objs[#f.objs + 1] = of
      end
    end
  end
  -- quest giver, rewards
  f.giver:Hide()
  f.rew:Hide()
  if s.focus.giver and rec.starter then
    clear(f.giver)
    pt(f.giver, "TOPLEFT", f, "TOPLEFT", x, -(y + 3))
    f.giver.text:SetText(rec.starter)
    f.giver:Show()
    y = y + 3 + 14
  end
  if s.focus.rewards then
    local r = Q.rewards(rec.questID)
    if r then
      local rx = 0
      local function place(fs, text, gap)
        fs:SetShown(text ~= nil)
        if not text then return end
        fs:SetText(text)
        clear(fs)
        pt(fs, "LEFT", f.rew, "LEFT", rx, 0)
        rx = rx + (num(fs:GetStringWidth()) or 40) + (gap or 8)
      end
      place(f.rew.xp, r.xp and T("xp", thousands(r.xp)) or nil)
      f.rew.coin:SetShown(r.money ~= nil)
      if r.money then
        clear(f.rew.coin)
        pt(f.rew.coin, "LEFT", f.rew, "LEFT", rx, 0)
        rx = rx + 11
      end
      place(f.rew.gold, r.money and money(r.money) or nil)
      if r.item then
        local qc = QTR.QUALITY[r.item.quality or 1] or QTR.C.white
        setColor(f.rew.item, qc)
        width(f.rew.item, max(30, w - rx))
        place(f.rew.item, "[" .. r.item.name .. "]")
      else
        f.rew.item:Hide()
      end
      clear(f.rew)
      pt(f.rew, "TOPLEFT", f, "TOPLEFT", x, -(y + 3))
      f.rew:Show()
      y = y + 3 + 14
    end
  end
  if rec.complete then
    local t = acquire("turnin", newTurnin, f)
    pt(t, "TOPLEFT", f, "TOPLEFT", x, -(y + 4))
    t.text:SetText(turninText(rec))
    width(t.text, w - 14)
    t.isTurnin = true
    f.objs[#f.objs + 1] = t
    y = y + 4 + math.ceil(17 * QTR.lineK())
  end
  y = y + 9
  height(f, y)
  return y
end

local function newNote(parent)
  local f = CreateFrame("Frame", nil, parent)
  size(f, CW, 16)
  f.text = font(f, "text", 11, QTR.C.faint, "LEFT")
  pt(f.text, "TOPLEFT", f, "TOPLEFT", 0, 0)
  width(f.text, CW)
  if f.text.SetWordWrap then f.text:SetWordWrap(true) end
  return f
end

local function note(parent, y, text)
  local n = acquire("note", newNote, parent)
  pt(n, "TOPLEFT", parent, "TOPLEFT", 0, -y)
  n.text:SetText(text)
  local h = max(16, (num(n.text:GetStringHeight()) or 13) + 3)
  height(n, h)
  return h
end

-- ---------------------------------------------------------------- arrangement

local function groupName(g)
  if g.kind == "turnin" then return T.groupTurnin end
  if g.id == "all" then return T.groupDist end
  if g.id == "level" then return T.groupLevel end
  return g.name or T.zoneNone
end
QTR.groupName = groupName

local function groupCollapsed(g)
  if g.kind == "flat" then return st.flatFolded[g.id] == true end
  return g.collapsed == true
end

local function groupToggle(g)
  local Q = QT()
  if g.kind == "turnin" then return function() Q.toggleSection("turnin") end end
  if g.kind == "flat" then return function() st.flatFolded[g.id] = not st.flatFolded[g.id] QTR.request() end end
  local key = g.key
  return function() Q.toggleZone(key) end
end

local function todoEntries()
  local Tr = TT()
  if not (Tr and type(Tr.entries) == "function") then return {} end
  local ok, list = pcall(Tr.entries)
  if ok and type(list) == "table" then return list end
  return {}
end

-- structure signature: what needs a new layout (not counts or distances; those are updated in place)
local function signature(view, todos, s)
  local p = { tostring(st.settingsOpen), s.order, s.done, tostring(s.look.objs), tostring(s.look.dist), tostring(s.look.icons), tostring(s.filter.zoneOnly), tostring(QT().focus()),
    s.look.doneObj, s.panel.todo, tostring(s.collapsed.todo), tostring(s.focus.show), tostring(s.focus.dist), tostring(s.focus.bar),
    tostring(s.focus.giver), tostring(s.focus.rewards), tostring(view.ready), tostring(view.filtered), s.mode, tostring(speakOn()) }
  local f = view.focus
  if f then
    p[#p + 1] = "F" .. f.questID .. (f.complete and "c" or "") .. (f.starter and "s" or "")
    for _, o in ipairs(f.objectives or {}) do p[#p + 1] = o.done and "d" or "o" end
  end
  local Q = QT()
  for _, g in ipairs(view.groups) do
    p[#p + 1] = "G" .. g.id .. (groupCollapsed(g) and "-" or "+")
    if not groupCollapsed(g) then
      for _, r in ipairs(g.quests) do
        p[#p + 1] = r.questID .. (r.complete and "c" or "") .. (r.next and "n" or "")
          .. #(r.objectives or {})
        for _, o in ipairs(r.objectives or {}) do p[#p + 1] = o.done and "d" or "o" end
      end
    end
  end
  p[#p + 1] = "T" .. #todos
  if not s.collapsed.todo then
    -- (the text of a material line carries its count: a changed count lays out again)
    for _, r in ipairs(todos) do p[#p + 1] = tostring(r.id) .. (r.done and "d" or "") .. (r.sub and r.text or "") end
  end
  return table.concat(p, ",")
end

local function layoutTodo(content, y, todos, s)
  local Q = QT()
  local b = acquire("zone", newZone, content)
  pt(b, "TOPLEFT", content, "TOPLEFT", 0, -y)
  b.name:SetText(upper(T.todo))
  local open = 0
  for _, r in ipairs(todos) do if not r.done and not r.sub then open = open + 1 end end
  b.count:SetText(tostring(open))
  local collapsed = s.collapsed.todo == true
  QTR.paintChev(b, collapsed, "todo")
  QTR.zoneLine(b)
  b.toggle = function() Q.toggleSection("todo") end
  st.blocks[#st.blocks + 1] = b
  height(b, math.ceil(20 * QTR.lineK()))
  y = y + 8 + math.ceil(20 * QTR.lineK())
  if not collapsed then
    for _, r in ipairs(todos) do
      if r.sub then
        -- material line of a shopping list: drawn like a quest objective ("4/20 Kupfererz"), done ones as the objective setting says
        if not (r.done and s.look.doneObj == "hide") then
          local f = acquire("todoobj", newShopObj, content)
          pt(f, "TOPLEFT", content, "TOPLEFT", 0, -y)
          local o = r.more and { done = false, label = r.text } or { done = r.done, need = r.need, have = r.have, label = r.name or r.text }
          y = y + fillObj(f, o, 18, CW, false, nil) + 1
          f.planId = r.planId
          st.blocks[#st.blocks + 1] = f
        end
      else
        local row = acquire("todo", newTodo, content)
        pt(row, "TOPLEFT", content, "TOPLEFT", 0, -y)
        y = y + fillTodo(row, r) + 1
        st.blocks[#st.blocks + 1] = row
        st.todoRows[r.id] = row
      end
    end
  end
  return y + 4
end

-- chevron of a head: down = open, turned a quarter (pointing right, like the template) = folded; animated over 0.25 s from the
-- angle the same group had before (key), unless "Bewegung reduzieren"
QTR.CHEV_FOLDED = pi / 2
function QTR.paintChev(b, collapsed, key)
  if not (b and b.chev) then return end
  b.chev:Show()
  b.folded = collapsed == true
  local to = collapsed and QTR.CHEV_FOLDED or 0
  local from = key and st.chevAngle[key]
  if key then st.chevAngle[key] = to end
  if from == nil or from == to or reduceMotion() then
    b.chevAnim = nil
    b.chev.rotate(to)
  else
    b.chev.rotate(from)
    b.chevAnim = { from = from, to = to, t = now() }
  end
end

function QTR.zoneLine(b)
  width(b.name, 0) -- measure the full text, not an earlier cut-off
  local nw = (num(b.name:GetStringWidth()) or 60)
  local cw = (num(b.count:GetStringWidth()) or 8)
  width(b.name, min(nw + 2, CW - 40))
  clear(b.line)
  pt(b.line, "LEFT", b, "LEFT", min(nw + 2, CW - 40) + 6, 0)
  pt(b.line, "RIGHT", b, "RIGHT", -(8 + 6 + cw + 6), 0)
end

local function layout(view, todos, s)
  local fr = ensureFrames()
  local content = fr.panel.content
  releasePools()
  st.blocks, st.rows, st.todoRows = {}, {}, {}
  local y = 0
  -- inline settings (D3/D4)
  if st.settingsOpen then
    local block = acquire("settings", newBlock, content)
    pt(block, "TOPLEFT", content, "TOPLEFT", 0, -(y + 8))
    y = y + 8 + layoutSettings(block)
    st.blocks[#st.blocks + 1] = block
    block.stagger = 0
  end
  -- to-do on top (D8)
  local hasTodo = #todos > 0
  if hasTodo and s.panel.todo ~= "bottom" then y = layoutTodo(content, y, todos, s) end
  -- focus card (D5)
  if s.focus.show then
    if view.focus then
      local f = acquire("focus", newFocus, content)
      pt(f, "TOPLEFT", content, "TOPLEFT", 0, -(y + 8))
      y = y + 8 + fillFocus(f, view.focus, s, view)
      f.stagger = 1
      st.blocks[#st.blocks + 1] = f
      st.focusFrame = f
    else
      st.focusFrame = nil
      local h = note(content, y + 8, T.noFocus)
      y = y + 8 + h
    end
  else
    st.focusFrame = nil
  end
  -- groups
  local Q = QT()
  if not view.ready then
    y = y + 8 + note(content, y + 8, T.reading)
  else
    local shown = 0
    for gi, g in ipairs(view.groups) do
      local head = acquire("zone", newZone, content)
      pt(head, "TOPLEFT", content, "TOPLEFT", 0, -(y + 8))
      head.name:SetText(upper(groupName(g)))
      head.count:SetText(tostring(g.count or #g.quests))
      local collapsed = groupCollapsed(g)
      QTR.paintChev(head, collapsed, "g:" .. tostring(g.id))
      QTR.zoneLine(head)
      head.toggle = groupToggle(g)
      head.stagger = min(gi + 1, 4)
      st.blocks[#st.blocks + 1] = head
      height(head, math.ceil(20 * QTR.lineK()))
      y = y + 8 + math.ceil(20 * QTR.lineK())
      if not collapsed then
        for _, rec in ipairs(g.quests) do
          local q = acquire("quest", newQuest, content)
          local gap = s.look.dist and QTR.BOX.gap or 2 -- boxed list: more air between the quests
          pt(q, "TOPLEFT", content, "TOPLEFT", 0, -(y + gap))
          y = y + gap + fillQuest(q, rec, s, view)
          q.stagger = min(gi + 1, 4)
          st.blocks[#st.blocks + 1] = q
          st.rows[rec.questID] = q
          shown = shown + 1
        end
      end
    end
    if #view.groups == 0 then
      if view.zoneOnly and (view.zoneHidden or 0) > 0 then
        y = y + 8 + note(content, y + 8, T.noZoneQuests)
      elseif (view.filtered or 0) > 0 then
        y = y + 8 + note(content, y + 8, T.filteredAll)
      elseif not view.focus then
        y = y + 8 + note(content, y + 8, T.empty[view.mode] or T.empty.tracked)
        y = y + 4 + note(content, y + 4, T.emptyHint)
      end
    end
  end
  if hasTodo and s.panel.todo == "bottom" then y = layoutTodo(content, y + 8, todos, s) end
  y = y + 4
  height(content, max(1, y))
  st.contentH = y
  st.laidOut = true
  QTR.sizePanel()
end

-- in place (also in combat): counts, distances, arrows, head counter
local function updateInPlace(view, s)
  for id, q in pairs(st.rows) do
    local rec = QT().record(id)
    if rec and q.rec then
      q.rec = rec
      if q.speak:IsShown() then q.speak:Bind(rec) end -- fresh record, and the voice packs may have loaded since the layout
      if q.dist:IsShown() then
        local d = dist(rec.dist)
        if d then q.dist.text:SetText(d) end
      end
      local objs = {}
      for _, o in ipairs(rec.objectives or {}) do
        if not (o.done and s.look.doneObj == "hide") then objs[#objs + 1] = o end
      end
      local k = 0
      for _, o in ipairs(q.objs) do
        if not o.isTurnin then
          k = k + 1
          local src = objs[k]
          if src and src.need and src.need > 1 then o.count:SetText(string.format("%d/%d", min(src.have or 0, src.need), src.need)) end
        end
      end
    end
  end
  local f = st.focusFrame
  if f and f.rec and view.focus and view.focus.questID == f.rec.questID then
    local rec = view.focus
    if f.speak:IsShown() then f.speak:Bind(rec) end
    local d = dist(rec.dist)
    if f.comp and f.comp:IsShown() then f.comp.dist:SetText(d or "–") end
    local shown = {}
    for _, o in ipairs(rec.objectives or {}) do
      if not (o.done and s.look.doneObj == "hide") then shown[#shown + 1] = o end
    end
    local k = 0
    for _, o in ipairs(f.objs) do
      if not o.isTurnin then
        k = k + 1
        local src = shown[k]
        if src and src.need and src.need > 1 then
          o.count:SetText(string.format("%d/%d", min(src.have or 0, src.need), src.need))
          if o.track:IsShown() then
            local w = o.track:GetWidth() or 0
            local pct = min(1, (src.have or 0) / src.need)
            width(o.bar, max(0.01, w * pct))
            o.bar:SetShown(pct > 0)
          end
        end
      end
    end
  end
  -- to-do extras (progress or distance of place goals; Plans.list measures it fresh on every read)
  for _, r in ipairs(st.todos or {}) do
    local row = st.todoRows and st.todoRows[r.id]
    if row and row:IsShown() then row.extra:SetText(r.extra or "") end
  end
end

-- arrows follow the facing (OnUpdate, throttled)
local function turnArrows()
  local Q = QT()
  for _, q in pairs(st.rows) do
    if q.rec and q.dist:IsShown() then
      local b = Q.bearing(q.rec)
      q.dist.arrow:SetShown(b ~= nil)
      if b then q.dist.arrow.turn(b) end
    end
  end
  local f = st.focusFrame
  if f and f.rec and f.comp:IsShown() then
    local b = Q.bearing(f.rec)
    f.comp.arrow:SetShown(b ~= nil)
    if b then f.comp.arrow.turn(b) end
  end
end

local function headCount(view)
  local fr = st.frames
  if not fr then return end
  local text = T("count", view.readyCount or 0, view.total or 0, view.maxQuests or 25)
  if (view.filtered or 0) > 0 then text = text .. T("filtered", view.filtered) end
  -- the counter must never reach the word "QUESTLOG" (large fonts): room = head width - word - gear - pin - gaps;
  -- too wide -> short form "total/max", and in the worst case it is cut at the room
  local hc = fr.panel.head
  local room = QTR.CW - (num(hc.eyebrow:GetStringWidth()) or 70) - 22 - 22 - 6 - 6 - 10
  width(hc.count, 0)
  hc.count:SetText(text)
  if (num(hc.count:GetStringWidth()) or 0) > room then -- 2nd form: without the ready part, 3rd: only total/max
    local short = tostring(view.total or 0) .. "/" .. tostring(view.maxQuests or 25)
    hc.count:SetText((view.filtered or 0) > 0 and (short .. T("filtered", view.filtered)) or short)
    if (num(hc.count:GetStringWidth()) or 0) > room then hc.count:SetText(short) end
  end
  width(hc.count, max(10, min(room, num(hc.count:GetStringWidth()) or room)))
  local h = fr.handle
  local n = view.readyCount or 0
  st.ready = n -- ready-to-turn-in quests only make the grip glow (no number)
  local cur, mx = view.total or 0, view.maxQuests or 25
  if mx < 1 then mx = 1 end
  local b = h.badge
  local pct = cur / mx
  local bg, ink = QTR.C.gold, QTR.C.dark
  if cur >= mx then bg, ink = QTR.C.full, QTR.C.fullText
  elseif pct >= QTR.BADGE_WARN then bg = QTR.C.warn end
  b.cur:SetText(tostring(cur))
  b.max:SetText(tostring(mx))
  setColor(b.cur, ink)
  setColor(b.max, ink)
  setColor(b.sep, ink, 0.55)
  if b.bg then b.bg.color(bg, 1) end
  -- size from the measured digits (follows the font size setting); never squeezed
  local tw = max(num(b.cur:GetStringWidth()) or 9, num(b.max:GetStringWidth()) or 9)
  local th = max(QTR.BADGE_FONT, math.ceil(num(b.cur:GetStringHeight()) or QTR.BADGE_FONT))
  local w, hgt = max(16, math.ceil(tw) + 6), th * 2 + 7
  local changed = b:GetWidth() ~= w or b:GetHeight() ~= hgt
  size(b, w, hgt)
  clear(b.cur)
  pt(b.cur, "TOP", b, "TOP", 0, -3)
  clear(b.max)
  pt(b.max, "BOTTOM", b, "BOTTOM", 0, 3)
  clear(b.sep)
  width(b.sep, w - 6)
  pt(b.sep, "CENTER", b, "CENTER", 0, 0)
  b:Show()
  if changed or not b.placed then b.placed = true h.stack() end
end

-- ---------------------------------------------------------------- progress hints (D9) and row effects (D12)

local function snapshot(view)
  local out = {}
  local Q = QT()
  for _, rec in ipairs(Q.records() or {}) do
    local haves = {}
    for i, o in ipairs(rec.objectives or {}) do haves[i] = o.have or (o.done and 1 or 0) end
    out[rec.questID] = { complete = rec.complete == true, haves = haves }
  end
  return out
end

local function detectProgress(view)
  local Q = QT()
  local snap = snapshot(view)
  local old = st.prog
  st.prog = snap
  if not old then return end
  local t = now()
  local s = settings()
  for _, rec in ipairs(Q.records() or {}) do
    local o, n = old[rec.questID], snap[rec.questID]
    if o and n then
      local becameReady = n.complete and not o.complete
      local hit
      for i, h in ipairs(n.haves) do
        if o.haves[i] and h > o.haves[i] then hit = i break end
      end
      if becameReady or hit then
        st.fx[rec.questID] = { t = t, obj = hit, ready = becameReady }
        if not st.open and st.p < 0.01 then
          st.ping = t
          if s.panel.notify then
            local obj = hit and rec.objectives[hit] or nil
            local text, pct
            if becameReady then
              text, pct = T.ready, 1
            elseif obj and obj.need then
              text = T("toastObj", obj.label or obj.text or "", min(obj.have or 0, obj.need), obj.need)
              pct = min(1, (obj.have or 0) / obj.need)
            else
              text, pct = obj and (obj.label or obj.text) or T.progress, 1
            end
            local from = 0
            if hit and obj and obj.need and obj.need > 0 then from = min(1, (o.haves[hit] or 0) / obj.need) end
            local counted = not becameReady and obj and obj.need
            st.toast = { t = t, title = rec.title or "", text = text, pct = pct or 1, from = min(from, pct or 1), done = becameReady == true, kind = rec.kind,
              label = counted and (obj.label or obj.text or "") or nil, have = counted and min(obj.have or 0, obj.need) or nil, need = counted and obj.need or nil }
            QTR.showToast()
          end
        end
      end
    end
  end
end

-- flash colour: warm white, greenish when the quest is ready to hand in
local function flashColor(tt) return tt.done and { 0.55, 1, 0.5 } or { 1, 0.93, 0.7 } end

-- everything the toast does besides sliding: additive flash (on 0.15 s, off 0.4 s), shine strip, filling bar. e = seconds since it appeared.
-- Reduced motion: only a short brightening, no strip, bar at its final length at once. At the end everything sits on whole pixels.
function QTR.toastFx(f, tt, e)
  local rm = reduceMotion()
  local A = QTR.ANIM
  local c = flashColor(tt)
  local fa = 0
  if rm then
    fa = e < A.flashOff and 0.3 * (1 - e / A.flashOff) or 0
  elseif e < A.flashOn then fa = 0.6 * e / A.flashOn
  elseif e < A.flashOn + A.flashOff then fa = 0.6 * (1 - (e - A.flashOn) / A.flashOff) end
  if f.flash then f.flash.color(c, max(0, fa)) end
  local sk = (e - A.shineAt) / A.shine
  local on = not rm and sk >= 0 and sk < 1
  if on then
    local x = -QTR.SHINE_W + (QTR.TOAST_W - 6 + QTR.SHINE_W) * ease(sk)
    local a = 0.38 * math.sin(math.pi * sk)
    f.shineL:ClearAllPoints()
    f.shineL:SetPoint("TOPLEFT", f.clip, "TOPLEFT", x, 0)
    f.shineL:SetPoint("BOTTOMLEFT", f.clip, "BOTTOMLEFT", x, 0)
    f.shineR:ClearAllPoints()
    f.shineR:SetPoint("TOPLEFT", f.shineL, "TOPRIGHT", 0, 0)
    f.shineR:SetPoint("BOTTOMLEFT", f.shineL, "BOTTOMRIGHT", 0, 0)
    gradient(f.shineL, "HORIZONTAL", { c[1], c[2], c[3], 0 }, { c[1], c[2], c[3], a })
    gradient(f.shineR, "HORIZONTAL", { c[1], c[2], c[3], a }, { c[1], c[2], c[3], 0 })
  end
  f.shineL:SetShown(on)
  f.shineR:SetShown(on)
  -- bar fills from the old to the new value, exactly the final width at the end
  local bk = rm and 1 or ease((e - A.barAt) / A.bar)
  local from, to = tt.from or 0, tt.pct or 1
  width(f.bar, max(0.01, (QTR.TOAST_W - 20) * (bk >= 1 and to or from + (to - from) * bk)))
  tt.fxDone = (rm and e >= A.flashOff) or (e >= A.flashOn + A.flashOff and sk >= 1 and bk >= 1)
end

-- /chronik quests hinweis [fertig]: fires the progress toast at the handle with sample data (first tracked quest, else "Testquest";
-- 3/10 -> 4/10, or the green "ready to hand in" variant). The toast only lives while the panel is in: an open (not pinned) panel is
-- slid in first and the toast follows as soon as it rests (st.testPending, checked in QTR.step); a pinned panel gets a hint only.
local function fireTest(spec)
  local Q = QT()
  local rec = Q and Q.records and (Q.records() or {})[1] or nil
  local obj = rec and rec.objectives and rec.objectives[1] or nil
  local label = obj and (obj.label or obj.text) or T.testObj
  local text, pct, from = T("toastObj", label, 4, 10), 0.4, 0.3
  if spec.done then text, pct, from = T.ready, 1, 0.9 end
  st.ping = now()
  st.toast = { t = now(), title = rec and rec.title or T.testTitle, text = text, pct = pct, from = from, done = spec.done == true,
    kind = rec and rec.kind or "explore", label = not spec.done and label or nil, have = not spec.done and 4 or nil, need = not spec.done and 10 or nil }
  QTR.showToast()
end

function QTR.testToast(done)
  if not QTR.active() then
    say(T.testOff)
    return false
  end
  if not st.frames then
    say(T.testNoFrames)
    return false
  end
  local spec = { done = done == true, at = now() }
  if st.open or st.p >= 0.01 then
    local isPinned = st.pinned
    if isPinned == nil then isPinned = settings().panel.pinned == true end -- pinned() is declared further down
    if isPinned then
      say(T.testPinned)
      return false
    end
    QTR.setOpen(false)
    if st.open then
      say(T.combat)
      return false
    end
    st.testPending = spec
    return true
  end
  fireTest(spec)
  return true
end

-- The objective text of the toast: up to 2 lines, the counter ("7/10") is never cut off. Does the whole text not fit into 2 lines,
-- the NAME part is shortened with "…" (as many characters as fit), the counter stays. The toast grows by the extra text lines
-- (track and gaps hang on its bottom edge and move along).
function QTR.fitToast(f, tt)
  local fs = f.text
  width(fs, QTR.TOAST_W - 20)
  if fs.SetMaxLines then fs:SetMaxLines(0) end -- measure unlimited, the cut is made here
  fs:SetText("Xg")
  local line = max(1, num(fs:GetStringHeight()) or 14)
  local function lines(s)
    fs:SetText(s)
    return floor((num(fs:GetStringHeight()) or line) / line + 0.5)
  end
  local text = tt.text or ""
  if tt.need then
    local label = tt.label or ""
    local function build(sub) return T("toastObj", sub, tt.have or 0, tt.need) end
    text = build(label)
    if lines(text) > 2 then
      local chars = {}
      for ch in label:gmatch("[\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
      local function cut(n) return (table.concat(chars, "", 1, n):gsub("%s+$", "")) .. "…" end
      local lo, hi, best = 0, #chars - 1, 0
      while lo <= hi do
        local mid = floor((lo + hi) / 2)
        if lines(build(cut(mid))) <= 2 then best, lo = mid, mid + 1 else hi = mid - 1 end
      end
      text = build(cut(best))
    end
  end
  fs:SetText(text)
  if fs.SetMaxLines then fs:SetMaxLines(2) end
  local extra = max(0, math.ceil((num(fs:GetStringHeight()) or line) - line - 0.01))
  height(f, QTR.TOAST_H + extra)
end

function QTR.showToast()
  local fr = st.frames
  local tt = st.toast
  if not (fr and tt) then return end
  local f = fr.toast
  f.title:SetText(upper(tt.title))
  QTR.fitToast(f, tt)
  setColor(f.text, tt.done and QTR.C.toastDone or QTR.C.white)
  if f.edge then f.edge.color(tt.done and QTR.C.check or QTR.C.gold, tt.done and 0.7 or 0.5) end
  setColor(f.bar, tt.done and QTR.C.check or QTR.C.gold)
  QTR.toastFx(f, tt, 0)
  if f.icon then f.icon:Hide() end
  f.icons = f.icons or {}
  local k = tt.kind or "explore"
  if not f.icons[k] then
    f.icons[k] = icon(f, GLYPHS[k] and k or "explore", 11, QTR.C.gold, 1.6)
    pt(f.icons[k], "TOPLEFT", f, "TOPLEFT", 10, -7)
  end
  for kk, g in pairs(f.icons) do g:SetShown(kk == k) end
  f.icon = f.icons[k]
  clear(f)
  pt(f, "TOPRIGHT", fr.handle, "TOPLEFT", -10, -6)
  f:SetAlpha(0)
  f:Show()
end

-- ---------------------------------------------------------------- panel geometry

local function screen()
  local w = num(UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 1920
  local h = num(UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 1080
  if w <= 0 then w = 1920 end
  if h <= 0 then h = 1080 end
  return w, h
end

function QTR.sizePanel()
  local fr = st.frames
  if not fr then return end
  local s = settings()
  local k = s.panel.scale or 1
  local _, sh = screen()
  local h = max(120, sh / k) -- full screen height (the panel is scaled by k)
  height(fr.panel, h)
  st.viewH = h - QTR.PAD.top - 30 - QTR.PAD.bottom
  QTR.scrollBy(0)
end

function QTR.scrollBy(dy)
  local fr = st.frames
  if not fr then return end
  local maxS = max(0, (st.contentH or 0) - (st.viewH or 0))
  -- the content moves by whole pixels only (a fractional scroll would blur every text of the list)
  local cp = ppu(fr.panel.content)
  maxS = math.ceil(maxS * cp) / cp
  st.scroll = max(0, min(maxS, (st.scroll or 0) + (dy or 0)))
  st.scroll = min(maxS, floor(st.scroll * cp + 0.5) / cp)
  fr.panel.scroll:SetVerticalScroll(st.scroll)
  local th = fr.panel.thumb
  if maxS > 0 and (st.viewH or 0) > 0 then
    local vh = st.viewH
    local thumbH = max(20, vh * vh / st.contentH)
    height(th, thumbH)
    clear(th)
    pt(th, "TOPRIGHT", fr.panel.scroll, "TOPRIGHT", QTR.PAD.right - 6, -((vh - thumbH) * st.scroll / maxS))
    th:Show()
  else
    th:Hide()
  end
end

-- place handle and panel: the handle follows the edit-mode holder "quests" (right edge, height), else the right edge at mid height
function QTR.place()
  local fr = st.frames
  if not fr then return false end
  local s = settings()
  local k = s.panel.scale or 1 -- panel and toast
  local gs = s.panel.gripScale or 1 -- the grip (and its pill) has its own size, independent of the panel scale
  local h = fr.handle
  h:SetScale(gs)
  fr.toast:SetScale(k)
  fr.panel:SetScale(k)
  local placed = false
  local hud = QTR.hud
  local sh = SNAP[h]
  if sh then sh.pts = {} end -- the edit-mode holder places the grip itself; only our own fallback point is remembered
  if hud and type(hud.place) == "function" then
    local ok, r = pcall(hud.place, h)
    placed = ok and r == true
  end
  if not placed then
    clear(h)
    pt(h, "RIGHT", UIParent, "RIGHT", 0, 40 / gs)
  end
  -- scale, UI scale or resolution changed: round every point, size and font height again for the new pixel size
  local ues = num(UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
  local key = table.concat({ ues, k, gs, pixelFactor() }, "|")
  if st.snapKey ~= key then
    st.snapKey = key
    QTR.resnap()
  end
  QTR.slide()
  return true
end

-- Blizzard's edit mode (or our own EditMode bridge) is on: the panel must not slide out, so the grip can be moved
local function editing()
  local EM = Journal and Journal.EditMode
  if EM and type(EM.isEditing) == "function" and EM.isEditing() == true then return true end
  local M = rawget(_G, "EditModeManagerFrame")
  if type(M) == "table" and type(M.IsShown) == "function" then
    local ok, v = pcall(M.IsShown, M)
    return ok and v == true
  end
  return false
end
QTR.editing = editing

-- slide position of the panel and the handle (st.p: 0 = in, 1 = out)
function QTR.slide()
  local fr = st.frames
  if not fr then return end
  local e = ease(st.p)
  local p = fr.panel
  local ft = settings().panel.fadeTime
  if ft == nil then ft = QTR.ANIM.fade end
  clear(p)
  pt(p, "TOPRIGHT", UIParent, "TOPRIGHT", QTR.W * 1.05 * (1 - e), 0)
  p:SetAlpha(ft <= 0 and 1 or min(1, st.p / (ft / QTR.ANIM.slide)))
  if st.p <= 0.001 then
    if p:IsShown() then p:Hide() end
  elseif not p:IsShown() then
    p:Show()
  end
  -- the handle fades out while the panel is open (and takes no clicks once it is fully out)
  local h = fr.handle
  local ed = editing()
  -- edit mode: full strength, easy to grab; otherwise the opacity of the whole grip follows the option (QTR.step)
  h:SetAlpha(ed and 1 or (1 - e) * (st.gripA or settings().panel.gripAlpha or 0.4))
  if h.EnableMouse then h:EnableMouse(st.p < 0.99 and not ed) end -- edit mode: the selection frame on top takes the mouse
end

-- ---------------------------------------------------------------- open / close / pin

local function pinned()
  if st.pinned == nil then st.pinned = settings().panel.pinned == true end
  return st.pinned
end

function QTR.isOpen() return st.open == true end

function QTR.setOpen(on)
  on = on == true
  if on == st.open then return end
  if inCombat() and st.frames then return end -- D11: frozen
  st.open = on
  if on then
    st.openedAt = now()
    st.toast = nil
    if st.frames then st.frames.toast:Hide() end
    QTR.request()
  end
  if reduceMotion() then
    st.p = on and 1 or 0
    QTR.slide()
  end
end

function QTR.togglePin()
  if inCombat() then
    say(T.combat)
    return false
  end
  st.pinned = not pinned()
  local Q = QT()
  Q.set("panel.pinned", st.pinned)
  if st.pinned then
    QTR.setOpen(true)
  else
    st.leaveAt = now() + (settings().panel.delay or 600) / 1000
  end
  local fr = st.frames
  if fr then fr.panel.head.pin.setOn(st.pinned) end
  return st.pinned
end

function QTR.toggleSettings()
  if inCombat() then
    say(T.combat)
    return false
  end
  st.settingsOpen = not st.settingsOpen
  st.gearT = now() -- the gear turns a quarter while the settings open (back when they close), QTR.step
  local fr = st.frames
  if fr then fr.panel.head.gear.setOn(st.settingsOpen) end
  QTR.request()
  return st.settingsOpen
end

-- clicks that change the layout wait for the end of combat (D11)
function QTR.whenFree(fn)
  if type(fn) ~= "function" then return end
  if inCombat() then
    st.queue[#st.queue + 1] = fn
    say(T.combat)
    return
  end
  safe(fn)
end

-- ---------------------------------------------------------------- clicks and menu

function QTR.rowClick(q, button)
  local rec = q and q.rec
  if not rec then return end
  local Q = QT()
  if button == "RightButton" then
    QTR.openMenu(q.title or q, rec)
    return
  end
  if Q.actions and Q.actions.showOnMap then safe(Q.actions.showOnMap, rec) end
end

local function menuEntry(root, text, enabled, fn, why)
  if type(root.CreateButton) ~= "function" then return nil end
  local ok, b = pcall(root.CreateButton, root, text, function() safe(fn) end)
  if not ok or type(b) ~= "table" then return nil end
  if not enabled and type(b.SetEnabled) == "function" then pcall(b.SetEnabled, b, false) end
  if why and type(b.SetTooltip) == "function" then
    pcall(b.SetTooltip, b, function(tip)
      local setT, addL = rawget(_G, "GameTooltip_SetTitle"), rawget(_G, "GameTooltip_AddNormalLine")
      if type(setT) == "function" then pcall(setT, tip, text) end
      if type(addL) == "function" then pcall(addL, tip, why) end
    end)
  end
  return b
end

-- the menu builds its own labels; the only foreign text is the record title, which QuestTrack made display-safe (Sanitize.display)
function QTR.menuEntries(rec)
  local Q = QT()
  local A = Q.actions
  local M = T.menu
  local s = A.state(rec)
  local out = {}
  local function add(key, text, enabled, fn, why) out[#out + 1] = { key = key, text = text, enabled = enabled == true, fn = fn, why = why } end
  add("map", M.map, s.canMap, function() A.showOnMap(rec) end, not s.canMap and A.message(s.combat and "combatMap" or "noMap") or nil)
  local whyDetails = (s.controller and A.message("controller")) or (s.combat and A.message("combatLog")) or (not s.inLog and A.message("noQuest")) or nil
  add("details", M.details, s.canDetails, function() A.details(rec) end, not s.canDetails and whyDetails or nil)
  local whyShare
  if not s.canShare then
    whyShare = not s.inLog and A.message("noQuest")
      or ((type(IsInGroup) == "function" and not IsInGroup()) and A.message("noGroup") or A.message("notPushable"))
  end
  add("share", M.share, s.canShare, function() A.share(rec) end, whyShare)
  add("watch", s.watched and M.unwatch or M.watch, s.canWatch, function() A.toggleWatch(rec) end,
    not s.canWatch and (not s.inLog and A.message("noQuest") or A.message("limit")) or nil)
  local focused = Q.focus() == rec.questID
  add("focus", focused and M.unfocus or M.focus, true, function() QTR.whenFree(function() Q.toggleFocus(rec.questID) end) end)
  add("hide", M.hide, true, function() QTR.whenFree(function() A.hide(rec) end) end)
  add("abandon", M.abandon, s.canAbandon, function() A.abandon(rec) end, not s.canAbandon and A.message("cannotAbandon") or nil)
  return out
end

function QTR.openMenu(owner, rec)
  local MU = rawget(_G, "MenuUtil")
  if not (type(MU) == "table" and type(MU.CreateContextMenu) == "function" and type(rec) == "table") then return false end
  local entries = QTR.menuEntries(rec)
  local title = ns.Sanitize and ns.Sanitize.cut and ns.Sanitize.cut(rec.title or T.menu.title, 48) or (rec.title or T.menu.title)
  local ok = pcall(MU.CreateContextMenu, owner, function(_, root)
    if type(root) ~= "table" then return end
    if type(root.CreateTitle) == "function" then pcall(root.CreateTitle, root, title) end
    for i, e in ipairs(entries) do
      if e.key == "abandon" and type(root.CreateDivider) == "function" then pcall(root.CreateDivider, root) end
      menuEntry(root, e.text, e.enabled, e.fn, e.why)
    end
  end)
  return ok
end

-- ---------------------------------------------------------------- render

function QTR.request()
  -- tracker off and nothing on screen: nothing to draw or tear down (no timer at all; the baseline stays untouched)
  if not st.active and not QTR.active() then return end
  if st.renderQueued then return end
  st.renderQueued = true
  local ok = type(C_Timer) == "table" and type(C_Timer.After) == "function" and pcall(C_Timer.After, 0, function() safe(QTR.render) end)
  if not ok then safe(QTR.render) end
end

function QTR.teardown()
  st.active = false
  local Q = QT()
  if Q and Q.setActive then Q.setActive(false) end
  local fr = st.frames
  if fr then
    fr.panel:Hide()
    fr.handle:Hide()
    fr.toast:Hide()
    fr.driver:Hide()
  end
  local B = Bar()
  if B then safe(B.refresh) end
end

function QTR.render()
  st.renderQueued = false
  if not QTR.active() then return QTR.teardown() end
  local fr = ensureFrames()
  if not st.active then
    st.active = true
    fr.handle:Show()
    fr.driver:Show()
    QTR.place()
    local Q = QT()
    if Q.setActive then Q.setActive(true) end
    fr.panel.head.pin.setOn(pinned())
    if pinned() then st.open, st.p = true, 1 QTR.slide() end
  end
  local s = settings()
  if st.scale ~= s.panel.scale or st.gripScale ~= s.panel.gripScale then
    st.scale = s.panel.scale
    st.gripScale = s.panel.gripScale
    QTR.place()
    QTR.sizePanel()
  end
  do -- font size / files changed: apply to all texts and lay out again (title widths!)
    local fk = table.concat({ fontSettings() }, "|")
    if st.fontKey ~= fk then
      local first = st.fontKey == nil
      st.fontKey = fk
      if not first then QTR.applyFonts() st.sig = nil end
    end
  end
  if fr.panel.lookKey ~= (s.panel.bgAlpha or 0.96) .. "|" .. (s.panel.fadeWidth or QTR.FADE) then QTR.applyLook(fr.panel, s) end
  local view = QT().build()
  st.view = view
  local todos = todoEntries()
  st.todos = todos
  detectProgress(view)
  headCount(view)
  local sig = signature(view, todos, s)
  if sig ~= st.sig then
    if inCombat() and st.laidOut then
      st.pending = true
      updateInPlace(view, s)
    else
      st.sig = sig
      st.pending = false
      layout(view, todos, s)
    end
  else
    updateInPlace(view, s)
  end
  local B = Bar()
  if B then safe(B.refresh) end
end

-- ---------------------------------------------------------------- per frame: hover, slide, effects

local function cursorAtEdge()
  local gx, gy = 0, 0
  if type(GetCursorPosition) == "function" then
    local ok, x, y = pcall(GetCursorPosition)
    if ok then gx, gy = num(x) or 0, num(y) or 0 end
  end
  local es = num(UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
  if es <= 0 then es = 1 end
  local x, y = gx / es, gy / es
  local sw, sh = screen()
  return x >= sw - QTR.EDGE and x <= sw + 1 and y <= sh - QTR.INSET.top + 40 and y >= QTR.INSET.bottom
end

local function over(f)
  if not (f and f.IsShown and f:IsShown() and f.IsMouseOver) then return false end
  local ok, v = pcall(f.IsMouseOver, f)
  return ok and v == true
end

-- Windows that must keep the panel in: while one of these is open AND covers the place where the panel (or its hover edge strip / grip)
-- would be, the panel does not slide out by hover, and it slides in if it was out (playtest: no accidental opening while clicking in the
-- bags). Only reads (IsShown/GetRect), nothing is hooked on Blizzard frames. A window elsewhere (e.g. on the left) does not matter.
-- The world map is left out on purpose (the tracker is meant to be used next to it).
QTR.BLOCKERS = { "ContainerFrameCombinedBags", "BankFrame", "AccountBankPanel", "GuildBankFrame", "MailFrame", "MerchantFrame", "TradeFrame",
  "AuctionHouseFrame", "CharacterFrame", "PlayerSpellsFrame", "SpellBookFrame", "ProfessionsFrame", "CollectionsJournal", "PVEFrame" }
QTR.BAG_FRAMES = 13 -- ContainerFrame1 .. ContainerFrame13 (single bags when "combine bags" is off)

-- rectangle of a frame in UIParent units: l, b, r, t (nil when it has no size yet)
local function rectOf(f)
  if not (f and type(f.GetRect) == "function") then return nil end
  local ok, l, b, w, h = pcall(f.GetRect, f)
  l, b, w, h = num(l), num(b), num(w), num(h)
  if not (ok and l and b and w and h) then return nil end
  local k = 1
  if type(f.GetEffectiveScale) == "function" and UIParent and type(UIParent.GetEffectiveScale) == "function" then
    local ok2, fe = pcall(f.GetEffectiveScale, f)
    local ok3, ue = pcall(UIParent.GetEffectiveScale, UIParent)
    fe, ue = ok2 and num(fe) or nil, ok3 and num(ue) or nil
    if fe and ue and fe > 0 and ue > 0 then k = fe / ue end
  end
  return l * k, b * k, (l + w) * k, (b + h) * k
end

local function overlaps(al, ab, ar, at, bl, bb, br, bt)
  return al < br and ar > bl and ab < bt and at > bb
end

local function shownFrame(name)
  local f = rawget(_G, name)
  if type(f) ~= "table" or type(f.IsShown) ~= "function" then return nil end
  local ok, v = pcall(f.IsShown, f)
  if ok and v == true then return f end
  return nil
end

-- the name of an open window that covers the panel's place (panel when out, hover strip at the edge, grip), else nil
function QTR.blockingWindow()
  local zones
  local names = {}
  for i = 1, QTR.BAG_FRAMES do names[#names + 1] = "ContainerFrame" .. i end
  for _, n in ipairs(QTR.BLOCKERS) do names[#names + 1] = n end
  for _, name in ipairs(names) do
    local f = shownFrame(name)
    if f then
      local l, b, r, t = rectOf(f)
      if l then
        if not zones then
          local fr = st.frames
          local sw, sh = screen()
          local k = num(settings().panel.scale) or 1
          local ph = fr and num(fr.panel and fr.panel.GetHeight and fr.panel:GetHeight()) or sh
          zones = {
            { sw - QTR.EDGE, QTR.INSET.bottom, sw, sh - QTR.INSET.top + 40 }, -- hover strip (cursorAtEdge)
            { sw - QTR.W * k, sh - ph * k, sw, sh }, -- the panel when it is out
          }
          local gl, gb, gr, gt = rectOf(fr and fr.handle)
          if gl then zones[#zones + 1] = { gl, gb, gr, gt } end
        end
        for _, z in ipairs(zones) do
          if overlaps(l, b, r, t, z[1], z[2], z[3], z[4]) then return name end
        end
      end
    end
  end
  return nil
end

local function hoverStep(t)
  local fr = st.frames
  local s = settings()
  if editing() then
    -- edit mode: stay in (even when pinned), nothing opens on hover
    st.leaveAt = nil
    if st.open then QTR.setOpen(false) end
    return
  end
  if inCombat() then return end -- D11: no in/out in combat
  if pinned() then
    if not st.open then QTR.setOpen(true) end
    return
  end
  local inside = over(fr.handle) or (st.p > 0 and over(fr.panel)) or cursorAtEdge()
  -- a window on the right (bags, bank, ...) is open: no sliding out by hover, and slide in if it was out (a click on the grip = pin still works)
  if ((inside and s.panel.hover) or st.open) and QTR.blockingWindow() then
    st.leaveAt = nil
    if st.open then QTR.setOpen(false) end
    return
  end
  if inside and s.panel.hover then
    st.leaveAt = nil
    if not st.open then QTR.setOpen(true) end
  elseif st.open then
    if inside then
      st.leaveAt = nil
    else
      st.leaveAt = st.leaveAt or (t + (s.panel.delay or 600) / 1000)
      if t >= st.leaveAt then
        st.leaveAt = nil
        QTR.setOpen(false)
      end
    end
  end
end

local function pulse(t, period) return 0.5 - 0.5 * cos((t % period) / period * 2 * pi) end

function QTR.step(elapsed)
  local fr = st.frames
  if not (fr and st.active) then return end
  elapsed = num(elapsed) or 0
  local t = now()
  hoverStep(t)
  local rm = reduceMotion()
  -- slide
  local target = st.open and 1 or 0
  if st.p ~= target then
    if rm then
      st.p = target
    else
      local d = elapsed / QTR.ANIM.slide
      st.p = target > st.p and min(target, st.p + d) or max(target, st.p - d)
    end
    QTR.slide()
  end
  local ed = editing()
  if ed ~= st.wasEditing then -- entering/leaving the edit mode: mouse and strength of the grip follow
    st.wasEditing = ed
    QTR.slide()
  end
  -- handle: hover width, beckon (ready > 0), ping after progress
  local h = fr.handle
  local hv = st.handleHover == true
  width(h, hv and QTR.HANDLE.wHover or QTR.HANDLE.w) -- a little wider on hover
  local e = ease(st.p)
  local glow = 0
  if (st.ready or 0) > 0 and not rm then glow = 0.55 * pulse(t, QTR.ANIM.beckon) end
  if st.ping then
    local dt = t - st.ping
    if dt > QTR.ANIM.ping * 2 then
      st.ping = nil
    elseif not rm then
      local ph = (dt % QTR.ANIM.ping) / QTR.ANIM.ping
      local k = ph < 0.4 and ph / 0.4 or (1 - ph) / 0.6
      glow = max(glow, 0.7 * k)
    end
  end
  -- opacity of the whole grip (strip, pill, chevron): option "Griff-Deckkraft" at rest, softly to 100 % on hover, ping, ready to hand in and
  -- in the edit mode; the chevron shows on hover only
  local rest = settings().panel.gripAlpha or 0.4
  -- ready-to-hand-in quests do not lift the grip permanently (with turn-ins in the log the option would never apply); the
  -- ping on progress still shows it briefly
  local want = (ed or hv or st.ping) and 1 or rest
  local cur = st.gripA or want
  if rm then
    cur = want
  else
    local d = elapsed / QTR.ANIM.gripFade
    cur = want > cur and min(want, cur + d) or max(want, cur - d)
  end
  st.gripA = cur
  h:SetAlpha(ed and 1 or cur * (1 - e))
  if h.chev and st.chevOn ~= hv then
    st.chevOn = hv
    h.chev.color(QTR.C.gold, hv and 0.85 or 0)
  end
  setColor(h.glow, QTR.C.gold, glow * (1 - e))
  -- test toast waits until the panel has slid in (gives up after 4 s)
  local tp = st.testPending
  if tp then
    if t - tp.at > 4 then st.testPending = nil
    elseif not st.open and st.p < 0.01 then
      st.testPending = nil
      fireTest(tp)
    end
  end
  -- toast (D9): in 10 %, hold, out from 84 %
  local tt = st.toast
  if tt and fr.toast:IsShown() then
    local dt = (t - tt.t) / QTR.ANIM.toast
    if dt >= 1 or st.p > 0.01 then
      fr.toast:Hide()
      st.toast = nil
    else
      local a, x
      local e = t - tt.t
      local A = QTR.ANIM
      if rm then a, x = 1, 0
      elseif dt >= 0.84 then a, x = 1 - (dt - 0.84) / 0.16, 14 * (dt - 0.84) / 0.16
      elseif e < A.toastIn then
        -- slides in from the right with a slight overshoot (ease-out-back), then rests exactly on x = 0
        local k, c1 = e / A.toastIn, 1.7
        local back = 1 + (c1 + 1) * (k - 1) ^ 3 + c1 * (k - 1) ^ 2
        a, x = min(1, k / 0.35), 56 * (1 - back)
      else a, x = 1, 0 end
      if not tt.fxDone then QTR.toastFx(fr.toast, tt, e) end
      fr.toast:SetAlpha(max(0, min(1, a)))
      clear(fr.toast)
      pt(fr.toast, "TOPRIGHT", fr.handle, "TOPLEFT", -10 + x, -6)
    end
  end
  -- staggered fade-in after opening (D12)
  if st.openedAt and st.p > 0 then
    local dt = t - st.openedAt
    local all = true
    for _, b in ipairs(st.blocks) do
      local k = 1
      if not rm then
        local s0 = (b.stagger or 0) * QTR.ANIM.stagger
        k = ease((dt - s0) / QTR.ANIM.stagIn)
      end
      if k < 1 then all = false end
      b:SetAlpha(max(0, k))
    end
    if all then st.openedAt = nil end
  end
  -- row effects: counter bump/shine, tick pop, quest flash (D12)
  if next(st.fx) and not rm then
    for id, fx in pairs(st.fx) do
      local dt = t - fx.t
      local q = st.rows[id]
      if dt > QTR.ANIM.hold or not q then
        if q then
          setColor(q.flash, QTR.C.gold, 0)
          -- the tick pop ends exactly at scale 1 (on the pixel grid again)
          for _, o in ipairs(q.objs) do
            if o.check then
              o.check:SetScale(1)
              o.check:SetAlpha(1)
            end
          end
        end
        st.fx[id] = nil
      else
        if fx.ready then
          local k = dt / QTR.ANIM.qflash
          local a = k < 0.3 and (k / 0.3) or max(0, 1 - (k - 0.3) / 0.7)
          setColor(q.flash, QTR.C.gold, 0.18 * a)
        end
        if fx.obj then
          local n = 0
          for _, o in ipairs(q.objs) do
            if not o.isTurnin then
              n = n + 1
              if n == fx.obj then
                local k = min(1, dt / QTR.ANIM.bump)
                local b = k < 0.4 and k / 0.4 or (1 - k) / 0.6
                setColor(o.count, { 1, 1 - 0.05 * b, 1 - 0.23 * b, 1 })
                if o.done and o.check:IsShown() then
                  local kp = min(1, dt / QTR.ANIM.pop)
                  local sc = kp < 0.6 and (0.3 + 0.95 * kp / 0.6) or (1.25 - 0.25 * (kp - 0.6) / 0.4)
                  o.check:SetScale(max(0.3, sc))
                  o.check:SetAlpha(min(1, kp / 0.6))
                end
              end
            end
          end
        end
      end
    end
  elseif next(st.fx) then
    st.fx = {}
  end
  -- turn-in mark pulse (only while the panel is out)
  if st.p > 0 then
    local qa = rm and 1 or (1 - 0.4 * pulse(t, QTR.ANIM.qpulse))
    for _, o in ipairs(pools.turnin and pools.turnin.used or {}) do o.q:SetAlpha(qa) end
    -- gear: a quarter turn (clockwise, like the template) over QTR.ANIM.gear
    local gear = fr.panel.head.gear.glyph
    local want = st.settingsOpen and -pi / 2 or 0
    if st.gearT and not rm then
      local k = ease((t - st.gearT) / QTR.ANIM.gear)
      local from = st.settingsOpen and 0 or -pi / 2
      gear.rotate(from + (want - from) * k)
      if k >= 1 then st.gearT = nil end
    else
      st.gearT = nil
      gear.rotate(want)
    end
    -- zone chevrons
    for _, b in ipairs(st.blocks) do
      local a = b.chevAnim
      if a then
        local k = rm and 1 or ease((t - a.t) / QTR.ANIM.chev)
        b.chev.rotate(a.from + (a.to - a.from) * k)
        if k >= 1 then b.chevAnim = nil end
      end
    end
  end
  st.tickAcc = (st.tickAcc or 0) + elapsed
  if st.tickAcc >= QTR.TICK then
    st.tickAcc = 0
    if st.p > 0 then turnArrows() end
  end
end

-- ---------------------------------------------------------------- lifecycle

local function afterCombat()
  local q = st.queue
  st.queue = {}
  for _, fn in ipairs(q) do safe(fn) end
  if st.pending or #q > 0 then
    st.sig = nil
    QTR.request()
  end
end

-- options button "Lage zurücksetzen": grip height, size and item bar back to their defaults
function QTR.resetPlace()
  local Q = QT()
  Q.set("panel.scale", 1)
  Q.set("panel.gripScale", 1)
  Q.resetPlace()
  local EM = Journal.EditMode
  if EM and type(EM.set) == "function" then
    EM.set("quests", "pos", nil)
    EM.set("questbar", "pos", nil)
    EM.set("questbar", "scale", nil)
    if type(EM.apply) == "function" then
      EM.apply("quests")
      EM.apply("questbar")
    end
  end
  QTR.place()
  QTR.sizePanel()
  local B = Bar()
  if B and B.state.frame then B.place() end
  return true
end

function QTR.status()
  local fr = st.frames
  return { active = st.active, open = st.open, p = st.p, pinned = pinned(), pending = st.pending, queued = #st.queue,
    frames = fr ~= nil, panelShown = fr ~= nil and fr.panel:IsShown() == true, handleShown = fr ~= nil and fr.handle:IsShown() == true,
    settingsOpen = st.settingsOpen, rows = (function() local n = 0 for _ in pairs(st.rows) do n = n + 1 end return n end)(),
    toast = st.toast ~= nil }
end

function QTR.install()
  if st.installed then return true end
  local Q = QT()
  if not (Q and Q.available and Q.available()) then return false end
  st.installed = true
  Q.onChange(function() QTR.request() end)
  local H = QTH()
  if H and H.onChange then H.onChange(function() QTR.request() end) end
  local Tr = TT()
  if Tr and Tr.onPlansChanged then Tr.onPlansChanged(function() if QTR.active() then QTR.request() end end) end
  if ns.Core and ns.Core.on then
    ns.Core.on("PLAYER_ENTERING_WORLD", function() QTR.request() end)
    ns.Core.on("PLAYER_REGEN_ENABLED", function() safe(afterCombat) end)
    ns.Core.on("DISPLAY_SIZE_CHANGED", function() if st.frames then QTR.place() QTR.sizePanel() QTR.request() end end)
    ns.Core.on("UI_SCALE_CHANGED", function() if st.frames then QTR.place() QTR.sizePanel() QTR.request() end end)
  end
  return true
end

QTR.install()
