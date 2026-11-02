-- Maps data-space map IDs (Forever, Classic-Era IDs: 1411 Durotar, 1414 Kalimdor) to the client's map space
-- (Retail: Durotar 1, Kalimdor 12). Map and point are converted via the world rect of the Forever map. Zone maps are
-- not all congruent (Mulgore, Barrens, Orgrimmar, Dun Morogh, Hillsbrad ...); identical maps carry no conversion, and a
-- point on no Retail candidate map is dropped.
-- Source: wago.tools UiMap / UiMapAssignment, Forever build 1.60.1.70170, Retail build 12.1.5.70575. World rect with
-- UiMin 0,0 / UiMax 1,1 (Region_0/1 = min X/Y, Region_3/4 = max X/Y); map x runs along descending world Y, map y
-- along descending world X.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local MapSpace = {}
Journal.MapSpace = MapSpace

local floor = math.floor

-- Tolerance at the map edge (rounding of data points): clamped up to here, beyond it the point counts as outside.
MapSpace.EDGE = 0.005

-- ZONES[ForeverID] = { c = continent (0 = none), a = helper mapping, r = { { RetailID[, ax, bx, ay, by] }, ... } }
-- Candidates in priority order; without coefficients the maps are congruent, else rx = ax + bx * x, ry = ay + by * y.
local ZONES = {
  [947] = { c = 0, r = { { 947 } } }, -- Azeroth
  [1411] = { c = 1414, r = { { 1 } } }, -- Durotar
  [1412] = { c = 1414, r = { { 7, -0.050458, 1.129205, -0.119839, 1.129014 }, { 65, 0.241172, 1.043079, 0.79767, 1.042901 } } }, -- Mulgore
  [1413] = { c = 1414, r = { { 10, -0.42132, 1.763597, 0.051659, 1.763458 }, { 199, -0.170882, 1.36706, -0.284991, 1.367201 }, { 64, -0.694603, 2.303032, -1.901992, 2.30327 } } }, -- The Barrens
  [1414] = { c = 0, r = { { 12, 0, 1, -0.02, 1 } } }, -- Kalimdor
  [1415] = { c = 0, r = { { 13, 0.070791, 0.845897, 0.176857, 0.845896 } } }, -- Eastern Kingdoms
  [1416] = { c = 1415, a = true, r = { { 25, 0.219366, 0.575835, -0.005784, 0.575835 } } }, -- Alterac Mountains
  [1417] = { c = 1415, r = { { 14, -0.074894, 1.035348, -0.003594, 1.035039 } } }, -- Arathi Highlands
  [1418] = { c = 1415, r = { { 15, 0.057667, 0.810039, 0.01731, 0.810592 } } }, -- Badlands
  [1419] = { c = 1415, r = { { 17, 0.013083, 0.914676, -0.006812, 0.914663 } } }, -- Blasted Lands
  [1420] = { c = 1415, r = { { 18 } } }, -- Tirisfal Glades
  [1421] = { c = 1415, r = { { 21, 0, 1, 0.000001, 1 } } }, -- Silverpine Forest
  [1422] = { c = 1415, r = { { 22, 0, 1.000001, 0.000001, 0.999999 } } }, -- Western Plaguelands
  [1423] = { c = 1415, r = { { 23, -0.007752, 1.067184, 0.004652, 1.066667 } } }, -- Eastern Plaguelands
  [1424] = { c = 1415, r = { { 25, 0.161097, 0.658098, 0.333547, 0.658097 } } }, -- Hillsbrad Foothills
  [1425] = { c = 1415, r = { { 26, 0, 1, 0.000001, 0.999999 } } }, -- The Hinterlands
  [1426] = { c = 1415, r = { { 27, 0.068481, 1.005529, -0.019784, 1.005744 } } }, -- Dun Morogh
  [1427] = { c = 1415, r = { { 32, 0, 0.999999, 0, 1 } } }, -- Searing Gorge
  [1428] = { c = 1415, r = { { 36, -0.062789, 0.929278, 0.021824, 0.929564 } } }, -- Burning Steppes
  [1429] = { c = 1415, r = { { 37, 0.000001, 0.999998, 0.000001, 0.999984 } } }, -- Elwynn Forest
  [1430] = { c = 1415, r = { { 42 } } }, -- Deadwind Pass
  [1431] = { c = 1415, r = { { 47, 0, 0.999999, -0.000002, 0.999983 } } }, -- Duskwood
  [1432] = { c = 1415, r = { { 48, 0, 1.000001, 0, 1.000002 } } }, -- Loch Modan
  [1433] = { c = 1415, r = { { 49, 0.078669, 0.845094, 0.035281, 0.845489 } } }, -- Redridge Mountains
  [1434] = { c = 1415, r = { { 224, 0.115421, 0.973927, 0.04673, 0.973783 } } }, -- Stranglethorn Vale
  [1435] = { c = 1415, r = { { 51, 0.056478, 0.914453, 0.051058, 0.914093 } } }, -- Swamp of Sorrows
  [1436] = { c = 1415, r = { { 52, 0.000001, 0.999999, 0, 1.000014 } } }, -- Westfall
  [1437] = { c = 1415, r = { { 56, 0, 1, -0.000001, 1 } } }, -- Wetlands
  [1438] = { c = 1414, r = { { 57, 0.071632, 0.866667, 0.004251, 0.866493 } } }, -- Teldrassil
  [1439] = { c = 1414, r = { { 62, 0.011602, 1.013212, -0.025615, 1.013049 } } }, -- Darkshore
  [1440] = { c = 1414, r = { { 63 } } }, -- Ashenvale
  [1441] = { c = 1414, r = { { 64, 0, 1.000001, -0.000001, 1.000001 } } }, -- Thousand Needles
  [1442] = { c = 1414, r = { { 65, 0.111228, 0.827684, 0.123941, 0.827859 } } }, -- Stonetalon Mountains
  [1443] = { c = 1414, r = { { 66, -0.000001, 1.000001, 0, 1.000001 } } }, -- Desolace
  [1444] = { c = 1414, r = { { 69 } } }, -- Feralas
  [1445] = { c = 1414, r = { { 70 } } }, -- Dustwallow Marsh
  [1446] = { c = 1414, r = { { 71, 0.021664, 0.956672, 0.021664, 0.956665 } } }, -- Tanaris
  [1447] = { c = 1414, r = { { 76, -0.017379, 0.919532, 0.010765, 0.919548 } } }, -- Azshara
  [1448] = { c = 1414, r = { { 77, 0.025774, 0.948454, 0.025773, 0.948453 } } }, -- Felwood
  [1449] = { c = 1414, r = { { 78, 0, 0.999999, -0.000001, 1.000003 } } }, -- Un'Goro Crater
  [1450] = { c = 1414, r = { { 80, 0, 1.000001, 0.000003, 0.999996 } } }, -- Moonglade
  [1451] = { c = 1414, r = { { 81, 0.109856, 0.858317, 0.031562, 0.858352 } } }, -- Silithus
  [1452] = { c = 1414, r = { { 83, -0.109756, 1.154471, 0.063516, 1.154472 } } }, -- Winterspring
  [1453] = { c = 1415, r = { { 84, -0.000002, 1.000002, -0.000003, 1.000007 } } }, -- Stormwind City
  [1454] = { c = 1414, r = { { 85, 0.100178, 0.806384, 0.183505, 0.806683 } } }, -- Orgrimmar
  [1455] = { c = 1415, r = { { 87 } } }, -- Ironforge
  [1456] = { c = 1414, r = { { 88 } } }, -- Thunder Bluff
  [1457] = { c = 1414, r = { { 89, 0.161821, 0.687415, 0.2203, 0.68712 } } }, -- Darnassus
  [1458] = { c = 1415, r = { { 90 } } }, -- Undercity
  [2482] = { c = 1414, r = { { 198, -0.001472, 0.817959, -0.038264, 0.817513 } } }, -- Mount Hyjal
  [2521] = { c = 0, r = {  } }, -- Zephras Isle
  [2524] = { c = 1414, r = {  } }, -- Darkspear Islands
  [2548] = { c = 1415, r = {  } }, -- Riverglades
  [2652] = { c = 1414, a = true, r = { { 69, 0.491607, 0.294964, -0.10072, 0.294964 }, { 66, 0.491195, 0.455978, 0.784573, 0.455872 } } }, -- Shen'dralas
}
MapSpace.ZONES = ZONES

