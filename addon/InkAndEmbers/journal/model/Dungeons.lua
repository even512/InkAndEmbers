-- Dungeon runs ("Dungeons" page of the Chronik): folds the instance visits (IE/IL, index.lists) into runs and collects what
-- happened in them. Pure read logic on the index and the log, nothing is stored (no new SV fields, no new collector, works
-- backwards). Names are raw SV text (Sanitize.field); display only via Sanitize.display.
--
--   Dungeons.build(index)            -> { runs = { run, ... newest first }, count, truncated }   (cached per index)
--   Dungeons.detail(index, run)      -> run.detail = { deaths, loot, quests, xp }                (lazy, cached on the run)
--                                       loot: own finds (LT) and group finds (LG) by time, { t, key, itemID, quality, count, name,
--                                       source, who (nil = you), class, roll }
--   Dungeons.group(index, run)       -> { { name, class, race, level, seconds }, ... }           (lazy, cached on the run)
--                                       only people present at a successful boss fight (IB success = 1); none without a boss win
--   Dungeons.completion(run)         -> { total, defeated, complete } | nil   only when the game itself names the bosses
--
-- Run: key, instanceID, name, kind, difficultyID, t0, t1 (first entry .. last leave), intervals { a1, b1, a2, b2, ... } (the
-- time really spent inside), seconds (sum of the visits), visits, live (still inside), endKnown, level0, level1, groupSize,
-- kills, bosses { { id, name, defeated, attempts, wipes, seconds, t } }, bossesDefeated, bossesFromCount, deathsCount.
-- A run is the chain of visits to the same instance and difficulty whose pauses are at most Dungeons.GAP seconds (ghost run,
-- disconnect, short trip to the vendor).
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Dungeons = {}
Journal.Dungeons = Dungeons

local floor, huge, min, max = math.floor, math.huge, math.min, math.max
local match, gmatch, format = string.match, string.gmatch, string.format

Dungeons.GAP = 1800          -- seconds: a shorter pause between two visits of the same instance keeps one run
Dungeons.RUNS_MAX = 600      -- runs kept (the newest)
Dungeons.LOOT_MAX = 120      -- finds per run
Dungeons.QUEST_MAX = 60      -- quests per run
Dungeons.DEATH_MAX = 60      -- deaths per run
Dungeons.XP_BLOCKS_MAX = 600 -- log blocks read for the experience of one run
Dungeons.NAME_MAX = 48
Dungeons.DC_WINDOW = 5       -- seconds: the cause line (DC) belongs to the death (DE) when it follows this closely
Dungeons.source = nil        -- tests: table with EJ_* functions instead of the client's

-- locale scope "m.Dungeons" (English in locales/enUS_model.lua), read late
local TEXT = ns.Locale.ns("m.Dungeons", {
  diff_1 = "Normal", diff_2 = "Heroisch", diff_3 = "10 Spieler", diff_4 = "25 Spieler", diff_5 = "10 Spieler (heroisch)",
  diff_6 = "25 Spieler (heroisch)", diff_8 = "Mythischer Schlüsselstein", diff_14 = "Normal", diff_15 = "Heroisch",
  diff_16 = "Mythisch", diff_17 = "Raidfinder", diff_23 = "Mythisch", diff_24 = "Zeitwanderung",
})
Dungeons.TEXT = TEXT

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function finite(v)
  return type(v) == "number" and v == v and v ~= huge and v ~= -huge
end

-- difficulty name: our own table first (German/English by the chosen language), else the client's name when its language
-- matches; nil if unknown
function Dungeons.difficultyName(id)
  id = tonumber(id)
  if not finite(id) then return nil end
  id = floor(id)
  local own = TEXT["diff_" .. id]
  if type(own) == "string" and own ~= "diff_" .. id then return own end
  local L = ns.Locale
  if L and L.matchesClient and L.matchesClient() and type(GetDifficultyInfo) == "function" then
    local ok, name = pcall(GetDifficultyInfo, id)
    if ok and type(name) == "string" and not isSecret(name) and name ~= "" then
      local S = ns.Sanitize
      return S and S.field(name) or nil
    end
  end
  return nil
end

local function charTable(index, name)
  local c = index.char
  local t = type(c) == "table" and c[name]
  return type(t) == "table" and t or nil
end

