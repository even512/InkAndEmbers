-- Open quests in the retail client: a runtime source from the game's own world map API instead of the data addon
-- InkAndEmbers_QuestData (QuestieDB/Forever data, wrong for retail zones). Active only in the retail client
-- (Journal.MapSpace.retailClient) outside the test mode and OpenQuests.ALLOW_RETAIL; Forever never gets here.
-- Per zone map: C_QuestLine.RequestQuestLinesForMap -> QUESTLINE_UPDATE (requestRequired = ask once more) or after
-- RetailOpen.TIMEOUT s -> C_QuestLine.GetAvailableQuestLines + GetForceVisibleQuests/GetQuestLineInfo.
-- The event names no map, so one request is in flight at a time (queue). Results are cached per uiMapID for the session;
-- quest/level events mark them stale (shown on, asked again on the next use). Nothing is asked or read in combat (the
-- queue waits for PLAYER_REGEN_ENABLED). All API calls in pcall; secret values are dropped field by field.
-- Filters like Blizzard's QuestOfferDataProvider: in progress / in the quest log / done this session out; startMapID must
-- be the map or one of its sub-maps; isHidden (low level) only with the minimap tracking "low level quests",
-- isAccountCompleted only with "account completed quests" (else counted as hidden); daily = repeatable (switch).
-- Missing compared with the data addon (said in the UI): no quest giver (the quest line name stands in), no locked quests
-- with reasons, no single quests outside a quest line, only the next step of a line.
-- Output = the shape of OpenQuests.list/zones; givers = { { key = "l<lineID>", kind = "line", id, name, mapID, points } }
-- with x/y 0-1 (retail map IDs, no MapSpace conversion).
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal
local OpenQuests = Journal.OpenQuests
if not OpenQuests then return end

local RetailOpen = {}
Journal.OpenQuestsRetail = RetailOpen

local floor, min, sort, lower, tostring = math.floor, math.min, table.sort, string.lower, tostring

RetailOpen.TIMEOUT = 3      -- seconds to wait for QUESTLINE_UPDATE (measured in game: ~0.15 s)
RetailOpen.REASK = 1        -- extra requests when QUESTLINE_UPDATE says requestRequired
RetailOpen.MAX_LINES = 200  -- entries read per map
RetailOpen.PREFETCH = 40    -- zones of the player's continent asked in the background (once per continent and session)
RetailOpen.PARENT_HOPS = 6  -- depth of the startMapID -> map check

-- texts (German here, English in locales/enUS_model.lua, scope "m.OpenQuestsRetail"; read only on use)
local T = ns.Locale.ns("m.OpenQuestsRetail", {
  noLine = "Ohne Questreihe",
  campaign = "Kampagne",
  legendary = "Legendär",
  important = "Wichtig",
  lowLevel = "niedrigstufig",
  accountDone = "von der Kriegsmeute erledigt",
  floorAbove = "Eingang eine Ebene höher",
  floorBelow = "Eingang eine Ebene tiefer",
  footer = "Daten: Weltkarte des Spiels",
  diagLine = "Offene Quests: aus der Weltkarte des Spiels (%d Zonen geladen%s)",
  diagWaiting = ", %d in Arbeit",
  diagNoApi = "Offene Quests: Retail, Weltkarten-Schnittstelle (C_QuestLine) fehlt",
})
RetailOpen.TEXT = T

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

-- pcall; nil if the call fails or any result is secret
local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if not r[1] then return nil end
  for i = 2, #r do
    if isSecret(r[i]) then return nil end
  end
  return r[2], r[3], r[4]
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function flag(t, k)
  local v = t[k]
  return not isSecret(v) and v == true
end

local function display(s)
  if isSecret(s) or type(s) ~= "string" or s == "" then return nil end
  local S_ = ns.Sanitize
  return S_ and S_.display(s, OpenQuests.NAME_MAX) or nil
end

local function inCombat()
  if type(InCombatLockdown) ~= "function" then return false end
  local ok, v = pcall(InCombatLockdown)
  return ok and not isSecret(v) and v == true
end

local function now()
  if type(GetTime) ~= "function" then return 0 end
  local ok, t = pcall(GetTime)
  return (ok and not isSecret(t) and type(t) == "number") and t or 0
