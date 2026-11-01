-- Collector 'Travel': flights, hearthstone, new home, ships/zeppelins as a guess.
-- Flight: hooksecurefunc('TakeTaxiNode') remembers start, destination and cost; TF is written once UnitOnTaxi turns true, TL on landing (polled per second during a flight only).
-- Hearthstone via UNIT_SPELLCAST_SUCCEEDED (player spells are exempt from secret rules); unknown hearthstone toys are caught by a heuristic (cast time, loading screen, arrival in the bind area; never on death/ghost). Crossing = continent change without flight, hearthstone, death or instance (guessed, TB).
local _, ns = ...
local Core, Store, Patterns = ns.Core, ns.Store, ns.Patterns

local floor, min = math.floor, math.min

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function str(v)
  if isSecret(v) or type(v) ~= "string" or v == "" then return nil end
  return v
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, ...)
  if not ok then return nil end
  return a, b
end

-- Known hearthstone spells (spellID from UNIT_SPELLCAST_SUCCEEDED). true = destination is the bind location, 'own' = own destination (then `bind` stays empty in HS).
-- Toy spells come from the client tables Toy/ItemEffect/ItemXItemEffect (wago.tools, Midnight/12.x), item ID in parentheses; new ones are caught by the heuristic below.
local HEARTH = {
  [8690] = true,       -- Hearthstone (6948)
  [556] = true,        -- Astral Recall (shaman)
  [421147] = true,     -- Infinite Hearthstone (208822)
  [1250878] = true,    -- Timerunner's Hearthstone (250411)
  [75136] = true,      -- Ethereal Portal (54452)
  [136508] = true,     -- Dark Portal (93672)
  [278244] = true,     -- Greatfather Winter's Hearthstone (162973)
  [278559] = true,     -- Headless Horseman's Hearthstone (163045)
  [285362] = true,     -- Lunar Elder's Hearthstone (165669)
  [285424] = true,     -- Peddlefeet's Lovely Hearthstone (165670)
  [286031] = true,     -- Noble Gardener's Hearthstone (165802)
  [286331] = true,     -- Fire Eater's Hearthstone (166746)
  [286353] = true,     -- Brewfest Reveler's Hearthstone (166747)
  [298068] = true,     -- Holographic Digitalization Hearthstone (168907)
  [308742] = true,     -- Eternal Traveler's Hearthstone (172179)
  [326064] = true,     -- Night Fae Hearthstone (180290)
  [340200] = true,     -- Necrolord Hearthstone (182773)
  [345393] = true,     -- Kyrian Hearthstone (184353)
  [342122] = true,     -- Venthyr Sinstone (183716)
  [363799] = true,     -- Dominated Hearthstone (188952)
  [366945] = true,     -- Enlightened Hearthstone (190196)
  [375357] = true,     -- Timewalker's Hearthstone (193588)
  [391042] = true,     -- Ohn'ir Windsage's Hearthstone (200630)
  [401802] = true,     -- Stone of the Hearth (212337)
  [420418] = true,     -- Deepdweller's Earthen Hearthstone (208704)
  [422284] = true,     -- Hearthstone of the Flame (209035)
  [463481] = true,     -- Notorious Thread's Hearthstone (228940)
  [1220729] = true,    -- Explosive Hearthstone (236687)
  [1242509] = true,    -- Cosmic Hearthstone (246565)
  [1261979] = true,    -- Lightcalled Hearthstone (257736)
  [1270814] = true,    -- Preyseeker's Hearthstone (263933)
  [1299014] = true,    -- Mycomancer's Hearthspore (264367)
  [1310234] = true,    -- Hiveborne Hearthstone (281136)
  [1311934] = true,    -- Shadeweaver's Hearthstone (281615)
  [171253] = "own",    -- Garrison Hearthstone (110560): takes you to the garrison
  [222695] = "own",    -- Dalaran Hearthstone (140192): takes you to Dalaran
}
local MIN_CAST = 2.0         -- seconds: from this cast time a spell is a teleport candidate (heuristic)
local ARRIVE_WAIT = 30       -- seconds: an arrival (PLAYER_ENTERING_WORLD) this soon after the cast belongs to the heuristic
local ARRIVE_LOAD_WAIT = 120 -- same if the loading screen began shortly after the cast
local LOAD_START_WAIT = 6    -- seconds: the loading screen must begin this soon after the cast
local HS_DEDUP = 60          -- seconds: after an HS no second one is created (known ID + heuristic)
local CAST_MAX_AGE = 15 -- seconds: a START this old is stale (no longer a teleport cast)
local STOP_GRACE = 0.5   -- seconds: a STOP this soon before SUCCEEDED still belongs to the successful cast (event order)
local START_WAIT = 15   -- seconds: how long takeoff may take after TakeTaxiNode
local POLL = 1          -- seconds: poll interval during a flight
local QUIET = 120       -- seconds: a flight/hearthstone/death this recent rules out a crossing
local ZONE_DELAY = 1.0  -- seconds after the zone change until the continent check

