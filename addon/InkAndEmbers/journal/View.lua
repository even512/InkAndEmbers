-- Adapter between the UI and the model. The ONLY place where the UI calls ns.Journal.Model and ns.Journal.Geo; Frame, Map,
-- Playback and Access only know View. No frame code, and no text from the SV is generated here (pass-through only).
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local View = {}
Journal.View = View

local floor, huge = math.floor, math.huge

local T = ns.Locale.ns("View", {
  startNote = "Die Reise beginnt hier.",
  zeroMin = "0 Min.",
})

View.POLL = 2.5
View.READY_THROTTLE = 2.5
View.GLOW_GROUP = 6
View.FOCUS_PAD = 0.12
View.FOCUS_MIN = 0.04
View.OVERVIEW_MIN = 0.22

View.OVERLAY_MAX = 400

View.status, View.model, View.stale, View.reason = "idle", nil, false, nil
View.active = false
-- Twinks: guid of the other character whose book is open read-only (View.setGuest), nil = own book. The book map then asks
-- Model.get for that guid and shows no live position, tail or arrow; the world map layer (View.worldModel, View.livePosition)
-- always stays with the logged-in character.
View.guest = nil

local PENDING = { pending = true, laeuft = true, ["läuft"] = true, building = true, aufbau = true, loading = true }
local STALE = { stale = true, veraltet = true, alt = true }

local function Model() return Journal.Model end
local function Geo() return Journal.Geo end

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == huge or v == -huge then return nil end
  return v
end

function View.classify(ok, m, why)
  if not ok then return "error", nil, false end
  if type(m) == "table" then
    return "ready", m, (STALE[why] == true) or m.stale == true
  end
  if PENDING[why] then return "loading", nil, false end
  if why == "keine-daten" or why == "kein-charakter" then return "nodata", nil, false end
  return "error", nil, false
end

local listener

function View.onChange(fn) listener = fn end

local function notify()
  if listener then
    local ok, err = pcall(listener, View.status, View.model, View.stale)
    if not ok and ns.Core then ns.Core.coreError(err) end
  end
end

local ticker
local function unwatch()
  if ticker then
    ticker:Cancel()
    ticker = nil
  end
end

local subscribed = false

local function watch()
  if ticker or not View.active then return end
  if subscribed and View.status == "ready" then return end
  ticker = C_Timer.NewTicker(View.POLL, function()
    if not View.active then return unwatch() end
    View.request()
  end)
end

-- Ready signal (Model.onReady). The observer does NOT call Model.get again (while walking the signature changes constantly,
-- causing endless rebuilds) but takes the delivered model, only while the window is open and at most every View.READY_THROTTLE s.
local pendingModel, applyQueued, lastApply = nil, false, -huge

local function now() return type(GetTime) == "function" and GetTime() or 0 end

local function applyReady()
  applyQueued = false
  local m = pendingModel
  pendingModel = nil
  if not View.active or type(m) ~= "table" then return end
  lastApply = now()
  local changed = (View.model ~= m) or View.status ~= "ready" or View.stale ~= (m.stale == true)
  View.status, View.model, View.stale, View.reason = "ready", m, m.stale == true, nil
  if not View.stale then unwatch() end
  if changed then notify() end
end

function View.onReadySignal(model)
  if not View.active then return end
  pendingModel = model
  if applyQueued then return end
  applyQueued = true
  local wait = View.READY_THROTTLE - (now() - lastApply)
  C_Timer.After(wait > 0 and wait or 0, applyReady)
end

function View.subscribe()
  local M = Model()
  if subscribed or not M then return end
  local fn = M.onReady
  if type(fn) == "function" then
    subscribed = pcall(fn, function(model)
      if View.guest == nil then View.onReadySignal(model) end
    end) and true or false
  end
  if subscribed and type(M.onGuestReady) == "function" then
    pcall(M.onGuestReady, function(model, guid)
      if View.guest ~= nil and guid == View.guest then View.onReadySignal(model) end
    end)
  end
end

-- guid of another character (read-only book) or nil (back to the own book). Drops the shown model so the next
-- View.request asks for the right character; never touches the own model slot. -> true when the mode changed
function View.setGuest(guid)
  if guid ~= nil and (type(guid) ~= "string" or guid == "") then return false end
  if guid == View.guest then return false end
  View.guest = guid
  pendingModel = nil
  View.status, View.model, View.stale, View.reason = "idle", nil, false, nil
  unwatch()
  return true
end

-- live position for the book map: none while a guest book is open
local function bookPosition()
  if View.guest ~= nil then return nil end
  return View.livePosition()
end

function View.request(opts)
  local M = Model()
  if View.guest ~= nil and (opts == nil or opts.guid == nil) then
    local o = { guid = View.guest }
    for k, v in pairs(opts or {}) do o[k] = v end
    o.guid = View.guest
    opts = o
  end
  local status, model, stale, why
  if not M or type(M.get) ~= "function" then
    status = "error"
  else
    local ok, m, w = pcall(M.get, opts)
    why = ok and w or nil
    status, model, stale = View.classify(ok, m, w)
    if not ok or status == "error" then
      local detail = (not ok and m) or M.lastError
      if detail and ns.Core then ns.Core.coreError("Reisejournal: " .. tostring(detail)) end
    end
  end
  if status == "loading" and View.model then
    status, model, stale = "ready", View.model, true
  end
  local changed = (status ~= View.status) or (model ~= View.model) or (stale ~= View.stale)
  View.status, View.model, View.stale, View.reason = status, model, stale and true or false, why
  if status == "loading" or View.stale then watch() else unwatch() end
  if changed then notify() end
  return status, model, changed
