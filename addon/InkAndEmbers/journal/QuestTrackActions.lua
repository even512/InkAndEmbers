-- Quest tracker actions (change "quest-tracker", step E3; WoW Forever only): what a click or a menu entry of the tracker does.
-- The window and the menu (E4) call these; every action checks the client, combat and the quest log itself and never raises.
--
-- PUBLIC API: QuestTrack.actions = A. q is a QuestTrack record (or a bare questID). Every action returns ok (bool), reason (token)
-- and, unless opts.quiet, prints a hint in the chat when it did not work (A.message(reason) gives the same text for a menu).
--   A.showOnMap(q, opts)  opens the world map on the quest's place (C_Map.OpenWorldMap, C side) and puts the pulsing target pin
--                         there (WorldLayer.setTarget). Ready quests: the record's place is the turn-in NPC (QuestTrack, E1).
--                         Pin + pan use Blizzard's quest marker (A.poiPoint, GetQuestsOnMap) when there is one, else the record's place.
--                         The quest becomes the focus quest first (QuestTrack.setFocus, synced to the game's active quest).
--                         ok reasons: "ok" (map + pin), "noPlace" (only the quest's zone is known: map without pin).
--                         fail: "retail" | "combat" | "noQuest" | "noMap" | "api" | "mapFailed"
--   A.details(q, opts)    QuestMapFrame_OpenToQuestDetails. ok: "opened"; fail: "retail" | "combat" | "controller" | "noQuest" |
--                         "api" | "failed". Never in combat and never in controller mode (Questie on Forever: it taints the gamepad
--                         bindings and crashes the client).
--   A.toggleWatch(q, opts) Add/RemoveQuestWatch. ok: "watched" | "unwatched"; fail: "retail" | "noQuest" | "limit" (25) | "npe"
--                         (QuestUtil.CanRemoveQuestWatch false) | "api" | "failed"
--   A.share(q, opts)      QuestLogPushQuest(logIndex). ok: "shared"; fail: "retail" | "noQuest" | "notPushable" | "noGroup" | "api" |
--                         "failed"
--   A.hide(q, opts)       own hide list (QuestTrack.hide, only our tracker). ok: "hidden"; fail: "retail" | "noQuest" | "failed"
--   A.abandon(q, opts)    Blizzard's own confirmation: SetSelectedQuest + SetAbandonQuest + StaticPopup ABANDON_QUEST[_WITH_ITEMS];
--                         the old quest log selection is saved (pcall) and put back in every case. ok: "asked" (the popup decides);
--                         fail: "retail" | "noQuest" | "cannotAbandon" | "api" | "failed"
--   A.state(q)            -> { inLog, watched, combat, controller, canMap, canDetails, canShare, canAbandon, canWatch } for the menu
--   A.message(reason)     -> text | nil
-- Map pan (design decision, option panel.panMap, default on): after the map shows the target map, A.centerOn sets a FIXED view on the
-- target (ScrollContainer:InstantPanAndZoom to a fixed zoom step, centred; see A.centerOn); pcall only, out of combat only.
-- Known risk (Questie finding): touching the canvas can taint the world map for the session, so the result of every pan is counted
-- in diag.questTracker.panMap (pans, errors, blocked = new Core.actionSummary entries). Option off = open the map and the pin only.
-- Never: SetMapID, ReloadUI, writing into Blizzard tables.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local QuestTrack = Journal.QuestTrack or {}
Journal.QuestTrack = QuestTrack

local A = {}
QuestTrack.actions = A

local floor = math.floor

A.MAX_WATCHES = 25
A.ITEM_NAMES_MAX = 6
A.NAME_BYTES = 80

A.TEXT = ns.Locale.ns("QuestTrackActions", {
  retail = "Den Quest-Tracker gibt es nur in WoW Forever.",
  combat = "Im Kampf geht das nicht. Versuch es danach noch einmal.",
  combatMap = "Im Kampf öffnet sich die Weltkarte nicht. Versuch es danach noch einmal.",
  combatLog = "Im Kampf öffnet sich das Questlog nicht. Versuch es danach noch einmal.",
  controller = "Im Controller-Modus öffnet der Tracker das Questlog nicht. Öffne es mit dem Controller.",
  noQuest = "Diese Quest steht nicht mehr im Questlog.",
  noMap = "Für diese Quest ist noch kein Ort bekannt.",
  mapFailed = "Die Weltkarte ließ sich gerade nicht öffnen.",
  api = "Das bietet dieser Client nicht an.",
  limit = "Es werden schon %d Quests verfolgt. Nimm erst eine andere heraus.",
  npe = "Das Verfolgen lässt sich gerade nicht abschalten.",
  notPushable = "Diese Quest lässt sich nicht teilen.",
  noGroup = "Zum Teilen musst du in einer Gruppe sein.",
  cannotAbandon = "Diese Quest lässt sich nicht abbrechen.",
  failed = "Das hat gerade nicht geklappt.",
})

-- ---------------------------------------------------------------- helpers

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function str(v)
  if isSecret(v) or type(v) ~= "string" then return nil end
  return v
end

local function flag(v)
  return not isSecret(v) and v == true
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d
end

local function inCombat()
  return type(InCombatLockdown) == "function" and flag(call(InCombatLockdown))
end

local function questLog()
  local cl = rawget(_G, "C_QuestLog")
  if type(cl) ~= "table" or isSecret(cl) then return nil end
  return cl
end

local function display(s, max)
  local S_ = ns.Sanitize
  s = str(s)
  if not (s and S_ and S_.display) then return nil end
  local out = S_.display(s, max or A.NAME_BYTES)
  if out == "" then return nil end
  return out
end

-- Gamepad UI (controller mode). Questie on Forever: InputUtil.IsGamepadUIEnabled; C_GamePad as a fallback.
function A.controllerMode()
  local iu = rawget(_G, "InputUtil")
  if type(iu) == "table" and type(iu.IsGamepadUIEnabled) == "function" then return flag(call(iu.IsGamepadUIEnabled)) end
  local gp = rawget(_G, "C_GamePad")
  if type(gp) == "table" and type(gp.IsEnabled) == "function" then return flag(call(gp.IsEnabled)) end
  return false
end

function A.message(reason)
  if type(reason) ~= "string" then return nil end
  if reason == "limit" then return A.TEXT("limit", A.maxWatches()) end
  local ok, t = pcall(function() return A.TEXT[reason] end)
  if ok and type(t) == "string" and t ~= "" and t ~= reason then return t end
  return nil
end

local function fail(reason, opts)
  if not (type(opts) == "table" and opts.quiet) then
    local msg = A.message(reason)
    if msg and ns.Core and ns.Core.print then ns.Core.print(msg) end
  end
  return false, reason
end

-- questID of q (record or number), nil when invalid
local function idOf(q)
  local v = q
  if type(q) == "table" then
    if isSecret(q) then return nil end
    v = q.questID
  end
  v = num(v)
  if not v then return nil end
  v = floor(v)
  if v <= 0 or v > 10000000 then return nil end
  return v
end

-- the current record of the model (fresher than the one the window holds), else the given table, else a bare record
local function recordOf(q, id)
  if type(QuestTrack.records) == "function" then
    local ok, list = pcall(QuestTrack.records)
    if ok and type(list) == "table" then
      for _, r in ipairs(list) do
        if type(r) == "table" and r.questID == id then return r, true end
      end
    end
  end
  if type(q) == "table" then return q, false end
  return { questID = id }, false
end

local function logIndexOf(id)
  local cl = questLog()
  local i = cl and num(call(cl.GetLogIndexForQuestID, id))
  if not i or i <= 0 then return nil end
  return floor(i)
end

local function available()
  return type(QuestTrack.available) == "function" and QuestTrack.available() == true
end

local function request()
  if type(QuestTrack.request) == "function" then pcall(QuestTrack.request) end
end

function A.maxWatches()
  return num(rawget(_G, "MAX_QUEST_WATCHES")) or A.MAX_WATCHES
end

local function isWatched(id, rec)
  local cl = questLog()
  if cl and type(cl.GetQuestWatchType) == "function" then
    local ok, t = pcall(cl.GetQuestWatchType, id)
    if ok and not isSecret(t) then return t ~= nil end
  end
  return type(rec) == "table" and rec.watched == true
end

-- ---------------------------------------------------------------- map

-- Blizzard's own quest marker (POI) of a quest: C_QuestLog.GetQuestsOnMap on the given maps in order, first hit wins.
-- -> mapID, x, y | nil. The tracker list/distance keeps its own ranking (QuestieDB first); only the map pin and the pan use this,
-- so the ring sits exactly on the marker Blizzard draws.
A.POI_SCAN_MAX = 300
function A.poiPoint(questID, maps)
  local CQ = rawget(_G, "C_QuestLog")
  if type(CQ) ~= "table" or type(CQ.GetQuestsOnMap) ~= "function" or type(maps) ~= "table" then return nil end
  local seen = {}
  for _, m in ipairs(maps) do
    m = num(m)
    if m and m > 0 and not seen[m] then
      seen[m] = true
      local ok, list = pcall(CQ.GetQuestsOnMap, floor(m))
      if ok and type(list) == "table" and not isSecret(list) then
        for i = 1, math.min(#list, A.POI_SCAN_MAX) do
          local e = list[i]
          if type(e) == "table" and not isSecret(e) and num(e.questID) == questID then
            local x, y = num(e.x), num(e.y)
            if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return floor(m), x, y end
          end
        end
      end
    end
  end
  return nil
end

function A.showOnMap(q, opts)
  if not available() then return fail("retail", opts) end
  if inCombat() then return fail("combatMap", opts) end
  local id = idOf(q)
  if not id then return fail("noQuest", opts) end
  local rec = recordOf(q, id)
  local loc = type(rec.loc) == "table" and rec.loc or nil
  local lx, ly, lmap = loc and num(loc.x), loc and num(loc.y), loc and num(loc.mapID)
  if not (lx and ly and lmap) then loc = nil end
  -- Blizzard's marker wins over a QuestieDB point (the model's "map"/"zone" places already are GetQuestsOnMap points)
  if not (loc and (loc.src == "map" or loc.src == "zone")) then
    local pm, px, py = A.poiPoint(id, { rec.zoneMapID, rec.zone, lmap })
    if pm then
      loc, lmap, lx, ly = { mapID = pm, x = px, y = py, src = "poi" }, pm, px, py
    end
  end
  local mapID = loc and lmap or num(rec.zone) or num(rec.zoneMapID)
  if not mapID or mapID <= 0 then return fail("noMap", opts) end
  local cm = rawget(_G, "C_Map")
  local open = type(cm) == "table" and cm.OpenWorldMap or nil
  if type(open) ~= "function" then return fail("api", opts) end
  local WL = Journal.WorldLayer
  if WL and type(WL.install) == "function" then pcall(WL.install) end
  local targeted = false
  if WL and loc and type(WL.setTarget) == "function" then
    local okT, r = pcall(WL.setTarget, { mapID = lmap, x = lx, y = ly, title = rec.title, questID = id })
    targeted = okT and r == true
  elseif WL then
    -- no place: an old target would point somewhere else
    WL.target = nil
  end
  -- the shown quest becomes the focus quest before the map opens: the focus sync (QuestTrack.setFocus -> C_SuperTrack, out of
  -- combat; showOnMap never runs in combat) makes it the game's active quest, so Blizzard draws its quest area on the map
  if type(QuestTrack.setFocus) == "function" and QuestTrack.focus and QuestTrack.focus() ~= id then pcall(QuestTrack.setFocus, id) end
  local ok, res = pcall(open, floor(mapID))
  if not ok or res == false then
    if targeted then WL.target = nil end
    return fail("mapFailed", opts)
  end
  -- the map frame may only exist now (load on demand); an already open map redraws for the new target
  if WL and type(WL.install) == "function" then pcall(WL.install) end
  if WL and type(WL.refresh) == "function" then pcall(WL.refresh) end
  if targeted then A.panToTarget(floor(mapID)) end
  return true, targeted and "ok" or "noPlace"
end

-- ---- pan the open world map onto the target pin (option panel.panMap); waits for the map to show the target map
A.PAN_TRIES, A.PAN_EVERY = 12, 0.1
A.pan = { gen = 0, pans = 0, errors = 0, blocked = 0, last = nil }

local function panDiag()
  local db = ns.Store and ns.Store.db
  if type(db) ~= "table" or isSecret(db) then return nil end
  if type(db.diag) ~= "table" then db.diag = {} end
  if type(db.diag.questTracker) ~= "table" then db.diag.questTracker = {} end
  if type(db.diag.questTracker.panMap) ~= "table" then db.diag.questTracker.panMap = {} end
  return db.diag.questTracker.panMap
end

local function blockedTotal()
  local C = ns.Core
  if not (C and type(C.actionSummary) == "function") then return nil end
  local ok, total = pcall(C.actionSummary)
  return ok and num(total) or nil
end

-- Fixed view (deterministic, the same end view at every click): never PanAndZoomTo (it is SetPanTarget + ScrollContainer:ZoomIn, i.e.
-- one zoom level further on EVERY call = the "zoom adds up" complaint). Instead, from MapCanvasScrollControllerMixin (Forever FrameXML,
-- Blizzard_MapCanvas/MapCanvas_ScrollContainerMixin.lua):
--   MapCanvasMixin:GetScaleForMinZoom / GetScaleForMaxZoom  (= ScrollContainer: zoomLevels[1] / zoomLevels[#zoomLevels]) -> scale
--   ScrollContainer:InstantPanAndZoom(scale, x, y, true)    sets scale AND centre at once; true = no lerp with the old position;
--                                                           the centre is clamped to the scroll extents of that scale
-- Fallback without InstantPanAndZoom: ScrollContainer:ResetZoom(true) (back to the base view) + SetZoomTarget(scale) + SetPanTarget(x, y).
-- Without any of that: SetPanTarget alone. Every call is a pcall; true when the view was set.
A.PAN_ZOOM = 0.5 -- fixed zoom step: this share of the way from the minimum to the maximum map scale

local function callOn(obj, name, ...)
  if type(obj) ~= "table" or type(obj[name]) ~= "function" then return false, nil end
  local ok, v = pcall(obj[name], obj, ...)
  return ok, v
end

function A.centerOn(map, x, y)
  local sc = map.ScrollContainer
  if type(sc) ~= "table" then sc = nil end
  local okMin, minS = callOn(map, "GetScaleForMinZoom")
  local okMax, maxS = callOn(map, "GetScaleForMaxZoom")
  if not (okMin and okMax) and sc then
    okMin, minS = callOn(sc, "GetScaleForMinZoom")
    okMax, maxS = callOn(sc, "GetScaleForMaxZoom")
  end
  minS, maxS = num(minS), num(maxS)
  local scale = okMin and okMax and minS and maxS and maxS >= minS and (minS + (maxS - minS) * A.PAN_ZOOM) or nil
  if sc and scale then
    if type(sc.InstantPanAndZoom) == "function" then
      if callOn(sc, "InstantPanAndZoom", scale, x, y, true) then return true end
    end
    local r = callOn(sc, "ResetZoom", true)
    local z = callOn(sc, "SetZoomTarget", scale)
    local p = callOn(sc, "SetPanTarget", x, y)
    if r and z and p then return true end
  end
  if sc and callOn(sc, "SetPanTarget", x, y) then return true end
  return false
end

local function panNow(mapID)
  local WL = Journal.WorldLayer
  local map = rawget(_G, "WorldMapFrame")
  if type(map) ~= "table" or not (WL and WL.target and type(WL.targetPos) == "function") then return true end
  local shown = num(call(map.GetMapID, map))
  if shown ~= mapID then return false end -- not there yet
  local x, y = WL.targetPos(WL.target, shown)
  if not (x and y) then return true end
  local before = blockedTotal()
  local ok = A.centerOn(map, x, y)
  local afterN = blockedTotal()
  local P = A.pan
  P.pans = P.pans + 1
  if not ok then P.errors = P.errors + 1 end
  if before and afterN then P.blocked = P.blocked + (afterN - before) end
  P.last = ok
  local d = panDiag()
  if d then d.pans, d.errors, d.blocked, d.lastOk, d.actionBlockedTotal = P.pans, P.errors, P.blocked, ok, afterN end
  return true
end

function A.panToTarget(mapID)
  local P = A.pan
  P.gen = P.gen + 1
  local gen = P.gen
  local s = type(QuestTrack.settings) == "function" and QuestTrack.settings() or nil
  if not (s and s.panel and s.panel.panMap == true) then return false end
  local C = rawget(_G, "C_Timer")
  if not (type(C) == "table" and type(C.After) == "function") then return false end
  local tries = 0
  local function step()
    if P.gen ~= gen then return end -- a newer click took over
    if inCombat() then return end -- no pan in combat (the map stays where it is)
    tries = tries + 1
    local done = panNow(mapID)
    if not done and tries < A.PAN_TRIES then pcall(C.After, A.PAN_EVERY, step) end
  end
  pcall(C.After, 0, step)
  return true
end

-- ---------------------------------------------------------------- quest log details

function A.details(q, opts)
  if not available() then return fail("retail", opts) end
  if A.controllerMode() then return fail("controller", opts) end
  if inCombat() then return fail("combatLog", opts) end
  local id = idOf(q)
  if not (id and logIndexOf(id)) then return fail("noQuest", opts) end
  local fn = rawget(_G, "QuestMapFrame_OpenToQuestDetails")
  if type(fn) ~= "function" then return fail("api", opts) end
  if not pcall(fn, id) then return fail("failed", opts) end
  return true, "opened"
end

-- ---------------------------------------------------------------- watch list

function A.toggleWatch(q, opts)
  if not available() then return fail("retail", opts) end
  local id = idOf(q)
  if not (id and logIndexOf(id)) then return fail("noQuest", opts) end
  local cl = questLog()
  local rec = recordOf(q, id)
  if isWatched(id, rec) then
    local qu = rawget(_G, "QuestUtil")
    if type(qu) == "table" and type(qu.CanRemoveQuestWatch) == "function" then
      local ok, can = pcall(qu.CanRemoveQuestWatch)
      if ok and not flag(can) then return fail("npe", opts) end
    end
    if type(cl.RemoveQuestWatch) ~= "function" then return fail("api", opts) end
    local ok, r = pcall(cl.RemoveQuestWatch, id)
    if not ok or r == false then return fail("failed", opts) end
    request()
    return true, "unwatched"
  end
  if type(cl.AddQuestWatch) ~= "function" then return fail("api", opts) end
  local n = num(call(cl.GetNumQuestWatches))
  if n and n >= A.maxWatches() then return fail("limit", opts) end
  local ok, r = pcall(cl.AddQuestWatch, id)
  if not ok or r == false then return fail("failed", opts) end
  request()
  return true, "watched"
end

-- ---------------------------------------------------------------- share

local function inGroup()
  return type(IsInGroup) == "function" and flag(call(IsInGroup))
end

local function pushable(id)
  local cl = questLog()
  return cl ~= nil and flag(call(cl.IsPushableQuest, id))
end

function A.share(q, opts)
  if not available() then return fail("retail", opts) end
  local id = idOf(q)
  local idx = id and logIndexOf(id)
  if not idx then return fail("noQuest", opts) end
  if not pushable(id) then return fail("notPushable", opts) end
  if not inGroup() then return fail("noGroup", opts) end
  local push = rawget(_G, "QuestLogPushQuest")
  if type(push) ~= "function" then return fail("api", opts) end
  if not pcall(push, idx) then return fail("failed", opts) end
  return true, "shared"
end

-- ---------------------------------------------------------------- hide (own list)

function A.hide(q, opts)
  if not available() then return fail("retail", opts) end
  local id = idOf(q)
  if not id then return fail("noQuest", opts) end
  if type(QuestTrack.hide) ~= "function" then return fail("api", opts) end
  local ok, r = pcall(QuestTrack.hide, id)
  if not ok or r ~= true then return fail("failed", opts) end
  return true, "hidden"
end

-- ---------------------------------------------------------------- abandon

-- item names for ABANDON_QUEST_WITH_ITEMS: the legacy global gives a string, C_QuestLog a list of item IDs
local function abandonItems(cl)
  local raw = call(rawget(_G, "GetAbandonQuestItems") or cl.GetAbandonQuestItems)
  if str(raw) then return display(raw, 200) end
  if type(raw) ~= "table" or isSecret(raw) then return nil end
  local names = {}
  local ci = rawget(_G, "C_Item")
  for _, itemID in ipairs(raw) do
    if #names >= A.ITEM_NAMES_MAX then break end
    itemID = num(itemID)
    if itemID then
      local name
      if type(ci) == "table" and type(ci.GetItemNameByID) == "function" then name = call(ci.GetItemNameByID, itemID) end
      if not str(name) and type(GetItemInfo) == "function" then name = call(GetItemInfo, itemID) end
      name = display(name, A.NAME_BYTES)
      if name then names[#names + 1] = name end
    end
  end
  if #names == 0 then return nil end
  return table.concat(names, ", ")
end

function A.abandon(q, opts)
  if not available() then return fail("retail", opts) end
  local id = idOf(q)
  if not (id and logIndexOf(id)) then return fail("noQuest", opts) end
  local cl = questLog()
  local show, hide = rawget(_G, "StaticPopup_Show"), rawget(_G, "StaticPopup_Hide")
  if type(cl.SetSelectedQuest) ~= "function" or type(cl.SetAbandonQuest) ~= "function" or type(show) ~= "function" then
    return fail("api", opts)
  end
  if type(cl.CanAbandonQuest) == "function" then
    local ok, can = pcall(cl.CanAbandonQuest, id)
    if ok and not flag(can) then return fail("cannotAbandon", opts) end
  end
  -- the title of a model record is display-safe already; anything else is read again and cleaned
  local rec, fromModel = recordOf(q, id)
  local title = (fromModel and str(rec.title)) or display(call(cl.GetTitleForQuestID, id)) or ""
  -- save the old selection (pcall); it is put back below in every case
  local okOld, old = false, nil
  if type(cl.GetSelectedQuest) == "function" then
    okOld, old = pcall(cl.GetSelectedQuest)
    old = okOld and num(old) or nil
  end
  local shown = false
  if pcall(cl.SetSelectedQuest, id) and pcall(cl.SetAbandonQuest) then
    local items = abandonItems(cl)
    if items then
      if type(hide) == "function" then pcall(hide, "ABANDON_QUEST") end
      shown = pcall(show, "ABANDON_QUEST_WITH_ITEMS", title, items)
    else
      if type(hide) == "function" then pcall(hide, "ABANDON_QUEST_WITH_ITEMS") end
      shown = pcall(show, "ABANDON_QUEST", title)
    end
  end
  if okOld then pcall(cl.SetSelectedQuest, old or 0) end
  if not shown then return fail("failed", opts) end
  return true, "asked"
end

-- ---------------------------------------------------------------- state for the menu

function A.state(q)
  local id = idOf(q)
  local on = available()
  local idx = on and id and logIndexOf(id) or nil
  local rec = id and recordOf(q, id) or {}
  local combat, controller = inCombat(), A.controllerMode()
  local cl = questLog()
  local loc = type(rec.loc) == "table" and rec.loc or nil
  local hasMap = (loc and num(loc.mapID)) or num(rec.zone) or num(rec.zoneMapID)
  local canAbandon = idx ~= nil
  if canAbandon and cl and type(cl.CanAbandonQuest) == "function" then
    local ok, can = pcall(cl.CanAbandonQuest, id)
    if ok then canAbandon = flag(can) end
  end
  local watched = idx ~= nil and isWatched(id, rec)
  return {
    inLog = idx ~= nil, watched = watched, combat = combat, controller = controller,
    canMap = on and not combat and hasMap ~= nil,
    canDetails = idx ~= nil and not combat and not controller and type(rawget(_G, "QuestMapFrame_OpenToQuestDetails")) == "function",
    canShare = idx ~= nil and pushable(id) and inGroup(),
    canAbandon = canAbandon,
    canWatch = idx ~= nil and (watched or (num(cl and call(cl.GetNumQuestWatches)) or 0) < A.maxWatches()),
  }
end