local Travel = {
  requires = { "UnitGUID" },
  events = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "CHAT_MSG_SYSTEM", "PLAYER_DEAD", "LOADING_SCREEN_ENABLED" },
  unitEvents = {
    UNIT_SPELLCAST_SUCCEEDED = { "player" }, UNIT_SPELLCAST_START = { "player" },
    UNIT_SPELLCAST_INTERRUPTED = { "player" }, UNIT_SPELLCAST_FAILED = { "player" }, UNIT_SPELLCAST_STOP = { "player" },
  },
}
local handlers = {}

local function recent(t, within)
  return t ~= nil and GetTime() - t <= (within or QUIET)
end

-- player dead or ghost? Unreadable (secret) counts as 'no'.
local function isDeadOrGhost()
  local v = call(UnitIsDeadOrGhost, "player")
  return not isSecret(v) and v == true
end

-- Flights

local function stopPoll(self)
  if self.poll then self.poll:Cancel() end
  self.poll = nil
end

local function pollFlight(self)
  local f = self.flight
  if not f then return stopPoll(self) end
  local onTaxi = call(UnitOnTaxi, "player") == true
  if not f.started then
    if onTaxi then
      f.started = GetTime()
      Store.append("TF", f.from, f.to, f.cost, f.fromNode, f.toNode, f.mapID)
    elseif GetTime() - f.requested > START_WAIT then
      self.flight = nil -- did not take off (e.g. too little money)
      stopPoll(self)
    end
  elseif not onTaxi then
    local mapID, x, y = ns.Zone.here()
    Store.append("TL", (not f.resumed) and floor(GetTime() - f.started) or nil, mapID, x, y)
    self.flight = nil
    self.lastFlightEnd = GetTime()
    stopPoll(self)
  end
end

local function startPoll(self)
  if self.poll then return end
  self.poll = Core.ticker(self, POLL, pollFlight)
end

-- slotIndex -> nodeID via C_TaxiMap (if present and readable)
local function nodeIds()
  local out = {}
  if type(C_TaxiMap) ~= "table" then return out end
  local mapID = num(call(GetTaxiMapID))
  local nodes = call(C_TaxiMap.GetAllTaxiNodes, mapID)
  if type(nodes) ~= "table" or isSecret(nodes) then return out end
  for i = 1, 300 do
    local n = nodes[i]
    if not isSecret(n) and n == nil then break end
    if type(n) == "table" and not isSecret(n) then
      local slot, id = num(n.slotIndex), num(n.nodeID)
      if slot and id then out[floor(slot)] = floor(id) end
    end
  end
  return out
end

