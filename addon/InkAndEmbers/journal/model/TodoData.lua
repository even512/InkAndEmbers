-- To-do targets: enemy and item lists to search. Source 1: addon InkAndEmbers_Data (LoadOnDemand, built by
-- scripts/build-todo-data.mjs), loaded on the first available/search call, never in combat or before login, in pcall; a
-- failure keeps its reason and is retried after TodoData.RETRY s.
-- npc = string, per enemy "\n<id>\t<name>\t<min>\t<max>\t<rank>\t<zone>" (rank "" normal, e elite, r rare, R rare
-- elite, b boss); item = per item "\n<id>\t<name>\t<quality>"; zones = { [zoneID] = name }. These names are German
-- (English where German is missing). For non-German add-on languages the data add-on also runs its English
-- files (guard: the global EveNChronicleTodoLang = "enUS", set here just before LoadAddOn): npcEn / itemEn = per entry
-- "\n<id>\t<English name>" sorted by that name, zonesEn = { [zoneID] = name } (only where it differs from German).
-- Names and search then use the English list; level, rank and zone come from the German list by id. Without an English
-- name for an id the German one is used. Entries are linked by id, never by name.
-- Source 2 (fallback and supplement): the character SV, npcs[npcID] = name and snapshots.items[itemID] = { name,
-- quality }. Search keys: lowercase, umlauts as ae/oe/ue/ss, no accents.
-- Retail client (TodoData.retailClient, Journal.MapSpace.retailClient): the lists come from QuestieDB
-- (Classic/Forever), so in Retail only the names are used for the search; level and zone of an enemy are left out (they
-- are often wrong there: scaling, Cataclysm zones). Counting a goal never depends on these lists (collectors/Plans.lua
-- matches FC_KILL npcID from the GUID / FC_LOOT itemID from the loot link, or the name). TodoData.ALLOW_RETAIL (tests)
-- keeps level and zone in Retail.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local TodoData = {}
Journal.TodoData = TodoData

local find, sub, gsub, gmatch, match, lower, char = string.find, string.sub, string.gsub, string.gmatch, string.match, string.lower, string.char
local floor, tonumber, tostring, sort = math.floor, tonumber, tostring, table.sort

TodoData.ADDON = "InkAndEmbers_Data"
TodoData.GLOBAL = "EveNChronicleTodoData"
TodoData.LANG_GLOBAL = "EveNChronicleTodoLang" -- read by the English files of the data add-on
TodoData.LIMIT = 30
TodoData.LIMIT_MAX = 200
TodoData.QUERY_MAX = 60 -- bytes of search text
TodoData.NAME_MAX = 80
-- locale scope "m.TodoData" (English in locales/enUS_model.lua); ranks and reasons are read on access
local TX = ns.Locale.ns("m.TodoData", {
  rank_e = "Elite", rank_r = "Selten", rank_R = "Selten-Elite", rank_b = "Boss",
  DISABLED = "im Addon-Menü deaktiviert",
  DEP_DISABLED = "Ink & Embers ist im Addon-Menü deaktiviert",
  MISSING = "Zusatzaddon InkAndEmbers_Data nicht installiert",
  DEP_MISSING = "Ink & Embers fehlt",
  INTERFACE_VERSION = "Zusatzaddon veraltet (Spielversion)",
  INCOMPATIBLE = "Zusatzaddon passt nicht zu dieser Spielversion",
  CORRUPT = "Zusatzaddon beschädigt",
  BANNED = "vom Spiel gesperrt",
  INSECURE = "vom Spiel gesperrt",
  NOT_DEMAND_LOADED = "nicht auf Abruf ladbar (LoadOnDemand fehlt)",
  COMBAT = "im Kampf (wird danach geladen)",
  NOT_LOGGED_IN = "noch nicht angemeldet",
  NO_API = "Ladefunktion fehlt",
  NO_DATA = "Zusatzaddon geladen, aber ohne Liste (neu installieren)",
  ERROR = "Fehler beim Laden",
  UNKNOWN = "unbekannter Grund",
  notTried = "noch nicht versucht",
  depMissing = "abhängiges Addon fehlt (%s)",
  listItem = "Gegenstandsliste",
  listNpc = "Gegnerliste",
  loaded = "%s: geladen (%s)",
  notInData = "%s: nicht geladen: fehlt im Zusatzaddon",
  notLoaded = "%s: nicht geladen: %s",
  retailNote = " (Retail: nur Namen, ohne Stufe und Gebiet)",
})
TodoData.T = TX
local RANK_KEYS = { e = true, r = true, R = true, b = true }
TodoData.RANKS = setmetatable({}, { __index = function(_, k)
  if type(k) == "string" and RANK_KEYS[k] then return TX["rank_" .. k] end
end })
local DASH = "\226\128\147" -- en dash (level range "12–14")
TodoData.RETRY = 10 -- seconds until the next load attempt after a failure
-- kind -> list in the data addon ("kill" = the to-do target kind, same list as "npc")
local KINDS = { npc = "npc", kill = "npc", item = "item" }

