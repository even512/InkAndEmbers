-- Kampf page: one area dropdown switches the whole page. Left the bestiary (kill count with tally, stamps, most hunted
-- with a 3D model, last rare), right the hunting grounds (heat map or markers), the deaths with the death
-- report, and close calls.
-- Data from journal/model/Kampf.lua (display-ready texts). A click on a bestiary card opens the model lens (a larger
-- model frame that grows out of the card, closed by clicking beside it or Esc). No OnUpdate except while the lens
-- animates, drags or a card is hovered; model frames are created on the first draw outside combat.
local _, ns = ...

local Journal = ns.Journal
local Pages, Widgets, Kampf = Journal and Journal.Pages, Journal and Journal.Widgets, Journal and Journal.Kampf
if not (Pages and Widgets and Kampf) then return end
local D = Widgets.Diary -- diary toolkit: area dropdown and paging
if not D then return end

local Theme = Journal.Theme or {}
local floor, max, min = math.floor, math.max, math.min

local Page = { needs = { index = true } }
Journal.KampfPage = Page

local G = Theme.GRID
local SZ = G.size                       -- font steps xs 11 · s 12 · m 14 · l 18 · xl 28
local SL, SR = {}, {}                   -- text block left / right { x, w }
SL.x, SL.w = Theme.gridX("L")
SR.x, SR.w = Theme.gridX("R")
local SL_END = SL.x + SL.w
-- top left (right of the swords): control line without title (area), below it counter and tally
local TOP_X = Theme.gridX("L", 2) + 6   -- 6 px gap to the swords (the keep-out ends at column 2)
local ZONE_Y = G.slots.ctrlTop.y
local COUNT_Y = G.slots.bodyTop.y
local TOTAL_SIZE = 44                   -- big kill count (display number, deliberately larger than the font steps)
-- tally right of the big number: bundles (4 vertical + 1 across) in rows, TALLY_COLS bundles per row
local TALLY_X, TALLY_Y, TALLY_COLS, TALLY_W, TALLY_ROW = TOP_X + 150, COUNT_Y, 5, 42, 34
local STROKE_GAP, STROKE_H, STROKE_THICK = 8, 24, 5
-- stamps (below the swords across the full width)
local MODE_HALO_X, MODE_HALO_Y, MODE_HALO_ALPHA = 20, 9, 0.82 -- parchment label under "Hotspots | Genau" (edge beyond the switch)
local STAMP_Y, STAMP_SIZE = 212, 100  -- emblems (100 px per column), below the swords (keep-out ends at y 208)
-- bestiary: head line (most hunted, paging), cards from column 4 (right of the blots bottom left); square picture frame
-- for the 3D model.
-- Four compact cards per sheet (frame 42, rows 50 instead of 58)
local HUNT_Y = 330
local CARD_X, CARD_Y, CARD_H, CARDS = Theme.gridX("L", 4), 360, 50, 4
local CARD_W = SL_END - CARD_X
local PIC = 42
local TEXT_X = PIC + 10 -- name and line below start here in the card
local COUNT_W = 46      -- kill count right in the card
local RARE_X, RARE_Y = CARD_X, 516
-- hunting grounds: title, below it caption | note (both before the swords top right, TOP_W), then the map. Larger map
-- (to x 400, 192 high) with a softly fading edge
-- instead of a hard one; heat blobs stay in the box (clipped)
local TOP_W = 320
-- last breath is a detail of the deaths, the map gets the room. Width to x 404 (2 px before the sword hilt that reaches
-- into the text block from x 406 in y 168..208; wider only goes over it),
-- height matching the map art 1002 x 668: 360 x 240 instead of 330 x 220. The lower block moves down by 20 (LOW_Y).
local MAP_W = 360
local MAP_Y, MAP_H = 114, 240
local ZOOM_MAX, ZOOM_STEP, DOT_SIZE, DOT_HIT = 8, 1.25, 5, 6   -- map zoom, factor per wheel notch, kill point (px) and hit radius
local DOUBLE_CLICK, DRAG_MIN = 0.35, 4                          -- seconds between two clicks; from this many px it counts as dragging
local LENS_W, LENS_H, LENS_MARGIN, LENS_ANIM, LENS_MODEL_H = 340, 440, 24, 0.25, 330
local LENS_CAM_MIN, LENS_CAM_MAX = 0.35, 2.4
local CAP_Y = G.slots.title.y + 26
-- lower block: control line (switch left, paging right), below it graves (default), close calls OR the death report
-- detail (replaces the switch with "Zurück zu den Toden")
local LOW_Y = 366
local DEATH_Y, HIT_ROW = LOW_Y + 32, G.line.dense
local HIT_W = 304                  -- narrow hits: end before the skull bottom right
local SPAN_W = 286                 -- closing line of the death report (two lines): ends before the blood bottom right (x 334 from y 578)
local LOW_W = 300                  -- deaths / close calls: width of the list (ends before the skull)
local GRAVE_ROW, GRAVE_NAME_W, GRAVE_STEP, GRAVE_STONES = 16, 160, 13, 7
local STONE_W, STONE_H = 11, 13    -- gravestone (one button per stone, a click opens the death report of exactly this death)
-- model in the picture frame: slightly rotated, closer to the camera (larger in the frame)
local MODEL_ROTATION, MODEL_DISTANCE = -0.45, 0.95
-- area dropdown: width of the field, width and row count of the list
local ZONE_DD_W, ZONE_POP_W, ZONE_POP_ROWS = 230, 300, 9
-- model frame: square and subtle. Light, calm ground (no black) so models are easy to see; a fine rim (RIM px) in
-- bronze or gold outside,
-- a hair-thin dark line inside. The model sits MODEL_INSET px from the edge.
local RIM, MODEL_INSET = 2, 3
-- look per rarity (cards differ from each other): ground tone (light), edge colour. Boss like elite warm, "unknown" like common.
local LOOKS = {
  -- ground: medium warm parchment shadow (slightly darker so models stand out)
  normal = { ground = { 0.74, 0.66, 0.52, 1 }, edge = { 0.55, 0.42, 0.26, 1 } },
  elite = { ground = { 0.78, 0.66, 0.46, 1 }, edge = { 0.80, 0.64, 0.28, 1 } },
  rare = { ground = { 0.62, 0.67, 0.72, 1 }, edge = { 0.40, 0.55, 0.78, 1 } },
  boss = { ground = { 0.76, 0.59, 0.52, 1 }, edge = { 0.72, 0.28, 0.20, 1 } },
}
LOOKS.unknown = LOOKS.normal

-- locale scope "p.Kampf" (English in locales/enUS_pages.lua), read when drawing
Page.TEXT = ns.Locale.ns("p.Kampf", {
  pageOf = "Seite %s von %s", deathOf = "Tod %s von %s", moreZones = "+ %s weitere Zonen", closeCount = "%s knappe Siege · %s",
  brand = "INK & EMBERS", page = "BESTIARIUM", right = "KAMPF", hunted = "MEISTGEJAGT", rare = "SELTENER GEGNER",
  zoneLabel = "GEBIET",
  graves = "WO ICH GESTORBEN BIN", gravesTip = "Zonen, in denen Ihr gestorben seid – ein Grabstein je Tod",
  close = "UM HAARESBREITE", prevDeath = "Tod davor", openDeath = "Klicken: Todesbericht dieses Todes",
  openLastDeath = "Klicken: Todesbericht des letzten Todes hier", deathNo = "Tod %s",
  nextDeath = "Tod danach", prevCards = "Vorige Gegner", nextCards = "Weitere Gegner",
  hintHunted = "Erlegt einen Gegner, dann erscheint er hier.", hintHuntedZone = "Erlegt hier einen Gegner, dann erscheint er in dieser Liste.",
  hintGraves = "Jeder Tod bekommt hier einen Grabstein.", hintClose = "Gewinnt einen Kampf mit wenig Leben, dann steht er hier.",
  hintZone = "Erlegt einen Gegner, dann zeichnen sich Eure Jagdgründe ab.",
  zoneEmpty = "Noch keine Zone mit Kills.", krit = "krit", unknownPic = "?", here = "hier",
  lowGraves = "Tode", lowClose = "Haaresbreite", backToGraves = "Zurück zu den Toden",
  noDeathTitle = "Der letzte Atemzug",
  modeHot = "Hotspots", modePoints = "Genau",
  modeHotTip = "Hotspots: ein Fleck je Rasterzelle, größer und dunkler bei mehr Kills",
  modePointsTip = "Genau: jeder Punkt ein erlegter Gegner (Stichprobe der letzten Kills)",
  mapHint = "Mausrad: zoomen · Ziehen: verschieben · Doppelklick: zurücksetzen",
  hotspot = "Hotspot", killsWord = "%s · %s Kills", onePoint = "Kill-Punkt", pointsHere = "%s Kills hier",
  sample = "Stichprobe: die letzten %s von %s Kills dieser Zone",
  openLens = "Klicken: Modell groß ansehen", lensHint = "Ziehen: drehen · Mausrad: Zoom · Esc oder Klick daneben: schließen",
  lowGravesTip = "Wo ich gestorben bin: Zonen mit einem Grabstein je Tod (Klick auf einen Grabstein: Todesbericht)",
  lowCloseTip = "Die knappsten Siege",
  huntedTip = "Gebiet wählen – die ganze Seite zeigt nur dieses Gebiet (beim Öffnen: Euer aktuelles Gebiet)",
})

local function font(parent, kind, size, color, justify)
  local fs = Widgets.font(parent, kind, size, color)
  if justify then fs:SetJustifyH(justify) end
  return fs
end

local function set(fs, text) Widgets.setText(fs, text) end

local function tex(parent, layer)
  return parent:CreateTexture(nil, layer or "ARTWORK")
end

local function rune(t, key)
  if Theme.TEX and Theme.TEX.markers and Theme.ATLAS and Theme.ATLAS[key] then
    t:SetTexture(Theme.TEX.markers)
    t:SetTexCoord(Theme.atlasCoords(Theme.ATLAS[key]))
  end
end

local function hover(frame, getLines)
  frame:EnableMouse(true)
  frame:SetScript("OnEnter", function(self)
    local ok, lines = Widgets.call(getLines, self)
    if ok and type(lines) == "table" then Widgets.tip(self, lines) end
  end)
  frame:SetScript("OnLeave", function(self) Widgets.hideTip(self) end)
end


