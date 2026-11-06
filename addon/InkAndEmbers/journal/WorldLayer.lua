-- World map layer: shows the journey on the Blizzard world map (WorldMapFrame): route (Line textures on ONE pin covering the
-- canvas), map markers, level-ups, note pins and, on zone maps, kill marks. Two switches (two entries in the map filter, two
-- settings): "journey" (ui.worldMap: route, markers, level-ups, kill marks) and "places" (ui.worldPins: note and place to-do pins). Own data provider
-- (MapCanvasDataProviderMixin) with pins from virtual XML templates (journal/WorldLayer.xml).
-- Works with OpenMap, which switches the map via SetMapID: the provider recomputes on every OnMapChanged into the
-- coordinates of the displayed map. No OpenMap internals are used.
-- No OnUpdate. While the map is open ONE slow ticker (WL.LIVE_INTERVAL) runs and stops with the map: it keeps the live tail
-- (thin line from the end of the drawn route to the player), retries a draw that came out empty (model not ready, map data
-- missing, canvas not laid out yet) and, every WL.REBUILD_EVERY s, asks the model for a background rebuild when new trail
-- points exist (Model.get without noRebuild: old state at once, the build runs in coroutine frames; Model.onReady redraws).
-- At most WL.PIN_MAX pins and WL.SEG_MAX lines. In combat nothing happens (AcquirePin can create frames): the layer only
-- clears and redraws after PLAYER_REGEN_ENABLED. Without WorldMapFrame / MapCanvas API it does nothing.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local WL = {}
Journal.WorldLayer = WL

local floor, huge = math.floor, math.huge

WL.PIN_TEMPLATE = "EveNChronicleWorldPinTemplate"
WL.ROUTE_TEMPLATE = "EveNChronicleWorldRouteTemplate"
WL.FRAME_LEVEL = "PIN_FRAME_LEVEL_AREA_POI"
WL.PIN_MAX = 600
WL.SEG_MAX = 1000
WL.CULL = 0.02
WL.KILL_CELL = 1 / 48
WL.KILL_MAX = 120
WL.MINI_SIZE = 14
WL.ROUTE_PX = 2.5
WL.FLIGHT_PX = 1.6
WL.SCALE_MIN, WL.SCALE_MAX = 0.8, 1.3
WL.READY_THROTTLE = 2.5
WL.LIVE_INTERVAL = 1
WL.REBUILD_EVERY = 10
WL.RETRY_EMPTY = 3
WL.TAIL_MAX_AGE, WL.TAIL_MAX_VIEW = 30, 0.25
WL.JUMP_MIN_YD, WL.JUMP_SPEED = 15, 110
WL.MENU_TAG = "MENU_WORLD_MAP_TRACKING"

WL.TEXT = ns.Locale.ns("WorldLayer", {
  menu = "Reise (Ink & Embers)",
  menuPlaces = "Orte (Ink & Embers)",
  setting = "Reise auf der Weltkarte zeigen",
  buttonOn = "Reise auf der Weltkarte: an",
  buttonOff = "Reise auf der Weltkarte: aus",
  buttonHint = "Klick: Route und Marken des Reisejournals ein- oder ausblenden",
  buttonPlacesOn = "Orte auf der Weltkarte: an",
  buttonPlacesOff = "Orte auf der Weltkarte: aus",
  buttonPlacesHint = "Klick: Notiz- und To-Do-Orte ein- oder ausblenden",
  combat = "Die Weltkarte öffnet die Chronik nicht im Kampf.",
  noMap = "Die Weltkarte ist gerade nicht verfügbar.",
  tipSource = "Reisejournal",
  noteTip = "Klick: Notiz im Buch öffnen",
  noteCombat = "Im Kampf öffnet sich das Buch nicht. Versucht es danach noch einmal.",
})

WL.stats = { pins = 0, segs = 0 }

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == huge or v == -huge then return nil end
  return v
end

local function inCombat()
  if type(InCombatLockdown) ~= "function" then return false end
  local ok, v = pcall(InCombatLockdown)
  return ok and v and true or false
end

local function gt()
  return type(GetTime) == "function" and num(GetTime()) or 0
end

local function say(msg)
  if ns.Core and ns.Core.print then ns.Core.print(msg) end
end

local function report(err)
  if ns.Core and ns.Core.coreError then ns.Core.coreError("Weltkarten-Ebene: " .. tostring(err)) end
end

local function worldMap()
  local f = rawget(_G, "WorldMapFrame")
  if type(f) == "table" and type(f.AddDataProvider) == "function" then return f end
  return nil
end

function WL.enabled()
  local P = Journal.Pages
  if not P or type(P.setting) ~= "function" then return true end
  return P.setting("worldMap") ~= false
end