-- NAMES[uiMapID] = { deDE, enUS }
local NAMES = {
  [1] = { "Durotar", "Durotar" },
  [7] = { "Mulgore", "Mulgore" },
  [10] = { "Nördliches Brachland", "Northern Barrens" },
  [12] = { "Kalimdor", "Kalimdor" },
  [13] = { "Die Östlichen Königreiche", "Eastern Kingdoms" },
  [14] = { "Arathihochland", "Arathi Highlands" },
  [15] = { "Ödland", "Badlands" },
  [17] = { "Verwüstete Lande", "Blasted Lands" },
  [18] = { "Tirisfal", "Tirisfal Glades" },
  [21] = { "Silberwald", "Silverpine Forest" },
  [22] = { "Westliche Pestländer", "Western Plaguelands" },
  [23] = { "Östliche Pestländer", "Eastern Plaguelands" },
  [25] = { "Vorgebirge des Hügellands", "Hillsbrad Foothills" },
  [26] = { "Hinterland", "The Hinterlands" },
  [27] = { "Dun Morogh", "Dun Morogh" },
  [32] = { "Sengende Schlucht", "Searing Gorge" },
  [36] = { "Brennende Steppe", "Burning Steppes" },
  [37] = { "Wald von Elwynn", "Elwynn Forest" },
  [42] = { "Gebirgspass der Totenwinde", "Deadwind Pass" },
  [47] = { "Dämmerwald", "Duskwood" },
  [48] = { "Loch Modan", "Loch Modan" },
  [49] = { "Rotkammgebirge", "Redridge Mountains" },
  [51] = { "Sümpfe des Elends", "Swamp of Sorrows" },
  [52] = { "Westfall", "Westfall" },
  [56] = { "Sumpfland", "Wetlands" },
  [57] = { "Teldrassil", "Teldrassil" },
  [62] = { "Dunkelküste", "Darkshore" },
  [63] = { "Eschental", "Ashenvale" },
  [64] = { "Tausend Nadeln", "Thousand Needles" },
  [65] = { "Steinkrallengebirge", "Stonetalon Mountains" },
  [66] = { "Desolace", "Desolace" },
  [69] = { "Feralas", "Feralas" },
  [70] = { "Düstermarschen", "Dustwallow Marsh" },
  [71] = { "Tanaris", "Tanaris" },
  [76] = { "Azshara", "Azshara" },
  [77] = { "Teufelswald", "Felwood" },
  [78] = { "Krater von Un'Goro", "Un'Goro Crater" },
  [80] = { "Mondlichtung", "Moonglade" },
  [81] = { "Silithus", "Silithus" },
  [83] = { "Winterquell", "Winterspring" },
  [84] = { "Sturmwind", "Stormwind City" },
  [85] = { "Orgrimmar", "Orgrimmar" },
  [87] = { "Eisenschmiede", "Ironforge" },
  [88] = { "Donnerfels", "Thunder Bluff" },
  [89] = { "Darnassus", "Darnassus" },
  [90] = { "Unterstadt", "Undercity" },
  [198] = { "Der Hyjal", "Mount Hyjal" },
  [199] = { "Südliches Brachland", "Southern Barrens" },
  [224] = { "Schlingendorntal", "Stranglethorn Vale" },
  [947] = { "Azeroth", "Azeroth" },
  [1411] = { "Durotar", "Durotar" },
  [1412] = { "Mulgore", "Mulgore" },
  [1413] = { "Das Brachland", "The Barrens" },
  [1414] = { "Kalimdor", "Kalimdor" },
  [1415] = { "Östliche Königreiche", "Eastern Kingdoms" },
  [1416] = { "Alteracgebirge", "Alterac Mountains" },
  [1417] = { "Arathihochland", "Arathi Highlands" },
  [1418] = { "Ödland", "Badlands" },
  [1419] = { "Verwüstete Lande", "Blasted Lands" },
  [1420] = { "Tirisfal", "Tirisfal Glades" },
  [1421] = { "Silberwald", "Silverpine Forest" },
  [1422] = { "Westliche Pestländer", "Western Plaguelands" },
  [1423] = { "Östliche Pestländer", "Eastern Plaguelands" },
  [1424] = { "Vorgebirge von Hillsbrad", "Hillsbrad Foothills" },
  [1425] = { "Hinterland", "The Hinterlands" },
  [1426] = { "Dun Morogh", "Dun Morogh" },
  [1427] = { "Sengende Schlucht", "Searing Gorge" },
  [1428] = { "Brennende Steppe", "Burning Steppes" },
  [1429] = { "Wald von Elwynn", "Elwynn Forest" },
  [1430] = { "Gebirgspass der Totenwinde", "Deadwind Pass" },
  [1431] = { "Dämmerwald", "Duskwood" },
  [1432] = { "Loch Modan", "Loch Modan" },
  [1433] = { "Rotkammgebirge", "Redridge Mountains" },
  [1434] = { "Schlingendorntal", "Stranglethorn Vale" },
  [1435] = { "Sümpfe des Elends", "Swamp of Sorrows" },
  [1436] = { "Westfall", "Westfall" },
  [1437] = { "Sumpfland", "Wetlands" },
  [1438] = { "Teldrassil", "Teldrassil" },
  [1439] = { "Dunkelküste", "Darkshore" },
  [1440] = { "Eschental", "Ashenvale" },
  [1441] = { "Tausend Nadeln", "Thousand Needles" },
  [1442] = { "Steinkrallengebirge", "Stonetalon Mountains" },
  [1443] = { "Desolace", "Desolace" },
  [1444] = { "Feralas", "Feralas" },
  [1445] = { "Marschen von Dustwallow", "Dustwallow Marsh" },
  [1446] = { "Tanaris", "Tanaris" },
  [1447] = { "Azshara", "Azshara" },
  [1448] = { "Teufelswald", "Felwood" },
  [1449] = { "Un'Goro-Krater", "Un'Goro Crater" },
  [1450] = { "Mondlichtung", "Moonglade" },
  [1451] = { "Silithus", "Silithus" },
  [1452] = { "Winterquell", "Winterspring" },
  [1453] = { "Sturmwind", "Stormwind City" },
  [1454] = { "Orgrimmar", "Orgrimmar" },
  [1455] = { "Eisenschmiede", "Ironforge" },
  [1456] = { "Donnerfels", "Thunder Bluff" },
  [1457] = { "Darnassus", "Darnassus" },
  [1458] = { "Unterstadt", "Undercity" },
  [2482] = { "Hyjal", "Mount Hyjal" },
  [2521] = { "Insel Zephras", "Zephras Isle" },
  [2524] = { "Darkspear-Inseln", "Darkspear Islands" },
  [2548] = { "Flusslande", "Riverglades" },
  [2652] = { "Shen'dralas", "Shen'dralas" },
}
MapSpace.NAMES = NAMES

