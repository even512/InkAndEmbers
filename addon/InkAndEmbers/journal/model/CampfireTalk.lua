-- Campfire talk: picks the suggestions ("Zettel am Feuer") from CampfireTexts, the fire session and the index,
-- honouring the repeat rules. Pure logic; writes only the sent/rejected memory (snapshots.state.campfire).
-- session = { mapID, zone, startT, level, people = { { guid, name, class, race, sex, level, sure, past } } } (from
-- collectors/Campfire.lua, all optional); pick(session, index, state, opts) -> note | nil, text without "|", at most
-- 255 bytes.
-- Selection (1.0.2): tiers are mixed by weight (CampfireTalk.TIER_W), shared inside a category; with a sure guest at the fire
-- the last free slot is a guest note (opts.slots, notes with skip = true do not count as shown); opts.person = only notes
-- about that guest. Locks (session and saved state) use note.lock = template id, or template id + "@" + guest key for guest
-- templates. factSaid(session, note) drops the note's fact to tier 1 for the rest of the round.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local CampfireTalk = {}
Journal.CampfireTalk = CampfireTalk

local floor, huge = math.floor, math.huge
local gsub, find, match, sub, format = string.gsub, string.find, string.match, string.sub, string.format

CampfireTalk.OUT_MAX = 255          -- bytes per sent sentence (chat limit)
CampfireTalk.SOFT_MAX = 200         -- longer sentences (long names) are skipped instead of cut
CampfireTalk.NAME_MAX = 24          -- bytes per player name
CampfireTalk.TEXT_MAX = 60          -- bytes per foreign text (zone, enemy, quest ...)
CampfireTalk.PEOPLE_MAX = 10        -- people per round
CampfireTalk.SENT_LOCK = 86400      -- seconds a sent template stays locked
CampfireTalk.REJECT_LOCK = 7200     -- seconds a rejected template stays locked
CampfireTalk.RECENT_MAX = 200       -- lock keys in the ring buffer of sent templates (guest templates lock per guest)
CampfireTalk.LOCK_KEY_MAX = 96      -- bytes per lock key ("<id>" or "<id>@<person key>")
CampfireTalk.FRESH = 7200           -- seconds a fact counts as fresh
CampfireTalk.FAREWELL_AFTER = 600   -- session seconds after which farewell sentences become possible
CampfireTalk.DEFAULTS = { address = "du" }
CampfireTalk.ADDRESSES = { du = true, ihr = true, mix = true }
-- max age of a fact in seconds (after that "vorhin" is wrong)
CampfireTalk.MAX_AGE = { death = 4 * 3600, rare = 8 * 3600, quest = 8 * 3600, newzone = 12 * 3600, level = 12 * 3600, medal = 12 * 3600,
  elite = 8 * 3600, bag = 12 * 3600, profession = 12 * 3600, rep = 8 * 3600, subzone = 3 * 3600 }
-- selection: weight per tier (1 = filler or fact already talked about, 2 = guest or older fact, 3 = fresh fact or earlier fire);
-- inside a category the weight is shared by its candidates, so many templates (or many guests) do not crowd out the rest
CampfireTalk.TIER_W = { 1, 2, 3 }
CampfireTalk.SLOTS = 3              -- notes shown at once (guest guarantee: one of them is about a guest if one is sure)
CampfireTalk.STREAK_WINDOW = 1800   -- kill streak: kills in the last N seconds ...
CampfireTalk.STREAK_MIN = 12        -- ... at least this many

local ELLIPSIS = "\226\128\166"
local BAD = "[|%%{}<>\\]"

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function finite(v)
  return not isSecret(v) and type(v) == "number" and v == v and v ~= huge and v ~= -huge
end

local function Sanitize() return ns.Sanitize end