local function onTakeTaxi(self, slot)
  slot = num(slot)
  if not slot then return end
  slot = floor(slot)
  local from, fromSlot
  local n = num(call(NumTaxiNodes)) or 0
  for i = 1, min(floor(n), 300) do
    if str(call(TaxiNodeGetType, i)) == "CURRENT" then
      from, fromSlot = str(call(TaxiNodeName, i)), i
      break
    end
  end
  local ids = nodeIds()
  self.flight = {
    from = from, to = str(call(TaxiNodeName, slot)), cost = num(call(TaxiNodeCost, slot)),
    fromNode = fromSlot and ids[fromSlot], toNode = ids[slot],
    requested = GetTime(), mapID = (ns.Zone.here()),
  }
  startPoll(self)
end

function Travel:init()
  self.flight, self.poll = nil, nil
  Core.hook(self, "TakeTaxiNode", onTakeTaxi)
  if call(UnitOnTaxi, "player") == true then -- reload in flight: start unknown
    self.flight = { started = GetTime(), resumed = true, requested = GetTime() }
    startPoll(self)
  end
end

-- Hearthstone and home

local function writeHearth(self, spellID, kind, mapID, x, y)
  self.hearthAt = GetTime()
  self.teleportAt = self.hearthAt -- only a real HS (known ID or heuristic) suppresses a crossing
  self.pending = nil
  local bind = kind ~= "own" and str(call(GetBindLocation)) or nil
  Store.append("HS", spellID, bind, mapID, x, y)
end

handlers.UNIT_SPELLCAST_START = function(self, unit, castGUID, spellID)
  if unit ~= "player" then return end
  self.castStart = { guid = str(castGUID), spell = num(spellID), at = GetTime() }
end

-- does the end event (INTERRUPTED/FAILED/STOP) belong to the remembered START? Without a readable GUID the spell ID decides.
local function sameCast(c, castGUID, spellID)
  local g = str(castGUID)
  if c.guid and g then return c.guid == g end
  local s = num(spellID)
  return s == nil or c.spell == nil or c.spell == s
end

-- interrupted/failed: the START no longer counts. STOP also fires after a success and is only noted;
-- a STOP long before SUCCEEDED (abort) invalidates the START.
local function castEnded(hard)
  return function(self, unit, castGUID, spellID)
    if unit ~= "player" then return end
    local c = self.castStart
    if not c or not sameCast(c, castGUID, spellID) then return end
    if hard then self.castStart = nil else c.stopAt = c.stopAt or GetTime() end
  end
end
handlers.UNIT_SPELLCAST_INTERRUPTED = castEnded(true)
handlers.UNIT_SPELLCAST_FAILED = castEnded(true)
handlers.UNIT_SPELLCAST_STOP = castEnded(false)

-- cast time: measured (START -> SUCCEEDED) or per spell info; instant spells (no START) do not count.
local function hasCastTime(self, castGUID, spellID)
  local c = self.castStart
  self.castStart = nil
  if c then
    local now = GetTime()
    local fresh = now - c.at <= CAST_MAX_AGE and not (c.stopAt and now - c.stopAt > STOP_GRACE)
    if fresh and (c.guid and c.guid == str(castGUID) or c.spell == spellID) and now - c.at >= MIN_CAST then return true end
    if not fresh and (c.guid and c.guid == str(castGUID) or c.spell == spellID) then return false end -- stale/aborted
  end
  local info = type(C_Spell) == "table" and call(C_Spell.GetSpellInfo, spellID) or nil
  if type(info) == "table" and not isSecret(info) then
    local ct = num(info.castTime)
    return ct ~= nil and ct >= MIN_CAST * 1000
  end
  return false
end

handlers.UNIT_SPELLCAST_SUCCEEDED = function(self, unit, castGUID, spellID)
  if unit ~= "player" then return end
  spellID = num(spellID)
  if not spellID then return end
  local kind = HEARTH[spellID]
  if kind then
    self.castStart = nil
    local mapID, x, y = ns.Zone.here()
    writeHearth(self, spellID, kind, mapID, x, y)
    return
  end
  -- heuristic: unknown spell with a cast time; the arrival in the bind area decides (onArrival).
  -- Dead/ghost (e.g. releasing at the graveyard in the bind area) is never a hearthstone. Known limit: a mage
  -- teleport to the bind city looks like a hearthstone.
  if isDeadOrGhost() or recent(self.hearthAt, HS_DEDUP) or not hasCastTime(self, castGUID, spellID) then return end
  local mapID, x, y = ns.Zone.here()
  self.pending = { spellID = spellID, at = GetTime(), mapID = mapID, x = x, y = y }
