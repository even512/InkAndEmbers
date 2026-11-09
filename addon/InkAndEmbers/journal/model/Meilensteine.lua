-- Milestones ("Meilensteine", Chronik): what each stretch of ten levels held (1-10, 10-20, ... up to the highest level) plus the
-- closing tally of the whole journey. Pure read logic over the index (lists LV, PL, QT, ZN, DE, LT, the kill series, the
-- instance runs of model/Dungeons.lua) and Chronik.static (time per level, away time per level, deaths per level); nothing is
-- stored, no new log line, works backwards for milestones reached before this file existed.
--   Meilensteine.build(index) -> res (cached per index, weak keys: freed with the index)
--     res = { sections = { sec, ... } (n = 10, 20, ... <= maxLevel), final = sec (final = true), reached, start, maxLevel,
--             step, latest = n of the last reached milestone | nil }
--     sec = { n, from, to, state ("done" | "running" | "open"), t0, t1, partial, since (first recorded level when partial),
--             nodata (reached before the recording began), empty (no data in the window), truncated (a list hit its cap:
--             "at least"), seconds (active time without away time, nil = unknown), secondsApprox, zonesNew, zoneNames (<= 3, zoneNamesAll <= 24 for the tooltip,
--             raw SV text), placeEnd (raw), kills, killsExact, quests, deaths, dungeons = { runs, bosses },
--             best = { itemID, key, quality, name (raw), ilvl, link } | nil, at = epoch of reaching n }
--     final additionally: days (play days), seals = { broken, total }, cols = { { n, seconds }, ... } (time per section)
--   Meilensteine.find(res, key) -> sec   (key = 10, 20, ... or "final")
-- Names are raw SV text: display only via Sanitize.display (the texts in journal/Meilenstein.lua and the page do that).
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Meilensteine = {}
Journal.Meilensteine = Meilensteine

local floor, max, min, huge = math.floor, math.max, math.min, math.huge
local match = string.match

Meilensteine.STEP = 10            -- a milestone every ten levels
Meilensteine.ZONE_NAMES = 3       -- zone names kept per section (the text names at most three)
Meilensteine.ZONE_NAMES_ALL = 24  -- all names of a section for the tooltip of the page (zoneNamesAll)
Meilensteine.BEST_CANDIDATES = 8  -- finds of the top quality compared by item level (client lookups, best effort)
Meilensteine.NAME_MAX = 80        -- bytes of a raw name kept (long zone and item names stay whole)
-- bought or handed over is not a find
Meilensteine.NOT_FOUND = { vendor = true, mail = true, trade = true, ah = true }
-- lists whose cap makes the numbers a lower bound ("mindestens")
Meilensteine.TRUNC_CODES = { "LV", "QT", "ZN", "DE", "LT", "killT" }

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function finite(v)
  return type(v) == "number" and v == v and v ~= huge and v ~= -huge
end

local function I() return Journal.Index end

local function levelOf(rec, code)
  local v = I().num(rec, code, "level")
  if finite(v) and v >= 1 and v <= 200 then return floor(v) end
  return nil
end

local function rawName(v)
  if isSecret(v) or type(v) ~= "string" or v == "" then return nil end
  if #v > Meilensteine.NAME_MAX then v = ns.Sanitize and ns.Sanitize.cut(v, Meilensteine.NAME_MAX) or string.sub(v, 1, Meilensteine.NAME_MAX) end
  return v
end

local function snapGroup(index, name)
  local char = type(index.char) == "table" and index.char or nil
  local snaps = char and type(char.snapshots) == "table" and char.snapshots or nil
  local g = snaps and snaps[name]
  return type(g) == "table" and g or nil
end

-- name of a map: the name stored at the first arrival (snapshots.maps), else the book's own zone table (MapSpace.NAMES);
-- nil when unknown (the text then leaves the zone out, it never shows a map number)
local function mapName(index, mapID)
  local maps = snapGroup(index, "maps")
  local e = maps and finite(mapID) and maps[mapID] or nil
  local n = type(e) == "table" and rawName(e.name) or nil
  if n then return n end
  local MS = Journal.MapSpace
  if MS and type(MS.name) == "function" and finite(mapID) then
    local ok, v = pcall(MS.name, mapID)
    if ok then return rawName(v) end
  end
  return nil
end

-- A new zone is a ZN line (first arrival on a map) of map type 3 that is its own main zone (field "zone" empty or the map
-- itself): the same rule as the area pop-up and the chapters of the journey (Model: a map counts with its main zone). Sub maps
-- the client also types 3 (their main zone is another map), caves, cities and dungeons do not count; each main zone once.
function Meilensteine.isNewZone(rec)
  local Idx = I()
  if Idx.num(rec, "ZN", "mapType") ~= 3 then return false end
  local m = Idx.num(rec, "ZN", "mapID")
  if not m then return false end
  local z = Idx.num(rec, "ZN", "zone")
  return z == nil or z == m