local function snapEntry(index, group, id)
  local snaps = charTable(index, "snapshots")
  local g = snaps and snaps[group]
  if type(g) ~= "table" or id == nil then return nil end
  local e = g[id]
  if e == nil then e = g[format("%.0f", id)] end
  return type(e) == "table" and e or nil
end

local function cleanName(v)
  if type(v) ~= "string" or isSecret(v) or v == "" then return nil end
  v = ns.Sanitize.field(v)
  return v ~= "" and v or nil
end

local function snapName(index, group, id)
  local e = snapEntry(index, group, id)
  return e and cleanName(e.name) or nil
end

local function npcName(index, id)
  local npcs = charTable(index, "npcs")
  if not (npcs and id) then return nil end
  local e = npcs[id]
  if e == nil then e = npcs[format("%.0f", id)] end
  if type(e) == "table" then e = e.name end
  return cleanName(e)
end

-- last record index with r.t <= t (0 if none); lists are sorted by time
local function lastAtOrBefore(list, t)
  local lo, hi = 1, #list
  if hi == 0 or list[1].t > t then return 0 end
  while lo < hi do
    local mid = floor((lo + hi + 1) / 2)
    if list[mid].t <= t then lo = mid else hi = mid - 1 end
  end
  return lo
end

-- first record index with r.t >= t
local function firstAtOrAfter(list, t)
  local lo, hi = 1, #list + 1
  while lo < hi do
    local mid = floor((lo + hi) / 2)
    if list[mid].t < t then lo = mid + 1 else hi = mid end
  end
  return lo
end

-- every record of the list inside one of the run's visit intervals (in time order); fn(record, listIndex)
local function eachIn(list, intervals, fn)
  if type(list) ~= "table" then return end
  for k = 1, #intervals, 2 do
    local a, b = intervals[k], intervals[k + 1]
    local i = firstAtOrAfter(list, a)
    while list[i] and list[i].t <= b do
      fn(list[i], i)
      i = i + 1
    end
  end
end

-- end of the session span that contains t (open session: now); nil if t is in none
local function sessionEnd(index, t, now)
  local sp = index.sessions
  if type(sp) ~= "table" or type(sp.t0) ~= "table" then return nil end
  local lo, hi, found = 1, #sp.t0, 0
  while lo <= hi do
    local mid = floor((lo + hi) / 2)
    if sp.t0[mid] <= t then found, lo = mid, mid + 1 else hi = mid - 1 end
  end
  if found == 0 then return nil end
  local e = sp.t1[found]
  if e == huge then return now, true end
  if e < t then return nil end
  return e, false
end

