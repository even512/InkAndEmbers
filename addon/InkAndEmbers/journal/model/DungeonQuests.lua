-- Dungeon quests ("Dungeons" under Quests, Forever only): pure logic, no frames. Data: EveNChronicleQuestData.dungeon of the data
-- addon InkAndEmbers_QuestData (Dungeons.lua, built by scripts/build-quest-data.mjs from QuestieDB zones/quest types), kept raw by
-- journal/model/OpenQuests.lua and parsed here on the first call. Quests, givers, names and the availability rules are
-- OpenQuests' (record/stateOf/statesOf/giversOf), so a quest means the same here as in "Offen". No rewards, no bosses, no loot.
--
-- Data format (E1, tab separated, one dungeon per line):
--   "\n<key>\t<name de>\t<name en>\t<levelMin>\t<levelMax>\t<mapID>:<x>,<y>;<mapID>:<x>,<y>\t<questId>[<grade>],..."
--   x/y are 0-100 percent of the map (like the givers); grade = one letter z (zone), t (Forever database quest type), a (derived,
--   strict), k (only through the chain), m (hand table), plus "*" when the quest is ambiguous (listed under every fitting dungeon).
--   Chains are NOT stored: they are derived at run time from preAll/preAny of the quest data (backward: prerequisites in the open
--   world, forward: follow-up quests).
--
-- PUBLIC API (all read-only results, do not modify; nothing loads or computes before the first call):
--   DungeonQuests.available()          -> true | false, reason            first call loads the data addon (OpenQuests.available,
--                                                                        never in combat / before login) and parses the table
--   DungeonQuests.status()             -> { available, reason, reasonText }   reasons: RETAIL, COMBAT, NO_DUNGEON_DATA, OpenQuests'
--   DungeonQuests.list(opts)           -> { dungeons = { {...} }, hiddenEmpty, partial, level, unavailable, reason }
--        opts.all = true  "Alle" (default "Für mich": dungeons without a quest for this character are left out, counted in
--        hiddenEmpty); opts.search = text (dungeon name or quest name, plain find, never a pattern/format argument; hits = matching
--        quests). Dungeon: key, name, nameDE, nameEN, minLevel, maxLevel, levelRel ("fit"|"coming"|"below", own level against the
--        span), entrances { {mapID, x, y (0-1, client map space), name} }, counts: total (quests for this character: other
--        faction/race/class out, alternatives that exclude each other count once, quests voided by a done alternative out),
--        done, log, open, locked, foreign, voided, all, estimated (assignment guessed), complete (total > 0 and done == total),
--        empty (total == 0), hits. Sorted by level span, empty ones last.
--   DungeonQuests.quests(key, opts)    -> { key, name, ..., counts, chains = { chain }, singles = { row }, continues (follow-up quests left
--                                           out at the end: raids and group quests without a dungeon, number only), byId, hiddenForeign,
--                                           hiddenLocked, unavailable, unknown }
--        opts.foreign = true shows quests of the other faction/race/class (state "foreign"), opts.locked = true shows locked rows
--        (hidden by default; the structure and the counts do not change). Chain: id (first quest), name, total (quests), counts (as
--        above, over the chain), steps (longest path), collapsed (everything done: closed by default), rows (at most CHAIN_MAX
--        quests, then ends), all (every row), more (quests beyond rows). Row: id, name, level, minLevel, state (done|log|open|locked|
--        foreign), reasons, notes (hints, see below), unsure, partial, seed (quest of this dungeon) / outside (chain quest outside
--        it; zone, zoneMap = giver zone; elsewhere = it belongs to another dungeon, see dungeons), assign (grade letter), estimated, ambiguous, dungeons (all keys), giverKind
--        (outside|inside|none), todo ("giver"|"entrance"|nil), excl (own exclusions), alt (quests in this list that exclude it or
--        are excluded by it: mark "oder"), depth, indent (depth, at most INDENT_MAX), deep (deeper than INDENT_MAX: flat with a
--        mark), step (longest path from a root, 1 = start), parent (placing quest), after (prerequisites in the list, only
--        when 2 or more: merge) with afterMode "all"|"any" and afterAny (mixed), fork = { n, kind = "then"|"either" } when 2 or
--        more follow-ups, ref = true (reference row "see ..." under the other prerequisites of a merge; only id, of, depth).
--   DungeonQuests.stateOf(id, key)     -> row-like record of a quest (state, reasons, notes, unsure, assign, giverKind ...) or nil
--   DungeonQuests.detail(id, key, opts)-> stateOf + prereqAll, prereqAny, excl ({id, name, state}), givers (OpenQuests.giversOf),
--                                         chips { faction, classes, races }, stations, step/steps, todo = { via, reason }
--   DungeonQuests.stations(res, id)    -> { {id, state, current} } the path through a quest (marks: done / current / open)
--   DungeonQuests.hints(id, key)       -> notes list { kind, text, tip }: unsure ("Beta-Daten unsicher", dezent: small mark + tip),
--                                         estimated ("Zuordnung geschätzt"), giverInside, giverNone, notChecked, raceUnsure, foreverNew
--   DungeonQuests.addTodo(key, id, opts) -> goalId | nil, reason, via     "Als To Do": at the giver (outside; opts.giver = giver of
--        giversOf or opts.pin = {mapID, x, y} = the point nearest to the chosen pin), at the dungeon entrance when the giver is inside
--        ("Dungeon betreten: <Dungeon> (Quest: <Quest>)"), nothing for an item start. reasons: kein-ort, kein-plan, voll,
--        nicht-bereit, doppelt (open goal with the same text exists), item-start, unbekannt.
--   DungeonQuests.entrancePins(dungeons, mapID) -> { {mapID, x, y, key, name, open, total} } entrances of list() dungeons on a map
--   DungeonQuests.onChange(fn)         -> true     fn() after events/names/source changed (QUEST_TURNED_IN, QUEST_ACCEPTED/REMOVED,
--                                                  PLAYER_LEVEL_UP, names arrived, live source): bundled to one call per 0.5 s
--   DungeonQuests.footer()             -> "Daten: QuestieDB x.y.z (...) · Dungeon-Zuordnung: Zone, Quest-Typ, abgeleitet"
--   DungeonQuests.diagInfo() / diagLine()  data counts, missing quest IDs, build times (ms)
-- LEARNED QUESTS: a quest the character accepted (QA) or turned in without a map (QT, instances give none) during a visit to
--   an instance (IE ... IL of the same visit, from the log via Journal.Index, nothing is stored) belongs to that dungeon on screen,
--   even when the data has no assignment (grade "l", note "learned"). instanceID -> dungeon key via DQ.INSTANCE_KEY, else the
--   snapshot name (German/English) of the instance. Never twice: quests the dungeon already lists stay as they are.
-- Texts of the page (labels of the states, "Beta-Daten unsicher") come from the UI / OpenQuests.TEXT; this file only carries the
-- texts of its own notes. Retail client: everything answers empty (unavailable, reason RETAIL), nothing is loaded.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local DQ = {}
Journal.DungeonQuests = DQ