-- session state (tests: TodoData._state). tried = at least one real load attempt; nextTry = GetTime() after which to retry;
-- reason = last failure (nil = loaded or not tried yet)
local S = { tried = false, loadCalls = 0, data = nil, keys = {}, reason = nil, nextTry = nil, counts = {} }
TodoData._state = S

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

-- Retail client? (Journal.MapSpace.retailClient: project id AND interface version >= 100000; Forever is never Retail)
function TodoData.retailClient()
  local ms = Journal.MapSpace
  return ms ~= nil and ms.retailClient() == true
end

-- names only (no Forever level/zone)?
local function namesOnly()
  return not TodoData.ALLOW_RETAIL and TodoData.retailClient()
end
TodoData.namesOnly = namesOnly

local function inCombat()
  if type(InCombatLockdown) ~= "function" then return false end
  local ok, v = pcall(InCombatLockdown)
  return ok and not isSecret(v) and v == true
end

-- search key: lowercase, umlauts -> ae/oe/ue/ss, other Latin-1 letters without accent, ' and " removed
local FOLD = {}
do
  local function set(from, to, s) for b = from, to do FOLD["\195" .. char(b)] = s end end
  set(0x80, 0x85, "a"); set(0xA0, 0xA5, "a"); set(0x86, 0x86, "ae"); set(0xA6, 0xA6, "ae")
  set(0x87, 0x87, "c"); set(0xA7, 0xA7, "c"); set(0x88, 0x8B, "e"); set(0xA8, 0xAB, "e")
  set(0x8C, 0x8F, "i"); set(0xAC, 0xAF, "i"); set(0x90, 0x90, "d"); set(0xB0, 0xB0, "d")
  set(0x91, 0x91, "n"); set(0xB1, 0xB1, "n"); set(0x92, 0x96, "o"); set(0xB2, 0xB6, "o")
  set(0x98, 0x98, "o"); set(0xB8, 0xB8, "o"); set(0x99, 0x9C, "u"); set(0xB9, 0xBC, "u")
  set(0x9D, 0x9D, "y"); set(0xBD, 0xBD, "y"); set(0xBF, 0xBF, "y"); set(0x9E, 0x9E, "th"); set(0xBE, 0xBE, "th")
  set(0x84, 0x84, "ae"); set(0xA4, 0xA4, "ae"); set(0x96, 0x96, "oe"); set(0xB6, 0xB6, "oe")
  set(0x9C, 0x9C, "ue"); set(0xBC, 0xBC, "ue"); set(0x9F, 0x9F, "ss")
end

local function fold(s)
  s = lower(s)
  s = gsub(s, "\195[\128-\191]", FOLD)
  s = gsub(s, "[\"']", "")
  return s
end
TodoData.fold = fold

-- Bundled names are only available in German and English; use English for other languages.
local function english()
  local L = ns.Locale
  return type(L) == "table" and L.active ~= "deDE"
end

local function display(s)
  local S_ = ns.Sanitize
  return S_ and S_.display(s, TodoData.NAME_MAX) or nil
end

-- adopt the data addon's global table (valid parts only) and delete the global
local function adopt()
  local g = _G[TodoData.GLOBAL]
  if type(g) ~= "table" then return false end
  _G[TodoData.GLOBAL] = nil
  local d = { zones = type(g.zones) == "table" and g.zones or {} }
  if type(g.npc) == "string" and sub(g.npc, 1, 1) == "\n" then d.npc = g.npc end
  if type(g.item) == "string" and sub(g.item, 1, 1) == "\n" then d.item = g.item end
  if not d.npc and not d.item then return false end
  if type(g.zonesEn) == "table" then d.zonesEn = g.zonesEn end
  if type(g.npcEn) == "string" and sub(g.npcEn, 1, 1) == "\n" then d.npcEn = g.npcEn end
  if type(g.itemEn) == "string" and sub(g.itemEn, 1, 1) == "\n" then d.itemEn = g.itemEn end
  S.data = d
  return true
