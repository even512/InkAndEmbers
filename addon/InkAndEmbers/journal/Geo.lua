-- Map coordinate conversion, kept apart from the model so it can be swapped (Retail lacks the Classic map IDs
-- 1414/1415/1420). Reads client map data only.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Geo = {}
Journal.Geo = Geo

local floor = math.floor

Geo.CONTINENT_TYPE = 2
Geo.MAX_DEPTH = 8
Geo.ZONE_TYPE = 3
Geo.RETRY_SEC = 30
-- Plausible rect bounds on the target map. Zones can stick out past the parent map edge (2395 on 2537: -0.038).
Geo.RECT_MIN = -0.5
Geo.RECT_MAX = 1.5
-- Start zones with their own map (Retail uiMapIDs): each is its own chapter instead of part of the parent zone.
Geo.START_ZONES = { [425] = true, [427] = true, [460] = true, [461] = true, [462] = true, [463] = true, [465] = true,
  [467] = true, [468] = true, [469] = true, [2524] = true }
-- Start maps that are not zone type but belong to a start zone (gnome start 30 -> 469).
Geo.START_ALIAS = { [30] = 469 }
-- Name fallback (lower case) for start zones with unknown IDs; zone-type maps only.
Geo.START_NAMES = {}
for _, n in ipairs({
  "nordhain", "nordhaintal", "northshire", "northshire valley", "coldridgetal", "das coldridgetal", "coldridge valley",
  "neu-tüftlerstadt", "new tinkertown", "shadowglen", "tal der prüfungen", "das tal der prüfungen", "valley of trials",
  "camp narache", "deathknell", "todesend", "sonnenwanderinsel", "insel der sonnenwanderer", "sunstrider isle", "ammental",
  "ammen vale", "echoinseln", "die echoinseln", "echo isles", "zephras", "insel zephras", "zephras isle", "thendal",
}) do Geo.START_NAMES[n] = true end
-- No fixed map IDs on purpose: Retail and Forever number their maps differently.

local provider = nil
local rects, continents, sizes, zones, mains, starts = {}, {}, {}, {}, {}, {}

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d
end

local function cmap(name)
  return type(C_Map) == "table" and C_Map[name] or nil
end

local function now()
  return num((call(GetTime))) or 0
end

-- Cache entry for "unavailable": { fail = time }. lookup returns false; once expired, nil (ask again).
local function failMark() return { fail = now() } end
local function lookup(tbl, key)
  local v = tbl[key]
  if type(v) == "table" and v.fail then
    if now() - v.fail < Geo.RETRY_SEC then return false end
    tbl[key] = nil
    return nil
  end
  return v
end

function Geo.setProvider(p)
  provider = (type(p) == "table") and p or nil
  Geo.reset()
end

function Geo.reset()
  rects, continents, sizes, zones, mains, starts = {}, {}, {}, {}, {}, {}
end

function Geo.retryFailed()
  for _, tbl in ipairs({ rects, continents, sizes, zones, mains, starts }) do
    for k, v in pairs(tbl) do
      if type(v) == "table" and v.fail then tbl[k] = nil end
    end
  end
end

local function plausibleRect(a, b, c, d)
  a, b, c, d = num(a), num(b), num(c), num(d)
  if not (a and b and c and d) then return nil end
  local lo, hi = Geo.RECT_MIN, Geo.RECT_MAX
  if a < lo or c < lo or b > hi or d > hi or b <= a or d <= c then return nil end
  return a, b, c, d
end

function Geo.rect(mapID, contID)
  mapID, contID = num(mapID), num(contID)
  if not mapID or not contID then return nil end
  if mapID == contID then return 0, 1, 0, 1 end
  local key = floor(mapID) * 100000 + floor(contID)
  local r = lookup(rects, key)
  if r == nil then
    local a, b, c, d
    if provider and provider.rect then
      a, b, c, d = plausibleRect(call(provider.rect, mapID, contID))
    else
      a, b, c, d = plausibleRect(call(cmap("GetMapRectOnMap"), mapID, contID))
    end
    if a then
      r = { a, b, c, d }
      rects[key] = r
    else
      rects[key] = failMark()
      r = false
    end
  end
  if not r then return nil end
  return r[1], r[2], r[3], r[4]
