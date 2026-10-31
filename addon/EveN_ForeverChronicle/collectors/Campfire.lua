-- Collector 'Campfire' (campfire talk): detects the fire session (campfire only, never an inn) and who sits at it (group, nameplates, mouseover/target, chat speakers); writes the LF line on standing up.
-- A session starts when the sit aura (Campfire.SIT_SPELLS) appears on the player outside combat (or after the sit key/SIT emote); it ends on movement, standing up, combat, zone change, loading screen, death, taxi, logout or IDLE_MAX.
-- Read only out of combat; every client value is checked for secret values first. Names of other players are foreign text: log via Sanitize.field, display via Sanitize.display.
local _, ns = ...
local Core, Store = ns.Core, ns.Store

-- chat messages of /chronik feuer and /chronik sim feuer (English: locales/enUS_core.lua, section 'col.Campfire'; pattern: docs/i18n.md).
-- Stored values (diag.plates, diag.auraRead, sit sources, log) stay German; the UI language is shown (lookup via WORDS/WHY_CODES).
local T = ns.Locale.ns("col.Campfire", {
  yes = "ja",
  no = "nein",
  unreadable = "nicht lesbar",
  on = "an",
  off = "aus",
  unknown = "unbekannt",
  -- Display of stored diagnostic values
  w_unbekannt = "unbekannt",
  w_schonAn = "schon an",
  w_eingeschaltet = "eingeschaltet",
  w_abgelehnt = "abgelehnt",
  w_zurueckgestellt = "zurückgestellt",
  w_fehlt = "fehlt",
  w_ja = "ja",
  w_nein = "nein",
  w_fehler = "fehler",
  w_gesperrt = "gesperrt",
  w_lesbar = "lesbar",
  notChecked = "noch nicht geprüft",
  -- reasons a round ended (log code -> display)
  why_move = "Bewegung",
  why_stand = "aufgestanden",
  why_jump = "gesprungen",
  why_combat = "Kampf",
  why_zone = "Zonenwechsel",
  why_dead = "Tod",
  why_loading = "Ladebildschirm",
  why_logout = "Abmelden",
  why_taxi = "Flug",
  why_idle = "30 Minuten ohne Klick",
  why_nearby = "Feuer weg",
  why_aura = "Sitz-Aura weg",
  why_manual = "beendet",
  why_simoff = "Simulation aus",
  why_simstand = "per Befehl aufgestanden",
  -- Person line
  level = "Stufe %s",
  stateSim = "Schein-Gast",
  stateAura = "am Feuer (Aura)",
  stateLingered = "am Feuer (verweilt)",
  stateNearby = "in der Nähe",
  person = "  %s%s - Quelle %s, %d s in Reichweite, %s",
  past = ", kennt Ihr vom Feuer (%d×%s)",
  pastLast = ", zuletzt %s",
  noRange = ", Reichweite nicht geprüft (nur Chat)",
  restHint = ", hat gerastet (Lagervorteile)",
  lastSeen = ", zuletzt vor %d s gesehen",
  -- Round and status
  roundRunning = "Lagerfeuer-Runde: läuft seit %d s, %d Personen erkannt.",
  roundNone = "Lagerfeuer-Runde: keine.",
  roundLastEnd = " Letzte endete: %s.",
  notesMissing = "Lagerfeuer: Die Zettel-Anzeige ist noch nicht eingebaut.",
  combatNoRead = "Lagerfeuer: im Kampf nicht lesbar, bitte nach dem Kampf erneut abfragen.",
  sitAura = "Lagerfeuer: Sitz-Aura %s: %s, Lagerfeuer in der Nähe (%d): %s.",
  plates = "Plaketten freundlicher Spieler: %s (%s = %s), beim Hinsetzen einschalten: %s%s.",
  platesLast = ", zuletzt: %s",
  platesTip = "Tipp: Mit Plaketten freundlicher Spieler (Optionen > Namen) erkennt die Chronik Mitspieler am Feuer besser.",
  auraRead = "Auren anderer Spieler lesbar: %s.",
  sitSignal = "Sitz-Signal: %s.",
  thisRound = "Diese Runde",
  lastRound = "Letzte Runde",
  probe = " (Probe)",
  roundSummary = "%s%s in %s: %d Personen, gesagt %d%s.",
  inLog = ", im Log (LF)",
  notInLog = ", nicht im Log",
  roundsSaved = "Runden gespeichert: %d (davon Probe %d).",
  probeTooShort = "Probe-Runde nach %d s beendet: zu kurz (unter %d s), nicht in die Chronik eingetragen.",
  -- Simulation
  simSayPrefix = "[Sim] Ihr sagt: ",
  simOff = "Simulation ist aus.",
  nameMissing = "Name fehlt.",
  classUnknown = "Klasse unbekannt (z. B. Krieger, Magierin, MAGE).",
  levelRange = "Stufe muss eine ganze Zahl von 1 bis %d sein.",
  guestMax = "Höchstens %d Schein-Gäste.",
  srcAura = "Sitz-Aura (Forever)",
  srcKey = "Sitz-Taste/Emote (Simulation)",
  srcCommand = "Befehl setzen (Simulation)",
  simFire = ", Retail-Feuer %d: %s",
  simLineOff = "Simulation: aus.",
  simLineOn = "Simulation: an, Sätze %s, %d Schein-Gäste.",
  loudSay = "laut in /sagen",
  localOnly = "nur lokal ([Sim])",
  helpOnOff = "/chronik sim feuer an|aus|status - Retail-Simulation des Lagerfeuers (gilt bis zum Neuladen)",
  helpSit = "/chronik sim feuer setzen|aufstehen - Probe-Runde beginnen/beenden (die Sitz-Taste geht auch)",
  helpGuest = "/chronik sim feuer gast <Name> <Klasse> <Stufe> [m|w] - Schein-Mitspieler (ohne Name: Liste)",
  helpSay = "/chronik sim feuer sagt <Name> <Text> - ein Schein-Gast spricht (zählt als Gespräch am Feuer)",
  helpLoud = "/chronik sim feuer laut - Sätze wirklich in /sagen senden (Umschalter)",
  helpClear = "/chronik sim feuer löschen - alle Probe-Runden aus dem Log entfernen (echte bleiben)",
  retailFire = "Retail-Feuer %d (Gemütliches Feuer) am Charakter: %s.",
  guestLine = "  Gast %s (%s, Stufe %d)",
  simOn = "Simulation an: Sitz-Taste oder /chronik sim feuer setzen beginnt eine Probe-Runde.",
  simOffNow = "Simulation aus.",
  probeRunning = "Probe-Runde läuft: Ihr sitzt am (simulierten) Feuer.",
  simFirstOn = "Simulation ist aus: erst /chronik sim feuer an.",
  alreadyRunning = "Es läuft schon eine Runde.",
  cantSit = "Hinsetzen geht gerade nicht (%s).",
  sitWhyNotReady = "nicht bereit",
  sitWhyCombat = "Kampf",
  sitWhyMounted = "beritten",
  stoodUp = "Aufgestanden.",
  noRound = "Es läuft keine Runde.",
  guestAdded = "Schein-Gast %s (%s, Stufe %d) sitzt mit am Feuer.",
  guestError = "Gast: %s",
  loudOn = "Sätze gehen wirklich in /sagen.",
  loudOff = "Sätze bleiben lokal ([Sim] Ihr sagt: ...).",
  cleared = "%d Probe-Runden entfernt, echte Runden bleiben.",
  noProbeRound = "Es läuft keine Probe-Runde.",
  textMissing = "Text fehlt.",
  noGuestAtFire = "Kein Schein-Gast mit diesem Namen am Feuer.",
  noGuest = "Kein Schein-Gast mit diesem Namen.",
  guestSays = "[Sim] %s sagt: %s",
  sayError = "Sagt: %s",
})