end

local function inCombat()
  if type(InCombatLockdown) ~= "function" then return false end
  local ok, v = pcall(InCombatLockdown)
  return ok and not isSecret(v) and v == true
end

-- first record index with r.t >= t (lists are sorted by time); #list + 1 if none
local function firstAtOrAfter(list, t)
  local lo, hi = 1, #list + 1
  while lo < hi do
    local mid = floor((lo + hi) / 2)
    if list[mid].t < t then lo = mid + 1 else hi = mid end
  end
  return lo
end

-- fn(record) for every record with t0 <= r.t < t1
local function each(list, t0, t1, fn)
  for i = firstAtOrAfter(list, t0), #list do
    local r = list[i]
    if r.t >= t1 then break end
    fn(r)
  end
end

-- level the recording began with: the first LV line minus one, or the level of the first PL line (login); nil = unknown
local function startLevel(index)
  local Idx = I()
  local best
  local lv = Idx.list(index, "LV")[1]
  local a = lv and levelOf(lv, "LV")
  if a then best = a - 1 end
  local pl = Idx.list(index, "PL")[1]
  local b = pl and levelOf(pl, "PL")
  if b and (not best or b < best) then best = b end
  if best and best < 1 then best = 1 end
  return best
end

-- current level as the Chronik reads it without live data: last LV line, else last PL line, else 1
local function reachedLevel(index)
  local Idx = I()
  local lv = Idx.list(index, "LV")
  local v = lv[#lv] and levelOf(lv[#lv], "LV")
  if v then return v end
  local pl = Idx.list(index, "PL")
  v = pl[#pl] and levelOf(pl[#pl], "PL")
  return v or 1
end

-- time of reaching level L; a level skipped in the log (several levels at once) counts with the next level found
local function levelTime(st, L)
  for l = L, max(L, st.top or L) do
    if finite(st.at[l]) then return st.at[l], l end
  end
  return nil
end

local function truncated(index)
  local tr = type(index.truncated) == "table" and index.truncated or {}
  for _, code in ipairs(Meilensteine.TRUNC_CODES) do
    if tr[code] then return true end
  end
  return false
end

-- active time of the levels lo .. hi - 1 (completed) plus, for a running section, the level in progress until t1. Away time
-- (AF lines) is taken out per level as in the forecast: a level keeps Chronik.AFK_FLOOR of its time.
local function activeTime(index, st, lo, hi, runningLevel, t1)
  local C = Journal.Chronik
  local floorShare = C and C.AFK_FLOOR or 0.2
  local sum, approx, known = 0, false, false
  for L = lo, hi - 1 do
    local d = st.dur[L]
    if finite(d) and d >= 0 then
      sum = sum + max(d * floorShare, d - (st.afk[L] or 0))
      known = true
      if st.approx[L] then approx = true end
    else
      approx = true
    end
  end
  if runningLevel then
    local t = st.at[runningLevel]
    if not finite(t) and runningLevel == 1 then t = index.startT end
    if finite(t) and finite(t1) and t1 > t then
      local d = (I().activeSeconds(index, t, t1))
      if finite(d) and d > 0 then
        sum = sum + max(d * floorShare, d - (st.afk[runningLevel] or 0))
        known = true
        approx = true
      end
    end
  end
  if not known then return nil, approx end
  return sum, approx
end

local function lootQuality(index, r, items)
  local q = I().num(r, "LT", "quality")
  if finite(q) then return floor(q) end
  local key = I().str(r, "LT", "item")
  local id = key and tonumber(match(key, "^(%d+)"))
  local it = id and items and items[id]
  q = type(it) == "table" and tonumber(it.quality) or nil
  return finite(q) and floor(q) or nil
end

-- item level of a find (client lookup by link, best effort; never in combat)
local function itemLevel(link)
  local F = Journal.Funde
  if not (F and type(F.itemLevel) == "function") or not link then return nil end
  local ok, v = pcall(F.itemLevel, { link = link })
  return ok and finite(v) and v or nil
end

-- best find of a window: highest quality (from green, bought/handed over left out); on a tie the higher item level (only for the
-- last BEST_CANDIDATES of the top quality, when the client knows them), otherwise the later find
local function bestFind(index, t0, t1, ctx)
  local Idx = I()
  local items = snapGroup(index, "items")
  local top, cands = nil, {}
  each(Idx.list(index, "LT"), t0, t1, function(r)
    local src = Idx.str(r, "LT", "source")
    if src and Meilensteine.NOT_FOUND[src] then return end
    local key = Idx.str(r, "LT", "item")
    if not key or not match(key, "^%d+") then return end
    local q = lootQuality(index, r, items)
    if not q or q < 2 then return end
    if not top or q > top then
      top, cands = q, {}
    elseif q < top then
      return
    end
    cands[#cands + 1] = { r = r, key = key }
    if #cands > Meilensteine.BEST_CANDIDATES then table.remove(cands, 1) end
  end)
  if not top then return nil end
  local Tx = Journal.Texts
  local pick, pickIlvl = cands[#cands], nil
  if #cands > 1 and not ctx.combat then
    for i = #cands, 1, -1 do
      local c = cands[i]
      local lvl = itemLevel(Tx and Tx.itemString(c.key) or nil)
      if lvl and (not pickIlvl or lvl > pickIlvl) then pick, pickIlvl = c, lvl end
    end
  end
  local id = tonumber(match(pick.key, "^(%d+)"))
  local it = items and items[id]
  local link = Tx and Tx.itemString(pick.key) or nil
  if not pickIlvl and not ctx.combat then pickIlvl = itemLevel(link) end
  return { itemID = id, key = pick.key, quality = top, name = type(it) == "table" and rawName(it.name) or nil, ilvl = pickIlvl,
    link = link, t = pick.r.t }
end

-- counts of a window [t0, t1): new zones (first arrival, map type 3), quests turned in, dungeon runs started, kills
local function windowCounts(index, sec, t0, t1, runs)
  local Idx = I()
  local zones, names, all, seen = 0, {}, {}, {}
  each(Idx.list(index, "ZN"), t0, t1, function(r)
    if not Meilensteine.isNewZone(r) then return end
    local m = Idx.num(r, "ZN", "mapID")
    if seen[m] then return end
    seen[m] = true
    zones = zones + 1
    if #all < Meilensteine.ZONE_NAMES_ALL then
      local nm = mapName(index, Idx.num(r, "ZN", "mapID"))
      if nm then
        all[#all + 1] = nm
        if #names < Meilensteine.ZONE_NAMES then names[#names + 1] = nm end
      end
    end
  end)
  sec.zonesNew, sec.zoneNames, sec.zoneNamesAll = zones, names, all
  local q = 0
  each(Idx.list(index, "QT"), t0, t1, function() q = q + 1 end)
  sec.quests = q
  local n, bosses = 0, 0
  for _, run in ipairs(runs) do
    if finite(run.t0) and run.t0 >= t0 and run.t0 < t1 then
      n = n + 1
      bosses = bosses + (tonumber(run.bossesDefeated) or 0)
    end
  end
  sec.dungeons = { runs = n, bosses = bosses }
  sec.kills, sec.killsExact = Idx.killsBetween(index, t0, t1)
end

local function deathsIn(st, lo, hi)
  local n = 0
  for L = lo, hi do n = n + (st.deaths[L] or 0) end
  return n
end

local function isEmpty(sec)
  return sec.seconds == nil and (sec.kills or 0) == 0 and (sec.quests or 0) == 0 and (sec.deaths or 0) == 0
    and (sec.zonesNew or 0) == 0 and sec.best == nil and (sec.dungeons and sec.dungeons.runs or 0) == 0
end

local function buildSection(index, st, ctx, n)
  local step = Meilensteine.STEP
  local lo = n - step
  local sec = { n = n, from = max(1, lo), to = n, key = n }
  local reached, start = ctx.reached, ctx.start
  if reached >= n then
    sec.state = "done"
  elseif reached >= lo then
    sec.state = "running"
  else
    sec.state = "open"
    return sec
  end
  if start >= n then
    sec.nodata = true -- reached before the recording began: nothing is invented
    return sec
  end
  -- partial: the recording began inside the section, or exactly on its mark without the mark's LV line (the time from reaching
  -- the mark until the recording began is missing: said, not hidden)
  sec.partial = start > sec.from or (lo > 1 and start == lo and not finite(st.at[lo]))
  if sec.partial then sec.since = start end
  local t0
  if lo <= 1 or sec.partial then
    t0 = index.startT
  else
    t0 = levelTime(st, lo) or index.startT
  end
  local t1
  if sec.state == "done" then
    local at, L = levelTime(st, n)
    t1 = at or index.lastT
    sec.at = at
    -- the place of the milestone: sub zone of its LV line, else the map's name
    if at and L then
      for _, r in ipairs(I().list(index, "LV")) do
        if r.t == at and levelOf(r, "LV") == L then
          sec.placeEnd = rawName(I().str(r, "LV", "sub")) or mapName(index, I().num(r, "LV", "mapID"))
          break
        end
      end
    end
  else
    t1 = index.lastT
  end
  if not finite(t0) then t0 = t1 end
  if not finite(t1) or t1 < t0 then t1 = t0 end
  sec.t0, sec.t1 = t0, t1
  local hiLevel = sec.state == "done" and n or reached
  sec.seconds, sec.secondsApprox = activeTime(index, st, max(sec.from, start), hiLevel, sec.state == "running" and reached or nil, t1)
  sec.deaths = deathsIn(st, sec.from, hiLevel - (sec.state == "done" and 1 or 0))
  -- a running section counts up to its last line (inclusive)
  local wEnd = sec.state == "done" and t1 or t1 + 1
  windowCounts(index, sec, t0, wEnd, ctx.runs)
  sec.best = bestFind(index, t0, wEnd, ctx)
  sec.truncated = ctx.truncated
  sec.empty = isEmpty(sec)
  return sec
end

local function buildFinal(index, st, ctx, sections)
  local top = ctx.maxLevel
  local fin = { n = top, from = 1, to = top, key = "final", final = true }
  fin.state = ctx.reached >= top and "done" or "running"
  fin.partial = ctx.start > 1
  if fin.partial then fin.since = ctx.start end
  local t0 = index.startT
  local t1
  if fin.state == "done" then t1 = levelTime(st, top) or index.lastT else t1 = index.lastT end
  if not finite(t0) then t0 = t1 end
  if not finite(t1) or t1 < t0 then t1 = t0 end
  fin.t0, fin.t1, fin.at = t0, t1, fin.state == "done" and t1 or nil
  local sum, approx, known = 0, false, false
  fin.cols = {}
  for _, s in ipairs(sections) do
    fin.cols[#fin.cols + 1] = { n = s.n, seconds = s.seconds, state = s.state, nodata = s.nodata }
    if s.seconds then
      sum, known = sum + s.seconds, true
      if s.secondsApprox then approx = true end
    elseif s.state ~= "open" then
      approx = true
    end
  end
  fin.seconds, fin.secondsApprox = known and sum or nil, approx
  fin.deaths = st.deathsTotal or 0
  local wEnd = fin.state == "done" and t1 or t1 + 1
  windowCounts(index, fin, t0, wEnd, ctx.runs)
  fin.best = bestFind(index, t0, wEnd, ctx)
  fin.truncated = ctx.truncated
  -- play days (calendar days with play time) and the journey medals
  fin.days = 0
  local Days = Journal.Days
  if Days and type(Days.list) == "function" then
    local ok, list = pcall(Days.list, index)
    if ok and type(list) == "table" then fin.days = #list end
  end
  local C = Journal.Chronik
  if C and type(C.sealsOf) == "function" then
    local ok, seals = pcall(C.sealsOf, index)
    if ok and type(seals) == "table" then fin.seals = { broken = seals.broken or 0, total = seals.total or 0 } end
  end
  fin.empty = isEmpty(fin)
  return fin
end

local cache = setmetatable({}, { __mode = "k" })

function Meilensteine.build(index)
  if type(index) ~= "table" then return nil end
  local hit = cache[index]
  if hit then return hit end
  local C = Journal.Chronik
  if not (C and I()) then return nil end
  local st = C.static(index)
  local maxLevel = C.maxLevel()
  local reached = reachedLevel(index)
  local start = startLevel(index) or reached
  if start > reached then start = reached end
  local runs = {}
  local D = Journal.Dungeons
  if D and type(D.build) == "function" then
    local ok, res = pcall(D.build, index)
    if ok and type(res) == "table" and type(res.runs) == "table" then runs = res.runs end
  end
  local ctx = { reached = reached, start = start, maxLevel = maxLevel, runs = runs, truncated = truncated(index), combat = inCombat() }
  local res = { sections = {}, reached = reached, start = start, maxLevel = maxLevel, step = Meilensteine.STEP }
  for n = Meilensteine.STEP, maxLevel, Meilensteine.STEP do
    local sec = buildSection(index, st, ctx, n)
    res.sections[#res.sections + 1] = sec
    if sec.state == "done" then res.latest = n end
  end
  res.final = buildFinal(index, st, ctx, res.sections)
  -- item levels are only looked up out of combat: a result built in combat is not kept
  if not ctx.combat then cache[index] = res end
  return res
end

function Meilensteine.find(res, key)
  if type(res) ~= "table" then return nil end
  if key == "final" then return res.final end
  for _, s in ipairs(res.sections) do
    if s.n == key then return s end
  end
  return nil
end

-- tests: forget the cached results
function Meilensteine.clear()
  for k in pairs(cache) do cache[k] = nil end
end