-- visits from IE/IL. IE opens, IL closes; a resumed IE (reload/login inside) continues the open visit; a new IE while one is
-- open means the earlier one never got its IL (crash): it ends with the session
local function visitsOf(index, now)
  local Idx = Journal.Index
  local ie, il = Idx.list(index, "IE"), Idx.list(index, "IL")
  local out, cur = {}, nil
  local function finish(v, t1, seconds)
    if t1 == nil then
      local e, live = sessionEnd(index, v.t0, now)
      t1 = max(v.t0, e or v.t0)
      v.endKnown, v.live = false, live == true
    else
      v.endKnown = true
    end
    v.t1 = max(t1, v.t0)
    if finite(seconds) and seconds >= 0 and seconds <= (v.t1 - v.t0) + 3600 then v.seconds = floor(seconds) else v.seconds = floor(v.t1 - v.t0) end
    out[#out + 1] = v
  end
  local i, j = 1, 1
  while i <= #ie or j <= #il do
    local takeIE
    if i > #ie then takeIE = false elseif j > #il then takeIE = true else takeIE = (ie[i].ln or 0) <= (il[j].ln or 0) end
    if takeIE then
      local r = ie[i]
      i = i + 1
      local id = Idx.num(r, "IE", "instanceID")
      if id and finite(r.t) then
        id = floor(id)
        local level = Idx.num(r, "IE", "level")
        local resumed = Idx.str(r, "IE", "resumed") == "1"
        if cur and resumed and cur.id == id then
          cur.level1 = level or cur.level1
          cur.group = max(cur.group or 0, Idx.num(r, "IE", "group") or 0)
        else
          if cur then finish(cur, nil) end
          cur = { id = id, kind = Idx.str(r, "IE", "type"), diff = Idx.num(r, "IE", "difficultyID"), t0 = r.t,
            level0 = level, level1 = level, group = Idx.num(r, "IE", "group") or 0 }
        end
      end
    else
      local r = il[j]
      j = j + 1
      local id = Idx.num(r, "IL", "instanceID")
      if cur and (id == nil or floor(id) == cur.id) then
        local v = cur
        cur = nil
        v.kills = Idx.num(r, "IL", "kills")
        v.deaths = Idx.num(r, "IL", "deaths")
        v.bossCount = Idx.num(r, "IL", "bosses")
        v.loot = Idx.num(r, "IL", "loot")
        -- no duration = IL written at a later login for a visit open at logout/crash: r.t is the login, not the end
        -- (would count offline hours): unknown end, the visit ends with its session
        local secs = Idx.num(r, "IL", "seconds")
        if finite(r.t) and secs ~= nil then finish(v, r.t, secs) else finish(v, nil) end
      end
    end
  end
  if cur then finish(cur, nil) end
  table.sort(out, function(a, b) return a.t0 < b.t0 end)
  return out
end

-- bosses of a run from the IB lines inside its visits
local function bossesOf(index, run)
  local Idx = Journal.Index
  local order, by, anon = {}, {}, 0
  eachIn(Idx.list(index, "IB"), run.intervals, function(r)
    local inst = Idx.num(r, "IB", "instanceID")
    if inst and floor(inst) ~= run.instanceID then return end
    local id = Idx.num(r, "IB", "encounterID")
    local key
    if id then
      id = floor(id)
      key = id
    else
      anon = anon + 1
      key = "?" .. anon
    end
    local b = by[key]
    if not b then
      b = { id = id, name = id and snapName(index, "encounters", id) or nil, attempts = 0, wipes = 0, defeated = false, t = r.t }
      by[key] = b
      order[#order + 1] = b
    end
    local ok = Idx.str(r, "IB", "success")
    local secs = Idx.num(r, "IB", "seconds")
    b.attempts = b.attempts + 1
    if ok == "1" then
      if not b.defeated then b.defeated, b.t = true, r.t end
      b.seconds = secs or b.seconds
    elseif ok == "0" then
      b.wipes = b.wipes + 1
      if not b.defeated then b.seconds = secs or b.seconds end
    end
  end)
  return order
end

local function deathsIn(index, run)
  local Idx = Journal.Index
  local n = 0
  eachIn(Idx.list(index, "DE"), run.intervals, function() n = n + 1 end)
  return n
end

local cache = setmetatable({}, { __mode = "k" })

function Dungeons.build(index, opts)
  local empty = { runs = {}, count = 0, truncated = false }
  if type(index) ~= "table" or type(index.char) ~= "table" or not Journal.Index then return empty end
  local hit = cache[index]
  if hit then return hit end
  local now = (opts and finite(opts.now)) and opts.now or time()
  local visits = visitsOf(index, now)
  local runs = {}
  for _, v in ipairs(visits) do
    local run = runs[#runs]
    if run and run.instanceID == v.id and run.difficultyID == v.diff and v.t0 - run.t1 <= Dungeons.GAP and v.t0 >= run.t0 then
      run.t1 = max(run.t1, v.t1)
      run.seconds = run.seconds + v.seconds
      run.visits = run.visits + 1
      run.intervals[#run.intervals + 1], run.intervals[#run.intervals + 2] = v.t0, v.t1
      run.endKnown = run.endKnown and v.endKnown
      run.live = v.live
      run.level1 = v.level1 or run.level1
      run.groupSize = max(run.groupSize or 0, v.group or 0)
      run.kills = (run.kills or 0) + (v.kills or 0)
      run.bossCount = (run.bossCount or 0) + (v.bossCount or 0)
    else
      runs[#runs + 1] = {
        key = format("%.0f:%d", v.t0, v.id), instanceID = v.id, name = snapName(index, "instances", v.id), kind = v.kind,
        difficultyID = v.diff, t0 = v.t0, t1 = v.t1, intervals = { v.t0, v.t1 }, seconds = v.seconds, visits = 1,
        endKnown = v.endKnown, live = v.live, level0 = v.level0, level1 = v.level1, groupSize = v.group or 0,
        kills = v.kills or 0, bossCount = v.bossCount or 0,
      }
    end
  end
  local truncated = #runs > Dungeons.RUNS_MAX
  local first = truncated and (#runs - Dungeons.RUNS_MAX + 1) or 1
  local out = {}
  for i = #runs, first, -1 do
    local run = runs[i]
    run.bosses = bossesOf(index, run)
    local defeated = 0
    for _, b in ipairs(run.bosses) do if b.defeated then defeated = defeated + 1 end end
    -- no boss lines (the client did not fire the events): the count the collector kept per visit
    run.bossesFromCount = #run.bosses == 0 and (run.bossCount or 0) > 0
    run.bossesDefeated = run.bossesFromCount and run.bossCount or defeated
    run.deathsCount = deathsIn(index, run)
    out[#out + 1] = run
  end
  local res = { runs = out, count = #out, truncated = truncated }
  cache[index] = res
  return res
end

-- level at the end: the highest of the last entry and the level-ups inside the run
local function endLevel(index, run)
  local Idx = Journal.Index
  local lv = run.level1
  eachIn(Idx.list(index, "LV"), { run.t0, run.t1 }, function(r)
    local l = Idx.num(r, "LV", "level")
    if l and (not lv or l > lv) then lv = l end
  end)
  return lv
end

-- cause of a death: the nearest DC line after the DE line (same moment, before the next DE)
local function causeOf(index, de, nextDeLn)
  local Idx = Journal.Index
  local dc = Idx.list(index, "DC")
  local lo, hi = 1, #dc + 1
  local ln = de.ln or 0
  while lo < hi do
    local mid = floor((lo + hi) / 2)
    if (dc[mid].ln or 0) <= ln then lo = mid + 1 else hi = mid end
  end
  local r = dc[lo]
  if not r or (r.t - de.t) > Dungeons.DC_WINDOW or (nextDeLn and (r.ln or 0) > nextDeLn) then return nil end
  local npcID = Idx.num(r, "DC", "npcID")
  return { cause = Idx.str(r, "DC", "cause"), guess = Idx.str(r, "DC", "guess") == "1",
    foe = npcID and npcName(index, floor(npcID)) or cleanName(Idx.str(r, "DC", "source")) }
end

-- experience inside the run, read from the log blocks that overlap it (only this run, only when asked for)
local function blockStart(block)
  return type(block) == "string" and tonumber(match(block, "^#~(%-?%d+)~")) or nil
end

local function xpOf(index, run)
  local char = index.char
  local log = type(char.log) == "table" and char.log or {}
  local lo, hi, from = 1, #log, 1
  while lo <= hi do -- last block that starts at or before t0
    local mid = floor((lo + hi) / 2)
    local s = blockStart(log[mid])
    if s and s <= run.t0 then from, lo = mid, mid + 1 else hi = mid - 1 end
  end
  local total, seen = 0, false
  local function inside(t)
    for k = 1, #run.intervals, 2 do
      if t >= run.intervals[k] and t <= run.intervals[k + 1] then return true end
    end
    return false
  end
  local function scanLine(t, rest)
    if not inside(t) then return end
    local amount, via = match(rest, "^[^~]*~([^~]*)~[^~]*~[^~]*~[^~]*~[^~]*~[^~]*~[^~]*~([^~]*)")
    if via == "unclear" then return end
    amount = tonumber(amount) or (match(rest, "^[^~]*~([^~]*)") and tonumber(match(rest, "^[^~]*~([^~]*)")))
    if finite(amount) and amount > 0 then
      total, seen = total + amount, true
    end
  end
  local blocks = 0
  for i = from, #log do
    local s = blockStart(log[i])
    if s and s > run.t1 then break end
    blocks = blocks + 1
    if blocks > Dungeons.XP_BLOCKS_MAX then break end
    if s then
      for dt, rest in gmatch(log[i], "\n(%-?%d+)~XP~([^\n]*)") do scanLine(s + tonumber(dt), rest) end
    end
  end
  local Store = ns.Store
  local ob = Store and Store.current == char and Store.block
  if type(ob) == "table" and finite(tonumber(ob.start)) and type(ob.lines) == "table" and tonumber(ob.start) <= run.t1 then
    for _, l in ipairs(ob.lines) do
      local dt, rest = match(l, "^(%-?%d+)~XP~(.*)$")
      if dt then scanLine(tonumber(ob.start) + tonumber(dt), rest) end
    end
  end
  return seen and floor(total) or nil
end

-- deaths, finds, quests and experience of a run (computed once per run)
function Dungeons.detail(index, run)
  if type(run) ~= "table" or type(index) ~= "table" then return { deaths = {}, loot = {}, quests = {} } end
  if run.detail then return run.detail end
  local Idx = Journal.Index
  local d = { deaths = {}, loot = {}, quests = {}, lootMore = 0, questMore = 0, deathMore = 0 }
  run.detail = d
  d.level1 = endLevel(index, run)

  local de = Idx.list(index, "DE")
  eachIn(de, run.intervals, function(r, i)
    if #d.deaths >= Dungeons.DEATH_MAX then
      d.deathMore = d.deathMore + 1
      return
    end
    local nextLn = de[i + 1] and de[i + 1].ln or nil
    local c = causeOf(index, r, nextLn) or {}
    d.deaths[#d.deaths + 1] = { t = r.t, cause = c.cause, guess = c.guess, foe = c.foe, sub = cleanName(Idx.str(r, "DE", "sub")) }
  end)

  -- finds from green up: our own (LT) and the group's (LG, since 1.0.8; older runs have none), mixed by time.
  -- who = nil means "you"; class and roll only on group finds.
  local items = charTable(index, "snapshots")
  items = items and items.items
  local found = {}
  local function collect(code, mine)
    eachIn(Idx.list(index, code), run.intervals, function(r)
      local key = Idx.str(r, code, "item")
      local itemID = key and tonumber(match(key, "^(%d+)"))
      if not itemID then return end
      local who = not mine and cleanName(Idx.str(r, code, "who")) or nil
      if not mine and not who then return end -- a group find without a readable recipient cannot be attributed
      local snap = type(items) == "table" and (items[itemID] or items[format("%.0f", itemID)]) or nil
      local q = Idx.num(r, code, "quality")
      if q == nil and type(snap) == "table" and finite(snap.quality) then q = snap.quality end
      if q and q < 2 then return end -- only green and better
      local n = Idx.num(r, code, "count")
      found[#found + 1] = { t = r.t, seq = #found + 1, key = key, itemID = floor(itemID), quality = q and floor(q) or nil,
        count = (n and n > 1 and n < 100000) and floor(n) or 1, name = type(snap) == "table" and cleanName(snap.name) or nil,
        source = mine and Idx.str(r, code, "source") or nil, who = who, class = not mine and Idx.str(r, code, "class") or nil,
        roll = not mine and Idx.str(r, code, "roll") or nil }
    end)
  end
  collect("LT", true)
  collect("LG", false)
  table.sort(found, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.seq < b.seq end)
  local classOf -- class of a recipient from the companion records when the find line has none (lazy)
  for _, e in ipairs(found) do
    if #d.loot >= Dungeons.LOOT_MAX then
      d.lootMore = d.lootMore + 1
    else
      if e.who and not e.class then
        if classOf == nil then
          classOf = {}
          local C = Journal.Companions
          local res = C and C.aggregate(index)
          for _, p in ipairs(res and res.list or {}) do
            local base = match(p.name, "^([^%-]+)") or p.name
            if p.class and classOf[base] == nil then classOf[base] = p.class end
          end
        end
        e.class = classOf[match(e.who, "^([^%-]+)") or e.who]
      end
      d.loot[#d.loot + 1] = e
    end
  end

  local quests = charTable(index, "quests")
  local byId, order = {}, {}
  local function quest(r, code)
    local id = Idx.num(r, code, "questID")
    if not id then return nil end
    id = floor(id)
    local q = byId[id]
    if not q then
      if #order >= Dungeons.QUEST_MAX then
        d.questMore = d.questMore + 1
        return nil
      end
      local e = quests and (quests[id] or quests[format("%.0f", id)])
      q = { id = id, t = r.t, title = type(e) == "table" and cleanName(e.title) or nil }
      byId[id] = q
      order[#order + 1] = q
    end
    return q
  end
  eachIn(Idx.list(index, "QA"), run.intervals, function(r)
    local q = quest(r, "QA")
    if q then q.accepted = true end
  end)
  eachIn(Idx.list(index, "QT"), run.intervals, function(r)
    local q = quest(r, "QT")
    if q then
      q.done, q.t = true, r.t
      q.xp, q.money = Idx.num(r, "QT", "xp"), Idx.num(r, "QT", "money")
    end
  end)
  table.sort(order, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.id < b.id end)
  d.quests = order

  d.xp = xpOf(index, run)
  return d
end

-- time windows { a1, b1, a2, b2, ... } of the successful boss fights of a run (IB success = 1): [t - seconds, t], a point (t, t)
-- when the duration is unknown. Failed attempts do not count.
local function bossWinWindows(index, run)
  local Idx = Journal.Index
  local out, n = {}, 0
  eachIn(Idx.list(index, "IB"), run.intervals, function(r)
    local inst = Idx.num(r, "IB", "instanceID")
    if inst and floor(inst) ~= run.instanceID then return end
    if Idx.str(r, "IB", "success") ~= "1" then return end
    local secs = Idx.num(r, "IB", "seconds")
    out[n + 1] = (secs and secs > 0 and secs < 86400) and (r.t - secs) or r.t
    out[n + 2] = r.t
    n = n + 2
  end)
  return out
end

-- true if one of the person's intervals { a1, b1, ... } touches one of the windows (ends included)
local function touches(ivs, windows)
  for k = 1, #ivs, 2 do
    for w = 1, #windows, 2 do
      if ivs[k] <= windows[w + 1] and ivs[k + 1] >= windows[w] then return true end
    end
  end
  return false
end

-- group of the run: the people (WB/WV intervals) who were there for at least one successful boss fight, most time in the run
-- first. Short guests without a boss win, and runs without any boss win, have no group. The level is only given when it was seen
-- around the run (the person's level at first or last sight), never guessed.
function Dungeons.group(index, run)
  if type(run) ~= "table" or type(index) ~= "table" then return {} end
  if run.group then return run.group end
  local C = Journal.Companions
  local out = {}
  run.group = out
  if not C then return out end
  local windows = bossWinWindows(index, run)
  if #windows == 0 then return out end
  local list = C.between(index, run.t0, run.t1)
  local res = C.aggregate(index)
  local people = {}
  for _, p in ipairs(res and res.list or {}) do people[p.name] = p end
  local slack = 600
  for _, m in ipairs(list) do
    local p = people[m.name]
    if p and touches(p.intervals, windows) then
      local level
      if p.firstT >= run.t0 - slack and p.firstT <= run.t1 + slack then
        level = p.level0
      elseif p.lastT >= run.t0 - slack and p.lastT <= run.t1 + slack then
        level = p.level1
      end
      out[#out + 1] = { name = m.name, class = m.class, race = m.race, level = level, seconds = m.seconds }
    end
  end
  return out
end

-- completion: only when the game names the bosses of the instance (Encounter Journal), validated against the instance ID.
-- Without a certain source nil comes back and the page does not mark anything.
local ejCache = {}

local function ejFn(name)
  local src = Dungeons.source
  local f
  if type(src) == "table" then f = src[name] else f = _G[name] end
  return type(f) == "function" and f or nil
end

local function ejBosses(instanceID)
  local hit = ejCache[instanceID]
  if hit ~= nil then return hit or nil end
  local result = false
  local forMap, info, byIndex = ejFn("EJ_GetInstanceForMap"), ejFn("EJ_GetInstanceInfo"), ejFn("EJ_GetEncounterInfoByIndex")
  if forMap and info and byIndex then
    local ok, jid = pcall(forMap, instanceID)
    if ok and finite(jid) and jid > 0 then
      local ok2, _, _, _, _, _, _, _, _, _, mapID = pcall(info, jid)
      if ok2 and finite(mapID) and mapID == instanceID then
        local ids = {}
        for i = 1, 40 do
          local ok3, _, _, _, _, _, _, dungeonEncounterID = pcall(byIndex, i, jid)
          if not ok3 or dungeonEncounterID == nil then break end
          if finite(dungeonEncounterID) then ids[#ids + 1] = floor(dungeonEncounterID) end
        end
        if #ids > 0 then result = ids end
      end
    end
  end
  ejCache[instanceID] = result
  return result or nil
end

function Dungeons.completion(run)
  if type(run) ~= "table" or not run.instanceID then return nil end
  local ids = ejBosses(run.instanceID)
  if not ids then return nil end
  local got = {}
  for _, b in ipairs(run.bosses or {}) do
    if b.defeated and b.id then got[b.id] = true end
  end
  local n = 0
  for _, id in ipairs(ids) do if got[id] then n = n + 1 end end
  return { total = #ids, defeated = n, complete = n == #ids }
end

function Dungeons.clear()
  cache = setmetatable({}, { __mode = "k" })
  ejCache = {}
end