end

function View.setActive(on)
  View.active = on and true or false
  if View.active then
    View.subscribe()
  else
    unwatch()
    pendingModel = nil
    View.status, View.model, View.stale, View.reason = "idle", nil, false, nil
  end
end

function View.isWatching() return ticker ~= nil end

function View.prepare()
  local M = Model()
  local fn = M and M.prepare
  if type(fn) ~= "function" then return false end
  local ok, err = pcall(fn)
  if not ok and ns.Core then ns.Core.coreError(err) end
  return ok
end

View.PREPARE_DELAY = 15
local prepPlanned, prepWaiting = false, false

local function runPrepare()
  if type(InCombatLockdown) == "function" and InCombatLockdown() then
    prepWaiting = true
    return
  end
  prepWaiting = false
  View.prepare()
end

function View.combatEnded()
  if prepWaiting then runPrepare() end
end

function View.prepareAfterLogin(delay)
  local M = Model()
  if M and type(M.prepareAfterLogin) == "function" then
    local ok, res = pcall(M.prepareAfterLogin, delay)
    return ok and res and true or false
  end
  if prepPlanned or type(C_Timer) ~= "table" then return false end
  prepPlanned = true
  C_Timer.After(delay or View.PREPARE_DELAY, runPrepare)
  return true
end

-- Read without creating (login, minimap): falls back to the defaults. If a ui table exists, its values pass the same checks as
-- on write (Model.settings), so a hand-edited or foreign-addon-modified SV cannot stop the window from opening.
function View.peek(key)
  local M = Model()
  local defaults = M and M.UI_DEFAULTS or {}
  local db = EveNChronicleDB
  local ui = type(db) == "table" and type(db.ui) == "table" and db.ui or nil
  if ui then
    local ok, checked = false, nil
    if M and type(M.settings) == "function" then ok, checked = pcall(M.settings) end
    ui = (ok and type(checked) == "table") and checked or nil
  end
  local v = ui and ui[key]
  if key == "pos" then
    if type(v) == "table" and type(v.point) == "string" and num(v.x) and num(v.y) then return v end
    return nil
  end
  if v == nil or type(v) ~= type(defaults[key]) then return defaults[key] end
  if type(v) == "number" and not num(v) then return defaults[key] end
  return v
end

function View.scaleChosen()
  local M = Model()
  if not M or type(M.settings) ~= "function" or type(EveNChronicleDB) ~= "table" then return false end
  local ok, ui = pcall(M.settings)
  return ok and type(ui) == "table" and ui.scaleSet == true
end

function View.set(key, value)
  local M = Model()
  if not M or type(M.setSetting) ~= "function" then return false end
  local ok, res = pcall(M.setSetting, key, value)
  return ok and res == true
end

function View.speeds()
  return { 20, 60, 180 }
end

local function call(name, ...)
  local M = Model()
  local fn = M and M[name]
  if type(fn) ~= "function" then return nil end
  local ok, a = pcall(fn, ...)
  if ok then return a end
  return nil
end

function View.playedAt(model, t) return call("playedAt", model, t) end
function View.timeAt(model, p) return call("timeAt", model, p) end
function View.chapterAt(model, t) return call("chapterAt", model, t) end
function View.actAt(model, t) return call("actAt", model, t) end
-- K2 replay: main zone at time t (Model.zoneAt, flown-over zones skipped) and the flight running at t (start, landing)
function View.zoneAtTime(model, t)
  local M = Model()
  if not (M and type(M.zoneAt) == "function") then return nil end
  local ok, z, a, b = pcall(M.zoneAt, model, t)
  if not ok then return nil end
  return num(z), num(a), num(b)
end
function View.flightAt(model, t)
  local M = Model()
  if not (M and type(M.flightAt) == "function") then return nil end
  local ok, a, b = pcall(M.flightAt, model, t)
  if not ok or not num(a) or not num(b) then return nil end
  return a, b
end
function View.continentOf(mapID)
  local G = Geo()
  if not (G and G.continentOf and num(mapID)) then return nil end
  local ok, c = pcall(G.continentOf, mapID)
  return ok and num(c) or nil
end
function View.formatWhen(model, t) return call("formatWhen", model, t) end
function View.toAxis(model, p)
  local q = call("toAxis", model, p)
  if type(q) == "number" then return q end
  return p
end
function View.fromAxis(model, q)
  local p = call("fromAxis", model, q)
  if type(p) == "number" then return p end
  return q
end
-- Levels of a section for the values table: "1 – 3" for level-ups, else "3" (the arrow is missing in some client fonts,
-- hence the dash); nil without numbers
function View.levelSpan(from, to)
  from, to = num(from), num(to)
  if not from then return nil end
  from = floor(from)
  if to and floor(to) > from then return from .. " – " .. floor(to) end
  return tostring(from)
end

function View.formatPlayed(sec)
  return call("formatPlayed", sec) or T.zeroMin
end

function View.routeOpts(project, key, maxSegments, affine)
  return { project = project, key = key, maxSegments = maxSegments, affine = affine }
