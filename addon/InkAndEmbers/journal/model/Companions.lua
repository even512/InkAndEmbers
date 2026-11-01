-- Companions evaluator: aggregates per person from log lines WB/WV (read on first call, not in the index) plus index
-- lists QT, DE and the kill series. Kept at runtime only (weak key on the index), nothing in the SV.
-- person = { name, class, race, level0/1, firstT/lastT, firstMapID/X/Y/Zone, lastMapID/Zone, minutes, seconds,
-- sessions, quests, kills, deaths, active, intervals }
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Companions = {}
Journal.Companions = Companions

local floor, huge, min, max = math.floor, math.huge, math.min, math.max

Companions.MERGE_GAP = 300 -- seconds: a shorter gap between two intervals of the same person counts as one session
Companions.MAX_EVENTS = 4000 -- WB/WV lines read (the rest sets res.truncated)

local cache = setmetatable({}, { __mode = "k" })

local function finite(v)
  return type(v) == "number" and v == v and v ~= huge and v ~= -huge
end

local function mapName(char, mapID)
  if not mapID then return nil end
  local snaps = type(char) == "table" and char.snapshots
  local maps = type(snaps) == "table" and snaps.maps
  local m = type(maps) == "table" and maps[mapID]
  local name = type(m) == "table" and m.name
  if type(name) ~= "string" or name == "" then return nil end
  name = ns.Sanitize.field(name)
  return name ~= "" and name or nil
end

-- end of the session span containing t (open span: now); nil if t is in none
local function spanEnd(sessions, t, now)
  if type(sessions) ~= "table" or type(sessions.t0) ~= "table" then return nil end
  local t0, t1 = sessions.t0, sessions.t1
  local lo, hi, found = 1, #t0, 0
  while lo <= hi do
    local mid = floor((lo + hi) / 2)
    if t0[mid] <= t then found, lo = mid, mid + 1 else hi = mid - 1 end
  end
  if found == 0 then return nil end
  local e = t1[found]
  if e < t then return nil end
  if e == huge then return now end
  return e
end

-- read the log: only WB/WV lines as short text "<epoch>~<WB|WV>~<fields>"; closed blocks once (incremental), the open
-- block fresh on every call
local scan = nil -- { char, nBlocks, firstRef, lastRef, ev }

local function readBlockEvents(ev, block)
  if type(block) ~= "string" then return end
  local h = tonumber(string.match(block, "^#~(%-?%d+)~"))
  if not finite(h) then return end
  for dt, code, rest in string.gmatch(block, "\n(%-?%d+)~(W[BV])~([^\n]*)") do
    local t = h + tonumber(dt)
    if finite(t) and #ev < Companions.MAX_EVENTS then ev[#ev + 1] = string.format("%.0f~%s~%s", t, code, rest) end
  end
end

