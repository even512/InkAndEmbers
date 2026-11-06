-- Collector 'Combat': every kill compactly, combat summary, narrow wins as an approximation.
-- No combat log (COMBAT_LOG_EVENT_UNFILTERED is blocked, never registered): kills from PARTY_KILL (fallback UNIT_DIED + kill XP, then kill XP alone). npcID always from the GUID.
-- Name, level, classification from a bounded unit cache, then UnitTokenFromGUID. UnitHealth('player') is secret in combat: 'narrow win' = under 10 % health at combat end (approximation).
local _, ns = ...
local Core, Store = ns.Core, ns.Store

local floor, match = math.floor, string.match

-- chat messages (English: locales/enUS_core.lua, section 'col.Combat'; pattern: docs/i18n.md)
local T = ns.Locale.ns("col.Combat", {
  meterOn = "Ich habe die Schadensanzeige für Euch eingeschaltet, damit Eure Kämpfe Schaden und Heilung festhalten. "
    .. "Lieber nicht? In den Einstellungen (Optionen, AddOns, Ink & Embers) den Haken „Schadensanzeige automatisch einschalten“ entfernen (oder /chronik messer aus).",
  autoOnCombat = "Schadensmesser-Automatik an. Die Option wird nach dem Kampf geprüft.",
  autoOnRefused = "Schadensmesser-Automatik an, aber der Client lässt die Option nicht ändern. Bitte in den Optionen unter Schadensanzeige selbst einschalten.",
  autoOn = "Schadensmesser-Automatik an.",
  autoOff = "Schadensmesser-Automatik aus. Die Option Schadensanzeige in den Blizzard-Optionen bleibt, wie sie ist.",
  autoState = "Schadensmesser-Automatik ist %s. /chronik messer an oder /chronik messer aus",
  on = "an",
  off = "aus",
  nowMissing = "fehlt",
  nowUnavailable = "nicht verfügbar",
  nowAvailable = "verfügbar",
  nowUnclear = "unklar",
  unknown = "unbekannt",
  status = "Schadensmesser: %s",
  statusLevel = " (Stufe %s)",
  statusLast = ", letzter Kampf: %s",
  statusNoFight = ", noch kein Kampf seit dem Laden",
  statusOption = ", Option %s, Automatik %s",
  enabled = "eingeschaltet",
  refused = "abgelehnt",
})

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function str(v)
  if isSecret(v) or type(v) ~= "string" or v == "" then return nil end
  return v
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c
end

local KILL_WAIT = 1.0   -- seconds: a kill waits this long for its XP message (and vice versa)
local DIED_KEEP = 3.0   -- seconds: UNIT_DIED stays usable for a message without PARTY_KILL
local CACHE_MAX = 200   -- entries in the unit cache, the oldest drop out
local SEEN_MAX = 100    -- last counted GUIDs (no kill twice)
local METER_DELAY = 0.5 -- seconds after combat end until the damage meter is read
local CLOSE_PCT = 10    -- narrow win: below this percent health at combat end
local METER_ENSURE_DELAY = 3 -- seconds after start until the damage meter is enabled

local function playerLevel()
  return num(call(UnitLevel, "player"))
end

local function here()
  return ns.Zone.here()
end