-- handler errors become the page notice (Pages.fail), never a Lua error
local function guarded(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then Pages.fail("kampf", err) end
  end
end

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function mouseDown()
  if type(IsMouseButtonDown) ~= "function" then return true end
  local ok, v = pcall(IsMouseButtonDown, "LeftButton")
  return not ok or v == true
end

-- fixed irregularity per stroke (-1..1): same number -> same hand, no jitter on redraw
local function jitter(i, salt)
  local v = math.sin(i * 12.9898 + salt * 78.233) * 43758.5453
  return (v - floor(v)) * 2 - 1
end

-- the player's current map (uiMapID) only outside combat; secret values and unreadable ones give nil
function Page.currentMap()
  -- another character's book (read only): the zone the guest last entered (their zone records), never the client's map
  local guest = Pages.guest and Pages.guest()
  if guest then return Page.guestMap(guest) end
  if inCombat() or not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
  if not ok or isSecret(id) or type(id) ~= "number" or id ~= id or id <= 0 or id >= 2147483648 then return nil end
  return floor(id)
end

-- last zone (map type 3) a guest character entered, from the guest index; nil without a record
function Page.guestMap(guest)
  local data = Journal.KampfPage and Journal.KampfPage.data
  local index, Idx = data and data.index, Journal.Index
  if not (index and Idx and index.guid == guest.guid) then return nil end
  local list = Idx.list(index, "ZN")
  for i = #list, 1, -1 do
    local r = list[i]
    if Idx.str(r, "ZN", "mapType") == "3" then
      local id = Idx.num(r, "ZN", "mapID")
      if type(id) == "number" and id == id and id > 0 and id < 2147483648 then return floor(id) end
    end
  end
  return nil
end

-- 3D model of the enemy (PlayerModel:SetCreature(npcID)). The frame shows "?" until the client has loaded the model
-- (OnModelLoaded, or GetModelFileID at once);
-- if it never does (unknown/blocked ID, not in the cache) the "?" stays. At most one model frame per card, created only
-- when the page is visible and never in combat; no OnUpdate.

local function try(obj, method, ...)
  local fn = obj and obj[method]
  if type(fn) ~= "function" then return nil end
  local ok, r = pcall(fn, obj, ...)
  if ok then return r end
  return nil
end

-- camera of a model frame (portrait zoom off, distance, rotation). The client resets the effective camera on load (and
-- when fitting a new frame size) but remembers the last value set, so the same value again does nothing.
-- So force it: first a slightly different value, then the wanted one -- exactly what the mouse wheel does.
local function applyCamera(m, dist, rot)
  try(m, "SetPortraitZoom", 0.01)
  try(m, "SetPortraitZoom", 0)
  try(m, "SetCamDistanceScale", dist * 1.01)
  try(m, "SetCamDistanceScale", dist)
  try(m, "SetRotation", rot)
end

local function modelReady(m)
  local id = try(m, "GetModelFileID")
  return not isSecret(id) and type(id) == "number" and id > 0
end

-- idempotent and guarded against re-entry: m:Show() fires OnModelLoaded synchronously in the client, which calls
-- markLoaded again ("C stack overflow").
-- Show only if the model is not visible yet.
local function markLoaded(c)
  local m = c.model
  if not (m and m.want) or m.marking then return end
  if m.loaded and m:IsShown() then return end
  m.marking = true
  m.loaded = true
  c.unknown:Hide()
  if not m:IsShown() then pcall(m.Show, m) end
  m.marking = nil
end

-- show the model without provoking another OnModelLoaded when the frame is already visible
local function showModel(m)
  if not m:IsShown() then m:Show() end
end

local function ensureModel(self, c)
  if c.model then return c.model end
  if inCombat() or not (self.left and self.left:IsVisible()) then return nil end
  local ok, m = pcall(CreateFrame, "PlayerModel", nil, c.box)
  if not ok or type(m) ~= "table" or type(m.SetCreature) ~= "function" then return nil end
  m:SetPoint("TOPLEFT", c.box, "TOPLEFT", c.insetX, -c.insetY)
  m:SetPoint("BOTTOMRIGHT", c.box, "BOTTOMRIGHT", -c.insetX, c.insetY)
  if m.SetFrameLevel and c.box.GetFrameLevel then
    local lvl = c.box:GetFrameLevel()
    if type(lvl) == "number" then m:SetFrameLevel(lvl + 1) end
  end
  m:SetScript("OnModelLoaded", function(model)
    applyCamera(model, MODEL_DISTANCE, MODEL_ROTATION)
    markLoaded(c)
  end)
  m:Hide()
  c.model = m
  self.modelCount = (self.modelCount or 0) + 1
  return m
end

-- B17: SetCreature(npcID) of a creature that is not in the client's creature cache only starts the query -- the frame
-- stays empty and no OnModelLoaded follows, even once the answer is there. A second SetCreature a moment later loads it
-- (why the lens, opened by a click later, showed the model while the card kept its "?"). So a card that has not loaded
-- asks again a few times (C_Timer, rising gaps, no OnUpdate); only while the same request stands, the page is visible
-- and not in combat. At most CARDS frames, so never more than four requests per step.
local RETRY_DELAYS = { 0.4, 1, 2, 4, 8 }

local function retryModel(self, c, gen)
  if not (type(C_Timer) == "table" and type(C_Timer.After) == "function") then return end
  local m = c.model
  local step = (m.tries or 0) + 1
  local delay = RETRY_DELAYS[step]
  if not delay then return end
  m.tries = step
  pcall(C_Timer.After, delay, function()
    Widgets.call(function()
      local mm = c.model
      if not (mm and mm.gen == gen and mm.want and not mm.loaded) then return end
      if inCombat() or not (self.left and self.left:IsVisible()) or not c:IsShown() then
        mm.tries = nil -- the next drawing starts the retries anew
        return
      end
      local id = mm.want
      try(mm, "ClearModel")
      showModel(mm)
      try(mm, "SetCreature", id)
      applyCamera(mm, MODEL_DISTANCE, MODEL_ROTATION)
      if mm.gen ~= gen or mm.want ~= id then return end
      if not mm.loaded and modelReady(mm) then markLoaded(c) end
      if not mm.loaded then retryModel(self, c, gen) end
    end)
  end)
end

-- npcID nil (instance kill without ID) or no model frame possible -> "?"
local function drawModel(self, c, npcID)
  if isSecret(npcID) or type(npcID) ~= "number" or npcID <= 0 then npcID = nil end
  local m = npcID and ensureModel(self, c) or c.model
  if not npcID or not m or inCombat() then
    if m and not npcID then
      m.want, m.loaded = nil, false
      m:Hide()
    end
    if not (m and m.loaded and m.want == npcID) then c.unknown:Show() end
    return
  end
  if m.want == npcID then
    -- loaded: show; still on its way: do not request again ("?" stays until OnModelLoaded)
    c.unknown:SetShown(not m.loaded)
    showModel(m)
    if not m.loaded and not m.tries then retryModel(self, c, m.gen) end
    return
  end
  -- other model: clear first (no old model whose OnModelLoaded wrongly reports the new one as loaded), then load
  m.want, m.loaded, m.tries = npcID, false, nil
  m.gen = (m.gen or 0) + 1
  local gen = m.gen
  c.unknown:Show()
  try(m, "ClearModel")
  showModel(m)
  try(m, "SetCreature", npcID)
  applyCamera(m, MODEL_DISTANCE, MODEL_ROTATION)
  if m.want == npcID and not m.loaded and modelReady(m) then markLoaded(c) end
  if m.gen == gen and m.want == npcID and not m.loaded then retryModel(self, c, gen) end
end


local function reduceMotion()
  local V = Journal.View
  return V and type(V.peek) == "function" and V.peek("reduceMotion") == true
end

local function effScale(f)
  local s = f and f.GetEffectiveScale and f:GetEffectiveScale()
  return (type(s) == "number" and s > 0) and s or 1
end

-- centre of a frame in UIParent units (bottom left); nil if the client gives none
local function centerOf(f)
  if not (f and f.GetCenter) then return nil end
  local x, y = f:GetCenter()
  if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y then return nil end
  local k = effScale(f) / effScale(UIParent)
  return x * k, y * k
end

local function clampTo(v, lo, hi)
  if lo > hi then return (lo + hi) / 2 end
  return max(lo, min(hi, v))
end

-- target (centre of the book, kept on the visible screen: margin LENS_MARGIN, scaled smaller on a small screen) and
-- start (centre and size of the clicked card)
function Page.LensGeometry(self, card)
  local UW, UH = UIParent:GetWidth(), UIParent:GetHeight()
  if type(UW) ~= "number" or UW <= 0 then UW = 1920 end
  if type(UH) ~= "number" or UH <= 0 then UH = 1080 end
  local jf = Journal.Frame and Journal.Frame.state and Journal.Frame.state.frame
  local sc = min(effScale(jf) / effScale(UIParent), (UW - 2 * LENS_MARGIN) / LENS_W, (UH - 2 * LENS_MARGIN) / LENS_H)
  if not (sc > 0) then sc = 1 end
  local hw, hh = LENS_W * sc / 2, LENS_H * sc / 2
  local fx, fy = centerOf(jf)
  fx, fy = fx or UW / 2, fy or UH / 2
  local gx, gy = clampTo(fx, LENS_MARGIN + hw, UW - LENS_MARGIN - hw), clampTo(fy, LENS_MARGIN + hh, UH - LENS_MARGIN - hh)
  local sx, sy = centerOf(card)
  local s0 = max(0.05, PIC * effScale(card) / effScale(UIParent) / LENS_W)
  return { x = gx, y = gy, s = sc, x0 = sx or gx, y0 = sy or gy, s0 = s0 }
end

-- camera of the lens (effective only after loading AND at the final size): after OnModelLoaded, after the fade-in ends,
-- on size changes and additionally delayed
-- (next frame, 0.05 s) -- only while the same lens is open
local function lensCamera(L)
  local m = L.model
  if not (L.open and not L.closing and m and m.want) then return end
  applyCamera(m, L.cam or MODEL_DISTANCE, L.rot or MODEL_ROTATION)
end

local function lensCameraSoon(L)
  lensCamera(L)
  if not (type(C_Timer) == "table" and type(C_Timer.After) == "function") then return end
  local token = L.model.want
  local function later()
    if L.model.want == token then Widgets.call(lensCamera, L) end
  end
  pcall(C_Timer.After, 0, later)
  pcall(C_Timer.After, 0.05, later)
end

local function lensApply(L, g, t)
  t = max(0, min(1, t))
  local e = 1 - (1 - t) ^ 3
  local s = g.s0 + (g.s - g.s0) * e
  local x, y = g.x0 + (g.x - g.x0) * e, g.y0 + (g.y - g.y0) * e
  L.frame:SetScale(s)
  L.frame:ClearAllPoints()
  L.frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
  L.frame:SetAlpha(t)
  L.t = t
end

local function lensHide(L)
  L.frame:SetScript("OnUpdate", nil)
  L.open, L.closing = false, false
  L.frame:Hide()
  L.catcher:Hide()
  L.model.want = nil
  Widgets.hideTip(L.frame)
end

-- dir 1 = open (grows out of the card), -1 = close (back into the card); duration <= LENS_ANIM s, no OnUpdate outside it
local function lensRun(L, dir)
  local g = L.geo
  if reduceMotion() then
    if dir > 0 then
      lensApply(L, g, 1)
      lensCameraSoon(L)
    else
      lensHide(L)
    end
    return
  end
  L.frame:SetScript("OnUpdate", function(f, dt)
    local t = (L.t or 0) + dir * (tonumber(dt) or 0) / LENS_ANIM
    if dir > 0 and t >= 1 then
      f:SetScript("OnUpdate", nil)
      lensApply(L, g, 1)
      lensCameraSoon(L) -- the model grew with the frame: fit again at the final size
    elseif dir < 0 and t <= 0 then
      lensHide(L)
    else
      lensApply(L, g, t)
    end
  end)
end

local function lensDragTick(L)
  local d = L.drag
  if not d then return end
  if not mouseDown() then
    L.drag = nil
    L.model:SetScript("OnUpdate", nil)
    return
  end
  local cx = GetCursorPosition and GetCursorPosition()
  if type(cx) ~= "number" then return end
  L.rot = d.rot + (cx - d.x) * 0.012
  try(L.model, "SetRotation", L.rot)
end

local function ensureLens(self)
  if self.lens then return self.lens end
  if inCombat() or not UIParent then return nil end
  local L = {}
  local cat = CreateFrame("Button", nil, UIParent)
  cat:SetFrameStrata("FULLSCREEN_DIALOG")
  cat:SetAllPoints(UIParent)
  if cat.SetFrameLevel then cat:SetFrameLevel(5) end
  local dim = cat:CreateTexture(nil, "BACKGROUND")
  dim:SetAllPoints(cat)
  dim:SetColorTexture(0, 0, 0, 0.35)
  if cat.RegisterForClicks then cat:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  cat:SetScript("OnClick", guarded(function() Page.CloseLens(self) end))
  cat:Hide()
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  if f.SetFrameLevel then f:SetFrameLevel(20) end
  f:SetSize(LENS_W, LENS_H)
  f:EnableMouse(true) -- swallows clicks inside the frame (no closing)
  f:Hide()
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(f)
  bg:SetColorTexture(Widgets.color("parchment", 0.98))
  local edge = Widgets.NewOutline(f, LENS_W, LENS_H, "sepia", 0.9)
  edge:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  local ground = f:CreateTexture(nil, "BORDER")
  ground:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -12)
  ground:SetSize(LENS_W - 24, LENS_MODEL_H)
  ground:SetColorTexture(0.74, 0.66, 0.52, 1)
  local unknown = font(f, "title", 48, "sepia", "CENTER")
  unknown:SetPoint("CENTER", ground, "CENTER", 0, 0)
  set(unknown, Page.TEXT.unknownPic)
  local ok, m = pcall(CreateFrame, "PlayerModel", nil, f)
  if not ok or type(m) ~= "table" or type(m.SetCreature) ~= "function" then
    cat:Hide()
    return nil
  end
  m:SetPoint("TOPLEFT", ground, "TOPLEFT", 0, 0)
  m:SetPoint("BOTTOMRIGHT", ground, "BOTTOMRIGHT", 0, 0)
  if m.SetFrameLevel then m:SetFrameLevel(22) end
  m:EnableMouse(true)
  if m.EnableMouseWheel then m:EnableMouseWheel(true) end
  m:SetScript("OnModelLoaded", function()
    unknown:Hide()
    lensCameraSoon(L) -- start size right on opening (not only after the wheel)
  end)
  m:SetScript("OnSizeChanged", function() Widgets.call(lensCamera, L) end)
  m:SetScript("OnMouseDown", guarded(function(model, button)
    if button ~= nil and button ~= "LeftButton" then return end
    local cx = GetCursorPosition and GetCursorPosition()
    if type(cx) ~= "number" then return end
    L.drag = { x = cx, rot = L.rot or MODEL_ROTATION }
    model:SetScript("OnUpdate", function() Widgets.call(lensDragTick, L) end)
  end))
  m:SetScript("OnMouseUp", function(model)
    L.drag = nil
    model:SetScript("OnUpdate", nil)
  end)
  m:SetScript("OnMouseWheel", guarded(function(_, delta)
    if type(delta) ~= "number" or delta ~= delta or delta == 0 then return end
    L.cam = clampTo((L.cam or MODEL_DISTANCE) / 1.12 ^ max(-3, min(3, delta)), LENS_CAM_MIN, LENS_CAM_MAX)
    try(L.model, "SetCamDistanceScale", L.cam)
  end))
  local rim = Widgets.NewOutline(f, LENS_W - 24, LENS_MODEL_H, "sepia", 0.7)
  rim:SetPoint("TOPLEFT", ground, "TOPLEFT", 0, 0)
  if rim.SetFrameLevel then rim:SetFrameLevel(24) end
  local name = font(f, "title", SZ.l, "ink", "CENTER")
  name:SetPoint("TOP", f, "TOPLEFT", LENS_W / 2, -(LENS_MODEL_H + 24))
  name:SetWidth(LENS_W - 24)
  name:SetWordWrap(false)
  local meta = font(f, "label", SZ.s, "sepia", "CENTER")
  meta:SetPoint("TOP", f, "TOPLEFT", LENS_W / 2, -(LENS_MODEL_H + 50))
  meta:SetWidth(LENS_W - 24)
  meta:SetWordWrap(false)
  local sub = font(f, "text", SZ.xs, "red", "CENTER")
  sub:SetPoint("TOP", f, "TOPLEFT", LENS_W / 2, -(LENS_MODEL_H + 68))
  sub:SetWidth(LENS_W - 24)
  sub:SetWordWrap(false)
  local hint = font(f, "label", SZ.xs, "sepia", "CENTER")
  hint:SetPoint("BOTTOM", f, "BOTTOMLEFT", LENS_W / 2, 10)
  hint:SetWidth(LENS_W - 24)
  hint:SetWordWrap(false)
  set(hint, Page.TEXT.lensHint)
  D.escKeys(f, function() Page.CloseLens(self) end) -- Esc closes (not in combat; otherwise Esc goes to the game)
  L.frame, L.catcher, L.model, L.unknown, L.name, L.meta, L.sub = f, cat, m, unknown, name, meta, sub
  -- closing the journal closes the lens at once
  local jf = Journal.Frame and Journal.Frame.state and Journal.Frame.state.frame
  if jf and jf.HookScript then jf:HookScript("OnHide", function() Page.CloseLens(self, true) end) end
  self.lens = L
  return L