-- stored German diagnostic value -> display key (unknown values appear unchanged)
local WORDS = {
  ["unbekannt"] = "w_unbekannt", ["schon an"] = "w_schonAn", ["eingeschaltet"] = "w_eingeschaltet", ["abgelehnt"] = "w_abgelehnt",
  ["zurückgestellt"] = "w_zurueckgestellt", ["fehlt"] = "w_fehlt", ["ja"] = "w_ja", ["nein"] = "w_nein", ["fehler"] = "w_fehler",
  ["gesperrt"] = "w_gesperrt", ["lesbar"] = "w_lesbar",
}
local function word(v)
  local key = WORDS[v]
  return key and T[key] or tostring(v)
end

local floor, gsub, find, match, gmatch, sub, format = math.floor, string.gsub, string.find, string.match, string.gmatch,
  string.sub, string.format

local Campfire = ns.Campfire or {}
ns.Campfire = Campfire

Campfire.SIT_SPELLS = { 1289723 }            -- sit aura on the player ('Welcoming Campfire', sitting in camp range)
Campfire.PEOPLE_AURAS = { 1289723 }          -- on other players: only the sit aura makes someone 'at the fire' at once
Campfire.HINT_AURAS = { 1229741 }            -- 'Camp Benefits' lasts 1 h after standing up: hint only (restHint), never sure
Campfire.NEARBY_SPELL = 1283391              -- 'Campfire Nearby': if it disappears during the session, the fire is gone
Campfire.DWELL = 20          -- seconds in range after which someone is 'at the fire'
Campfire.MIN_LF = 60         -- seconds: shorter sessions write no LF line
Campfire.SIM_MIN_LF = 5      -- seconds: same for trial rounds (simulation: short trials should reach the book)
Campfire.IDLE_MAX = 1800     -- seconds without a click, then the session ends
Campfire.SCAN_EVERY = 2      -- seconds between two passes (plates, group, known people)
Campfire.GAP_UNIT = 6        -- seconds: the largest gap between two sightings that still counts as 'continuously there'
Campfire.MAX_TRACK = 20      -- people tracked per session
Campfire.MAX_LF = 10         -- people per LF line (the field is also capped at Sanitize.FIELD_MAX; n counts all)
Campfire.RANGE_INDEX = 4     -- CheckInteractDistance: 4 = follow (about 28 yd)
Campfire.END_ON_AURA_LOSS = false
Campfire.PLATES_CVAR = "nameplateShowFriends"
Campfire.HISTORY_MAX = 2000  -- LF lines read for recognition (the newest are kept)
Campfire.DEFAULTS = { showFriendPlates = true }
Campfire.SIM_FIRE_SPELLS = { 7353 }  -- Retail 'Cozy Fire' (cooking fire, about 10 yd): noted only
Campfire.SIM_GUEST_MAX = 5
Campfire.SIM_LEVEL_MAX = 100

local AURA_THROTTLE = 1.0
local FIRST_READ = 2.0
local SIT_RECHECK = 1.2   -- seconds after sit key/SIT emote until the sit aura is checked
local NAME_MAX = 64
local NAMEPLATES = 40
local MAX_RAID, MAX_PARTY = 40, 4
local GUID_PREFIX = "Player-"

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

local function isTrue(v)
  return not isSecret(v) and v == true
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if not r[1] then return nil end
  return r[2], r[3], r[4], r[5], r[6], r[7], r[8]
end

local function inCombat()
  return isTrue(call(InCombatLockdown))
end

local function now() return GetTime() end

Campfire.diag = { plates = nil, auraRead = nil, lastEnd = nil, dropped = 0 }

-- Settings (EveNChronicleDB.ui.campfire)

local function uiTable(create)
  local db = rawget(_G, "EveNChronicleDB")
  if type(db) ~= "table" or isSecret(db) then return nil end
  local ui = db.ui
  if type(ui) ~= "table" or isSecret(ui) then
    if not create then return nil end
    ui = {}
    db.ui = ui
  end
  local c = ui.campfire
  if type(c) ~= "table" or isSecret(c) then
    if not create then return nil end
    c = {}
    ui.campfire = c
  end
  return c
end

function Campfire.settings()
  local raw = uiTable(false) or {}
  local out = {}
  for k, d in pairs(Campfire.DEFAULTS) do
    local v = raw[k]
    if not isSecret(v) and type(v) == type(d) then out[k] = v else out[k] = d end
  end
  return out
end

Campfire.listeners = {}