end

local function now()
  if type(GetTime) ~= "function" then return 0 end
  local ok, t = pcall(GetTime)
  return (ok and not isSecret(t) and type(t) == "number") and t or 0
end

local function loggedIn()
  if type(IsLoggedIn) ~= "function" then return true end
  local ok, v = pcall(IsLoggedIn)
  if not ok or isSecret(v) then return true end
  return v ~= false and v ~= nil
end

-- failure reason (client code such as "DISABLED", "DEP_DISABLED"); only short uppercase codes
local function cleanReason(r)
  if isSecret(r) or type(r) ~= "string" then return nil end
  r = match(r, "^[%u%d_]+$")
  return r and sub(r, 1, 40) or nil
end

local function fail(reason, wait)
  S.reason = reason
  S.nextTry = wait and (now() + TodoData.RETRY) or nil
  return false
end

local function loaded()
  S.reason, S.nextTry = nil, nil
  return true
end

local function loadData()
  if S.data then return true end
  if adopt() then return loaded() end -- already loaded elsewhere
  -- transient blocks: no attempt, no waiting (asked again next time)
  if inCombat() then return fail("COMBAT") end
  if not loggedIn() then return fail("NOT_LOGGED_IN") end
  if S.nextTry and now() < S.nextTry then return false end -- wait briefly after a failure, the reason stays
  local api = type(C_AddOns) == "table" and C_AddOns.LoadAddOn or nil
  if type(api) ~= "function" then api = type(LoadAddOn) == "function" and LoadAddOn or nil end
  if not api then return fail("NO_API", true) end
  S.tried = true
  S.loadCalls = S.loadCalls + 1
  if english() then _G[TodoData.LANG_GLOBAL] = "enUS" end
  local ok, isLoaded, reason = pcall(api, TodoData.ADDON)
  _G[TodoData.LANG_GLOBAL] = nil
  if not ok then return fail("ERROR", true) end
  if adopt() then return loaded() end
  -- LoadAddOn returns (loaded, reason): nil/false = not loaded, reason says why ("DISABLED", "MISSING", "DEP_...");
  -- loaded but without a valid table = old or broken file
  if isSecret(isLoaded) or not isLoaded then return fail(cleanReason(reason) or "UNKNOWN", true) end
  return fail("NO_DATA", true)
end

function TodoData.available(kind)
  local k = KINDS[kind]
  if not k then return false end
  if not S.data then loadData() end
  return S.data ~= nil and S.data[k] ~= nil
end

-- retry now (skips the wait after a failure; /chronik diag) -> loaded?
function TodoData.retry()
  if not S.data then
    S.nextTry = nil
    loadData()
  end
  return S.data ~= nil
end

-- entry count of a list (counted once)
local function countOf(k)
  if S.counts[k] then return S.counts[k] end
  local blob = S.data and S.data[k]
  if not blob then return 0 end
  local _, n = gsub(blob, "\n%d+\t", "")
  S.counts[k] = n
  return n
end

function TodoData.status()
  return { loaded = S.data ~= nil, reason = S.reason, tried = S.tried, npc = countOf("npc"), item = countOf("item"),
    namesOnly = namesOnly() }
end

local REASON_KEYS = { DISABLED = true, DEP_DISABLED = true, MISSING = true, DEP_MISSING = true, INTERFACE_VERSION = true,
  INCOMPATIBLE = true, CORRUPT = true, BANNED = true, INSECURE = true, NOT_DEMAND_LOADED = true, COMBAT = true,
  NOT_LOGGED_IN = true, NO_API = true, NO_DATA = true, ERROR = true, UNKNOWN = true }
TodoData.REASONS = setmetatable({}, { __index = function(_, k)
  if type(k) == "string" and REASON_KEYS[k] then return TX[k] end
end })

function TodoData.reasonText(reason)
  if type(reason) ~= "string" then return TX.notTried end
  local t = TodoData.REASONS[reason]
  if t then return t end
  if find(reason, "^DEP_") then return TX("depMissing", reason) end
  return reason
