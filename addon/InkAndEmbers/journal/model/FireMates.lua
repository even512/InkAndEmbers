-- Campfire companions: groups the campfire rounds (log line LF, index.lists.LF, written by collectors/Campfire.lua)
-- into rounds with people recognised from earlier fires, and a person list.
-- Names are raw SV text; display only via Sanitize.display (who/again return display-ready text). Pure read logic.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local FireMates = {}
Journal.FireMates = FireMates

local floor, huge = math.floor, math.huge
local format, match = string.format, string.match

FireMates.ROUNDS_MAX = 2000   -- rounds read (the newest are kept)
FireMates.PEOPLE_MAX = 500    -- people in the list (the most recently seen are kept)
FireMates.NAMES_MAX = 3       -- names shown in an entry, the rest as "und k weitere Gaeste"
FireMates.TIP_MAX = 8         -- people in the diary entry tooltip
FireMates.NAME_MAX = 48

local function finite(v)
  return type(v) == "number" and v == v and v ~= huge and v ~= -huge
end

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function shown(v, n)
  if type(v) ~= "string" or isSecret(v) then return nil end
  local S = ns.Sanitize
  return S and S.display(v, n or FireMates.NAME_MAX) or nil
end

-- zone names (snapshot "maps"; otherwise the map's main zone)

local function mapName(maps, id)
  if type(maps) ~= "table" or not finite(id) then return nil end
  local e = maps[id]
  if e == nil then e = maps[format("%.0f", id)] end
  if type(e) == "table" then e = e.name end
  if type(e) ~= "string" or e == "" or isSecret(e) then return nil end
  e = ns.Sanitize.field(e)
  return e ~= "" and e or nil
end

local function zoneOf(maps, mapID)
  if not finite(mapID) then return nil end
  local n = mapName(maps, mapID)
  if n then return n end
  local Geo = Journal.Geo
  if Geo and type(Geo.mainZoneOf) == "function" then
    local ok, z = pcall(Geo.mainZoneOf, mapID)
    if ok and finite(z) and z > 0 and z ~= mapID then return mapName(maps, floor(z)) end
  end
  return nil
end

-- people field of the LF line (format: collectors/Campfire.lua encodePeople): per person
-- "guid,name-realm,class,race,level,sex,how", ";"-separated, guid without the "Player-" prefix.
-- Read here too so the evaluator works without the collector; tests/lagerfeuer-chronik.test.mjs checks that both readers agree.

local GUID_PREFIX = "Player-"

local function splitOn(s, sep)
  local out, pos = {}, 1
  while true do
    local a = string.find(s, sep, pos, true)
    if not a then
      out[#out + 1] = string.sub(s, pos)
      return out
    end
    out[#out + 1] = string.sub(s, pos, a - 1)
    pos = a + 1
  end
end

local function cell(v)
  if type(v) ~= "string" or v == "" or v == "?" then return nil end
  return v
end

function FireMates.parsePeople(text)
  local list = {}
  if type(text) ~= "string" or text == "" or isSecret(text) then return list end
  for _, one in ipairs(splitOn(text, ";")) do
    local f = splitOn(one, ",")
    local guid, full = cell(f[1]), cell(f[2])
    if guid and string.sub(guid, 1, #GUID_PREFIX) ~= GUID_PREFIX then guid = GUID_PREFIX .. guid end
    if guid or full then
      local name, realm = full, nil
      if full then
        local n, r = match(full, "^(.-)%-([^%-]+)$")
        if n and n ~= "" then name, realm = n, r end
      end
      local level, sex = tonumber(cell(f[5]) or ""), tonumber(cell(f[6]) or "")
      list[#list + 1] = { guid = guid, full = full, name = name, realm = realm, class = cell(f[3]), race = cell(f[4]),
        level = level and floor(level) or nil, sex = (sex == 2 or sex == 3) and sex or nil, how = f[7] == "a" and "a" or "d" }
    end
  end
  return list
end

local cache = setmetatable({}, { __mode = "k" })

local function clone(e)
  return { n = e.n, lastT = e.lastT, lastMapID = e.lastMapID, lastZone = e.lastZone, lastLevel = e.lastLevel }
end

local function build(index)
  local out = { rounds = {}, people = {}, truncated = false }
  local Idx = Journal.Index
  if not Idx then return out end
  local char = type(index) == "table" and index.char
  local snaps = type(char) == "table" and char.snapshots
  local maps = type(snaps) == "table" and type(snaps.maps) == "table" and snaps.maps or nil

  local raw = {}
  for _, r in ipairs(Idx.list(index, "LF")) do
    if type(r) == "table" and finite(r.t) then raw[#raw + 1] = r end
  end
  table.sort(raw, function(a, b)
    if a.t ~= b.t then return a.t < b.t end
    return (finite(a.ln) and a.ln or 0) < (finite(b.ln) and b.ln or 0)
  end)
  if #raw > FireMates.ROUNDS_MAX then
    local keep = {}
    for i = #raw - FireMates.ROUNDS_MAX + 1, #raw do keep[#keep + 1] = raw[i] end
    raw, out.truncated = keep, true
  end

  local byGuid, byName, all = {}, {}, {}
  for i, r in ipairs(raw) do
    local mapID = Idx.num(r, "LF", "mapID")
    mapID = mapID and floor(mapID) or nil
    local zone = zoneOf(maps, mapID)
    local level = Idx.num(r, "LF", "level")
    local people = FireMates.parsePeople(Idx.str(r, "LF", "people"))
    local count = Idx.num(r, "LF", "count")
    local round = { t = r.t, ln = finite(r.ln) and r.ln or i, mapID = mapID, zone = zone, level = level and floor(level) or nil,
      seconds = Idx.num(r, "LF", "seconds"), said = Idx.num(r, "LF", "said"), people = {} }
    if Idx.num(r, "LF", "sim") == 1 then round.sim = true end -- trial round (retail simulation)
    local counted = {}
    for _, p in ipairs(people) do
      local e = (p.guid and byGuid[p.guid]) or (p.full and byName[p.full]) or nil
      if not counted[e or p] then
        counted[e or p] = true
        if e then p.past = clone(e) end
        if not e then
          e = { n = 0, firstT = r.t, firstMapID = mapID, firstZone = zone, level0 = p.level, visits = {} }
          all[#all + 1] = e
        end
        e.n = e.n + 1
        counted[e] = true
        e.guid, e.full = p.guid or e.guid, p.full or e.full
        e.name, e.realm = p.name or e.name, p.realm or e.realm
        e.class, e.race, e.sex = p.class or e.class, p.race or e.race, p.sex or e.sex
        e.level = p.level or e.level
        if e.level0 == nil then e.level0 = p.level end
        e.lastT, e.lastMapID, e.lastZone, e.lastLevel = r.t, mapID, zone, p.level or e.lastLevel
        e.lastSim = round.sim
        e.visits[#e.visits + 1] = { t = r.t, mapID = mapID, zone = zone, level = p.level, sim = round.sim }
        if p.guid then byGuid[p.guid] = e end
        if p.full then byName[p.full] = e end
        round.people[#round.people + 1] = p
      end
    end
    round.n = (count and count >= #round.people) and floor(count) or #round.people
    out.rounds[#out.rounds + 1] = round
  end

  for i, e in ipairs(all) do e.key = e.guid or e.full or ("#" .. i) end
  table.sort(all, function(a, b)
    if a.lastT ~= b.lastT then return a.lastT > b.lastT end
    if a.n ~= b.n then return a.n > b.n end
    return tostring(a.key) < tostring(b.key)
  end)
  if #all > FireMates.PEOPLE_MAX then
    for i = #all, FireMates.PEOPLE_MAX + 1, -1 do all[i] = nil end
    out.truncated = true
  end
  out.people = all
  return out
end

local function get(index)
  if type(index) ~= "table" then return { rounds = {}, people = {}, truncated = false } end
  local c = cache[index]
  if not c then
    local ok, res = pcall(build, index)
    c = ok and res or { rounds = {}, people = {}, truncated = false }
    cache[index] = c
  end
  return c
end

function FireMates.rounds(index) return get(index).rounds end

function FireMates.aggregate(index)
  local c = get(index)
  return { list = c.people, count = #c.people, rounds = #c.rounds, truncated = c.truncated }
end

local function liveStr(v)
  if type(v) ~= "string" or v == "" or isSecret(v) then return nil end
  return v
end

function FireMates.withLive(res, s)
  if type(res) ~= "table" then res = { list = {}, count = 0, rounds = 0, truncated = false } end
  if type(s) ~= "table" or s.active ~= true or type(s.people) ~= "table" then return res end
  local list = type(res.list) == "table" and res.list or {}
  local at = {}
  for i, p in ipairs(list) do
    if p.guid and not at[p.guid] then at[p.guid] = i end
    if p.full and not at["n:" .. p.full] then at["n:" .. p.full] = i end
  end
  local startT = finite(s.startT) and s.startT or nil
  local mapID = finite(s.mapID) and floor(s.mapID) or nil
  local zone = liveStr(s.zone)
  local used, live = {}, {}
  for _, q in ipairs(s.people) do
    local guid, full = type(q) == "table" and liveStr(q.guid) or nil, type(q) == "table" and liveStr(q.full) or nil
    if type(q) == "table" and q.sure == true and (guid or full) then
      local i = (guid and at[guid]) or (full and at["n:" .. full]) or nil
      local e = {}
      if i and not used[i] then
        used[i] = true
        for k, v in pairs(list[i]) do e[k] = v end
      else
        e = { key = guid or full, n = 0, firstT = startT, firstMapID = mapID, firstZone = zone, level0 = q.level, visits = {} }
      end
      e.guid, e.full = guid or e.guid, full or e.full
      e.name, e.realm = liveStr(q.name) or e.name, liveStr(q.realm) or e.realm
      e.class, e.race = liveStr(q.class) or e.class, liveStr(q.race) or e.race
      e.sex = (q.sex == 2 or q.sex == 3) and q.sex or e.sex
      e.level = finite(q.level) and floor(q.level) or e.level
      e.n = (tonumber(e.n) or 0) + 1
      e.lastT = startT or e.lastT
      e.live, e.liveSim, e.liveZone = true, s.sim == true, zone
      live[#live + 1] = e
    end
  end
  local out = {}
  for _, e in ipairs(live) do out[#out + 1] = e end
  for i, p in ipairs(list) do
    if not used[i] then out[#out + 1] = p end
  end
  return { list = out, count = #out, rounds = res.rounds, truncated = res.truncated,
    live = { sim = s.sim == true, zone = zone, mapID = mapID, startT = startT, n = #live } }
end

function FireMates.sorted(res, sort)
  local src = type(res) == "table" and type(res.list) == "table" and res.list or {}
  local out = {}
  for i, p in ipairs(src) do out[i] = p end
  if sort == "count" then
    table.sort(out, function(a, b)
      if a.n ~= b.n then return a.n > b.n end
      if a.lastT ~= b.lastT then return a.lastT > b.lastT end
      return tostring(a.key) < tostring(b.key)
    end)
  end
  return out -- "recent": the list is already ordered by last fire
end

-- texts (display-ready); locale scope "m.FireMates" (English in locales/enUS_model.lua)

local TX = ns.Locale.ns("m.FireMates", {
  andWord = " und ",
  more_one = "{names} und {n} weiterer Gast",
  more_other = "{names} und {n} weitere Gäste",
  count = "{text} ({n})",
  againMeZone = "{name} kenne ich schon vom Feuer in {zone}.",
  againMe = "{name} kenne ich schon von einem früheren Feuer.",
  againYouZone = "{name} kennt Ihr vom Feuer in {zone}.",
  againYou = "{name} kennt Ihr von einem früheren Feuer.",
})

-- first name; on Forever "Vorname Nachname" if the part after "-" is a surname, not a shard (Names.mateName)
local function firstName(p)
  local n = p.name or p.full
  if type(n) ~= "string" then return nil end
  local N = ns.Names
  if N then
    local raw = p.name and N.mateName(p.name, p.realm) or N.mateName(p.full)
    return shown(raw or n)
  end
  return shown(match(n, "^([^%-]+)") or n)
end

-- "Kuno", "Kuno und Mira", "Kuno, Mira und Bo"; from the fourth guest "Kuno, Mira, Bo und 2 weitere Gaeste", then the count "(4)"
function FireMates.who(round)
  if type(round) ~= "table" or type(round.people) ~= "table" or #round.people == 0 then return nil end
  local names = {}
  for _, p in ipairs(round.people) do
    if #names >= FireMates.NAMES_MAX then break end
    local s = firstName(p)
    if s then names[#names + 1] = s end
  end
  if #names == 0 then return nil end
  local total = tonumber(round.n) or #round.people
  if total < #round.people then total = #round.people end
  local more = total - #names
  local text
  if more > 0 then
    text = TX(ns.Locale.plural(more, "more_one", "more_other"), { names = table.concat(names, ", "), n = format("%d", more) })
  elseif #names == 1 then
    text = names[1]
  else
    text = table.concat(names, ", ", 1, #names - 1) .. TX.andWord .. names[#names]
  end
  if total >= 2 then text = TX("count", { text = text, n = format("%d", total) }) end
  return text
end

-- recognition: first person of the round already known from an earlier fire (zone of the last shared fire)
function FireMates.again(round, voice)
  if type(round) ~= "table" then return nil end
  for _, p in ipairs(round.people or {}) do
    local past = p.past
    local name = past and firstName(p)
    if name then
      local zone = shown(past.lastZone, 40)
      local key = (voice == "ich" and "againMe" or "againYou") .. (zone and "Zone" or "")
      return TX(key, { name = name, zone = zone })
    end
  end
  return nil
end

function FireMates.tipPeople(round)
  local out = {}
  for _, p in ipairs(type(round) == "table" and round.people or {}) do
    if #out >= FireMates.TIP_MAX then break end
    out[#out + 1] = p
  end
  return out
end