local find, sub, gmatch, match, lower = string.find, string.sub, string.gmatch, string.match, string.lower
local floor, tonumber, sort, max, min = math.floor, tonumber, table.sort, math.max, math.min

DQ.CHAIN_MAX = 40 -- quests per chain in the sheet; the rest is "... and n more"
DQ.INDENT_MAX = 4 -- indentation levels; deeper rows are flat
DQ.NAME_MAX = 80
DQ.SEARCH_MAX = 60
DQ.FOREVER_NEW_ID = 90000 -- quest IDs from here are Forever's own (data incomplete)
DQ.DUNGEONS_MAX = 200
DQ.QUESTS_MAX = 3000 -- per dungeon line
DQ.DEPTH_MAX = 200 -- guard of the tree walk

-- texts (German here, English in locales/enUS_model.lua, scope "m.DungeonQuests")
local T = ns.Locale.ns("m.DungeonQuests", {
  hintEstimated = "Zuordnung geschätzt",
  tipEstimated = "Die Zuordnung zu diesem Dungeon ist abgeleitet, nicht belegt",
  tipAmbiguous = "Gehört vermutlich zu: %s",
  hintGiverInside = "Geber im Dungeon",
  tipGiverInside = "Der Geber steht im Dungeon, die Karte zeigt den Eingang",
  hintGiverNone = "Start per Gegenstand",
  tipGiverNone = "Kein Geber auf der Karte: die Quest beginnt mit einem Gegenstand (kein To Do möglich)",
  hintForeverNew = "Neue Forever-Quest",
  tipForeverNew = "Forever-neue Quest: Daten lückenhaft",
  hintLearned = "In der Instanz angenommen",
  tipLearned = "Von Euch in der Instanz angenommen: die Zuordnung zu diesem Dungeon stammt aus Eurem Tagebuch",
  todoEntrance = "Dungeon betreten: %s (Quest: %s)",
  footerAssign = "Dungeon-Zuordnung: Zone, Quest-Typ, abgeleitet",
  reasonRetail = "In Retail gibt es die Dungeon-Quests nicht",
  reasonNoData = "Dungeon-Daten fehlen (Zusatzaddon neu installieren)",
  reasonCombat = "im Kampf (wird danach geladen)",
  diagLoaded = "Dungeon-Quests: %d Dungeons, %d Quests (%d fehlen in den Questdaten)",
  diagNotLoaded = "Dungeon-Quests: nicht geladen: %s",
})
DQ.TEXT = T

local EMPTY = {}

-- instanceID (GetInstanceInfo, 8th value) -> dungeon key (area ID of the data, see Dungeons.lua). Classic instance IDs plus
-- 3065 (The Hall of Thanes, seen in the log of a real visit). Without an entry the instance name is compared (see keyOfInstance).
DQ.INSTANCE_KEY = {
  [33] = "209", [47] = "491", [34] = "717", [43] = "718", [48] = "719", [90] = "721", [129] = "722", [189] = "796",
  [209] = "1176", [70] = "1337", [109] = "1477", [36] = "1581", [229] = "1583", [230] = "1584", [329] = "2017",
  [289] = "2057", [349] = "2100", [389] = "2437", [429] = "2557", [3065] = "16919",
}

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function display(s, max_)
  local S_ = ns.Sanitize
  return S_ and S_.display(s, max_ or DQ.NAME_MAX) or nil
end

local function inCombat()
  if type(InCombatLockdown) ~= "function" then return false end
  local ok, v = pcall(InCombatLockdown)
  return ok and not isSecret(v) and v == true
end

local function clock()
  local f = rawget(_G, "debugprofilestop")
  if type(f) ~= "function" then return 0 end
  local ok, v = pcall(f)
  return (ok and num(v)) or 0
end

local OQ = Journal.OpenQuests

-- module state: parsed table per data table, static chain expansion per dungeon, caches per generation of OpenQuests
local M = { blob = nil, data = nil, D = nil, exp = {}, c = nil, cg = nil, cn = nil, listeners = {}, hooked = false, diag = {} }

-- ---------------------------------------------------------------- parsing