end

function View.livePosition()
  if type(C_Map) ~= "table" or type(C_Map.GetBestMapForUnit) ~= "function" then return nil end
  local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
  map = ok and num(map) or nil
  if not map then return nil end
  local x, y
  if type(C_Map.GetPlayerMapPosition) == "function" then
    local ok2, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if ok2 and type(pos) == "table" and not isSecret(pos) and type(pos.GetXY) == "function" then
      local ok3, a, b = pcall(pos.GetXY, pos)
      if ok3 then x, y = num(a), num(b) end
    end
  end
  return map, x, y
end

-- Size of a map in world yards { w, h } for the live tail's jump detection (a view unit is one map width/height); nil if unknown.
function View.sceneYards(mapID)
  local G = Geo()
  if not (G and G.mapSize and mapID) then return nil end
  local ok, w, h = pcall(G.mapSize, mapID)
  w, h = ok and num(w) or nil, ok and num(h) or nil
  if w and h and w > 0 and h > 0 then return { w, h } end
  return nil
end

-- Facing of the player in radians (0 = north, counter-clockwise, like Texture:SetRotation); nil if unknown or secret.
function View.facing()
  if type(GetPlayerFacing) ~= "function" then return nil end
  local ok, f = pcall(GetPlayerFacing)
  return ok and num(f) or nil
end

-- Live arrow of a built scene (Map's live tick; no rebuild). -> vx, vy, facing | false (the player is not on the shown map:
-- hide the arrow) | nil (no usable position right now: leave the arrow as it is).
function View.liveHead(scene)
  if type(scene) ~= "table" or type(scene.project) ~= "function" then return nil end
  local lm, lx, ly = bookPosition()
  if not lm then return nil end
  if scene.mode ~= "continent" and scene.mode ~= "zone" and lm ~= scene.mapID then return false end
  local known = lx and ly
  local ok, vx, vy = pcall(scene.project, lm, lx or 0.5, ly or 0.5)
  if not (ok and num(vx) and num(vy)) then return false end
  if not known then return nil end
  return vx, vy, View.facing()
end

local function contFromKey(key)
  return type(key) == "string" and tonumber(string.match(key, "^geo:(%d+)$")) or nil
end

local function rectOf(mapID, contID)
  local G = Geo()
  if not (G and G.rect and mapID and contID) then return nil end
  local ok, a, b, c, d = pcall(G.rect, mapID, contID)
  if ok and num(a) and num(b) and num(c) and num(d) and b > a and d > c then
    return { x0 = a, x1 = b, y0 = c, y1 = d }
  end
  return nil
end

function View.bounds(scene, extra, minSize)
  local x0, y0, x1, y1 = huge, huge, -huge, -huge
  local function add(x, y)
    if x and y then
      if x < x0 then x0 = x end
      if x > x1 then x1 = x end
      if y < y0 then y0 = y end
      if y > y1 then y1 = y end
    end
  end
  for _, s in ipairs(scene.route and scene.route.segments or {}) do
    add(s.x1, s.y1)
    add(s.x2, s.y2)
  end
  for _, m in ipairs(scene.markers or {}) do add(m.vx, m.vy) end
  if extra then add(extra.vx, extra.vy) end
  if x0 == huge then return nil end
  local w, h = x1 - x0, y1 - y0
  local size = math.max(w, h, minSize or View.FOCUS_MIN)
  local padX = math.max(w, size * 0.5) * View.FOCUS_PAD + (size - w) / 2
  local padY = math.max(h, size * 0.5) * View.FOCUS_PAD + (size - h) / 2
  return { x0 = x0 - padX, x1 = x1 + padX, y0 = y0 - padY, y1 = y1 + padY }
end

local WHOLE = { x0 = 0, x1 = 1, y0 = 0, y1 = 1 }

function View.viewFor(model, sel)
  sel = sel or {}
  if sel.chapter and model.chapters and model.chapters[sel.chapter] then return { chapter = sel.chapter } end
  local act = sel.act and model.acts and model.acts[sel.act]
  if act then
    local cont = num(act.continentID) or View.continentOf(View.zoneFor(model, sel))
    if cont then return { continent = cont } end
  end
  if sel.zone then return { zone = sel.zone } end
  if sel.map then return { map = sel.map } end
  if sel.continent then return { continent = sel.continent } end
  local c1 = model.continents and model.continents[1]
  if c1 and c1.id then return { continent = c1.id } end
  return { all = true }
end

local function projector(model, view)
  local M = Model()
  local ok, project, key, mode, map, affine = pcall(M.projectorFor, model, view)
  if not ok or type(project) ~= "function" then return nil end
  return project, key, mode, map, type(affine) == "function" and affine or nil
end

local function emptyList() return {} end

-- Mini icons of the route: kill positions and level-ups without their own marker. Kill marks only exist on the zone map
-- (too many and too coarse on the continent map); level-ups show on every map.
local function addMinis(scene, model, view, project, key, withKills)
  local M = Model()
  if withKills and M and type(M.killsIn) == "function" then
    local ok, kills = pcall(M.killsIn, model, view, project, key)
    scene.kills = (ok and type(kills) == "table") and kills or nil
  end
  if M and type(M.levelUpsIn) == "function" then
    local ok, lv = pcall(M.levelUpsIn, model, view, project)
    scene.levelUps = (ok and type(lv) == "table") and lv or emptyList()
  end