end

-- open the lens: card (with card.item.id). A second click on the same card closes it again.
function Page.OpenLens(self, card)
  local item = card and card.item
  if not (item and type(item.id) == "number" and not isSecret(item.id) and item.id > 0) then return end
  if inCombat() then return end
  local L = ensureLens(self)
  if not L then return end
  if L.open and not L.closing and L.card == card then return Page.CloseLens(self) end
  L.card, L.item = card, item
  set(L.name, item.name)
  set(L.meta, item.meta)
  set(L.sub, type(item.tip) == "table" and item.tip[2] or "")
  local m = L.model
  L.rot, L.cam, L.drag = MODEL_ROTATION, MODEL_DISTANCE, nil
  m.want = item.id
  L.unknown:Show()
  try(m, "ClearModel")
  if not m:IsShown() then m:Show() end
  try(m, "SetCreature", item.id)
  applyCamera(m, L.cam, L.rot)
  if modelReady(m) then L.unknown:Hide() end
  L.geo = Page.LensGeometry(self, card)
  L.open, L.closing = true, false
  L.catcher:Show()
  if not L.frame:IsShown() then lensApply(L, L.geo, reduceMotion() and 1 or 0) end
  L.frame:Show()
  -- only now the model is visible: if loaded set the camera once more at once; otherwise OnModelLoaded sets it. The end
  -- of the fade-in sets it finally (lensRun)
  if modelReady(m) then lensCamera(L) end
  lensRun(L, 1)
end

-- close the lens (instant: at once, without animation); with animation it grows back into the card
function Page.CloseLens(self, instant)
  local L = self.lens
  if not (L and L.open) then return end
  if instant == true then return lensHide(L) end
  if L.closing then return end
  L.closing = true
  L.geo = Page.LensGeometry(self, L.card)
  lensRun(L, -1)
end