end

-- data addon disabled in the addon menu (reason of the last load attempt)
function TodoData.disabled()
  return S.reason == "DISABLED" or S.reason == "DEP_DISABLED"
end

function TodoData.diagLine(kind)
  local k = KINDS[kind] or "npc"
  local label = k == "item" and TX.listItem or TX.listNpc
  if S.data and S.data[k] then return TX("loaded", label, countOf(k)) .. (namesOnly() and TX.retailNote or "") end
  if S.data then return TX("notInData", label) end
  return TX("notLoaded", label, TodoData.reasonText(S.reason))
end

-- raw line (without the leading "\n") of an entry; nil if the id is missing
local function rawLine(blob, id)
  local s = find(blob, "\n" .. id .. "\t", 1, true)
  if not s then return nil end
  local e = find(blob, "\n", s + 1, true)
  return sub(blob, s + 1, (e or #blob + 1) - 1)
end

local function levelText(min, max)
  min, max = tonumber(min), tonumber(max)
  if not min then return nil end
  if not max or max == min then return tostring(min) end
  return min .. DASH .. max
end

-- English name of an id (nil: English not wanted or not known -> the caller keeps the German one)
local function nameEn(kind, id)
  if not english() then return nil end
  local blob = S.data and S.data[kind .. "En"]
  if not blob then return nil end
  local line = rawLine(blob, id)
  return line and match(line, "^%d+\t([^\t]+)$") or nil
end

local function zoneName(d, zid)
  local en = english() and type(d.zonesEn) == "table" and d.zonesEn[zid] or nil
  if type(en) == "string" and en ~= "" then return display(en) end
  local z = d.zones[zid]
  return type(z) == "string" and display(z) or nil
end

local function npcRecord(line, d)
  local id, name, min, max, rank, zone = match(line, "^(%d+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
  if not id then return nil end
  local zid = tonumber(zone)
  local rec = { id = tonumber(id), name = display(nameEn("npc", id) or name), rank = TodoData.RANKS[rank] }
  if not namesOnly() then
    rec.level = levelText(min, max)
    rec.zone = zid and zoneName(d, zid) or nil
  end
  return rec
end

local function itemRecord(line)
  local id, name, q = match(line, "^(%d+)\t([^\t]*)\t([^\t]*)$")
  if not id then return nil end
  return { id = tonumber(id), name = display(nameEn("item", id) or name), quality = tonumber(q) }
end

local function record(kind, id)
  local d = S.data
  local blob = d and d[kind]
  if not blob then return nil end
  local line = rawLine(blob, id)
  if not line then return nil end
  if kind == "npc" then return npcRecord(line, d) end
  return itemRecord(line)
end

-- search key string of a kind (once per session)
local KEY_PATTERN = "\n(%d+)\t([^\t\n]*)[^\n]*"

-- English: the English list (sorted by English name), then the German names of ids it lacks; else the German list
local function keyBlob(kind)
  local blob = S.data and S.data[kind]
  if not blob then return nil end
  local en = english() and S.data[kind .. "En"] or nil
  local ck = en and (kind .. "En") or kind
  local k = S.keys[ck]
  if k then return k end
  if not en then
    k = fold((gsub(blob, KEY_PATTERN, "\n%1\t%2")))
  else
    local have = {}
    for id in gmatch(en, "\n(%d+)\t") do have[id] = true end
    local rest = {}
    for id, name in gmatch(blob, KEY_PATTERN) do
      if not have[id] then rest[#rest + 1] = "\n" .. id .. "\t" .. name end
    end
    k = fold((gsub(en, KEY_PATTERN, "\n%1\t%2")) .. table.concat(rest))
  end
  S.keys[ck] = k
  return k
end

-- { [id] = { name, quality } } from the character SV (nil without SV)
local function fallbackSource(kind)
  local Store = ns.Store
  local c = Store and type(Store.char) == "function" and Store.char() or nil
  if type(c) ~= "table" then return nil end
  local out = {}
  if kind == "npc" then
    local t = c.npcs
    if type(t) ~= "table" then return out end
    for id, v in pairs(t) do
      local n = type(v) == "string" and v or (type(v) == "table" and type(v.name) == "string" and v.name) or nil
      if type(id) == "number" and n and not isSecret(n) then out[id] = { n } end
    end
  else
    local t = type(c.snapshots) == "table" and c.snapshots.items or nil
    if type(t) ~= "table" then return out end
    for id, v in pairs(t) do
      if type(id) == "number" and type(v) == "table" and type(v.name) == "string" then
        out[id] = { v.name, type(v.quality) == "number" and v.quality or nil }
      end
    end
  end
  return out
end

-- match group: 1 name start, 2 word start, 3 substring, nil = no match
local function rankOf(key, q)
  local p = find(key, q, 1, true)
  if not p then return nil end
  if p == 1 then return 1 end
  if find(key, " " .. q, 1, true) or find(key, "-" .. q, 1, true) then return 2 end
  return 3
end

local function fallbackSearch(kind, q, limit, have)
  local src = fallbackSource(kind)
  if not src then return {} end
  local hits = {}
  for id, v in pairs(src) do
    if not have[id] then
      local key = fold(v[1])
      local r = rankOf(key, q)
      if r then hits[#hits + 1] = { r = r, key = key, id = id, v = v } end
    end
  end
  sort(hits, function(a, b)
    if a.r ~= b.r then return a.r < b.r end
    if a.key ~= b.key then return a.key < b.key end
    return a.id < b.id
  end)
  local out = {}
  for i = 1, math.min(#hits, limit) do
    local h = hits[i]
    local name = display(h.v[1])
    if name then out[#out + 1] = { id = h.id, name = name, quality = kind == "item" and h.v[2] or nil } end
  end
  return out
end

local function cleanQuery(query)
  if isSecret(query) or type(query) ~= "string" then return nil end
  local plain = ns.Sanitize and ns.Sanitize.plain(query, TodoData.QUERY_MAX) or nil
  if not plain then return nil end
  local q = fold(plain)
  q = gsub(q, "^%s+", "")
  q = gsub(q, "%s+$", "")
  if q == "" then return nil end
  return q
end

local function cleanLimit(limit)
  if isSecret(limit) or type(limit) ~= "number" or limit ~= limit then return TodoData.LIMIT end
  limit = floor(limit)
  if limit < 1 then return TodoData.LIMIT end
  if limit > TodoData.LIMIT_MAX then return TodoData.LIMIT_MAX end
  return limit
end

function TodoData.search(kind, query, limit)
  local k = KINDS[kind]
  if not k then return {} end
  kind = k
  local q = cleanQuery(query)
  if not q then return {} end
  limit = cleanLimit(limit)
  local out, have = {}, {}
  if TodoData.available(kind) then
    local keys = keyBlob(kind)
    local groups = { {}, {}, {} }
    for id, key in gmatch(keys, "\n(%d+)\t([^\n]*)") do
      local r = rankOf(key, q)
      if r and #groups[r] < limit then
        local g = groups[r]
        g[#g + 1] = id
        if r == 1 and #g >= limit then break end -- list is sorted by name: enough name starts
      end
    end
    for r = 1, 3 do
      for _, id in ipairs(groups[r]) do
        if #out >= limit then break end
        local rec = record(kind, id)
        if rec and rec.name then
          out[#out + 1] = rec
          have[rec.id] = true
        end
      end
    end
  end
  if #out < limit then
    for _, rec in ipairs(fallbackSearch(kind, q, limit - #out, have)) do out[#out + 1] = rec end
  end
  return out
end

function TodoData.name(kind, id)
  local k = KINDS[kind]
  if not k or isSecret(id) or type(id) ~= "number" or id ~= id then return nil end
  kind = k
  id = floor(id)
  if S.data and S.data[kind] then
    local rec = record(kind, id)
    if rec and rec.name then return rec.name end
  end
  local Store = ns.Store
  local c = Store and type(Store.char) == "function" and Store.char() or nil
  if type(c) ~= "table" then return nil end
  local v
  if kind == "npc" then
    v = type(c.npcs) == "table" and c.npcs[id] or nil
    if type(v) == "table" then v = v.name end
  else
    v = type(c.snapshots) == "table" and type(c.snapshots.items) == "table" and c.snapshots.items[id] or nil
    v = type(v) == "table" and v.name or nil
  end
  if type(v) ~= "string" or isSecret(v) then return nil end
  return display(v)
end