end

handlers.LOADING_SCREEN_ENABLED = function(self)
  local p = self.pending
  if p and GetTime() - p.at <= LOAD_START_WAIT then p.loading = true end
end

-- does one of the player's place names (zone, real zone, subzone) match the bind location? nil = unreadable.
local function atBindLocation()
  local bind = str(call(GetBindLocation))
  if not bind then return nil end
  local read = false
  for _, fn in ipairs({ GetZoneText or false, GetRealZoneText or false, GetSubZoneText or false }) do
    local name = str(call(fn))
    if name then
      read = true
      if name == bind then return true end
    end
  end
  if not read then return nil end
  return false
end

-- arrival after a cast with a cast time: in the bind area -> HS (spellID stays the real one), else nothing.
-- An unreadable arrival is retried once after ZONE_DELAY; when in doubt no entry.
local function onArrival(self, retry)
  local p = self.pending
  if not p then return end
  if not retry then
    local age = GetTime() - p.at
    if age > (p.loading and ARRIVE_LOAD_WAIT or ARRIVE_WAIT) then
      self.pending = nil
      return
    end
  end
  -- died (after the cast) or dead/ghost now: releasing/resurrecting at the graveyard is no hearthstone.
  if isDeadOrGhost() or (self.deathAt and self.deathAt >= p.at) then
    self.pending = nil
    return
  end
  if recent(self.hearthAt, HS_DEDUP) then
    self.pending = nil
    return
  end
  local here = atBindLocation()
  if here == true then
    writeHearth(self, p.spellID, true, p.mapID, p.x, p.y)
  elseif here == nil and not retry and Core.after(self, ZONE_DELAY, function(s) onArrival(s, true) end) then
    return
  else
    self.pending = nil
  end
end

handlers.CHAT_MSG_SYSTEM = function(self, text)
  if isSecret(text) or type(text) ~= "string" then return end
  local bind = str((Patterns.match("ERR_DEATHBIND_SUCCESS_S", text)))
  if bind then Store.append("HB", bind, (ns.Zone.here())) end
end

handlers.PLAYER_DEAD = function(self)
  self.deathAt = GetTime()
  self.pending, self.castStart = nil, nil
end

-- Crossing (guessed)

local function checkContinent(self)
  local Zone = ns.Zone
  if call(IsInInstance) == true then
    self.wasInstance = true
    return
  end
  local mapID = Zone.here()
  local continent = mapID and Zone.ancestor(mapID, Zone.TYPE_CONTINENT)
  if not continent then return end
  local prev, prevMap = self.continent, self.mapID
  local quiet = not (self.flight or recent(self.lastFlightEnd) or recent(self.hearthAt) or recent(self.teleportAt)
    or recent(self.deathAt)
    or self.wasInstance or call(UnitIsDeadOrGhost, "player") == true)
  if prev and continent ~= prev and quiet then
    Store.append("TB", prevMap, mapID, prev, continent)
  end
  self.continent, self.mapID, self.wasInstance = continent, mapID, false
end

local function scheduleCheck(self)
  if self.checkOn then return end
  self.checkOn = true
  if not Core.after(self, ZONE_DELAY, function(s)
    s.checkOn = false
    checkContinent(s)
  end) then
    self.checkOn = false
  end
end

handlers.PLAYER_ENTERING_WORLD = function(self, ...)
  onArrival(self)
  scheduleCheck(self, ...)
end
handlers.ZONE_CHANGED_NEW_AREA = scheduleCheck

function Travel:onEvent(event, ...)
  local h = handlers[event]
  if h then h(self, ...) end
end

ns.RegisterCollector("Travel", Travel)