local function logEvents(char)
  local log = type(char) == "table" and type(char.log) == "table" and char.log or {}
  if not scan or scan.char ~= char or #log < scan.nBlocks or (scan.nBlocks > 0 and (log[1] ~= scan.firstRef or log[scan.nBlocks] ~= scan.lastRef)) then
    scan = { char = char, nBlocks = 0, ev = {} }
  end
  for i = scan.nBlocks + 1, #log do readBlockEvents(scan.ev, log[i]) end
  scan.nBlocks = #log
  scan.firstRef, scan.lastRef = log[1], log[#log]
  local out = {}
  for i = 1, #scan.ev do out[i] = scan.ev[i] end
  local Store = ns.Store
  local ob = Store and Store.current == char and Store.block
  if type(ob) == "table" and finite(tonumber(ob.start)) and type(ob.lines) == "table" then
    local start = tonumber(ob.start)
    for _, l in ipairs(ob.lines) do
      local dt, code, rest = string.match(l, "^(%-?%d+)~(W[BV])~?(.*)$")
      if dt and #out < Companions.MAX_EVENTS then out[#out + 1] = string.format("%.0f~%s~%s", start + tonumber(dt), code, rest) end
    end
  end
  return out, #out >= Companions.MAX_EVENTS
end

-- raw lines "<epoch>~WB|WV~name~class~race~level~mapID~x~y[~why]" -> people and events
-- person = { name, class, race, level0, level1, map0, x0, y0, map1, t0, t1 }; missing fields are false
local function parseEvents(compEv)
  local people, byName, n = {}, {}, 0
  local et, ep, ek, ne = {}, {}, {}, 0
  local function field(v)
    if v == nil or v == "" or v == "?" then return nil end
    return v
  end
  for i = 1, #compEv do
    local t, code, name, cls, race, level, map, x, y = string.match(compEv[i], "^(%-?%d+)~(%u+)~([^~]+)~?([^~]*)~?([^~]*)~?([^~]*)~?([^~]*)~?([^~]*)~?([^~]*)")
    t = tonumber(t)
    if t and name and name ~= "?" and (code == "WB" or code == "WV") then
      local lv, m = tonumber(field(level)), tonumber(field(map))
      local p = byName[name]
      if not p then
        n = n + 1
        p = { name = name, class = field(cls), race = field(race), level0 = lv, level1 = lv, map0 = m, x0 = tonumber(field(x)),
          y0 = tonumber(field(y)), map1 = m, t0 = t, t1 = t, idx = n }
        byName[name] = p
        people[n] = p
      else
        p.class, p.race = p.class or field(cls), p.race or field(race)
        if lv then
          p.level0 = p.level0 or lv
          p.level1 = lv
        end
        if m and not p.map0 then p.map0, p.x0, p.y0 = m, tonumber(field(x)), tonumber(field(y)) end
        p.map1 = m or p.map1
        p.t1 = t
      end
      ne = ne + 1
      et[ne], ep[ne], ek[ne] = t, p.idx, code == "WB" and 1 or 2
    end
  end
  return { people = people, n = n, et = et, ep = ep, ek = ek, ne = ne }
end

-- intervals per person: WB opens, WV closes. A second WB while open (crash, relogin) closes the old one at the end of
-- its session span;
-- intervals still open at the end close at the session span end or now.
local function intervals(comp, sessions, now)
  local iv, open = {}, {}
  local function close(p, a, b)
    if b < a then b = a end
    local l = iv[p]
    if not l then
      l = {}
      iv[p] = l
    end
    local k = #l
    if k >= 2 and a - l[k] < Companions.MERGE_GAP then
      if b > l[k] then l[k] = b end -- gap too small: same session
    else
      l[k + 1], l[k + 2] = a, b
    end
  end
  for n = 1, comp.ne do
    local t, p, k = comp.et[n], comp.ep[n], comp.ek[n]
    if k == 1 then
      local o = open[p]
      if o then
        local e = spanEnd(sessions, o, now)
        if e and e >= t then e = t end
        close(p, o, e or o)
      end
      open[p] = t
    else
      local o = open[p]
      if o then
        close(p, o, t)
        open[p] = nil
      end
    end
  end
  local stillOpen = {}
  local lastOpen = sessions and sessions.t1 and sessions.t1[#sessions.t1] == huge
  for p, o in pairs(open) do
    local e = spanEnd(sessions, o, now)
    close(p, o, min(e or o, now))
    stillOpen[p] = (e == now and lastOpen) and true or nil
  end
  return iv, stillOpen
end

-- first index i with list[i].t >= t (lists are sorted by time)
local function lowerBound(list, t)
  local lo, hi = 1, #list + 1
  while lo < hi do
    local mid = floor((lo + hi) / 2)
    if list[mid].t < t then lo = mid + 1 else hi = mid end
  end
  return lo
end

local function countIn(list, ivs)
  if not list or #list == 0 then return 0 end
  local n = 0
  for k = 1, #ivs, 2 do
    local a, b = ivs[k], ivs[k + 1]
    local i = lowerBound(list, a)
    while list[i] and list[i].t <= b do
      n = n + 1
      i = i + 1
    end
  end
  return n
end

function Companions.aggregate(index, opts)
  if type(index) ~= "table" or type(index.char) ~= "table" then return nil end
  local c = cache[index]
  if c then return c end
  local events, truncated = logEvents(index.char)
  local comp = parseEvents(events)
  local now = (opts and finite(opts.now)) and opts.now or time()
  local Index = Journal.Index
  local iv, live = intervals(comp, index.sessions, now)
  local qt = index.lists and index.lists.QT
  local de = index.lists and index.lists.DE
  local list = {}
  for i = 1, comp.n do
    local p = comp.people[i]
    local ivs = iv[i] or {}
    local seconds = 0
    local kills = 0
    for k = 1, #ivs, 2 do
      seconds = seconds + (ivs[k + 1] - ivs[k])
      if Index and Index.killsBetween and ivs[k + 1] > ivs[k] then kills = kills + (Index.killsBetween(index, ivs[k], ivs[k + 1])) end
    end
    list[#list + 1] = {
      name = p.name, class = p.class, race = p.race, level0 = p.level0, level1 = p.level1,
      firstT = p.t0, lastT = p.t1, firstMapID = p.map0, firstX = p.x0, firstY = p.y0,
      firstZone = mapName(index.char, p.map0), lastMapID = p.map1, lastZone = mapName(index.char, p.map1),
      seconds = seconds, minutes = floor(seconds / 60 + 0.5), sessions = floor(#ivs / 2),
      quests = countIn(qt, ivs), kills = kills, deaths = countIn(de, ivs), active = live[i] == true, intervals = ivs,
    }
  end
  table.sort(list, function(a, b)
    if a.lastT ~= b.lastT then return a.lastT > b.lastT end
    return a.name < b.name
  end)
  local res = { list = list, count = #list, truncated = truncated }
  cache[index] = res
  return res
end

function Companions.sorted(res, mode)
  local out = {}
  if type(res) ~= "table" or type(res.list) ~= "table" then return out end
  for i, p in ipairs(res.list) do out[i] = p end
  local cmp
  if mode == "minutes" then
    cmp = function(a, b) if a.seconds ~= b.seconds then return a.seconds > b.seconds end return a.name < b.name end
  elseif mode == "first" then
    cmp = function(a, b) if a.firstT ~= b.firstT then return a.firstT < b.firstT end return a.name < b.name end
  elseif mode == "name" then
    cmp = function(a, b) return string.lower(a.name) < string.lower(b.name) end
  else
    cmp = function(a, b) if a.lastT ~= b.lastT then return a.lastT > b.lastT end return a.name < b.name end
  end
  table.sort(out, cmp)
  return out
end

function Companions.between(index, t0, t1, opts)
  local out = {}
  if not finite(t0) or not finite(t1) or t1 <= t0 then return out end
  local res = Companions.aggregate(index, opts)
  if not res then return out end
  for _, p in ipairs(res.list) do
    local s = 0
    local ivs = p.intervals
    for k = 1, #ivs, 2 do
      local a, b = max(ivs[k], t0), min(ivs[k + 1], t1)
      if b > a then s = s + (b - a) end
    end
    if s > 0 then out[#out + 1] = { name = p.name, class = p.class, race = p.race, seconds = s } end
  end
  table.sort(out, function(a, b) if a.seconds ~= b.seconds then return a.seconds > b.seconds end return a.name < b.name end)
  return out
end

-- Companions.detail(index, person[, n]) -> { zones = { name, ... }, quests = { title, ... } }
-- most frequent zones of the shared time and the latest shared quests (sanitized titles), at most n (default 4)
function Companions.detail(index, p, n)
  local out = { zones = {}, quests = {} }
  if type(index) ~= "table" or type(p) ~= "table" or type(p.intervals) ~= "table" then return out end
  n = tonumber(n) or 4
  local Index = Journal.Index
  local lists = index.lists or {}
  local ivs = p.intervals
  local function inside(t)
    for k = 1, #ivs, 2 do if t >= ivs[k] and t <= ivs[k + 1] then return true end end
    return false
  end
  local seen, order = {}, {}
  local function addMap(mapID, w)
    local name = mapName(index.char, mapID)
    if not name then return end
    if not seen[name] then
      seen[name] = { name = name, n = 0, i = #order + 1 }
      order[#order + 1] = seen[name]
    end
    seen[name].n = seen[name].n + (w or 1)
  end
  addMap(p.firstMapID)
  addMap(p.lastMapID)
  local texts = type(index.char.quests) == "table" and index.char.quests or nil
  local qt = lists.QT or {}
  for i = #qt, 1, -1 do
    local r = qt[i]
    if finite(r.t) and inside(r.t) then
      addMap(Index and Index.num(r, "QT", "mapID"))
      local id = Index and Index.num(r, "QT", "questID")
      local q = id and texts and texts[floor(id)]
      local title = type(q) == "table" and type(q.title) == "string" and ns.Sanitize.field(q.title) or nil
      if title and title ~= "" and #out.quests < n then out.quests[#out.quests + 1] = title end
    end
  end
  for _, r in ipairs(lists.DE or {}) do
    if finite(r.t) and inside(r.t) then addMap(Index and Index.num(r, "DE", "mapID")) end
  end
  table.sort(order, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.i < b.i end)
  for i = 1, min(n, #order) do out.zones[i] = order[i].name end
  return out
end

function Companions.clear()
  scan = nil
  cache = setmetatable({}, { __mode = "k" })
end