end

function Geo.affine(mapID, contID)
  local a, b, c, d = Geo.rect(mapID, contID)
  if not a then return nil end
  return a, b - a, c, d - c
end

local function ancestor(mapID, wanted)
  local id, depth = mapID, 0
  while id and id > 0 and depth < Geo.MAX_DEPTH do
    local info = call(cmap("GetMapInfo"), id)
    if type(info) ~= "table" or isSecret(info) then return nil end
    local t = num(info.mapType)
    if t == wanted then return floor(id) end
    if t and t < wanted then return nil end
    id = num(info.parentMapID)
    depth = depth + 1
  end
  return nil
end

function Geo.startZoneOf(mapID)
  mapID = num(mapID)
  if not mapID or mapID <= 0 then return nil end
  mapID = floor(mapID)
  if Geo.START_ZONES[mapID] then return mapID end
  if Geo.START_ALIAS[mapID] then return Geo.START_ALIAS[mapID] end
  local v = lookup(starts, mapID)
  if v == nil then
    if provider then
      v = provider.startZoneOf and num(call(provider.startZoneOf, mapID)) or nil
    else
      local info = call(cmap("GetMapInfo"), mapID)
      if type(info) ~= "table" or isSecret(info) then
        starts[mapID] = failMark()
        return nil
      end
      local name = info.name
      if num(info.mapType) == Geo.ZONE_TYPE and type(name) == "string" and not isSecret(name)
        and Geo.START_NAMES[string.lower(name)] then v = mapID end
    end
    -- no start zone is a valid result (0), not a failure
    starts[mapID] = v or 0
  end
  if not v or v == 0 then return nil end
  return floor(v)
end

-- Outermost ancestor of type wanted: walk on until a type above wanted (continent) or the chain ends.
-- A start zone ends the chain.
local function outermost(mapID, wanted)
  local id, depth, best = mapID, 0, nil
  while id and id > 0 and depth < Geo.MAX_DEPTH do
    local info = call(cmap("GetMapInfo"), id)
    if type(info) ~= "table" or isSecret(info) then return best end
    local t = num(info.mapType)
    if t and t < wanted then return best end
    if t == wanted then
      best = floor(id)
      if Geo.startZoneOf(best) then return best end
    end
    id = num(info.parentMapID)
    depth = depth + 1
  end
  return best
end

local function chain(tbl, mapID, field, wanted, walk)
  mapID = num(mapID)
  if not mapID then return nil end
  local v = lookup(tbl, mapID)
  if v == nil then
    if provider then
      v = provider[field] and num(call(provider[field], mapID)) or nil
    else
      v = (walk or ancestor)(mapID, wanted)
    end
    tbl[mapID] = v or failMark()
  end
  return v or nil
end

function Geo.zoneOf(mapID) return chain(zones, mapID, "zoneOf", Geo.ZONE_TYPE) end
function Geo.continentOf(mapID) return chain(continents, mapID, "continentOf", Geo.CONTINENT_TYPE) end
function Geo.mainZoneOf(mapID)
  local s = Geo.startZoneOf(mapID)
  if s then return s end
  return chain(mains, mapID, "mainZoneOf", Geo.ZONE_TYPE, outermost)
end

local function corner(fn, mapID, x, y)
  local ok, vec = pcall(CreateVector2D, x, y)
  if not ok or type(vec) ~= "table" then return nil end
  local _, p = call(fn, mapID, vec)
  if type(p) ~= "table" or isSecret(p) then return nil end
  local px, py = call(p.GetXY, p)
  return num(px), num(py)
end