function WL.setEnabled(on)
  local P = Journal.Pages
  local ok = P and type(P.setSetting) == "function" and P.setSetting("worldMap", on and true or false) or false
  WL.refresh()
  if WL.button then pcall(WL.paintButton) end
  return ok
end

-- places: note pins and place to-do pins; own setting (missing in old saved games = on, whatever the journey switch says)
function WL.placesEnabled()
  local P = Journal.Pages
  if not P or type(P.setting) ~= "function" then return true end
  return P.setting("worldPins") ~= false
end

function WL.setPlacesEnabled(on)
  local P = Journal.Pages
  local ok = P and type(P.setSetting) == "function" and P.setSetting("worldPins", on and true or false) or false
  WL.refresh()
  if WL.buttonPlaces then pcall(WL.paintButton) end
  return ok
end

-- anything to draw at all (journey or places)
function WL.anyEnabled()
  return WL.enabled() or WL.placesEnabled()
end

local function bookPlaying()
  local F = Journal.Frame
  local J = F and F.state
  return J and J.st and J.st.playing and J.frame and J.frame:IsShown() and true or false
end

local function inBox(x, y)
  local m = WL.CULL
  return x >= -m and x <= 1 + m and y >= -m and y <= 1 + m
end

local function clipSeg(x1, y1, x2, y2)
  local Map = Journal.Map
  local m = WL.CULL
  if Map and type(Map.clip) == "function" then
    local ok, a, b, c, d = pcall(Map.clip, x1, y1, x2, y2, -m, -m, 1 + m, 1 + m)
    if ok then return a, b, c, d end
    return nil
  end
  if inBox(x1, y1) and inBox(x2, y2) then return x1, y1, x2, y2 end
  return nil
end

local function markerSize(kind)
  local Theme, Map = Journal.Theme, Journal.Map
  if kind == "milestone" then return (Map and Map.MILESTONE_MARK_SIZE) or 26 end
  if kind == "level" then return (Map and Map.LEVEL_MARK_SIZE) or 18 end
  return (Theme and Theme.MARKER_SIZE and Theme.MARKER_SIZE[kind]) or 22
end

-- Frame.notePins also returns the open place to-dos as { id = "todo:<n>", hint, color } (ids of real notes are numbers)
function WL.isTodoPin(n)
  return type(n) == "table" and type(n.id) == "string" and n.id:sub(1, 5) == "todo:"
end

