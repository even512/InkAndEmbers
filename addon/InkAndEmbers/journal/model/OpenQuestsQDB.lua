-- Open quests, live source (Forever only): reads quests and quest givers from the separately installed addon QuestieDB
-- (optional dependency, public API LibQuestieDB, docs/api.md of QuestieDB) and builds the same compact records as the
-- parser of the data addon InkAndEmbers_QuestData (journal/model/OpenQuests.lua, adopt): quests[id] = { id, name, minLevel,
-- level, races, classes, preAll, preAny, excl, flags, givers = keys }, givers[key] = { kind, id, name, maps = { { mapID,
-- points = { { x, y } } } } } (x/y 0-1, at most MAX_POINTS per map like thinPoints in scripts/build-quest-data.mjs).
-- Rules (change "questiedb", A2-A5):
--   * used only when QDB.probe() says so: never in the retail client (checked first, QuestieDB is not touched there), the
--     addon is loaded, LibQuestieDB is a table in baked mode, flavor Forever, RequireContract(1) passes, OpenQuests.QDB_LIVE.
--   * access only through LibQuestieDB.Quest/Npc/Object/Support/l10n, never through the short globals (QuestDB, NpcDB, ...).
--   * never l10n.SetLocale (global state owned by Questie); German names only while l10n.currentLocale is "deDE", English
--     names through GetRaw (Get when the active QuestieDB locale is enUS). Missing German names: the caller's client cache
--     (noDE, as with the data addon).
--   * the work runs in a coroutine (QDB.newJob / QDB.step) with a time budget per frame; the caller schedules it (never in
--     combat). No yield inside pcall (Lua 5.1): every QuestieDB call is a single pcall, yields happen between records.
--   * zone tables (Support ZoneDB, Lua source strings) are loaded with loadstring in an empty environment, inside pcall,
--     with a size limit; only number -> number entries are kept. Dungeon areas are dropped like instances in the build.
--   * no InvalidateCache: QuestieDB keeps the warmed cache (decision F6, counted as QuestieDB memory).
--   * memory: with opts.base (the data addon's parsed records) every record that comes out equal (QDB.sameQuest /
--     QDB.sameGiver) is the base's table itself, so after the switch the live data costs about what the data addon cost and
--     the build holds little more than the differing records. Flag sets are shared per combination, records are built
--     without preallocated empty fields.
-- Names are cleaned like cleanName in the build (no control characters or '|', 80 bytes); display still goes through
-- Sanitize.display in OpenQuests.lua.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local QDB = {}
Journal.OpenQuestsQDB = QDB

local find, sub, gsub, match, lower = string.find, string.sub, string.gsub, string.match, string.lower
local floor, tonumber, sort = math.floor, tonumber, table.sort

QDB.ADDON = "QuestieDB"
QDB.FLAVOR = "Forever"
QDB.CONTRACT = 1 -- we read only entity fields (contract 1); RequireContract checks the provider's range
QDB.MAX_POINTS = 4 -- per map, as MAX_POINTS_PER_MAP in the build
QDB.MAX_LEVEL = 100
QDB.MAX_ID = 10000000
QDB.NAME_MAX = 80 -- bytes, as MAX_NAME_BYTES in the build
QDB.ZONE_MAX_BYTES = 2 * 1024 * 1024 -- per zone table source string
QDB.ZONE_DEPTH = 8 -- parent chain
QDB.VERSION_MAX = 40

-- categories (negative zoneOrSort) that count as group content: the "event" group of the Forever database plus
-- Battlegrounds/Epic/Legendary (GROUP_SORTS in the build)
local GROUP_SORTS = {}
for _, v in ipairs({ -21, -22, -41, -364, -365, -366, -368, -369, -370, -374, -375, -376, -378, -402, -404, -641, -644,
  -25, -1, -344 }) do GROUP_SORTS[v] = true end
QDB.GROUP_SORTS = GROUP_SORTS