-- foreign text for use in sentences: no codes/control characters, single line, not truncated. nil if empty, truncated
-- or containing
-- characters that do not occur in player names, zones and quests ("|", "%", "{", "}", "<", ">", "\").
local function safeText(v, max)
  local S = Sanitize()
  if not S or isSecret(v) or type(v) ~= "string" then return nil end
  max = max or CampfireTalk.TEXT_MAX
  local s = S.plain(v, max)
  if not s or find(s, BAD) then return nil end
  if sub(s, -#ELLIPSIS) == ELLIPSIS and sub(v, -#ELLIPSIS) ~= ELLIPSIS then return nil end -- truncated
  return s
end

-- outgoing chat sentence: no codes, no "|" (removed, not doubled), no control characters, truncated UTF-8-safe
function CampfireTalk.clean(s)
  local S = Sanitize()
  if not S or isSecret(s) or type(s) ~= "string" then return nil end
  s = S.plain(s, CampfireTalk.OUT_MAX)
  if not s then return nil end
  s = gsub(s, "|", "")
  s = gsub(s, "%c", "")
  s = gsub(s, "  +", " ")
  s = gsub(s, "^ +", "")
  s = gsub(s, " +$", "")
  s = S.cut(s, CampfireTalk.OUT_MAX)
  if s == "" then return nil end
  return s
end

-- fill placeholders. vars1/vars2: name -> text tables; nil if one is missing. Replacement via function:
-- "%" in the replacement has no special meaning and replaced text is not evaluated again.
function CampfireTalk.fill(template, vars1, vars2)
  if type(template) ~= "string" then return nil end
  local missing = false
  local out = gsub(template, "{(%a+)}", function(k)
    local v = (vars1 and vars1[k]) or (vars2 and vars2[k])
    if type(v) ~= "string" or isSecret(v) then
      missing = true
      return ""
    end
    return v
  end)
  if missing then return nil end
  return out
end

function CampfireTalk.settings()
  local db = EveNChronicleDB
  local c = type(db) == "table" and not isSecret(db) and db.campfire or nil
  local a = type(c) == "table" and not isSecret(c) and c.address or nil
  if type(a) ~= "string" or isSecret(a) or not CampfireTalk.ADDRESSES[a] then a = CampfireTalk.DEFAULTS.address end
  return { address = a }
end

function CampfireTalk.setAddress(v)
  if isSecret(v) or type(v) ~= "string" or not CampfireTalk.ADDRESSES[v] then return false end
  local db = EveNChronicleDB
  if type(db) ~= "table" then return false end
  if type(db.campfire) ~= "table" then db.campfire = {} end
  db.campfire.address = v
  return true
end

-- state (snapshots.state.campfire = { recent = { id -> t }, rejected = { id -> t } })

local function cleanMap(m)
  local out = {}
  if type(m) == "table" and not isSecret(m) then
    for k, v in pairs(m) do
      if type(k) == "string" and not isSecret(k) and #k <= CampfireTalk.LOCK_KEY_MAX and finite(v) then out[k] = v end
    end
  end
  return out
end

function CampfireTalk.state()
  local Store = ns.Store
  local char = Store and type(Store.char) == "function" and Store.char() or nil
  local st = type(char) == "table" and type(char.snapshots) == "table" and char.snapshots.state or nil
  local c = type(st) == "table" and st.campfire or nil
  if type(c) ~= "table" then return { recent = {}, rejected = {} } end
  return { recent = cleanMap(c.recent), rejected = cleanMap(c.rejected) }
end

local function prune(map, lock, now, max)
  local n, oldestId, oldestT = 0, nil, huge
  for id, t in pairs(map) do
    if now - t >= lock and t <= now then
      map[id] = nil
    else
      n = n + 1
      if t < oldestT then oldestId, oldestT = id, t end
    end
  end
  if max and n > max and oldestId then
    map[oldestId] = nil
    return prune(map, lock, now, max)
  end
end

local function mark(state, field, lock, max, note, now)
  if type(state) ~= "table" or type(note) ~= "table" or type(note.id) ~= "string" then return false end
  local key = type(note.lock) == "string" and #note.lock <= CampfireTalk.LOCK_KEY_MAX and note.lock or note.id
  now = finite(now) and now or time()
  if type(state[field]) ~= "table" then state[field] = {} end
  state[field][key] = floor(now)
  prune(state[field], lock, now, max)
  return true
end

function CampfireTalk.markSent(state, note, now)
  return mark(state, "recent", CampfireTalk.SENT_LOCK, CampfireTalk.RECENT_MAX, note, now)
end

function CampfireTalk.markRejected(state, note, now)
  return mark(state, "rejected", CampfireTalk.REJECT_LOCK, nil, note, now)
end

local function persist(fn, note, now)
  local st = CampfireTalk.state()
  if not fn(st, note, now) then return false end
  local Store = ns.Store
  if not (Store and type(Store.putSnapshot) == "function") then return false end
  return Store.putSnapshot("state", "campfire", { recent = st.recent, rejected = st.rejected }, true)
end

function CampfireTalk.sent(note, now) return persist(CampfireTalk.markSent, note, now) end
function CampfireTalk.rejected(note, now) return persist(CampfireTalk.markRejected, note, now) end

local function blocked(map, id, lock, now)
  local t = type(map) == "table" and map[id] or nil
  if not finite(t) then return false end
  if t > now + 3600 then return false end -- clock was wrong: do not lock forever
  return now - t < lock
end

local function charOf(index)
  local c = type(index) == "table" and index.char or nil
  return type(c) == "table" and c or nil
end

local function mapName(index, mapID)
  if not finite(mapID) then return nil end
  mapID = floor(mapID)
  local char = charOf(index)
  local snaps = char and type(char.snapshots) == "table" and char.snapshots or nil
  local maps = snaps and type(snaps.maps) == "table" and snaps.maps or nil
  local e = maps and (maps[mapID] or maps[tostring(mapID)]) or nil
  local name = type(e) == "table" and safeText(e.name) or nil
  if name then return name end
  local Zone = ns.Zone
  if Zone and type(Zone.info) == "function" then
    local ok, info = pcall(Zone.info, mapID)
    if ok and type(info) == "table" and not isSecret(info) then return safeText(info.name) end
  end
  return nil
end

local function npcName(index, npcID)
  if not finite(npcID) then return nil end
  local char = charOf(index)
  local npcs = char and type(char.npcs) == "table" and char.npcs or nil
  local n = npcs and (npcs[npcID] or npcs[tostring(npcID)]) or nil
  return safeText(n)
end

function CampfireTalk.facts(index, now)
  local out = {}
  local Index = Journal.Index
  if type(index) ~= "table" or not Index then return out end
  now = finite(now) and now or time()
  local MAX_AGE, FRESH = CampfireTalk.MAX_AGE, CampfireTalk.FRESH

  local function inAge(r, kind)
    return type(r) == "table" and finite(r.t) and r.t <= now + 60 and now - r.t <= MAX_AGE[kind]
  end
  local function tooOld(r, kind)
    return type(r) ~= "table" or not finite(r.t) or now - r.t > MAX_AGE[kind]
  end
  local function put(kind, r, f)
    f.t, f.key, f.kind, f.fresh = r.t, kind .. ":" .. format("%.0f", r.t), kind, (now - r.t) <= FRESH
    out[kind] = f
  end

  local de = Index.list(index, "DE")
  local r = de[#de]
  if inAge(r, "death") then
    local f = { zone = mapName(index, Index.num(r, "DE", "mapID")) }
    if not f.zone and Index.deathInstance then
      f.zone = safeText(Index.instanceName(index, Index.deathInstance(index, r))) -- instance death: no map
    end
    local dc = Index.list(index, "DC")
    for i = #dc, 1, -1 do
      local c = dc[i]
      if not finite(c.t) or c.t < r.t then break end
      if c.t - r.t <= 30 then
        f.foe = npcName(index, Index.num(c, "DC", "npcID")) or safeText(Index.str(c, "DC", "source"))
        break
      end
    end
    put("death", r, f)
  end

  -- KI in the index holds only rare, elite and boss kills
  local ki = Index.list(index, "KI")
  for i = #ki, 1, -1 do
    local k = ki[i]
    if tooOld(k, "rare") or (out.rare and out.elite) then break end
    local cls = Index.str(k, "KI", "cls")
    local kind = (cls == "rare" or cls == "rareelite") and "rare" or (cls == "elite" and "elite") or nil
    if kind and not out[kind] and inAge(k, kind) then
      local name = npcName(index, Index.num(k, "KI", "npcID")) or safeText(Index.str(k, "KI", "name"))
      if name then put(kind, k, { name = name }) end
    end
  end

  local qt = Index.list(index, "QT")
  for i = #qt, 1, -1 do
    local q = qt[i]
    if tooOld(q, "quest") then break end
    local id = Index.num(q, "QT", "questID")
    local quests = charOf(index) and charOf(index).quests
    local e = type(quests) == "table" and id and (quests[id] or quests[tostring(id)]) or nil
    local title = type(e) == "table" and safeText(e.title) or nil
    if title then
      put("quest", q, { title = title })
      break
    end
  end

  local zn = Index.list(index, "ZN")
  for i = #zn, 1, -1 do
    local z = zn[i]
    if tooOld(z, "newzone") then break end
    if Index.num(z, "ZN", "mapType") == 3 then
      local name = mapName(index, Index.num(z, "ZN", "mapID"))
      if name then
        put("newzone", z, { name = name })
        break
      end
    end
  end

  local lv = Index.list(index, "LV")
  local l = lv[#lv]
  if inAge(l, "level") then
    local n = Index.num(l, "LV", "level")
    if finite(n) and n >= 1 and n <= 999 then put("level", l, { level = format("%.0f", floor(n)) }) end
  end

  -- moments (MO): first elite kill (marks the elite fact), first bag, profession, reputation tier
  local mo = Index.list(index, "MO")
  local MO_KIND = { first_elite = "elite", first_bag = "bag", profession = "profession", reputation = "rep" }
  local char0 = charOf(index)
  local snaps0 = char0 and type(char0.snapshots) == "table" and char0.snapshots or nil
  for i = #mo, 1, -1 do
    local m = mo[i]
    if type(m) ~= "table" or not finite(m.t) or now - m.t > 12 * 3600 then break end
    local kind = MO_KIND[Index.str(m, "MO", "kind") or ""]
    if kind == "elite" then
      if out.elite and math.abs(out.elite.t - m.t) <= 5 then out.elite.first = true end
    elseif kind and not out[kind] and inAge(m, kind) then
      if kind == "bag" then
        put("bag", m, {})
      elseif kind == "profession" then
        local name = Index.str(m, "MO", "value")
        name = name and not tonumber(name) and safeText(name) or nil
        if name then put("profession", m, { name = name }) end
      else
        local v = Index.str(m, "MO", "value")
        local id = v and tonumber(v)
        local facs = snaps0 and type(snaps0.factions) == "table" and snaps0.factions or nil
        local e = id and facs and (facs[id] or facs[tostring(id)]) or nil
        local name = type(e) == "table" and safeText(e.name) or (v and not id and safeText(v)) or nil
        if name then put("rep", m, { name = name }) end
      end
    end
  end

  local sz = Index.list(index, "SZ")
  local z = sz[#sz]
  if inAge(z, "subzone") then
    local name = safeText(Index.str(z, "SZ", "name"))
    if name then put("subzone", z, { name = name }) end
  end

  if type(Index.killsBetween) == "function" then
    local okk, n = pcall(Index.killsBetween, index, now - CampfireTalk.STREAK_WINDOW, now)
    if okk and finite(n) and n >= CampfireTalk.STREAK_MIN and n <= 999 then
      put("streak", { t = now }, { kills = format("%.0f", floor(n)) })
      out.streak.key = "streak"
    end
  end

  local char = charOf(index)
  local medals = char and type(char.snapshots) == "table" and type(char.snapshots.medals) == "table" and char.snapshots.medals or nil
  if medals then
    local Chronik = Journal.Chronik
    local byId = Chronik and type(Chronik.SEAL_BY_ID) == "table" and Chronik.SEAL_BY_ID or nil
    local bestT, bestTitle
    for key, e in pairs(medals) do
      if type(key) == "string" and type(e) == "table" and finite(e.t) and inAge(e, "medal") and (not bestT or e.t > bestT) then
        local seal = byId and byId[match(key, "^(.-):") or key] or nil
        local title = type(seal) == "table" and safeText(seal.title) or nil
        if title then bestT, bestTitle = e.t, title end
      end
    end
    if bestT then put("medal", { t = bestT }, { title = bestTitle }) end
  end
  return out
end

local function personName(raw)
  if isSecret(raw) or type(raw) ~= "string" then return nil end
  local first = match(raw, "^([^%-]+)")
  if not first then return nil end
  local n = safeText(first, CampfireTalk.NAME_MAX)
  -- player names are letters only: whitespace, digits or ASCII punctuation (left over from codes) -> not a name
  if not n or find(n, "[%s%p%d]") then return nil end
  return n
end

-- key of a session person as used in notes (note.person) and lock keys: guid, else "n:<first name>"
function CampfireTalk.personKey(p)
  if type(p) ~= "table" or isSecret(p) then return nil end
  local guid = p.guid
  if type(guid) == "string" and not isSecret(guid) and #guid <= 64 and not find(guid, "%c") then return guid end
  local name = personName(p.name)
  return name and ("n:" .. name) or nil
end

local function token(v)
  if isSecret(v) or type(v) ~= "string" or #v > 32 or not find(v, "^%a+$") then return nil end
  return v
end

local function sexOf(v)
  if isSecret(v) then return nil end
  if v == 3 or v == "f" or v == "female" or v == "FEMALE" then return "f" end
  if v == 2 or v == "m" or v == "male" or v == "MALE" then return "m" end
  return nil
end

-- bring a session person into a checked state (nil if nothing usable)
local function normPerson(p, index)
  if type(p) ~= "table" or isSecret(p) then return nil end
  local T = Journal.CampfireTexts
  local out = { sure = p.sure == true, name = personName(p.name) }
  local guid = p.guid
  if type(guid) == "string" and not isSecret(guid) and #guid <= 64 and not find(guid, "%c") then out.guid = guid end
  out.key = CampfireTalk.personKey(p)
  out.raceToken, out.classToken = token(p.race), token(p.class)
  if finite(p.level) and p.level >= 1 and p.level <= 999 then out.level = floor(p.level) end
  -- class and race names in the active language (CampfireTexts.className/raceName, article "einen"/"a"/"an")
  local sex = sexOf(p.sex)
  if T and sex and type(p.class) == "string" and not isSecret(p.class) then
    out.klasse, out.einKlasse = T.className(p.class, sex)
  end
  out.volk = T and type(p.race) == "string" and not isSecret(p.race) and T.raceName(p.race) or nil
  local past = p.past
  if type(past) == "table" and not isSecret(past) and finite(past.count) and past.count >= 1 then
    out.past = { count = floor(past.count), level = finite(past.level) and floor(past.level) or nil,
      zone = safeText(past.zone) or mapName(index, past.mapID) }
  end
  return out
end

local usedBySession = setmetatable({}, { __mode = "k" })   -- session -> { lock key -> true } (shown this round)
local saidBySession = setmetatable({}, { __mode = "k" })   -- session -> { fact kind -> true } (sent this round)

function CampfireTalk.resetSession(session)
  if type(session) == "table" then
    usedBySession[session] = nil
    saidBySession[session] = nil
  end
end

-- a note was said in this round: its fact (kind) drops to the lowest tier for the rest of the round
function CampfireTalk.factSaid(session, note)
  if type(session) ~= "table" or isSecret(session) or type(note) ~= "table" or type(note.fact) ~= "string" then return false end
  local kind = match(note.fact, "^(%a+)")
  if not kind then return false end
  local said = saidBySession[session] or {}
  said[kind] = true
  saidBySession[session] = said
  return true
end

-- lock key: the template id; for guest templates template id plus guest
local function lockKey(def, person)
  if not (def.person and person and person.key) then return def.id end
  return sub(def.id .. "@" .. person.key, 1, CampfireTalk.LOCK_KEY_MAX)
end

local function dayPart(hour)
  if not finite(hour) then return nil end
  if hour >= 5 and hour < 10 then return "morning" end
  if hour >= 10 and hour < 17 then return "day" end
  if hour >= 17 and hour < 21 then return "evening" end
  return "night"
end

local function ownLevel(session, opts)
  local v = opts.level
  if not finite(v) then v = type(session) == "table" and session.level or nil end
  if not finite(v) and type(UnitLevel) == "function" then
    local ok, lv = pcall(UnitLevel, "player")
    if ok then v = lv end
  end
  if finite(v) and v >= 1 and v <= 999 then return floor(v) end
  return nil
end

-- own race/class token (opts.race / opts.class, else UnitRace / UnitClass second return)
local function ownToken(opts, field, fn)
  local v = token(opts[field])
  if v then return v end
  local f = rawget(_G, fn)
  if type(f) == "function" then
    local ok, _, tok = pcall(f, "player")
    if ok then return token(tok) end
  end
  return nil
end

local function gameHour(opts)
  if finite(opts.hour) then return opts.hour end
  if type(GetGameTime) == "function" then
    local ok, h = pcall(GetGameTime)
    if ok and finite(h) then return h end
  end
  return nil
end

local function sessionZone(session, index)
  if type(session) == "table" then
    local z = safeText(session.zone)
    if z then return z end
    local m = mapName(index, session.mapID)
    if m then return m end
  end
  if type(C_Map) == "table" and type(C_Map.GetBestMapForUnit) == "function" then
    local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
    if ok then return mapName(index, id) end
  end
  return nil
end

local function chooseForm(address, rnd)
  if address == "ihr" then return "ihr" end
  if address == "mix" then return rnd() < 0.5 and "du" or "ihr" end
  return "du"
end

local function weightedPick(list, rnd)
  local total = 0
  for _, c in ipairs(list) do total = total + c.w end
  if total <= 0 then return nil end
  local x = rnd() * total
  for i, c in ipairs(list) do
    x = x - c.w
    if x < 0 then return i end
  end
  return #list
end

function CampfireTalk.pick(session, index, state, opts)
  local T = Journal.CampfireTexts
  if not T then return nil end
  opts = type(opts) == "table" and opts or {}
  local sess = type(session) == "table" and not isSecret(session) and session or nil
  local now = finite(opts.now) and opts.now or time()
  local rnd = type(opts.rnd) == "function" and opts.rnd or math.random
  local address = opts.address
  if type(address) ~= "string" or not CampfireTalk.ADDRESSES[address] then address = CampfireTalk.settings().address end

  local ok, facts = true, opts.facts
  if type(facts) ~= "table" then ok, facts = pcall(CampfireTalk.facts, index, now) end
  if not ok or type(facts) ~= "table" then facts = {} end

  local people, nearby, others = {}, 0, 0
  local rawPeople = sess and type(sess.people) == "table" and not isSecret(sess.people) and sess.people or {}
  for i = 1, CampfireTalk.PEOPLE_MAX do
    local p = rawPeople[i]
    if p == nil then break end
    local np = normPerson(p, index)
    if np then
      nearby = nearby + 1
      if np.sure then
        others = others + 1
        if np.name and np.key and (not opts.follow or np.key == opts.speaker) then people[#people + 1] = np end
      end
    end
  end

  local startT = sess and finite(sess.startT) and sess.startT or nil
  local sinceStart = startT and (now - startT) or nil
  local ctx = {
    part = dayPart(gameHour(opts)), sinceStart = sinceStart, others = others, nearby = nearby,
    myLevel = ownLevel(sess, opts), myRace = ownToken(opts, "race", "UnitRace"), myClass = ownToken(opts, "class", "UnitClass"),
    topic = opts.follow and type(opts.topic) == "string" and opts.topic or nil,
    farewell = opts.farewell == true or (sinceStart ~= nil and sinceStart >= CampfireTalk.FAREWELL_AFTER),
    facts = facts,
  }

  -- shared placeholders (foreign texts already checked)
  local zone = sessionZone(sess, index)
  local base = { zone = zone }
  if facts.death then base.todort, base.toter = facts.death.zone, facts.death.foe end
  if facts.rare then base.rare = facts.rare.name end
  if facts.quest then base.quest = facts.quest.title end
  if facts.newzone then base.neuzone = facts.newzone.name end
  if facts.level then base.stufe = facts.level.level end
  if facts.medal then base.medaille = facts.medal.title end
  if facts.elite then base.elite = facts.elite.name end
  if facts.profession then base.beruf = facts.profession.name end
  if facts.rep then base.fraktion = facts.rep.name end
  if facts.subzone then base.unterzone = facts.subzone.name end
  if facts.streak then base.kills = facts.streak.kills end
  if others >= 1 then base.anzahl = T.countWord(others + 1) end

  -- locks
  local visIds, visCats, visFacts, visPeople = {}, {}, {}, {}
  local shown, guestShown = 0, false
  if type(opts.visible) == "table" then
    for _, n in ipairs(opts.visible) do
      if type(n) == "table" then
        if n.id then visIds[n.id] = true end
        if n.cat then visCats[n.cat] = true end
        if n.fact then visFacts[n.fact] = true end
        -- notes marked skip were drawn but not shown (did not fit): they block their template, but neither the guest nor
        -- the slot counts as shown
        if not n.skip then
          if n.person then visPeople[n.person] = true end
          shown = shown + 1
          if n.person then guestShown = true end
        end
      end
    end
  end
  local used = sess and usedBySession[sess] or nil
  local said = sess and saidBySession[sess] or nil
  local recent, rejected = type(state) == "table" and state.recent or nil, type(state) == "table" and state.rejected or nil
  local follow = opts.follow == true

  local cands = {}
  local function consider(def, person)
    local pv
    if person then
      pv = { name = person.name, klasse = person.klasse, einKlasse = person.einKlasse, volk = person.volk,
        stufe = person.level and format("%.0f", person.level) or nil }
      if person.past then
        pv.altzone = person.past.zone
        pv.mal = T.ordinal(person.past.count + 1)
        pv.altstufe = person.past.level and format("%.0f", person.past.level) or nil
      end
    end
    local factDef = def.fact and facts[def.fact] or nil
    if def.fact and not factDef then return end
    if factDef and visFacts[factDef.key] then return end
    ctx.person = person
    if def.when then
      local okw, res = pcall(def.when, ctx)
      if not okw or not res then return end
    end
    local text = CampfireTalk.fill(T.text(def, "du"), pv, base)
    if not text then return end
    local clean = CampfireTalk.clean(text)
    if not clean or #clean > CampfireTalk.SOFT_MAX then return end
    local tier = 1
    if factDef then
      tier = factDef.fresh and 3 or 2
      -- the fact was already talked about this round: lowest tier (topic follow-ups stay, they continue the topic)
      if not follow and said and said[factDef.kind or ""] then tier = 1 end
    elseif person then
      tier = def.cat == "past" and 3 or 2
    end
    cands[#cands + 1] = { def = def, pv = pv, person = person, fact = factDef, tier = tier, w = def.w,
      lock = lockKey(def, person) }
  end

  local avoid = type(opts.avoid) == "table" and opts.avoid or {}
  -- opts.person: only notes about this guest (a guest who just sat down)
  local wantPerson = not follow and type(opts.person) == "string" and opts.person or nil
  local function free(lock)
    return not (used and used[lock]) and not blocked(recent, lock, CampfireTalk.SENT_LOCK, now)
      and not blocked(rejected, lock, CampfireTalk.REJECT_LOCK, now)
  end
  for _, def in ipairs(T.list) do
    local ok
    if follow then
      ok = def.cat == "follow" and not visIds[def.id] and not avoid[def.id]
    else
      -- for a late guest the guest categories stay open even if another guest's note shows one (second late guest)
      ok = def.cat ~= "follow" and not visIds[def.id] and (not visCats[def.cat] or (wantPerson ~= nil and def.person))
    end
    if ok then
      if def.person then
        for _, p in ipairs(people) do
          if not visPeople[p.key] then
            local lock = lockKey(def, p)
            if follow and not blocked(rejected, lock, CampfireTalk.REJECT_LOCK, now) then consider(def, p)
            elseif not follow and free(lock) then consider(def, p) end
          end
        end
      elseif follow then
        if not blocked(rejected, def.id, CampfireTalk.REJECT_LOCK, now) then consider(def, nil) end
      elseif free(def.id) then
        consider(def, nil)
      end
    end
  end

  -- guest guarantee: sure guests at the fire and no guest note among the shown ones yet -> the last free slot is a guest note
  local slots = finite(opts.slots) and opts.slots or CampfireTalk.SLOTS
  local needGuest = not follow and #people > 0 and not guestShown and shown >= slots - 1
  if wantPerson or needGuest then
    local only = {}
    for _, c in ipairs(cands) do
      if c.person and (not wantPerson or c.person.key == wantPerson) then only[#only + 1] = c end
    end
    if wantPerson or #only > 0 then cands = only end
  end

  if not follow then
    -- mix the tiers: weight = template weight x tier weight, shared inside the category
    local perCat = {}
    for _, c in ipairs(cands) do perCat[c.def.cat] = (perCat[c.def.cat] or 0) + 1 end
    for _, c in ipairs(cands) do c.w = c.w * CampfireTalk.TIER_W[c.tier] / perCat[c.def.cat] end
  end

  while #cands > 0 do
    local pool, map = cands, nil
    if follow then
      -- follow-ups: the highest tier wins (a topic follow-up continues what was just said)
      local best = 0
      for _, c in ipairs(cands) do if c.tier > best then best = c.tier end end
      pool, map = {}, {}
      for i, c in ipairs(cands) do
        if c.tier == best then
          pool[#pool + 1] = c
          map[#pool] = i
        end
      end
    end
    local pickIdx = weightedPick(pool, rnd) or 1
    local c = pool[pickIdx]
    table.remove(cands, map and map[pickIdx] or pickIdx)

    local form = chooseForm(address, rnd)
    local text = CampfireTalk.clean(CampfireTalk.fill(T.text(c.def, form == "ihr" and "ihr" or "du"), c.pv, base))
    local whyTpl = T.text(c.def, "why")
    local why = CampfireTalk.clean(CampfireTalk.fill(whyTpl, c.pv, base) or whyTpl)
    if text and #text <= CampfireTalk.SOFT_MAX and why and not find(why, "{") then
      if sess then
        used = used or {}
        used[c.lock] = true
        usedBySession[sess] = used
      end
      return { id = c.def.id, cat = c.def.cat, text = text, why = why, fact = c.fact and c.fact.key or nil,
        person = c.person and c.person.key or nil, form = form, tier = c.tier, lock = c.lock }
    end
  end
  return nil
end

function CampfireTalk.pickSet(session, index, state, opts, n)
  local out = {}
  opts = type(opts) == "table" and opts or {}
  local o = {}
  for k, v in pairs(opts) do o[k] = v end
  n = finite(n) and floor(n) or 3
  for _ = 1, n do
    o.visible = out
    local note = CampfireTalk.pick(session, index, state, o)
    if not note then break end
    out[#out + 1] = note
  end
  return out
end
