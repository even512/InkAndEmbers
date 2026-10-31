-- Per calendar day (character local time, key = whole days since 1970): facts from the index, lists and trail; data
-- only, no texts. Days.facts(index, key, opts) -> { zones, kills, rares, deaths, quests, loot, companions, campfires,
-- seals, moments, plansDone, notes, ... }.
-- Names are raw SV text (Sanitize.field); display only via Sanitize.display.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Days = {}
Journal.Days = Days

local floor, huge, min, max = math.floor, math.huge, math.min, math.max
local match, gmatch = string.match, string.gmatch

Days.MIN_STAY = 30        -- seconds: shorter stays in a zone drop out of the zone sequence (border flicker)
Days.RARES_MAX = 5
Days.COMPANIONS_MAX = 10
Days.MOMENTS_MAX = 8
Days.DAYS_MAX = 4000
Days.NOTES_MAX = 3
Days.CAMPFIRES_MAX = 3

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

local function tzAt(index, t)
  local tzT = type(index.tzT) == "table" and index.tzT or {}
  local i = bsearch(tzT, t)
  if i == 0 then return finite(index.tz0) and index.tz0 or 0 end
  local v = index.tzV and index.tzV[i]
  return finite(v) and v or 0
end

function Days.keyOf(index, t)
  if type(index) ~= "table" or not finite(t) then return nil end
  return floor((t + tzAt(index, t)) / 86400)
end

function Days.bounds(index, key)
  if type(index) ~= "table" or not finite(key) then return nil end
  local tz = tzAt(index, key * 86400 + 43200 - (finite(index.tz0) and index.tz0 or 0))
  local t0 = key * 86400 - tz
  return t0, t0 + 86400
end

local function span(index, now)
  local sp = index.sessions
  if type(sp) ~= "table" or type(sp.t0) ~= "table" then return {}, {} end
  local a, b = {}, {}
  for i = 1, #sp.t0 do
    a[i] = sp.t0[i]
    b[i] = sp.t1[i] == huge and max(now, sp.t0[i]) or sp.t1[i]
  end
  return a, b
end