end

local function emptyScene(model, sel)
  local G = Geo()
  local map, x, y = bookPosition()
  if not map and model.current then map, x, y = model.current.mapID, model.current.x, model.current.y end
  local scene = { sel = sel or {}, empty = true, markers = {}, gaps = {}, route = { segments = {}, count = 0 },
    range = { 0, 0 } }
  local cont
  if map and G and G.continentOf then
    local ok, c = pcall(G.continentOf, map)
    cont = ok and num(c) or nil
  end
  local zoneRect = cont and rectOf(map, cont)
  if cont and zoneRect and G.projector then
    local project, key = G.projector(cont)
    scene.view, scene.mode, scene.contID, scene.project, scene.key = { continent = cont }, "continent", cont, project, key
    scene.focus = zoneRect
  else
    scene.view = map and { map = map } or { all = true }
    scene.mode, scene.mapID = "map", map
    scene.project = function(_, px, py) return px, py end
    scene.key = "map:" .. (map and string.format("%d", floor(map)) or "-")
    scene.focus = WHOLE
  end
  if map and x and y then
    local ok, vx, vy = pcall(scene.project, map, x, y)
    if ok and num(vx) and num(vy) then
      scene.current = { vx = vx, vy = vy, facing = bookPosition() and View.facing() or nil }
    end
  end
  scene.live = View.guest == nil -- no live tick in a guest book
  scene.notes = { { text = T.startNote, kind = "start", vx = scene.current and scene.current.vx,
    vy = scene.current and scene.current.vy } }
  return scene
end