-- entries of the area dropdown list: "Alle Zonen" first, then the zones with kills; the current zone carries "· hier".
-- Form for D.NewDropdown: { text, value, count, active }
function Page.HuntedItems(self)
  local v = self.view
  if not v then return {} end
  local sel = v.hunted.zone
  local here = self.here
  local items = { { text = Kampf.TEXT.allZones, value = "all", count = v.allTotal or v.summary.total, active = sel == nil } }
  for _, z in ipairs(v.zones) do
    local label = z.name
    if z.mapID == here then label = label .. " · " .. Page.TEXT.here end
    items[#items + 1] = { text = label, value = z.mapID, count = z.n, active = z.mapID == sel }
  end
  return items
end

-- four strips (top, bottom, left, right) of a line of thickness thick, inset px from the edge of frame parent; colour later
function Page.edgeStrips(parent, inset, thick)
  local out = {}
  for k, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local t = tex(parent, "OVERLAY")
    if side == "TOP" or side == "BOTTOM" then
      local sy = side == "TOP" and -inset or inset
      t:SetPoint(side .. "LEFT", parent, side .. "LEFT", inset, sy)
      t:SetPoint(side .. "RIGHT", parent, side .. "RIGHT", -inset, sy)
      t:SetHeight(thick)
    else
      local sx = side == "LEFT" and inset or -inset
      t:SetPoint("TOP" .. side, parent, "TOP" .. side, sx, -inset)
      t:SetPoint("BOTTOM" .. side, parent, "BOTTOM" .. side, sx, inset)
      t:SetWidth(thick)
    end
    t:SetColorTexture(0, 0, 0, 1)
    out[k] = t
  end
  return out
end

local function buildLeft(self, left)
  local T = Page.TEXT
  local u = {}
  self.L = u
  Widgets.NewPageHead(left, { side = "L" }):SetTexts(T.brand, T.page)

  -- area dropdown at the very top: "GEBIET [Tirisfal v]"; the list (buildHuntedPicker) has "Alle Gebiete" and every zone
  local zl = font(left, "label", SZ.xs, "sepia", "LEFT")
  zl:SetPoint("TOPLEFT", left, "TOPLEFT", TOP_X, -(ZONE_Y + 5))
  set(zl, T.zoneLabel)
  local hz = D.NewDropdown(left, { width = ZONE_DD_W, text = Kampf.TEXT.allZones, keepText = true, rows = ZONE_POP_ROWS,
    popupWidth = ZONE_POP_W, tip = { T.huntedTip },
    onPick = guarded(function(it) Page.SelectHunted(self, it.value) end) })
  hz:SetPoint("LEFT", zl, "RIGHT", 6, 1)
  u.huntedButton, u.zoneLabel = hz, zl

  local label = font(left, "label", SZ.xs, "sepia", "LEFT")
  label:SetPoint("TOPLEFT", left, "TOPLEFT", TOP_X, -COUNT_Y)
  label:SetWidth(TALLY_X - TOP_X - 8)
  label:SetWordWrap(false)
  local total = font(left, "title", TOTAL_SIZE, "ink", "LEFT")
  total:SetPoint("TOPLEFT", left, "TOPLEFT", TOP_X, -(COUNT_Y + 16))
  u.label, u.total = label, total
  hover(total, function()
    local v = self.view
    if not v then return nil end
    local lines = {}
    for _, s in ipairs(v.summary.tip or {}) do lines[#lines + 1] = s end
    if v.tally.strokes > 0 then lines[#lines + 1] = v.tally.tip[1] end
    return lines
  end)

  -- tally: ink strokes as lines (Media/Stroke), 4 vertical per bundle, the fifth across
  local function inkLine()
    local l = left:CreateLine(nil, "ARTWORK")
    if Theme.TEX and Theme.TEX.stroke then
      l:SetTexture(Theme.TEX.stroke)
      l:SetVertexColor(Widgets.color("ink", 0.9))
    else
      l:SetColorTexture(Widgets.color("ink", 0.85))
    end
    l:SetThickness(STROKE_THICK)
    return l
  end
  local perBundle = 4
  u.strokes = Widgets.Pool(inkLine, nil, Kampf.TALLY_MAX * perBundle / 5)
  u.slashes = Widgets.Pool(inkLine, nil, Kampf.TALLY_MAX / 5)
  -- legend from the scale change on: one stroke and "= 10"
  local legendMark = inkLine()
  legendMark:SetThickness(4)
  legendMark:SetStartPoint("TOPLEFT", left, TOP_X + 4, -(COUNT_Y + 74))
  legendMark:SetEndPoint("TOPLEFT", left, TOP_X + 4, -(COUNT_Y + 90))
  local legend = font(left, "label", SZ.xs, "sepia", "LEFT")
  legend:SetPoint("TOPLEFT", left, "TOPLEFT", TOP_X + 12, -(COUNT_Y + 76))
  u.legend, u.legendMark = legend, legendMark

  -- stamps: ring (Media/RoundRing) with number and label
  u.stamps = {}
  local colW = SL.w / 4
  for i = 1, 4 do
    local f = CreateFrame("Frame", nil, left)
    f:SetSize(STAMP_SIZE, STAMP_SIZE)
    f:SetPoint("TOPLEFT", left, "TOPLEFT", SL.x + (i - 1) * colW + (colW - STAMP_SIZE) / 2, -STAMP_Y)
    local ring = tex(f, "ARTWORK")
    ring:SetAllPoints(f)
    local key = Kampf.STAMPS[i].key
    local emb = Theme.HAS_KILL_EMBLEMS and Theme.TEX and Theme.TEX.killEmblems and Theme.EMBLEMS and Theme.EMBLEMS[key] or nil
    local v, l
    if emb then
      -- emblem (bronze wolf, gold dragon, silver dragon, iron skull): the number sits centred in the empty band; dark
      -- ink on metal (light text on the iron) with a shadow; the kind is in the tooltip
      ring:SetTexture(Theme.TEX.killEmblems)
      ring:SetTexCoord(Theme.emblemCoords(key))
      v = font(f, "title", SZ.m, "ink", "CENTER")
      v:SetPoint("CENTER", f, "TOPLEFT", emb.band.u * STAMP_SIZE, -emb.band.v * STAMP_SIZE)
      v:SetWidth(emb.band.w * STAMP_SIZE)
      v:SetWordWrap(false)
      v:SetTextColor(emb.ink[1], emb.ink[2], emb.ink[3], 1)
      if v.SetShadowColor then v:SetShadowColor(emb.shade[1], emb.shade[2], emb.shade[3], emb.shade[4]) end
      if v.SetShadowOffset then v:SetShadowOffset(0.7, -0.7) end
      v.metalInk = true -- text on metal (not ink on parchment): own shadow, test journal-ink
      f.emblem = emb
    else
      if Theme.TEX and Theme.TEX.ring then ring:SetTexture(Theme.TEX.ring) end
      v = font(f, "title", SZ.l, "ink", "CENTER")
      v:SetPoint("CENTER", f, "CENTER", 0, 6)
      l = font(f, "label", SZ.xs, "ink", "CENTER")
      l:SetPoint("TOP", v, "BOTTOM", 0, -2)
    end
    f.ring, f.value, f.text = ring, v, l
    hover(f, function(fr) return fr.tip end)
    u.stamps[i] = f
  end
  local foot = font(left, "label", SZ.xs, "sepia", "LEFT")
  foot:SetPoint("TOPLEFT", left, "TOPLEFT", SL.x, -(STAMP_Y + STAMP_SIZE + 2))
  foot:SetWidth(SL.w)
  foot:SetWordWrap(false)
  u.stampFoot = foot

  -- bestiary head: left "MEISTGEJAGT" and the species count, right the paging ("Seite x von y" + arrow pair)
  local hh = font(left, "label", SZ.xs, "sepia", "LEFT")
  hh:SetPoint("TOPLEFT", left, "TOPLEFT", SL.x, -HUNT_Y)
  set(hh, T.hunted)
  local species = font(left, "label", SZ.xs, "sepia", "LEFT")
  species:SetPoint("LEFT", hh, "RIGHT", 10, 0)
  species:SetWidth(140)
  species:SetWordWrap(false)
  u.species = species
  u.cardNav = D.NewNavPair(left, { onPrev = guarded(function() Page.ShiftCards(self, -1) end),
    onNext = guarded(function() Page.ShiftCards(self, 1) end), tipPrev = { T.prevCards }, tipNext = { T.nextCards } })
  u.cardNav.frame:SetPoint("TOPRIGHT", left, "TOPLEFT", SL_END + 4, -(HUNT_Y - 7))
  u.cardPrev, u.cardNext = u.cardNav.prev, u.cardNav.next
  local cardPos = font(left, "label", SZ.s, "sepia", "RIGHT")
  cardPos:SetPoint("RIGHT", u.cardNav.frame, "LEFT", -6, 0)
  u.cardPos = cardPos
  Widgets.NewRule(left, SL.x, HUNT_Y + 22, SL.w)
  u.cards = {}
  for i = 1, CARDS do
    local c = CreateFrame("Frame", nil, left)
    c:SetSize(CARD_W, PIC)
    c:SetPoint("TOPLEFT", left, "TOPLEFT", CARD_X, -(CARD_Y + (i - 1) * CARD_H))
    -- picture frame: square, light ground, above it the 3D model (later, ensureModel), on top a fine rim (4 strips,
    -- colour by rarity) with a hair-thin dark inner line and the "?" for "no model"
    local box = CreateFrame("Frame", nil, c)
    box:SetSize(PIC, PIC)
    box:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
    local ground = tex(box, "BACKGROUND")
    ground:SetAllPoints(box)
    ground:SetColorTexture(0.74, 0.66, 0.52, 1)
    local fx = CreateFrame("Frame", nil, box)
    fx:SetAllPoints(box)
    if fx.SetFrameLevel and box.GetFrameLevel then
      local lvl = box:GetFrameLevel()
      if type(lvl) == "number" then fx:SetFrameLevel(lvl + 5) end
    end
    c.insetX, c.insetY = MODEL_INSET, MODEL_INSET
    local rim, line = Page.edgeStrips(fx, 0, RIM), Page.edgeStrips(fx, RIM, 1)
    local unknown = font(fx, "title", SZ.l, "sepia", "CENTER")
    unknown:SetPoint("CENTER", box, "CENTER", 0, 0)
    set(unknown, T.unknownPic)
    local name = font(c, "title", SZ.m, "ink", "LEFT")
    name:SetPoint("TOPLEFT", c, "TOPLEFT", TEXT_X, -5)
    name:SetWidth(CARD_W - TEXT_X - COUNT_W - 6)
    name:SetWordWrap(false)
    local meta = font(c, "label", SZ.xs, "sepia", "LEFT")
    meta:SetPoint("TOPLEFT", c, "TOPLEFT", TEXT_X, -24)
    meta:SetWidth(CARD_W - TEXT_X - COUNT_W - 6)
    meta:SetWordWrap(false)
    local count = font(c, "title", SZ.m, "red", "RIGHT")
    count:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, -13)
    count:SetWidth(COUNT_W)
    count:SetWordWrap(false)
    c.box, c.ground, c.rim, c.line, c.unknown, c.name, c.meta, c.count = box, ground, rim, line, unknown, name, meta, count
    hover(c, function(f)
      local tip = f.item and f.item.tip
      if type(tip) ~= "table" or type(f.item.id) ~= "number" then return tip end
      local lines = {}
      for _, l in ipairs(tip) do lines[#lines + 1] = l end
      lines[#lines + 1] = T.openLens
      return lines
    end)
    c:SetScript("OnMouseUp", guarded(function(f, button)
      if button == nil or button == "LeftButton" then Page.OpenLens(self, f) end
    end))
    u.cards[i] = c
  end
  local none = font(left, "text", SZ.s, "sepia", "LEFT")
  none:SetPoint("TOPLEFT", left, "TOPLEFT", CARD_X, -(CARD_Y + 8))
  u.cardsEmpty = none

  -- last rare enemy (right of the charred corner)
  local rare = CreateFrame("Frame", nil, left)
  rare:SetSize(SL_END - RARE_X, 58)
  rare:SetPoint("TOPLEFT", left, "TOPLEFT", RARE_X, -RARE_Y)
  local rl = font(rare, "label", SZ.xs, "red", "LEFT")
  rl:SetPoint("TOPLEFT", rare, "TOPLEFT", 0, 0)
  set(rl, T.rare)
  local rn = font(rare, "title", SZ.m, "ink", "LEFT")
  rn:SetPoint("TOPLEFT", rare, "TOPLEFT", 0, -14)
  rn:SetWidth(SL_END - RARE_X)
  rn:SetWordWrap(false)
  local rm = font(rare, "label", SZ.xs, "sepia", "LEFT")
  rm:SetPoint("TOPLEFT", rare, "TOPLEFT", 0, -34)
  rm:SetWidth(SL_END - RARE_X)
  rm:SetWordWrap(false)
  local rf = font(rare, "title", SZ.s, "red", "LEFT")
  rf:SetPoint("TOPLEFT", rare, "TOPLEFT", 0, -48)
  rf:SetWidth(SL_END - RARE_X)
  rf:SetWordWrap(false)
  rare.name, rare.meta, rare.fight = rn, rm, rf
  hover(rare, function() return self.view and self.view.rare and self.view.rare.tip end)
  u.rare = rare
end

-- look of a card by rarity (normal/elite/rare/boss): light ground and fine rim in the rarity colour, inside a hair-thin
-- dark line (depth). The 3D model stands straight.
function Page.applyLook(c, item)
  local look = LOOKS[item and item.stamp] or LOOKS.normal
  local g, e = look.ground, look.edge
  c.ground:SetColorTexture(g[1], g[2], g[3], g[4])
  for _, t in ipairs(c.rim) do t:SetColorTexture(e[1], e[2], e[3], e[4]) end
  for _, t in ipairs(c.line) do t:SetColorTexture(0.18, 0.12, 0.06, 0.35) end
  c.look = look
end

-- page the bestiary (CARDS per sheet)
function Page.ShiftCards(self, delta)
  if not self.view then return end
  local n = self.view.hunted.count
  local pages = max(1, math.ceil(n / CARDS))
  local p = (self.cardPage or 1) + (tonumber(delta) or 0)
  if p < 1 or p > pages then return end
  self.cardPage = p
  Page.DrawCards(self)
end

function Page.DrawCards(self)
  local u, hunted = self.L, self.view.hunted
  local pages = max(1, math.ceil(hunted.count / CARDS))
  local p = min(max(self.cardPage or 1, 1), pages)
  self.cardPage = p
  for i, c in ipairs(u.cards) do
    local item = hunted.item((p - 1) * CARDS + i)
    c.item = item
    if item then
      c:Show()
      Page.applyLook(c, item)
      drawModel(self, c, item.id)
      set(c.name, item.name)
      set(c.meta, item.meta)
      set(c.count, item.countText)
    else
      Widgets.hideTip(c)
      c:Hide()
    end
  end
  local empty = ""
  if hunted.count == 0 then empty = hunted.zone and (Kampf.TEXT.noHuntedZone .. " " .. Page.TEXT.hintHuntedZone)
      or (Kampf.TEXT.noHunted .. " " .. Page.TEXT.hintHunted) end
  set(u.cardsEmpty, empty)
  u.cardNav:SetEnabled(p > 1, p < pages)
  set(u.cardPos, pages > 1 and Page.TEXT("pageOf", Journal.Texts.int(p), Journal.Texts.int(pages)) or "")
end

-- one bundle: up to four vertical strokes and the cross stroke at five; position, slant and length slightly irregular
local function drawTally(self, tally)
  local u = self.L
  u.strokes:ReleaseAll()
  u.slashes:ReleaseAll()
  local left = self.left
  local idx = 0
  for i, n in ipairs(tally.bundles) do
    local col, row = (i - 1) % TALLY_COLS, floor((i - 1) / TALLY_COLS)
    local x, y = TALLY_X + col * TALLY_W, TALLY_Y + row * TALLY_ROW
    for k = 1, min(n, 4) do
      idx = idx + 1
      local s = u.strokes:Acquire()
      if not s then break end
      local sx = x + (k - 1) * STROKE_GAP + jitter(idx, 1) * 0.8
      local top, bottom = y + jitter(idx, 2) * 2, y + STROKE_H + jitter(idx, 3) * 2.5
      local lean = jitter(idx, 4) * 1.8
      s:SetStartPoint("TOPLEFT", left, sx + lean, -top)
      s:SetEndPoint("TOPLEFT", left, sx - lean * 0.5, -bottom)
      s:SetThickness(STROKE_THICK + jitter(idx, 5) * 0.6)
    end
    if n >= 5 then
      local l = u.slashes:Acquire()
      if l then
        local j1, j2 = jitter(i, 6) * 2, jitter(i, 7) * 2.5
        l:SetStartPoint("TOPLEFT", left, x - 5, -(y + STROKE_H - 5 + j1))
        l:SetEndPoint("TOPLEFT", left, x + 3 * STROKE_GAP + 6, -(y + 5 + j2))
        l:SetThickness(STROKE_THICK + 0.5 + jitter(i, 8) * 0.5)
      end
    end
  end
  local legend = tally.strokes > 0 and tally.legend or nil
  set(u.legend, legend)
  u.legendMark:SetShown(legend ~= nil)
end

-- font size of the number in the band of emblem emb: at most SZ.m; with more digits smaller so that the text
-- (characters about 0.62 of the font size wide) fits the free band width
-- (3-4 digits incl. thousands space), never below 9 px. Characters are counted, not bytes (the narrow space of
-- Texts.int is multi-byte UTF-8).
Page.EMBLEM_DIGIT_W = 0.62
function Page.EmblemFontSize(emb, text)
  local chars = (type(text) == "string" and text or ""):gsub("[\128-\191]", "")
  local n = math.max(1, #chars)
  local room = (emb and emb.band and emb.band.w or 0.44) * STAMP_SIZE
  return math.max(9, math.min(SZ.m, floor(room / (n * Page.EMBLEM_DIGIT_W))))
end

local function drawLeft(self, view)
  local u = self.L
  local s = view.summary
  set(u.label, s.label)
  set(u.total, s.totalText)
  drawTally(self, view.tally)
  for i, f in ipairs(u.stamps) do
    local st = view.stamps.list[i]
    f.tip = st.tip
    if f.emblem then
      -- without kills: the emblem pale and desaturated, the number muted
      local on = st.value > 0
      f.ring:SetVertexColor(1, 1, 1, on and 1 or 0.45)
      if f.ring.SetDesaturated then f.ring:SetDesaturated(not on) end
      local e = f.emblem
      f.value:SetTextColor(e.ink[1], e.ink[2], e.ink[3], on and 1 or 0.7)
      f.value:SetFont(Widgets.FONT.title, Page.EmblemFontSize(e, st.valueText), "")
      set(f.value, st.valueText)
    else
      f.ring:SetVertexColor(Widgets.color(st.color, st.value > 0 and 0.9 or 0.35))
      f.value:SetTextColor(Widgets.color(st.color))
      f.text:SetTextColor(Widgets.color(st.color))
      set(f.value, st.valueText)
      set(f.text, st.label)
    end
  end
  local notes = {}
  if view.stamps.footnote then notes[#notes + 1] = view.stamps.footnote end
  if view.stamps.groupNote then notes[#notes + 1] = view.stamps.groupNote end
  set(u.stampFoot, table.concat(notes, " · "))
  set(u.species, view.hunted.speciesText)
  u.huntedButton:SetText(view.hunted.zoneName or Kampf.TEXT.allZones)
  u.huntedButton:SetItems(Page.HuntedItems(self))
  Page.DrawCards(self)
  -- the paragraph "Seltener Gegner" bottom left stays off (looked out of place); rares still appear on the map
  u.rare:Hide()
end

local function buildMap(self, right)
  local u = self.R
  local box = CreateFrame("Frame", nil, right)
  box:SetPoint("TOPLEFT", right, "TOPLEFT", SR.x, -MAP_Y)
  box:SetSize(MAP_W, MAP_H)
  if box.SetClipsChildren then box:SetClipsChildren(true) end
  u.map = box
  Page.wireMap(self, box)
  local frame = Widgets.NewOutline(right, MAP_W, MAP_H, "sepia", 0.5)
  frame:SetPoint("TOPLEFT", right, "TOPLEFT", SR.x, -MAP_Y)
  u.mapFrame = frame
  -- soft edge: a mask (Media/MapFade, white with a soft, slightly irregular fading edge, like the journey map) lies
  -- exactly over the map art (drawHunt);
  -- tiles and heat blobs fade into the parchment with it. The fine frame stays only as a fallback without a mask API.
  if type(box.CreateMaskTexture) == "function" and Theme.TEX and Theme.TEX.mapFade then
    local ok, mk = pcall(box.CreateMaskTexture, box)
    if ok and mk then
      mk:SetTexture(Theme.TEX.mapFade, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      mk:SetAllPoints(box)
      u.mapMask = mk
    end
  end
  frame:SetShown(u.mapMask == nil)
  local function masked(t)
    if u.mapMask and t.AddMaskTexture then pcall(t.AddMaskTexture, t, u.mapMask) end
    return t
  end
  u.tiles = Widgets.Pool(function()
    local t = box:CreateTexture(nil, "BACKGROUND")
    if t.SetDesaturated then t:SetDesaturated(true) end
    return masked(t)
  end, nil, 64)
  u.overlays = Widgets.Pool(function()
    local t = box:CreateTexture(nil, "BACKGROUND", nil, 2)
    return masked(t)
  end, nil, (Journal.View and Journal.View.OVERLAY_MAX) or 400)
  u.heat = Widgets.Pool(function()
    local t = box:CreateTexture(nil, "ARTWORK")
    rune(t, "disc")
    if t.SetBlendMode then t:SetBlendMode("BLEND") end
    return masked(t)
  end, nil, Kampf.HEAT_MAX)
  u.dots = Widgets.Pool(function()
    local t = box:CreateTexture(nil, "ARTWORK", nil, 1)
    rune(t, "disc")
    t:SetSize(DOT_SIZE, DOT_SIZE)
    return masked(t)
  end, nil, Kampf.POINT_MAX)
  local layer = CreateFrame("Frame", nil, box)
  layer:SetAllPoints(box)
  if layer.SetFrameLevel and box.GetFrameLevel then
    local lvl = box:GetFrameLevel()
    if type(lvl) == "number" then layer:SetFrameLevel(lvl + 2) end
  end
  u.markers = Widgets.Pool(function()
    local b = CreateFrame("Frame", nil, layer)
    b:SetSize(18, 18)
    local t = tex(b, "OVERLAY")
    t:SetAllPoints(b)
    b.icon = t
    hover(b, function(f) return f.tip end)
    return b
  end, function(b) Widgets.hideTip(b) b.tip = nil end, Kampf.MARKER_MAX)
  local empty = font(box, "text", SZ.s, "sepia", "CENTER")
  empty:SetPoint("CENTER", box, "CENTER", 0, 0)
  u.mapEmpty = empty
  -- switch Hotspots | Genau bottom left on the map (only with exact points), book style like the other switches (ink,
  -- red scribble): no box, only a half transparent parchment label
  -- with a soft irregular fading edge (Media/MapFade, same shape as the map edge; fallback Media/Glow) and a light
  -- parchment shadow under the text so it stays readable on the map art
  local T = Page.TEXT
  u.mapMode = D.NewToggle(right, { size = SZ.xs, gap = 10, value = "hot",
    items = { { key = "hot", label = T.modeHot, tip = { T.modeHot, T.modeHotTip, T.mapHint } },
      { key = "exact", label = T.modePoints, tip = { T.modePoints, T.modePointsTip, T.mapHint } } },
    onChange = guarded(function(key) Page.SetMapMode(self, key) end) })
  local chip = u.mapMode.frame
  local haloTex = Theme.TEX and (Theme.TEX.mapFade or Theme.TEX.glow)
  if haloTex then
    local halo = chip:CreateTexture(nil, "BACKGROUND", nil, -1)
    halo:SetPoint("TOPLEFT", chip, "TOPLEFT", -MODE_HALO_X, MODE_HALO_Y)
    halo:SetPoint("BOTTOMRIGHT", chip, "BOTTOMRIGHT", MODE_HALO_X, -MODE_HALO_Y)
    halo:SetTexture(haloTex)
    halo:SetVertexColor(Widgets.color("parchment", MODE_HALO_ALPHA))
    u.mapModeHalo = halo
  end
  for _, b in ipairs(u.mapMode.buttons) do
    local t = b.text
    if t and t.SetShadowColor then
      t:SetShadowColor(Widgets.color("parchment", 0.95))
      if t.SetShadowOffset then t:SetShadowOffset(1, -1) end
      t.mapShade = true -- light shadow text on the map (not the page's ink shadow), test journal-ink
    end
  end
  if chip.SetFrameLevel and box.GetFrameLevel then
    local lvl = box:GetFrameLevel()
    if type(lvl) == "number" then
      chip:SetFrameLevel(lvl + 8)
      -- buttons (text, scribble) safely above the label of the switch
      for _, b in ipairs(u.mapMode.buttons) do
        if b.SetFrameLevel then b:SetFrameLevel(lvl + 9) end
      end
    end
  end
  chip:Hide()
  -- caption (left) and note (right) in the line between title and map, both before the swords
  local cap = font(right, "label", SZ.s, "sepia", "LEFT")
  cap:SetPoint("TOPLEFT", right, "TOPLEFT", SR.x, -CAP_Y)
  cap:SetWidth(TOP_W - 150)
  cap:SetWordWrap(false)
  u.caption = cap
  local note = font(right, "title", SZ.m, "red", "RIGHT")
  note:SetPoint("TOPRIGHT", right, "TOPLEFT", SR.x + TOP_W, -(CAP_Y - 1))
  note:SetWidth(150)
  note:SetWordWrap(false)
  u.mapNote = note
end

local function buildRight(self, right)
  local T = Page.TEXT
  local u = {}
  self.R = u
  u.head = Widgets.NewPageHead(right, { side = "R" })
  u.head:SetTexts("", T.right)
  local title = font(right, "title", SZ.l, "ink", "LEFT")
  title:SetPoint("TOPLEFT", right, "TOPLEFT", SR.x, -G.slots.title.y)
  title:SetWidth(TOP_W)
  title:SetWordWrap(false)
  u.mapTitle = title
  u.mapTitleHover = CreateFrame("Frame", nil, right)
  u.mapTitleHover:SetPoint("TOPLEFT", title, "TOPLEFT", 0, 0)
  u.mapTitleHover:SetSize(TOP_W, 22)
  u.mapTitleHover:EnableMouse(false)
  u.mapTitleHover:SetScript("OnEnter", function(h) if h.full then Widgets.tip(h, { h.full }) end end)
  u.mapTitleHover:SetScript("OnLeave", function(h) Widgets.hideTip(h) end)
  buildMap(self, right)

  -- control line of the lower block (grid): left the switch Tode | Haaresbreite, right the paging of the deaths ("Tod x
  -- von y" + arrow pair).
  -- Both only in the death report detail; there "Zurück zu den Toden" replaces the switch on the left (Esc too).
  local cy = -(LOW_Y + 12)
  u.lowToggle = D.NewToggle(right, { size = SZ.m, gap = 14, value = "graves",
    items = { { key = "graves", label = T.lowGraves, tip = { T.lowGraves, T.lowGravesTip } },
      { key = "close", label = T.lowClose, tip = { T.lowClose, T.lowCloseTip } } },
    onChange = guarded(function(key) Page.ShowLow(self, key) end) })
  u.lowItemsAll = u.lowToggle.items
  u.lowCloseShown = true
  u.lowToggle.frame:SetPoint("LEFT", right, "TOPLEFT", SR.x - 3, cy)
  u.deathBack = D.NewBack(right, T.backToGraves, guarded(function() Page.CloseDeath(self) end), { size = SZ.m })
  u.deathBack:SetPoint("LEFT", right, "TOPLEFT", SR.x - 3, cy)
  u.deathBack:Hide()
  u.deathNav = D.NewNavPair(right, { onPrev = guarded(function() Page.ShiftDeath(self, -1) end),
    onNext = guarded(function() Page.ShiftDeath(self, 1) end), tipPrev = { T.prevDeath }, tipNext = { T.nextDeath } })
  u.deathNav.frame:SetPoint("TOPRIGHT", right, "TOPLEFT", SR.x + SR.w + 4, -LOW_Y)
  u.prev, u.next = u.deathNav.prev, u.deathNav.next
  local dpos = font(right, "label", SZ.s, "sepia", "RIGHT")
  dpos:SetPoint("RIGHT", u.deathNav.frame, "LEFT", -6, 0)
  u.deathPos = dpos

  -- death report "Der letzte Atemzug" (detail of the deaths; the holder toggles with Page.Apply)
  local db = CreateFrame("Frame", nil, right)
  db:SetAllPoints(right)
  u.deathBox = db
  local dt = font(db, "title", SZ.m, "ink", "LEFT")
  dt:SetPoint("TOPLEFT", right, "TOPLEFT", SR.x, -DEATH_Y)
  dt:SetWidth(SR.w)
  dt:SetWordWrap(false)
  local ds = font(db, "label", SZ.xs, "sepia", "LEFT")
  ds:SetPoint("TOPLEFT", right, "TOPLEFT", SR.x, -(DEATH_Y + 19))
  ds:SetWidth(SR.w)
  ds:SetWordWrap(false)
  u.deathTitle, u.deathSub = dt, ds
  u.hits = {}
  for i = 1, Kampf.HITS_MAX do
    local y = DEATH_Y + 38 + (i - 1) * HIT_ROW
    local row = CreateFrame("Frame", nil, db)
    row:SetSize(HIT_W, HIT_ROW)
    row:SetPoint("TOPLEFT", right, "TOPLEFT", SR.x, -y)
    local who = font(row, "text", SZ.xs, "ink", "LEFT")
    who:SetPoint("LEFT", row, "LEFT", 0, 0)
    who:SetWidth(150)
    who:SetWordWrap(false)
    local bg = tex(row, "BORDER")
    bg:SetColorTexture(Widgets.color("sepia", 0.15))
    bg:SetSize(90, 6)
    bg:SetPoint("LEFT", row, "LEFT", 158, 0)
    local fill = tex(row, "ARTWORK")
    fill:SetColorTexture(Widgets.color("red", 0.8))
    fill:SetHeight(6)
    fill:SetPoint("LEFT", bg, "LEFT", 0, 0)
    local amt = font(row, "title", SZ.s, "ink", "RIGHT")
    amt:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    amt:SetWidth(52)
    row.who, row.bg, row.fill, row.amount = who, bg, fill, amt
    hover(row, function(f) return f.item and f.item.tip end)
    u.hits[i] = row
  end
  local span = font(db, "title", SZ.s, "red", "LEFT")
  span:SetPoint("TOPLEFT", right, "TOPLEFT", SR.x, -(DEATH_Y + 42 + Kampf.HITS_MAX * HIT_ROW))
  span:SetWidth(SPAN_W) -- ends before the blood bottom right (x 334 from y 578): after the map growth the second line reaches there
  span:SetWordWrap(true)
  span:SetJustifyV("TOP")
  u.span = span

  -- deaths (list): per zone the name and one gravestone per death (more than GRAVE_STONES: stones + "+n")
  local gb = CreateFrame("Frame", nil, right)
  gb:SetAllPoints(right)
  u.gravesBox = gb
  local y0 = DEATH_Y
  local gh = font(gb, "label", SZ.xs, "sepia", "LEFT")
  gh:SetPoint("TOPLEFT", right, "TOPLEFT", SR.x, -y0)
  set(gh, T.graves)
  hover(gh, function() return { T.graves, T.gravesTip } end)
  u.gravesHead = gh
  u.graves = {}
  -- gravestones and line are clickable and open the death report of exactly this death: stone k = k-th death of the
  -- zone (oldest first),
  -- "+n" = the next one not shown, the zone name = the last death there. Hover red.
  local function paintStone(b)
    b.icon:SetVertexColor(Widgets.color(b.hover and "red" or "sepia", 0.95))
  end
  local function newStone(row)
    local b = CreateFrame("Button", nil, row)
    b:SetSize(STONE_W + 2, GRAVE_ROW)
    local st = tex(b, "ARTWORK")
    st:SetSize(STONE_W, STONE_H)
    st:SetPoint("CENTER", b, "CENTER", 0, 0)
    if Theme.TEX and Theme.TEX.grave then st:SetTexture(Theme.TEX.grave) end
    b.icon = st
    if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp") end
    b:SetScript("OnClick", guarded(function(sb) Page.OpenDeath(self, sb.death) end))
    b:SetScript("OnEnter", function(sb)
      sb.hover = true
      paintStone(sb)
      if sb.death then Widgets.tip(sb, { sb.tipText or T("deathNo", Journal.Texts.int(sb.death)), T.openDeath }) end
    end)
    b:SetScript("OnLeave", function(sb)
      sb.hover = false
      paintStone(sb)
      Widgets.hideTip(sb)
    end)
    paintStone(b)
    return b
  end
  for i = 1, Kampf.GRAVE_MAX do
    local row = CreateFrame("Button", nil, gb)
    row:SetSize(LOW_W, GRAVE_ROW)
    row:SetPoint("TOPLEFT", right, "TOPLEFT", SR.x, -(y0 + 18 + (i - 1) * GRAVE_ROW))
    local name = font(row, "label", SZ.xs, "ink", "LEFT")
    name:SetPoint("LEFT", row, "LEFT", 0, 0)
    name:SetWidth(GRAVE_NAME_W)
    name:SetWordWrap(false)
    row.stones = {}
    for k = 1, GRAVE_STONES do
      local st = newStone(row)
      st:SetPoint("LEFT", row, "LEFT", GRAVE_NAME_W + 3 + (k - 1) * GRAVE_STEP, 0)
      row.stones[k] = st
    end
    local more = CreateFrame("Button", nil, row)
    more:SetSize(30, GRAVE_ROW)
    more:SetPoint("LEFT", row, "LEFT", GRAVE_NAME_W + 4 + (GRAVE_STONES - 1) * GRAVE_STEP, 0)
    local mt = font(more, "title", SZ.xs, "red", "LEFT")
    mt:SetPoint("LEFT", more, "LEFT", 0, 0)
    more.text = mt
    if more.RegisterForClicks then more:RegisterForClicks("LeftButtonUp") end
    more:SetScript("OnClick", guarded(function(b) Page.OpenDeath(self, b.death) end))
    hover(more, function(b) return b.death and { T("deathNo", Journal.Texts.int(b.death)), T.openDeath } or nil end)
    row.name, row.more = name, more
    if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp") end
    row:SetScript("OnClick", guarded(function(r)
      local list = r.item and r.item.deaths
      if type(list) == "table" and #list > 0 then Page.OpenDeath(self, list[#list]) end
    end))
    hover(row, function(f)
      if not (f.item and f.item.tip) then return nil end
      local lines = {}
      for _, l in ipairs(f.item.tip) do lines[#lines + 1] = l end
      lines[#lines + 1] = T.openLastDeath
      return lines
    end)
    row:HookScript("OnEnter", function(r) r.name:SetTextColor(Widgets.color("red")) end)
    row:HookScript("OnLeave", function(r) r.name:SetTextColor(Widgets.color("ink")) end)
    u.graves[i] = row
  end
  local ge = font(gb, "text", SZ.xs, "sepia", "LEFT")
  ge:SetPoint("TOPLEFT", right, "TOPLEFT", SR.x, -(y0 + 20))
  ge:SetWidth(LOW_W)
  u.gravesEmpty = ge
  local ghost = font(gb, "label", SZ.xs, "sepia", "LEFT")
  ghost:SetPoint("TOPLEFT", right, "TOPLEFT", SR.x, -(y0 + 22 + Kampf.GRAVE_MAX * GRAVE_ROW))
  ghost:SetWidth(LOW_W) -- ends before the skull bottom right (x 348 from y 479), a long line wraps
  ghost:SetWordWrap(true)
  ghost:SetJustifyV("TOP")
  u.ghost = ghost

  local cb = CreateFrame("Frame", nil, right)
  cb:SetAllPoints(right)
  u.closeBox = cb
  local cx = SR.x
  local ch = font(cb, "label", SZ.xs, "sepia", "LEFT")
  ch:SetPoint("TOPLEFT", right, "TOPLEFT", cx, -y0)
  set(ch, T.close)
  u.close = {}
  for i = 1, Kampf.CLOSE_MAX do
    local row = CreateFrame("Frame", nil, cb)
    row:SetSize(LOW_W, 18)
    row:SetPoint("TOPLEFT", right, "TOPLEFT", cx, -(y0 + 18 + (i - 1) * 18))
    local name = font(row, "text", SZ.xs, "ink", "LEFT")
    name:SetPoint("LEFT", row, "LEFT", 0, 0)
    name:SetWidth(LOW_W - 56)
    name:SetWordWrap(false)
    local pct = font(row, "title", SZ.m, "red", "RIGHT")
    pct:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    pct:SetWidth(46)
    row.name, row.pct = name, pct
    hover(row, function(f) return f.item and f.item.tip end)
    u.close[i] = row
  end
  local ce = font(cb, "text", SZ.xs, "sepia", "LEFT")
  ce:SetPoint("TOPLEFT", right, "TOPLEFT", cx, -(y0 + 20))
  ce:SetWidth(LOW_W)
  u.closeEmpty = ce
  local cf = font(cb, "label", SZ.xs, "sepia", "LEFT")
  cf:SetPoint("TOPLEFT", right, "TOPLEFT", cx, -(y0 + 20 + Kampf.CLOSE_MAX * 18))
  cf:SetWidth(SR.w)
  cf:SetJustifyV("TOP")
  u.closeFoot = cf
  Page.ShowLow(self, "graves")
end

-- shows what self.low / self.detail say: list of deaths (default), close calls or the death report detail (only if
-- there is a death;
-- otherwise it falls back to the list, whose empty state shows "Noch nirgends gestorben.")
-- close wins need a readable life value: where the client keeps it locked outside combat (Forever) there are none, so the tab
-- "Haaresbreite" is hidden as long as there is no entry (existing entries stay visible). ns.closeWinReadable comes from the collector.
local function closeTabWanted(self)
  -- all zones together (view.closeTotal), not the zone-filtered list: the tab must not come and go with the zone choice
  local v = self.view
  local total = v and (v.closeTotal or (v.close and v.close.total))
  if (tonumber(total) or 0) > 0 then return true end
  local fn = ns.closeWinReadable
  return not (type(fn) == "function" and fn() == false)
end

function Page.Apply(self)
  local u = self.R
  if not u then return end
  local wanted = closeTabWanted(self)
  if wanted ~= u.lowCloseShown then
    u.lowCloseShown = wanted
    u.lowToggle:SetItems(wanted and u.lowItemsAll or { u.lowItemsAll[1] })
  end
  if not wanted and self.low == "close" then self.low = "graves" end
  local detail = self.detail == true and self.low == "graves" and self.view ~= nil and self.view.death ~= nil
  self.detail = detail
  u.lowToggle:SetValue(self.low)
  u.lowToggle.frame:SetShown(not detail)
  u.deathBack:SetShown(detail)
  u.deathBox:SetShown(detail)
  u.gravesBox:SetShown(self.low == "graves" and not detail)
  u.closeBox:SetShown(self.low == "close")
  u.deathNav.frame:SetShown(detail)
  u.deathPos:SetShown(detail)
  if not detail then
    Widgets.hideTip(u.prev)
    Widgets.hideTip(u.next)
  end
end

-- lower block of the right page: "graves" (deaths, default) or "close" (close calls); closes the death report detail
function Page.ShowLow(self, key)
  if not self.R then return end
  self.low = key == "close" and "close" or "graves"
  self.detail = false
  Page.Apply(self)
end

-- close the death report detail: back to the list of deaths
function Page.CloseDeath(self)
  if not self.R then return end
  self.low = "graves"
  self.detail = false
  Page.Apply(self)
end

function Page:Build(left, right)
  self.left, self.right = left, right
  buildLeft(self, left)
  buildRight(self, right)
  self.built = true
end

-- map art of the zone as on the journey map (View.zoneArt: base map + uncovered overlays; View.mapArt as fallback
-- without valid zone art) or nil.
-- Remembered per zone until drawHunt redraws (zoom/drag do not ask the client again).
function Page.ZoneArt(self, mapID)
  if not mapID then return nil end
  local c = self.artCache
  if c and c.id == mapID then return c.art or nil end
  local View, art = Journal.View, nil
  local function valid(a) return type(a) == "table" and tonumber(a.w) and tonumber(a.h) and a.w > 0 and a.h > 0 end
  for _, fn in ipairs({ View and View.zoneArt or false, View and View.mapArt or false }) do
    if type(fn) == "function" then
      local ok, a = pcall(fn, mapID)
      if ok and valid(a) then art = a break end
    end
  end
  self.artCache = { id = mapID, art = art or false }
  return art
end

-- map image of the zone (Blizzard art, sepia or original colours per setting mapColor) fitted into the box -> rectangle
-- x, y, w, h (pixels in the box)
local function drawArt(self, mapID, H, z, tx, ty)
  local u = self.R
  u.tiles:ReleaseAll()
  u.overlays:ReleaseAll()
  local View, Map = Journal.View, Journal.Map
  local art = Page.ZoneArt(self, mapID)
  if not art or not (Map and Map.tiles) then return 0, 0, MAP_W, H end
  z = z or 1
  local s = min(MAP_W / art.w, H / art.h)
  local w, h = art.w * s, art.h * s
  -- left-aligned at the text block (grid), vertically centred in the box
  local ox, oy = 0, (H - h) / 2
  -- map colour: same setting (menu) as on the journey map, sepia or original colours
  local original = View.peek and View.peek("mapColor") == "original"
  local tx0, ty0 = tx or 0, ty or 0
  for _, t in ipairs(Map.tiles(art)) do
    local tx = u.tiles:Acquire()
    if not tx then break end
    tx:SetTexture(t.file)
    tx:SetTexCoord(0, t.u1, 0, t.v1)
    if Map.tintTile then Map.tintTile(tx, original) end
    tx:SetSize((t.x1 - t.x0) * s * z, (t.y1 - t.y0) * s * z)
    tx:SetPoint("TOPLEFT", u.map, "TOPLEFT", ox + t.x0 * s * z + tx0, -(oy + t.y0 * s * z + ty0))
  end
  -- uncovered areas (exploration overlays) over the base map, same tint; upper layer for isDrawOnTopLayer
  for _, t in ipairs(type(art.overlays) == "table" and art.overlays or {}) do
    local tx = u.overlays:Acquire()
    if not tx then break end
    if tx.SetDrawLayer then tx:SetDrawLayer("BACKGROUND", t.top and 3 or 2) end
    tx:SetTexture(t.file)
    tx:SetTexCoord(0, t.u1, 0, t.v1)
    if Map.tintTile then Map.tintTile(tx, original) end
    tx:SetSize((t.x1 - t.x0) * s * z, (t.y1 - t.y0) * s * z)
    tx:SetPoint("TOPLEFT", u.map, "TOPLEFT", ox + t.x0 * s * z + tx0, -(oy + t.y0 * s * z + ty0))
  end
  return ox, oy, w, h
end

local MARKER_COLOR = { death = "red", rare = "blue", elite = "sepia", boss = "red" }

-- map icons (death, rare, elite, boss) as on the journey map: the painted symbol from Media/MapIcons at its size
-- (Theme.MARKER_SIZE) and own colour;
-- without the texture the old ink mark (atlas Markers) tinted
function Page.MarkerIcon(b, kind)
  local painted = Theme.HAS_MAP_ICONS and Theme.TEX and Theme.TEX.mapIcons and Theme.MAP_ICONS and Theme.MAP_ICONS[kind] ~= nil
    and Theme.mapIconCoords
  if painted then
    local size = Theme.MARKER_SIZE and Theme.MARKER_SIZE[kind] or 22
    b:SetSize(size, size)
    b.icon:SetTexture(Theme.TEX.mapIcons)
    b.icon:SetTexCoord(Theme.mapIconCoords(kind))
    b.icon:SetVertexColor(1, 1, 1, 1)
  else
    b:SetSize(18, 18)
    rune(b.icon, kind)
    b.icon:SetVertexColor(Widgets.color(MARKER_COLOR[kind] or "ink", 1))
  end
end

local function exactOn(self, hunt)
  return self.mapMode == "exact" and hunt.mode == "heat" and hunt.points ~= nil
end

local function clampView(mv, a)
  local z = mv.z
  mv.tx = max(a.w * (1 - z), min(0, mv.tx))
  mv.ty = max(a.h * (1 - z), min(0, mv.ty))
end

-- draw the map (tiles, blobs/points, markers) with zoom/shift self.mv; self.art = rectangle of the art in the box
function Page.PaintMap(self)
  local u, hunt = self.R, self.view and self.view.hunt
  if not (u and hunt) then return end
  local H = MAP_H
  local mv = self.mv
  local ox, oy, w, h = drawArt(self, hunt.zone, H, mv.z, mv.tx, mv.ty)
  local a = { ox = ox, oy = oy, w = w, h = h, H = H }
  self.art = a
  local z = mv.z
  u.heat:ReleaseAll()
  u.dots:ReleaseAll()
  u.markers:ReleaseAll()
  local function px(nx) return ox + mv.tx + nx * w * z end
  local function py(ny) return oy + mv.ty + ny * h * z end
  local function inside(x, y, pad) return x >= ox - pad and x <= ox + w + pad and y >= oy - pad and y <= oy + h + pad end
  if exactOn(self, hunt) then
    for _, p in ipairs(hunt.points.list) do
      local x, y = px(p.x), py(p.y)
      if inside(x, y, 0) then
        local t = u.dots:Acquire()
        if not t then break end
        t:SetVertexColor(Widgets.color("red", 0.85))
        t:SetPoint("CENTER", u.map, "TOPLEFT", x, -y)
      end
    end
  else
    local g = hunt.grid or 32
    for _, c in ipairs(hunt.cells) do
      local x, y = px((c.gx + 0.5) / g), py((c.gy + 0.5) / g)
      local size = min(160, max(6, w * z / g * 2.4))
      if inside(x, y, size / 2) then
        local t = u.heat:Acquire()
        if not t then break end
        t:SetSize(size, size)
        t:SetVertexColor(Widgets.color("red", c.alpha * 0.55))
        t:SetPoint("CENTER", u.map, "TOPLEFT", x, -y)
      end
    end
  end
  for _, m in ipairs(hunt.markers) do
    local x, y = px(m.x), py(m.y)
    if inside(x, y, 0) then
      local b = u.markers:Acquire()
      if not b then break end
      Page.MarkerIcon(b, m.kind)
      b.tip = m.tip
      b:SetPoint("CENTER", u.map, "TOPLEFT", x, -y)
    end
  end
  return ox, oy, w, h, H
end

-- mouse pointer in the map box (pixels from top left); nil if not readable
local function cursorIn(frame)
  if type(GetCursorPosition) ~= "function" then return nil end
  local s = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
  local cx, cy = GetCursorPosition()
  local left, top = frame:GetLeft(), frame:GetTop()
  if not (type(cx) == "number" and type(cy) == "number" and type(left) == "number" and type(top) == "number"
    and type(s) == "number" and s > 0) then return nil end
  return cx / s - left, top - cy / s
end

local function clock() return type(GetTime) == "function" and GetTime() or 0 end

-- zoom (wheel) around the point (cx, cy) in the box; delta > 0 = closer. -> true if the view changed
function Page.ZoomMap(self, delta, cx, cy)
  local mv, a = self.mv, self.art
  if not (mv and a) or type(delta) ~= "number" or delta ~= delta or delta == 0 then return false end
  if not (cx and cy) then
    cx, cy = cursorIn(self.R.map)
    if not cx then cx, cy = a.ox + a.w / 2, a.oy + a.H / 2 end
  end
  local z0 = mv.z
  local z1 = max(1, min(ZOOM_MAX, z0 * ZOOM_STEP ^ max(-3, min(3, delta))))
  if math.abs(z1 - z0) < 1e-9 then return false end
  local nx, ny = (cx - a.ox - mv.tx) / z0, (cy - a.oy - mv.ty) / z0 -- point of the art under the pointer (unzoomed)
  mv.z = z1
  mv.tx, mv.ty = cx - a.ox - nx * z1, cy - a.oy - ny * z1
  clampView(mv, a)
  self.hoverKey = nil
  Widgets.hideTip(self.R.map)
  Page.PaintMap(self)
  return true
end

function Page.ResetMap(self)
  self.mv = { z = 1, tx = 0, ty = 0 }
  self.hoverKey = nil
  if self.R then Widgets.hideTip(self.R.map) end
  Page.PaintMap(self)
end

function Page.SetMapMode(self, key)
  self.mapMode = key == "exact" and "exact" or "hot"
  self.hoverKey = nil
  if self.R then
    Widgets.hideTip(self.R.map)
    self.R.mapMode:SetValue(self.mapMode)
  end
  Page.PaintMap(self)
end

-- hit under the pointer (cx, cy in the box): blob (hotspots) or point (exact) -> key, tooltip lines; else nil
function Page.MapHit(self, cx, cy)
  local hunt, a, mv = self.view and self.view.hunt, self.art, self.mv
  if not (hunt and a and mv) or hunt.mode ~= "heat" then return nil end
  if cx < a.ox or cx > a.ox + a.w or cy < a.oy or cy > a.oy + a.h then return nil end
  local T, int, z = Page.TEXT, Journal.Texts.int, mv.z
  local head, key, lines, count
  if exactOn(self, hunt) then
    local best, bd = nil, DOT_HIT * DOT_HIT + 1
    for i, p in ipairs(hunt.points.list) do
      local dx, dy = a.ox + mv.tx + p.x * a.w * z - cx, a.oy + mv.ty + p.y * a.h * z - cy
      local d = dx * dx + dy * dy
      if d < bd then best, bd = i, d end
    end
    if not best then return nil end
    local p = hunt.points.list[best]
    local rx, ry = DOT_SIZE / (a.w * z), DOT_SIZE / (a.h * z)
    lines, count = hunt.spot(p.x - rx, p.y - ry, p.x + rx, p.y + ry)
    key = "p" .. best
    head = count == 1 and T.onePoint or T("pointsHere", int(count))
  else
    local g = hunt.grid or 32
    local size = min(160, max(6, a.w * z / g * 2.4))
    local best, bd = nil, (size * 0.35) ^ 2
    for _, c in ipairs(hunt.cells) do
      local dx = a.ox + mv.tx + (c.gx + 0.5) / g * a.w * z - cx
      local dy = a.oy + mv.ty + (c.gy + 0.5) / g * a.h * z - cy
      local d = dx * dx + dy * dy
      if d < bd then best, bd = c, d end
    end
    if not best then return nil end
    key = "c" .. best.gx .. ":" .. best.gy
    head = T("killsWord", T.hotspot, int(best.n))
    if hunt.spot then lines = hunt.spot(best.gx / g, best.gy / g, (best.gx + 1) / g, (best.gy + 1) / g) end
  end
  local tip = { head }
  for _, l in ipairs(lines or {}) do tip[#tip + 1] = l end
  if hunt.points and hunt.points.sample then
    tip[#tip + 1] = T("sample", int(hunt.points.n), int(hunt.points.total))
  end
  return key, tip
end

-- hover/drag: only while the pointer is on the map (OnUpdate is removed on leaving)
function Page.MapTick(self)
  local u = self.R
  if not (u and u.map:IsShown()) then return end
  local cx, cy = cursorIn(u.map)
  if not cx then return end
  local pr = self.press
  if pr and not mouseDown() then pr = nil self.press = nil end
  if pr then
    local dx, dy = cx - pr.x, cy - pr.y
    if not pr.moved and dx * dx + dy * dy >= DRAG_MIN * DRAG_MIN then pr.moved = true end
    if pr.moved then
      local mv, a = self.mv, self.art
      if mv and a and mv.z > 1 then
        local tx, ty = mv.tx, mv.ty
        mv.tx, mv.ty = pr.tx + dx, pr.ty + dy
        clampView(mv, a)
        if mv.tx ~= tx or mv.ty ~= ty then
          self.hoverKey = nil
          Widgets.hideTip(u.map)
          Page.PaintMap(self)
        end
      end
      return
    end
  end
  local key, tip = Page.MapHit(self, cx, cy)
  if key ~= self.hoverKey then
    self.hoverKey = key
    if key then Widgets.tip(u.map, tip) else Widgets.hideTip(u.map) end
  end
end

function Page.StopMapHover(self)
  local u = self.R
  self.press, self.hoverKey = nil, nil
  if u and u.map then
    u.map:SetScript("OnUpdate", nil)
    Widgets.hideTip(u.map)
  end
end

-- zoom, drag and double click on the map box (wheel, left button); tooltips via MapTick
function Page.wireMap(self, box)
  box:EnableMouse(true)
  if box.EnableMouseWheel then box:EnableMouseWheel(true) end
  box:SetScript("OnMouseWheel", guarded(function(_, delta) Page.ZoomMap(self, delta) end))
  box:SetScript("OnMouseDown", guarded(function(f, button)
    if button ~= nil and button ~= "LeftButton" then return end
    local cx, cy = cursorIn(f)
    if not (cx and self.mv) then return end
    self.press = { x = cx, y = cy, tx = self.mv.tx, ty = self.mv.ty, moved = false }
  end))
  box:SetScript("OnMouseUp", guarded(function(f, button)
    local pr = self.press
    self.press = nil
    if button ~= nil and button ~= "LeftButton" then return end
    if not pr or pr.moved then
      self.lastClick = nil
      return
    end
    local t = clock()
    local last = self.lastClick
    if last and t - last.t <= DOUBLE_CLICK and (pr.x - last.x) ^ 2 + (pr.y - last.y) ^ 2 < 64 then
      self.lastClick = nil
      Page.ResetMap(self)
    else
      self.lastClick = { t = t, x = pr.x, y = pr.y }
    end
  end))
  box:SetScript("OnEnter", guarded(function(f)
    local acc = 0
    f:SetScript("OnUpdate", function(_, dt)
      acc = acc + (tonumber(dt) or 0)
      if acc < 0.05 then return end
      acc = 0
      local ok, err = pcall(Page.MapTick, self)
      if not ok then Pages.fail("kampf", err) end
    end)
  end))
  box:SetScript("OnLeave", guarded(function() Page.StopMapHover(self) end))
end

local function drawHunt(self, hunt)
  local u = self.R
  local heat = hunt.mode == "heat"
  local H = MAP_H
  u.map:SetHeight(H)
  u.mapFrame:SetHeight(H)
  set(u.mapTitle, Kampf.TEXT.hunt .. (hunt.zoneName and (" · " .. hunt.zoneName) or ""))
  local mtSize = Widgets.fitLine(u.mapTitle, TOP_W, 11) -- "Hunting Grounds · <long zone name>" fits the column in English too
  local mtCut = mtSize and (mtSize < (u.mapTitle.fitBase or mtSize) or (tonumber(u.mapTitle:GetStringWidth()) or 0) > TOP_W)
  u.mapTitleHover.full = mtCut and u.mapTitle:GetText() or nil
  u.mapTitleHover:EnableMouse(mtCut and true or false)
  -- new zone/new state: zoom back to the whole map
  if self.mvHunt ~= hunt or not self.mv then
    self.mv, self.mvHunt, self.lastClick = { z = 1, tx = 0, ty = 0 }, hunt, nil
  end
  Page.StopMapHover(self)
  self.artCache = nil -- fetch the map art (with newly uncovered areas) fresh once per redraw
  local ox, oy, w, h = Page.PaintMap(self)
  set(u.mapEmpty, (hunt.mode == "empty" and not hunt.zone) and (Kampf.TEXT.noZone .. " " .. Page.TEXT.hintZone) or "")
  u.mapMode.frame:ClearAllPoints()
  u.mapMode.frame:SetPoint("TOPLEFT", self.right, "TOPLEFT", SR.x + ox + 8, -(MAP_Y + oy + h - 30))
  u.mapMode:SetValue(self.mapMode == "exact" and hunt.points and "exact" or "hot")
  u.mapMode.frame:SetShown(heat and hunt.points ~= nil)
  -- frame tight around the map art (without art: the whole box)
  u.mapFrame:ClearAllPoints()
  u.mapFrame:SetPoint("TOPLEFT", self.right, "TOPLEFT", SR.x + ox, -(MAP_Y + oy))
  u.mapFrame:SetSize(w, h)
  -- soft edge exactly around the map art
  if u.mapMask then
    u.mapMask:ClearAllPoints()
    u.mapMask:SetPoint("TOPLEFT", u.map, "TOPLEFT", ox, -oy)
    u.mapMask:SetSize(w, h)
  end
  -- caption and note sit fixed in the line above the map (buildMap)
  set(u.caption, hunt.caption)
  set(u.mapNote, hunt.note)
end

local function drawDeath(self, d)
  local u = self.R
  if not d then
    set(u.deathTitle, Page.TEXT.noDeathTitle)
    set(u.deathSub, Kampf.TEXT.noDeath)
    for _, row in ipairs(u.hits) do
      row.item = nil
      row:Hide()
    end
    set(u.span, "")
    u.deathNav:SetEnabled(false, false)
    set(u.deathPos, "")
    return
  end
  set(u.deathTitle, d.title)
  set(u.deathSub, d.sub)
  for i, row in ipairs(u.hits) do
    local h = d.hits[i]
    row.item = h
    if h then
      row:Show()
      set(row.who, h.spell and (h.who .. " · " .. h.spell) or h.who)
      row.who:SetTextColor(Widgets.color(h.gap and "sepia" or "ink"))
      set(row.amount, h.crit and (h.amountText .. " " .. Page.TEXT.krit) or h.amountText)
      row.amount:SetTextColor(Widgets.color(h.heal and "treasure" or (h.crit and "red" or "ink")))
      -- health bar: health before the hit (gap for an unreadable value)
      if h.hp then
        row.bg:Show()
        row.fill:SetWidth(max(90 * h.hp, 0.01))
        row.fill:SetShown(h.hp > 0)
      else
        row.bg:Hide()
        row.fill:Hide()
      end
    else
      Widgets.hideTip(row)
      row:Hide()
    end
  end
  local tail = {}
  if d.span then tail[#tail + 1] = d.span end
  if d.cause then tail[#tail + 1] = d.cause end
  if d.note then tail[#tail + 1] = "(" .. d.note .. ")" end
  set(u.span, table.concat(tail, " "))
  u.deathNav:SetEnabled(d.i > 1, d.i < d.n)
  local n = tonumber(d.n) or 0
  set(u.deathPos, n > 0 and Page.TEXT("deathOf", Journal.Texts.int(d.i), Journal.Texts.int(n)) or "")
end

local function drawLow(self, view)
  local u = self.R
  local g = view.graves
  for i, row in ipairs(u.graves) do
    local item = g.list[i]
    row.item = item
    if item then
      row:Show()
      set(row.name, item.name)
      local n = tonumber(item.n) or 0
      local stones = n > GRAVE_STONES and (GRAVE_STONES - 1) or n
      local ids = type(item.deaths) == "table" and item.deaths or {}
      local tips = type(item.stoneTips) == "table" and item.stoneTips or {}
      for k, s in ipairs(row.stones) do
        s.death = ids[k]
        s.tipText = tips[k]
        s:SetShown(k <= stones)
        s:EnableMouse(k <= stones and ids[k] ~= nil)
        if k > stones then Widgets.hideTip(s) end
      end
      row.more.death = n > GRAVE_STONES and ids[stones + 1] or nil
      set(row.more.text, n > GRAVE_STONES and ("+" .. Journal.Texts.int(n - stones)) or "")
      row.more:SetShown(n > GRAVE_STONES)
    else
      Widgets.hideTip(row)
      row:Hide()
    end
  end
  set(u.gravesEmpty, g.empty and (Kampf.TEXT.noGraves .. " " .. Page.TEXT.hintGraves) or "")
  local ghost = g.ghost
  if g.more > 0 then ghost = Page.TEXT("moreZones", Journal.Texts.int(g.more)) .. (ghost and (" · " .. ghost) or "") end
  set(u.ghost, ghost)
  local c = view.close
  for i, row in ipairs(u.close) do
    local item = c.list[i]
    row.item = item
    if item then
      row:Show()
      set(row.name, item.name)
      set(row.pct, item.pctText)
    else
      Widgets.hideTip(row)
      row:Hide()
    end
  end
  set(u.closeEmpty, c.total == 0 and (Kampf.TEXT.noClose .. " " .. Page.TEXT.hintClose) or "")
  local foot = c.footnote
  if c.total > #c.list then foot = Page.TEXT("closeCount", Journal.Texts.int(c.total), foot) end
  set(u.closeFoot, c.total > 0 and foot or "")
end

local function evaluate(self)
  local d = self.data
  return Kampf.evaluate(d.index, { live = d.live, now = d.now, death = self.deathIdx, hunted = self.hunted })
end

-- redraw the whole page (both halves) after the area choice
local function drawAll(self, view)
  self.R.head:SetTexts(Widgets.playerLine(self.data) or view.head, Page.TEXT.right)
  drawLeft(self, view)
  drawHunt(self, view.hunt)
  drawDeath(self, view.death)
  drawLow(self, view)
  Page.Apply(self)
end

-- open/close the area dropdown list (on == nil: toggle); stays closed without an evaluation
function Page.ToggleHuntedZones(self, on)
  local dd = self.L and self.L.huntedButton
  if not dd then return end
  if on == nil then on = not dd:IsOpen() end
  if on and self.view then
    dd:SetItems(Page.HuntedItems(self))
    dd:Open()
  else
    dd:Close()
  end
end

-- key: "all" or uiMapID; remembered in ui.kampfHunted. On open the current zone wins, "all" only holds until closing.
-- The choice switches the whole page; the death report starts at the last death of the area again.
function Page.SelectHunted(self, key)
  if not self.data then return end
  self.hunted = key
  self.deathIdx = nil
  self.detail = false
  if not self.data.guest then Pages.setSetting("kampfHunted", key) end -- looking at a guest never changes the own choice
  Page.ToggleHuntedZones(self, false)
  local nv = evaluate(self)
  if not nv then return end
  self.view = nv
  self.cardPage = 1
  drawAll(self, nv)
end

function Page.ShiftDeath(self, delta)
  local v = self.view
  if not (v and v.death and self.data) then return end
  local i = v.death.i + (tonumber(delta) or 0)
  if i < 1 or i > v.death.n then return end
  self.deathIdx = i
  local nv = evaluate(self)
  if not nv then return end
  self.view = nv
  drawDeath(self, nv.death)
end

-- open the death report of exactly death i (number as opts.death in the shown list): click on a gravestone.
-- The death report detail replaces the list of deaths, "Tod x von y" shows this death.
function Page.OpenDeath(self, i)
  i = tonumber(i)
  if not (i and i == i and self.data and self.view) then return end
  self.deathIdx = floor(i)
  local nv = evaluate(self)
  if not nv then return end
  self.view = nv
  drawDeath(self, nv.death)
  self.low, self.detail = "graves", nv.death ~= nil
  Page.Apply(self)
end

function Page:Refresh(data)
  if not self.built then return end
  self.data = data
  if data.changed then self.deathIdx = nil end
  -- another character's book (or back to the own one): the area choice starts from scratch for that character
  local gid = data.guest and data.guest.guid or false
  if self.bookOf ~= gid then
    self.bookOf = gid
    self.hunted, self.here, self.detail = nil, nil, false
  end
  -- area choice on open: the current zone (readable only outside combat), else the remembered choice, else all areas
  if self.hunted == nil and data.index then
    self.here = Page.currentMap()
    -- guest book: not the logged-in character's remembered choice
    self.hunted = Kampf.huntedZone(data.index, self.here, (not data.guest) and Pages.setting("kampfHunted") or nil)
  end
  local view = evaluate(self)
  if not view then error("Kampf: keine Auswertung") end
  local fresh = self.view == nil or self.view.hunted ~= view.hunted
  self.view = view
  if fresh then self.cardPage = 1 end
  drawAll(self, view)
end

function Page:OnHide()
  Page.CloseLens(self, true)
  Page.StopMapHover(self)
  local L, R = self.L, self.R
  if L then
    for _, c in ipairs(L.cards) do Widgets.hideTip(c) end
    Widgets.hideTip(L.rare)
    Widgets.hideTip(L.total)
    Widgets.hideTip(L.cardPrev)
    Widgets.hideTip(L.cardNext)
    Widgets.hideTip(L.huntedButton)
    L.huntedButton:Close()
    -- a hidden model frame releases its model: set again on the next show
    for _, c in ipairs(L.cards) do
      if c.model then c.model.want, c.model.loaded, c.model.tries = nil, false, nil end
    end
  end
  -- the next open picks the area again (current zone) and starts at the list of deaths
  self.hunted, self.here = nil, nil
  self.detail = false
  if R then
    for _, list in ipairs({ R.hits, R.graves, R.close }) do
      for _, row in ipairs(list) do Widgets.hideTip(row) end
    end
    for _, row in ipairs(R.graves) do
      for _, s in ipairs(row.stones) do Widgets.hideTip(s) end
      Widgets.hideTip(row.more)
    end
    for _, b in ipairs(R.markers.used) do Widgets.hideTip(b) end
    Widgets.hideTip(R.prev)
    Widgets.hideTip(R.next)
    Widgets.hideTip(R.deathBack)
  end
end

Pages.register("kampf", Page)