function WL.build(model, mapID, opts)
  opts = opts or {}
  local View = Journal.View
  if not View or type(View.worldScene) ~= "function" then return nil end
  -- opts.journey / opts.places (default on; opts.notes = false also turns places off). Playback in the book (routeOnly) only
  -- reduces the journey part to the route; without the journey switch it does not matter.
  local journey = opts.journey ~= false
  local places = opts.places ~= false and opts.notes ~= false
  local routeOnly = journey and opts.routeOnly and true or false
  local scene = View.worldScene(model, mapID, { kills = opts.kills, routeOnly = routeOnly or not journey, maxSegments = WL.SEG_MAX,
    allowEmpty = places })
  if not scene then return nil end
  local out = { kind = scene.kind, mapID = scene.mapID, segs = {}, pins = {}, tail = journey and scene.route and scene.route.tail or nil,
    partial = journey and scene.route and scene.route.partial and true or false }
  if type(scene.project) == "function" then
    out.project = scene.project
    out.yards = View.sceneYards and View.sceneYards(scene.mapID) or nil
  end
  local segs = out.segs
  for _, s in ipairs(journey and scene.route and scene.route.segments or {}) do
    if #segs >= WL.SEG_MAX then break end
    local x1, y1, x2, y2 = num(s.x1), num(s.y1), num(s.x2), num(s.y2)
    if x1 and y1 and x2 and y2 then
      local a, b, c, d = clipSeg(x1, y1, x2, y2)
      if a then segs[#segs + 1] = { a, b, c, d, flight = s.kind == "flight" } end
    end
  end
  if routeOnly then return out end

  local pins = out.pins
  local function add(p)
    if #pins >= WL.PIN_MAX then return false end
    pins[#pins + 1] = p
    return true
  end
  for _, e in ipairs(journey and scene.markers or {}) do
    local mk, x, y = e.marker, num(e.vx), num(e.vy)
    if type(mk) == "table" and x and y and inBox(x, y) then
      add({ kind = mk.kind, x = x, y = y, size = markerSize(mk.kind), tip = mk.tip, big = mk.big })
    end
  end
  if places then
    local F = Journal.Frame
    local okN, notes = false, nil
    if F and type(F.notePins) == "function" then okN, notes = pcall(F.notePins, scene) end
    if okN and type(notes) == "table" then
      local P = (Journal.Theme and Journal.Theme.NOTE_PIN) or { size = 26 }
      for _, n in ipairs(notes) do
        local x, y = num(n.vx), num(n.vy)
        if x and y and inBox(x, y) and type(n.title) == "string" then
          if WL.isTodoPin(n) then
            -- place to-do (Vorhaben.mapPins): same pin art, tinted, hover only (no click target, nothing opens)
            add({ kind = "todo", x = x, y = y, size = P.size, color = n.color, tip = { title = n.title, detail = n.hint } })
          else
            add({ kind = "note", id = n.id, x = x, y = y, size = P.size, tip = { title = n.title, detail = WL.TEXT.noteTip } })
          end
        end
      end
    end
  end
  for _, l in ipairs(journey and scene.levelUps or {}) do
    local x, y = num(l.vx), num(l.vy)
    if x and y and inBox(x, y) then add({ kind = "levelup", x = x, y = y, size = WL.MINI_SIZE, tip = l.tip }) end
  end
  local Map = Journal.Map
  local kills = journey and scene.kills or nil
  if kills and num(kills.n) and kills.n > 0 and Map and type(Map.bundleKills) == "function" then
    local ok, list = pcall(Map.bundleKills, kills, WL.KILL_CELL, WL.KILL_CELL, 1)
    if ok and type(list) == "table" then
      local inside = {}
      for _, b in ipairs(list) do
        if num(b.vx) and num(b.vy) and inBox(b.vx, b.vy) then inside[#inside + 1] = b end
      end
      local room = math.min(WL.KILL_MAX, WL.PIN_MAX - #pins)
      if #inside > room and type(Map.pickBundles) == "function" then
        local okP, picked = pcall(Map.pickBundles, inside, math.max(room, 0))
        inside = (okP and type(picked) == "table") and picked or {}
      end
      for _, b in ipairs(inside) do
        local size = 16
        if type(Map.killBase) == "function" then size = Map.killBase(b.n) end
        if not add({ kind = "kill", x = b.vx, y = b.vy, size = size, bundle = b, kills = kills }) then break end
      end
    end
  end
  return out
end

-- Pin mixins for the XML templates. The base MapCanvasPinMixin is mixed in on install because it only exists with the world map.

EveNChronicleWorldPinMixin = {}
EveNChronicleWorldRouteMixin = {}
local PinMixin, RouteMixin = EveNChronicleWorldPinMixin, EveNChronicleWorldRouteMixin

local function try(obj, method, ...)
  local fn = obj and obj[method]
  if type(fn) ~= "function" then return nil end
  local ok, a = pcall(fn, obj, ...)
  if ok then return a end
  return nil
end

-- The XML template sets OnEnter/OnLeave and OnLoad turns mouse motion on, which MapCanvasMixin:AcquirePin asserts against for a
-- new pin (Blizzard_MapCanvas.lua: "pin:GetScript("OnEnter") == nil") unless the pin opts out of the warning. We do it on purpose.
-- Defined on the mixin itself, so fillMixin (only fills nil keys) never lets the base mixin's false answer replace it.
function PinMixin:DisableInheritedMotionScriptsWarning() return true end

function PinMixin:OnLoad()
  try(self, "UseFrameLevelType", WL.FRAME_LEVEL)
  try(self, "SetScalingLimits", 1, WL.SCALE_MIN, WL.SCALE_MAX)
  -- hover only (tooltip); clicks go to the map
  try(self, "SetMouseClickEnabled", false)
  try(self, "SetMouseMotionEnabled", true)
  local shadow = self:CreateTexture(nil, "ARTWORK", nil, -1)
  shadow:SetPoint("CENTER", self, "CENTER", 1, -1.5)
  shadow:Hide()
  local icon = self:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("CENTER", self, "CENTER", 0, 0)
  self.icon, self.shadow = icon, shadow
end

function WL.paintPin(pin, p)
  local Theme, Map = Journal.Theme, Journal.Map
  local icon, shadow = pin.icon, pin.shadow
  if not (Theme and icon) then return end
  local size = num(p.size) or 20
  icon:SetSize(size, size)
  shadow:SetSize(size, size)
  icon:ClearAllPoints()
  if (p.kind == "note" or p.kind == "todo") and Theme.TEX and Theme.TEX.notePin then
    local P = Theme.NOTE_PIN or { tipX = 0.1, tipY = 0.9 }
    icon:SetPoint("CENTER", pin, "CENTER", (0.5 - (P.tipX or 0.1)) * size, ((P.tipY or 0.9) - 0.5) * size)
    icon:SetTexture(Theme.TEX.notePin)
    icon:SetTexCoord(0, 1, 0, 1)
    local c = p.kind == "todo" and type(p.color) == "table" and p.color or nil
    if c and num(c[1]) and num(c[2]) and num(c[3]) then icon:SetVertexColor(c[1], c[2], c[3], 1) else icon:SetVertexColor(1, 1, 1, 1) end
    shadow:Hide()
    return
  end
  icon:SetPoint("CENTER", pin, "CENTER", 0, 0)
  if p.kind == "kill" and Map and type(Map.setKillArt) == "function" then
    Map.setKillArt(icon, shadow)
    shadow:Show()
    return
  end
  shadow:Hide()
  local kind = (p.kind == "levelup") and "level" or p.kind
  if Theme.HAS_MAP_ICONS and Theme.MAP_ICONS and Theme.MAP_ICONS[kind] ~= nil then
    icon:SetTexture(Theme.TEX.mapIcons)
    icon:SetTexCoord(Theme.mapIconCoords(kind))
    icon:SetVertexColor(1, 1, 1, 1)
  else
    local A = Theme.ATLAS or {}
    icon:SetTexture(Theme.TEX.markers)
    icon:SetTexCoord(Theme.atlasCoords(A[kind] or A.level or 0))
    if kind == "level" or kind == "milestone" then Theme.color(icon, Theme.C.gold, 1) else icon:SetVertexColor(1, 1, 1, 1) end
  end
end

function PinMixin:OnAcquired(p)
  self.data = p
  -- only note pins take clicks (they open the note in the book); all others let clicks through to the map
  try(self, "SetMouseClickEnabled", p ~= nil and p.kind == "note")
  local size = num(p and p.size) or 20
  self:SetSize(size, size)
  WL.paintPin(self, p)
  self:SetPosition(p.x, p.y)
end

function PinMixin:OnReleased()
  if self.hover then
    self.hover = false
    local Theme = Journal.Theme
    if Theme and Theme.hideTooltip then Theme.hideTooltip() end
  end
  self.data = nil
end

function WL.showTip(pin)
  local p = pin.data
  local Theme, Map, W = Journal.Theme, Journal.Map, Journal.Widgets
  if not p or not Theme then return end
  if p.kind == "kill" then
    if Map and type(Map.killTip) == "function" and W and W.tip then
      local ok, lines, colors = pcall(Map.killTip, p.kills, p.bundle)
      if ok and type(lines) == "table" then
        lines[#lines + 1] = WL.TEXT.tipSource
        colors = colors or {}
        colors[#lines] = { 0.6, 0.75, 1 }
        W.tip(pin, lines, colors)
      end
    end
  elseif type(p.tip) == "table" then
    Theme.tooltip(pin, p.tip, WL.TEXT.tipSource)
  end
end

function WL.openNotePin(pin, button)
  local p = pin and pin.data
  if not (p and p.kind == "note" and p.id) then return false end
  if button and button ~= "LeftButton" then return false end
  if inCombat() then
    say(WL.TEXT.noteCombat)
    return false
  end
  local wmf = rawget(_G, "WorldMapFrame")
  local hide = rawget(_G, "HideUIPanel")
  if wmf and wmf.IsShown and wmf:IsShown() then
    if type(hide) == "function" then pcall(hide, wmf) else pcall(wmf.Hide, wmf) end
  end
  local A, F = Journal.Access, Journal.Frame
  if A and type(A.isOpen) == "function" and type(A.open) == "function" and not A.isOpen() then pcall(A.open) end
  if F and type(F.openNote) == "function" then
    local ok, r = pcall(F.openNote, p.id)
    return ok and r and true or false
  end
  return false
end

function PinMixin:OnMouseUp(button)
  local ok, err = pcall(WL.openNotePin, self, button)
  if not ok then report(err) end
end

-- newer MapCanvas pins report clicks via OnMouseClickAction
function PinMixin:OnMouseClickAction(button)
  self:OnMouseUp(button)
end

function PinMixin:OnMouseEnter()
  self.hover = true
  local ok, err = pcall(WL.showTip, self)
  if not ok then report(err) end
end

function PinMixin:OnMouseLeave()
  self.hover = false
  local Theme = Journal.Theme
  if Theme and Theme.hideTooltip then Theme.hideTooltip() end
end

-- Route: ONE pin the size of the canvas, with the pooled lines on it. The line width is re-set to WL.ROUTE_PX screen
-- pixels on every zoom.
function RouteMixin:OnLoad()
  try(self, "UseFrameLevelType", WL.FRAME_LEVEL)
  try(self, "SetIgnoreGlobalPinScale", true)
  try(self, "SetMouseClickEnabled", false)
  try(self, "SetMouseMotionEnabled", false)
  try(self, "EnableMouse", false)
  self.lines = {}
end

local function canvasScale(pin)
  local map = try(pin, "GetMap")
  local s = map and num(try(map, "GetCanvasScale"))
  if not s or s <= 0 then s = 1 end
  return s
end

function WL.layoutRoute(pin)
  local map = try(pin, "GetMap")
  local canvas = map and try(map, "GetCanvas")
  local w, h = 0, 0
  if canvas then
    w, h = num(try(canvas, "GetWidth")) or 0, num(try(canvas, "GetHeight")) or 0
  end
  local segs = pin.segs or {}
  local lines = pin.lines
  if w <= 0 or h <= 0 then
    for _, l in ipairs(lines) do l:Hide() end
    return 0
  end
  pin:SetSize(w, h)
  pin.cw, pin.ch, pin.laid = w, h, true
  local Theme = Journal.Theme
  local red = Theme and Theme.C and Theme.C.red or { 0.7, 0.1, 0.1 }
  local blue = Theme and Theme.C and Theme.C.blue or { 0.2, 0.35, 0.7 }
  local s = canvasScale(pin)
  pin.thickScale = s
  local n = 0
  for i, seg in ipairs(segs) do
    if i > WL.SEG_MAX then break end
    local l = lines[i]
    if not l then
      l = pin:CreateLine(nil, "OVERLAY")
      lines[i] = l
    end
    l:SetStartPoint("TOPLEFT", pin, seg[1] * w, -seg[2] * h)
    l:SetEndPoint("TOPLEFT", pin, seg[3] * w, -seg[4] * h)
    if seg.flight then
      l:SetColorTexture(blue[1], blue[2], blue[3], 0.85)
      l:SetThickness(WL.FLIGHT_PX / s)
    else
      l:SetColorTexture(red[1], red[2], red[3], 0.95)
      l:SetThickness(WL.ROUTE_PX / s)
    end
    l.flight = seg.flight
    l:Show()
    n = i
  end
  for i = n + 1, #lines do lines[i]:Hide() end
  pcall(WL.placeTail, pin)
  return n
end

-- Live tail: a thin line from the end of the drawn route (route.tail, in the coordinates of the displayed map) to the player's
-- position, so the route runs on between two model rebuilds. Same rules as the book map (Map.placeTail): only while the last
-- trail point is recent, the player is near it and no blink/port happened (a step beyond max(JUMP_MIN_YD, JUMP_SPEED * s)
-- yards switches the tail of this trail point off; a new trail point brings it back).
function WL.placeTail(pin)
  local line = pin.tailLine
  local function off()
    if line then line:Hide() end
    return false
  end
  local live = pin.live
  local w, h = pin.cw or 0, pin.ch or 0
  if not (live and live.tail and type(live.project) == "function") or w <= 0 or h <= 0 then return off() end
  local View = Journal.View
  if not (View and type(View.livePosition) == "function") then return off() end
  local tail = live.tail
  local tx, ty, tt = num(tail.vx), num(tail.vy), num(tail.t)
  if not (tx and ty) then return off() end
  local lm, lx, ly = View.livePosition()
  if not (lm and lx and ly) then return off() end
  local okP, vx, vy = pcall(live.project, lm, lx, ly)
  vx, vy = okP and num(vx) or nil, okP and num(vy) or nil
  if not (vx and vy) then return off() end
  local now = gt()
  if live.lastX and live.yards then
    local dt = now - (live.lastT or now)
    local dx, dy = (vx - live.lastX) * live.yards[1], (vy - live.lastY) * live.yards[2]
    if math.sqrt(dx * dx + dy * dy) > math.max(WL.JUMP_MIN_YD, WL.JUMP_SPEED * dt) then live.offT = tt end
  end
  live.lastX, live.lastY, live.lastT = vx, vy, now
  if live.offT ~= nil and live.offT == tt then return off() end
  local age = (type(time) == "function" and tt) and (time() - tt) or 0
  local dx, dy = vx - tx, vy - ty
  if age < 0 or age > WL.TAIL_MAX_AGE or (dx == 0 and dy == 0) or dx * dx + dy * dy > WL.TAIL_MAX_VIEW ^ 2 then return off() end
  local a, b, c, d = clipSeg(tx, ty, vx, vy)
  if not a then return off() end
  if not line then
    line = pin:CreateLine(nil, "OVERLAY")
    pin.tailLine = line
  end
  local Theme = Journal.Theme
  local red = Theme and Theme.C and Theme.C.red or { 0.7, 0.1, 0.1 }
  line:SetStartPoint("TOPLEFT", pin, a * w, -b * h)
  line:SetEndPoint("TOPLEFT", pin, c * w, -d * h)
  line:SetColorTexture(red[1], red[2], red[3], 0.95)
  line:SetThickness(WL.ROUTE_PX / canvasScale(pin))
  line:Show()
  return true
end

function WL.thickenRoute(pin)
  local s = canvasScale(pin)
  local old = pin.thickScale or 1
  if math.abs(s - old) / old < 0.05 then return false end
  pin.thickScale = s
  for _, l in ipairs(pin.lines or {}) do
    if l:IsShown() then l:SetThickness((l.flight and WL.FLIGHT_PX or WL.ROUTE_PX) / s) end
  end
  if pin.tailLine and pin.tailLine:IsShown() then pin.tailLine:SetThickness(WL.ROUTE_PX / s) end
  return true
end

function RouteMixin:OnAcquired(segs, live)
  self.segs = segs
  self.live = live
  WL.routePin = self
  local ok, err = pcall(WL.layoutRoute, self)
  if not ok then report(err) end
  self:SetPosition(0.5, 0.5)
end

function RouteMixin:OnReleased()
  self.segs, self.live, self.laid = nil, nil, false
  if WL.routePin == self then WL.routePin = nil end
  for _, l in ipairs(self.lines or {}) do l:Hide() end
  if self.tailLine then self.tailLine:Hide() end
end

function RouteMixin:OnCanvasScaleChanged()
  local base = rawget(_G, "MapCanvasPinMixin")
  if base and type(base.OnCanvasScaleChanged) == "function" then pcall(base.OnCanvasScaleChanged, self) end
  pcall(WL.thickenRoute, self)
end

function RouteMixin:OnCanvasSizeChanged()
  if self.segs then pcall(WL.layoutRoute, self) end
end

local pending = false

local function removeAll(provider)
  local map = provider:GetMap()
  if not map then return end
  try(map, "RemoveAllPinsByTemplate", WL.PIN_TEMPLATE)
  try(map, "RemoveAllPinsByTemplate", WL.ROUTE_TEMPLATE)
end

local function draw(provider, rebuild)
  local map = provider:GetMap()
  if not map then return end
  local on = WL.anyEnabled()
  if on and inCombat() then
    -- Combat: leave the drawn pins alone (no removing, no drawing) and catch up after PLAYER_REGEN_ENABLED. Only pins of another
    -- map than the one now shown are taken away, they would sit in the wrong place.
    pending = true
    local shown = num(try(map, "GetMapID"))
    if WL.stats and WL.stats.mapID and shown ~= WL.stats.mapID then
      removeAll(provider)
      WL.stats = { pins = 0, segs = 0 }
      WL.routePin = nil
    end
    return
  end
  removeAll(provider)
  WL.stats = { pins = 0, segs = 0 }
  WL.routePin = nil
  if not on then return end
  pending = false
  WL.lastDraw = gt()
  -- an empty or partial result is retried by the live tick (WL.retry); a complete draw clears the flag below
  WL.retry = true
  local mapID = num(try(map, "GetMapID"))
  if not mapID then return end
  local View = Journal.View
  local model = View and View.worldModel and View.worldModel(rebuild)
  WL.drawnModel = model
  -- no model or an empty one (new character): no journey, but places (notes, place to-dos) still show. Nothing is missing
  -- then, so no retry every few seconds; the live tick redraws when a new model arrives (drawnModel changes).
  if type(model) ~= "table" then
    WL.retry = false
    return
  end
  if model.empty then WL.retry = false end
  local playing = bookPlaying()
  local kills = true
  if View and type(View.peek) == "function" then
    local okK, v = pcall(View.peek, "showKills")
    if okK and v == false then kills = false end
  end
  local ok, data = pcall(WL.build, model, mapID, { routeOnly = playing, kills = kills, journey = WL.enabled(), places = WL.placesEnabled() })
  if not ok then
    report(data)
    return
  end
  if not data then return end
  if #data.segs > 0 then
    map:AcquirePin(WL.ROUTE_TEMPLATE, data.segs, { tail = data.tail, project = data.project, yards = data.yards })
  end
  for _, p in ipairs(data.pins) do map:AcquirePin(WL.PIN_TEMPLATE, p) end
  WL.stats = { pins = #data.pins, segs = #data.segs, mapID = mapID, kind = data.kind }
  -- keep retrying while the route is only partial (map data missing) or the canvas was not laid out yet
  local pin = WL.routePin
  WL.retry = not model.empty and (data.partial or (#data.segs > 0 and not (pin and pin.laid))) or false
end

-- Live tick: one ticker, only while the world map is open (see header)
function WL.liveTick()
  local wmf, provider = worldMap(), WL.provider
  if not (wmf and provider and wmf.IsShown and wmf:IsShown() and WL.anyEnabled()) then
    WL.stopLive()
    return false
  end
  if inCombat() then return false end
  local now = gt()
  if WL.retry and now - (WL.lastDraw or -huge) >= WL.RETRY_EMPTY then
    provider:RefreshAllData(true)
    return true
  end
  if now >= (WL.nextKick or 0) then
    WL.nextKick = now + WL.REBUILD_EVERY
    local View = Journal.View
    local m = View and type(View.worldModel) == "function" and View.worldModel(true) or nil
    -- a background build redraws via Model.onReady; a synchronous rebuild (no coroutines) delivers a new model right here
    if m and WL.drawnModel and m ~= WL.drawnModel then
      provider:RefreshAllData(false)
      return true
    end
  end
  local pin = WL.routePin
  if pin and pin.segs then
    if not pin.laid then pcall(WL.layoutRoute, pin) else pcall(WL.placeTail, pin) end
  end
  return true
end

function WL.startLive()
  if WL.ticker or type(C_Timer) ~= "table" or type(C_Timer.NewTicker) ~= "function" then return false end
  WL.nextKick = gt() + WL.REBUILD_EVERY
  WL.ticker = C_Timer.NewTicker(WL.LIVE_INTERVAL, function()
    local ok, err = pcall(WL.liveTick)
    if not ok then report(err) end
  end)
  return true
end

function WL.stopLive()
  local t = WL.ticker
  WL.ticker = nil
  if t and type(t.Cancel) == "function" then pcall(t.Cancel, t) end
end

local function newProvider()
  local base = rawget(_G, "MapCanvasDataProviderMixin")
  local P = (type(CreateFromMixins) == "function") and CreateFromMixins(base) or {}
  if type(CreateFromMixins) ~= "function" then for k, v in pairs(base) do P[k] = v end end
  function P:RemoveAllData()
    removeAll(self)
  end
  -- fromOnShow = true: the map was just opened, so the model may trigger a rebuild (background); otherwise only draw the
  -- existing state.
  function P:RefreshAllData(fromOnShow)
    local ok, err = pcall(draw, self, fromOnShow and true or false)
    if not ok then report(err) end
    local wmf = worldMap()
    if wmf and wmf.IsShown and wmf:IsShown() and WL.anyEnabled() then WL.startLive() end
  end
  function P:OnShow()
    WL.nextKick = 0
    if WL.anyEnabled() then WL.startLive() end
  end
  function P:OnHide()
    WL.stopLive()
  end
  function P:OnMapChanged()
    self:RefreshAllData(false)
  end
  return P
end

local function fillMixin(target, base)
  if type(base) ~= "table" then return end
  for k, v in pairs(base) do
    if target[k] == nil then target[k] = v end
  end
end

function WL.available()
  return worldMap() ~= nil
end

function WL.install()
  if WL.provider then return true end
  local wmf = worldMap()
  local baseP, basePin = rawget(_G, "MapCanvasDataProviderMixin"), rawget(_G, "MapCanvasPinMixin")
  if not wmf or type(baseP) ~= "table" or type(basePin) ~= "table" then return false end
  fillMixin(PinMixin, basePin)
  fillMixin(RouteMixin, basePin)
  local provider = newProvider()
  local ok, err = pcall(wmf.AddDataProvider, wmf, provider)
  if not ok then
    report(err)
    return false
  end
  WL.provider = provider
  WL.installToggle(wmf)
  return true
end

function WL.refresh()
  local wmf, p = worldMap(), WL.provider
  if not (wmf and p) then return false end
  if not (wmf.IsShown and wmf:IsShown()) then return false end
  p:RefreshAllData(false)
  return true
end

if Journal.Notes and type(Journal.Notes.onChange) == "function" then
  Journal.Notes.onChange(function() WL.refresh() end)
end
-- To-dos created, completed or deleted while the map is open: Plans.onChange is batched (Plans.CHANGE_DELAY), WL.refresh only
-- redraws while the map is shown
if ns.Plans and type(ns.Plans.onChange) == "function" then
  ns.Plans.onChange(function() WL.refresh() end)
end

local readyQueued = false
local function onModelReady()
  if readyQueued or not WL.provider then return end
  local wmf = worldMap()
  if not (wmf and wmf:IsShown() and WL.anyEnabled()) then return end
  readyQueued = true
  local function run()
    readyQueued = false
    WL.refresh()
  end
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(WL.READY_THROTTLE, run)
  else
    run()
  end
end

-- Toggle on the map edge: entry in the filter menu (Menu API); without it a small button with a book icon

function WL.paintButton()
  local b = WL.button
  if b then
    b.icon:SetDesaturated(not WL.enabled())
    b.icon:SetAlpha(WL.enabled() and 1 or 0.55)
  end
  local c = WL.buttonPlaces
  if c then
    c.icon:SetDesaturated(not WL.placesEnabled())
    c.icon:SetAlpha(WL.placesEnabled() and 1 or 0.55)
  end
end

-- Fallback without the Menu API: one small button per switch at the lower left edge of the map canvas (own child frames)
local function makeButton(parent, x, texture, isOn, toggle, tipOn, tipOff, hint)
  local ok, b = pcall(CreateFrame, "Button", nil, parent)
  if not ok or not b then return nil end
  b:SetSize(28, 28)
  b:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, 8)
  if b.SetFrameLevel and parent.GetFrameLevel then b:SetFrameLevel((parent:GetFrameLevel() or 0) + 20) end
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints(b)
  icon:SetTexture(texture)
  b.icon = icon
  b:SetScript("OnClick", function() toggle(not isOn()) end)
  b:SetScript("OnEnter", function(self)
    local W = Journal.Widgets
    if W and W.tip then W.tip(self, { isOn() and tipOn or tipOff, hint }) end
  end)
  b:SetScript("OnLeave", function(self)
    local W = Journal.Widgets
    if W and W.hideTip then W.hideTip(self) end
  end)
  return b
end

function WL.installToggle(wmf)
  if WL.toggleKind then return WL.toggleKind end
  local M = rawget(_G, "Menu")
  if type(M) == "table" and type(M.ModifyMenu) == "function" then
    local ok = pcall(M.ModifyMenu, WL.MENU_TAG, function(_, root)
      if type(root) ~= "table" or type(root.CreateCheckbox) ~= "function" then return end
      if type(root.CreateDivider) == "function" then root:CreateDivider() end
      root:CreateCheckbox(WL.TEXT.menu, function() return WL.enabled() end, function() WL.setEnabled(not WL.enabled()) end)
      root:CreateCheckbox(WL.TEXT.menuPlaces, function() return WL.placesEnabled() end,
        function() WL.setPlacesEnabled(not WL.placesEnabled()) end)
    end)
    if ok then
      WL.toggleKind = "menu"
      return "menu"
    end
  end
  local parent = wmf.ScrollContainer or wmf
  local Theme = Journal.Theme
  local b = makeButton(parent, 8, "Interface\\AddOns\\InkAndEmbers\\Media\\MinimapIcon", WL.enabled, WL.setEnabled,
    WL.TEXT.buttonOn, WL.TEXT.buttonOff, WL.TEXT.buttonHint)
  if not b then return nil end
  WL.button = b
  WL.buttonPlaces = makeButton(parent, 42, (Theme and Theme.TEX and Theme.TEX.notePin) or "Interface\\AddOns\\InkAndEmbers\\Media\\MinimapIcon",
    WL.placesEnabled, WL.setPlacesEnabled, WL.TEXT.buttonPlacesOn, WL.TEXT.buttonPlacesOff, WL.TEXT.buttonPlacesHint)
  WL.paintButton()
  WL.toggleKind = "button"
  return "button"
end

function WL.openMap(mapID)
  if inCombat() then
    say(WL.TEXT.combat)
    return false, "kampf"
  end
  local wmf = worldMap()
  if not wmf then
    say(WL.TEXT.noMap)
    return false, "keine-karte"
  end
  WL.install()
  if not WL.enabled() then
    local P = Journal.Pages
    if P and type(P.setSetting) == "function" then P.setSetting("worldMap", true) end
    if WL.button then pcall(WL.paintButton) end
  end
  mapID = num(mapID)
  local wasShown = wmf.IsShown and wmf:IsShown() and true or false
  local oldMap = num(try(wmf, "GetMapID"))
  local opened = false
  local open = rawget(_G, "OpenWorldMap")
  if type(open) == "function" then opened = pcall(open, mapID) end
  if not opened or not (wmf.IsShown and wmf:IsShown()) then
    if not wmf:IsShown() then
      local show, toggle = rawget(_G, "ShowUIPanel"), rawget(_G, "ToggleWorldMap")
      if type(show) == "function" then pcall(show, wmf) elseif type(toggle) == "function" then pcall(toggle) else pcall(wmf.Show, wmf) end
    end
    if mapID and type(wmf.SetMapID) == "function" then pcall(wmf.SetMapID, wmf, mapID) end
  end
  if not wmf:IsShown() then
    say(WL.TEXT.noMap)
    return false, "keine-karte"
  end
  if wasShown and (mapID == nil or mapID == oldMap) then WL.refresh() end
  return true
end

if ns.Core and ns.Core.on then
  ns.Core.on("PLAYER_LOGIN", function() WL.install() end)
  ns.Core.on("ADDON_LOADED", function(_, name)
    if name == "Blizzard_WorldMap" then WL.install() end
  end)
  ns.Core.on("PLAYER_REGEN_ENABLED", function()
    if pending then WL.refresh() end
  end)
  -- new zone / loading screen: the next live tick asks the model for new data at once
  local function soon() WL.nextKick = 0 end
  ns.Core.on("ZONE_CHANGED_NEW_AREA", soon)
  ns.Core.on("PLAYER_ENTERING_WORLD", soon)
end
if Journal.View and Journal.View.onModelReady then Journal.View.onModelReady(onModelReady) end