function View.zoneFor(model, sel)
  sel = sel or {}
  if sel.continent or sel.map then return nil end
  local chapters = model.chapters or {}
  if sel.chapter then
    local c = chapters[sel.chapter]
    return c and num(c.zoneID) or nil
  end
  -- an act starts in the zone of its first station (K2: the click jumps to the start of the act)
  local act = sel.act and model.acts and model.acts[sel.act]
  if act then
    local z = num(act.t0) and View.zoneAtTime(model, act.t0)
    local c = chapters[act.first]
    return z or (c and num(c.zoneID)) or num(act.zoneID)
  end
  if sel.zone then return num(sel.zone) end
  local M = Model()
  local function zoneOfMap(map)
    if not map then return nil end
    local z
    if M and type(M.zoneOf) == "function" then
      local ok, v = pcall(M.zoneOf, model, map)
      z = ok and num(v) or nil
    end
    return z or map
  end
  local lm = bookPosition()
  local z = zoneOfMap(lm) or zoneOfMap(model.current and num(model.current.mapID))
  if z then return z end
  local last = chapters[#chapters]
  return last and num(last.zoneID) or nil
end

-- Exploration overlay tiles (C_MapExplorationInfo.GetExploredMapTextures) in map pixels of the zone art, like Blizzard's map
-- frame: tiles of tileW x tileH, the last column/row sits in a file of the next power of two (from 16), so texcoords u1/v1 < 1.
-- Only uncovered pieces; hover highlights are dropped.
function View.overlayTiles(entries, tileW, tileH, max)
  local out = {}
  if type(entries) ~= "table" or isSecret(entries) then return out end
  max = max or View.OVERLAY_MAX
  local function pow2(n)
    local f = 16
    while f < n do f = f * 2 end
    return f
  end
  for _, e in ipairs(entries) do
    if #out >= max then break end
    if type(e) == "table" and not isSecret(e) and not e.isShownByMouseOver then
      local tw, th, ox, oy = num(e.textureWidth), num(e.textureHeight), num(e.offsetX), num(e.offsetY)
      local files = e.fileDataIDs
      if tw and th and ox and oy and tw > 0 and th > 0 and type(files) == "table" and not isSecret(files) then
        local cols, rows = math.ceil(tw / tileW), math.ceil(th / tileH)
        for j = 1, rows do
          local ph = (j < rows) and tileH or (th % tileH)
          if ph == 0 then ph = tileH end
          local fh = (j < rows) and tileH or pow2(ph)
          for k = 1, cols do
            local pw = (k < cols) and tileW or (tw % tileW)
            if pw == 0 then pw = tileW end
            local fw = (k < cols) and tileW or pow2(pw)
            local file = files[(j - 1) * cols + k]
            if (type(file) == "number" or type(file) == "string") and not isSecret(file) and #out < max then
              local x0, y0 = ox + tileW * (k - 1), oy + tileH * (j - 1)
              out[#out + 1] = { file = file, x0 = x0, y0 = y0, x1 = x0 + pw, y1 = y0 + ph, u1 = pw / fw, v1 = ph / fh,
                top = e.isDrawOnTopLayer and true or false }
            end
          end
        end
      end
    end
  end
  return out
end

-- reveal = true (setting revealMap): the whole zone uncovered, overlays from OpenQuests.overlays (same way as the open-quests
-- page). Without data for the zone the explored overlays stay.
function View.zoneArt(zoneID, reveal)
  local art = View.mapArt(zoneID)
  if not art then return nil end
  local valid = false
  for _, f in ipairs(art.files) do
    if (type(f) == "number" and f > 0) or (type(f) == "string" and f ~= "") then valid = true break end
  end
  if not valid then return nil end
  art.overlays = {}
  local E = C_MapExplorationInfo
  if type(E) == "table" and type(E.GetExploredMapTextures) == "function" then
    local ok, entries = pcall(E.GetExploredMapTextures, zoneID)
    if ok then art.overlays = View.overlayTiles(entries, art.tileW, art.tileH) end
  end
  if reveal then
    local OQ = Journal.OpenQuests
    if type(OQ) == "table" and type(OQ.overlays) == "function" then
      local okA, all = pcall(OQ.overlays, zoneID)
      if okA and type(all) == "table" and next(all) ~= nil then
        local okT, tiles = pcall(View.overlayTiles, all, art.tileW, art.tileH)
        if okT and type(tiles) == "table" and #tiles > 0 then art.overlays = tiles end
      end
    end
  end
  return art
end

-- K2: played-seconds range of a selection (chapter, else act); nil for the whole journey
function View.selRange(model, sel)
  sel = sel or {}
  local c = sel.chapter and model.chapters and model.chapters[sel.chapter]
  if c and num(c.p0) and num(c.p1) and c.p1 > c.p0 then return c.p0, c.p1 end
  local a = sel.act and model.acts and model.acts[sel.act]
  if a and num(a.p0) and num(a.p1) and a.p1 > a.p0 then return a.p0, a.p1 end
  return nil
end

-- start (epoch) of the selected chapter or act; nil without one
function View.selStart(model, sel)
  sel = sel or {}
  local c = sel.chapter and model.chapters and model.chapters[sel.chapter]
  if c then return num(c.t0) end
  local a = sel.act and model.acts and model.acts[sel.act]
  return a and num(a.t0) or nil
end

local function within(p, a, b)
  p = num(p)
  return p ~= nil and p >= a and p <= b
end

-- Restricts route, markers, gaps, level-ups and kills of a scene to the played seconds a..b (act, or a chapter shown on another
-- zone's map while replaying). New tables: the model's memoised results stay untouched.
function View.clipRange(scene, model, a, b)
  local r = scene.route or {}
  local segs = {}
  for _, s in ipairs(r.segments or {}) do
    local s0, s1 = num(s.p0) or num(s.p) or 0, num(s.p) or num(s.p0) or 0
    if s1 >= a and s0 <= b then segs[#segs + 1] = s end
  end
  local total = model.timeline and num(model.timeline.total) or 0
  scene.route = { segments = segs, count = #segs, points = r.points, tolerance = r.tolerance, truncated = r.truncated,
    partial = r.partial, failed = r.failed, tail = (b >= total) and r.tail or nil }
  local function keep(list, pOf)
    local out = {}
    for _, e in ipairs(list or {}) do
      if within(pOf(e), a, b) then out[#out + 1] = e end
    end
    return out
  end
  scene.markers = keep(scene.markers, function(e) return e.marker and e.marker.p end)
  scene.gaps = keep(scene.gaps, function(e) return e.gap and e.gap.p0 end)
  if scene.levelUps then scene.levelUps = keep(scene.levelUps, function(e) return e.p end) end
  local k = scene.kills
  if type(k) == "table" and type(k.n) == "number" then
    local o = { n = 0, vx = {}, vy = {}, p = {}, t = {}, id = {}, lv = {}, name = k.name, stamp = k.stamp }
    for i = 1, k.n do
      if within(k.p[i], a, b) then
        local n = o.n + 1
        o.n = n
        o.vx[n], o.vy[n], o.p[n], o.t[n], o.id[n], o.lv[n] = k.vx[i], k.vy[i], k.p[i], k.t[i], k.id[i], k.lv[i]
      end
    end
    scene.kills = o
  end
  return scene
end

-- margin notes of a range: the best notes of its chapters (Model.notes per chapter, memoised there), at most Model.NOTES_MAX
local function rangeNotes(model, sel, project)
  local M = Model()
  local list = {}
  local act = sel.act and model.acts and model.acts[sel.act]
  local ids = sel.chapter and { sel.chapter } or (act and act.chapters) or {}
  for _, i in ipairs(ids) do
    local ok, notes = pcall(M.notes, model, { chapter = i }, project)
    if ok and type(notes) == "table" then
      for _, n in ipairs(notes) do list[#list + 1] = n end
    end
  end
  table.sort(list, function(x, y)
    if (x.score or 0) ~= (y.score or 0) then return (x.score or 0) > (y.score or 0) end
    return (x.t or 0) < (y.t or 0)
  end)
  local max = (M and M.NOTES_MAX) or 3
  for i = #list, max + 1, -1 do list[i] = nil end
  return list
end

local function zoneScene(model, sel, opts)
  local G, M = Geo(), Model()
  if not (G and G.zoneProjector and M) then return nil end
  local reveal = View.peek("revealMap") == true
  -- opts.zone: the replay shows another zone than the selection (K2 zone change); without art for it the selection's zone
  local zone, art = opts and num(opts.zone), nil
  if zone then
    art = View.zoneArt(zone, reveal)
    if not art then zone = nil end
  end
  if not zone then
    zone = View.zoneFor(model, sel)
    if not zone then return nil end
    art = View.zoneArt(zone, reveal)
    if not art then return nil end
  end
  local project, key, affine = G.zoneProjector(zone)
  local chap = sel.chapter and model.chapters[sel.chapter]
  local view = (chap and chap.zoneID == zone) and { chapter = sel.chapter } or { zone = zone }
  local ra, rb = View.selRange(model, sel)
  local scene = { sel = sel, mode = "zone", zoneID = zone, art = art, project = project, key = key, affine = affine,
    view = view, focus = WHOLE, clip = WHOLE }
  if G.continentOf then
    local ok, c = pcall(G.continentOf, zone)
    scene.contID = ok and num(c) or nil
  end
  local okR, route = pcall(M.route, model, view, View.routeOpts(project, key, nil, affine))
  scene.route = (okR and type(route) == "table") and route or { segments = {}, count = 0 }
  local okM, markers = pcall(M.markersIn, model, view, project)
  scene.markers = okM and markers or emptyList()
  local okG, gaps = pcall(M.gapsIn, model, view, project)
  scene.gaps = okG and gaps or emptyList()
  if ra and not view.chapter then
    scene.notes = rangeNotes(model, sel, project)
  else
    local okN, notes = pcall(M.notes, model, view, project)
    scene.notes = okN and notes or emptyList()
  end
  for _, n in ipairs(scene.notes) do
    if n.t and not n.p then n.p = call("playedAt", model, n.t) end
  end
  addMinis(scene, model, view, project, key, true)
  if ra and not view.chapter then View.clipRange(scene, model, ra, rb) end
  local lm, lx, ly = bookPosition()
  local cur
  if lm and lx and ly then cur = { mapID = lm, x = lx, y = ly } else cur = model.current end
  if cur then
    local ok, vx, vy = pcall(project, cur.mapID, cur.x, cur.y)
    if ok and num(vx) and num(vy) then
      scene.current = { vx = vx, vy = vy, facing = (lm and lx and ly) and View.facing() or nil }
    end
  end
  scene.live = View.guest == nil -- no live tick in a guest book
  scene.yards = View.sceneYards(zone)
  local total = model.timeline and num(model.timeline.total) or 0
  scene.range = ra and { ra, rb } or { 0, total }
  scene.chapter = chap and sel.chapter or nil
  scene.act = sel.act
  scene.empty = (scene.route.count or 0) == 0 and #scene.markers == 0
  return scene
end

-- Scene for model + selection. sel = nil | { chapter = i } | { zone = id } | { continent = id } | { map = id }.
-- opts.mode = "zone" (default) | "continent". Without zone art the continent view is used (scene.zoneFallback = true).
function View.scene(model, sel, opts)
  sel = sel or {}
  local M = Model()
  if model.empty then return emptyScene(model, sel) end
  local wantZone = not (opts and opts.mode == "continent")
  if wantZone then
    local ok, zs = pcall(zoneScene, model, sel, opts)
    if ok and zs then return zs end
    if not ok and ns.Core then ns.Core.coreError("Reisejournal (Zonenkarte): " .. tostring(zs)) end
  end
  local view = View.viewFor(model, sel)
  -- K2: a flight while replaying an act/chapter shows its continent (opts.continent); an act on the continent map likewise
  -- (the act's chapters are cut to its time range below)
  local ra, rb = View.selRange(model, sel)
  local flight = opts and num(opts.continent) and true or false
  if flight then view = { continent = opts.continent } end
  local project, key, mode, map, affine = projector(model, view)
  if not project then
    project, key, mode = function(_, x, y) return x, y end, "map:-", "map"
  end
  local scene = { sel = sel, mode = mode, project = project, key = key, affine = affine }
  if mode == "continent" then
    scene.contID = contFromKey(key) or view.continent
      or (view.chapter and model.chapters[view.chapter] and model.chapters[view.chapter].continentID)
  else
    map = view.map or map
    if map then view = { map = map } end
    scene.mapID = map
  end
  scene.view = view

  local okR, route = pcall(M.route, model, view, View.routeOpts(project, key, nil, affine))
  scene.route = (okR and type(route) == "table") and route or { segments = {}, count = 0 }
  local okM, markers = pcall(M.markersIn, model, view, project)
  scene.markers = okM and markers or emptyList()
  local okG, gaps = pcall(M.gapsIn, model, view, project)
  scene.gaps = okG and gaps or emptyList()
  local ranged = ra and not view.chapter
  if ranged then
    scene.notes = rangeNotes(model, sel, project)
  else
    local okN, notes = pcall(M.notes, model, view, project)
    scene.notes = okN and notes or emptyList()
  end
  for _, n in ipairs(scene.notes) do
    if n.t and not n.p then n.p = call("playedAt", model, n.t) end
  end
  addMinis(scene, model, view, project, key, mode ~= "continent")
  if ranged then View.clipRange(scene, model, ra, rb) end

  local lm, lx, ly = bookPosition()
  local cur
  if lm and lx and ly then cur = { mapID = lm, x = lx, y = ly } else cur = model.current end
  if cur and (mode == "continent" or cur.mapID == scene.mapID) then
    local ok, vx, vy = pcall(project, cur.mapID, cur.x, cur.y)
    if ok and num(vx) and num(vy) then
      scene.current = { vx = vx, vy = vy, facing = (lm and lx and ly) and View.facing() or nil }
    end
  end
  scene.live = View.guest == nil -- no live tick in a guest book
  scene.yards = View.sceneYards(mode == "continent" and scene.contID or scene.mapID)

  local focus
  local fp = flight and opts.flightP
  if flight and type(fp) == "table" and num(fp[1]) and num(fp[2]) then
    -- the flight itself (with a margin), so route and arrow of the flight fill the map
    local segs = {}
    for _, s in ipairs(scene.route.segments) do
      if (num(s.p) or 0) >= fp[1] and (num(s.p0) or 0) <= fp[2] then segs[#segs + 1] = s end
    end
    focus = View.bounds({ route = { segments = segs } }, nil, View.OVERVIEW_MIN)
  end
  if focus then
    -- set above (flight)
  elseif mode == "continent" and ((opts and opts.whole) or sel.continent) then
    focus = WHOLE
  elseif mode == "continent" and ranged then
    focus = View.bounds(scene, nil, View.OVERVIEW_MIN)
  elseif mode == "continent" and (view.chapter or view.zone) then
    local zone = view.zone or (model.chapters[view.chapter] and model.chapters[view.chapter].zoneID)
    focus = rectOf(zone, scene.contID)
    if not focus then focus = View.bounds(scene) end
  elseif mode == "map" and sel.chapter then
    focus = View.bounds(scene, scene.current)
  else
    focus = View.bounds(scene, scene.current, View.OVERVIEW_MIN)
  end
  scene.focus = focus or WHOLE

  local total = model.timeline and num(model.timeline.total) or 0
  scene.range = ra and { ra, rb } or { 0, total }
  scene.chapter = (sel.chapter and model.chapters[sel.chapter]) and sel.chapter or nil
  scene.act = sel.act
  scene.flight = flight or nil
  scene.zoneFallback = wantZone and not sel.continent or nil
  scene.empty = (scene.route.count or 0) == 0 and #scene.markers == 0
  if scene.empty then
    scene.notes = { { text = T.startNote, kind = "start", vx = scene.current and scene.current.vx,
      vy = scene.current and scene.current.vy } }
  end
  return scene
end

function View.mapName(mapID)
  if not mapID or type(C_Map) ~= "table" or type(C_Map.GetMapInfo) ~= "function" then return nil end
  local ok, info = pcall(C_Map.GetMapInfo, mapID)
  if not ok or type(info) ~= "table" or isSecret(info) then return nil end
  local S = ns.Sanitize
  return S and S.display and S.display(info.name, 40) or nil
end

-- Zone under a point of the continent map (hover/click like Blizzard's world map): C_Map.GetMapInfoAtPosition(contID, x, y).
-- World/continent (mapType < 3) and the map itself do not count; a sub-map (cave, district) becomes its main zone (Geo.zoneOf).
-- -> { id = zoneID, name = sanitized display name | nil } | nil. Secret values = nil.
function View.zoneInfoAt(contID, vx, vy)
  if not num(contID) or not num(vx) or not num(vy) then return nil end
  if type(C_Map) ~= "table" or type(C_Map.GetMapInfoAtPosition) ~= "function" then return nil end
  local ok, info = pcall(C_Map.GetMapInfoAtPosition, contID, vx, vy)
  if not ok or type(info) ~= "table" or isSecret(info) then return nil end
  local id = num(info.mapID)
  if not id or id == contID then return nil end
  local t = num(info.mapType)
  if t and t < 3 then return nil end
  local zone = id
  local G = Geo()
  if G and G.zoneOf then
    local ok2, z = pcall(G.zoneOf, id)
    if ok2 and num(z) then zone = z end
  end
  if zone == contID then return nil end
  local name
  if zone == id then
    local S = ns.Sanitize
    name = S and S.display and S.display(info.name, 40) or nil
  end
  if not name then name = View.mapName(zone) end
  return { id = zone, name = name }
end

function View.zoneAt(contID, vx, vy)
  local z = View.zoneInfoAt(contID, vx, vy)
  return z and z.id or nil
end

function View.mapArt(mapID)
  if not mapID or type(C_Map) ~= "table" or type(C_Map.GetMapArtLayers) ~= "function"
    or type(C_Map.GetMapArtLayerTextures) ~= "function" then
    return nil
  end
  local ok, layers = pcall(C_Map.GetMapArtLayers, mapID)
  if not ok or type(layers) ~= "table" or isSecret(layers) or type(layers[1]) ~= "table" then return nil end
  local L = layers[1]
  local w, h, tw, th = num(L.layerWidth), num(L.layerHeight), num(L.tileWidth), num(L.tileHeight)
  if not (w and h and tw and th) or w <= 0 or h <= 0 or tw <= 0 or th <= 0 then return nil end
  local ok2, files = pcall(C_Map.GetMapArtLayerTextures, mapID, 1)
  if not ok2 or type(files) ~= "table" or isSecret(files) or #files == 0 then return nil end
  return { w = w, h = h, tileW = tw, tileH = th, files = files }
end

function View.mapAspect(mapID)
  local G = Geo()
  if mapID and G and G.mapSize then
    local ok, w, h = pcall(G.mapSize, mapID)
    if ok and num(w) and num(h) and h > 0 then return w / h end
  end
  return 1.5
end

function View.zoneOutlines(model, contID, max)
  local out, seen = {}, {}
  for _, c in ipairs(model.chapters or {}) do
    local z = c.zoneID
    if z and not seen[z] and #out < (max or 12) then
      seen[z] = true
      local r = rectOf(z, contID)
      if r then out[#out + 1] = r end
    end
  end
  return out
end

-- World map layer data for journal/WorldLayer.lua, in the coordinates of the map currently displayed. Which map that is, is
-- decided by the client or a map addon like OpenMap (SetMapID): no fixed map IDs here.
-- zone / sub-map / instance: Geo.zoneProjector, view { zone }; continent: Geo.projector, view { continent = id };
-- world / cosmos (mapType <= 1): View.worldProjector.

View.WORLD_TYPE = 1 -- Enum.UIMapType.World (cosmos = 0)

local function mapInfo(mapID)
  if type(C_Map) ~= "table" or type(C_Map.GetMapInfo) ~= "function" then return nil end
  local ok, info = pcall(C_Map.GetMapInfo, mapID)
  if not ok or type(info) ~= "table" or isSecret(info) then return nil end
  return info
end

-- Projection onto a world/cosmos map: the map's direct rect on the world map (GetMapRectOnMap(map, 947), as OpenMap places
-- every zone), else the chain map -> continent -> world. -> project, key ("world:<id>"), affine
function View.worldProjector(worldID)
  worldID = num(worldID)
  local memo = {}
  local aff = function(mapID)
    local G = Geo()
    mapID = num(mapID)
    if not (worldID and mapID and G and G.affine) then return nil end
    local e = memo[mapID]
    if e == nil then
      local a, b, c, d = G.affine(mapID, worldID)
      if not a and G.continentOf then
        local okC, cont = pcall(G.continentOf, mapID)
        cont = okC and num(cont) or nil
        if cont and cont ~= mapID then
          local a1, b1, c1, d1 = G.affine(mapID, cont)
          local a2, b2, c2, d2 = G.affine(cont, worldID)
          if a1 and a2 then a, b, c, d = a2 + b2 * a1, b2 * b1, c2 + d2 * c1, d2 * d1 end
        end
      end
      e = a and { a, b, c, d } or false
      memo[mapID] = e
    end
    if not e then return nil end
    return e[1], e[2], e[3], e[4]
  end
  local fn = function(mapID, x, y)
    if not x or not y then return nil end
    local a, b, c, d = aff(mapID)
    if not a then return nil end
    return a + b * x, c + d * y
  end
  return fn, "world:" .. (worldID and string.format("%d", floor(worldID)) or "-"), aff
end

function View.worldKind(mapID)
  mapID = num(mapID)
  if not mapID then return nil end
  local info = mapInfo(mapID)
  local t = info and num(info.mapType)
  if t and t <= View.WORLD_TYPE then return "world" end
  local G = Geo()
  if G and G.continentOf then
    local ok, c = pcall(G.continentOf, mapID)
    if ok and num(c) == mapID then return "continent" end
  end
  return "zone"
end

-- rebuild = true (world map just opened): Model.get like the book; with new data the old state comes at once and the rebuild
-- runs in the background (Model.onReady). Otherwise noRebuild: existing state only (it would rebuild constantly while walking).
function View.worldModel(rebuild)
  local M = Model()
  if not M or type(M.get) ~= "function" then return nil end
  local ok, m = pcall(M.get, (not rebuild) and { noRebuild = true } or nil)
  if ok and type(m) == "table" then return m end
  return nil
end

function View.onModelReady(fn)
  local M = Model()
  if not M or type(M.onReady) ~= "function" or type(fn) ~= "function" then return false end
  local ok, res = pcall(M.onReady, fn)
  return ok and res and true or false
end

function View.worldScene(model, mapID, opts)
  opts = opts or {}
  local M, G = Model(), Geo()
  mapID = num(mapID)
  if type(model) ~= "table" or not mapID or not M or not G then return nil end
  -- an empty model (new character, nothing travelled yet) still has places (notes, place to-dos): only with opts.allowEmpty
  local empty = model.empty and true or false
  if empty and not opts.allowEmpty then return nil end
  local kind = View.worldKind(mapID)
  local project, key, affine, view
  if kind == "world" then
    project, key, affine = View.worldProjector(mapID)
    view = { all = true }
  elseif kind == "continent" then
    project, key, affine = G.projector(mapID)
    view = { continent = mapID }
  else
    project, key, affine = G.zoneProjector(mapID)
    local z
    if type(M.zoneOf) == "function" and not empty then
      local ok, v = pcall(M.zoneOf, model, mapID)
      z = ok and num(v) or nil
    end
    view = { zone = z or mapID }
  end
  local scene = { kind = kind, mapID = mapID, view = view, key = key, project = project, markers = {}, levelUps = {} }
  if empty then
    scene.route = { segments = {}, count = 0 }
    return scene
  end
  local okR, route = pcall(M.route, model, view, View.routeOpts(project, key, opts.maxSegments or 1000, affine))
  scene.route = (okR and type(route) == "table") and route or { segments = {}, count = 0 }
  if opts.routeOnly then return scene end
  local okM, markers = pcall(M.markersIn, model, view, project)
  scene.markers = (okM and type(markers) == "table") and markers or {}
  if type(M.levelUpsIn) == "function" then
    local ok, lv = pcall(M.levelUpsIn, model, view, project)
    scene.levelUps = (ok and type(lv) == "table") and lv or {}
  end
  if kind == "zone" and opts.kills ~= false and type(M.killsIn) == "function" then
    local ok, kills = pcall(M.killsIn, model, view, project, key)
    scene.kills = (ok and type(kills) == "table") and kills or nil
  end
  return scene
end