end

local function api()
  local Q = type(C_QuestLine) == "table" and C_QuestLine or nil
  if Q and type(Q.RequestQuestLinesForMap) == "function" and type(Q.GetAvailableQuestLines) == "function" then return Q end
  return nil
end

-- session state (tests: RetailOpen._state). cache[mapID] = { state = "queued"|"asking"|"ready", stale, recs, at, via };
-- queue = map IDs waiting; flight = { mapID, token, asks } of the request in flight; prefetched[continent] = true
local S = { cache = {}, queue = {}, flight = nil, token = 0, prefetched = {}, waitCombat = false, requests = 0 }
RetailOpen._state = S

-- on: switch OpenQuests.RETAIL_SOURCE set, retail client, no test mode, no ALLOW_RETAIL (those keep the data addon in the
-- retail map space). Switch off = the tab stays locked in Retail (reason RETAIL) as in 0.9.2; the code below stays untouched.
function RetailOpen.active()
  return OpenQuests.RETAIL_SOURCE == true and OpenQuests.ALLOW_RETAIL ~= true and OpenQuests.test() == nil and OpenQuests.retailClient() == true
end

function RetailOpen.available()
  return api() ~= nil
end

local function mapInfo(id)
  local C = type(C_Map) == "table" and C_Map or nil
  local info = C and call(C.GetMapInfo, id) or nil
  return (type(info) == "table" and not isSecret(info)) and info or nil
end

-- is sub a sub-map of (or equal to) mapID? walks the parent chain a few steps
local function within(sub, mapID)
  local id = sub
  for _ = 1, RetailOpen.PARENT_HOPS do
    if id == mapID then return true end
    local info = mapInfo(id)
    local p = info and num(info.parentMapID)
    if not p or p == 0 or p == id then return false end
    id = p
  end
  return id == mapID
end

-- one QuestLineInfo -> plain record (nil = unusable: no id, no point, secret fields)
local function record(info, mapID, fallbackID)
  if type(info) ~= "table" or isSecret(info) then return nil end
  local id = num(info.questID) or num(fallbackID)
  local x, y = num(info.x), num(info.y)
  if not (id and id > 0 and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1) then return nil end
  id = floor(id)
  local start = num(info.startMapID)
  local r = { id = id, x = x, y = y, name = display(info.questName), lineID = num(info.questLineID), lineName = display(info.questLineName),
    hidden = flag(info, "isHidden"), daily = flag(info, "isDaily"), campaign = flag(info, "isCampaign"), legendary = flag(info, "isLegendary"),
    important = flag(info, "isImportant"), account = flag(info, "isAccountCompleted"), inProgress = flag(info, "inProgress"),
    floor = num(info.floorLocation) }
  if start and start > 0 and floor(start) ~= mapID and not within(floor(start), mapID) then r.elsewhere = true end
  local C = type(C_QuestLog) == "table" and C_QuestLog or nil
  if not r.name then r.name = C and display((call(C.GetTitleForQuestID, id))) or nil end
  local lv = C and num((call(C.GetQuestDifficultyLevel, id))) or nil
  r.level = (lv and lv > 0) and floor(lv) or nil
  return r
end