local function parseEntrances(s)
  local out = {}
  for part in gmatch(s or "", "[^;]+") do
    local mid, x, y = match(part, "^%s*(%d+):([%d%.]+),([%d%.]+)%s*$")
    mid, x, y = tonumber(mid), tonumber(x), tonumber(y)
    if mid and mid > 0 and x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
      out[#out + 1] = { mapID = floor(mid), x = x / 100, y = y / 100 }
    end
  end
  return out
end

-- dungeon table -> { list = { dungeon }, byKey, byQuest = id -> { keys }, bad }
local function parse(blob)
  local D = { list = {}, byKey = {}, byQuest = {}, bad = 0, quests = 0 }
  for line in gmatch(blob, "\n([^\n]*)") do
    if line ~= "" and #D.list < DQ.DUNGEONS_MAX then
      local key, de, en, lo, hi, ent, qs = match(line, "^([%w_%-]+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t?([^\t]*)$")
      if key and not D.byKey[key] then
        local dg = { key = key, nameDE = display(de) or "", nameEN = display(en) or "", entrances = parseEntrances(ent), quests = {},
          grade = {}, star = {}, set = {} }
        local lv1, lv2 = tonumber(lo) or 0, tonumber(hi) or 0
        lv1, lv2 = max(0, min(floor(lv1), 99)), max(0, min(floor(lv2), 99))
        if lv2 < lv1 then lv1, lv2 = lv2, lv1 end
        dg.minLevel, dg.maxLevel = lv1, lv2
        for tok in gmatch(qs or "", "[^,]+") do
          local id, flags = match(tok, "^%s*(%d+)([%a%*]*)%s*$")
          id = tonumber(id)
          if id and id > 0 and id <= 2147483647 and not dg.set[id] and #dg.quests < DQ.QUESTS_MAX then
            dg.set[id] = true
            dg.quests[#dg.quests + 1] = id
            local g = match(flags, "[ztakm]")
            if g then dg.grade[id] = g end
            if find(flags, "*", 1, true) then dg.star[id] = true end
            local keys = D.byQuest[id]
            if not keys then
              keys = {}
              D.byQuest[id] = keys
            end
            keys[#keys + 1] = key
            D.quests = D.quests + 1
          end
        end
        sort(dg.quests)
        if #dg.quests > 0 then
          D.list[#D.list + 1] = dg
          D.byKey[key] = dg
        else
          D.bad = D.bad + 1
        end
      else
        D.bad = D.bad + 1
      end
    end
  end
  return D
end

-- ---------------------------------------------------------------- learned quests (from the log, nothing stored)

-- accepted quests (QA) and unmapped turned-in quests (QT) inside an instance visit -> list { id, inst, name }, plus a
-- signature that changes with the list. Recomputed only when the index is a new one; without an index (still building,
-- no data) the last known list stays.
local function scanLearned()
  local Idx = Journal.Index
  if type(Idx) ~= "table" or type(Idx.get) ~= "function" or type(Idx.instanceAt) ~= "function" then return M.lraw or EMPTY, M.lsigRaw or "" end
  local ok, index = pcall(Idx.get, { noRebuild = inCombat() })
  if not ok or type(index) ~= "table" or isSecret(index) then return M.lraw or EMPTY, M.lsigRaw or "" end
  if M.lidx == index then return M.lraw or EMPTY, M.lsigRaw or "" end
  local out, seen, parts = {}, {}, {}
  local function take(code, unmappedOnly)
    for _, r in ipairs(Idx.list(index, code)) do
      local id = Idx.num(r, code, "questID")
      if id and id > 0 and id <= 2147483647 and not (unmappedOnly and Idx.num(r, code, "mapID")) then
        id = floor(id)
        local inst = Idx.instanceAt(index, r.t)
        local k = inst and (floor(inst) .. ":" .. id)
        if k and not seen[k] and #out < DQ.QUESTS_MAX then
          seen[k] = true
          out[#out + 1] = { id = id, inst = floor(inst), name = Idx.instanceName(index, inst) }
          parts[#parts + 1] = k
        end
      end
    end
  end
  take("QA", false)
  take("QT", true)
  sort(parts)
  M.lidx, M.lraw, M.lsigRaw = index, out, table.concat(parts, ",")
  return out, M.lsigRaw
end

-- dungeon key of an instance: the (client language) name against the German/English dungeon names first, so a wrong table
-- entry cannot override a name hit; DQ.INSTANCE_KEY only as fallback
local function keyOfInstance(D, inst, name)
  local n = name and display(name)
  if n then
    n = lower(n)
    for _, dg in ipairs(D.list) do
      if lower(dg.nameDE) == n or lower(dg.nameEN) == n then return dg.key end
    end
  end
  local k = DQ.INSTANCE_KEY[inst]
  if k and D.byKey[k] then return k end
  return nil
end

-- adds the learned quests to their dungeons (grade "l"); quests a dungeon already lists stay untouched (no duplicates)
local function applyLearned(D, learned)
  local touched = {}
  for _, e in ipairs(learned) do
    local key = keyOfInstance(D, e.inst, e.name)
    local dg = key and D.byKey[key]
    if dg and not dg.set[e.id] then
      dg.set[e.id] = true
      dg.quests[#dg.quests + 1] = e.id
      dg.grade[e.id] = "l"
      dg.learned = dg.learned or {}
      dg.learned[e.id] = true
      local keys = D.byQuest[e.id]
      if not keys then
        keys = {}
        D.byQuest[e.id] = keys
      end
      keys[#keys + 1] = key
      D.quests = D.quests + 1
      touched[dg] = true
    end
  end
  for dg in pairs(touched) do sort(dg.quests) end
end

-- Retail client: no data addon, no QuestieDB; the tests of the retail map space (ALLOW_RETAIL) and the test mode keep the data
local function retail()
  return OQ ~= nil and OQ.retailClient() and not (OQ.test() ~= nil or OQ.ALLOW_RETAIL)
end

-- parsed table or nil, reason. The first call loads the data addon (OpenQuests.available: never in combat or before login).
local function ensure()
  if not OQ then return nil, "NO_DATA" end
  if retail() then return nil, "RETAIL" end
  if not M.D and inCombat() then return nil, "COMBAT" end
  if not OQ.available() then
    local st = OQ.status()
    return nil, (st and st.reason) or "UNKNOWN"
  end
  local blob, data = OQ.dungeonBlob()
  if not blob then return nil, "NO_DUNGEON_DATA" end
  local learned, lsig = scanLearned()
  if M.D and M.blob == blob and M.data == data and M.lsig == lsig then return M.D end
  local t0 = clock()
  local ok, D = pcall(parse, blob)
  if not ok or type(D) ~= "table" or #D.list == 0 then
    M.D, M.blob, M.data = nil, nil, nil
    return nil, "NO_DUNGEON_DATA"
  end
  if #learned > 0 then pcall(applyLearned, D, learned) end -- a failure here only loses the learned quests
  M.D, M.blob, M.data, M.exp, M.c, M.lsig = D, blob, data, {}, nil, lsig
  M.diag = { parseMs = clock() - t0, expandMs = 0, missing = 0, maxNodes = 0 }
  return D
end

function DQ.available()
  local D, reason = ensure()
  return D ~= nil, reason
end

local REASON_TEXT = { RETAIL = "reasonRetail", NO_DUNGEON_DATA = "reasonNoData", COMBAT = "reasonCombat" }

function DQ.reasonText(reason)
  local k = type(reason) == "string" and REASON_TEXT[reason] or nil
  if k then return T[k] end
  return OQ and OQ.reasonText(reason) or tostring(reason)
end

function DQ.status()
  local D, reason = ensure()
  return { available = D ~= nil, reason = reason, reasonText = reason and DQ.reasonText(reason) or nil }
end

-- caches of one generation (events, arriving names): records, states, results
local function cache()
  local g, n = OQ.generation()
  local c = M.c
  if not c or M.cg ~= g or M.cn ~= n then
    c = { rec = {}, st = {}, ent = {}, names = {}, counts = {}, res = {}, ids = {} }
    M.c, M.cg, M.cn = c, g, n
  end
  return c
end

local function rec(c, id)
  local r = c.rec[id]
  if r == nil then
    r = OQ.record(id) or false
    c.rec[id] = r
  end
  return r or nil
end

-- states of the quests in ids into the cache (one reader call for the missing ones)
local function loadStates(c, ids)
  local need
  for _, id in ipairs(ids) do
    if c.st[id] == nil then
      need = need or {}
      need[#need + 1] = id
    end
  end
  if need then
    local got = OQ.statesOf(need)
    for _, id in ipairs(need) do c.st[id] = got[id] or false end
  end
end

local function stOf(c, id)
  return c.st[id] or nil
end

local function lvOf(r)
  return r.level or r.minLevel or 0
end

local function sortByLevel(c)
  return function(a, b)
    local ra, rb = rec(c, a), rec(c, b)
    local la, lb = ra and lvOf(ra) or 999, rb and lvOf(rb) or 999
    if la ~= lb then return la < lb end
    return a < b
  end
end

-- the name of a dungeon in the language of the data: German client German (when there is one), else English, else the key
local function dungeonName(dg)
  local german = M.data and M.data.german
  local first, second = dg.nameEN, dg.nameDE
  if german then first, second = dg.nameDE, dg.nameEN end
  if first ~= "" then return first end
  if second ~= "" then return second end
  return dg.key
end

local function mapNameOf(c, mapID)
  local n = c.names[mapID]
  if n == nil then
    n = OQ.mapName(mapID) or false
    c.names[mapID] = n
  end
  return n or nil
end

-- entrances in the client's map space
local function entrancesOf(c, dg)
  local e = c.ent[dg.key]
  if e then return e end
  e = {}
  for _, en in ipairs(dg.entrances) do
    local mid, x, y = OQ.pointOut(en.mapID, en.x, en.y)
    if mid then e[#e + 1] = { mapID = mid, x = x, y = y, name = mapNameOf(c, mid) } end
  end
  c.ent[dg.key] = e
  return e
end

-- ---------------------------------------------------------------- counts

local PRIO = { done = 4, log = 3, open = 2, locked = 1 }

local function hasId(list, id)
  if list then
    for _, x in ipairs(list) do
      if x == id then return true end
    end
  end
  return false
end

-- counts over a list of quest IDs: foreign ones are left out; quests voided by a done/accepted alternative (own excl; the other
-- way round, i.e. listed as excl by another quest, only if that exclusion is mutual) are left out; alternatives that exclude each other (mutual) count once (best state)
local function tally(c, ids)
  local list, seen = {}, {}
  for _, id in ipairs(ids) do
    if not seen[id] then
      seen[id] = true
      list[#list + 1] = id
    end
  end
  local extra = {}
  for _, id in ipairs(list) do
    local r = rec(c, id)
    if r and r.excl then
      for _, x in ipairs(r.excl) do
        if not seen[x] then
          seen[x] = "peer"
          extra[#extra + 1] = x
        end
      end
    end
  end
  loadStates(c, list)
  loadStates(c, extra)
  local res = { all = 0, total = 0, done = 0, log = 0, open = 0, locked = 0, foreign = 0, voided = 0 }
  local cand, rev = {}, {}
  for _, id in ipairs(list) do
    local r, st = rec(c, id), stOf(c, id)
    if r and st then
      res.all = res.all + 1
      if st.partial then res.partial = true end
      if st.state == "foreign" then
        res.foreign = res.foreign + 1
      else
        cand[#cand + 1] = id
        for _, x in ipairs(r.excl or EMPTY) do
          local t = rev[x]
          if not t then
            t = {}
            rev[x] = t
          end
          t[#t + 1] = id
        end
      end
    end
  end
  local live, liveSet = {}, {}
  for _, id in ipairs(cand) do
    local st = stOf(c, id)
    local void = false
    if st.state ~= "done" and st.state ~= "log" then
      local r = rec(c, id)
      for _, x in ipairs(r.excl or EMPTY) do
        local sx = stOf(c, x)
        if sx and (sx.state == "done" or sx.state == "log") then void = true break end
      end
      if not void then
        -- reverse voiding only if the exclusion is mutual (both list each other): QuestieDB often has one-sided entries
        -- (e.g. 2923 excludes 2922 but not the other way round); the row of the other quest shows no reason then, so it must
        -- not be dropped from the counts either
        for _, x in ipairs(rev[id] or EMPTY) do
          local sx = stOf(c, x)
          if sx and (sx.state == "done" or sx.state == "log") and hasId(r.excl, x) then void = true break end
        end
      end
    end
    if void then
      res.voided = res.voided + 1
    else
      live[#live + 1] = id
      liveSet[id] = true
    end
  end
  -- mutual exclusion groups (union-find)
  local parent = {}
  local function root(x)
    while parent[x] and parent[x] ~= x do
      parent[x] = parent[parent[x]] or parent[x]
      x = parent[x]
    end
    return x
  end
  for _, id in ipairs(live) do parent[id] = id end
  for _, id in ipairs(live) do
    local r = rec(c, id)
    for _, x in ipairs(r.excl or EMPTY) do
      if liveSet[x] then
        local rx = rec(c, x)
        if rx and hasId(rx.excl, id) then
          local a, b = root(id), root(x)
          if a ~= b then parent[b] = a end
        end
      end
    end
  end
  local unit = {}
  for _, id in ipairs(live) do
    local k = root(id)
    local s = stOf(c, id).state
    if not unit[k] or PRIO[s] > PRIO[unit[k]] then unit[k] = s end
  end
  for _, s in pairs(unit) do
    res.total = res.total + 1
    res[s] = res[s] + 1
  end
  res.complete = res.total > 0 and res.done == res.total
  return res
end

local function dungeonCounts(c, dg)
  local n = c.counts[dg.key]
  if n then return n end
  n = tally(c, dg.quests)
  local est = 0
  for _, id in ipairs(dg.quests) do
    local g = dg.grade[id]
    if g == "a" or g == "k" or g == "m" or dg.star[id] then est = est + 1 end
  end
  n.estimated = est
  n.empty = n.total == 0
  c.counts[dg.key] = n
  return n
end

-- ---------------------------------------------------------------- list

local function levelRel(level, dg)
  if level < dg.minLevel then return "coming" end
  if level > dg.maxLevel then return "below" end
  return "fit"
end

local function needleOf(s)
  if type(s) ~= "string" or isSecret(s) then return nil end
  local d = display(s, DQ.SEARCH_MAX)
  if not d then return nil end
  d = lower(d)
  d = match(d, "^%s*(.-)%s*$")
  return d ~= "" and d or nil
end

local function unavailable(extra, reason)
  local r = { unavailable = true, reason = reason, dungeons = {}, hiddenEmpty = 0 }
  for k, v in pairs(extra or EMPTY) do r[k] = v end
  return r
end

function DQ.list(opts)
  if type(opts) ~= "table" or isSecret(opts) then opts = EMPTY end
  local D, reason = ensure()
  if not D then return unavailable(nil, reason) end
  local c = cache()
  local needle = needleOf(opts.search)
  local rkey = (opts.all == true and "A" or "-") .. "|" .. (needle or "")
  local hit = c.res["L|" .. rkey]
  if hit then return hit end
  local profile = OQ.profileInfo()
  local res = { dungeons = {}, hiddenEmpty = 0, level = profile.level, search = needle }
  for _, dg in ipairs(D.list) do
    local n = dungeonCounts(c, dg)
    local hits, nameHit = 0, false
    if needle then
      nameHit = (find(lower(dg.nameDE), needle, 1, true) or find(lower(dg.nameEN), needle, 1, true)) ~= nil
      for _, id in ipairs(dg.quests) do
        local r = rec(c, id)
        if r and find(lower(r.name), needle, 1, true) then hits = hits + 1 end
      end
    end
    if not needle or nameHit or hits > 0 then
      if n.empty and opts.all ~= true then
        res.hiddenEmpty = res.hiddenEmpty + 1
      else
        res.dungeons[#res.dungeons + 1] = { key = dg.key, name = dungeonName(dg), nameDE = dg.nameDE, nameEN = dg.nameEN,
          minLevel = dg.minLevel, maxLevel = dg.maxLevel, levelRel = levelRel(profile.level, dg), entrances = entrancesOf(c, dg),
          total = n.total, done = n.done, log = n.log, open = n.open, locked = n.locked, foreign = n.foreign, voided = n.voided,
          all = n.all, estimated = n.estimated, complete = n.complete, empty = n.empty, hits = hits,
          partial = n.partial }
        if n.partial then res.partial = true end
      end
    end
  end
  sort(res.dungeons, function(a, b)
    if a.empty ~= b.empty then return not a.empty end
    if a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end
    if a.maxLevel ~= b.maxLevel then return a.maxLevel < b.maxLevel end
    if a.name ~= b.name then return a.name < b.name end
    return a.key < b.key
  end)
  c.res["L|" .. rkey] = res
  return res
end

function DQ.entrancePins(dungeons, mapID)
  local out = {}
  mapID = num(mapID)
  if type(dungeons) ~= "table" or not mapID then return out end
  for _, dg in ipairs(dungeons) do
    for _, e in ipairs(dg.entrances or EMPTY) do
      if e.mapID == mapID then
        out[#out + 1] = { mapID = e.mapID, x = e.x, y = e.y, key = dg.key, name = dg.name, open = dg.open or 0, total = dg.total or 0 }
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------- chains

-- the connected quests of a dungeon: its own quests plus prerequisites and follow-ups (preAll/preAny) around them. Quests of other
-- dungeons stay in (row.elsewhere); the walk stops forward at group quests without a dungeon (raids and the like), counted in
-- "continues" (number of quests only, not listed). Static per data table.
local function expand(c, D, dg)
  local e = M.exp[dg.key]
  if e then return e end
  local t0 = clock()
  local isSeed, inSet, nodes, queue = {}, {}, {}, {}
  local missing = 0
  for _, id in ipairs(dg.quests) do
    if rec(c, id) then
      isSeed[id], inSet[id] = true, true
      nodes[#nodes + 1] = id
      queue[#queue + 1] = id
    else
      missing = missing + 1
    end
  end
  local fol = OQ.followers() or EMPTY
  local stopAfter = {}
  local qi = 1
  while queue[qi] do
    local id = queue[qi]
    qi = qi + 1
    local r = rec(c, id)
    local function visit(nid, forward)
      if inSet[nid] or (forward and stopAfter[nid]) then return end
      local rn = rec(c, nid)
      if not rn then return end
      -- quests of another dungeon stay in the chain (shared chains run through several dungeons, shown capped in each)
      local raid = forward and rn.flags.g == true and D.byQuest[nid] == nil
      if raid then
        stopAfter[nid] = true
      else
        inSet[nid] = true
        nodes[#nodes + 1] = nid
        queue[#queue + 1] = nid
      end
    end
    for _, p in ipairs(r.preAll or EMPTY) do visit(p, false) end
    for _, p in ipairs(r.preAny or EMPTY) do visit(p, false) end
    for _, f in ipairs(fol[id] or EMPTY) do visit(f, true) end
  end
  sort(nodes)
  local continues = 0
  for _ in pairs(stopAfter) do continues = continues + 1 end
  e = { nodes = nodes, isSeed = isSeed, continues = continues, missing = missing }
  M.exp[dg.key] = e
  M.diag.expandMs = (M.diag.expandMs or 0) + (clock() - t0)
  M.diag.missing = (M.diag.missing or 0) + missing
  if #nodes > (M.diag.maxNodes or 0) then M.diag.maxNodes = #nodes end
  return e
end

local function dungeonsOf(D, id)
  local keys = D.byQuest[id]
  return keys or EMPTY
end

-- hints (notes) of a quest in the context of a dungeon (dg may be nil)
local function hintsFor(c, D, id, dg, r, st, giverKind)
  local out = {}
  local TX = OQ.TEXT
  if r.unsure then out[#out + 1] = { kind = "unsure", text = TX.unsureLabel, tip = TX.unsureTip } end
  local keys = dungeonsOf(D, id)
  local star = false
  for _, k in ipairs(keys) do
    local d2 = D.byKey[k]
    if d2 and d2.star[id] then star = true end
  end
  local g = dg and dg.grade[id] or nil
  if star or #keys > 1 or g == "a" or g == "k" or g == "m" then
    local tip = T.tipEstimated
    if #keys > 1 then
      local names = {}
      for _, k in ipairs(keys) do names[#names + 1] = dungeonName(D.byKey[k]) end
      tip = T("tipAmbiguous", table.concat(names, ", "))
    end
    out[#out + 1] = { kind = "estimated", text = T.hintEstimated, tip = tip }
  end
  if dg and dg.learned and dg.learned[id] then
    out[#out + 1] = { kind = "learned", text = T.hintLearned, tip = T.tipLearned }
  end
  if giverKind == "inside" then
    out[#out + 1] = { kind = "giverInside", text = T.hintGiverInside, tip = T.tipGiverInside }
  elseif giverKind == "none" then
    out[#out + 1] = { kind = "giverNone", text = T.hintGiverNone, tip = T.tipGiverNone }
  end
  if r.flags.s then out[#out + 1] = { kind = "notChecked", text = TX.notChecked } end
  if st.raceUnsure then out[#out + 1] = { kind = "raceUnsure", text = TX.raceUnsure } end
  if id >= DQ.FOREVER_NEW_ID then out[#out + 1] = { kind = "foreverNew", text = T.hintForeverNew, tip = T.tipForeverNew } end
  return out
end

local function todoVia(kind)
  if kind == "outside" then return "giver" end
  if kind == "inside" then return "entrance" end
  return nil
end

-- the record of a quest for the lists (no structure fields)
local function baseRow(c, D, dg, id, isSeed)
  local r, st = rec(c, id), stOf(c, id)
  if not (r and st) then return nil end
  local kind = OQ.giverKind(id)
  local keys = dungeonsOf(D, id)
  local g = dg and dg.grade[id] or nil
  local row = { id = id, name = r.name, level = r.level, minLevel = r.minLevel, state = st.state, reasons = st.reasons, unsure = r.unsure,
    partial = st.partial, seed = isSeed == true, outside = not isSeed, elsewhere = (not isSeed and #keys > 0) or nil, assign = g, dungeons = keys, giverKind = kind, todo = todoVia(kind),
    excl = r.excl or EMPTY }
  local star = false
  for _, k in ipairs(keys) do
    local d2 = D.byKey[k]
    if d2 and d2.star[id] then star = true end
  end
  row.ambiguous = star or #keys > 1
  row.estimated = row.ambiguous or g == "a" or g == "k" or g == "m"
  row.notes = hintsFor(c, D, id, dg, r, st, kind)
  if not isSeed and kind == "outside" then
    local mid = OQ.giverMap(id)
    if mid then
      row.zoneMap = mid
      row.zone = mapNameOf(c, mid)
    end
  end
  return row
end

local function emptyQuests(dg, c, extra)
  local r = { key = dg and dg.key, chains = {}, singles = {}, byId = {}, hiddenForeign = 0, hiddenLocked = 0, continues = 0 }
  for k, v in pairs(extra or EMPTY) do r[k] = v end
  return r
end

function DQ.quests(key, opts)
  if type(opts) ~= "table" or isSecret(opts) then opts = EMPTY end
  local D, reason = ensure()
  if not D then return unavailable({ key = type(key) == "string" and key or nil, chains = {}, singles = {}, byId = {} }, reason) end
  local dg = type(key) == "string" and D.byKey[key] or nil
  if not dg then return emptyQuests(nil, nil, { unknown = true }) end
  local c = cache()
  local rkey = "Q|" .. dg.key .. "|" .. (opts.foreign == true and "F" or "-") .. (opts.locked == true and "L" or "-")
  if c.res[rkey] then return c.res[rkey] end
  local t0 = clock()
  local e = expand(c, D, dg)
  local nodes = e.nodes
  loadStates(c, nodes)
  local peers = {}
  for _, id in ipairs(nodes) do
    local r = rec(c, id)
    for _, x in ipairs(r and r.excl or EMPTY) do peers[#peers + 1] = x end
  end
  loadStates(c, peers)

  -- keep: nodes shown (other faction/race/class left out unless asked for)
  local keep, kept, hiddenForeign = {}, {}, 0
  for _, id in ipairs(nodes) do
    local st = stOf(c, id)
    if st and rec(c, id) then
      if st.state == "foreign" and opts.foreign ~= true then
        hiddenForeign = hiddenForeign + 1
      else
        keep[id] = true
        kept[#kept + 1] = id
      end
    end
  end
  local byLevel = sortByLevel(c)

  -- edges among the kept quests
  local parents, children = {}, {}
  for _, id in ipairs(kept) do
    local r = rec(c, id)
    local ps, seen = {}, {}
    for _, p in ipairs(r.preAll or EMPTY) do
      if keep[p] and not seen[p] and p ~= id then
        seen[p] = true
        ps[#ps + 1] = p
      end
    end
    local nAll = #ps
    for _, p in ipairs(r.preAny or EMPTY) do
      if keep[p] and not seen[p] and p ~= id then
        seen[p] = true
        ps[#ps + 1] = p
      end
    end
    parents[id] = { all = nAll, list = ps }
    for _, p in ipairs(ps) do
      local ch = children[p]
      if not ch then
        ch = {}
        children[p] = ch
      end
      ch[#ch + 1] = id
    end
  end
  for _, ch in pairs(children) do sort(ch, byLevel) end

  -- exclusion relation among the kept quests (own excl or listed by the other)
  local alt = {}
  for _, id in ipairs(kept) do
    local r = rec(c, id)
    for _, x in ipairs(r.excl or EMPTY) do
      if keep[x] and x ~= id then
        alt[id] = alt[id] or {}
        alt[x] = alt[x] or {}
        if not hasId(alt[id], x) then alt[id][#alt[id] + 1] = x end
        if not hasId(alt[x], id) then alt[x][#alt[x] + 1] = id end
      end
    end
  end
  for _, list in pairs(alt) do sort(list) end
  local function exclusive(a, b)
    return hasId(alt[a], b)
  end

  -- components (undirected over the pre links)
  local comp, comps = {}, {}
  for _, id in ipairs(kept) do
    if not comp[id] then
      local members, stack = {}, { id }
      comp[id] = true
      while #stack > 0 do
        local x = stack[#stack]
        stack[#stack] = nil
        members[#members + 1] = x
        for _, y in ipairs(parents[x].list) do
          if not comp[y] then
            comp[y] = true
            stack[#stack + 1] = y
          end
        end
        for _, y in ipairs(children[x] or EMPTY) do
          if not comp[y] then
            comp[y] = true
            stack[#stack + 1] = y
          end
        end
      end
      sort(members, byLevel)
      comps[#comps + 1] = members
    end
  end

  -- longest path from a root (cycle-safe)
  local stepOf, visiting = {}, {}
  local function step(id)
    local s = stepOf[id]
    if s then return s end
    if visiting[id] then return 1 end
    visiting[id] = true
    local best = 0
    for _, p in ipairs(parents[id].list) do best = max(best, step(p)) end
    visiting[id] = nil
    stepOf[id] = best + 1
    return best + 1
  end

  local byId = {}
  local function makeRow(id, depth, parentId)
    local row = baseRow(c, D, dg, id, e.isSeed[id])
    row.depth = depth
    row.indent = min(depth, DQ.INDENT_MAX)
    row.deep = depth > DQ.INDENT_MAX or nil
    row.step = step(id)
    row.parent = parentId
    row.alt = alt[id] or EMPTY
    local ps = parents[id]
    if #ps.list >= 2 then
      local all, any = {}, {}
      for i, p in ipairs(ps.list) do
        if i <= ps.all then all[#all + 1] = p else any[#any + 1] = p end
      end
      if #all >= 2 or (#all >= 1 and #any >= 1) then
        row.after, row.afterMode = all, "all"
        if #any > 0 then row.afterAny = any end
      else
        row.after, row.afterMode = any, "any"
      end
    end
    local ch = children[id]
    if ch and #ch >= 2 then
      local either = true
      for i = 1, #ch do
        for j = i + 1, #ch do
          if not exclusive(ch[i], ch[j]) then either = false end
        end
      end
      row.fork = { n = #ch, kind = either and "either" or "then" }
    end
    return row
  end

  local chains, singles = {}, {}
  local showLocked = opts.locked == true
  local hiddenLocked = 0
  for _, members in ipairs(comps) do
    if #members == 1 then
      local row = makeRow(members[1], 0, nil)
      byId[row.id] = row
      if row.state == "locked" and not showLocked then
        hiddenLocked = hiddenLocked + 1
      else
        singles[#singles + 1] = row
      end
    else
      local rows, placed = {}, {}
      local function place(id, depth, parentId)
        placed[id] = true
        local row = makeRow(id, depth, parentId)
        byId[id] = row
        rows[#rows + 1] = row
        if depth >= DQ.DEPTH_MAX then return end
        for _, ch in ipairs(children[id] or EMPTY) do
          if placed[ch] then
            rows[#rows + 1] = { ref = true, id = ch, of = id, depth = depth + 1, indent = min(depth + 1, DQ.INDENT_MAX) }
          else
            if not row.firstChild then row.firstChild = ch end
            place(ch, depth + 1, id)
          end
        end
      end
      for _, id in ipairs(members) do
        if #parents[id].list == 0 then place(id, 0, nil) end
      end
      for _, id in ipairs(members) do -- cycles without a root
        if not placed[id] then place(id, 0, nil) end
      end
      local steps = 0
      for _, id in ipairs(members) do steps = max(steps, stepOf[id] or 1) end
      local counts = tally(c, members)
      -- locked rows are hidden unless asked for (structure, depth and counts stay as they are)
      local visible = {}
      for _, row in ipairs(rows) do
        if row.ref then
          local target = byId[row.id]
          if showLocked or not target or target.state ~= "locked" then visible[#visible + 1] = row end
        elseif row.state == "locked" and not showLocked then
          hiddenLocked = hiddenLocked + 1
        else
          visible[#visible + 1] = row
        end
      end
      local head = rows[1]
      for _, row in ipairs(rows) do
        if not row.ref then row.chainId, row.chainSteps = head.id, steps end
      end
      local shown, n = {}, 0
      for _, row in ipairs(visible) do
        if not row.ref then
          if n >= DQ.CHAIN_MAX then break end
          n = n + 1
        end
        shown[#shown + 1] = row
      end
      local totalVisible = 0
      for _, row in ipairs(visible) do
        if not row.ref then totalVisible = totalVisible + 1 end
      end
      if totalVisible > 0 then
        chains[#chains + 1] = { id = head.id, name = head.name, total = #members, counts = counts, steps = steps,
          collapsed = counts.complete or nil, rows = shown, all = visible, more = totalVisible - n }
      end
    end
  end
  sort(chains, function(a, b)
    local ra, rb = byId[a.id], byId[b.id]
    local la, lb = ra and lvOf(ra) or 999, rb and lvOf(rb) or 999
    if la ~= lb then return la < lb end
    return a.id < b.id
  end)
  sort(singles, function(a, b)
    local la, lb = lvOf(a), lvOf(b)
    if la ~= lb then return la < lb end
    return a.id < b.id
  end)

  local profile = OQ.profileInfo()
  local res = { key = dg.key, name = dungeonName(dg), nameDE = dg.nameDE, nameEN = dg.nameEN, minLevel = dg.minLevel, maxLevel = dg.maxLevel,
    levelRel = levelRel(profile.level, dg), entrances = entrancesOf(c, dg), counts = dungeonCounts(c, dg), chains = chains, singles = singles,
    continues = e.continues, missing = e.missing, byId = byId, hiddenForeign = hiddenForeign, hiddenLocked = hiddenLocked }
  c.res[rkey] = res
  M.diag.lastBuildMs = clock() - t0
  return res
end

-- ---------------------------------------------------------------- single quests, details

-- the dungeon context of a quest: the given key, else the first dungeon that lists it
local function contextOf(D, id, key)
  local dg = type(key) == "string" and D.byKey[key] or nil
  if dg then return dg end
  local keys = D.byQuest[id]
  return keys and D.byKey[keys[1]] or nil
end

function DQ.hints(id, key)
  local D = ensure()
  id = num(id)
  if not (D and id) then return {} end
  id = floor(id)
  local c = cache()
  loadStates(c, { id })
  local r, st = rec(c, id), stOf(c, id)
  if not (r and st) then return {} end
  return hintsFor(c, D, id, contextOf(D, id, key), r, st, OQ.giverKind(id))
end

function DQ.stateOf(id, key)
  local D = ensure()
  id = num(id)
  if not (D and id) then return nil end
  id = floor(id)
  local c = cache()
  loadStates(c, { id })
  local dg = contextOf(D, id, key)
  return baseRow(c, D, dg, id, dg ~= nil and dg.set[id] == true)
end

-- the path through a quest of a quests() result: its prerequisites (placing quests up to the root), itself, its first follow-ups
function DQ.stations(res, id)
  local out = {}
  id = num(id)
  if type(res) ~= "table" or not id or type(res.byId) ~= "table" then return out end
  local row = res.byId[floor(id)]
  if not row then return out end
  local up, guard = {}, 0
  local x = row
  while x.parent and guard < DQ.DEPTH_MAX do
    local p = res.byId[x.parent]
    if not p then break end
    table.insert(up, 1, p)
    x = p
    guard = guard + 1
  end
  for _, p in ipairs(up) do out[#out + 1] = { id = p.id, state = p.state } end
  out[#out + 1] = { id = row.id, state = row.state, current = true }
  local d = row
  guard = 0
  while d.firstChild and guard < DQ.DEPTH_MAX do
    local ch = res.byId[d.firstChild]
    if not ch then break end
    out[#out + 1] = { id = ch.id, state = ch.state }
    d = ch
    guard = guard + 1
  end
  return out
end

local CLASSIC_RACES = { "Human", "Orc", "Dwarf", "NightElf", "Scourge", "Tauren", "Gnome", "Troll" }
local CLASSIC_CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local function hasBit(mask, bit)
  return floor((mask % (bit * 2)) / bit) == 1
end

-- chips: faction (nil = both), class and race tokens the quest is restricted to
local function chipsOf(r)
  local chips = { classes = {}, races = {} }
  local classic = (r.races or 0) % 256
  if classic ~= 0 then
    local ally, horde = false, false
    for i, name in ipairs(CLASSIC_RACES) do
      local bit = 2 ^ (i - 1)
      if hasBit(classic, bit) then
        chips.races[#chips.races + 1] = name
        if hasBit(77, bit) then ally = true else horde = true end
      end
    end
    chips.faction = (ally and not horde) and "Alliance" or (horde and not ally) and "Horde" or nil
    if #chips.races == #CLASSIC_RACES then chips.races = {} end
  end
  local cmask = (r.classes or 0) % 4294967296
  if cmask ~= 0 and OQ.CLASS_BIT then
    for _, token in ipairs(CLASSIC_CLASSES) do
      local bit = OQ.CLASS_BIT[token]
      if bit and hasBit(cmask % 2048, bit) then chips.classes[#chips.classes + 1] = token end
    end
  end
  return chips
end

local function refOf(c, id)
  local r, st = rec(c, id), stOf(c, id)
  return { id = id, name = r and r.name or nil, state = st and st.state or nil }
end

function DQ.detail(id, key, opts)
  local D = ensure()
  id = num(id)
  if not (D and id) then return nil end
  id = floor(id)
  local c = cache()
  loadStates(c, { id })
  local r = rec(c, id)
  if not r then return nil end
  local dg = contextOf(D, id, key)
  local row = baseRow(c, D, dg, id, dg ~= nil and dg.set[id] == true)
  if not row then return nil end
  local pre = {}
  for _, p in ipairs(r.preAll or EMPTY) do pre[#pre + 1] = p end
  for _, p in ipairs(r.preAny or EMPTY) do pre[#pre + 1] = p end
  for _, x in ipairs(r.excl or EMPTY) do pre[#pre + 1] = x end
  loadStates(c, pre)
  local d = {}
  for k, v in pairs(row) do d[k] = v end
  d.prereqAll, d.prereqAny, d.excl, d.chips = {}, {}, {}, chipsOf(r)
  for _, p in ipairs(r.preAll or EMPTY) do d.prereqAll[#d.prereqAll + 1] = refOf(c, p) end
  for _, p in ipairs(r.preAny or EMPTY) do d.prereqAny[#d.prereqAny + 1] = refOf(c, p) end
  for _, x in ipairs(r.excl or EMPTY) do d.excl[#d.excl + 1] = refOf(c, x) end
  d.givers = OQ.giversOf(id)
  d.dungeon = dg and { key = dg.key, name = dungeonName(dg), entrances = entrancesOf(c, dg) } or nil
  d.todo = { via = row.todo, reason = row.todo == nil and "item-start" or nil }
  if dg then
    local res = DQ.quests(dg.key, type(opts) == "table" and opts or { locked = true, foreign = true })
    local x = res.byId and res.byId[id]
    if x then
      d.step, d.parent = x.step, x.parent
      d.stations = DQ.stations(res, id)
      if x.chainId then
        local head = res.byId[x.chainId]
        d.steps, d.chain = x.chainSteps, { id = x.chainId, name = head and head.name or nil }
      end
    end
  end
  return d
end

-- ---------------------------------------------------------------- "Als To Do"

local function nearestPoint(givers, pin)
  local best, bd
  for _, g in ipairs(givers or EMPTY) do
    for _, pt in ipairs(g.points or EMPTY) do
      local dd = (pt[1] - pin.x) ^ 2 + (pt[2] - pin.y) ^ 2
      if g.mapID == pin.mapID and (not bd or dd < bd) then best, bd = { mapID = g.mapID, x = pt[1], y = pt[2] }, dd end
    end
  end
  return best
end

function DQ.addTodo(key, id, opts)
  if type(opts) ~= "table" or isSecret(opts) then opts = EMPTY end
  local D = ensure()
  id = num(id)
  if not (D and id) then return nil, "unbekannt" end
  id = floor(id)
  local r = OQ.record(id)
  if not r then return nil, "unbekannt" end
  local givers, kind = OQ.giversOf(id)
  if kind == "outside" then
    local o = { unique = true }
    local pin = type(opts.pin) == "table" and not isSecret(opts.pin) and num(opts.pin.x) and num(opts.pin.y) and num(opts.pin.mapID) and opts.pin or nil
    local at = pin and nearestPoint(givers, pin) or nil
    if at then
      o.mapID, o.x, o.y = at.mapID, at.x, at.y
    elseif type(opts.giver) == "table" then
      o.giver = opts.giver
    end
    local goal, why = OQ.addTodo({ id = id, name = r.name, givers = givers }, o)
    return goal, why, "giver"
  elseif kind == "inside" then
    local dg = contextOf(D, id, key)
    if not dg then return nil, "kein-ort" end
    local c = cache()
    local en = entrancesOf(c, dg)[1]
    if not en then return nil, "kein-ort" end
    local text = T("todoEntrance", dungeonName(dg), r.name)
    local goal, why = OQ.addTodo({ id = id, name = r.name }, { mapID = en.mapID, x = en.x, y = en.y, text = text, unique = true })
    return goal, why, "entrance"
  end
  return nil, "item-start"
end

-- ---------------------------------------------------------------- change notice, footer, diagnostics

function DQ.onChange(fn)
  if type(fn) ~= "function" then return false end
  M.listeners[#M.listeners + 1] = fn
  if not M.hooked and OQ and type(OQ.listen) == "function" then
    M.hooked = true
    OQ.listen(function()
      for _, f in ipairs(M.listeners) do pcall(f) end
    end)
    -- the index arrives or grows later than the first draw: a changed learned list redraws the page
    local Idx = Journal.Index
    if type(Idx) == "table" and type(Idx.onReady) == "function" then
      Idx.onReady(function()
        if not M.D then return end
        local _, sig = scanLearned()
        if sig ~= M.lsig then
          for _, f in ipairs(M.listeners) do pcall(f) end
        end
      end)
    end
  end
  return true
end

function DQ.footer()
  local base = OQ and OQ.footer() or ""
  return base .. " · " .. T.footerAssign
end

function DQ.diagInfo()
  local D = M.D
  local d = M.diag or EMPTY
  return { loaded = D ~= nil, dungeons = D and #D.list or 0, quests = D and D.quests or 0, badLines = D and D.bad or 0,
    missing = d.missing or 0, parseMs = d.parseMs, expandMs = d.expandMs, lastBuildMs = d.lastBuildMs, maxNodes = d.maxNodes or 0 }
end

function DQ.diagLine()
  local D, reason = ensure()
  if not D then return T("diagNotLoaded", DQ.reasonText(reason)) end
  local info = DQ.diagInfo()
  return T("diagLoaded", info.dungeons, info.quests, info.missing)
end

DQ._state = M