-- Reverse mapping and Retail continents from ZONES. The reverse target is the Forever map whose FIRST candidate is the
-- Retail map (Stonetalon 65 -> 1442, not the Mulgore overhang), else the first other mention (Southern Barrens 199 -> 1413).
-- a = true: helper mapping, never a reverse target.
local INV, RETAIL_CONT = {}, {}
for fid, z in pairs(ZONES) do
  if not z.a and z.r[1] then INV[z.r[1][1]] = fid end
end
for fid, z in pairs(ZONES) do
  if not z.a then
    for i = 2, #z.r do
      local rid = z.r[i][1]
      if INV[rid] == nil then INV[rid] = fid end
    end
  end
end
for fid, z in pairs(ZONES) do
  local cont = z.c ~= 0 and ZONES[z.c] and ZONES[z.c].r[1] and ZONES[z.c].r[1][1] or nil
  if cont then
    for _, cand in ipairs(z.r) do RETAIL_CONT[cand[1]] = RETAIL_CONT[cand[1]] or cont end
  end
end

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

-- Retail client? Doubly checked: WOW_PROJECT_ID == WOW_PROJECT_MAINLINE AND interface version >= 100000. WoW Forever runs
-- on the retail engine and may report the same project id as Retail, but its interface version is 16001.
MapSpace.RETAIL_MIN_INTERFACE = 100000
function MapSpace.retailClient()
  local id, main = num(rawget(_G, "WOW_PROJECT_ID")), num(rawget(_G, "WOW_PROJECT_MAINLINE"))
  if not (id and main and id == main) then return false end
  if type(GetBuildInfo) ~= "function" then return false end
  local ok, _, _, _, interface = pcall(GetBuildInfo)
  interface = ok and num(interface) or nil
  return interface ~= nil and interface >= MapSpace.RETAIL_MIN_INTERFACE
