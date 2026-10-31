-- Collector 'Rest' (campfire review; detection and gate only, the summary is computed by journal/model/Rest.lua). Rest starts when IsResting() (inn, city) or an aura
-- from Rest.FIRE_SPELLS / FIRE_PATTERNS becomes active. Read only out of combat (else after PLAYER_REGEN_ENABLED); secret values count as 'not resting' / 'no aura'. UNIT_AURA player is throttled.
-- The first state after login or reload is never a start. One RA line at most every REST_GAP s. Campfire and inn both active: kind = 'fire'. UI API: ns.onRestStart(fn), ns.Rest.shouldShow/markShown/state.
local _, ns = ...
local Core, Store = ns.Core, ns.Store

local floor = math.floor

-- chat messages (English: locales/enUS_core.lua, section 'col.Rest'; pattern: docs/i18n.md)
local T = ns.Locale.ns("col.Rest", {
  aurasCombat = "Auren: im Kampf nicht lesbar, bitte nach dem Kampf erneut abfragen.",
  aurasNoApi = "Auren: Schnittstelle C_UnitAuras nicht verfügbar.",
  aurasHeader = "Auren: %d am Spieler (%d Buffs, %d Debuffs)%s.",
  aurasHidden = ", %d gesperrt",
  auraLine = "  %s  %s%s%s",
  debuffTag = " [Debuff]",
  fireHit = " (Lagerfeuer-Treffer)",
  aurasSaved = "Die Liste steht auch in EveNChronicleDB.diag.auras (nach dem nächsten Sichern in der Datei).",
  never = "noch nie",
  dateFmt = "%d.%m.%Y %H:%M",
  idPart = " ID %s",
  fireStatus = "Lagerfeuer: bekannte IDs %s, zuletzt erkannt %s.",
})

local Rest = ns.Rest or {}
ns.Rest = Rest

Rest.REVIEW_GAP = 1200     -- seconds: at least this long since the last review (20 min)
Rest.COZY_FIRE = 7353      -- aura 'Cozy Fire' (campfire, radius 10 meters)
local REST_GAP = 300       -- seconds: at most one RA line (and one hook call) per 5 minutes
local AURA_THROTTLE = 1.0  -- seconds: UNIT_AURA player batched
local CHECK_DELAY = 0.5
local FIRST_READ = 2.0   -- seconds after start: first state if no event came by then

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a = pcall(fn, ...)
  if not ok then return nil end
  return a
end

local function inCombat()
  local v = call(InCombatLockdown)
  return not isSecret(v) and v == true
end

-- State (snapshots.state.rest = { last, shown })

function Rest.state()
  local char = Store.char()
  local st = char and char.snapshots and char.snapshots.state
  local r = type(st) == "table" and st.rest or nil
  if type(r) ~= "table" then return { last = nil, shown = nil } end
  return { last = num(r.last), shown = num(r.shown) }
end

local function saveState(last, shown)
  local t = {}
  if last then t.last = floor(last) end
  if shown then t.shown = floor(shown) end
  if next(t) == nil then return false end
  return Store.putSnapshot("state", "rest", t, true)
end

function Rest.markShown(now)
  now = num(now) or time()
  local st = Rest.state()
  return saveState(st.last, now)
end

function Rest.shouldShow(now)
  if inCombat() then return false, "combat" end
  now = num(now) or time()
  local shown = Rest.state().shown
  if shown and now - shown < Rest.REVIEW_GAP then return false, "recent" end
  return true
end

-- Hook for the UI

local startHooks = {}

