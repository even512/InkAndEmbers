-- Shared index of the journal pages: one pass over the character's block log (closed blocks plus the open block in the
-- Store). Rare events are kept as records, frequent ones (KI, XP, GD, AH) only as sums.
-- Index.get(opts) -> index | nil, reason ("keine-daten", "kein-charakter", "baut", "fehler"). Incremental; with an
-- older state of the same character the old index returns at once (stale = true) while the rebuild runs as a coroutine.
-- index fields (read only):
--   guid, char, lines, blocks, firstT, lastT, startT, stale, timings, truncated[code] (a list or sum hit its cap),
--   counts[code] (lines per code)
--   lists[code]   records of Index.LISTS (rec.t = epoch, rec.ln = running line number, rec[i] = field i): KI only
--                 elite/rare/boss, KF only close wins (close = 1),
--                 LT quality >= 2 (unknown kept), GD only lines where the balance first reaches a step of
--                 Index.RICH_STEPS; LF = campfire rounds
--   kills         { total, stamp = { normal, elite, rare, boss, unknown }, npc[npcID] = { n, stamp, map[mapID] = n,
--                 group, [1] = min level, [2] = max level },
--                   npcCount, npcUnknown, map[mapID], day[key], group, withPos, heat[mapID][cell] (Index.HEAT_GRID^2,
--                   cell = gy * GRID + gx), heatMaps,
--                   pts[mapID] = { n, pos[], nl[], t[] } (ring buffer: pos = x * 10000 + y, nl = npcID * 128 + level),
--                   ptsN, fight[ln] = duration of the fight of the rare kill ln }
--   killSeries    { size, b = { minute buckets }, c = { cumulative kills } } for ALL kills; query via Index.killsBetween
--   xp            { total, n, rested, unclear, source[src] = { n, amount, rested }, level[level][src] = amount }; src =
--                 kill | quest | explore | other
--   money         { source[src] = { gain, loss, n }, level[level] = { gain, loss, out[src] }, first / last / peak = {
--                 t, balance } }
--   skills[name] = { rank, max, t }     ah[action] = { n, deposit, price }     restT, restInnT, restFireT = rest times
--                                       (RA); restKinds = { inn, fire }
--   questObj[questID]  flat array, Index.QOBJ_STRIDE slots per objective from (idx-1)*STRIDE: have, need (0 = unknown),
--                      kind, text (false = none), n; read via Index.questGoals
-- WB/WV (companions) are deliberately not in the index (memory limit): ns.Journal.Companions reads them from the log.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Index = {}
Journal.Index = Index

local floor, huge, min = math.floor, math.huge, math.min
local unpack = unpack or table.unpack
local MAX_INT = 2 ^ 53 -- print with "%.0f", not "%d" (undefined or an error beyond 2^31 in the test VM / 2^63 in the client)
local match, gmatch, sub, find, format = string.match, string.gmatch, string.sub, string.find, string.format

Index.ASYNC = true            -- background build; false = always synchronous
Index.FRAME_BUDGET = 8        -- ms of compute time per frame during the background build (as Model.FRAME_BUDGET)
Index.CHECK_EVERY = 32        -- lines between two looks at the clock
Index.PREPARE_DELAY = 20      -- seconds after login until preparation (after the model, Model.PREPARE_DELAY = 15)
Index.COMBAT_RETRY = 2        -- seconds to wait while preparation is held up by combat
Index.LIST_MAX = 20000        -- records per list
Index.FIELD_CAP = 256         -- bytes per kept field
Index.NPC_MAX = 6000          -- distinct npcIDs in the sums
Index.MAP_MAX = 3000          -- distinct maps in the sums
Index.DAY_MAX = 4000          -- distinct days
Index.HEAT_MAPS = 400         -- maps with a heat grid
Index.HEAT_GRID = 32          -- grid per map (32 x 32)
Index.POINT_MAX = 400        -- exact kill points per map (ring buffer, newest kept)
Index.POINT_TOTAL = 12000     -- exact kill points over all maps (total memory budget)
Index.KEY_MAX = 32            -- distinct sources/actions per sum (rest -> "other")
Index.SESSION_MAX = 5000
Index.NPC_MAP_MAX = 16        -- distinct maps per NPC (kills.npc[id].map)
Index.NPC_MAP_TOTAL = 300000  -- map entries over all NPCs (total memory budget)
Index.KILL_BUCKET = 60        -- seconds per bucket of the kill series (index.killSeries)
Index.KILLT_MAX = 20000       -- occupied buckets of the kill series (~14 days of constant hunting; memory: 2 numbers per bucket)
Index.RICH_COPPER = 1000000   -- 100 gold in copper (silver step of the medal "Ein kleines Vermoegen")
-- balance steps in copper (ascending): the first GD line reaching one is kept as a record (time of the medal tier).
-- Must match the "fortune" steps in Chronik.MEDAL_STEPS (gold * 10000; a test keeps both equal).
Index.RICH_STEPS = { 100000, 1000000, 3000000 }
Index.SKILL_MAX = 40          -- distinct professions in index.skills
Index.FIGHT_SLACK = 3         -- seconds of slack when matching a rare kill to its fight (kills.fight)
Index.PENDING_MAX = 8         -- rare kills waiting for their KF entry at the same time
Index.QOBJ_MAX = 6000         -- quests with objective progress (index.questObj)
Index.QOBJ_IDX = 12           -- objectives per quest
Index.QOBJ_TEXT = 96          -- bytes per kept objective text
Index.QOBJ_STRIDE = 5         -- slots per objective in the flat array index.questObj[questID]
Index.REST_MAX = 5000         -- rest times in index.restT