end

-- Highest player level of the client: WoW Forever always 60; Retail asks GetMaxLevelForPlayerExpansion (the expansion the
-- account owns), else GetMaxPlayerLevel. Every call under pcall, secret/odd values ignored; fallback 60.
MapSpace.FOREVER_MAX_LEVEL = 60
MapSpace.MAX_LEVEL_CAP = 200 -- plausibility limit for the client answer
local MAX_LEVEL_APIS = { "GetMaxLevelForPlayerExpansion", "GetMaxPlayerLevel" }
function MapSpace.maxLevel()
  local base = MapSpace.FOREVER_MAX_LEVEL
  if not MapSpace.retailClient() then return base end
  for _, name in ipairs(MAX_LEVEL_APIS) do
    local fn = rawget(_G, name)
    if type(fn) == "function" then
      local ok, v = pcall(fn)
      v = ok and num(v) or nil
      if v and v == floor(v) and v >= base and v <= MapSpace.MAX_LEVEL_CAP then return v end
    end
  end
  return base
end

-- Campfire talk (Campfire.lua, FireNotes.lua) only recognizes the Forever auras, so in Retail it never starts: the interface hides
-- everything about it there (options, tutorial page, Chronik tab "Am Feuer"). Exception: the development simulation (/chronik sim)
-- is running, then the campfire parts stay visible. MapSpace.ALLOW_FIRE_RETAIL = true: never hide (tests).
function MapSpace.fireTalkHidden()
  if MapSpace.ALLOW_FIRE_RETAIL or not MapSpace.retailClient() then return false end
  local C = ns.Campfire
  if C and type(C.isSim) == "function" then
    local ok, on = pcall(C.isSim)
    if ok and on == true then return false end
  end
  return true