function ns.onRestStart(fn)
  if type(fn) ~= "function" then return false end
  for _, f in ipairs(startHooks) do
    if f == fn then return false end
  end
  startHooks[#startHooks + 1] = fn
  return true
end

local function fireStart(info)
  for i = 1, #startHooks do Core.safe(startHooks[i], info) end
end

-- Collector

local Collector = {
  requires = { "IsResting" },
  events = { "PLAYER_UPDATE_RESTING", "PLAYER_REGEN_ENABLED" },
  unitEvents = { UNIT_AURA = { "player" } },
}
local handlers = {}


-- Campfire detection: known spell IDs (buffs and debuffs); only if none is found, narrow name patterns on helpful player auras.
-- An unknown ID found by name is remembered in diag.fireSeen[spellID] = name and treated like a known one from then on.

local function diagTable()
  local db = Store.db
  local d = type(db) == "table" and db.diag or nil
  return type(d) == "table" and d or nil
end

-- known rest auras: 7353 Retail 'Cozy Fire'; Forever (beta, Wowhead): 1289723 'Welcoming Campfire' (sitting in camp range, 1 min wait),
-- 1229741 'Camp Benefits' (buff after 1 min of rest, 1 h), 1229451 'Boosted Rest' (camp tent, runs as DEBUFF/HARMFUL).
-- Each counts as rest (kind 'fire'); the spell ID is src in the RA line.
Rest.FIRE_SPELLS = { Rest.COZY_FIRE, 1289723, 1229741, 1229451 }
-- auras that are never rest: 1283391 'Campfire Nearby' (merely a fire within 100 yards)
Rest.FIRE_IGNORE_IDS = { [1283391] = true }

-- name patterns only as a fallback when no known ID was found (lowercase, substring), de/en
Rest.FIRE_PATTERNS = {
  "lagerfeuer", "campfire", "camp benefits", "boosted rest", "cozy fire", "gemütliches feuer", "gemuetliches feuer",
  "lagervorteile", "erholsame rast",
}
-- names that match a pattern but are never rest (Campfire Nearby and its German equivalent)
Rest.FIRE_IGNORE = { "campfire nearby", "lagerfeuer in der nähe", "lagerfeuer in der naehe", "lagerfeuer in der nahe" }

local AURA_SCAN = 60           -- at most this many player buffs are scanned
local FIRE_SEEN_MAX = 20       -- at most this many IDs remembered by name in diag.fireSeen

local function knownFireID(id)
  if id == nil or Rest.FIRE_IGNORE_IDS[id] then return false end
  for _, k in ipairs(Rest.FIRE_SPELLS) do
    if k == id then return true end
  end
  local d = diagTable()
  return d ~= nil and type(d.fireSeen) == "table" and d.fireSeen[id] ~= nil
end

local function plainHas(s, list)
  for _, p in ipairs(list) do
    if string.find(s, p, 1, true) then return true end
  end
  return false
end

-- does the aura name match a campfire pattern? (strings only, never secret values)
function Rest.nameMatches(name)
  if isSecret(name) or type(name) ~= "string" then return false end
  local low = string.lower(name)
  if plainHas(low, Rest.FIRE_IGNORE) then return false end
  return plainHas(low, Rest.FIRE_PATTERNS)
end

-- player auras (filter 'HELPFUL' | 'HARMFUL') -> list { id = number|nil, name = text|nil }, number of secret entries.
-- nil, 'api' without C_UnitAuras.
local function scanAuras(filter)
  local A = type(C_UnitAuras) == "table" and C_UnitAuras or nil
  if not A then return nil, "api" end
  local list, hidden = {}, 0
  local function take(aura)
    if isSecret(aura) or type(aura) ~= "table" then
      hidden = hidden + 1
      return
    end
    local id = num(aura.spellId)
    local name = aura.name
    if isSecret(name) or type(name) ~= "string" then name = nil end
    if id == nil and name == nil then
      hidden = hidden + 1
      return
    end
    list[#list + 1] = { id = id and floor(id) or nil, name = name and ns.Sanitize.field(name) or nil }
  end
  if type(A.GetAuraDataByIndex) == "function" then
    for i = 1, AURA_SCAN do
      local ok, aura = pcall(A.GetAuraDataByIndex, "player", i, filter)
      if not ok or aura == nil then break end
      take(aura)
    end
  elseif type(A.ForEachAura) == "function" then
    pcall(A.ForEachAura, "player", filter, AURA_SCAN, take, true)
  else
    return nil, "api"
  end
  return list, hidden
end

-- /chronik auren: current player buffs (spellID + name) in chat and in diag.auras (timestamped)
function Rest.listAuras()
  if inCombat() then
    Core.print(T.aurasCombat)
    return false
  end
  local list, hidden = scanAuras("HELPFUL")
  if not list then
    Core.print(T.aurasNoApi)
    return false
  end
  local bad, badHidden = scanAuras("HARMFUL") -- debuffs count too (the 'Boosted Rest' tent is one)
  hidden = hidden + (badHidden or 0)
  local all = {}
  for _, a in ipairs(list) do all[#all + 1] = { id = a.id, name = a.name } end
  for _, a in ipairs(bad or {}) do all[#all + 1] = { id = a.id, name = a.name, harmful = true } end
  local d = diagTable()
  if d then
    local saved = {}
    for i, a in ipairs(all) do saved[i] = { id = a.id, name = a.name, harmful = a.harmful } end
    d.auras = { at = floor(time()), list = saved, hidden = hidden > 0 and hidden or nil }
  end
  Core.print(T("aurasHeader", #all, #list, #all - #list, hidden > 0 and T("aurasHidden", hidden) or ""))
  for _, a in ipairs(all) do
    local hit = knownFireID(a.id) or ((a.id == nil or not Rest.FIRE_IGNORE_IDS[a.id]) and Rest.nameMatches(a.name))
    Core.print(T("auraLine", a.id and tostring(a.id) or "?", a.name or "?", a.harmful and T.debuffTag or "",
      hit and T.fireHit or ""))
  end
  if d then Core.print(T.aurasSaved) end
  return true
end

-- remembers an ID found by name (diag.fireSeen) and the last hit (diag.fireLast)
local function noteFire(id, name)
  local d = diagTable()
  if not d then return end
  local static = false -- fixed IDs (FIRE_SPELLS) need no fireSeen entry
  for _, k in ipairs(Rest.FIRE_SPELLS) do
    if k == id then static = true end
  end
  if id and not static and type(name) == "string" and name ~= "" then
    if type(d.fireSeen) ~= "table" then d.fireSeen = {} end
    if d.fireSeen[id] == nil then
      local n = 0
      for _ in pairs(d.fireSeen) do n = n + 1 end
      if n < FIRE_SEEN_MAX then d.fireSeen[id] = name end
    end
  end
  d.fireLast = { at = floor(time()), id = id, name = name }
end

-- line for /chronik diag: known IDs and last hit
function Rest.fireStatus()
  local ids = {}
  for _, k in ipairs(Rest.FIRE_SPELLS) do ids[#ids + 1] = tostring(k) end
  local d = diagTable()
  local seen = {}
  if d and type(d.fireSeen) == "table" then
    for k, v in pairs(d.fireSeen) do seen[#seen + 1] = { id = k, name = v } end
    table.sort(seen, function(a, b) return tostring(a.id) < tostring(b.id) end)
  end
  for _, s in ipairs(seen) do ids[#ids + 1] = tostring(s.id) .. " (" .. tostring(s.name) .. ")" end
  local last = d and type(d.fireLast) == "table" and d.fireLast or nil
  local lastText = T.never
  if last and type(last.at) == "number" then
    lastText = date(T.dateFmt, last.at) .. (last.id and T("idPart", tostring(last.id)) or "")
      .. (last.name and (" " .. tostring(last.name)) or "")
  end
  return T("fireStatus", table.concat(ids, ", "), lastText)
end

-- campfire/tent aura on the player? -> yes, spellID (or nil). Secret values count as 'no'.
-- Known IDs first (buffs and debuffs); name patterns on the buffs only without a hit.
local function readFire()
  local A = type(C_UnitAuras) == "table" and C_UnitAuras or nil
  if not A then return false end
  -- fast path: known IDs directly (GetPlayerAuraBySpellID finds buffs and debuffs)
  local viaID = type(A.GetPlayerAuraBySpellID) == "function"
  if viaID then
    local ids = {}
    for _, k in ipairs(Rest.FIRE_SPELLS) do ids[#ids + 1] = k end
    local d = diagTable()
    if d and type(d.fireSeen) == "table" then
      for k in pairs(d.fireSeen) do
        if type(k) == "number" then ids[#ids + 1] = k end
      end
    end
    for _, id in ipairs(ids) do
      if not Rest.FIRE_IGNORE_IDS[id] then
        local ok, aura = pcall(A.GetPlayerAuraBySpellID, id)
        if ok and aura ~= nil and not isSecret(aura) then
          local name = type(aura) == "table" and not isSecret(aura.name) and type(aura.name) == "string" and aura.name or nil
          noteFire(id, name and ns.Sanitize.field(name) or nil)
          return true, id
        end
      end
    end
  end
  -- buff list: known IDs (also without GetPlayerAuraBySpellID), then name patterns; debuff list: known IDs only
  local buffs = scanAuras("HELPFUL")
  if buffs and not viaID then
    for _, a in ipairs(buffs) do
      if knownFireID(a.id) then
        noteFire(a.id, a.name)
        return true, a.id
      end
    end
  end
  local debuffs = not viaID and scanAuras("HARMFUL") or nil
  for _, a in ipairs(debuffs or {}) do
    if knownFireID(a.id) then
      noteFire(a.id, a.name)
      return true, a.id
    end
  end
  for _, a in ipairs(buffs or {}) do
    if not (a.id and Rest.FIRE_IGNORE_IDS[a.id]) and Rest.nameMatches(a.name) then
      noteFire(a.id, a.name)
      return true, a.id
    end
  end
  return false
end

-- resting? -> yes, kind ('inn' | 'fire'), src (spell ID of the aura, 'name' for a name hit without a readable ID, 'inn').
-- Secret values count as 'no'; the aura needs C_UnitAuras.
local function readRest()
  local fire, id = readFire()
  local r = call(IsResting)
  local inn = not isSecret(r) and r == true
  if fire then return true, "fire", id and tostring(floor(id)) or "name" end
  if inn then return true, "inn", "inn" end
  return false, nil
end

local function started(self, kind, src)
  local now = time()
  local prev = Rest.state().last
  if prev and now - prev < REST_GAP then return end
  local mapID, x, y = ns.Zone.here()
  local level = num(call(UnitLevel, "player"))
  local rested = num(call(GetXPExhaustion))
  if rested and rested <= 0 then rested = nil end
  Store.append("RA", kind, mapID, x, y, level, rested, src)
  saveState(now, Rest.state().shown)
  fireStart({ t = now, prev = prev, kind = kind, src = src, mapID = mapID, x = x, y = y, level = level and floor(level) or nil,
    rested = rested and floor(rested) or nil })
end

function Collector.check(self)
  if not Store.ready() then return end
  if inCombat() then
    self.deferred = true
    return
  end
  self.deferred = false
  local resting, kind, src = readRest()
  local before = self.resting
  self.resting = resting
  if resting and before == false then started(self, kind, src) end
end

local function scheduleCheck(self)
  if self.checkTimer then return end
  self.checkTimer = true
  if not Core.after(self, CHECK_DELAY, function(s)
    s.checkTimer = false
    s.check(s)
  end) then
    self.checkTimer = false
  end
end

handlers.PLAYER_UPDATE_RESTING = scheduleCheck

handlers.PLAYER_REGEN_ENABLED = function(self)
  if self.deferred then scheduleCheck(self) end
end

handlers.UNIT_AURA = function(self)
  if self.auraTimer then return end
  if inCombat() then
    self.deferred = true -- check after PLAYER_REGEN_ENABLED
    return
  end
  self.auraTimer = true
  if not Core.after(self, AURA_THROTTLE, function(s)
    s.auraTimer = false
    s.check(s)
  end) then
    self.auraTimer = false
  end
end

function Collector:onEvent(event, ...)
  local h = handlers[event]
  if h then h(self, ...) end
end

-- the first state (after login or reload) is never a start: it comes from the first event or after FIRST_READ at the latest
function Collector:init()
  self.resting = nil     -- nil = no state read yet
  self.deferred = false
  self.auraTimer = false
  self.checkTimer = false
  Core.after(self, FIRST_READ, function(s)
    if s.resting == nil and Store.ready() and not inCombat() then
      s.resting = (readRest())
    end
  end)
end

ns.RegisterCollector("Rest", Collector)