function Campfire.onSettingsChanged(fn)
  if type(fn) ~= "function" then return false end
  for _, f in ipairs(Campfire.listeners) do
    if f == fn then return false end
  end
  Campfire.listeners[#Campfire.listeners + 1] = fn
  return true
end

local applyPlates -- below (needs the session)

function Campfire.set(key, value)
  local d = type(key) == "string" and Campfire.DEFAULTS[key]
  if d == nil or isSecret(value) or type(value) ~= type(d) then return false end
  local t = uiTable(true)
  if not t then return false end
  local old = Campfire.settings()[key]
  t[key] = value
  if old ~= value then
    if key == "showFriendPlates" and applyPlates then Core.safe(applyPlates) end
    for i = 1, #Campfire.listeners do Core.safe(Campfire.listeners[i], key, value) end
  end
  return true
end

-- CVar nameplateShowFriends

local function getCVar(name)
  local v
  local CV = rawget(_G, "C_CVar")
  if type(CV) == "table" and not isSecret(CV) then v = call(CV.GetCVar, name) end
  if v == nil then v = call(rawget(_G, "GetCVar"), name) end
  if type(v) == "number" and not isSecret(v) then v = tostring(floor(v)) end
  return str(v)
end

local function setCVar(name, value)
  local CV = rawget(_G, "C_CVar")
  if type(CV) == "table" and not isSecret(CV) and type(CV.SetCVar) == "function" then
    pcall(CV.SetCVar, name, value)
  elseif type(rawget(_G, "SetCVar")) == "function" then
    pcall(SetCVar, name, value)
  end
  return getCVar(name) == value
end
Campfire.getCVar = getCVar

local plates = nil      -- { old = '0' } while the session has changed the CVar
local restoreWanted = false

local function savePlates()
  if plates then
    Store.putSnapshot("state", "campfirePlates", { old = plates.old }, true)
  else
    Store.dropSnapshot("state", "campfirePlates")
  end
end

local function platesOn()
  if plates or not Campfire.settings().showFriendPlates then return end
  if inCombat() then return end
  local cur = getCVar(Campfire.PLATES_CVAR)
  if cur == nil then
    Campfire.diag.plates = "unbekannt"
    return
  end
  if cur ~= "0" then
    Campfire.diag.plates = "schon an"
    return
  end
  plates = { old = cur }
  savePlates() -- remember first, then change (a crash in between: restored at the next start)
  if setCVar(Campfire.PLATES_CVAR, "1") then
    Campfire.diag.plates = "eingeschaltet"
  else
    plates = nil
    savePlates()
    Campfire.diag.plates = "abgelehnt"
  end
end

-- restore the old value. In combat: later (PLAYER_REGEN_ENABLED). -> true when done
local function platesRestore()
  if not plates then
    restoreWanted = false
    return true
  end
  if inCombat() then
    restoreWanted = true
    return false
  end
  restoreWanted = false
  local cur = getCVar(Campfire.PLATES_CVAR)
  if cur == "1" then setCVar(Campfire.PLATES_CVAR, plates.old) end -- otherwise the player changed it themselves: their choice stays
  plates = nil
  savePlates()
  Campfire.diag.plates = "zurückgestellt"
  return true
end
Campfire.platesChanged = function() return plates ~= nil end

-- People field of the LF line: per person 'guid,name-realm,class,race,level,sex,how', people separated by ';'.
-- guid without the 'Player-' prefix (saves space), how = 'a' (aura read) or 'd' (dwelled). Commas and semicolons in foreign text become spaces.
-- The field stays under Sanitize.FIELD_MAX: a person who no longer fits is dropped entirely.

local function part(v)
  if v == nil or isSecret(v) then return "" end
  if type(v) == "number" then return Store.int(v) end
  if type(v) ~= "string" then return "" end
  local s = ns.Sanitize.field(v)
  return (gsub(s, "[,;]", " "))
end

function Campfire.encodePeople(list)
  local out, size = {}, 0
  local max = ns.Sanitize.FIELD_MAX
  for _, p in ipairs(type(list) == "table" and list or {}) do
    local guid = type(p.guid) == "string" and p.guid or ""
    if sub(guid, 1, #GUID_PREFIX) == GUID_PREFIX then guid = sub(guid, #GUID_PREFIX + 1) end
    local one = table.concat({ part(guid), part(p.full), part(p.class), part(p.race), part(p.level), part(p.sex),
      p.aura and "a" or "d" }, ",")
    local add = #one + (#out > 0 and 1 or 0)
    if size + add > max then break end
    out[#out + 1] = one
    size = size + add
  end
  return table.concat(out, ";")
end

local function splitOn(s, sep)
  local out = {}
  local pos = 1
  while true do
    local a = find(s, sep, pos, true)
    if not a then
      out[#out + 1] = sub(s, pos)
      return out
    end
    out[#out + 1] = sub(s, pos, a - 1)
    pos = a + 1
  end
end

local function cell(v)
  if type(v) ~= "string" or v == "" or v == "?" then return nil end
  return v
end

function Campfire.parsePeople(text)
  local list = {}
  if type(text) ~= "string" or text == "" or isSecret(text) then return list end
  for _, one in ipairs(splitOn(text, ";")) do
    local f = splitOn(one, ",")
    local guid, full = cell(f[1]), cell(f[2])
    if guid and not find(guid, "^" .. GUID_PREFIX) then guid = GUID_PREFIX .. guid end
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

-- field positions from ns.Types (single source of the line format)
local LF_POS = nil
local function lfPos()
  if LF_POS then return LF_POS end
  local t = ns.Types and ns.Types.LF
  local p = {}
  for i, d in ipairs(t and t.fields or {}) do p[d[1]] = i end
  LF_POS = p
  return p
end

local function roundOf(t, fields)
  local p = lfPos()
  local function n(name)
    local v = tonumber(cell(fields[p[name]]) or "")
    if not num(v) then return nil end
    return floor(v)
  end
  return { t = t, mapID = n("mapID"), x = n("x"), y = n("y"), level = n("level"), seconds = n("seconds"), n = n("count"),
    said = n("said"), sim = (p.sim and n("sim") == 1) or nil, people = Campfire.parsePeople(fields[p.people]) }
end

local function keepNewest(list)
  local over = #list - Campfire.HISTORY_MAX
  if over <= 0 then return list end
  local out = {}
  for i = over + 1, #list do out[#out + 1] = list[i] end
  return out
end

function Campfire.roundsFromIndex(index)
  local I = ns.Journal and ns.Journal.Index
  if not (I and I.list) then return {} end
  local out = {}
  for _, rec in ipairs(I.list(index, "LF")) do
    if type(rec) == "table" and type(rec.t) == "number" then out[#out + 1] = roundOf(rec.t, rec) end
  end
  return keepNewest(out)
end

function Campfire.rounds(char)
  local out = {}
  if type(char) ~= "table" then return out end
  local function take(t, rest)
    if num(t) then out[#out + 1] = roundOf(t, splitOn(rest or "", "~")) end
  end
  for _, block in ipairs(type(char.log) == "table" and char.log or {}) do
    if type(block) == "string" and find(block, "~LF~", 1, true) then
      local h = tonumber(match(block, "^#~(%-?%d+)~"))
      if num(h) then
        for dt, code, rest in gmatch(block, "\n(%-?%d+)~(%u+)~?([^\n]*)") do
          if code == "LF" then take(h + tonumber(dt), rest) end
        end
      end
    end
  end
  local b = Store.block
  if Store.current == char and type(b) == "table" and type(b.lines) == "table" and num(b.start) then
    for _, line in ipairs(b.lines) do
      local dt, code, rest = match(line, "^(%-?%d+)~(%u+)~?(.*)$")
      if dt and code == "LF" then take(b.start + tonumber(dt), rest) end
    end
  end
  return keepNewest(out)
end

local function addToHistory(h, round)
  h.rounds = h.rounds + 1
  local counted = {} -- the same person (GUID or name-realm) counts once per round
  for _, p in ipairs(round.people) do
    local e = (p.guid and h.byGuid[p.guid]) or (p.full and h.byName[p.full])
    if not e then
      e = { n = 0, firstT = round.t }
    end
    if not counted[e] then e.n = e.n + 1 end
    counted[e] = true
    if round.t < e.firstT then e.firstT = round.t end
    if not e.lastT or round.t >= e.lastT then
      e.lastT, e.lastMapID, e.lastLevel = round.t, round.mapID, p.level or e.lastLevel
      e.full, e.name = p.full or e.full, p.name or e.name
      e.class, e.race, e.sex = p.class or e.class, p.race or e.race, p.sex or e.sex
    end
    if p.guid then h.byGuid[p.guid] = e end
    if p.full then h.byName[p.full] = e end
  end
end

function Campfire.history(rounds)
  local h = { byGuid = {}, byName = {}, rounds = 0 }
  for _, r in ipairs(type(rounds) == "table" and rounds or {}) do addToHistory(h, r) end
  return h
end

-- Session shape:
--   session = { active, id, startT, startGT, mapID, x, y, zone, level, src, said, seconds/endGT/why (after the end),
--     talk = { gt, who = 'self' | 'other', guid, name } (who spoke last; chat text is never stored), people = { person, ... } }
--   person = { guid, name, realm, full (name-realm), class, race, sex, level, src, srcs, firstGT, lastGT, dwell, aura, restHint, sure, past }
--   sure = 'at the fire': wears the sit aura or stayed in range for DWELL seconds; only those go into the LF line. restHint never counts as sure.

local session, lastSession = nil, nil
local byGuid = {}
local sessionN = 0
local hist = nil       -- { char, sim, h } recognition (built once per character/sim state from the log, then carried on)
local Collector
local sim = { on = false, loud = false, guests = {} } -- only until reload, never saved

local startHooks = {}

function ns.onCampfire(fn)
  if type(fn) ~= "function" then return false end
  for _, f in ipairs(startHooks) do
    if f == fn then return false end
  end
  startHooks[#startHooks + 1] = fn
  return true
end

local function fire(what, s)
  for i = 1, #startHooks do Core.safe(startHooks[i], what, s) end
end

function Campfire.session() return session end
function Campfire.lastSession() return lastSession end

function Campfire.touch()
  if not session then return false end
  session.lastActGT = now()
  return true
end

local talked -- defined below

function Campfire.noteSaid()
  if not session then return false end
  session.said = session.said + 1
  session.lastActGT = now()
  talked("self")
  return true
end

local function zoneName(mapID)
  if not num(mapID) then return nil end
  local char = Store.char()
  local maps = type(char) == "table" and type(char.snapshots) == "table" and char.snapshots.maps or nil
  local m = type(maps) == "table" and maps[mapID] or nil
  local name = type(m) == "table" and str(m.name) or nil
  if not name then
    local info = ns.Zone.info(mapID)
    name = info and str(info.name) or nil
  end
  if not name then return nil end
  name = ns.Sanitize.field(name)
  return name ~= "" and name or nil
end
Campfire.zoneName = zoneName

local function history()
  local char = Store.char()
  if type(char) ~= "table" then return nil end
  if not hist or hist.char ~= char or hist.sim ~= sim.on then
    local rounds = Campfire.rounds(char)
    if not sim.on then -- real rounds do not recognize anyone from trial rounds
      local real = {}
      for _, r in ipairs(rounds) do
        if not r.sim then real[#real + 1] = r end
      end
      rounds = real
    end
    hist = { char = char, sim = sim.on, h = Campfire.history(rounds) }
  end
  return hist.h
end

local function pastOf(guid, full)
  local h = history()
  local e = h and ((guid and h.byGuid[guid]) or (full and h.byName[full])) or nil
  if not e then return nil end
  return { n = e.n, firstT = e.firstT, lastT = e.lastT, lastMapID = e.lastMapID, lastZone = zoneName(e.lastMapID),
    lastLevel = e.lastLevel }
end

local function ownRealm()
  local r = str(call(GetNormalizedRealmName))
  if not r then
    r = str(call(GetRealmName))
    if r then r = gsub(r, "[%s%-]", "") end
  end
  return r
end

local function myGuid()
  return str(call(UnitGUID, "player"))
end

local function validGuid(g)
  g = str(g)
  if not g or not find(g, "^Player%-") or #g > 40 then return nil end
  return g
end

local function cleanName(v)
  v = str(v)
  if not v then return nil end
  local unknown = rawget(_G, "UNKNOWNOBJECT")
  if type(unknown) == "string" and not isSecret(unknown) and v == unknown then return nil end
  v = ns.Sanitize.cut(ns.Sanitize.field(v), NAME_MAX)
  return v ~= "" and v or nil
end

local function sexOf(v)
  v = num(v)
  return (v == 2 or v == 3) and v or nil
end

-- reads a player unit (not you). -> info | nil. Secret single values stay empty; without GUID or name: nil.
local function readPlayer(unit)
  if not isTrue(call(UnitIsPlayer, unit)) then return nil end
  if isTrue(call(UnitIsUnit, unit, "player")) then return nil end
  local guid = validGuid(call(UnitGUID, unit))
  if not guid or guid == myGuid() then return nil end
  local name, realm
  if type(UnitFullName) == "function" then
    name, realm = call(UnitFullName, unit)
  else
    name, realm = call(UnitName, unit)
  end
  name = cleanName(name)
  if not name then return nil end
  realm = cleanName(realm) or ownRealm()
  if realm then realm = gsub(realm, "[%s%-]", "") end
  local _, class = call(UnitClass, unit)
  local _, race = call(UnitRace, unit)
  local level = num(call(UnitLevel, unit))
  return { guid = guid, name = name, realm = realm, class = cleanName(class), race = cleanName(race),
    level = level and level > 0 and floor(level) or nil, sex = sexOf(call(UnitSex, unit)) }
end

-- range (about 28 yd): true / false / nil (unreadable)
local function inRange(unit)
  if type(CheckInteractDistance) ~= "function" then return nil end
  local ok, r = pcall(CheckInteractDistance, unit, Campfire.RANGE_INDEX)
  if not ok or isSecret(r) or r == nil then return nil end
  return r == true or r == 1
end

-- hint aura (Camp Benefits) on the other player? -> true / false (secret/error: false)
local function hintOn(unit)
  local A = rawget(_G, "C_UnitAuras")
  if type(A) ~= "table" or type(A.GetUnitAuraBySpellID) ~= "function" then return false end
  for _, id in ipairs(Campfire.HINT_AURAS) do
    local ok, a = pcall(A.GetUnitAuraBySpellID, unit, id)
    if ok and a ~= nil and not isSecret(a) then return true end
  end
  return false
end

-- sit aura on the other player? -> true / false; remembers the read state for diagnostics
local function auraOn(unit)
  local A = rawget(_G, "C_UnitAuras")
  if type(A) ~= "table" or type(A.GetUnitAuraBySpellID) ~= "function" then
    Campfire.diag.auraRead = "fehlt"
    return false
  end
  local state = "nein"
  for _, id in ipairs(Campfire.PEOPLE_AURAS) do
    local ok, a = pcall(A.GetUnitAuraBySpellID, unit, id)
    if not ok then
      state = "fehler"
    elseif isSecret(a) then
      state = "gesperrt"
    elseif a ~= nil then
      Campfire.diag.auraRead = "ja"
      return true
    elseif state == "nein" then
      state = "lesbar"
    end
  end
  if Campfire.diag.auraRead ~= "ja" then Campfire.diag.auraRead = state end
  return false
end

local changed = false

-- gap = nil: sighting without checked range (chat without a unit): the person is noted, dwell time does not grow
local function sight(info, src, t, gap, aura, hint)
  local s = session
  if not s or not info then return nil end
  local p = byGuid[info.guid]
  if not p then
    if #s.people >= Campfire.MAX_TRACK then
      Campfire.diag.dropped = Campfire.diag.dropped + 1
      return nil
    end
    local full = info.realm and (info.name .. "-" .. info.realm) or info.name
    full = ns.Sanitize.cut(full, NAME_MAX)
    p = { guid = info.guid, name = info.name, realm = info.realm, full = full, class = info.class, race = info.race,
      sex = info.sex, level = info.level, src = src, srcs = {}, firstGT = t, lastGT = gap and t or nil, dwell = 0, aura = false,
      sure = false, past = pastOf(info.guid, full) }
    s.people[#s.people + 1] = p
    byGuid[info.guid] = p
    changed = true
  else
    p.level = info.level or p.level
    p.class, p.race, p.sex = p.class or info.class, p.race or info.race, p.sex or info.sex
    if gap then
      local d = p.lastGT and (t - p.lastGT) or 0
      if d > 0 and d <= gap then p.dwell = p.dwell + d end
      if not p.lastGT or t > p.lastGT then p.lastGT = t end
    end
  end
  if hint then p.restHint = true end
  p.srcs[src] = true
  if aura and not p.aura then
    p.aura = true
    changed = true
  end
  if not p.sure and (p.aura or p.dwell >= Campfire.DWELL) then
    p.sure = true
    changed = true
  end
  return p
end

-- check a unit: player, not you, in range. Only a nameplate (it appears only nearby anyway) counts even with unreadable range;
-- group, target, mouseover and chat need an unambiguous 'in range'.
local function sightUnit(unit, src)
  if not session or inCombat() then return nil end
  local info = readPlayer(unit)
  if not info then return nil end
  local r = inRange(unit)
  local plate = find(unit, "^nameplate%d+$") ~= nil
  if r == false or (r ~= true and not plate) then return nil end
  return sight(info, src, now(), Campfire.GAP_UNIT, auraOn(unit), hintOn(unit))
end

local function scanGroup()
  local raid = isTrue(call(IsInRaid))
  local grouped = isTrue(call(IsInGroup)) or raid
  if not grouped then return end
  local prefix, max = raid and "raid" or "party", raid and MAX_RAID or MAX_PARTY
  for i = 1, max do sightUnit(prefix .. i, "group") end
end

local function scanAll()
  if not session or inCombat() then return end
  local seen = {}
  scanGroup()
  for i = 1, NAMEPLATES do
    local u = "nameplate" .. i
    local e = call(UnitExists, u)
    if isTrue(e) then
      local p = sightUnit(u, "plate")
      if p then seen[p.guid] = true end
    end
  end
  sightUnit("target", "target")
  sightUnit("mouseover", "mouse")
  -- find known people again via any token (target, plate, group)
  if type(UnitTokenFromGUID) == "function" then
    for _, p in ipairs(session.people) do
      if not seen[p.guid] then
        local tok = str(call(UnitTokenFromGUID, p.guid))
        if tok then sightUnit(tok, p.src == "group" and "group" or p.src) end
      end
    end
  end
end

local function flushChanged()
  if changed and session then
    changed = false
    fire("update", session)
  end
  changed = false
end

-- chat speaker (say, emote): payload name-realm (arg 2), GUID (arg 12). Without a unit or readable range only 'nearby' (never sure).
local function chatSpeaker(playerName, guid)
  if not session or inCombat() then return end
  guid = validGuid(guid)
  if not guid or guid == myGuid() then return end
  local tok = type(UnitTokenFromGUID) == "function" and str(call(UnitTokenFromGUID, guid)) or nil
  local info = tok and readPlayer(tok) or nil
  local aura, hint, gap = false, false, nil
  if info then
    local r = inRange(tok)
    if r == false then return end
    if r == true then gap = Campfire.GAP_UNIT end -- only with confirmed range (about 28 yd) does the time count
    aura, hint = auraOn(tok), hintOn(tok)
  else
    local _, class, _, race, sex, name, realm = call(GetPlayerInfoByGUID, guid)
    name = cleanName(name)
    realm = cleanName(realm)
    local raw = str(playerName)
    if not name and raw then
      local n, r = match(raw, "^([^%-]+)%-(.+)$")
      name = cleanName(n or raw)
      realm = realm or cleanName(r)
    end
    if not name then return end
    realm = realm or ownRealm()
    if realm then realm = gsub(realm, "[%s%-]", "") end
    info = { guid = guid, name = name, realm = realm, class = cleanName(class), race = cleanName(race), sex = sexOf(sex) }
  end
  sight(info, "chat", now(), gap, aura, hint)
  flushChanged()
end

local function sitAura()
  local A = rawget(_G, "C_UnitAuras")
  if type(A) ~= "table" or type(A.GetPlayerAuraBySpellID) ~= "function" then return nil end
  local secret = false
  for _, id in ipairs(Campfire.SIT_SPELLS) do
    local ok, a = pcall(A.GetPlayerAuraBySpellID, id)
    if ok and isSecret(a) then
      secret = true
    elseif ok and a ~= nil then
      return true, id
    end
  end
  if secret then return nil end
  return false
end

local function nearbyAura()
  local A = rawget(_G, "C_UnitAuras")
  if type(A) ~= "table" or type(A.GetPlayerAuraBySpellID) ~= "function" then return nil end
  local ok, a = pcall(A.GetPlayerAuraBySpellID, Campfire.NEARBY_SPELL)
  if not ok or isSecret(a) then return nil end
  return a ~= nil
end

-- order in the LF line: aura first, then longest dwell time
local function lfPeople(s)
  local list = {}
  for _, p in ipairs(s.people) do
    if p.sure then list[#list + 1] = p end
  end
  table.sort(list, function(a, b)
    if a.aura ~= b.aura then return a.aura end
    if a.dwell ~= b.dwell then return a.dwell > b.dwell end
    return a.firstGT < b.firstGT
  end)
  local n = #list
  for i = Campfire.MAX_LF + 1, #list do list[i] = nil end
  return list, n
end

local function endSession(self, why)
  local s = session
  if not s then return end
  session = nil
  byGuid = {}
  changed = false
  if self and self.ticker then
    self.ticker:Cancel()
    self.ticker = nil
  end
  s.active = false
  s.endGT = now()
  s.seconds = floor(s.endGT - s.startGT)
  s.why = why
  Campfire.diag.lastEnd = why
  if s.seconds >= (s.sim and Campfire.SIM_MIN_LF or Campfire.MIN_LF) then
    local list, n = lfPeople(s)
    local text = Campfire.encodePeople(list)
    Store.append("LF", s.mapID, s.x, s.y, s.level, s.seconds, n, text, s.said, s.sim and 1 or nil)
    s.written = true
    -- trial rounds only into the sim memory; real rounds into both
    local h = hist and Store.char() == hist.char and (hist.sim or not s.sim) and hist.h or nil
    if h then addToHistory(h, { t = s.startT, mapID = s.mapID, people = Campfire.parsePeople(text) }) end
  elseif s.sim then
    Core.print(T("probeTooShort", s.seconds, Campfire.SIM_MIN_LF))
  end
  platesRestore()
  lastSession = s
  fire("end", s)
end
Campfire.stop = function(why) endSession(Collector, why or "manual") end

local function tick(self)
  if not session then return end
  if inCombat() then return endSession(self, "combat") end
  if isTrue(call(UnitOnTaxi, "player")) then return endSession(self, "taxi") end
  if now() - session.lastActGT >= Campfire.IDLE_MAX then return endSession(self, "idle") end
  scanAll()
  flushChanged()
end

-- Retail fire (7353) on the player? true / false / nil (unreadable)
local function simFire()
  local A = rawget(_G, "C_UnitAuras")
  if type(A) ~= "table" or type(A.GetPlayerAuraBySpellID) ~= "function" then return nil end
  local secret = false
  for _, id in ipairs(Campfire.SIM_FIRE_SPELLS) do
    local ok, a = pcall(A.GetPlayerAuraBySpellID, id)
    if ok and isSecret(a) then
      secret = true
    elseif ok and a ~= nil then
      return true
    end
  end
  if secret then return nil end
  return false
end

-- dummy guest into the running session (counts as 'at the fire' at once)
local function addGuest(g, t)
  local s = session
  if not s or byGuid[g.guid] then return nil end
  if #s.people >= Campfire.MAX_TRACK then
    Campfire.diag.dropped = Campfire.diag.dropped + 1
    return nil
  end
  local p = { guid = g.guid, name = g.name, realm = g.realm, full = g.full, class = g.class, race = nil, sex = g.sex,
    level = g.level, src = "sim", srcs = { sim = true }, firstGT = t, lastGT = t, dwell = Campfire.DWELL, aura = false,
    sure = true, sim = true, past = pastOf(g.guid, g.full) }
  s.people[#s.people + 1] = p
  byGuid[g.guid] = p
  return p
end

local function startSession(self, spellID, near, how)
  sessionN = sessionN + 1
  local mapID, x, y = ns.Zone.here()
  local level = num(call(UnitLevel, "player"))
  local t = now()
  session = { active = true, id = sessionN, startT = floor(time()), startGT = t, lastActGT = t, mapID = mapID, x = x, y = y,
    zone = zoneName(mapID), level = level and floor(level) or nil, src = spellID, said = 0, people = {},
    nearSeen = near == true, sitSrc = how or "aura" }
  if sim.on then
    session.sim = true
    session.simFire = simFire()
  end
  byGuid = {}
  changed = false
  history() -- build recognition once (outside combat)
  if session.sim then
    for _, g in ipairs(sim.guests) do addGuest(g, t) end
  end
  platesOn()
  scanAll()
  changed = false
  if self.ticker then self.ticker:Cancel() end
  self.ticker = Core.ticker(self, Campfire.SCAN_EVERY, function(s) tick(s) end)
  fire("start", session)
end

applyPlates = function()
  if not session then return end
  if Campfire.settings().showFriendPlates then platesOn() else platesRestore() end
end

-- Collector

Collector = {
  requires = { "UnitGUID" },
  events = {
    "PLAYER_STARTED_MOVING", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ZONE_CHANGED_NEW_AREA", "PLAYER_DEAD",
    "PLAYER_ENTERING_WORLD", "PLAYER_CONTROL_LOST", "PLAYER_LOGOUT", "NAME_PLATE_UNIT_ADDED", "UPDATE_MOUSEOVER_UNIT",
    "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE", "CHAT_MSG_SAY", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
  },
  unitEvents = { UNIT_AURA = { "player" } },
}
local handlers = {}

function Collector.check(self)
  if not Store.ready() then return end
  if inCombat() then
    self.deferred = true
    return
  end
  self.deferred = false
  local sit, id = sitAura()
  local before = self.sitting
  local force = self.forceStart
  self.forceStart = false
  if sit ~= nil then self.sitting = sit end
  if session then
    local near = nearbyAura()
    if near == true then session.nearSeen = true end
    if session.nearSeen and near == false then return endSession(self, "nearby") end
    if Campfire.END_ON_AURA_LOSS and sit == false then return endSession(self, "aura") end
    return
  end
  if sit == true and (before == false or force) then startSession(self, id, nearbyAura()) end
end

local function schedule(self, delay)
  if self.auraTimer then return end
  if inCombat() then
    self.deferred = true
    return
  end
  self.auraTimer = true
  if not Core.after(self, delay or AURA_THROTTLE, function(s)
    s.auraTimer = false
    s.check(s)
  end) then
    self.auraTimer = false
  end
end

handlers.UNIT_AURA = function(self) schedule(self) end

handlers.PLAYER_REGEN_ENABLED = function(self)
  if restoreWanted then platesRestore() end
  if self.deferred then schedule(self) end
end

handlers.PLAYER_REGEN_DISABLED = function(self) endSession(self, "combat") end
handlers.PLAYER_STARTED_MOVING = function(self) endSession(self, "move") end
handlers.ZONE_CHANGED_NEW_AREA = function(self) endSession(self, "zone") end
handlers.PLAYER_DEAD = function(self) endSession(self, "dead") end
handlers.PLAYER_ENTERING_WORLD = function(self) endSession(self, "loading") end
handlers.PLAYER_LOGOUT = function(self) endSession(self, "logout") end
handlers.PLAYER_CONTROL_LOST = function(self)
  if session and isTrue(call(UnitOnTaxi, "player")) then endSession(self, "taxi") end
end

handlers.NAME_PLATE_UNIT_ADDED = function(_, unit)
  unit = str(unit)
  if not session or not unit or not find(unit, "^nameplate%d+$") then return end
  sightUnit(unit, "plate")
  flushChanged()
end
handlers.UPDATE_MOUSEOVER_UNIT = function()
  if not session then return end
  sightUnit("mouseover", "mouse")
  flushChanged()
end
handlers.PLAYER_TARGET_CHANGED = function()
  if not session then return end
  sightUnit("target", "target")
  flushChanged()
end
handlers.GROUP_ROSTER_UPDATE = function()
  if not session or inCombat() then return end
  scanGroup()
  flushChanged()
end

local function chat(_, _, playerName, ...)
  local guid = select(10, ...) -- arg 12 of the payload
  chatSpeaker(playerName, guid)
end

-- who spoke last (never the text). p = person of the session (only for who = 'other')
talked = function(who, p)
  local s = session
  if not s then return end
  s.talk = { gt = now(), who = who, guid = p and p.guid or nil, name = p and p.name or nil }
  fire("talk", s)
end

-- say at the fire: you or a person 'at the fire' (sure). Someone merely nearby does not count as talk.
local function sayHeard(guid)
  if not session or inCombat() then return end
  guid = validGuid(guid)
  if not guid then return end
  if guid == myGuid() then return talked("self") end
  local p = byGuid[guid]
  if p and p.sure then talked("other", p) end
end

handlers.CHAT_MSG_SAY = function(self, _, playerName, ...)
  chat(self, nil, playerName, ...)
  sayHeard((select(10, ...)))
end
handlers.CHAT_MSG_EMOTE = chat
handlers.CHAT_MSG_TEXT_EMOTE = chat

function Collector:onEvent(event, ...)
  local h = handlers[event]
  if h then h(self, ...) end
end

-- sit key, jumping and emotes: standing up without movement ends the session; sitting by key checks the sit aura
-- start a sim round (sit key/emote or command). -> true | false, reason
local function simStart(self, how)
  if not sim.on then return false, "aus" end
  if session then return false, "läuft" end
  if not Store.ready() then return false, "nicht bereit" end
  if inCombat() then return false, "Kampf" end
  if isTrue(call(UnitOnTaxi, "player")) or isTrue(call(IsMounted)) or isTrue(call(IsFlying)) then
    return false, "beritten"
  end
  startSession(self, nil, nearbyAura(), how)
  return true
end

local function sitKey(self)
  if session then return endSession(self, "stand") end
  if sim.on and simStart(self, "taste") then return end
  self.forceStart = true
  self.auraTimer = false
  schedule(self, SIT_RECHECK)
end

function Collector:init()
  self.sitting = nil   -- nil = no state read yet (the first state is never a start)
  self.deferred = false
  self.auraTimer = false
  self.forceStart = false
  -- restore pending (reload or crash during a session)?
  local char = Store.char()
  local st = char and type(char.snapshots) == "table" and char.snapshots.state
  local saved = type(st) == "table" and st.campfirePlates or nil
  if type(saved) == "table" and (saved.old == "0" or saved.old == "1") then
    plates = { old = saved.old }
    platesRestore()
  elseif saved ~= nil then
    Store.dropSnapshot("state", "campfirePlates") -- unknown value: never passed to SetCVar, discard
  end
  Core.hook(self, "SitStandOrDescendStart", function(s) sitKey(s) end)
  Core.hook(self, "JumpOrAscendStart", function(s) endSession(s, "jump") end)
  Core.hook(self, "DoEmote", function(s, token)
    token = str(token)
    if not token then return end
    token = string.upper(token)
    if token == "STAND" then
      endSession(s, "stand")
    elseif token == "SIT" and not session then
      sitKey(s)
    end
  end)
  Core.after(self, FIRST_READ, function(s)
    if s.sitting == nil and Store.ready() and not inCombat() then
      local sit = sitAura()
      if sit ~= nil then s.sitting = sit end
    end
  end)
end

ns.RegisterCollector("Campfire", Collector)

-- /chronik feuer

-- end codes of a round (diag.lastEnd); the display is in T['why_<code>']
local WHY_CODES = {
  move = true, stand = true, jump = true, combat = true, zone = true, dead = true, loading = true, logout = true, taxi = true,
  idle = true, nearby = true, aura = true, manual = true, simoff = true, simstand = true,
}

local function whyText(code)
  return WHY_CODES[code] and T["why_" .. code] or "?"
end

local function yesNo(v)
  if v == nil then return T.unreadable end
  return v and T.yes or T.no
end

local function personLine(p, t)
  local name = ns.Sanitize.display(p.full or p.name) or "?"
  local bits = {}
  if p.class then bits[#bits + 1] = ns.Sanitize.display(p.class) end
  if p.level then bits[#bits + 1] = T("level", Store.int(p.level)) end
  local srcs = {}
  for _, k in ipairs({ "group", "plate", "target", "mouse", "chat", "sim" }) do
    if p.srcs and p.srcs[k] then srcs[#srcs + 1] = k end
  end
  local state = p.sim and T.stateSim or (p.sure and (p.aura and T.stateAura or T.stateLingered) or T.stateNearby)
  local line = T("person", name,
    #bits > 0 and (" (" .. table.concat(bits, ", ") .. ")") or "", table.concat(srcs, "+"), floor(p.dwell or 0), state)
  if p.past then
    local zone = p.past.lastZone and ns.Sanitize.display(p.past.lastZone) or nil
    line = line .. T("past", p.past.n or 0, zone and T("pastLast", zone) or "")
  end
  if not p.lastGT then line = line .. T.noRange end
  if p.restHint and not p.aura then line = line .. T.restHint end
  if t and p.lastGT and t - p.lastGT > Campfire.GAP_UNIT then line = line .. T("lastSeen", floor(t - p.lastGT)) end
  return line
end

function Campfire.savedCounts()
  local n, m = 0, 0
  for _, r in ipairs(Campfire.rounds(Store.char())) do
    n = n + 1
    if r.sim then m = m + 1 end
  end
  return n, m
end

function Campfire.statusLine()
  local s = session
  if s then
    return T("roundRunning", floor(now() - s.startGT), #s.people)
  end
  return T.roundNone .. (Campfire.diag.lastEnd and T("roundLastEnd", whyText(Campfire.diag.lastEnd)) or "")
end

function Campfire.slash(rest)
  rest = type(rest) == "string" and string.lower(rest) or ""
  if rest == "test" then
    local notes = ns.Journal and ns.Journal.FireNotes
    if notes and type(notes.test) == "function" then
      notes.test()
    else
      Core.print(T.notesMissing)
    end
    return
  end
  if inCombat() then
    Core.print(T.combatNoRead)
  else
    local sit = sitAura()
    Core.print(T("sitAura", tostring(Campfire.SIT_SPELLS[1]),
      yesNo(sit), Campfire.NEARBY_SPELL, yesNo(nearbyAura())))
  end
  local cv = getCVar(Campfire.PLATES_CVAR)
  local auto = Campfire.settings().showFriendPlates
  Core.print(T("plates",
    cv == nil and T.unknown or (cv ~= "0" and T.on or T.off), Campfire.PLATES_CVAR, cv and ns.Sanitize.display(cv) or "?",
    auto and T.on or T.off, Campfire.diag.plates and T("platesLast", word(Campfire.diag.plates)) or ""))
  if cv == "0" and not auto then
    Core.print(T.platesTip)
  end
  Core.print(T("auraRead", Campfire.diag.auraRead and word(Campfire.diag.auraRead) or T.notChecked))
  local s = session or lastSession
  Core.print(Campfire.simLine())
  if s then Core.print(T("sitSignal", Campfire.sitSourceText(s))) end
  Core.print(Campfire.statusLine())
  local saved, probe = Campfire.savedCounts()
  Core.print(T("roundsSaved", saved, probe))
  if s then
    local zone = s.zone and ns.Sanitize.display(s.zone) or "?"
    Core.print(T("roundSummary", session and T.thisRound or T.lastRound,
      s.sim and T.probe or "", zone, #s.people, s.said or 0, s.written and T.inLog or (session and "" or T.notInLog)))
    local t = session and now() or nil
    for _, p in ipairs(s.people) do Core.print(personLine(p, t)) end
  end
end

-- Retail simulation: Retail 12.x has neither the Forever sit aura (1289723) nor a readable sit state. A sim round starts with the sit key / SIT emote
-- or '/chronik sim feuer setzen' (aura 7353 is only noted in session.simFire), ends like a real one and lasts only until reload.

local function simPrefix() return T.simSayPrefix end
local GUEST_NAME_MAX = 24

function Campfire.isSim() return sim.on end
function Campfire.simLoud() return sim.loud end

-- sim switch. Off ends a running trial round and forgets the dummy guests.
function Campfire.setSim(on)
  on = on == true
  if on == sim.on then return false end
  if not on then
    if session and session.sim then endSession(Collector, "simoff") end
    sim.guests = {}
    sim.loud = false
  end
  sim.on = on
  hist = nil
  return true
end

function Campfire.setSimLoud(on)
  sim.loud = on == true
  return sim.loud
end

local function chatLine(line)
  local frame = rawget(_G, "DEFAULT_CHAT_FRAME")
  local types = rawget(_G, "ChatTypeInfo")
  local info = type(types) == "table" and not isSecret(types) and types.SAY or nil
  if type(frame) == "table" and type(frame.AddMessage) == "function" then
    if type(info) == "table" and num(info.r) and num(info.g) and num(info.b) then
      pcall(frame.AddMessage, frame, line, info.r, info.g, info.b)
    else
      pcall(frame.AddMessage, frame, line)
    end
  else
    Core.print(line)
  end
end

-- local chat line instead of /say. -> true = done (do not send), false = really send
function Campfire.simSay(text)
  if not sim.on or sim.loud then return false end
  if isSecret(text) or type(text) ~= "string" or text == "" then return true end
  chatLine(simPrefix() .. ns.Sanitize.display(ns.Sanitize.cut(text, 255)))
  return true
end

-- a dummy guest speaks (shown locally only, never sent, text never remembered)
function Campfire.simGuestSay(name, text)
  if not sim.on then return nil, T.simOff end
  local s = session
  if not (s and s.sim) then return nil, T.noProbeRound end
  name = cleanName(name)
  if not name then return nil, T.nameMissing end
  if isSecret(text) or type(text) ~= "string" then return nil, T.textMissing end
  text = gsub(gsub(text, "^%s+", ""), "%s+$", "")
  if text == "" then return nil, T.textMissing end
  local low, p = string.lower(name), nil
  for _, q in ipairs(s.people) do
    if q.sim and type(q.name) == "string" and string.lower(q.name) == low then p = q end
  end
  if not p then return nil, T.noGuestAtFire end
  chatLine(T("guestSays", ns.Sanitize.display(p.name) or "?", ns.Sanitize.display(ns.Sanitize.cut(text, 255)) or ""))
  talked("other", p)
  return p
end

function Campfire.simSit() return simStart(Collector, "befehl") end

function Campfire.simStand()
  if not session then return false end
  endSession(Collector, "simstand")
  return true
end

-- classes for dummy guests: file name or German name (the grammatical form decides the sex)
local CLASS_FILES = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true, DEATHKNIGHT = true,
  SHAMAN = true, MAGE = true, WARLOCK = true, MONK = true, DRUID = true, DEMONHUNTER = true, EVOKER = true }
local CLASS_DE = {
  krieger = { "WARRIOR", 2 }, kriegerin = { "WARRIOR", 3 }, paladin = { "PALADIN" }, ["jäger"] = { "HUNTER", 2 },
  ["jägerin"] = { "HUNTER", 3 }, jaeger = { "HUNTER", 2 }, jaegerin = { "HUNTER", 3 }, schurke = { "ROGUE", 2 },
  schurkin = { "ROGUE", 3 }, priester = { "PRIEST", 2 }, priesterin = { "PRIEST", 3 }, todesritter = { "DEATHKNIGHT", 2 },
  todesritterin = { "DEATHKNIGHT", 3 }, schamane = { "SHAMAN", 2 }, schamanin = { "SHAMAN", 3 }, magier = { "MAGE", 2 },
  magierin = { "MAGE", 3 }, hexenmeister = { "WARLOCK", 2 }, hexenmeisterin = { "WARLOCK", 3 }, ["mönch"] = { "MONK", 2 },
  ["mönchin"] = { "MONK", 3 }, moench = { "MONK", 2 }, moenchin = { "MONK", 3 }, druide = { "DRUID", 2 },
  druidin = { "DRUID", 3 }, ["dämonenjäger"] = { "DEMONHUNTER", 2 }, ["dämonenjägerin"] = { "DEMONHUNTER", 3 },
  rufer = { "EVOKER", 2 }, ruferin = { "EVOKER", 3 },
}

local function classOf(word)
  word = str(word)
  if not word then return nil end
  local up = string.upper(word)
  if CLASS_FILES[up] then return up, nil end
  local low = string.lower(word)
  local de = CLASS_DE[low]
  if de then return de[1], de[2] end
  local lists = { rawget(_G, "LOCALIZED_CLASS_NAMES_MALE"), rawget(_G, "LOCALIZED_CLASS_NAMES_FEMALE") }
  for i = 1, 2 do
    local tbl = lists[i]
    if type(tbl) == "table" and not isSecret(tbl) then
      for file, name in pairs(tbl) do
        if CLASS_FILES[file] and str(name) and string.lower(name) == low then return file, i == 1 and 2 or 3 end
      end
    end
  end
  return nil
end

-- stable dummy GUID from the name (server 0 = simulation)
local function guestGuid(name)
  local h = 5381
  local low = string.lower(name)
  for i = 1, #low do h = (h * 33 + string.byte(low, i)) % 4294967296 end
  return format("Player-0-%08X", h)
end

-- create a dummy guest. -> guest | nil, error text
function Campfire.simGuest(name, class, level, sex)
  if not sim.on then return nil, T.simOff end
  name = cleanName(name)
  if name then name = ns.Sanitize.cut((gsub(name, "[%s%-,;]", "")), GUEST_NAME_MAX) end
  if not name or name == "" then return nil, T.nameMissing end
  local file, formSex = classOf(class)
  if not file then return nil, T.classUnknown end
  level = tonumber(level)
  if not num(level) or level < 1 or level > Campfire.SIM_LEVEL_MAX or level ~= floor(level) then
    return nil, T("levelRange", Campfire.SIM_LEVEL_MAX)
  end
  if sex == "w" then sex = 3 elseif sex == "m" then sex = 2 else sex = formSex or 2 end
  local realm = ownRealm() or "Sim"
  local g = { guid = guestGuid(name), name = name, realm = realm, full = ns.Sanitize.cut(name .. "-" .. realm, NAME_MAX),
    class = file, level = floor(level), sex = sex }
  local replaced = false
  for i, old in ipairs(sim.guests) do
    if old.guid == g.guid then
      sim.guests[i] = g
      replaced = true
    end
  end
  if not replaced then
    if #sim.guests >= Campfire.SIM_GUEST_MAX then
      return nil, T("guestMax", Campfire.SIM_GUEST_MAX)
    end
    sim.guests[#sim.guests + 1] = g
  end
  if session and session.sim then
    local p = byGuid[g.guid]
    if p then
      p.class, p.level, p.sex = g.class, g.level, g.sex
    else
      addGuest(g, now())
    end
    fire("update", session)
  end
  return g
end

-- remove a dummy guest (by name, case-insensitive), also during a running trial round: out of the guest list and out of the round
-- (people, index, talk marker). -> true | nil, error
function Campfire.simGuestRemove(name)
  if not sim.on then return nil, T.simOff end
  name = cleanName(name)
  if not name then return nil, T.nameMissing end
  local low, found = string.lower(name), false
  for i = #sim.guests, 1, -1 do
    local g = sim.guests[i]
    if type(g.name) == "string" and string.lower(g.name) == low then
      table.remove(sim.guests, i)
      found = true
      local s = session
      if s and s.sim then
        for k = #s.people, 1, -1 do
          if s.people[k].guid == g.guid then table.remove(s.people, k) end
        end
        byGuid[g.guid] = nil
        if s.talk and s.talk.guid == g.guid then s.talk = nil end
        fire("update", s)
      end
    end
  end
  if not found then return nil, T.noGuest end
  return true
end

function Campfire.simGuests()
  local out = {}
  for i, g in ipairs(sim.guests) do out[i] = g end
  return out
end

-- remove only LF lines with sim = 1 (log blocks and open block). -> number of removed lines
local function isSimLine(line, pos)
  local code, rest = match(line, "^%-?%d+~(%u+)~?(.*)$")
  if code ~= "LF" then return false end
  return splitOn(rest, "~")[pos] == "1"
end

function Campfire.dropSimRounds()
  local char = Store.char()
  local pos = lfPos().sim
  if type(char) ~= "table" or not pos then return 0 end
  local removed = 0
  local log = char.log
  if type(log) == "table" then
    local out, n = {}, #log
    for i = 1, n do
      local block = log[i]
      if type(block) == "string" and find(block, "~LF~", 1, true) then
        local lines = splitOn(block, "\n")
        local keep, drop = { lines[1] }, 0
        for k = 2, #lines do
          if isSimLine(lines[k], pos) then drop = drop + 1 else keep[#keep + 1] = lines[k] end
        end
        removed = removed + drop
        if drop == 0 then
          out[#out + 1] = block
        elseif #keep > 1 then
          out[#out + 1] = table.concat(keep, "\n")
        end -- only the header is left: the block goes away
      else
        out[#out + 1] = block
      end
    end
    if removed > 0 then
      for i = 1, n do log[i] = out[i] end
    end
  end
  local b = Store.block
  if Store.current == char and type(b) == "table" and type(b.lines) == "table" then
    local keep = {}
    for _, line in ipairs(b.lines) do
      if type(line) == "string" and isSimLine(line, pos) then removed = removed + 1 else keep[#keep + 1] = line end
    end
    if #keep ~= #b.lines then b.lines = keep end
  end
  if removed > 0 then
    if type(char.lineCount) == "number" then char.lineCount = math.max(0, char.lineCount - removed) end
    hist = nil
    if lastSession and lastSession.sim then lastSession.written = false end
    local J = ns.Journal
    if J and J.Index and type(J.Index.invalidate) == "function" then Core.safe(J.Index.invalidate) end
    if J and J.Model and type(J.Model.invalidate) == "function" then Core.safe(J.Model.invalidate) end
  end
  return removed
end

local SIT_SRC = { aura = "srcAura", taste = "srcKey", befehl = "srcCommand" }

function Campfire.sitSourceText(s)
  if type(s) ~= "table" then return "-" end
  local t = SIT_SRC[s.sitSrc] and T[SIT_SRC[s.sitSrc]] or "?"
  if s.sitSrc == "aura" and s.src then t = t .. " " .. Store.int(s.src) end
  if s.sim then t = t .. T("simFire", Campfire.SIM_FIRE_SPELLS[1], yesNo(s.simFire)) end
  return t
end

function Campfire.simLine()
  if not sim.on then return T.simLineOff end
  return T("simLineOn", sim.loud and T.loudSay or T.localOnly, #sim.guests)
end

local SIM_HELP = { "helpOnOff", "helpSit", "helpGuest", "helpSay", "helpLoud", "helpClear" } -- keys; texts are filled in when printing

local function printSimHelp()
  for _, key in ipairs(SIM_HELP) do Core.print(T[key]) end
end

-- English subcommands -> the German ones (both work)
local SIM_CMDS = { on = "an", off = "aus", sit = "setzen", stand = "aufstehen", guest = "gast", loud = "laut", clear = "löschen" , say = "sagt" }
Campfire.SIM_HELP = SIM_HELP -- keys (texts: Campfire.simHelpLines())

function Campfire.simHelpLines()
  local out = {}
  for i, key in ipairs(SIM_HELP) do out[i] = T[key] end
  return out
end

local function simStatus()
  Core.print(Campfire.simLine())
  if not inCombat() then
    Core.print(T("retailFire", Campfire.SIM_FIRE_SPELLS[1], yesNo(simFire())))
  end
  for _, g in ipairs(sim.guests) do
    Core.print(T("guestLine", ns.Sanitize.display(g.full), g.class, g.level))
  end
  Core.print(Campfire.statusLine())
end

function Campfire.simSlash(text)
  text = type(text) == "string" and not isSecret(text) and text or ""
  local words = {}
  for w in gmatch(text, "%S+") do
    words[#words + 1] = w
    if #words >= 7 then break end
  end
  local topic = string.lower(words[1] or "")
  if topic ~= "feuer" and topic ~= "lagerfeuer" and topic ~= "campfire" then
    printSimHelp()
    return
  end
  local cmd = string.lower(words[2] or "status")
  cmd = SIM_CMDS[cmd] or cmd
  if cmd == "an" then
    Campfire.setSim(true)
    Core.print(T.simOn)
  elseif cmd == "aus" then
    Campfire.setSim(false)
    Core.print(T.simOffNow)
  elseif cmd == "status" then
    simStatus()
  elseif cmd == "setzen" then
    local ok, why = simStart(Collector, "befehl")
    if ok then
      Core.print(T.probeRunning)
    elseif why == "aus" then
      Core.print(T.simFirstOn)
    elseif why == "läuft" then
      Core.print(T.alreadyRunning)
    else
      local whyKey = (why == "nicht bereit" and "sitWhyNotReady") or (why == "Kampf" and "sitWhyCombat")
        or (why == "beritten" and "sitWhyMounted") or nil
      Core.print(T("cantSit", whyKey and T[whyKey] or tostring(why)))
    end
  elseif cmd == "aufstehen" then
    Core.print(Campfire.simStand() and T.stoodUp or T.noRound)
  elseif cmd == "gast" then
    if not words[3] then return simStatus() end
    local g, err = Campfire.simGuest(words[3], words[4], words[5], words[6] and string.lower(words[6]) or nil)
    if g then
      Core.print(T("guestAdded", ns.Sanitize.display(g.full), g.class, g.level))
    else
      Core.print(T("guestError", err))
    end
  elseif cmd == "sagt" then
    -- name = third word (without a trailing ':' or ','), everything after is the text
    local name, said = match(text, "^%s*%S+%s+%S+%s+(%S+)%s*(.*)$")
    if name then name = gsub(name, "[:,;]+$", "") end
    local p, err = Campfire.simGuestSay(name, said)
    if not p then Core.print(T("sayError", err)) end
  elseif cmd == "laut" then
    local arg = string.lower(words[3] or "")
    local on = (arg == "an") or (arg == "on") or (arg ~= "aus" and arg ~= "off" and not sim.loud)
    Campfire.setSimLoud(on)
    Core.print(on and T.loudOn or T.loudOff)
  elseif cmd == "löschen" or cmd == "loeschen" or cmd == "lÖschen" then
    local n = Campfire.dropSimRounds()
    Core.print(T("cleared", n))
  else
    printSimHelp()
  end
end