-- read the answer for a map (out of combat only)
local function read(mapID)
  local Q = api()
  local recs, seen = {}, {}
  if not Q then return recs end
  local list = call(Q.GetAvailableQuestLines, mapID)
  if type(list) == "table" then
    for i, info in ipairs(list) do
      if i > RetailOpen.MAX_LINES then break end
      local r = record(info, mapID)
      if r and not seen[r.id] then
        seen[r.id] = true
        recs[#recs + 1] = r
      end
    end
  end
  local force = call(Q.GetForceVisibleQuests, mapID)
  if type(force) == "table" and type(Q.GetQuestLineInfo) == "function" then
    for i, id in ipairs(force) do
      if i > RetailOpen.MAX_LINES then break end
      id = num(id)
      if id and not seen[floor(id)] then
        local r = record(call(Q.GetQuestLineInfo, floor(id), mapID), mapID, id)
        if r then
          seen[r.id] = true
          recs[#recs + 1] = r
        end
      end
    end
  end
  return recs
end

local pump

-- the world map events are registered with the first request (only the retail source ever asks; Forever stays as before)
local function listen()
  if S.listening then return end
  S.listening = true
  local C = ns.Core
  if not (C and C.on) then return end
  for _, ev in ipairs({ "QUESTLINE_UPDATE", "PLAYER_REGEN_ENABLED" }) do
    C.on(ev, function(event, a) if RetailOpen.active() then RetailOpen.onEvent(event, a) end end)
  end
end

-- the request in flight is answered (event) or timed out: read it, cache it, go on with the queue
local function finish(via)
  local f = S.flight
  if not f then return end
  S.flight = nil
  local e = S.cache[f.mapID]
  if inCombat() then
    -- read after the fight: back to the front of the queue
    if e then e.state = e.recs and "ready" or "queued" end
    table.insert(S.queue, 1, f.mapID)
    S.waitCombat = true
    return
  end
  local ok, recs = pcall(read, f.mapID)
  e = e or {}
  S.cache[f.mapID] = e
  e.recs = ok and recs or (e.recs or {})
  e.state, e.stale, e.via, e.at = "ready", nil, via, now()
  if OpenQuests._changed then OpenQuests._changed() end
  pump()
end
RetailOpen._finish = finish

pump = function()
  if S.flight or #S.queue == 0 then return end
  listen()
  if inCombat() then
    S.waitCombat = true
    return
  end
  local Q = api()
  if not Q then return end
  local mapID = table.remove(S.queue, 1)
  local e = S.cache[mapID]
  if e and e.state == "ready" and not e.stale then return pump() end
  S.token = S.token + 1
  local token = S.token
  S.flight = { mapID = mapID, token = token, asks = 1 }
  if e then e.state = e.recs and "ready" or "asking" else S.cache[mapID] = { state = "asking" } end
  S.requests = S.requests + 1
  local ok = pcall(Q.RequestQuestLinesForMap, mapID)
  if not ok then return finish("error") end
  local timerOk = type(C_Timer) == "table" and type(C_Timer.After) == "function"
    and pcall(C_Timer.After, RetailOpen.TIMEOUT, function()
      if S.flight and S.flight.token == token then finish("timeout") end
    end)
  if not timerOk then finish("now") end
end

-- ask for a map (front = before the background queue); keeps a cached answer while it is asked again
local function want(mapID, front)
  local e = S.cache[mapID]
  if e and e.state == "ready" and not e.stale then return e end
  if S.flight and S.flight.mapID == mapID then return e end
  for i, q in ipairs(S.queue) do
    if q == mapID then
      if front and i > 1 then
        table.remove(S.queue, i)
        table.insert(S.queue, 1, mapID)
      end
      return e
    end
  end
  if not e then
    e = { state = "queued" }
    S.cache[mapID] = e
  end
  if front then table.insert(S.queue, 1, mapID) else S.queue[#S.queue + 1] = mapID end
  pump()
  return S.cache[mapID]
end
RetailOpen.want = want

local function playerMap()
  local C = type(C_Map) == "table" and C_Map or nil
  local id = C and num((call(C.GetBestMapForUnit, "player"))) or nil
  return id and floor(id) or nil
end

-- maps that show quest offers: not world/continent/cosmic (MapUtil.ShouldMapTypeShowQuests)
local function questMap(id)
  local info = mapInfo(id)
  local t = info and num(info.mapType)
  return t == nil or t >= 3
end

-- continent of a map (mapType 2 in the parent chain)
local function continentOf(id)
  for _ = 1, RetailOpen.PARENT_HOPS do
    local info = mapInfo(id)
    if not info then return nil end
    if num(info.mapType) == 2 then return id end
    local p = num(info.parentMapID)
    if not p or p == 0 or p == id then return nil end
    id = floor(p)
  end
  return nil
end

-- the player's zone first, then (once per continent) its other zones in the background
local function prime()
  if not api() then return nil end
  local here = playerMap()
  if not (here and questMap(here)) then return nil end
  want(here, true)
  local cont = continentOf(here)
  if cont and not S.prefetched[cont] then
    S.prefetched[cont] = true
    local C = type(C_Map) == "table" and C_Map or nil
    local kids = C and call(C.GetMapChildrenInfo, cont, 3, false) or nil
    if type(kids) == "table" then
      local n = 0
      for _, k in ipairs(kids) do
        local id = type(k) == "table" and not isSecret(k) and num(k.mapID) or nil
        if id and floor(id) ~= here and num(k.mapType) == 3 then
          n = n + 1
          if n > RetailOpen.PREFETCH then break end
          want(floor(id), false)
        end
      end
    end
  end
  return here
end

local function questLogSet()
  local set = {}
  local C = type(C_QuestLog) == "table" and C_QuestLog or nil
  if not C then return set end
  local n = num((call(C.GetNumQuestLogEntries)))
  if not n or type(C.GetInfo) ~= "function" then return set end
  for i = 1, min(floor(n), 400) do
    local ok, info = pcall(C.GetInfo, i)
    if ok and type(info) == "table" and not isSecret(info) and not info.isHeader then
      local qid = num(info.questID)
      if qid and qid > 0 then set[floor(qid)] = true end
    end
  end
  return set
end

local function done(id)
  local st = OpenQuests._state
  if st and st.turned and st.turned[id] then return true end
  local C = type(C_QuestLog) == "table" and C_QuestLog or nil
  if not (C and type(C.IsQuestFlaggedCompleted) == "function") then return false end
  local ok, r = pcall(C.IsQuestFlaggedCompleted, id)
  return ok and not isSecret(r) and r == true
end

local function tracking(fnName)
  local M = type(C_Minimap) == "table" and C_Minimap or nil
  local v = M and call(M[fnName]) or nil
  return v == true
end

local function emptyResult(scope, mapID)
  return { scope = scope, mapID = mapID, open = {}, locked = {}, openCount = 0, lockedCount = 0,
    hidden = { group = 0, repeatable = 0, class = 0, category = 0, lowLevel = 0, account = 0, total = 0 }, foreign = 0, noLocation = 0,
    test = false, retail = true }
end

local function sortOpen(a, b)
  local la, lb = a.level or 999, b.level or 999
  if la ~= lb then return la < lb end
  local na, nb = lower(a.name), lower(b.name)
  if na ~= nb then return na < nb end
  return a.id < b.id
end

-- records of one map into res (filters see the head)
local function collect(res, mapID, recs, opts, ctx)
  local kinds = type(opts.kinds) == "table" and opts.kinds or {}
  for _, r in ipairs(recs) do
    if not r.inProgress and not r.elsewhere and not ctx.log[r.id] and not ctx.seen[r.id] and not done(r.id) then
      ctx.seen[r.id] = true
      local hide
      if r.hidden and not ctx.trackLow then hide = "lowLevel"
      elseif r.account and not ctx.trackAccount then hide = "account"
      elseif r.daily and kinds.repeatable ~= true then hide = "repeatable" end
      if hide then
        res.hidden[hide] = res.hidden[hide] + 1
        res.hidden.total = res.hidden.total + 1
      else
        local notes = {}
        if r.campaign then notes[#notes + 1] = T.campaign end
        if r.legendary then notes[#notes + 1] = T.legendary end
        if r.important then notes[#notes + 1] = T.important end
        if r.hidden then notes[#notes + 1] = T.lowLevel end
        if r.account then notes[#notes + 1] = T.accountDone end
        if r.floor == 0 then notes[#notes + 1] = T.floorAbove elseif r.floor == 1 then notes[#notes + 1] = T.floorBelow end
        local lineID = r.lineID and floor(r.lineID) or 0
        res.open[#res.open + 1] = { id = r.id, name = r.name or OpenQuests.TEXT("questFallback", r.id), level = r.level, minLevel = 0,
          unsure = false, flags = { r = r.daily or nil }, state = "open", noLocation = false, reasons = {}, notes = notes, retail = true,
          givers = { { key = "l" .. lineID, kind = "line", id = lineID, name = r.lineName or T.noLine, mapID = mapID, points = { { r.x, r.y } } } } }
        res.openCount = res.openCount + 1
      end
    end
  end
end

local function context()
  return { log = questLogSet(), seen = {}, trackLow = tracking("IsTrackingHiddenQuests"),
    trackAccount = tracking("IsTrackingAccountCompletedQuests") }
end

-- OpenQuests.list in retail: scope = uiMapID or "all" (all maps answered so far this session)
function RetailOpen.list(scope, opts)
  opts = type(opts) == "table" and not isSecret(opts) and opts or {}
  if not api() then
    local r = emptyResult(scope, type(scope) == "number" and scope or nil)
    r.unavailable, r.reason = true, "NO_QUESTLINE"
    return r
  end
  prime()
  local ctx = context()
  if scope == "all" then
    local res = emptyResult("all", nil)
    local ids = {}
    for id, e in pairs(S.cache) do
      if e.recs then ids[#ids + 1] = id end
      if e.state ~= "ready" or e.stale then res.loading = true end
    end
    sort(ids)
    for _, id in ipairs(ids) do collect(res, id, S.cache[id].recs, opts, ctx) end
    sort(res.open, sortOpen)
    if inCombat() and res.loading then res.combat = true end
    return res
  end
  local mapID = num(scope)
  if not mapID then
    local r = emptyResult("all", nil)
    r.invalid = true
    return r
  end
  mapID = floor(mapID)
  local res = emptyResult(mapID, mapID)
  if not questMap(mapID) then
    res.noQuestMap = true
    return res
  end
  local e = want(mapID, true)
  if e and e.recs then collect(res, mapID, e.recs, opts, ctx) end
  if not e or e.state ~= "ready" or e.stale then
    res.loading = true
    if inCombat() then res.combat = true end
  end
  sort(res.open, sortOpen)
  return res
end

-- OpenQuests.zones in retail: every answered map with open quests, plus the player's zone (also while it is loading)
function RetailOpen.zones(opts)
  opts = type(opts) == "table" and not isSecret(opts) and opts or {}
  local out = { total = { open = 0, locked = 0 }, zones = {}, retail = true }
  if not api() then
    out.unavailable, out.reason = true, "NO_QUESTLINE"
    return out
  end
  local here = prime()
  local ctx = context()
  local per = {}
  for id, e in pairs(S.cache) do
    if e.recs then
      local res = emptyResult(id, id)
      ctx.seen = {}
      collect(res, id, e.recs, opts, ctx)
      if res.openCount > 0 or id == here then per[id] = res.openCount end
    end
    if e.state ~= "ready" or e.stale then out.loading = true end
  end
  if here and per[here] == nil then per[here] = 0 end
  for id, n in pairs(per) do
    out.total.open = out.total.open + n
    out.zones[#out.zones + 1] = { mapID = id, open = n, locked = 0, name = OpenQuests.mapName(id) }
  end
  sort(out.zones, function(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.mapID < b.mapID
  end)
  return out
end

function RetailOpen.footer() return T.footer end

function RetailOpen.diagLine()
  if not api() then return T.diagNoApi end
  local n, wait = 0, 0
  for _, e in pairs(S.cache) do
    if e.recs then n = n + 1 end
    if e.state ~= "ready" or e.stale then wait = wait + 1 end
  end
  return T("diagLine", n, wait > 0 and T("diagWaiting", wait) or "")
end

-- quest/level events: answers become stale (kept on screen, asked again on the next use)
local STALE = { QUEST_TURNED_IN = true, QUEST_ACCEPTED = true, QUEST_REMOVED = true, PLAYER_LEVEL_UP = true }
function RetailOpen.onEvent(event, arg)
  if event == "QUESTLINE_UPDATE" then
    local f = S.flight
    if not f then return end
    if not isSecret(arg) and arg == true and f.asks <= RetailOpen.REASK and not inCombat() then
      f.asks = f.asks + 1
      local Q = api()
      if Q and pcall(Q.RequestQuestLinesForMap, f.mapID) then return end
    end
    finish("event")
  elseif event == "PLAYER_REGEN_ENABLED" then
    if S.waitCombat then
      S.waitCombat = false
      pump()
    end
  elseif STALE[event] then
    for _, e in pairs(S.cache) do
      if e.state == "ready" then e.stale = true end
    end
  end
end

function RetailOpen.reset()
  S.cache, S.queue, S.flight, S.prefetched, S.waitCombat = {}, {}, nil, {}, false
end

