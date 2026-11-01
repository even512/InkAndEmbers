-- ns.Zone: current map and position. Map names are cached once per mapID in snapshots.maps[mapID].name (capped by Store.LIMITS.maps).
-- Zone.coord is the only map fraction -> tenth-of-a-permille conversion (also used by the trail).
local _, ns = ...
local Store = ns.Store

local floor = math.floor

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
  local ok, a, b, c, d = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d
end

local Zone = {}
ns.Zone = Zone

-- Enum.UIMapType: 0 Cosmic, 1 World, 2 Continent, 3 Zone, 4 Dungeon, 5 Micro, 6 Orphan
Zone.TYPE_CONTINENT = 2
Zone.TYPE_ZONE = 3
Zone.MAX_DEPTH = 8

local knownMaps = {} -- mapID -> true once the name is stored or can no longer be stored

-- reset per login (other character, other snapshots.maps)
function Zone.reset()
  knownMaps = {}
end

-- map fraction 0..1 -> tenths of a permille 0..9999; nil for secret/invalid values
function Zone.coord(v)
  v = num(v)
  if not v or v < 0 or v > 1 then return nil end
  local c = floor(v * 10000 + 0.5)
  if c > 9999 then c = 9999 end
  return c
end

function Zone.info(mapID)
  if not num(mapID) then return nil end
  local info = call(C_Map and C_Map.GetMapInfo, mapID)
  if type(info) ~= "table" or isSecret(info) then return nil end
  return info
end

function Zone.noteMap(mapID)
  if knownMaps[mapID] then return end
  local info = Zone.info(mapID)
  local name = info and str(info.name) or nil
  if name and Store.char() then
    -- stored once; not retried above the limit (diag.limits)
    Store.putSnapshot("maps", mapID, { name = name })
    knownMaps[mapID] = true
  end
end

-- parent map of the given type (main zone, continent), the map itself included; nil if none
function Zone.ancestor(mapID, mapType)
  local id, depth = num(mapID), 0
  while id and id > 0 and depth < Zone.MAX_DEPTH do
    local info = Zone.info(id)
    if not info then return nil end
    local t = num(info.mapType)
    if t == mapType then return floor(id) end
    if t and t < mapType then return nil end
    id = num(info.parentMapID)
    depth = depth + 1
  end
  return nil
end

-- current mapID and raw map fractions 0..1; nil if unreadable
function Zone.raw()
  local mapID = num(call(C_Map and C_Map.GetBestMapForUnit, "player"))
  if not mapID or mapID <= 0 then return nil end
  mapID = floor(mapID)
  Zone.noteMap(mapID)
  local pos = call(C_Map and C_Map.GetPlayerMapPosition, mapID, "player")
  if type(pos) == "table" and not isSecret(pos) then
    local px, py = call(pos.GetXY, pos)
    px, py = num(px), num(py)
    if px and py and Zone.coord(px) and Zone.coord(py) then return mapID, px, py end
  end
  return mapID, nil, nil
end

-- mapID, x, y (tenths of a permille); all nil if the client withholds the map
function Zone.here()
  local mapID, px, py = Zone.raw()
  if not mapID then return nil end
  if px then return mapID, Zone.coord(px), Zone.coord(py) end
  return mapID, nil, nil
end

-- current subzone (GetSubZoneText) for the last field of MO, SH, LV and DE; sanitized, capped at SUB_MAX bytes; nil if empty or secret
Zone.SUB_MAX = 60
function Zone.sub()
  local name = str(call(GetSubZoneText))
  if not name then return nil end
  name = ns.Sanitize.field(name)
  if name == "" then return nil end
  return (string.gsub(ns.Sanitize.cut(name, Zone.SUB_MAX), " +$", ""))
end

if ns.Core and ns.Core.on then ns.Core.on("PLAYER_LOGIN", Zone.reset) end
