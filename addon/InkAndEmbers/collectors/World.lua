-- Collector 'World': first arrival per map, subzone and continent, discoveries, flight points.
-- Visited maps are stored once in snapshots.zones[mapID], subzones in snapshots.subzones['<mapID>:<name>'], continents in snapshots.continents[mapID]
-- (each with level and time). A new main zone -> signal FC_ZONE_NEW (screenshot).
local _, ns = ...
local Core, Store, Patterns = ns.Core, ns.Store, ns.Patterns

local format = string.format

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

local CHECK_DELAY = 0.5 -- seconds: map info is current only shortly after the zone event
local DEDUPE = 2.0      -- seconds: the same message via CHAT_MSG_SYSTEM and UI_INFO_MESSAGE

local function playerLevel()
  return num(call(UnitLevel, "player"))
end

local function npcIdOf(guid)
  if not str(guid) then return nil end
  local kind, id = string.match(guid, "^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  if (kind == "Creature" or kind == "Vehicle") and id then return tonumber(id) end
  return nil
end

local World = {
  requires = { "UnitLevel" },
  events = {
    "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "CHAT_MSG_SYSTEM",
    "UI_INFO_MESSAGE",
  },
}
local handlers = {}

function World:init()
  self.recent = {}
  self.checkOn = false
end

-- new map: ZN line; a new main zone also FC_ZONE_NEW. Returns true if new.
local function visitMap(mapID, level, x, y)
  if not Store.putSnapshot("zones", mapID, { seen = true, level = level }) then return false end
  local Zone = ns.Zone
  local info = Zone.info(mapID)
  local mapType = info and num(info.mapType)
  Store.append("ZN", mapID, mapType, Zone.ancestor(mapID, Zone.TYPE_ZONE), Zone.ancestor(mapID, Zone.TYPE_CONTINENT), level, x, y)
  if mapType == Zone.TYPE_ZONE then Core.emit("FC_ZONE_NEW", mapID) end
  return true
end

local function check(self)
  local Zone = ns.Zone
  local mapID, x, y = Zone.here()
  if not mapID then return end
  local level = playerLevel()
  visitMap(mapID, level, x, y)
  -- main zone also when first arriving in a cave/city submap
  local zone = Zone.ancestor(mapID, Zone.TYPE_ZONE)
  -- always secure the main zone's name (even for visited zones; noteMap asks once per mapID and login):
  -- otherwise the book shows 'Map 27' when starting in a submap (gnomes: New Tinkertown in Dun Morogh)
  if zone then Zone.noteMap(zone) end
  if zone and zone ~= mapID then visitMap(zone, level) end
  local continent = Zone.ancestor(mapID, Zone.TYPE_CONTINENT)
  if continent and Store.putSnapshot("continents", continent, { seen = true, level = level }) then
    Zone.noteMap(continent)
    Core.emit("FC_CONTINENT_NEW", continent)
  end
  local sub = str(call(GetSubZoneText))
  if sub then
    local name = ns.Sanitize.field(sub)
    if name ~= "" and Store.putSnapshot("subzones", format("%d:%s", mapID, name), { seen = true, level = level }) then
      Store.append("SZ", mapID, name, level)
    end
  end
end

local function scheduleCheck(self)
  if self.checkOn then return end
  self.checkOn = true
  if not Core.after(self, CHECK_DELAY, function(s)
    s.checkOn = false
    check(s)
  end) then
    self.checkOn = false
  end
end

handlers.PLAYER_ENTERING_WORLD = scheduleCheck
handlers.ZONE_CHANGED = scheduleCheck
handlers.ZONE_CHANGED_INDOORS = scheduleCheck
handlers.ZONE_CHANGED_NEW_AREA = scheduleCheck

-- System messages: discovery, new flight point

local function fresh(self, key)
  local t = GetTime()
  local last = self.recent[key]
  if last and t - last < DEDUPE then return false end
  for k, at in pairs(self.recent) do
    if t - at >= DEDUPE then self.recent[k] = nil end
  end
  self.recent[key] = t
  return true
end

local function systemMessage(self, text)
  if isSecret(text) or type(text) ~= "string" then return end
  local name, xp = Patterns.match("ERR_ZONE_EXPLORED_XP", text)
  if name == nil then
    name, xp = Patterns.match("ERR_ZONE_EXPLORED", text), nil
  end
  name = str(name)
  if name then
    if fresh(self, "ex:" .. name) then Store.append("EX", name, num(xp), (ns.Zone.here()), playerLevel()) end
    return
  end
  local taxi = _G.ERR_NEWTAXIPATH
  if type(taxi) ~= "string" or isSecret(taxi) then
    Patterns.compile("ERR_NEWTAXIPATH") -- notes the missing GlobalString in diag.patterns
    return
  end
  if text == taxi and fresh(self, "fp") then
    local id = npcIdOf(call(UnitGUID, "npc"))
    local npc = str(call(UnitName, "npc"))
    if id and npc then Store.putText("npcs", id, npc) end
    local mapID, x, y = ns.Zone.here()
    Store.append("FP", id, mapID, x, y, playerLevel(), (id == nil) and npc or nil)
  end
end

handlers.CHAT_MSG_SYSTEM = function(self, text)
  systemMessage(self, text)
end

handlers.UI_INFO_MESSAGE = function(self, a, b)
  systemMessage(self, type(b) == "string" and b or a)
end

function World:onEvent(event, ...)
  local h = handlers[event]
  if h then h(self, ...) end
end

ns.RegisterCollector("World", World)