local QUEST_KEYS = { "startedBy", "requiredLevel", "questLevel", "requiredRaces", "requiredClasses", "preQuestGroup",
  "preQuestSingle", "exclusiveTo", "zoneOrSort", "requiredSkill", "requiredMinRep", "requiredMaxRep", "specialFlags",
  "breadcrumbForQuestId", "requiredSpell", "requiredMaxLevel" }
QDB.QUEST_KEYS = QUEST_KEYS

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

-- whole number (non-integers rounded, like int() in the build)
local function int(v)
  v = num(v)
  if not v then return nil end
  return floor(v + 0.5)
end

local function retail()
  local ms = Journal.MapSpace
  return ms ~= nil and type(ms.retailClient) == "function" and ms.retailClient() == true
end

-- ---------------------------------------------------------------- availability

-- Is the live source usable? Returns ok, reason[, lib]. Reasons: RETAIL, OFF, NO_API, NOT_LOADED, NO_LIB, NOT_BAKED,
-- FLAVOR, CONTRACT, ACTIVE. Retail is checked first and returns before anything about QuestieDB is read.
function QDB.probe()
  if retail() then return false, "RETAIL" end
  local OQ = Journal.OpenQuests
  if OQ and OQ.QDB_LIVE == false then return false, "OFF" end
  local C = type(C_AddOns) == "table" and C_AddOns or nil
  local isLoaded = C and C.IsAddOnLoaded or nil
  if type(isLoaded) ~= "function" then isLoaded = rawget(_G, "IsAddOnLoaded") end
  if type(isLoaded) ~= "function" then return false, "NO_API" end
  local ok, a, b = pcall(isLoaded, QDB.ADDON)
  if not ok or isSecret(a) or isSecret(b) then return false, "NO_API" end
  -- C_AddOns.IsAddOnLoaded returns loadedOrLoading, loaded
  if a ~= true or (b ~= nil and b ~= true) then return false, "NOT_LOADED" end
  local lib = rawget(_G, "LibQuestieDB")
  if type(lib) ~= "table" then return false, "NO_LIB" end
  if lib.readMode ~= "baked" then return false, "NOT_BAKED" end
  local flavor = lib.flavor
  if type(flavor) ~= "table" or flavor.name ~= QDB.FLAVOR then return false, "FLAVOR" end
  if type(lib.RequireContract) ~= "function" then return false, "CONTRACT" end
  local okC, pass = pcall(lib.RequireContract, QDB.CONTRACT)
  if not okC or pass ~= true then return false, "CONTRACT" end
  for _, e in ipairs({ "Quest", "Npc", "Object" }) do
    local ent = lib[e]
    if type(ent) ~= "table" or type(ent.Get) ~= "function" or type(ent.GetAllIds) ~= "function" then return false, "NO_LIB" end
  end
  if type(lib.Support) ~= "table" or type(lib.Support.Get) ~= "function" then return false, "NO_LIB" end
  return true, "ACTIVE", lib
end

-- TOC metadata reader (never in retail): the field as a short plain token; nil when absent, nil + "invalid" when present but
-- not a plain token (so the diagnostics can tell "not installed" from "garbage")
local function tocField(field)
  if retail() then return nil end
  local C = type(C_AddOns) == "table" and C_AddOns or nil
  local get = C and C.GetAddOnMetadata or rawget(_G, "GetAddOnMetadata")
  if type(get) ~= "function" then return nil end
  local ok, v = pcall(get, QDB.ADDON, field)
  if not ok or isSecret(v) or type(v) ~= "string" then return nil end
  v = match(v, "^%s*(.-)%s*$")
  if v == "" then return nil end
  if #v > QDB.VERSION_MAX or not match(v, "^[%w%.%-%+_]+$") then return nil, "invalid" end
  return v
end