end

function MapSpace.client()
  if not num(rawget(_G, "WOW_PROJECT_ID")) then return nil end
  if MapSpace.retailClient() then return "retail" end
  return "data"
end

local function inside(v)
  local e = MapSpace.EDGE
  if v < -e or v > 1 + e then return nil end
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end

function MapSpace.toClient(mapID, x, y, space)
  mapID, x, y = num(mapID), num(x), num(y)
  if not (mapID and x and y) then return nil end
  mapID = floor(mapID)
  if space ~= "retail" then return mapID, x, y end
  local z = ZONES[mapID]
  if not z then return nil end
  for _, cand in ipairs(z.r) do
    local cx, cy = x, y
    if cand[2] then cx, cy = cand[2] + cand[3] * x, cand[4] + cand[5] * y end
    cx, cy = inside(cx), inside(cy)
    if cx and cy then return cand[1], cx, cy end
  end
  return nil
end

function MapSpace.mapToClient(mapID, space)
  mapID = num(mapID)
  if not mapID then return nil end
  mapID = floor(mapID)
  if space ~= "retail" then return mapID end
  local z = ZONES[mapID]
  return z and z.r[1] and z.r[1][1] or nil
end

function MapSpace.fromClient(clientID, space)
  clientID = num(clientID)
  if not clientID then return nil end
  clientID = floor(clientID)
  if space ~= "retail" then return clientID end
  return INV[clientID]
end

function MapSpace.continentOf(id)
  id = num(id)
  if not id then return nil end
  id = floor(id)
  local z = ZONES[id]
  if z then return z.c ~= 0 and z.c or nil end
  return RETAIL_CONT[id]
end

function MapSpace.name(id)
  id = num(id)
  local n = id and NAMES[floor(id)]
  if not n then return nil end
  local loc = type(GetLocale) == "function" and select(2, pcall(GetLocale)) or nil
  if loc == "deDE" then return n[1] end
  return n[2]
end