function Days.list(index, opts)
  local out = {}
  if type(index) ~= "table" then return out end
  local Index = Journal.Index
  if not Index then return out end
  local now = (opts and finite(opts.now)) and opts.now or time()
  local a, b = span(index, now)
  local seen = {}
  for i = 1, #a do
    local k0, k1 = Days.keyOf(index, a[i]), Days.keyOf(index, b[i])
    if k0 and k1 then
      for k = k0, min(k1, k0 + Days.DAYS_MAX) do seen[k] = true end
    end
  end
  local keys = {}
  for k in pairs(seen) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    if #out >= Days.DAYS_MAX then break end
    local t0, t1 = Days.bounds(index, k)
    local secs = Index.activeSeconds(index, t0, min(t1, now))
    if secs > 0 then
      local d, m, y = Index.dateOf(index, t0 + 3600)
      out[#out + 1] = { key = k, t0 = t0, t1 = t1, seconds = secs, day = d, month = m, year = y }
    end
  end
  return out
end

local function charTable(index, name)
  local char = index.char
  local t = type(char) == "table" and char[name]
  return type(t) == "table" and t or nil
end

local function snapName(index, group, key)
  local snaps = charTable(index, "snapshots")
  local g = snaps and snaps[group]
  local e = type(g) == "table" and g[key]
  local name = type(e) == "table" and e.name
  if type(name) ~= "string" or name == "" then return nil end
  name = ns.Sanitize.field(name)
  return name ~= "" and name or nil
end

local function npcName(index, npcID)
  local npcs = charTable(index, "npcs")
  local n = npcs and npcs[npcID]
  if type(n) ~= "string" or n == "" then return nil end
  n = ns.Sanitize.field(n)
  return n ~= "" and n or nil
end

local function questTitle(index, questID)
  local quests = charTable(index, "quests")
  local q = quests and quests[questID]
  local title = type(q) == "table" and q.title
  if type(title) ~= "string" or title == "" then return nil end
  title = ns.Sanitize.field(title)
  return title ~= "" and title or nil
end

local function each(list, t0, t1, fn)
  if type(list) ~= "table" then return end
  for i = 1, #list do
    local r = list[i]
    if r.t >= t0 and r.t < t1 then fn(r) end
  end
end

-- zone sequence from the trail (head "#~<epoch>~<mapID>" per block, a new block on every map change)

local function zoneOf(mapID)
  local Geo = Journal.Geo
  if Geo then
    for _, f in ipairs({ Geo.mainZoneOf, Geo.zoneOf }) do
      if type(f) == "function" then
        local ok, z = pcall(f, mapID)
        if ok and finite(z) and z > 0 then return floor(z) end
      end
    end
  end
  return mapID
end

local function trailStarts(index, t0, t1)
  local out = {}
  local trail = charTable(index, "trail") or {}
  for i = 1, #trail do
    local b = trail[i]
    if type(b) == "string" then
      local start, map = match(b, "^#~(%-?%d+)~(%d+)")
      start = start and tonumber(start)
      if start then
        local e = { t = start, map = tonumber(map), last = start }
        -- read the end of a stay (last point) only for blocks of the day: one block per map change, the trail is large
        if start >= t0 and start < t1 then
          local dt = match(b, "\n(%-?%d+)~[^\n]*$")
          if dt then e.last = start + tonumber(dt) end
        end
        out[#out + 1] = e
      end
    end
  end
  local Store = ns.Store
  local open = Store and Store.current == index.char and Store.trailBlock
  if type(open) == "table" and finite(tonumber(open.start)) and tonumber(open.mapID) and type(open.lines) == "table" and #open.lines > 0 then
    local dt = match(open.lines[#open.lines], "^(%-?%d+)~")
    out[#out + 1] = { t = tonumber(open.start), map = tonumber(open.mapID), last = tonumber(open.start) + (tonumber(dt) or 0) }
  end
  return out
end

local function zoneSequence(index, t0, t1)
  local seq = {}
  local blocks = trailStarts(index, t0, t1)
  for i, b in ipairs(blocks) do
    if b.t >= t0 and b.t < t1 and b.map and b.map > 0 then
      local stop = blocks[i + 1] and min(blocks[i + 1].t, b.last + 1) or (b.last + 1)
      local secs = max(0, min(stop, t1) - b.t)
      local zid = zoneOf(b.map)
      local prev = seq[#seq]
      if prev and prev.zoneID == zid then
        prev.seconds = prev.seconds + secs
      else
        seq[#seq + 1] = { mapID = b.map, zoneID = zid, t = b.t, seconds = secs }
      end
    end
  end
  -- short stays (border flicker) drop out unless they are the only one
  local out = {}
  for _, z in ipairs(seq) do
    if z.seconds >= Days.MIN_STAY or #seq == 1 then
      local prev = out[#out]
      if prev and prev.zoneID == z.zoneID then
        prev.seconds = prev.seconds + z.seconds
      else
        out[#out + 1] = z
      end
    end
  end
  for _, z in ipairs(out) do z.name = snapName(index, "maps", z.zoneID) or snapName(index, "maps", z.mapID) end
  return out
end

local function zoneFallback(index, t0, t1)
  local out = {}
  local Index = Journal.Index
  each(index.lists and index.lists.ZN, t0, t1, function(r)
    local mapID = Index.num(r, "ZN", "mapID")
    local zone = Index.num(r, "ZN", "zone") or mapID
    if mapID and zone then
      local prev = out[#out]
      if not (prev and prev.zoneID == zone) then
        out[#out + 1] = { mapID = floor(mapID), zoneID = floor(zone), t = r.t, seconds = 0, name = snapName(index, "maps", floor(zone)) }
      end
    end
  end)
  return out
end

-- kills of the day from the raw log (only the day's blocks): total and most-killed enemy

local function scanKills(index, t0, t1)
  local char = index.char
  local counts, total = {}, 0
  local function line(t, rest)
    if t < t0 or t >= t1 then return end
    total = total + 1
    local id = match(rest, "^(%d+)")
    if id then counts[id] = (counts[id] or 0) + 1 end
  end
  local log = type(char) == "table" and type(char.log) == "table" and char.log or {}
  local heads = {}
  for i = 1, #log do
    local b = log[i]
    heads[i] = type(b) == "string" and tonumber(match(b, "^#~(%-?%d+)~")) or false
  end
  local nextHead, following = {}, nil
  for i = #log, 1, -1 do
    nextHead[i] = following
    if heads[i] then following = heads[i] end
  end
  for i = 1, #log do
    local h = heads[i]
    if h and h < t1 and (not nextHead[i] or nextHead[i] > t0) then
      for dt, rest in gmatch(log[i], "\n(%-?%d+)~KI~?([^\n]*)") do line(h + tonumber(dt), rest) end
    end
  end
  local Store = ns.Store
  local ob = Store and Store.current == char and Store.block
  if type(ob) == "table" and finite(tonumber(ob.start)) and type(ob.lines) == "table" then
    for _, l in ipairs(ob.lines) do
      local dt, rest = match(l, "^(%-?%d+)~KI~?(.*)$")
      if dt then line(tonumber(ob.start) + tonumber(dt), rest) end
    end
  end
  local top, kinds = nil, 0
  for id, n in pairs(counts) do
    kinds = kinds + 1
    local idn = tonumber(id)
    if not top or n > top.n or (n == top.n and idn < top.npcID) then top = { npcID = idn, n = n } end
  end
  if top then top.name = npcName(index, top.npcID) end
  return { total = total, top = top, kinds = kinds }
end

local RANK = { boss = 3, rare = 2, elite = 1 }

function Days.facts(index, key, opts)
  if type(index) ~= "table" or not finite(key) then return nil end
  local Index = Journal.Index
  if not Index then return nil end
  local lists = index.lists or {}
  local now = (opts and finite(opts.now)) and opts.now or time()
  local t0, t1 = Days.bounds(index, key)
  local d, m, y = Index.dateOf(index, t0 + 3600)
  local f = { key = key, t0 = t0, t1 = t1, day = d, month = m, year = y }
  local upto = min(t1, now)

  f.seconds = (Index.activeSeconds(index, t0, upto))
  -- first and last played second from the session spans
  local a, b = span(index, now)
  for i = 1, #a do
    local s, e = max(a[i], t0), min(b[i], t1)
    if e > s and (e - s) > 0 then
      if not f.firstT or s < f.firstT then f.firstT = s end
      if not f.lastT or e > f.lastT then f.lastT = e end
    end
  end
  if f.firstT then
    local h, mi = Index.timeOfDay(index, f.firstT)
    f.firstClock = h and { h, mi } or nil
    h, mi = Index.timeOfDay(index, f.lastT)
    f.lastClock = h and { h, mi } or nil
  end

  f.zones = zoneSequence(index, t0, t1)
  if #f.zones == 0 then f.zones = zoneFallback(index, t0, t1) end

  f.instances = {}
  each(lists.IE, t0, t1, function(r)
    local id = Index.num(r, "IE", "instanceID")
    if id then
      f.instances[#f.instances + 1] = { instanceID = floor(id), name = snapName(index, "instances", floor(id)), t = r.t }
    end
  end)

  f.levels = {}
  each(lists.LV, t0, t1, function(r)
    local lv = Index.num(r, "LV", "level")
    if lv then
      f.levels[#f.levels + 1] = { level = floor(lv), t = r.t, mapID = Index.num(r, "LV", "mapID") }
      if not f.levelEnd or lv > f.levelEnd then f.levelEnd = floor(lv) end
    end
  end)

  f.kills = scanKills(index, t0, t1)
  local rare = {}
  each(lists.KI, t0, t1, function(r)
    local id = Index.num(r, "KI", "npcID")
    local cls = Index.str(r, "KI", "cls")
    local lv = Index.num(r, "KI", "level")
    local tag = (lv == -1 or cls == "worldboss") and "boss" or ((cls == "rare" or cls == "rareelite") and "rare") or (cls == "elite" and "elite") or nil
    if tag then
      local k = id and floor(id) or ("n:" .. (Index.str(r, "KI", "name") or "?"))
      local e = rare[k]
      if not e then
        local nm = id and npcName(index, floor(id)) or nil
        if not nm then
          local own = Index.str(r, "KI", "name")
          nm = own and ns.Sanitize.field(own) or nil
          if nm == "" then nm = nil end
        end
        e = { npcID = id and floor(id) or nil, name = nm, cls = tag, n = 0 }
        rare[k] = e
      end
      e.n = e.n + 1
      if RANK[tag] > RANK[e.cls] then e.cls = tag end
    end
  end)
  f.rares = {}
  for _, e in pairs(rare) do f.rares[#f.rares + 1] = e end
  table.sort(f.rares, function(x, y2)
    if RANK[x.cls] ~= RANK[y2.cls] then return RANK[x.cls] > RANK[y2.cls] end
    if x.n ~= y2.n then return x.n > y2.n end
    return (x.npcID or 0) < (y2.npcID or 0)
  end)
  while #f.rares > Days.RARES_MAX do f.rares[#f.rares] = nil end

  -- deaths with cause (DC follows DE within a few seconds)
  local dc = lists.DC or {}
  f.deaths = { count = 0, list = {} }
  each(lists.DE, t0, t1, function(r)
    local e = { t = r.t, mapID = Index.num(r, "DE", "mapID"), level = Index.num(r, "DE", "level") }
    for i = 1, #dc do
      local c = dc[i]
      if c.t >= r.t and c.t <= r.t + 15 then
        e.cause = Index.str(c, "DC", "cause")
        local npc = Index.num(c, "DC", "npcID")
        local nm = npc and npcName(index, floor(npc)) or nil
        if not nm then
          local src = Index.str(c, "DC", "source")
          nm = src and ns.Sanitize.field(src) or nil
          if nm == "" then nm = nil end
        end
        e.killer = nm
        break
      elseif c.t > r.t + 15 then
        break
      end
    end
    f.deaths.count = f.deaths.count + 1
    f.deaths.list[#f.deaths.list + 1] = e
  end)

  -- one named quest: the last turned in with a title
  f.quests = { count = 0 }
  each(lists.QT, t0, t1, function(r)
    f.quests.count = f.quests.count + 1
    local id = Index.num(r, "QT", "questID")
    local title = id and questTitle(index, floor(id)) or nil
    if title then f.quests.named = { questID = floor(id), title = title } end
  end)

  f.loot = { count = 0 }
  local best
  each(lists.LT, t0, t1, function(r)
    f.loot.count = f.loot.count + 1
    local item = Index.str(r, "LT", "item")
    local id = item and match(item, "^(%d+)")
    local q = Index.num(r, "LT", "quality") or -1
    if id and (not best or q >= best.quality) then
      best = { itemID = tonumber(id), quality = q, count = floor(Index.num(r, "LT", "count") or 1) }
    end
  end)
  if best then
    best.name = snapName(index, "items", best.itemID)
    if best.quality < 0 then best.quality = nil end
    f.loot.best = best
  end

  f.companions = { count = 0, list = {} }
  local C = Journal.Companions
  if C then
    local list = C.between(index, t0, upto, { now = now })
    f.companions.count = #list
    for i = 1, min(#list, Days.COMPANIONS_MAX) do f.companions.list[i] = list[i] end
  end

  f.campfires = { count = 0, list = {} }
  local FM = Journal.FireMates
  if FM and type(FM.rounds) == "function" then
    local ok, rounds = pcall(FM.rounds, index)
    if ok and type(rounds) == "table" then
      for _, rd in ipairs(rounds) do
        if rd.t >= t0 and rd.t < upto then
          f.campfires.count = f.campfires.count + 1
          if #f.campfires.list < Days.CAMPFIRES_MAX then
            f.campfires.list[#f.campfires.list + 1] = { t = rd.t, zone = rd.zone, who = FM.who(rd), again = FM.again(rd, "ich"), sim = rd.sim }
          end
        end
      end
    end
  end

  f.seals = {}
  local Chronik = Journal.Chronik
  if Chronik and type(Chronik.sealsOf) == "function" then
    local ok, res = pcall(Chronik.sealsOf, index)
    if ok and type(res) == "table" and type(res.list) == "table" then
      -- one entry per earned tier (a medal can take several tiers in a day), by time
      for _, s in ipairs(res.list) do
        for k = 1, (s.max or 1) do
          local st = s.steps and s.steps[k]
          if st and finite(st.at) and st.at >= t0 and st.at < t1 then
            f.seals[#f.seals + 1] = { id = s.id, title = s.title, tier = st.tier, at = st.at }
          end
        end
      end
      table.sort(f.seals, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        return a.id < b.id
      end)
    end
  end

  f.moments = {}
  each(lists.MO, t0, t1, function(r)
    if #f.moments < Days.MOMENTS_MAX then
      local v = Index.str(r, "MO", "value")
      f.moments[#f.moments + 1] = { kind = Index.str(r, "MO", "kind"), value = v and ns.Sanitize.field(v) or nil }
    end
  end)

  f.plansDone = {}
  each(lists.VE, t0, t1, function(r)
    local id = Index.num(r, "VE", "id")
    local text = Index.str(r, "VE", "text")
    f.plansDone[#f.plansDone + 1] = { id = id and floor(id) or nil, text = text and ns.Sanitize.field(text) or nil }
  end)

  -- notes of the day (own SV table, not in the index): titles only, raw text after NoteMarkup.cleanTitle
  f.notes = {}
  local N = Journal.Notes
  if N and N.between then
    local ok, list = pcall(N.between, t0, t1)
    if ok and type(list) == "table" then
      for i = 1, math.min(#list, Days.NOTES_MAX) do f.notes[i] = { id = list[i].id, title = list[i].title } end
    end
  end

  f.empty = (#f.zones == 0 and #f.levels == 0 and f.kills.total == 0 and f.deaths.count == 0 and f.quests.count == 0
    and f.loot.count == 0 and f.companions.count == 0 and f.campfires.count == 0 and #f.seals == 0 and #f.moments == 0 and #f.plansDone == 0
    and #f.instances == 0 and #f.notes == 0)
  return f
end