-- is the metadata API there at all (diagnostics: no API = no line)
function QDB.metaAvailable()
  if retail() then return false end
  local C = type(C_AddOns) == "table" and C_AddOns or nil
  return type(C and C.GetAddOnMetadata or rawget(_G, "GetAddOnMetadata")) == "function"
end

function QDB.version() return tocField("Version") end
function QDB.contract() return tocField("X-Contract-Version") end

-- ---------------------------------------------------------------- pure helpers (ported from scripts/build-quest-data.mjs)

local function cut(s, max)
  local S_ = ns.Sanitize
  if S_ and S_.cut then return S_.cut(s, max) end
  return sub(s, 1, max)
end

-- cleanName: control characters, '|' and zero-width/line separators -> space, spaces collapsed, trimmed, 80 bytes
function QDB.cleanName(s)
  if isSecret(s) or type(s) ~= "string" then return nil end
  s = gsub(s, "[%c|]", " ")
  s = gsub(s, "\226\128[\139-\143\168\169]", " ")
  s = gsub(s, "\239\187\191", " ")
  s = gsub(s, "%s+", " ")
  s = gsub(s, "^ ", "")
  s = gsub(s, " $", "")
  if s == "" then return nil end
  s = cut(s, QDB.NAME_MAX)
  return s ~= "" and s or nil
end

-- placeholder quests of the base data (PLACEHOLDER in the build)
local PLACEHOLDER_WORDS = { "%f[%w_]unused%f[^%w_]", "%f[%w_]deprecated%f[^%w_]", "%f[%w_]nyi%f[^%w_]" }
function QDB.placeholder(name)
  local l = lower(name)
  if find(l, "(only gm", 1, true) or find(l, "[ph]", 1, true) then return true end
  if sub(l, 1, 1) == "[" or match(l, "^<.*>$") then return true end
  for i = 1, #PLACEHOLDER_WORDS do
    if find(l, PLACEHOLDER_WORDS[i]) then return true end
  end
  return find(l, "%f[%w_]zzold") ~= nil
end