-- rare events: every line becomes a record
Index.LISTS = {
  L = true, R = true, S = true, O = true, X = true, LV = true, PL = true, RS = true, DE = true, DR = true, DC = true,
  DB = true, QA = true, QT = true, QR = true, QX = true, BK = true, MO = true, SH = true, GW = true, ZN = true, SZ = true,
  EX = true, FP = true, HB = true, TF = true, TL = true, HS = true, IE = true, IL = true, IB = true, GU = true, DU = true,
  LF = true, -- VE is not here: H.VE keeps only the first line per to-do
}

local XP_SOURCES = { kill = true, quest = true, explore = true, other = true }
local STAMP = { normal = "normal", trivial = "normal", minus = "normal", elite = "elite", rare = "rare",
  rareelite = "rare", worldboss = "boss" }

-- millisecond clock: debugprofilestop in the client, os.clock in the test VM (as Model)
local function clock()
  if type(debugprofilestop) == "function" then return debugprofilestop() end
  if type(os) == "table" and type(os.clock) == "function" then return os.clock() * 1000 end
  return 0
end

-- background build: pause() yields once the frame budget is used up. Only effective inside the build coroutine; never
-- call inside pcall/sort.
local inJob, deadline = false, huge
local tick = 0
local function pause()
  if not inJob then return end
  tick = tick + 1
  if tick >= Index.CHECK_EVERY then
    tick = 0
    if clock() >= deadline then coroutine.yield() end
  end
end

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function finite(v)
  return type(v) == "number" and v == v and v ~= huge and v ~= -huge
end

local function bsearch(arr, v) -- largest index i with arr[i] <= v, 0 if none
  local lo, hi = 1, #arr
  if hi == 0 or arr[1] > v then return 0 end
  while lo < hi do
    local mid = floor((lo + hi + 1) / 2)
    if arr[mid] <= v then lo = mid else hi = mid - 1 end
  end
  return lo
end

local FIELDS = {} -- code -> { name = position, n } (only for codes from ns.Types)