-- npcID from a creature/vehicle GUID; players, pets and objects have none
local function npcIdOf(guid)
  if not str(guid) then return nil end
  local kind, id = match(guid, "^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  if (kind == "Creature" or kind == "Vehicle") and id then return tonumber(id) end
  return nil
end

local Combat = {
  requires = { "UnitGUID" },
  events = {
    "PARTY_KILL", "UNIT_DIED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD", "PLAYER_LOGOUT",
  },
  signals = { "FC_XP" },
}
local handlers = {}

function Combat:init()
  self.cache, self.cacheOrder, self.cacheHead, self.cacheTail, self.cacheCount = {}, {}, 1, 1, 0
  self.seen, self.seenOrder = {}, {}
  self.pending = {} -- recognised kills still waiting for their XP
  self.orphans = {} -- kill XP without a recognised kill (waits briefly for PARTY_KILL)
  self.died = {}    -- { guid, at } from UNIT_DIED
  self.fight = InCombatLockdown() and { start = GetTime(), kills = 0 } or nil
  self.meterDone = false
  -- enable the damage meter (outside combat): shortly after start, in combat only after PLAYER_REGEN_ENABLED
  Core.after(self, METER_ENSURE_DELAY, function(s) s.meterDone = ns.meterEnsure() ~= "kampf" end)
end

-- Unit cache

local function trimCache(self)
  local order = self.cacheOrder
  while self.cacheCount > CACHE_MAX do
    local old = order[self.cacheHead]
    order[self.cacheHead] = nil
    self.cacheHead = self.cacheHead + 1
    if old ~= nil and self.cache[old] then
      self.cache[old] = nil
      self.cacheCount = self.cacheCount - 1
    end
  end
  if self.cacheHead > 1000 then -- compact the order list
    local fresh = {}
    for i = self.cacheHead, self.cacheTail - 1 do
      if order[i] ~= nil then fresh[#fresh + 1] = order[i] end
    end
    self.cacheOrder, self.cacheHead, self.cacheTail = fresh, 1, #fresh + 1
  end
end

local function readUnit(unit)
  return str(call(UnitName, unit)), num(call(UnitLevel, unit)), str(call(UnitClassification, unit))
end

local function remember(self, unit)
  if not str(unit) then return end
  local guid = str(call(UnitGUID, unit))
  if not guid or not npcIdOf(guid) then return end
  local name, level, cls = readUnit(unit)
  if not (name or level or cls) then return end -- all secret: remember nothing
  local e = self.cache[guid]
  if not e then
    e = {}
    self.cache[guid] = e
    self.cacheOrder[self.cacheTail] = guid
    self.cacheTail = self.cacheTail + 1
    self.cacheCount = self.cacheCount + 1
    trimCache(self)
  end
  e.name, e.level, e.cls = name or e.name, level or e.level, cls or e.cls
end

-- name, level, classification for a GUID: cache first, then the unit (if still visible)
local function describe(self, guid)
  local e = self.cache[guid]
  local name, level, cls = e and e.name, e and e.level, e and e.cls
  if not (name and level and cls) then
    local unit = str(call(UnitTokenFromGUID, guid))
    if unit then
      local n, l, c = readUnit(unit)
      name, level, cls = name or n, level or l, cls or c
    end
  end
  return name, level, cls
end

local function markSeen(self, guid)
  self.seen[guid] = true
  local order = self.seenOrder
  order[#order + 1] = guid
  if #order > SEEN_MAX then
    self.seen[table.remove(order, 1)] = nil
  end
end

-- who landed the killing blow? Secret stays secret (becomes '?').
local function attackerKind(attacker)
  if isSecret(attacker) then return attacker end
  if not str(attacker) then return nil end
  if attacker == str(call(UnitGUID, "player")) then return "self" end
  local pet = str(call(UnitGUID, "pet"))
  if pet and attacker == pet then return "pet" end
  return "group"
end

-- Kills

local function finishKill(self, k)
  if k.done then return end
  k.done = true
  local id = num(k.npcID)
  if id and k.name then Store.putText("npcs", id, k.name) end
  -- position on every kill (extended): x/y at the time of the kill, empty if the map withholds them (instances).
  -- Old lines without x/y stay valid; readers treat missing fields like empty ones.
  Store.append("KI", k.npcID, k.level, k.cls, k.mapID, k.xp, k.by, k.via, (id == nil) and k.name or nil, playerLevel(), k.x, k.y)
  Core.emit("FC_KILL", k.npcID, k.level, k.cls, k.by, k.name) -- name last (to-do counters match by name)
end

local function removeFrom(list, item)
  for i = #list, 1, -1 do
    if list[i] == item then
      table.remove(list, i)
      return true
    end
  end
  return false
end

-- new kill: counts in the running combat, waits briefly for the XP (or takes one that already arrived).
local function addKill(self, k)
  if self.fight then self.fight.kills = self.fight.kills + 1 end
  k.at = GetTime()
  k.mapID, k.x, k.y = here()
  Core.emit("FC_KILL_SEEN", k.npcID) -- at once (Loot assigns auto-loot); FC_KILL follows after the XP wait
  for i, o in ipairs(self.orphans) do
    if not o.used and (o.name == nil or k.name == nil or o.name == k.name) then
      o.used = true
      table.remove(self.orphans, i)
      k.xp, k.name = o.xp, k.name or o.name
      finishKill(self, k)
      return
    end
  end
  self.pending[#self.pending + 1] = k
  Core.after(self, KILL_WAIT, function(s)
    if removeFrom(s.pending, k) then finishKill(s, k) end
  end)
end

handlers.PARTY_KILL = function(self, attacker, target)
  local k = { by = attackerKind(attacker), via = "pk" }
  if isSecret(target) then
    k.npcID = target -- secret in instances: noted as '?', no duplicate protection possible
  else
    local guid = str(target)
    local id = guid and npcIdOf(guid)
    if not id then return end -- player/pet as target: PvP belongs to the Social collector
    if self.seen[guid] then return end
    markSeen(self, guid)
    k.npcID = id
    k.name, k.level, k.cls = describe(self, guid)
  end
  addKill(self, k)
end

handlers.UNIT_DIED = function(self, guid)
  guid = str(guid)
  if not guid or not npcIdOf(guid) or self.seen[guid] then return end
  local t = GetTime()
  local list = self.died
  for i = #list, 1, -1 do
    if t - list[i].at > DIED_KEEP then table.remove(list, i) end
  end
  if #list >= 20 then table.remove(list, 1) end
  list[#list + 1] = { guid = guid, at = t }
end

-- kill XP without PARTY_KILL: matching UNIT_DIED (same name in the cache), else only the name from the message.
local function orphanExpired(self, o)
  if o.used then return end
  o.used = true
  removeFrom(self.orphans, o)
  local t = GetTime()
  for i, d in ipairs(self.died) do
    if t - d.at <= DIED_KEEP + KILL_WAIT and not self.seen[d.guid] then
      local name, level, cls = describe(self, d.guid)
      if o.name == nil or name == o.name then
        table.remove(self.died, i)
        markSeen(self, d.guid)
        local k = { npcID = npcIdOf(d.guid), name = name or o.name, level = level, cls = cls, via = "died", xp = o.xp }
        if self.fight then self.fight.kills = self.fight.kills + 1 end
        k.mapID, k.x, k.y = here()
        finishKill(self, k)
        return
      end
    end
  end
  if self.fight then self.fight.kills = self.fight.kills + 1 end
  local k = { name = o.name, via = "xp", xp = o.xp }
  k.mapID, k.x, k.y = here()
  finishKill(self, k)
end

handlers.FC_XP = function(self, src, amt, target)
  if src ~= "kill" then return end
  amt = num(amt)
  if not amt then return end
  target = str(target)
  local hit
  for i, p in ipairs(self.pending) do
    if target and p.name == target then
      hit = i
      break
    end
  end
  if not hit then
    for i, p in ipairs(self.pending) do
      if p.name == nil then
        hit = i
        break
      end
    end
  end
  if hit then
    local k = table.remove(self.pending, hit)
    k.xp, k.name = amt, k.name or target
    finishKill(self, k)
    return
  end
  local o = { xp = amt, name = target, at = GetTime() }
  self.orphans[#self.orphans + 1] = o
  Core.after(self, KILL_WAIT, function(s) orphanExpired(s, o) end)
end

-- Fill the unit cache

handlers.PLAYER_TARGET_CHANGED = function(self) remember(self, "target") end
handlers.UPDATE_MOUSEOVER_UNIT = function(self) remember(self, "mouseover") end
handlers.NAME_PLATE_UNIT_ADDED = function(self, unit) remember(self, unit) end

-- Combat (duration, kills, damage meter, narrow win)

-- Enable the damage meter automatically
-- Blizzard's option 'Enable damage meter' is the CVar damageMeterEnabled (off by default); without it C_DamageMeter returns nothing and the KF fields stay empty.
-- Writing the CVar is allowed outside combat. The automation runs unless ui.meterAuto is false (/chronik messer an|aus).
-- Deliberately untouched: the visibility of Blizzard's window (Edit Mode) is part of the layout and not safely writable by addons.
local METER_CVAR = "damageMeterEnabled"

ns.meterEnsured = nil -- for /chronik diag: result of the last enable attempt

-- automation switch (SavedVariables ui.meterAuto, default on)
function ns.meterAutoOn()
  local db = rawget(_G, "EveNChronicleDB")
  local ui = type(db) == "table" and db.ui or nil
  if type(ui) == "table" and not isSecret(ui) and ui.meterAuto == false then return false end
  return true
end

function ns.meterSetAuto(on)
  local db = rawget(_G, "EveNChronicleDB")
  if type(db) ~= "table" then return false end
  if type(db.ui) ~= "table" then db.ui = {} end
  db.ui.meterAuto = on and true or false
  return true
end

-- option 'Enable damage meter': true/false, nil if the CVar is missing or unreadable on this client
function ns.meterOption()
  local v
  local CV = C_CVar
  if type(CV) == "table" and not isSecret(CV) then v = call(CV.GetCVar, METER_CVAR) end
  if v == nil then v = call(GetCVar, METER_CVAR) end
  v = str(v)
  if not v then return nil end
  return v == "1" or v == "true"
end

-- checks the option and enables it if needed. Returns "kampf" (retry later), "aus" (automation off),
-- "unbekannt" (CVar missing), "schon an", "eingeschaltet" or "abgelehnt".
function ns.meterEnsure()
  if InCombatLockdown() then return "kampf" end
  if not ns.meterAutoOn() then ns.meterEnsured = "aus" return "aus" end
  local on = ns.meterOption()
  local result
  if on == nil then
    result = "unbekannt"
  elseif on then
    result = "schon an"
  else
    local CV = C_CVar
    if type(CV) == "table" and not isSecret(CV) and type(CV.SetCVar) == "function" then
      pcall(CV.SetCVar, METER_CVAR, "1")
    elseif type(SetCVar) == "function" then
      pcall(SetCVar, METER_CVAR, "1")
    end
    if ns.meterOption() == true then
      result = "eingeschaltet"
      Core.print(T.meterOn)
    else
      result = "abgelehnt"
    end
  end
  ns.meterEnsured = result
  return result
end

-- /chronik messer [an|aus]
function ns.meterSlash(rest)
  rest = type(rest) == "string" and string.lower(rest) or ""
  local sw = Core.onOff(rest)
  if sw == true then
    ns.meterSetAuto(true)
    local r = ns.meterEnsure()
    if r == "eingeschaltet" then return end -- message was already shown
    if r == "kampf" then
      Core.print(T.autoOnCombat)
    elseif r == "abgelehnt" then
      Core.print(T.autoOnRefused)
    else
      Core.print(T.autoOn)
    end
  elseif sw == false then
    ns.meterSetAuto(false)
    ns.meterEnsured = "aus"
    Core.print(T.autoOff)
  else
    Core.print(T("autoState", ns.meterAutoOn() and T.on or T.off))
  end
end

-- prefer Enum values, else the tested numbers (session 1 = current, type 0 = damage).
local function enumValue(group, name, fallback)
  local E = Enum
  if type(E) ~= "table" or isSecret(E) then return fallback end
  local g = E[group]
  if type(g) ~= "table" or isSecret(g) then return fallback end
  return num(g[name]) or fallback
end

-- own amount of a damage meter type for the running (just ended) session; nil if unreadable.
-- reason of the last read attempt for /chronik diag
ns.meterLast = nil

local function meterRead(kind)
  local DM = C_DamageMeter
  if type(DM) ~= "table" or isSecret(DM) then return nil, "fehlt" end
  if call(DM.IsDamageMeterAvailable) == false then return nil, "nicht verfügbar" end
  local s = call(DM.GetCombatSessionFromType, enumValue("DamageMeterSessionType", "Current", 1), kind)
  if isSecret(s) then return nil, "gesperrt" end
  if type(s) ~= "table" then return nil, "keine Sitzung" end
  local sources = s.combatSources
  if type(sources) == "table" and not isSecret(sources) then
    local me = str(call(UnitGUID, "player"))
    for i = 1, 40 do
      local c = sources[i]
      if not isSecret(c) and c == nil then break end
      if type(c) == "table" and not isSecret(c) and (c.isLocalPlayer == true or (me and str(c.sourceGUID) == me)) then
        local a = num(c.totalAmount)
        return a and floor(a) or nil, a and "ok" or "Wert gesperrt"
      end
    end
    -- in a group the total is not the own value
    if (num(call(GetNumGroupMembers)) or 0) > 1 then return nil, "kein eigener Eintrag" end
  end
  local total = num(s.totalAmount)
  return total and floor(total) or nil, total and "ok" or "Wert gesperrt"
end

local function meterAmount(kind)
  local a, why = meterRead(kind)
  if kind == enumValue("DamageMeterType", "DamageDone", 0) then
    local lvl = playerLevel()
    ns.meterLast = { why = why, level = lvl }
    -- from which level does the client provide the damage meter? (Retail: level 7 'unavailable', level 90 ok)
    local db = rawget(_G, "EveNChronicleDB")
    local diag = type(db) == "table" and type(db.diag) == "table" and db.diag or nil
    if diag and lvl then
      if why == "ok" then
        if not diag.meterFirstOkLevel then diag.meterFirstOkLevel = lvl end
      elseif why == "nicht verfügbar" and lvl > (diag.meterNoLevel or 0) then
        diag.meterNoLevel = lvl
      end
    end
  end
  return a
end

-- for /chronik diag: state now (outside combat) and result after the last combat
function ns.meterStatus()
  local DM = C_DamageMeter
  local now
  if type(DM) ~= "table" or isSecret(DM) then
    now = "fehlt"
  else
    local avail = call(DM.IsDamageMeterAvailable)
    now = avail == false and "nicht verfügbar" or (avail == true and "verfügbar" or "unklar")
  end
  -- now stays a German value for diag.meter in the file; the UI language is shown
  local nowText = (now == "fehlt" and T.nowMissing) or (now == "nicht verfügbar" and T.nowUnavailable)
    or (now == "verfügbar" and T.nowAvailable) or T.nowUnclear
  local last = ns.meterLast
  local line = T("status", nowText) .. (playerLevel() and T("statusLevel", playerLevel()) or "")
  if last then
    line = line .. T("statusLast", tostring(last.why))
  else
    line = line .. T.statusNoFight
  end
  local opt = ns.meterOption()
  line = line .. T("statusOption", opt == nil and T.unknown or (opt and T.on or T.off), ns.meterAutoOn() and T.on or T.off)
  if ns.meterEnsured == "eingeschaltet" then
    line = line .. " (" .. T.enabled .. ")"
  elseif ns.meterEnsured == "abgelehnt" then
    line = line .. " (" .. T.refused .. ")"
  end
  return line, now, last and last.why or nil
end

-- Health at combat end: is it readable at all? The result of the last combat end (and the state of the self-test) lands in
-- diag.hpEnd = "ok" | "secret". Evidence (WoW Forever): UnitHealth('player') is secret at PLAYER_REGEN_ENABLED and also
-- later outside combat (diag.state.healthSecret = true), so a later read is no substitute: without a readable value the
-- "close win" can never be measured. The medal "Um Haaresbreite" hides itself then (journal/model/Chronik.lua).
local function diagTable()
  local db = rawget(_G, "EveNChronicleDB")
  return type(db) == "table" and type(db.diag) == "table" and db.diag or nil
end

local function noteHpEnd(hp)
  local diag = diagTable()
  if not diag then return end
  if isSecret(hp) then
    diag.hpEnd = "secret"
  elseif num(hp) ~= nil then
    diag.hpEnd = "ok"
  end
end

-- false only when it is known that the health at combat end cannot be read; unknown (no combat yet, no self-test) = true
function ns.closeWinReadable()
  local diag = diagTable()
  if not diag then return true end
  if diag.hpEnd == "secret" then return false end
  if diag.hpEnd == "ok" then return true end
  local state = diag.state
  if type(state) == "table" and state.healthSecret == true then return false end
  return true
end

handlers.PLAYER_REGEN_DISABLED = function(self)
  self.fight = { start = GetTime(), kills = 0 }
end

handlers.PLAYER_DEAD = function(self)
  if self.fight then self.fight.dead = true end
end

handlers.PLAYER_REGEN_ENABLED = function(self)
  local f = self.fight
  self.fight = nil
  if not self.meterDone then self.meterDone = ns.meterEnsure() ~= "kampf" end
  if not f then return end
  local duration = GetTime() - f.start
  local dead = f.dead or call(UnitIsDeadOrGhost, "player") == true
  local hp, hpMax = call(UnitHealth, "player"), num(call(UnitHealthMax, "player"))
  noteHpEnd(hp)
  local pct
  if isSecret(hp) then
    pct = hp -- secret: '?'
  elseif num(hp) and hpMax and hpMax > 0 then
    pct = floor(num(hp) * 100 / hpMax)
  end
  local close = num(pct) ~= nil and pct < CLOSE_PCT and not dead
  if close then Core.emit("FC_CLOSE_WIN", pct) end
  Core.after(self, METER_DELAY, function(s)
    local damage, healing, taken
    if not InCombatLockdown() then -- already the next combat: the meter no longer belongs to this one
      damage = meterAmount(enumValue("DamageMeterType", "DamageDone", 0))
      healing = meterAmount(enumValue("DamageMeterType", "HealingDone", 2))
      taken = meterAmount(enumValue("DamageMeterType", "DamageTaken", 7))
    end
    Store.append("KF", duration, f.kills, damage, healing, taken, pct, close and 1 or 0, dead and 1 or 0, playerLevel(), (here()))
  end)
end

-- on logout: write waiting kills and messages at once
handlers.PLAYER_LOGOUT = function(self)
  local pending = self.pending
  self.pending = {}
  for _, k in ipairs(pending) do finishKill(self, k) end
  local orphans = self.orphans
  for i = #orphans, 1, -1 do orphanExpired(self, orphans[i]) end
end

function Combat:onEvent(event, ...)
  local h = handlers[event]
  if h then h(self, ...) end
end

ns.RegisterCollector("Combat", Combat)