-- at most max points per map, deterministic: rounded to 0.1, no duplicates, sorted, then farthest-point sampling
function QDB.thinPoints(points, max)
  max = max or QDB.MAX_POINTS
  local seen, uniq = {}, {}
  for _, p in ipairs(points) do
    local kx, ky = floor(p[1] * 10 + 0.5), floor(p[2] * 10 + 0.5)
    local k = kx * 2048 + ky
    if not seen[k] then
      seen[k] = true
      uniq[#uniq + 1] = { kx / 10, ky / 10 }
    end
  end
  local function byXY(a, b)
    if a[1] ~= b[1] then return a[1] < b[1] end
    return a[2] < b[2]
  end
  sort(uniq, byXY)
  if #uniq <= max then return uniq end
  local function d2(a, b) return (a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 end
  local chosen = { 1 }
  local minD = {}
  for i = 1, #uniq do minD[i] = d2(uniq[i], uniq[1]) end
  while #chosen < max do
    local best
    for i = 1, #uniq do
      if not best or minD[i] > minD[best] then best = i end
    end
    chosen[#chosen + 1] = best
    for i = 1, #uniq do
      local d = d2(uniq[i], uniq[best])
      if d < minD[i] then minD[i] = d end
    end
  end
  local out = {}
  for i, idx in ipairs(chosen) do out[i] = uniq[idx] end
  sort(out, byXY)
  return out
end

-- quest IDs: whole numbers 1..MAX_ID, unique, ascending (idList in the build)
local function idList(v, into)
  local out = into or {}
  if type(v) == "number" then v = { v } end
  if type(v) ~= "table" or isSecret(v) then return out end
  for _, x in pairs(v) do
    x = int(x)
    if x and x > 0 and x <= QDB.MAX_ID then out[#out + 1] = x end
  end
  return out
end

local function uniqSorted(list, skip)
  if #list == 0 then return nil end
  sort(list)
  local out, last = {}, nil
  for _, x in ipairs(list) do
    if x ~= last and x ~= skip then out[#out + 1] = x end
    last = x
  end
  return #out > 0 and out or nil
end

-- valid quest ID in v (number or list)? no table is built
local function hasId(v)
  if type(v) == "number" then
    local x = int(v)
    return x ~= nil and x > 0 and x <= QDB.MAX_ID
  end
  if type(v) ~= "table" or isSecret(v) then return false end
  for _, x in pairs(v) do
    x = int(x)
    if x and x > 0 and x <= QDB.MAX_ID then return true end
  end
  return false
end

-- sorted unique ID list of v and extra (both optional), without skip; nil when empty (a table only when there is an ID)
local function idsOf(v, extra, skip)
  if not hasId(v) and not hasId(extra) then return nil end
  local list = idList(v)
  idList(extra, list)
  return uniqSorted(list, skip)
end

local function nonEmpty(t)
  return type(t) == "table" and not isSecret(t) and next(t) ~= nil
end

local function level(v)
  local n = int(v)
  return (n and n >= 1 and n <= QDB.MAX_LEVEL) and n or nil
end

local function mask(v)
  local n = int(v)
  return (n and n > 0) and n or 0
end

-- ---------------------------------------------------------------- zones

-- Lua source string of QuestieDB's ZoneDB -> table (empty environment, pcall, size limit); a table is taken as it is
local function loadTable(src)
  if type(src) == "table" and not isSecret(src) then return src end
  if type(src) ~= "string" or #src > QDB.ZONE_MAX_BYTES then return nil end
  if sub(src, 1, 1) == "\27" then return nil end -- precompiled bytecode is never run
  local f
  if type(setfenv) == "function" and type(loadstring) == "function" then
    f = loadstring(src, "=QuestieDB.ZoneDB")
    if f then setfenv(f, {}) end
  elseif type(setfenv) ~= "function" and type(load) == "function" then
    f = load(src, "=QuestieDB.ZoneDB", "t", {}) -- Lua 5.2+: text mode, empty environment
  end -- no way to sandbox -> nil (never run in the global environment)
  if type(f) ~= "function" then return nil end
  local ok, t = pcall(f)
  if not ok or type(t) ~= "table" then return nil end
  return t
end

-- only number -> number entries (non-negative whole numbers)
local function numMap(t)
  local out = {}
  if type(t) ~= "table" then return out end
  for k, v in pairs(t) do
    k, v = int(k), int(v)
    if k and v and k >= 0 and v >= 0 then out[k] = v end
  end
  return out
end

-- zone resolver from Support.Get("ZoneDB"): resolve(areaID) -> uiMapID or nil (instance/unknown), group(areaID) -> dungeon
-- area (quest flag g). nil, "ZONES" without a usable area -> map table. pause (optional) is called between the heavy
-- steps (one ZoneDB string each) so the caller can spread them over frames (never inside a pcall).
function QDB.zones(lib, pause)
  pause = type(pause) == "function" and pause or function() end
  local okZ, Z = pcall(lib.Support.Get, "ZoneDB")
  if not okZ or type(Z) ~= "table" or isSecret(Z) then return nil, "ZONES" end
  local P = type(Z.private) == "table" and Z.private or {}
  local okM, base = pcall(loadTable, P.areaIdToUiMapId)
  pause()
  local map = numMap(okM and base or nil)
  pause()
  if next(map) == nil then return nil, "ZONES" end
  local _, over = pcall(loadTable, P.areaIdToUiMapIdOverride)
  pause()
  over = numMap(over)
  local _, parentBase = pcall(loadTable, P.subZoneToParentZone)
  pause()
  local _, parentOver = pcall(loadTable, P.subZoneToParentZoneOverride)
  pause()
  local parent = numMap(parentBase)
  for k, v in pairs(numMap(parentOver)) do parent[k] = v end
  pause()
  -- dungeons: key = dungeon area (spawns there are dropped); alternative areas only mark group quests
  local dungeon, groupArea = {}, {}
  if type(P.dungeons) == "table" then
    for areaID, d in pairs(P.dungeons) do
      areaID = int(areaID)
      if areaID then
        dungeon[areaID] = true
        groupArea[areaID] = true
        if type(d) == "table" and type(d[2]) == "table" then
          for _, alt in ipairs(d[2]) do
            alt = int(alt)
            if alt then groupArea[alt] = true end
          end
        end
      end
    end
  end
  local cache = {}
  local function resolve(areaID)
    local c = cache[areaID]
    if c ~= nil then return c or nil end
    local result = false
    local cur = areaID
    for _ = 1, QDB.ZONE_DEPTH do
      if cur == nil or dungeon[cur] then break end
      local m = over[cur]
      if m ~= nil then
        if m > 0 then result = m end
        break
      end
      m = map[cur]
      if m and m > 0 then
        result = m
        break
      end
      cur = parent[cur]
    end
    cache[areaID] = result
    return result or nil
  end
  return { resolve = resolve, group = function(areaID) return groupArea[areaID] == true end }
end

-- spawns { [areaID] = { { x, y }, ... } } -> list of { mapID, points } (0-1, thinned), ascending by map
function QDB.spawnMaps(spawns, zones)
  local per, ids = {}, {}
  if type(spawns) ~= "table" or isSecret(spawns) then return ids end
  for areaID, pts in pairs(spawns) do
    areaID = int(areaID)
    local mapID = areaID and zones.resolve(areaID) or nil
    if mapID and type(pts) == "table" then
      for _, p in pairs(pts) do
        local x, y = type(p) == "table" and num(p[1]) or nil, type(p) == "table" and num(p[2]) or nil
        if x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
          local list = per[mapID]
          if not list then
            list = {}
            per[mapID] = list
            ids[#ids + 1] = mapID
          end
          list[#list + 1] = { x, y }
        end
      end
    end
  end
  sort(ids)
  local out = {}
  for i, mapID in ipairs(ids) do
    local points = {}
    for j, p in ipairs(QDB.thinPoints(per[mapID])) do points[j] = { p[1] / 100, p[2] / 100 } end
    out[i] = { mapID = mapID, points = points }
  end
  return out
end

-- ---------------------------------------------------------------- sharing with the data addon's records (memory)

local FLAG_ORDER = { "u", "r", "g", "s", "k" }
QDB.FLAG_ORDER = FLAG_ORDER

local function sameList(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

local function sameFlags(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for _, c in ipairs(FLAG_ORDER) do
    if (a[c] == true) ~= (b[c] == true) then return false end
  end
  return true
end

-- same quest record (all fields the open-quests logic reads)
function QDB.sameQuest(a, b)
  return type(a) == "table" and type(b) == "table" and a.id == b.id and a.name == b.name and a.minLevel == b.minLevel
    and a.level == b.level and a.races == b.races and a.classes == b.classes and (a.noDE == true) == (b.noDE == true)
    and sameList(a.preAll, b.preAll) and sameList(a.preAny, b.preAny) and sameList(a.excl, b.excl)
    and sameList(a.givers, b.givers) and sameFlags(a.flags, b.flags)
end

-- same giver record (kind, id, name, faction, noDE, maps with identical points)
function QDB.sameGiver(a, b)
  if type(a) ~= "table" or type(b) ~= "table" or a.kind ~= b.kind or a.id ~= b.id or a.name ~= b.name or a.faction ~= b.faction
    or (a.noDE == true) ~= (b.noDE == true) or type(a.maps) ~= "table" or type(b.maps) ~= "table" or #a.maps ~= #b.maps then
    return false
  end
  for i = 1, #a.maps do
    local ma, mb = a.maps[i], b.maps[i]
    if type(ma) ~= "table" or type(mb) ~= "table" or ma.mapID ~= mb.mapID or #ma.points ~= #mb.points then return false end
    for j = 1, #ma.points do
      local pa, pb = ma.points[j], mb.points[j]
      if pa[1] ~= pb[1] or pa[2] ~= pb[2] then return false end
    end
  end
  return true
end

-- ---------------------------------------------------------------- reading

-- one field (pcall per call; nil on error)
local function get(ent, id, key)
  local ok, v = pcall(ent.Get, id, key)
  if not ok then return nil end
  return v
end

-- positions in QUEST_KEYS
local K = {}
for i, k in ipairs(QUEST_KEYS) do K[k] = i end

-- all quest fields of one quest by position (K): GetAll (one call) when present, else Get per key
local function questFields(Q, id)
  if type(Q.GetAll) == "function" then
    local ok, vals = pcall(Q.GetAll, id, QUEST_KEYS)
    if ok and type(vals) == "table" and not isSecret(vals) then return vals end
  end
  local f = {}
  for i, k in ipairs(QUEST_KEYS) do f[i] = get(Q, id, k) end
  return f
end

-- does a translation supply the name (German equal to English, e.g. proper names)? l10n.GetProvenance when present
-- (read only), else no
local function translated(lib, datatype, id)
  local l10n = type(lib.l10n) == "table" and lib.l10n or nil
  local fn = l10n and l10n.GetProvenance
  if type(fn) ~= "function" then return false end
  local ok, owner = pcall(fn, datatype, id, "name")
  return ok and not isSecret(owner) and owner ~= nil and owner ~= false
end

-- name pair of an entity: shown name (German where the active QuestieDB locale is deDE and a translation exists) and
-- whether it is German. ctx.german = the client wants German names, ctx.deDE = QuestieDB's active locale is deDE,
-- ctx.enUS = it is enUS (Get is English then and cached). datatype ("Quest"/"Npc"/"Object") for the translation check.
local function names(ent, id, ctx, lib, datatype)
  local en
  if ctx.enUS then
    en = QDB.cleanName(get(ent, id, "name"))
  else
    if type(ent.GetRaw) == "function" then
      local ok, v = pcall(ent.GetRaw, id, "name")
      if ok then en = QDB.cleanName(v) end
    end
    if not en then en = QDB.cleanName(get(ent, id, "name")) end -- overlay-added entity: no raw row
  end
  if ctx.german and ctx.deDE then
    local de = QDB.cleanName(get(ent, id, "name"))
    if de and de ~= en then return de, en, true end
    -- same text: German only when a translation supplies it (as the build counts it)
    if de and lib and translated(lib, datatype, id) then return de, en, true end
    return en or de, en or de, false
  end
  return en, en, false
end

-- giver (cached per key): nil without a mapped point (like the build: such a giver gives no location)
local function giver(job, kind, id)
  local key = (kind == "npc" and "n" or "o") .. id
  local g = job.givers[key]
  if g ~= nil then return g or nil, key end
  local ent = kind == "npc" and job.lib.Npc or job.lib.Object
  local okS, spawns = pcall(ent.Get, id, "spawns")
  local maps = okS and QDB.spawnMaps(spawns, job.zones) or {}
  if #maps == 0 then
    job.givers[key] = false
    return nil, key
  end
  local name, _, de = names(ent, id, job.ctx, job.lib, kind == "npc" and "Npc" or "Object")
  name = name or ((kind == "npc" and "NPC " or "Objekt ") .. id)
  g = { kind = kind, id = id, name = name, maps = maps }
  if job.ctx.german and not de then g.noDE = true end
  local b = job.base and job.base.givers[key]
  if b and QDB.sameGiver(g, b) then
    g = b -- the data addon's table: no second copy
    job.sharedGivers = job.sharedGivers + 1
  end
  job.givers[key] = g
  job.nGivers = job.nGivers + 1
  return g, key
end

-- flag bits (u r g s k) -> flag text in FLAG_ORDER
local FLAG_BIT = { u = 1, r = 2, g = 4, s = 8, k = 16 }

-- one shared, read-only flag table per combination (job.flagSets[bits])
local function flagTable(job, bits)
  if bits == 0 then return job.EMPTY end
  local t = job.flagSets[bits]
  if not t then
    t = {}
    for _, c in ipairs(FLAG_ORDER) do
      if floor(bits / FLAG_BIT[c]) % 2 == 1 then t[c] = true end
    end
    job.flagSets[bits] = t
  end
  return t
end

local GIVER_SLOTS = { "npc", "object" } -- startedBy = { npcs, objects, items }

local function questRecord(job, id)
  local Q = job.lib.Quest
  local name, en, de = names(Q, id, job.ctx, job.lib, "Quest")
  -- the placeholder rule reads the English base name (as the build)
  if not name or QDB.placeholder(en or name) then return nil end
  local f = questFields(Q, id)
  local minL, qLevel = level(f[K.requiredLevel]), level(f[K.questLevel])
  local bits = 0
  local th = (Journal.OpenQuests and Journal.OpenQuests.UNSURE_LEVEL) or 30
  if (minL and minL > th) or (not minL and qLevel and qLevel > th) then bits = bits + 1 end
  local special = int(f[K.specialFlags])
  local r = special ~= nil and special % 2 == 1
  local g = false
  local zs = int(f[K.zoneOrSort])
  if zs and zs < 0 then
    bits = bits + 16
    g = GROUP_SORTS[zs] == true
  elseif zs and zs > 0 and job.zones.group(zs) then
    g = true
  end
  if hasId(f[K.requiredSkill]) or nonEmpty(f[K.requiredMinRep]) or nonEmpty(f[K.requiredMaxRep])
    or (int(f[K.requiredSpell]) or 0) > 0 or (int(f[K.requiredMaxLevel]) or 0) > 0 then bits = bits + 8 end
  -- r/g of the data addon (Forever database quest type) are added, as OpenQuests finishLive does
  local o = job.base and job.base.quests[id] or nil
  local of = type(o) == "table" and type(o.flags) == "table" and o.flags or nil
  if of and of.r then r = true end
  if of and of.g then g = true end
  if r then bits = bits + 2 end
  if g then bits = bits + 4 end
  -- givers: only givers with a mapped point, keys sorted and unique
  local keys
  local sb = f[K.startedBy]
  if type(sb) == "table" and not isSecret(sb) then
    for slot, kind in ipairs(GIVER_SLOTS) do
      local list = sb[slot]
      if type(list) == "number" then list = { list } end
      if type(list) == "table" and not isSecret(list) then
        for _, gid in pairs(list) do
          gid = int(gid)
          if gid and gid > 0 and gid <= QDB.MAX_ID then
            local gv, key = giver(job, kind, gid)
            if gv then
              keys = keys or {}
              keys[#keys + 1] = key
            end
          end
        end
      end
    end
  end
  if keys and #keys > 1 then
    sort(keys)
    local n = 1
    for i = 2, #keys do
      if keys[i] ~= keys[n] then
        n = n + 1
        keys[n] = keys[i]
      end
    end
    for i = #keys, n + 1, -1 do keys[i] = nil end
  end
  local minLevel, races, classes = minL or 0, mask(f[K.requiredRaces]), mask(f[K.requiredClasses])
  local preAll, preAny = idsOf(f[K.preQuestGroup]), idsOf(f[K.preQuestSingle])
  local excl = idsOf(f[K.exclusiveTo], f[K.breadcrumbForQuestId], id)
  local noDE = job.ctx.german and not de
  local fset = flagTable(job, bits)
  -- equal to the data addon's record: share it (no second copy, no new table)
  if o and o.id == id and o.name == name and o.minLevel == minLevel and o.level == qLevel and o.races == races
    and o.classes == classes and (o.noDE == true) == (noDE == true) and sameList(o.preAll, preAll) and sameList(o.preAny, preAny)
    and sameList(o.excl, excl) and sameList(o.givers, keys) and sameFlags(o.flags, fset) then
    job.sharedQuests = job.sharedQuests + 1
    return o
  end
  -- only the fields that are set (a constructor listing nil fields would reserve their slots)
  local q = { id = id, name = name, minLevel = minLevel, races = races, classes = classes, flags = fset }
  q.level = qLevel
  q.givers = keys
  q.preAll = preAll
  q.preAny = preAny
  q.excl = excl
  if noDE then q.noDE = true end
  return q
end

-- ---------------------------------------------------------------- job (coroutine with a time budget)

-- opts.german = the client wants German names; opts.empty = shared empty flag table of the caller; opts.base = the data addon's
-- parsed records { quests, givers } (optional): equal records are shared, its flags r/g are added
function QDB.newJob(lib, opts)
  opts = type(opts) == "table" and opts or {}
  local l10n = type(lib.l10n) == "table" and lib.l10n or nil
  local loc = l10n and l10n.currentLocale or nil -- read only, never SetLocale
  local base = opts.base
  if type(base) ~= "table" or type(base.quests) ~= "table" or type(base.givers) ~= "table" then base = nil end
  local job = { lib = lib, quests = {}, givers = {}, nQuests = 0, nGivers = 0, done = 0, state = "new", EMPTY = opts.empty or {},
    base = base, flagSets = {}, sharedQuests = 0, sharedGivers = 0,
    ctx = { german = opts.german == true, deDE = loc == "deDE", enUS = loc == "enUS" or loc == nil } }
  job.co = coroutine.create(function()
    local zones, why = QDB.zones(lib, coroutine.yield)
    if not zones then
      job.fail = why
      return
    end
    job.zones = zones
    coroutine.yield()
    local okI, ids = pcall(lib.Quest.GetAllIds)
    if not okI or type(ids) ~= "table" then
      job.fail = "NO_LIB"
      return
    end
    job.total = #ids
    for i = 1, #ids do
      local id = int(ids[i])
      if id and id > 0 and id <= QDB.MAX_ID and not job.quests[id] then
        local okQ, q = pcall(questRecord, job, id)
        if okQ and q then
          job.quests[id] = q
          job.nQuests = job.nQuests + 1
        elseif not okQ then
          job.errors = (job.errors or 0) + 1
        end
      end
      job.done = i
      job.tick()
    end
  end)
  return job
end

-- one frame of work: at most budgetMs (clock = ms function, e.g. debugprofilestop) and at most maxItems quests (without a
-- clock the item count is the only limit). Returns "more", "done" or "error" (job.fail = reason).
function QDB.step(job, budgetMs, clock, maxItems)
  if job.state == "done" or job.state == "error" then return job.state end
  local t0 = clock and clock() or nil
  local left = maxItems or 200
  job.tick = function()
    left = left - 1
    if left <= 0 or (t0 and clock() - t0 >= budgetMs) then coroutine.yield() end
  end
  local ok, err = coroutine.resume(job.co)
  if t0 then
    local used = clock() - t0
    job.steps = (job.steps or 0) + 1
    job.ms = (job.ms or 0) + used
    if not job.maxStep or used > job.maxStep then job.maxStep = used end
  end
  if not ok then
    job.state, job.fail = "error", "FAILED"
    job.base = nil
    job.err = type(err) == "string" and sub(gsub(err, "[%c|]", " "), 1, 200) or nil
    return "error"
  end
  if coroutine.status(job.co) == "dead" then
    if job.fail then
      job.state, job.base = "error", nil
      return "error"
    end
    job.state = "done"
    job.base, job.flagSets = nil, nil -- no reference to the data addon's records beyond the shared ones
    job.givers = (function()
      local out = {}
      for k, g in pairs(job.givers) do if g then out[k] = g end end
      return out
    end)()
    return "done"
  end
  return "more"
end