function Index.fields(code)
  if type(code) ~= "string" then return nil end
  local f = FIELDS[code]
  if f then return f end
  local t = ns.Types and ns.Types[code]
  if type(t) ~= "table" or type(t.fields) ~= "table" then return nil end
  f = { n = #t.fields }
  for i, d in ipairs(t.fields) do
    if type(d) == "table" and type(d[1]) == "string" then f[d[1]] = i end
  end
  FIELDS[code] = f
  return f
end

local function pos(code, name)
  local f = Index.fields(code)
  return f and f[name]
end

function Index.str(rec, code, name)
  if type(rec) ~= "table" then return nil end
  local i = pos(code, name)
  local v = i and rec[i]
  if type(v) ~= "string" or v == "" then return nil end
  if v == "?" then return nil, true end
  return v
end

local function toNum(v)
  if type(v) ~= "string" or v == "" or v == "?" then return nil end
  local n = tonumber(v)
  if not finite(n) then return nil end
  return n
end

function Index.num(rec, code, name)
  if type(rec) ~= "table" then return nil end
  local i = pos(code, name)
  return i and toNum(rec[i]) or nil
end

local function id(v) -- positive integer from a field, else nil
  if type(v) ~= "string" or not find(v, "^%d+$") or #v > 12 then return nil end
  local n = tonumber(v)
  if not n or n <= 0 then return nil end
  return n
end

local function key(v) -- source/action as key: short lowercase words only
  if type(v) ~= "string" or #v > 24 or not find(v, "^[%a_]+$") then return "other" end
  return v
end

local function newState(db, guid, char)
  local meta = type(db.meta) == "table" and db.meta or {}
  local tz = tonumber(meta.tzOffset)
  return {
    db = db, guid = guid, char = char, nBlocks = 0, firstRef = nil, lastRef = nil,
    lines = 0, firstT = huge, lastT = -huge, tz = finite(tz) and tz or 0, tzT = {}, tzV = {},
    counts = {}, lists = {}, truncated = {}, keyN = {},
    kills = { total = 0, stamp = { normal = 0, elite = 0, rare = 0, boss = 0, unknown = 0 }, npc = {}, npcCount = 0,
      npcUnknown = 0, map = {}, mapCount = 0, day = {}, dayCount = 0, group = 0, withPos = 0, heat = {}, heatMaps = 0,
      pts = {}, ptsN = 0, npcMapTotal = 0, fight = {}, fightN = 0 },
    xp = { total = 0, n = 0, rested = 0, unclear = 0, source = {}, level = {} },
    money = { source = {}, level = {}, first = nil, last = nil, peak = nil },
    skills = {}, skillN = 0,
    pendLn = {}, pendT = {}, pendN = 0, -- rare kills still waiting for their KF (line number, time)
    ah = {},
    killSeries = { size = Index.KILL_BUCKET, b = {}, c = {} },
    questObj = {}, questObjN = 0,
    restT = {}, restInnT = {}, restFireT = {}, restKinds = { inn = 0, fire = 0 },
    richN = 0, -- balance steps reached (Index.RICH_STEPS)
  }
end

local function push(S, code, rec)
  local list = S.lists[code]
  if not list then
    list = {}
    S.lists[code] = list
  end
  if #list >= Index.LIST_MAX then
    S.truncated[code] = true
    return
  end
  list[#list + 1] = rec
end

-- key in a bounded sum (sources/actions): more than Index.KEY_MAX distinct -> "other"
local function bounded(S, name, tbl, k)
  if tbl[k] == nil then
    local n = S.keyN[name] or 0
    if n >= Index.KEY_MAX then
      S.truncated[name] = true
      k = "other"
    else
      S.keyN[name] = n + 1
    end
  end
  return k
end

local SF = { n = 0 } -- fields of the current line
local FAST_MAX = 11      -- up to this many fields: a single match instead of gmatch (hot path: KI, XP, GD)
local PAT = {}           -- field count -> pattern "^([^~]*)~?([^~]*)~?..."

-- splits rest into at most max fields in SF[1..max]; missing trailing fields become "" (like empty fields in the log)
local function split(rest, max)
  if max <= FAST_MAX then
    local p = PAT[max]
    if not p then
      p = "^" .. string.rep("([^~]*)~?", max)
      PAT[max] = p
    end
    SF[1], SF[2], SF[3], SF[4], SF[5], SF[6], SF[7], SF[8], SF[9], SF[10], SF[11] = match(rest, p)
    for i = max + 1, SF.n do SF[i] = nil end
    SF.n = max
    return max
  end
  local n = 0
  for v in gmatch(rest .. "~", "([^~]*)~") do
    n = n + 1
    if n > max then
      n = max
      break
    end
    SF[n] = v
  end
  for i = n + 1, SF.n do SF[i] = nil end
  SF.n = n
  return n
end

-- record: fields 1..n as an array, rec.t = epoch. The fields come from the constructor in one go so the array takes
-- exactly n slots
-- (filling r[i] = v one by one grows in powers of two: 9 fields = 16 slots, noticeable with tens of thousands of records).
local function record(t, n, ln)
  local cap = Index.FIELD_CAP
  local cut = ns.Sanitize and ns.Sanitize.cut
  while n > 0 and SF[n] == "" do n = n - 1 end -- do not keep empty trailing fields
  local r = { t = t, ln = ln, unpack(SF, 1, n) }
  for i = 1, n do
    local v = r[i]
    if #v > cap then r[i] = cut and cut(v, cap) or sub(v, 1, cap) end
  end
  return r
end

local function dayKey(S, t)
  return floor((t + S.tz) / 86400)
end

-- line handlers: H[code](S, t, n) with the fields in SF

local H = {}

-- attach the fight duration to a rare kill (kills.fight[ln]); the first matching fight wins
local function linkFight(S, ln, d)
  local k = S.kills
  if k.fight[ln] ~= nil then return end
  if k.fightN >= Index.LIST_MAX then
    S.truncated.fight = true
    return
  end
  k.fight[ln], k.fightN = d, k.fightN + 1
end

H.L = function(S, t)
  local tz = toNum(SF[6])
  if tz and tz > -86400 and tz < 86400 then
    S.tz = tz
    if #S.tzT < Index.LIST_MAX then
      S.tzT[#S.tzT + 1], S.tzV[#S.tzV + 1] = t, tz
    else
      S.truncated.L = true -- an SV with millions of login lines: the time zone history stops growing
    end
  end
end

local function countKeys(tbl)
  local n = 0
  for _ in pairs(tbl) do n = n + 1 end
  return n
end

H.KI = function(S, t)
  local k = S.kills
  k.total = k.total + 1
  local lv = toNum(SF[2])
  local stamp = (lv == -1) and "boss" or STAMP[SF[3]] or "unknown"
  k.stamp[stamp] = k.stamp[stamp] + 1
  local npc = id(SF[1])
  if npc then
    local e = k.npc[npc]
    if not e and k.npcCount < Index.NPC_MAX then
      e = { n = 0, stamp = stamp, map = {} } -- keep small: one entry per NPC kind (up to NPC_MAX)
      k.npc[npc] = e
      k.npcCount = k.npcCount + 1
    elseif not e then
      S.truncated.npc = true
    end
    if e then
      e.n = e.n + 1
      if lv and lv > 0 then
        if not e[1] or lv < e[1] then e[1] = lv end
        if not e[2] or lv > e[2] then e[2] = lv end
      end
      if SF[6] == "group" then e.group = (e.group or 0) + 1 end
      local m = id(SF[4])
      if m then
        local c = e.map[m]
        if c then
          e.map[m] = c + 1
        elseif k.npcMapTotal < Index.NPC_MAP_TOTAL and countKeys(e.map) < Index.NPC_MAP_MAX then
          e.map[m], k.npcMapTotal = 1, k.npcMapTotal + 1
        else
          S.truncated.npcMap = true
        end
      end
    end
  else
    k.npcUnknown = k.npcUnknown + 1
  end
  if SF[6] == "group" then k.group = k.group + 1 end
  local m = id(SF[4])
  if m then
    if k.map[m] then
      k.map[m] = k.map[m] + 1
    elseif k.mapCount < Index.MAP_MAX then
      k.map[m], k.mapCount = 1, k.mapCount + 1
    else
      S.truncated.map = true
    end
    local x, y = toNum(SF[10]), toNum(SF[11])
    if x and y and x >= 0 and x <= 9999 and y >= 0 and y <= 9999 then
      k.withPos = k.withPos + 1
      local h = k.heat[m]
      if not h and k.heatMaps < Index.HEAT_MAPS then
        h = {}
        k.heat[m], k.heatMaps = h, k.heatMaps + 1
      end
      if h then
        local g = Index.HEAT_GRID
        local cell = floor(y * g / 10000) * g + floor(x * g / 10000)
        h[cell] = (h[cell] or 0) + 1
      end
      -- exact point (sample, ring buffer per map): for "Genau" and the hunting-reason tooltips
      local p = k.pts[m]
      if not p and k.ptsN < Index.POINT_TOTAL then
        p = { n = 0, pos = {}, nl = {}, t = {} }
        k.pts[m] = p
      end
      if p then
        local slot = p.n % Index.POINT_MAX + 1
        if p.n < Index.POINT_MAX then
          if k.ptsN < Index.POINT_TOTAL then k.ptsN = k.ptsN + 1 else slot = nil end
        end
        if slot then
          p.n = p.n + 1
          local lvc = (lv and lv > 0) and min(floor(lv), 127) or 0
          p.pos[slot] = floor(x) * 10000 + floor(y)
          p.nl[slot] = (npc or 0) * 128 + lvc
          p.t[slot] = floor(t)
        end
      end -- no room (total budget): no points, only heat; no truncated flag, the points are a sample anyway
    end
  end
  -- kill series: buckets in log order; a jump back in time (clock changed) lands in the last bucket
  local ks = S.killSeries
  local kb, kc = ks.b, ks.c
  local nb = #kb
  local bt = floor(t / ks.size)
  if nb > 0 and bt <= kb[nb] then
    kc[nb] = kc[nb] + 1
  elseif nb < Index.KILLT_MAX then
    kb[nb + 1], kc[nb + 1] = bt, (nb > 0 and kc[nb] or 0) + 1
  else
    S.truncated.killT = true
  end
  local d = dayKey(S, t)
  if k.day[d] then
    k.day[d] = k.day[d] + 1
  elseif k.dayCount < Index.DAY_MAX then
    k.day[d], k.dayCount = 1, k.dayCount + 1
  end
  if stamp == "rare" then
    -- fight duration (rare only, Kampf page): the KF of this fight may precede the KI line (delayed up to 1 s)
    local ft, fd = S.fightT, S.fightD
    if ft and t <= ft + Index.FIGHT_SLACK and t >= ft - fd - Index.FIGHT_SLACK then
      linkFight(S, S.lines, fd)
    else
      -- waits for the KF entry of its fight; several rare kills in the same fight wait together (flat lists, at most
      -- Index.PENDING_MAX; the oldest drops out)
      local pl, pt = S.pendLn, S.pendT
      if S.pendN >= Index.PENDING_MAX then
        for i = 1, S.pendN - 1 do pl[i], pt[i] = pl[i + 1], pt[i + 1] end
        S.pendN = S.pendN - 1
      end
      S.pendN = S.pendN + 1
      pl[S.pendN], pt[S.pendN] = S.lines, t
    end
  end
  if stamp == "elite" or stamp == "rare" or stamp == "boss" then return true end
end

H.XP = function(S)
  local x = S.xp
  if SF[9] == "unclear" then
    x.unclear = x.unclear + 1
    return
  end
  local src = XP_SOURCES[SF[1]] and SF[1] or "other"
  local amt, rested = toNum(SF[2]) or 0, toNum(SF[3]) or 0
  x.total, x.n, x.rested = x.total + amt, x.n + 1, x.rested + rested
  local s = x.source[src]
  if not s then
    s = { n = 0, amount = 0, rested = 0 }
    x.source[src] = s
  end
  s.n, s.amount, s.rested = s.n + 1, s.amount + amt, s.rested + rested
  local lv = toNum(SF[7])
  if lv and lv >= 1 and lv <= 200 then
    lv = floor(lv)
    local l = x.level[lv]
    if not l then
      l = {}
      x.level[lv] = l
    end
    l[src] = (l[src] or 0) + amt
  end
end

H.GD = function(S, t)
  local m = S.money
  local delta, balance = toNum(SF[1]), toNum(SF[2])
  local keep = false
  if balance then
    if not m.first then m.first = { t = t, balance = balance } end
    m.last = { t = t, balance = balance }
    if not m.peak or balance > m.peak.balance then m.peak = { t = t, balance = balance } end
    local steps = Index.RICH_STEPS
    while S.richN < #steps and balance >= steps[S.richN + 1] do S.richN, keep = S.richN + 1, true end
  end
  if not delta or delta == 0 then return keep end
  local src = bounded(S, "money", m.source, key(SF[3]))
  local s = m.source[src]
  if not s then
    s = { gain = 0, loss = 0, n = 0 }
    m.source[src] = s
  end
  s.n = s.n + 1
  local lv = toNum(SF[4])
  local l
  if lv and lv >= 1 and lv <= 200 then
    lv = floor(lv)
    l = m.level[lv]
    if not l then
      l = { gain = 0, loss = 0, out = {} }
      m.level[lv] = l
    end
  end
  if delta > 0 then
    s.gain = s.gain + delta
    if l then l.gain = l.gain + delta end
  else
    s.loss = s.loss - delta
    if l then
      l.loss = l.loss - delta
      l.out[src] = (l.out[src] or 0) - delta
    end
  end
  return keep
end

H.AH = function(S)
  local a = bounded(S, "ah", S.ah, key(SF[1]))
  local e = S.ah[a]
  if not e then
    e = { n = 0, deposit = 0, price = 0 }
    S.ah[a] = e
  end
  e.n = e.n + 1
  local d, p = toNum(SF[6]), toNum(SF[5])
  if d and d > 0 then e.deposit = e.deposit + d end
  if p and p > 0 then e.price = e.price + p end
end

-- quest objective progress (QO): final state per (questID, idx), no record list (a step per kill would be too much)
local QS = Index.QOBJ_STRIDE
H.QO = function(S, t)
  local qid, idx = id(SF[1]), id(SF[2])
  if not qid or not idx or idx > Index.QOBJ_IDX then return false end
  local have, need = toNum(SF[3]), toNum(SF[4])
  if not have or have < 0 or have > 1000000 then return false end
  if need and (need <= 0 or need > 1000000) then need = nil end
  local qo = S.questObj
  local e = qo[qid]
  if not e then
    if S.questObjN >= Index.QOBJ_MAX then
      S.truncated.questObj = true
      return false
    end
    e = {}
    qo[qid] = e
    S.questObjN = S.questObjN + 1
  end
  -- flat array per quest (QOBJ_STRIDE slots per objective): have, need (0 = unknown), kind, text (false = none), n
  local base = (idx - 1) * QS
  for i = #e + 1, base + QS do e[i] = false end -- fill gaps (objectives without a line) and create the new objective
  if e[base + 1] == false then e[base + 5] = 0 end
  e[base + 1], e[base + 2] = floor(have), need and floor(need) or 0
  e[base + 3] = key(SF[5])
  e[base + 5] = e[base + 5] + 1
  local txt = SF[6]
  if type(txt) == "string" and txt ~= "" and txt ~= "?" then
    local cut = ns.Sanitize and ns.Sanitize.cut
    e[base + 4] = #txt > Index.QOBJ_TEXT and (cut and cut(txt, Index.QOBJ_TEXT) or sub(txt, 1, Index.QOBJ_TEXT)) or txt
  end
  return false
end

-- rest (RA): only the times (ns.Rest.summary cuts "since the last rest" from them)
H.RA = function(S, t)
  local r = S.restT
  if #r >= Index.REST_MAX then
    S.truncated.rest = true
    return
  end
  r[#r + 1] = t
  local kind = SF[1]
  if kind == "inn" or kind == "fire" then
    S.restKinds[kind] = S.restKinds[kind] + 1
    local kt = kind == "inn" and S.restInnT or S.restFireT
    kt[#kt + 1] = t
  end
end

-- profession: best known value per name. Only lines with a maximum (max) are professions; weapon skills have none.
H.SK = function(S, t)
  local name, rank, cap = SF[1], toNum(SF[2]), toNum(SF[3])
  if name == "" or name == "?" or not rank or not cap or rank < 0 then return end
  name = sub(name, 1, 64)
  local e = S.skills[name]
  if not e then
    if S.skillN >= Index.SKILL_MAX then
      S.truncated.skills = true
      return
    end
    S.skillN = S.skillN + 1
    e = { rank = -1 }
    S.skills[name] = e
  end
  if rank > e.rank then e.rank, e.max, e.t = rank, cap, t end
end

H.KF = function(S, t)
  local d = toNum(SF[1])
  if d and d >= 0 and d < 86400 then
    S.fightT, S.fightD = t, d
    local pl, pt = S.pendLn, S.pendT
    local keep = 0
    for i = 1, S.pendN do
      local pn, tt = pl[i], pt[i]
      if tt <= t + Index.FIGHT_SLACK and tt >= t - d - Index.FIGHT_SLACK then
        linkFight(S, pn, d)
      else
        keep = keep + 1
        pl[keep], pt[keep] = pn, tt
      end
    end
    S.pendN = keep
  end
  return SF[7] == "1"
end
-- to-do done (VE): each to-do counts once, at the first completion (key = id + text). Older states hold multiple lines
-- (tick/open/tick);
-- they are dropped here so the medal "Eigene Wege" and the diary are not inflated. The log lines themselves stay unchanged.
Index.PLAN_MAX = 5000
H.VE = function(S)
  local seen = S.planSeen
  if not seen then
    seen = {}
    S.planSeen, S.planSeenN = seen, 0
  end
  local k = tostring(SF[1]) .. "|" .. tostring(SF[6])
  if seen[k] then return false end
  if S.planSeenN >= Index.PLAN_MAX then
    S.truncated.plans = true
    return true
  end
  seen[k] = true
  S.planSeenN = S.planSeenN + 1
  return true
end
H.LT = function(S)
  local q = toNum(SF[3])
  return q == nil or q >= 2 -- unknown quality (empty or "?") stays: better too many than losing a find
end

local function onLine(S, t, code, rest)
  S.lines = S.lines + 1
  if t > S.lastT then S.lastT = t end
  if t < S.firstT then S.firstT = t end
  local types = ns.Types
  if not (types and types[code]) then return end
  S.counts[code] = (S.counts[code] or 0) + 1
  local h, keep = H[code], Index.LISTS[code]
  if not (h or keep) then return end
  local n = split(rest, Index.fields(code).n)
  if h and h(S, t) then keep = true end
  if keep then push(S, code, record(t, n, S.lines)) end
end

local function readBlock(S, block)
  if type(block) ~= "string" then return end
  local h = tonumber(match(block, "^#~(%-?%d+)~"))
  if not finite(h) then return end
  for dt, code, rest in gmatch(block, "\n(%-?%d+)~(%u+)~?([^\n]*)") do
    local t = h + tonumber(dt) -- tonumber("999...9" with 400 digits) is inf: skip the line
    if finite(t) then onLine(S, t, code, rest) end
    pause()
  end
end

local function readOpen(S, lines, start)
  if type(lines) ~= "table" or not finite(start) then return end
  for i = 1, #lines do
    local line = lines[i]
    if type(line) == "string" then
      local dt, code, rest = match(line, "^(%-?%d+)~(%u+)~?(.*)$")
      if dt then
        local t = start + tonumber(dt)
        if finite(t) then onLine(S, t, code, rest) end
      end
    end
    pause()
  end
end

local function deep(v)
  if type(v) ~= "table" then return v end
  local o = {}
  for k, x in pairs(v) do
    o[k] = deep(x)
    pause()
  end
  return o
end

local function clone(S)
  local o = {}
  for k, v in pairs(S) do
    if k == "lists" then
      local l = {}
      for code, list in pairs(v) do
        local c = {}
        for i = 1, #list do c[i] = list[i] end
        l[code] = c
        pause()
      end
      o.lists = l
    elseif k == "db" or k == "char" or k == "firstRef" or k == "lastRef" then
      o[k] = v
    else
      o[k] = deep(v)
    end
  end
  return o
end

-- sessions of the character as sorted, merged spans [t0, t1] (open session: t1 = huge)
local function sessionSpans(db, guid, char)
  local meta = type(db.meta) == "table" and db.meta or {}
  local list = type(meta.sessions) == "table" and meta.sessions or {}
  local Store = ns.Store
  local liveIdx = Store and Store.current == char and Store.session or nil
  local raw = {}
  local n = #list
  local from = n > Index.SESSION_MAX and n - Index.SESSION_MAX + 1 or 1
  for i = from, n do
    local s = list[i]
    if type(s) == "table" and s.guid == guid then
      local t0 = tonumber(s.start)
      if finite(t0) then
        local t1 = tonumber(s.stop)
        if not finite(t1) then
          if s.interrupted then
            t1 = tonumber(s.lastKnown)
          elseif i == liveIdx then
            t1 = huge
          else
            t1 = tonumber(s.lastSave)
          end
          if t1 ~= huge and not finite(t1) then t1 = t0 end
        end
        if t1 < t0 then t1 = t0 end
        raw[#raw + 1] = { t0, t1 }
      end
    end
  end
  table.sort(raw, function(a, b) return a[1] < b[1] end)
  local sp = { t0 = {}, t1 = {}, cum = {} }
  for _, r in ipairs(raw) do
    local k = #sp.t0
    if k > 0 and r[1] <= sp.t1[k] then
      if r[2] > sp.t1[k] then sp.t1[k] = r[2] end
    else
      sp.t0[k + 1], sp.t1[k + 1] = r[1], r[2]
    end
  end
  local cum = 0
  for i = 1, #sp.t0 do
    sp.cum[i] = cum
    if sp.t1[i] ~= huge then cum = cum + (sp.t1[i] - sp.t0[i]) end
  end
  return sp
end

local function activeUntil(sp, t)
  local i = bsearch(sp.t0, t)
  if i == 0 then return 0 end
  return sp.cum[i] + (min(t, sp.t1[i]) - sp.t0[i])
end

function Index.activeSeconds(index, t0, t1)
  t0, t1 = tonumber(t0), tonumber(t1)
  if not finite(t0) or not finite(t1) or t1 <= t0 then return 0, true end
  local sp = type(index) == "table" and index.sessions
  if not sp or #sp.t0 == 0 then return t1 - t0, false end
  return activeUntil(sp, t1) - activeUntil(sp, t0), true
end

local function tzAt(index, t)
  local i = bsearch(index.tzT, t)
  if i == 0 then return index.tz0 or 0 end
  return index.tzV[i]
end

function Index.dayOf(index, t)
  t = tonumber(t)
  if type(index) ~= "table" or not finite(t) then return 1 end
  local s = index.startT
  local d = floor((t + tzAt(index, t)) / 86400) - floor((s + tzAt(index, s)) / 86400) + 1
  return d < 1 and 1 or d
end

function Index.timeOfDay(index, t)
  t = tonumber(t)
  if type(index) ~= "table" or not finite(t) then return nil end
  local s = (t + tzAt(index, t)) % 86400
  return floor(s / 3600), floor(s % 3600 / 60), floor(s % 60)
end

-- calendar date to "days since 1970-01-01" (civil calendar, as Chronik.civil)
local function civil(z)
  z = z + 719468
  local era = floor(z / 146097)
  local doe = z - era * 146097
  local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
  local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
  local mp = floor((5 * doy + 2) / 153)
  local d = doy - floor((153 * mp + 2) / 5) + 1
  local m = mp < 10 and mp + 3 or mp - 9
  local y = yoe + era * 400
  if m <= 2 then y = y + 1 end
  return y, m, d
end

function Index.dateOf(index, t)
  t = tonumber(t)
  if type(index) ~= "table" or not finite(t) or t < 0 or t > 4102444800 then return nil end
  local y, m, d = civil(floor((t + tzAt(index, t)) / 86400))
  return d, m, y
end

-- kills up to (excluding) t: whole buckets before it plus the proportional bucket of t
local function killsBefore(ks, t)
  local bt = floor(t / ks.size)
  local i = bsearch(ks.b, bt)
  if i == 0 then return 0 end
  if ks.b[i] < bt then return ks.c[i] end
  local before = i > 1 and ks.c[i - 1] or 0
  return before + (ks.c[i] - before) * ((t - bt * ks.size) / ks.size)
end

function Index.killsBetween(index, t0, t1)
  t0, t1 = tonumber(t0), tonumber(t1)
  local ks = type(index) == "table" and index.killSeries
  if type(ks) ~= "table" or not finite(t0) or not finite(t1) or t1 <= t0 then return 0, false end
  local n = killsBefore(ks, t1) - killsBefore(ks, t0)
  if n < 0 then n = 0 end
  return floor(n + 0.5), t0 % ks.size == 0 and t1 % ks.size == 0
end

-- lowest and highest level of a kills.npc entry (nil if no level was ever read)
function Index.npcLevels(e)
  if type(e) ~= "table" then return nil, nil end
  return e[1], e[2]
end

-- quest objectives of a quest as tables { idx, have, need|nil, kind, text|nil, n }, sorted by idx (built fresh on each call)
function Index.questGoals(index, questID)
  local out = {}
  local e = type(index) == "table" and type(index.questObj) == "table" and index.questObj[questID]
  if type(e) ~= "table" then return out end
  local QS = Index.QOBJ_STRIDE
  for base = 0, #e - QS, QS do
    if e[base + 1] ~= false then
      local need, text = e[base + 2], e[base + 4]
      out[#out + 1] = { idx = base / QS + 1, have = e[base + 1], need = need and need > 0 and need or nil, kind = e[base + 3],
        text = text or nil, n = e[base + 5] }
    end
  end
  return out
end

function Index.list(index, code)
  local l = type(index) == "table" and type(index.lists) == "table" and index.lists[code]
  return l or {}
end

local base = nil      -- private state of the closed blocks
local cache = nil     -- { db, guid, sig, index }
local job = nil
local readyFns = {}
local prepScheduled = false
Index.readyErrors = 0

local function fail(err)
  local ok, s = pcall(tostring, err)
  s = ok and s or "?"
  Index.lastError = (ns.Sanitize and ns.Sanitize.field(s)) or "?"
end

local function signature(guid, char, open)
  local log = type(char.log) == "table" and char.log or {}
  local last = log[#log]
  local ll = type(last) == "string" and #last or 0
  local b = open and open.block
  local ob = type(b) == "table" and type(b.lines) == "table" and #b.lines or 0
  local os_ = type(b) == "table" and tonumber(b.start) or 0
  if not finite(os_) then os_ = 0 elseif os_ > MAX_INT then os_ = MAX_INT elseif os_ < -MAX_INT then os_ = -MAX_INT end
  return table.concat({ guid, #log, ll, ob, format("%.0f", floor(os_) + 0) }, "|")
end

local function resolve(opts)
  local db = opts.db or EveNChronicleDB
  if type(db) ~= "table" or type(db.chars) ~= "table" then return nil, "keine-daten" end
  local Store = ns.Store
  local guid = opts.guid
  if guid == nil then
    guid = Store and Store.guid
    if guid == nil and type(UnitGUID) == "function" then
      local ok, g = pcall(UnitGUID, "player")
      if ok and not isSecret(g) then guid = g end
    end
  end
  if type(guid) ~= "string" then return nil, "kein-charakter" end
  local char = db.chars[guid]
  if type(char) ~= "table" then return nil, "kein-charakter" end
  local open = (Store and Store.current == char) and Store or nil
  return { db = db, guid = guid, char = char, open = open }
end

-- snapshot of the sources: number of closed blocks and a copy of the open lines (the Store keeps writing while the
-- build runs in slices)
local function snapshot(ctx)
  local log = type(ctx.char.log) == "table" and ctx.char.log or {}
  local s = { log = log, nLog = #log }
  local b = ctx.open and ctx.open.block
  if type(b) == "table" and type(b.lines) == "table" and tonumber(b.start) then
    local lines = {}
    for i = 1, #b.lines do lines[i] = b.lines[i] end
    s.openLines, s.openStart = lines, tonumber(b.start)
  end
  return s
end

local function baseValid(ctx, snap)
  local S = base
  if not S or S.db ~= ctx.db or S.guid ~= ctx.guid or S.char ~= ctx.char then return false end
  if snap.nLog < S.nBlocks then return false end
  if S.nBlocks > 0 and (snap.log[1] ~= S.firstRef or snap.log[S.nBlocks] ~= S.lastRef) then return false end
  return true
end

local function build(ctx, snap, force)
  local c0 = clock()
  if force or not baseValid(ctx, snap) then base = newState(ctx.db, ctx.guid, ctx.char) end
  local S = base
  for i = S.nBlocks + 1, snap.nLog do
    readBlock(S, snap.log[i])
    -- counted only after the whole block. If readBlock fails mid-block, the whole state is dropped (stepJob/buildSync
    -- set base = nil),
    -- so a half-read block never stays in the state. The pauses only interrupt the block inside the build coroutine,
    -- which finishes it.
    S.nBlocks = i
    if i == 1 then S.firstRef = snap.log[1] end
    S.lastRef = snap.log[i]
  end
  local I = clone(S)
  readOpen(I, snap.openLines, snap.openStart)
  I.lists = I.lists or {}
  local info = type(ctx.char.info) == "table" and ctx.char.info or {}
  local first = tonumber(info.firstSeen)
  if I.firstT == huge then I.firstT, I.lastT = first or 0, first or 0 end
  I.startT = (finite(first) and first < I.firstT) and first or I.firstT
  local meta = type(ctx.db.meta) == "table" and ctx.db.meta or {}
  I.tz0 = finite(tonumber(meta.tzOffset)) and tonumber(meta.tzOffset) or 0
  I.sessions = sessionSpans(ctx.db, ctx.guid, ctx.char)
  I.blocks = snap.nLog
  I.keyN, I.firstRef, I.lastRef, I.db, I.nBlocks = nil, nil, nil, nil, nil
  I.timings = { total = clock() - c0 }
  return I
end

local function asyncOK(opts)
  return Index.ASYNC == true and not opts.sync and type(coroutine) == "table" and type(coroutine.create) == "function"
    and type(C_Timer) == "table" and type(C_Timer.After) == "function"
end

local function inCombat()
  if type(InCombatLockdown) ~= "function" then return false end
  local ok, v = pcall(InCombatLockdown)
  return ok and v == true
end

local function currentSig(db, guid)
  local char = type(db.chars) == "table" and db.chars[guid]
  if type(char) ~= "table" then return nil end
  local Store = ns.Store
  return signature(guid, char, (Store and Store.current == char) and Store or nil)
end

local function publish(j, I)
  I.timings.cpu, I.timings.frames, I.timings.maxFrame = j.cpu, j.frames, j.maxFrame
  I.sig = j.sig
  I.stale = currentSig(j.db, j.guid) ~= j.sig
  cache = { db = j.db, guid = j.guid, sig = j.sig, index = I }
end

-- work one slice (budget ms) -> true when finished or aborted
local function stepJob(j, budget)
  if job ~= j then return true end
  local c0 = clock()
  deadline, inJob, tick = c0 + budget, true, 0
  local ok, res = coroutine.resume(j.co)
  inJob, deadline = false, huge
  local dt = clock() - c0
  j.cpu, j.frames = j.cpu + dt, j.frames + 1
  if budget < huge and dt > j.maxFrame then j.maxFrame = dt end
  if not ok then
    job, base = nil, nil -- half state: start over next time
    fail(res)
    return true
  end
  if coroutine.status(j.co) ~= "dead" then return false end
  job = nil
  publish(j, res)
  for _, fn in ipairs(readyFns) do
    if not pcall(fn, res) then Index.readyErrors = Index.readyErrors + 1 end
  end
  return true
end

local function schedule(j)
  local function step()
    if job ~= j then return end
    if j.low and inCombat() then
      C_Timer.After(Index.COMBAT_RETRY, step)
      return
    end
    local ok, done = pcall(stepJob, j, Index.FRAME_BUDGET)
    if not ok then
      if job == j then job, base = nil, nil end
      fail(done)
    elseif not done then
      C_Timer.After(0, step)
    end
  end
  C_Timer.After(0, step)
end

local function startJob(ctx, sig, low)
  if job and job.db == ctx.db and job.guid == ctx.guid then
    if not low then job.low = false end
    return job
  end
  if job then base = nil end -- a replaced build (other character) may leave a half state
  local snap = snapshot(ctx)
  local j = { db = ctx.db, guid = ctx.guid, sig = sig, low = low, cpu = 0, frames = 0, maxFrame = 0 }
  j.co = coroutine.create(function() return build(ctx, snap, false) end)
  job = j
  schedule(j)
  return j
end

-- synchronous: finish a running background build without budget (never abort it), then read what is missing
local function buildSync(ctx, sig, force)
  if job then stepJob(job, huge) end
  if not force and cache and cache.db == ctx.db and cache.guid == ctx.guid and cache.sig == sig then
    cache.index.stale = false
    return cache.index
  end
  local c0 = clock()
  local ok, I = pcall(build, ctx, snapshot(ctx), force)
  if not ok then
    base = nil
    fail(I)
    return nil, "fehler"
  end
  local dt = clock() - c0
  I.timings.cpu, I.timings.frames, I.timings.maxFrame = dt, 1, dt
  I.sig, I.stale = sig, false
  cache = { db = ctx.db, guid = ctx.guid, sig = sig, index = I }
  return I
end

function Index.get(opts)
  opts = opts or {}
  local ctx, why = resolve(opts)
  if not ctx then return nil, why end
  local sig = signature(ctx.guid, ctx.char, ctx.open)
  if opts.force or not asyncOK(opts) then return buildSync(ctx, sig, opts.force) end
  local mine = cache and cache.db == ctx.db and cache.guid == ctx.guid
  if mine and cache.sig == sig then
    cache.index.stale = false
    return cache.index
  end
  if mine and opts.noRebuild then -- caller in an onReady chain: draw with the existing state, do not rebuild
    cache.index.stale = true
    return cache.index
  end
  startJob(ctx, sig, false)
  if mine then
    cache.index.stale = true
    return cache.index
  end
  return nil, "baut"
end

function Index.prepare(opts)
  opts = opts or {}
  if not asyncOK(opts) then return false end
  local ctx = resolve(opts)
  if not ctx then return false end
  local sig = signature(ctx.guid, ctx.char, ctx.open)
  if cache and cache.db == ctx.db and cache.guid == ctx.guid and cache.sig == sig then return false end
  startJob(ctx, sig, true)
  return true
end

function Index.prepareAfterLogin(delay)
  if prepScheduled or not asyncOK({}) then return false end
  delay = tonumber(delay) or Index.PREPARE_DELAY
  if delay ~= delay or delay < 0 or delay > 600 then delay = Index.PREPARE_DELAY end
  prepScheduled = true
  C_Timer.After(delay, function()
    local ok, err = pcall(Index.prepare)
    if not ok then fail(err) end
  end)
  return true
end

function Index.building() return job ~= nil end

function Index.onReady(fn)
  if type(fn) ~= "function" then return false end
  for _, f in ipairs(readyFns) do
    if f == fn then return true end
  end
  readyFns[#readyFns + 1] = fn
  return true
end

function Index.invalidate()
  cache, base, job = nil, nil, nil
end