function Geo.mapSize(mapID)
  mapID = num(mapID)
  if not mapID then return nil end
  local s = lookup(sizes, mapID)
  if s == nil then
    local w, h
    if provider then
      if provider.mapSize then w, h = call(provider.mapSize, mapID) end
    elseif type(CreateVector2D) == "function" then
      local fn = cmap("GetWorldPosFromMapPos")
      local x0, y0 = corner(fn, mapID, 0, 0)
      local x1, y1 = corner(fn, mapID, 1, 1)
      -- World axes are swapped: map width = diff of world y, map height = diff of world x
      if x0 and y0 and x1 and y1 then w, h = math.abs(y1 - y0), math.abs(x1 - x0) end
    end
    w, h = num(w), num(h)
    if w and h and w > 1 and h > 1 and w < 100000 and h < 100000 then
      s = { w, h }
      sizes[mapID] = s
    else
      sizes[mapID] = failMark()
      s = false
    end
  end
  if not s then return nil end
  return s[1], s[2]
end

function Geo.projector(contID)
  contID = num(contID)
  local fn = function(mapID, x, y)
    if not contID or not x or not y then return nil end
    local a, b, c, d = Geo.rect(mapID, contID)
    if not a then return nil end
    return a + x * (b - a), c + y * (d - c)
  end
  local aff = function(mapID)
    if not contID then return nil end
    return Geo.affine(mapID, contID)
  end
  return fn, "geo:" .. (contID and string.format("%d", floor(contID)) or "-"), aff
end

function Geo.zoneAffine(mapID, zoneID)
  mapID, zoneID = num(mapID), num(zoneID)
  if not mapID or not zoneID then return nil end
  if mapID == zoneID then return 0, 1, 0, 1 end
  local mz = Geo.zoneOf(mapID)
  if mz == zoneID then
    local a, b, c, d = Geo.affine(mapID, zoneID)
    if a then return a, b, c, d end
  elseif mz then
    local ma, mb, mc2, md = Geo.affine(mapID, mz)
    local za, zb, zc, zd = Geo.affine(zoneID, mz)
    if ma and za and zb ~= 0 and zd ~= 0 then return (ma - za) / zb, mb / zb, (mc2 - zc) / zd, md / zd end
  end
  local cont = Geo.continentOf(zoneID)
  if not cont then return nil end
  local mc = (mapID == cont) and cont or Geo.continentOf(mapID)
  if mc ~= cont then return nil end
  local ma, mb, mc2, md = Geo.affine(mapID, cont)
  local za, zb, zc, zd = Geo.affine(zoneID, cont)
  if not (ma and za) or zb == 0 or zd == 0 then return nil end
  -- continent: cx = ma + mb * x; zone: zx = (cx - za) / zb
  return (ma - za) / zb, mb / zb, (mc2 - zc) / zd, md / zd
end

function Geo.zoneProjector(zoneID)
  zoneID = num(zoneID)
  local memo = {}
  local aff = function(mapID)
    if not zoneID then return nil end
    mapID = num(mapID)
    if not mapID then return nil end
    local e = memo[mapID]
    if e == nil then
      local a, b, c, d = Geo.zoneAffine(mapID, zoneID)
      -- Only successes are kept: a failure (map data not ready yet, Geo's own retry cache) must not hide a map's route and the
      -- player arrow for the whole life of the scene.
      if not a then return nil end
      e = { a, b, c, d }
      memo[mapID] = e
    end
    return e[1], e[2], e[3], e[4]
  end
  local fn = function(mapID, x, y)
    if not x or not y then return nil end
    local a, b, c, d = aff(mapID)
    if not a then return nil end
    return a + b * x, c + d * y
  end
  return fn, "zone:" .. (zoneID and string.format("%d", floor(zoneID)) or "-"), aff
end

-- After a loading screen map data may exist that was missing before: retry failures.
if ns.Core and ns.Core.on then
  ns.Core.on("PLAYER_ENTERING_WORLD", Geo.retryFailed)
  ns.Core.on("ZONE_CHANGED_NEW_AREA", Geo.retryFailed)
end
