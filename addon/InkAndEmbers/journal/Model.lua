-- Journey model (core of the travel map). Only reads EveNChronicleDB (block log, trail, text tables, snapshots) and prepares
-- chapters, route, markers, margin notes, header and time axis. No frame code. The model itself writes only under
-- EveNChronicleDB.ui (Model.settings / Model.setSetting: scale, speed, minimap, minimapAngle, reduceMotion, pos).
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Model = {}
Journal.Model = Model

local floor, sqrt, abs, huge, log = math.floor, math.sqrt, math.abs, math.huge, math.log
local format, match, gmatch, sub, find, gsub, upper = string.format, string.match, string.gmatch, string.sub,
  string.find, string.gsub, string.upper
local tsort = table.sort

local function clock()
  if type(debugprofilestop) == "function" then return debugprofilestop() end
  if type(os) == "table" and type(os.clock) == "function" then return os.clock() * 1000 end
  return 0
end

-- Background build: pause() yields once the frame budget is used. Only effective inside the build coroutine (inJob); built
-- synchronously it is just a comparison. Never call it inside pcall/sort.
local inJob, deadline = false, huge
local function pause()
  if inJob and clock() >= deadline then coroutine.yield() end
end

-- Thresholds (fine-tuned, see tests/journal-model.test.mjs)
Model.IDLE_GAP = 66                  -- s played without a trail point = standstill (AFK, combat on the spot, trade, offline); thinned straights bridge up to ~63 s
Model.IDLE_KEEP = 12
Model.IDLE_FLIGHT_KEEP = 60
Model.STAY_FLICKER = 30              -- s played: a shorter zone visit (zone border flicker) never forms a chapter of its own and is not named as a detour (buildChapters)
Model.TRANSIT_PLAY = 180
Model.MAX_SEGMENTS = 800
Model.LINE_POOL_MAX = 1000
Model.NOTES_MAX = 3
Model.MARKERS_MAX = 250
Model.NAME_MAX = 40
Model.TITLE_MAX = 64
Model.TITLE_VARIANTS = 60
Model.TEXT_MAX = 160
Model.BREAK_GAP = 120
Model.BREAK_DIST = 200
Model.LINK_GAP = 30
Model.YARDS_PER_STEP = 30
Model.SIMPLIFY_MIN = 0.001
Model.CLUSTER = 300
Model.THIN_TOL = 3
Model.THIN_DT = 60
Model.ASYNC = true
Model.FRAME_BUDGET = 8
Model.PREPARE_DELAY = 15
Model.COMBAT_RETRY = 2
Model.ROUTE_RETRY_SEC = 30
Model.UI_DEFAULTS = { scale = 1, speed = 60, minimap = true, minimapAngle = 225, reduceMotion = false, mapColor = "sepia", showKills = true }
Model.MAP_COLORS = { sepia = true, original = true }
Model.SPEEDS = { [20] = true, [60] = true, [180] = true }

local NUMWORD = { "ein", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "elf", "zwölf" }
local TIMES = { "einmal", "zweimal", "dreimal", "viermal", "fünfmal", "sechsmal", "siebenmal", "achtmal" }
local ROMAN = { { 1000, "M" }, { 900, "CM" }, { 500, "D" }, { 400, "CD" }, { 100, "C" }, { 90, "XC" }, { 50, "L" }, { 40, "XL" }, { 10, "X" }, { 9, "IX" }, { 5, "V" }, { 4, "IV" }, { 1, "I" } }
local SHOT_REASONS = { levelup = "Stufenaufstieg", zone = "neue Zone", kill = "besonderer Gegner", boss = "Boss",
  close_win = "knapper Sieg", death = "Tod", item = "besonderer Fund", manual = "selbst aufgenommen" }
local CAUSES = { fall = "Sturz", drown = "Ertrinken", fatigue = "Erschöpfung", lava = "Lava", fire = "Feuer",
  slime = "Schleim", environment = "Umgebung" }
local HOW = { corpse = "Leichenlauf", spirit = "Geistheiler", res = "wiederbelebt", unknown = "Weg unbekannt" }
local SPECIAL = { elite = "elite", rare = "rare", rareelite = "rare", worldboss = "boss" }
local CLS_TEXT = { elite = "Elite", rare = "Rar", boss = "Boss" }

local MT
do
  local de = {
    stampFmt = "{d}.{m}. {h}:{mi}", mapN = "Karte %s", lvShort = "St. %s", underway = "Unterwegs", levelN = "Stufe %s", unknownPlace = "unbekannter Ort",
    unknown = "unbekannt", zeroMin = "0 Min.", timesN = "%s-mal", whenFmt = "Tag %s, %s",
    firstDeath = "erster Tod", firstDeathIn = "erster Tod in %s", deathsN = "%s Tode", bossDown = "%s bezwungen",
    rareDown = "%s gestellt", level60 = "Stufe %s, das Ziel", levelReached = "Stufe %s erreicht",
    newHomeAt = "neues Zuhause: %s", newHome = "ein neues Zuhause", firstBlue = "der erste seltene Fund",
    firstEpic = "das erste lila Stück", firstMount = "das erste Reittier", newShores = "neue Ufer",
    visited = "%s besucht", descent = "ein Abstieg in die Tiefe", flightTo = "Flug nach %s", flightColon = "Flug: %s",
    questsDone = "%s Quests erledigt", storyStart = "Die Reise beginnt hier", storyTransit = "Auf der Durchreise",
    storyQuiet = "Ein ruhiger Abschnitt", thenToward = ", danach Richtung %s",
    afterPlayed = "nach %s Spielzeit", causeLine = "Ursache: %s", firstDeathTitle = "Erster Tod", deathTitle = "Tod",
    bossTag = "Boss", rareTag = "rar", eliteTag = "Elite", levelPrefix = "Stufe %s · ", timesSuffix = "%s-mal",
    memory = "Erinnerung", hearthTitle = "Ruhestein", hearthTo = "nach %s", hearthOwn = "eigenes Ziel",
    flightPoint = "Neuer Flugpunkt", flightMaster = "Flugmeister: %s",
    kills = "%s Kills", death_one = "%s Tod", death_other = "%s Tode", boss_one = "%s Boss", boss_other = "%s Bosse",
    gapInstance = "Position in der Instanz nicht lesbar", gapLocked = "Position gesperrt, Spur unterbrochen",
    instanceTitle = "Instanz", instanceNamed = "Instanz: %s", trailBroken = "Spur unterbrochen",
    duration = "Dauer %s", flight = "Flug", flightFromTo = "Flug von %s nach %s",
    noteFirstDeath = "erster Tod", noteDeath = "Tod", spiritTimes = "%s Geistheiler", diedTimes = "%s gestorben",
    toughest = "Stärkster Gegner: %s%s", levelUnknownParen = " (Stufe ??)", levelParen = " (Stufe %s)",
    noteFlight = "Flug · %s", noteLongestFlight = "längster Flug · %s", noteMilestone = "%s · Stufe %s",
    range = " · %s bis %s", stays_one = "%s Zonenaufenthalt", stays_other = "%s Zonenaufenthalte", approx = "ca. ",
    onFoot = "%s km zu Fuß", flights_one = "%s Flug", flights_other = "%s Flüge", totalTitle = "Gesamtreise",
    statsFlights_one = "%s Flug", statsFlights_other = "%s Flüge", statsHearths_one = "%s Ruhestein",
    statsHearths_other = "%s Ruhesteine", statsDay = "Tag %s", detours_one = "Abstecher: %s",
    detours_other = "Abstecher: %s",
  }
  for i, w in ipairs(NUMWORD) do de["num_" .. i] = w end
  for i, w in ipairs(TIMES) do de["times_" .. i] = w end
  for k, w in pairs(SHOT_REASONS) do de["shot_" .. k] = w end
  for k, w in pairs(CAUSES) do de["cause_" .. k] = w end
  for k, w in pairs(HOW) do de["how_" .. k] = w end
  for k, w in pairs(CLS_TEXT) do de["cls_" .. k] = w end
  MT = ns.Locale.ns("Model", de)
end

local MAP_FIELD = { LV = 2, QA = 4, QT = 4, QX = 4, BK = 4, DE = 2, DB = 4, ZN = 1, SZ = 1, EX = 3,
  FP = 2, TP = 2, TF = 6, TL = 2, HS = 3, HB = 2, MO = 5, SH = 5, GW = 6, SP = 4, RP = 6,
  GS = 5, GE = 7, DU = 4, PK = 6, PD = 4, AH = 10, TH = 7 }
local LEVEL_FIELD = { RS = 6, PL = 3, QA = 2, QT = 2, DE = 1 }

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local MAX_INT = 2 ^ 53 -- largest number safely printed as an integer; "%.0f" instead of "%d" (above 2^31 in the test VM / 2^63 in the client "%d" is undefined or an error)
local function int(x)
  if x ~= x then return "0" end
  if x > MAX_INT then x = MAX_INT elseif x < -MAX_INT then x = -MAX_INT end
  return format("%.0f", floor(x) + 0)
end

-- Memo for sanitized texts: only short inputs (Model.MEMO_KEY_MAX bytes) are memoised, so a manipulated SV with huge fields cannot fill memory with long keys.
Model.MEMO_KEY_MAX = 256

local plainMemo, plainMemoN = {}, 0
local function plain(s, n)
  local S = ns.Sanitize
  if not S or not S.plain then return nil end
  n = n or Model.NAME_MAX
  if type(s) ~= "string" or #s > Model.MEMO_KEY_MAX then return S.plain(s, n) end
  local key = n .. "\1" .. s
  local v = plainMemo[key]
  if v == nil then
    v = S.plain(s, n) or false
    if plainMemoN > 4000 then plainMemo, plainMemoN = {}, 0 end
    plainMemo[key], plainMemoN = v, plainMemoN + 1
  end
  return v or nil
end

local dispMemo, dispMemoN = {}, 0
local function disp(s, n)
  local S = ns.Sanitize
  if not S or not S.display then return nil end
  n = n or Model.TEXT_MAX
  if type(s) ~= "string" or #s > Model.MEMO_KEY_MAX then return S.display(s, n) end
  local key = n .. "\1" .. s
  local v = dispMemo[key]
  if v == nil then
    v = S.display(s, n) or false
    if dispMemoN > 4000 then dispMemo, dispMemoN = {}, 0 end
    dispMemo[key], dispMemoN = v, dispMemoN + 1
  end
  return v or nil
end

local function nz(v)
  if v == nil or v == "" then return nil end
  return tonumber(v)
end

local function single(s) return s ~= nil and not find(s, " ", 1, true) end

local function roman(n)
  local out = ""
  for _, r in ipairs(ROMAN) do
    while n >= r[1] do
      out = out .. r[2]
      n = n - r[1]
    end
  end
  return out
end

local function capital(s)
  if not s then return s end
  local n = (s:byte(1) or 0) >= 192 and 2 or 1
  return ns.Journal.Fmt.upper(sub(s, 1, n)) .. sub(s, n + 1)
end

local function times(n) return TIMES[n] and MT["times_" .. n] or MT("timesN", int(n)) end
local function numword(n) return NUMWORD[n] and MT["num_" .. n] or int(n) end

function Model.formatPlayed(sec)
  sec = floor(tonumber(sec) or 0)
  if sec < 0 then sec = 0 end
  return ns.Journal.Fmt.duration(sec) or MT.zeroMin
end

local function bsearch(arr, v)
  local lo, hi = 1, #arr
  if hi == 0 or arr[1] > v then return 0 end
  while lo < hi do
    local mid = floor((lo + hi + 1) / 2)
    if arr[mid] <= v then lo = mid else hi = mid - 1 end
  end
  return lo
end

local function openSpan(J, t)
  J.spanOpen, J.spanStart = true, t
end

local function closeSpan(J, t)
  if not J.spanOpen then return end
  J.spanOpen = false
  if t < J.spanStart then t = J.spanStart end
  local n = #J.spT0 + 1
  J.spT0[n], J.spT1[n] = J.spanStart, t
end

local function finishSpans(J)
  if J.spanOpen then
    closeSpan(J, J.lastT)
    J.spLastOpen = true
  end
  local cum = 0
  for i = 1, #J.spT0 do
    J.spCum[i] = cum
    cum = cum + (J.spT1[i] - J.spT0[i])
  end
  J.playedTotal = cum
end

local function played(J, t)
  local i = bsearch(J.spT0, t)
  if i == 0 then return 0 end
  local d, len = t - J.spT0[i], J.spT1[i] - J.spT0[i]
  if d > len and not (i == #J.spT0 and J.spLastOpen) then d = len end
  return J.spCum[i] + d
end

local function timeAt(J, p)
  local i = bsearch(J.spCum, p)
  if i == 0 then return J.firstT end
  local d, len = p - J.spCum[i], J.spT1[i] - J.spT0[i]
  if d > len and not (i == #J.spCum and J.spLastOpen) then d = len end
  return J.spT0[i] + d
end

local function tzAt(J, t)
  local i = bsearch(J.tzT, t)
  if i == 0 then return J.tz0 end
  return J.tzV[i]
end

local function dayOf(J, t)
  return floor((t + tzAt(J, t)) / 86400) - floor((J.startT + tzAt(J, J.startT)) / 86400) + 1
end

local function when(J, t)
  local s = (t + tzAt(J, t)) % 86400
  return MT("whenFmt", int(dayOf(J, t)), format("%02d:%02d", floor(s / 3600), floor(s % 3600 / 60)))
end

local function mapName(J, id)
  if not id then return nil end
  local s = J.snap.maps and J.snap.maps[id]
  local n = type(s) == "table" and plain(s.name) or nil
  if n then return n end
  local V = ns.Journal and ns.Journal.View
  if V and type(V.mapName) == "function" then
    local ok, live = pcall(V.mapName, id)
    if ok and type(live) == "string" and live ~= "" then return live end
  end
  return nil
end

local function zoneOf(J, m)
  if not m then return nil end
  local k = J.zoneKey[m]
  if k == nil then
    local info = J.zn[m]
    if info and info.type and info.type <= 2 then
      k = m
      J.nonQual[m] = true
    elseif info and info.zone then
      k = info.zone
    else
      local g
      if J.geo and J.geo.zoneOf then
        local ok, v = pcall(J.geo.zoneOf, m)
        g = ok and tonumber(v) or nil
      end
      k = g or m
    end
    J.zoneKey[m] = k
  end
  return k
end

local function startZoneOf(m)
  local G = Journal.Geo
  if not m or not (G and G.startZoneOf) then return nil end
  local ok, v = pcall(G.startZoneOf, m)
  v = ok and tonumber(v) or nil
  if v and v == v and v > 0 then return floor(v) end
  return nil
end

-- Main zone for the chapters: zoneOf; if that zone lies in another zone (Geo chain, Retail: Elwynn subzone in Elwynn 37) the
-- outermost counts. Exception: a start zone with its own map (Northshire 425, New Tinkertown 469, also gnome start map 30 and
-- its caves) is its own main zone and chapter. Forever/Classic start zones have no own map; zoneOf is already the main zone.
local function mainZoneOf(J, m)
  if not m then return nil end
  local s = J.startKey[m]
  if s == nil then
    s = startZoneOf(m) or false
    J.startKey[m] = s
  end
  if s then return s end
  local z = zoneOf(J, m)
  if not z or J.nonQual[z] then return z end
  local k = J.mainKey[z]
  if k == nil then
    local start = startZoneOf(z)
    k = start or z
    if not start and J.geo and J.geo.mainZoneOf then
      local ok, v = pcall(J.geo.mainZoneOf, z)
      v = ok and tonumber(v) or nil
      local info = v and J.zn[v]
      if v and v == v and v > 0 and not (info and info.type and info.type <= 2) then k = floor(v) end
    end
    J.mainKey[z] = k
  end
  return k
end

local function continentOf(J, m)
  if not m then return nil end
  local c = J.contOf[m]
  if c == nil then
    local info = J.zn[m]
    if info and info.type == 2 then c = m
    elseif info and info.cont then c = info.cont
    elseif J.geo and J.geo.continentOf then
      local ok, v = pcall(J.geo.continentOf, m)
      c = ok and tonumber(v) or nil
    end
    J.contOf[m] = c or false
  end
  return c or nil
end

local function mapSize(J, m)
  local s = J.sizeOf[m]
  if s == nil then
    s = false
    if J.geo and J.geo.mapSize then
      local ok, w, h = pcall(J.geo.mapSize, m)
      if ok and tonumber(w) and tonumber(h) then s = { w, h } end
    end
    J.sizeOf[m] = s
  end
  return s or nil
end

local F = { n = 0 }
local function split(rest)
  local n = 0
  for f in gmatch(rest .. "~", "([^~]*)~") do
    n = n + 1
    F[n] = f
  end
  for i = n + 1, F.n do F[i] = nil end
  F.n = n
  return n
end

local function push(list, v) list[#list + 1] = v return v end

local H = {}
local RAW = {}

H.L = function(J, t)
  if J.spanOpen then closeSpan(J, J.lastT) end
  openSpan(J, t)
  local tz = nz(F[6])
  if tz then
    J.tzT[#J.tzT + 1], J.tzV[#J.tzV + 1] = t, tz
  end
  push(J.breaks, t)
end
H.O = function(J, t) closeSpan(J, t) end
H.LV = function(J, t)
  local lv = nz(F[1])
  if lv then push(J.lv, { t = t, level = lv, map = nz(F[2]), x = nz(F[3]), y = nz(F[4]) }) end
end
RAW.KI = function(J, t, rest)
  -- Fields 1-4 (npcID, level, class, map) and 10-11 (x, y: kill position, 0..9999; old lines without)
  local npc, lvl, cls, map, kx, ky = match(rest,
    "^([^~]*)~?([^~]*)~?([^~]*)~?([^~]*)~?[^~]*~?[^~]*~?[^~]*~?[^~]*~?[^~]*~?([^~]*)~?([^~]*)")
  local n0 = #J.kT + 1
  J.kT[n0] = t
  J.kN[n0] = tonumber(npc) or false
  lvl = tonumber(lvl)
  J.kL[n0] = lvl and (lvl > 0 and floor(lvl) or (lvl == -1 and -1)) or false -- level of the enemy; -1 = boss/??; false = unknown
  map = tonumber(map)
  -- Position packed into one number: (map * 10000 + x) * 10000 + y; false = unknown (instance, old line)
  kx, ky = tonumber(kx), tonumber(ky)
  if map and map > 0 and kx and ky and kx >= 0 and kx <= 9999 and ky >= 0 and ky <= 9999 then
    J.kP[n0] = (floor(map) * 10000.0 + floor(kx)) * 10000.0 + floor(ky) -- floating point: integers are 32 bit in the test VM
  else
    J.kP[n0] = false
  end
  if map and map > 0 then
    local n = #J.sT + 1
    J.sT[n], J.sM[n] = t, map
  end
  lvl = tonumber(lvl)
  local tag = SPECIAL[cls]
  if lvl == -1 then tag = "boss" end
  if tag then
    split(rest)
    push(J.specials, { t = t, npc = nz(F[1]), level = lvl, tag = tag, map = nz(F[4]), name = F[8], plevel = nz(F[9]),
      x = nz(F[10]), y = nz(F[11]) })
  end
end
H.DE = function(J, t)
  push(J.deaths, { t = t, level = nz(F[1]), map = nz(F[2]), x = nz(F[3]), y = nz(F[4]), inst = F[5] == "1" })
end
H.DC = function(J, t)
  local d = J.deaths[#J.deaths]
  if d and not d.cause and t - d.t <= 120 then d.cause, d.npc, d.source = F[4], nz(F[1]), F[2] end
end
H.DB = function(J, t)
  push(J.breaks, t)
  local d = J.deaths[#J.deaths]
  if d and not d.how and t - d.t <= 7200 then d.how = F[1] end
  if F[1] == "spirit" then push(J.spirits, { t = t, map = nz(F[4]), x = nz(F[5]), y = nz(F[6]) }) end
end
H.QA = function(J, t)
  J.qaN = J.qaN + 1
  push(J.evX, t)
end
H.QT = function(J, t) push(J.qt, { t = t, qid = nz(F[1]) }) end
H.SH = function(J, t)
  push(J.shots, { t = t, key = F[1], reasons = F[2], level = nz(F[4]), map = nz(F[5]), x = nz(F[6]), y = nz(F[7]) })
end
H.HS = function(J, t)
  push(J.breaks, t)
  push(J.hs, { t = t, bind = F[2], map = nz(F[3]), x = nz(F[4]), y = nz(F[5]) })
end
H.HB = function(J, t) push(J.hb, { t = t, bind = F[1], map = nz(F[2]) }) end
H.TF = function(J, t) push(J.tf, { t = t, from = F[1], to = F[2], cost = nz(F[3]) }) end
H.TL = function(J, t) push(J.tl, { t = t, sec = nz(F[1]), map = nz(F[2]), x = nz(F[3]), y = nz(F[4]) }) end
H.FP = function(J, t) push(J.fp, { t = t, npc = nz(F[1]), map = nz(F[2]), x = nz(F[3]), y = nz(F[4]), name = F[6] }) end
H.IE = function(J, t)
  push(J.breaks, t)
  local g = push(J.gaps, { kind = "instance", t0 = t, inst = nz(F[1]), itype = F[2] })
  J.openInst = g
end
H.IL = function(J, t)
  push(J.breaks, t)
  local g = J.openInst
  if g and not g.t1 then
    g.t1, g.kills, g.ideaths, g.bosses = t, nz(F[3]), nz(F[4]), nz(F[5])
  end
  J.openInst = nil
end
H.TP = function(J, t)
  local reason = F[1]
  if reason == "taxi" then return end
  push(J.breaks, t)
  if J.openInst and not J.openInst.t1 then return end
  push(J.gaps, { kind = (reason == "instance") and "instance" or "unreadable", t0 = t, map = nz(F[2]) })
end
H.IB = function(J, t) if F[2] == "1" then push(J.ib, { t = t, enc = nz(F[1]), inst = nz(F[6]) }) end end
H.MO = function(J, t) push(J.mo, { t = t, kind = F[1], value = F[2], detail = F[3], level = nz(F[4]), map = nz(F[5]) }) end
H.SZ = function(J, t) push(J.sz, { t = t, map = nz(F[1]), name = F[2] }) end
H.ZN = function(J, t)
  local m = nz(F[1])
  if m and not J.zn[m] then J.zn[m] = { type = nz(F[2]), zone = nz(F[3]), cont = nz(F[4]), t = t } end
end
H.EX = function(J, t) push(J.ex, t) end
H.TB = function(J, t) push(J.tb, t) end
H.RT = function(J, t) push(J.rt, { t = t, faction = F[1], standing = nz(F[3]), prev = nz(F[4]), name = F[5] }) end
H.GS = function(J, t) push(J.gs, t) end
H.GM = function(J, t) push(J.gm, { t = t, name = F[1] }) end
H.GU = function(J, t) if F[1] == "join" or F[1] == "change" then push(J.gu, { t = t, guild = F[2] }) end end
H.DU = function(J, t) if F[2] == "win" then push(J.du, t) end end
H.PK = function(J, t) push(J.pk, t) end
H.BK = function(J, t) if F[5] == "1" then push(J.bk, { t = t, key = F[1] }) end end
H.TA = function(J, t) if nz(F[3]) == 1 and nz(F[2]) and nz(F[2]) > 0 then push(J.ta, t) end end
H.SP = function(J, t) push(J.sp, t) end
H.VE = function(J, t) push(J.evX, t) end
RAW.LT = function(J, t, rest)
  -- only finds of note (field 3 quality: 3 blue or better) count as a chapter event (buildChapters)
  local q = tonumber(match(rest, "^[^~]*~[^~]*~([^~]*)"))
  if q and q >= 3 then push(J.evX, t) end
end
RAW.GD = function(J, t, rest)
  local d, src = match(rest, "^(%d+)~[^~]*~([^~]*)")
  d = tonumber(d)
  if d and d > 0 and src ~= "start" and src ~= "gap" then
    J.gT[#J.gT + 1], J.gV[#J.gV + 1] = t, d
  end
end

local function onLine(J, t, code, rest)
  if not J.spanOpen then openSpan(J, t) end
  if t > J.lastT then J.lastT = t end
  if t < J.firstT then J.firstT = t end
  local raw = RAW[code]
  if raw then raw(J, t, rest) return end
  local mf, lf, h = MAP_FIELD[code], LEVEL_FIELD[code], H[code]
  if not (mf or lf or h) then return end
  split(rest)
  if mf then
    local m = nz(F[mf])
    if m and m > 0 then
      local n = #J.sT + 1
      J.sT[n], J.sM[n] = t, m
    end
  end
  if lf and not J.baseLevel then J.baseLevel = nz(F[lf]) end
  if h then h(J, t) end
end

-- Snapshot of the sources: closed blocks up to nLog/nTrail (immutable, only appended), open blocks as a copy. The build
-- reads only the snapshot; whatever arrives during a background build merely makes the result stale.
local function snapshot(char, open)
  local log = type(char.log) == "table" and char.log or {}
  local trail = type(char.trail) == "table" and char.trail or {}
  local s = { log = log, nLog = #log, trail = trail, nTrail = #trail }
  local b = open and open.block
  if type(b) == "table" and type(b.lines) == "table" and tonumber(b.start) then
    local lines = {}
    for i = 1, #b.lines do lines[i] = b.lines[i] end
    s.openLines, s.openStart = lines, tonumber(b.start)
  end
  local t = open and open.trailBlock
  if type(t) == "table" and type(t.lines) == "table" and #t.lines > 0 and tonumber(t.start) and tonumber(t.mapID) then
    local lines = {}
    for i = 1, #t.lines do lines[i] = t.lines[i] end
    s.trailLines, s.trailStart, s.trailMap = lines, tonumber(t.start), tonumber(t.mapID)
  end
  return s
end

-- Log state after the closed blocks (cache): closed blocks never change, so their read result is kept as a copy and only
-- the new part is read on the next build.
local LOG_ARRAYS = { "spT0", "spT1", "tzT", "tzV", "sT", "sM", "lv", "kT", "kN", "kL", "kP", "specials", "spirits", "qt", "shots", "hs",
  "hb", "tf", "tl", "fp", "ib", "mo", "sz", "ex", "tb", "rt", "gs", "gm", "gu", "du", "pk", "bk", "ta", "sp", "gT", "gV",
  "breaks", "evX" }
local LOG_VALUES = { "firstT", "lastT", "spanOpen", "spanStart", "qaN", "baseLevel" }
local logCache = nil

local function copyArray(a)
  local o = {}
  for i = 1, #a do o[i] = a[i] end
  return o
end

local function copyRecord(r)
  local o = {}
  for k, v in pairs(r) do o[k] = v end
  return o
end

local function copyLogState(from, to)
  for _, k in ipairs(LOG_ARRAYS) do
    to[k] = copyArray(from[k])
    pause()
  end
  for _, k in ipairs(LOG_VALUES) do to[k] = from[k] end
  to.deaths = {}
  for i, d in ipairs(from.deaths) do to.deaths[i] = copyRecord(d) end
  to.gaps, to.openInst = {}, nil
  for i, g in ipairs(from.gaps) do
    local c = copyRecord(g)
    to.gaps[i] = c
    if from.openInst == g then to.openInst = c end
  end
  to.zn = copyRecord(from.zn)
  return to
end

local function readBlock(J, block)
  if type(block) ~= "string" then return end
  local h = tonumber(match(block, "^#~(%-?%d+)~"))
  if not h then return end
  for dt, code, rest in gmatch(block, "\n(%-?%d+)~(%u+)~?([^\n]*)") do
    onLine(J, h + tonumber(dt), code, rest)
  end
end

local function readLog(J, snap, db, guid)
  local log, n, k = snap.log, snap.nLog, 0
  local c = logCache
  if c and c.db == db and c.guid == guid and c.n <= n and log[1] == c.first and log[c.n] == c.last then
    copyLogState(c.state, J)
    k = c.n
  end
  for i = k + 1, n do
    readBlock(J, log[i])
    pause()
  end
  if n > k then
    logCache = { db = db, guid = guid, n = n, first = log[1], last = log[n], state = copyLogState(J, {}) }
  end
  local lines, start = snap.openLines, snap.openStart
  if lines then
    for _, line in ipairs(lines) do
      local dt, code, rest = match(line, "^(%-?%d+)~(%u+)~?(.*)$")
      if dt then onLine(J, start + tonumber(dt), code, rest) end
    end
  end
end

-- Trail blocks as number series { start, map, n, t (epoch), x, y (0..9999), mk (marker per index, sparse) }. Closed blocks
-- are decoded once and cached (per block index, checked against the block text).
local trailCache = nil
local NO_MARKS = {}

local function trailPoints(start, map, iter)
  local ts, xs, ys, mk, n = {}, {}, {}, nil, 0
  for dt, x, y, mark in iter do
    if dt then
      n = n + 1
      ts[n], xs[n], ys[n] = start + tonumber(dt), tonumber(x), tonumber(y)
      if mark ~= "" then
        mk = mk or {}
        mk[n] = mark
      end
    end
  end
  return { start = start, map = map, n = n, t = ts, x = xs, y = ys, mk = mk or NO_MARKS }
end

local function decodeTrailText(text)
  local s, m = match(text, "^#~(%-?%d+)~(%d+)")
  if not s then return nil end
  return trailPoints(tonumber(s), tonumber(m), gmatch(text, "\n(%-?%d+)~(%d+)~(%d+)~?(%a?)"))
end

local function lineIter(lines)
  local i = 0
  return function()
    i = i + 1
    local line = lines[i]
    if line == nil then return nil end
    local dt, x, y, mark = match(line, "^(%-?%d+)~(%d+)~(%d+)~?(%a?)")
    if not dt then return false end
    return dt, x, y, mark
  end
end

local function trailBlocks(snap, db, guid)
  local c = trailCache
  if not (c and c.db == db and c.guid == guid) then
    c = { db = db, guid = guid, list = {} }
    trailCache = c
  end
  local out, list, trail = {}, c.list, snap.trail
  for i = 1, snap.nTrail do
    local block = trail[i]
    if type(block) == "string" then
      local e = list[i]
      if not (e and e.src == block) then
        e = { src = block, dec = decodeTrailText(block) or false }
        list[i] = e
        pause()
      end
      if e.dec then out[#out + 1] = e.dec end
    end
  end
  local top = c.top or 0
  for i = snap.nTrail + 1, top do list[i] = nil end
  c.top = snap.nTrail
  if snap.trailLines then out[#out + 1] = trailPoints(snap.trailStart, snap.trailMap, lineIter(snap.trailLines)) end
  return out
end

local function blockEnd(b)
  if b.n > 0 then return b.t[b.n] end
  return b.start
end

local function levelAt(J, t)
  local lv = J.lv
  local lo, hi, best = 1, #lv, nil
  while lo <= hi do
    local mid = floor((lo + hi) / 2)
    if lv[mid].t <= t then best = mid lo = mid + 1 else hi = mid - 1 end
  end
  if best then return lv[best].level end
  if J.baseLevel then return J.baseLevel end
  if lv[1] then return lv[1].level - 1 end
  return 1
end

local function buildStays(J, blocks)
  local tT, tM = {}, {}
  for _, b in ipairs(blocks) do
    tT[#tT + 1], tM[#tM + 1] = b.start, b.map
    tT[#tT + 1], tM[#tM + 1] = blockEnd(b), b.map
  end
  local sT, sM = J.sT, J.sM
  local i, k, n1, n2 = 1, 1, #sT, #tT
  local stays, cur = {}, nil
  while i <= n1 or k <= n2 do
    if (i + k) % 1024 == 0 then pause() end
    local t, m
    if k > n2 or (i <= n1 and sT[i] <= tT[k]) then
      t, m = sT[i], sM[i]
      i = i + 1
    else
      t, m = tT[k], tM[k]
      k = k + 1
    end
    local z = mainZoneOf(J, m)
    if cur and cur.z == z then
      if t > cur.t1 then cur.t1 = t end
    else
      if cur and t > cur.t1 then cur.t1 = t end
      cur = { z = z, t0 = t, t1 = t, map = m }
      stays[#stays + 1] = cur
    end
  end
  if cur and J.lastT > cur.t1 then cur.t1 = J.lastT end
  local li = 1
  for _, s in ipairs(stays) do
    s.levels, s.act = 0, played(J, s.t1) - played(J, s.t0)
    while J.lv[li] and J.lv[li].t < s.t0 do li = li + 1 end
    local lj = li
    while J.lv[lj] and J.lv[lj].t <= s.t1 do
      s.levels = s.levels + 1
      lj = lj + 1
    end
  end
  return stays
end

-- Chapter = zone visit with an event ("Abstecher" rule): a visit is a stay in one main zone (outermost zone of the
-- map, mainZoneOf; sub-maps, caves and embedded zones stay in it; continent/world maps (nonQual, e.g. ship) belong to the
-- running visit). A visit becomes a chapter of its own only if something of note happens in it, regardless of its length (an
-- event late in the visit makes the whole visit, from its entry, the chapter):
--   KI kill (also rare/elite/boss), PK PvP kill, QA quest accepted, QT quest turned in, LV level up, DE death, EX area
--   discovered, FP new flight point, HB new home, SP spell learned, RT reputation tier, IE instance entered, IB boss
--   encounter, MO moment (except "continent", that comes just by arriving), LT find of quality blue or better, VE plan done.
--   Not: ZN/SZ (first arrival), SH (also automatic on a new zone), TF/TL/HS/TB (travel), XP, gold, group and gear lines.
-- A visit without an event is a detour: it stays in the running chapter (time range, so its trail is still drawn and the
-- replay never jumps) and is named in chapter.detours (zone IDs, first occurrence order). A return to the chapter zone simply
-- continues the chapter (A -> B -> C -> A with B, C without event = chapter A with two detours). Visits shorter than
-- Model.STAY_FLICKER played seconds (zone border flicker) never form a chapter, even with an event, and are not named;
-- zones only crossed during a flight (TF/TL) are not named either. Visits before the first chapter visit belong to it (it
-- starts at the start of the journey); a journey without any event is one chapter anchored at the first visit that is not a
-- short lead-in.
local function buildChapters(J, stays)
  local chapters = {}
  local function newChapter(z, t0)
    chapters[#chapters + 1] = { zoneID = z, t0 = t0 }
  end
  if #stays == 0 then
    newChapter(nil, J.firstT)
    return chapters
  end
  -- qualifying stays (without continent maps), consecutive equal zones merged
  -- Stays without duration (several lines in the same second, e.g. sub-map and main zone on entering) are no stay; only if there
  -- is nothing else do they count.
  local anyLong = false
  for _, s in ipairs(stays) do
    if not J.nonQual[s.z] and s.t1 > s.t0 then anyLong = true break end
  end
  local q = {}
  for _, s in ipairs(stays) do
    if not J.nonQual[s.z] and (s.t1 > s.t0 or not anyLong) then
      local last = q[#q]
      if last and last.z == s.z then
        last.act, last.t1 = last.act + s.act, s.t1
      else
        q[#q + 1] = { z = s.z, t0 = s.t0, t1 = s.t1, act = s.act }
      end
    end
  end
  if #q == 0 then
    newChapter(stays[1].z, J.firstT)
    return chapters
  end
  local flicker = Model.STAY_FLICKER
  local n = #q
  -- Events: mark each visit in which something of note happened (time t falls into the visit whose t0 is the last <= t;
  -- before the first visit = first visit). The lists need not be sorted; the cursor only makes sorted input fast.
  local qT0 = {}
  for k = 1, n do qT0[k] = q[k].t0 end
  local qi = 1
  local function mark(t)
    if type(t) ~= "number" then return end
    if not (t >= qT0[qi] and (qi == n or t < qT0[qi + 1])) then
      qi = bsearch(qT0, t)
      if qi == 0 then qi = 1 end
    end
    q[qi].ev = true
  end
  local function markNums(list)
    for k = 1, #list do
      if k % 1024 == 0 then pause() end
      mark(list[k])
    end
  end
  local function markRecs(list, keep)
    for k, r in ipairs(list) do
      if k % 1024 == 0 then pause() end
      if not keep or keep(r) then mark(r.t) end
    end
  end
  markNums(J.kT)                                                  -- KI kill (incl. rare/elite/boss)
  markNums(J.pk)                                                  -- PK PvP kill
  markNums(J.ex)                                                  -- EX area discovered
  markNums(J.sp)                                                  -- SP spell / rank learned (trainer)
  markNums(J.evX)                                                 -- QA quest accepted, LT find blue or better, VE plan done
  markRecs(J.qt)                                                  -- QT quest turned in
  markRecs(J.lv)                                                  -- LV level up
  markRecs(J.deaths)                                              -- DE death
  markRecs(J.fp)                                                  -- FP new flight point
  markRecs(J.hb)                                                  -- HB new home (hearthstone bound)
  markRecs(J.ib)                                                  -- IB boss encounter won
  markRecs(J.rt)                                                  -- RT reputation tier
  markRecs(J.mo, function(m) return m.kind ~= "continent" end)    -- MO moment (not: new continent, comes just by arriving)
  for k, g in ipairs(J.gaps) do                                   -- IE instance entered
    -- the middle of the stay inside (IE comes before the first line on the instance map); still inside: entry time
    if g.kind == "instance" then mark((g.t1 and g.t1 > g.t0) and (g.t0 + (g.t1 - g.t0) / 2) or g.t0) end
    if k % 1024 == 0 then pause() end
  end
  -- Flights (TL: landing time and duration; without duration back to the last TF start): zones only crossed in the air are
  -- transit, not a detour worth naming.
  local fa, fb = {}, {}
  do
    local list, tf, ti = {}, J.tf, 0
    for _, l in ipairs(J.tl) do
      local s = (l.sec and l.sec > 0) and (l.t - l.sec) or nil
      if not s then
        while tf[ti + 1] and tf[ti + 1].t <= l.t do ti = ti + 1 end
        s = tf[ti] and tf[ti].t or nil
      end
      if s and s <= l.t then list[#list + 1] = { s, l.t } end
    end
    tsort(list, function(x, y) return x[1] < y[1] end)
    for k, f in ipairs(list) do fa[k], fb[k] = f[1], f[2] end
  end
  local function inFlight(s)
    local k = bsearch(fa, s.t0 + 2)
    return k > 0 and s.t1 <= fb[k] + 2
  end
  -- Anchor of the first chapter: the first visit with an event, it starts at the beginning of the journey. Without any
  -- event the first visit that is not a short lead-in (Model.STAY_FLICKER) anchors it.
  local first
  for k = 1, n do
    if q[k].ev and q[k].act >= flicker then first = k break end
  end
  if not first then
    first = 1
    local sum = 0
    for k = 1, n - 1 do
      sum = sum + q[k].act
      if sum >= flicker then break end
      if q[k + 1].act >= flicker then first = k + 1 break end
    end
  end
  local cur
  local function open(z, t0)
    newChapter(z, t0)
    cur = chapters[#chapters]
    cur.detours, cur.detourSeen = {}, {}
  end
  local function detour(s)
    if s.z == cur.zoneID or s.act < flicker or inFlight(s) or cur.detourSeen[s.z] then return end
    cur.detourSeen[s.z] = true
    cur.detours[#cur.detours + 1] = s.z
  end
  open(q[first].z, J.firstT)
  for k = 1, first - 1 do detour(q[k]) end
  for k = first + 1, n do
    local s = q[k]
    if s.z ~= cur.zoneID then
      if s.ev and s.act >= flicker then open(s.z, s.t0) else detour(s) end
    end
    if k % 1024 == 0 then pause() end
  end
  for _, c in ipairs(chapters) do c.detourSeen = nil end
  return chapters
end

local function chapterIndex(J, t)
  local i = bsearch(J.chT0, t)
  if i == 0 then return 1 end
  return i
end

local function npcName(J, id, fallback)
  local n = id and J.npcs[id]
  if type(n) == "string" then return plain(n) end
  return plain(fallback)
end

local function clusterMax(list)
  local C = Model.CLUSTER
  local grid = {}
  local function cell(map, cx, cy) return (map * 4096 + cx) * 4096 + cy end
  for _, a in ipairs(list) do
    if a.map and a.x and a.y then
      local k = cell(a.map, floor(a.x / C), floor(a.y / C))
      local l = grid[k]
      if not l then
        l = {}
        grid[k] = l
      end
      l[#l + 1] = a
    end
  end
  local best, bestItem = 0, nil
  for _, a in ipairs(list) do
    if a.map and a.x and a.y then
      local cx, cy, n = floor(a.x / C), floor(a.y / C), 0
      for gx = cx - 1, cx + 1 do
        for gy = cy - 1, cy + 1 do
          local l = grid[cell(a.map, gx, gy)]
          if l then
            for _, b in ipairs(l) do
              if abs(b.x - a.x) <= C and abs(b.y - a.y) <= C then n = n + 1 end
            end
          end
        end
      end
      if n > best then best, bestItem = n, a end
    end
  end
  return best, bestItem
end

local function aggregate(J, chapters)
  for i, c in ipairs(chapters) do
    c.index = i
    c.t1 = chapters[i + 1] and chapters[i + 1].t0 or J.lastT
    c.agg = { kills = 0, npc = {}, deaths = {}, specials = {}, quests = 0, shots = 0, moN = 0, hb = {}, hs = 0, mo = {}, tf = {},
      tlMax = 0, fp = 0, inst = {}, ib = {}, books = {}, gs = 0, gm = {}, gu = {}, du = 0, pk = 0, rt = {}, tb = 0, sz = {},
      ex = 0, talent = false, sp = 0, income = 0, night = 0, dayEv = 0, chains = {}, lv = {}, spirit = 0 }
  end
  local chT0, nCh, ci = J.chT0, #J.chT0, 1
  local function at(t)
    if not (t >= chT0[ci] and (ci == nCh or t < chT0[ci + 1])) then
      ci = bsearch(chT0, t)
      if ci == 0 then ci = 1 end
    end
    return chapters[ci].agg
  end
  local tzT, nTz, ti = J.tzT, #J.tzT, 0
  local function isNight(t)
    if not (ti > 0 and t >= tzT[ti] and (ti == nTz or t < tzT[ti + 1])) then ti = bsearch(tzT, t) end
    local tz = ti > 0 and J.tzV[ti] or J.tz0
    return floor(((t + tz) % 86400) / 3600) < 5
  end
  for k = 1, #J.kT do
    if k % 1024 == 0 then pause() end
    local a, t = at(J.kT[k]), J.kT[k]
    a.kills = a.kills + 1
    local npc = J.kN[k]
    if npc then a.npc[npc] = (a.npc[npc] or 0) + 1 end
    if isNight(t) then a.night = a.night + 1 end
    a.dayEv = a.dayEv + 1
  end
  pause()
  for _, q in ipairs(J.qt) do
    local a = at(q.t)
    a.quests = a.quests + 1
    a.dayEv = a.dayEv + 1
    if isNight(q.t) then a.night = a.night + 1 end
    local rec = q.qid and J.quests[q.qid]
    if type(rec) == "table" and tonumber(rec.questLinePos) and tonumber(rec.questLineLen)
      and tonumber(rec.questLinePos) >= tonumber(rec.questLineLen) and tonumber(rec.questLineLen) > 1 then
      push(a.chains, rec.questLineName)
    end
  end
  for idx, d in ipairs(J.deaths) do
    d.global = idx
    push(at(d.t).deaths, d)
  end
  for _, s in ipairs(J.spirits) do local a = at(s.t) a.spirit = a.spirit + 1 end
  for _, s in ipairs(J.specials) do push(at(s.t).specials, s) end
  for _, s in ipairs(J.shots) do local a = at(s.t) a.shots = a.shots + 1 end
  for _, h in ipairs(J.hb) do push(at(h.t).hb, h) end
  for _, h in ipairs(J.hs) do local a = at(h.t) a.hs = a.hs + 1 end
  -- Moment count = the album's count (model/Momente.lua buildAlbum): every MO line except the starting continent, plus every
  -- zone arrival (ZN of map type 3) except the very first one (the starting zone).
  local skipContinent = true
  for _, m in ipairs(J.mo) do
    local a = at(m.t)
    if m.kind == "continent" and skipContinent then
      skipContinent = false
    else
      a.moN = a.moN + 1
    end
    if not a.mo[m.kind] then a.mo[m.kind] = m end
  end
  local arrivals = {}
  for _, info in pairs(J.zn) do
    if info.type == 3 and info.t then arrivals[#arrivals + 1] = info.t end
  end
  table.sort(arrivals)
  for i = 2, #arrivals do local a = at(arrivals[i]) a.moN = a.moN + 1 end
  for _, f in ipairs(J.tf) do push(at(f.t).tf, f) end
  for _, l in ipairs(J.tl) do
    local a = at(l.t)
    if l.sec and l.sec > a.tlMax then a.tlMax = l.sec end
  end
  for _, f in ipairs(J.fp) do local a = at(f.t) a.fp = a.fp + 1 end
  for _, g in ipairs(J.gaps) do if g.kind == "instance" and g.inst then push(at(g.t0).inst, g) end end
  for _, b in ipairs(J.ib) do push(at(b.t).ib, b) end
  for _, b in ipairs(J.bk) do push(at(b.t).books, b) end
  for _, t in ipairs(J.gs) do local a = at(t) a.gs = a.gs + 1 end
  for _, g in ipairs(J.gm) do
    local a = at(g.t)
    if g.name and g.name ~= "" and g.name ~= "?" then a.gm[g.name] = (a.gm[g.name] or 0) + 1 end
  end
  for _, g in ipairs(J.gu) do push(at(g.t).gu, g) end
  for _, t in ipairs(J.du) do local a = at(t) a.du = a.du + 1 end
  for _, t in ipairs(J.pk) do local a = at(t) a.pk = a.pk + 1 end
  for _, r in ipairs(J.rt) do
    if r.standing and (not r.prev or r.standing > r.prev) then push(at(r.t).rt, r) end
  end
  for _, t in ipairs(J.tb) do local a = at(t) a.tb = a.tb + 1 end
  for _, s in ipairs(J.sz) do push(at(s.t).sz, s) end
  for _, t in ipairs(J.ex) do local a = at(t) a.ex = a.ex + 1 end
  for _, t in ipairs(J.ta) do at(t).talent = true end
  for _, t in ipairs(J.sp) do local a = at(t) a.sp = a.sp + 1 end
  pause()
  for k = 1, #J.gT do
    if k % 1024 == 0 then pause() end
    local a = at(J.gT[k])
    a.income = a.income + J.gV[k]
  end
  for _, l in ipairs(J.lv) do push(at(l.t).lv, l) end
  pause()

  local bestIncome, bestIdx = 0, nil
  for i, c in ipairs(chapters) do
    pause()
    local a = c.agg
    c.levelFrom = (i == 1) and levelAt(J, J.firstT) or levelAt(J, c.t0)
    c.levelTo = levelAt(J, c.t1)
    if c.levelTo < c.levelFrom then c.levelTo = c.levelFrom end
    c.p0, c.p1 = played(J, c.t0), played(J, c.t1)
    c.played = c.p1 - c.p0
    c.zoneName = c.zoneID and (mapName(J, c.zoneID) or plain(MT("mapN", int(c.zoneID)))) or nil
    c.continentID = c.zoneID and continentOf(J, c.zoneID) or nil
    a.sameSpot = clusterMax(a.deaths)
    if a.income > bestIncome then bestIncome, bestIdx = a.income, i end
    for _, s in ipairs(a.specials) do
      local key = (s.tag == "boss") and "boss" or ((s.tag == "rare") and "rare" or "elite")
      local cur = a[key]
      local lv = s.level == -1 and 999 or (s.level or 0)
      local clv = cur and (cur.level == -1 and 999 or (cur.level or 0)) or -1
      if (npcName(J, s.npc, s.name)) and lv > clv then a[key] = s end
      if key == "elite" then a.elites = (a.elites or 0) + 1 end
    end
    local topN, topC = nil, 0
    for npc, n in pairs(a.npc) do
      if n > topC or (n == topC and npc < topN) then topN, topC = npc, n end
    end
    a.topNpc, a.topCount = topN, topC
    local topM, topMC = nil, 0
    for name, n in pairs(a.gm) do
      if n > topMC or (n == topMC and name < topM) then topM, topMC = name, n end
    end
    a.topMate, a.topMateCount = topM, topMC
  end
  J.maxIncomeChapter = bestIdx
end

local function civil(days)
  local z = days + 719468
  local era = floor(z / 146097)
  local doe = z - era * 146097
  local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
  local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
  local mp = floor((5 * doy + 2) / 153)
  local d = doy - floor((153 * mp + 2) / 5) + 1
  local m = mp < 10 and mp + 3 or mp - 9
  local y = yoe + era * 400 + (m <= 2 and 1 or 0)
  return y, m, d
end

local function stamp(J, t)
  if not (type(t) == "number" and t == t and t > -1e12 and t < 1e12) then return "" end
  local lt = t + tzAt(J, t)
  local _, m, d = civil(floor(lt / 86400))
  local s = lt % 86400
  return MT("stampFmt", { d = format("%02d", d), m = format("%02d", m), h = format("%02d", floor(s / 3600)), mi = format("%02d", floor(s % 3600 / 60)) })
end
Model._stamp = function(t, tz) return stamp({ tzT = {}, tzV = {}, tz0 = tz or 0 }, t) end

local function labelChapters(J, chapters)
  for _, c in ipairs(chapters) do
    c.startText = stamp(J, c.t0)
    c.label = MT("lvShort", int(c.levelFrom)) .. (c.startText ~= "" and (" · " .. c.startText) or "")
    c.title = (disp(c.zoneName, Model.NAME_MAX) or MT.underway) .. " · " .. c.label
    c.titleKind = "stay"
  end
end

local function story(J, c, nextC)
  local a, ph = c.agg, {}
  local function add(score, text) if text then ph[#ph + 1] = { score = score, text = text, n = #ph } end end
  local d = a.deaths[1]
  if d then
    local where = d.map and mapName(J, d.map)
    if d.global == 1 then add(100, (where and single(where)) and MT("firstDeathIn", where) or MT.firstDeath)
    elseif #a.deaths >= 2 then add(40, MT("deathsN", numword(#a.deaths)))
    end
  end
  if a.boss then local n = npcName(J, a.boss.npc, a.boss.name) add(95, n and MT("bossDown", n)) end
  if a.rare then local n = npcName(J, a.rare.npc, a.rare.name) add(80, n and MT("rareDown", n)) end
  local ms = Journal.MapSpace
  local top = ms and ms.maxLevel and ms.maxLevel() or 60 -- highest level of the client (Forever 60, Retail 80/90)
  for _, l in ipairs(a.lv) do
    if l.level == top then add(98, MT("level60", int(top))) elseif l.level % 10 == 0 then add(60 + l.level / 10, MT("levelReached", int(l.level))) end
  end
  local h = a.hb[#a.hb]
  if h then local b = plain(h.bind) add(65, b and MT("newHomeAt", b) or MT.newHome) end
  if a.mo.first_blue then add(70, MT.firstBlue) end
  if a.mo.first_epic then add(75, MT.firstEpic) end
  if a.mo.mount then add(78, MT.firstMount) end
  if a.mo.continent then add(55, MT.newShores) end
  local g = a.inst[1]
  if g then
    local s = J.snap.instances and J.snap.instances[g.inst]
    local n = type(s) == "table" and plain(s.name) or nil
    add(58, n and MT("visited", n) or MT.descent)
  end
  local f = a.tf[#a.tf]
  if f then
    local to = plain(f.to)
    to = to and (match(to, "^([^,]+)") or to)
    add(35, to and (single(to) and MT("flightTo", to) or MT("flightColon", to)) or nil)
  end
  if a.quests >= 10 then add(30, MT("questsDone", int(a.quests))) end
  tsort(ph, function(x, y)
    if x.score ~= y.score then return x.score > y.score end
    return x.n < y.n
  end)
  local parts = {}
  local maxParts = nextC and 2 or 3
  for k = 1, math.min(maxParts, #ph) do parts[#parts + 1] = ph[k].text end
  local s
  if #parts == 0 then
    if c.index == 1 and not nextC then
      s = MT.storyStart
    elseif (c.played or 0) < Model.TRANSIT_PLAY then
      s = MT.storyTransit
    else
      s = MT.storyQuiet
    end
  else
    s = table.concat(parts, ", ")
  end
  if nextC and nextC.zoneName and nextC.zoneID ~= c.zoneID then s = s .. MT("thenToward", nextC.zoneName) end
  return disp(capital(s) .. ".", Model.TEXT_MAX)
end

local function decodeTrail(J, blocks)
  local runs, flights = {}, {}
  local breaks, gaps = J.breaks, J.gaps
  tsort(breaks)
  tsort(gaps, function(x, y) return x.t0 < y.t0 end)
  local bi, gi = 1, 1
  local nextBreak = breaks[1] or huge
  local nextGap = gaps[1] and gaps[1].t0 or huge
  local run, xs, ys, ts, rn = nil, nil, nil, nil, 0
  local pT, pX, pY, pMap, pMark = nil, nil, nil, nil, nil
  local yards, approx = 0, false
  local BG, BD2, LG, YPS = Model.BREAK_GAP, Model.BREAK_DIST * Model.BREAK_DIST, Model.LINK_GAP, Model.YARDS_PER_STEP
  local TOL2, TDT = Model.THIN_TOL * Model.THIN_TOL, Model.THIN_DT
  local chT0, chI = J.chT0, 1
  local chLo, chHi = chT0[1] or -huge, chT0[2] or huge
  local sw, sh
  local function newRun(map, chap, t0)
    xs, ys, ts, rn = {}, {}, {}, 0
    run = { mapID = map, zone = zoneOf(J, map), continent = continentOf(J, map), chapter = chap, xs = xs, ys = ys, ts = ts,
      n = 0, raw = 0, t0 = t0 }
    runs[#runs + 1] = run
    local s = mapSize(J, map)
    if s then sw, sh = s[1], s[2] else sw, sh = nil, nil end
  end
  for _, b in ipairs(blocks) do
    local map, bt, bx, by, bmk = b.map, b.t, b.x, b.y, b.mk
    for i = 1, b.n do
      local t, x, y, mark = bt[i], bx[i], by[i], bmk[i]
      if nextGap < t then
        while gaps[gi] and gaps[gi].t0 < t do
          local g = gaps[gi]
          if pT then g.map, g.x, g.y = g.map or pMap, pX, pY end
          if not g.t1 then g.t1 = t end
          gi = gi + 1
        end
        nextGap = gaps[gi] and gaps[gi].t0 or huge
      end
      local brk = (run == nil) or (map ~= pMap) or (mark ~= nil and mark == "z") or (pMark ~= nil and (pMark == "d" or pMark == "f"))
      if nextBreak <= t then
        while breaks[bi] and breaks[bi] <= t do
          if pT and breaks[bi] > pT then brk = true end
          bi = bi + 1
        end
        nextBreak = breaks[bi] or huge
      end
      if not brk and t - pT > BG then
        local dx, dy = x - pX, y - pY
        if dx * dx + dy * dy > BD2 then brk = true end
      end
      if t < chLo or t >= chHi then
        chI = bsearch(chT0, t)
        if chI == 0 then chI = 1 end
        chLo, chHi = chT0[chI] or -huge, chT0[chI + 1] or huge
        if chI == 1 then chLo = -huge end
      end
      if pMark == "f" and mark == "l" then
        flights[#flights + 1] = { from = { mapID = pMap, x = pX / 10000, y = pY / 10000 },
          to = { mapID = map, x = x / 10000, y = y / 10000 }, t0 = pT, t1 = t, p0 = played(J, pT), p1 = played(J, t),
          chapter = chapterIndex(J, pT) }
      end
      if brk then
        local link
        -- Any map change within LINK_GAP continues the walk (also a tick that saw the new map before the zone event: no "z" mark).
        if pT and map ~= pMap and t - pT <= LG and pMark ~= "d" and pMark ~= "f" then
          local k = bsearch(breaks, t)
          if not (k > 0 and breaks[k] > pT) then link = { mapID = pMap, x = pX, y = pY, t = pT } end
        end
        newRun(map, chI, t)
        run.link = link
      else
        if chI ~= run.chapter then
          newRun(map, chI, pT)
          rn = 1
          xs[1], ys[1], ts[1] = pX, pY, pT
        end
        if sw then
          local dx, dy = (x - pX) / 10000 * sw, (y - pY) / 10000 * sh
          yards = yards + sqrt(dx * dx + dy * dy)
        else
          approx = true
          if x ~= pX or y ~= pY then yards = yards + YPS end
        end
      end
      -- Thinning: the last stored point B is dropped if it lies almost on the line between its predecessor A and the new point C
      -- (or is a duplicate during a standstill). The start of a run always stays; points are merged only within THIN_DT seconds.
      local drop = false
      if rn >= 2 and t - ts[rn - 1] <= TDT then
        local ax, ay, bx2, by2 = xs[rn - 1], ys[rn - 1], xs[rn], ys[rn]
        if bx2 == x and by2 == y then
          drop = (ax == x and ay == y)
        elseif not (bx2 == ax and by2 == ay) then
          local cx, cy, ex, ey = x - ax, y - ay, bx2 - ax, by2 - ay
          local len2 = cx * cx + cy * cy
          local cross = ex * cy - ey * cx
          local dot = ex * cx + ey * cy
          drop = len2 > 0 and cross * cross <= TOL2 * len2 and dot > 0 and dot < len2
        end
      end
      if not drop then rn = rn + 1 end
      xs[rn], ys[rn], ts[rn] = x, y, t
      run.n, run.raw = rn, run.raw + 1
      pT, pX, pY, pMap, pMark = t, x, y, map, mark
    end
    pause()
  end
  while gaps[gi] do
    local g = gaps[gi]
    if pT then g.map, g.x, g.y = g.map or pMap, pX, pY end
    gi = gi + 1
  end
  local contPoints = {}
  for _, r in ipairs(runs) do
    pause()
    local rx, ry = r.xs, r.ys
    local minX, maxX, minY, maxY, lx, ly = rx[1], rx[1], ry[1], ry[1], 0, 0
    for i = 2, r.n do
      local x, y = rx[i], ry[i]
      if x < minX then minX = x elseif x > maxX then maxX = x end
      if y < minY then minY = y elseif y > maxY then maxY = y end
      lx, ly = lx + abs(x - rx[i - 1]), ly + abs(y - ry[i - 1])
    end
    r.minX, r.maxX, r.minY, r.maxY, r.lx, r.ly = minX, maxX, minY, maxY, lx, ly
    local c = r.continent
    if c then contPoints[c] = (contPoints[c] or 0) + r.raw end
  end
  J.runs, J.flights, J.yards, J.kmApprox = runs, flights, yards, approx
  J.lastPoint = pT and { t = pT, x = pX, y = pY, map = pMap, mark = pMark } or nil
  local conts = {}
  for id, n in pairs(contPoints) do conts[#conts + 1] = { id = id, points = n } end
  tsort(conts, function(x, y)
    if x.points ~= y.points then return x.points > y.points end
    return x.id < y.id
  end)
  J.continents = conts
end

local function tip(J, title, t, map, level, detail)
  return {
    title = disp(title, Model.NAME_MAX + 20),
    when = when(J, t),
    place = disp(mapName(J, map) or (map and MT("mapN", int(map))) or MT.unknownPlace, Model.NAME_MAX + 20),
    level = level and MT("levelN", int(level)) or nil,
    detail = detail and disp(detail, Model.TEXT_MAX) or nil,
  }
end

local function marker(J, kind, t, map, x, y, level, title, detail, big)
  if not (map and x and y) then return nil end
  return {
    kind = kind, big = big or false, mapID = map, x = x / 10000, y = y / 10000, t = t, p = played(J, t),
    chapter = chapterIndex(J, t), level = level, count = 1, zone = zoneOf(J, map), continent = continentOf(J, map),
    tip = tip(J, title, t, map, level, detail),
  }
end

local function buildMarkers(J)
  local out = {}
  local function put(m)
    if m then
      out[#out + 1] = m
      if #out % 64 == 0 then pause() end
    end
  end
  for _, l in ipairs(J.lv) do
    if l.level % 5 == 0 then
      local big = l.level % 10 == 0
      put(marker(J, big and "milestone" or "level", l.t, l.map, l.x, l.y, l.level, MT("levelN", int(l.level)),
        MT("afterPlayed", Model.formatPlayed(played(J, l.t))), big))
    end
  end
  for _, d in ipairs(J.deaths) do
    local cause
    if d.cause == "enemy" or (d.cause == nil or d.cause == "") and (d.npc or (d.source and d.source ~= "")) then
      cause = npcName(J, d.npc, d.source)
    end
    cause = cause or (CAUSES[d.cause] and MT["cause_" .. d.cause]) or MT.unknown
    local detail = MT("causeLine", cause) .. (HOW[d.how] and (" · " .. MT["how_" .. d.how]) or "")
    put(marker(J, "death", d.t, d.map, d.x, d.y, d.level, d.global == 1 and MT.firstDeathTitle or MT.deathTitle, detail))
  end
  local lastBy = {}
  for _, s in ipairs(J.specials) do
    if s.map and s.x and s.y then
      local key = (s.npc or s.name or "?") .. ":" .. int(s.map)
      local m = lastBy[key]
      if m and s.t - m.t <= 1800 and abs(s.x / 10000 - m.x) * 10000 <= Model.CLUSTER and abs(s.y / 10000 - m.y) * 10000 <= Model.CLUSTER then
        m.count = m.count + 1
        m.tip.detail = disp((m.baseDetail or "") .. " · " .. MT("timesSuffix", int(m.count)), Model.TEXT_MAX)
      else
        local n = npcName(J, s.npc, s.name) or MT.unknown
        local lvl = s.level == -1 and "??" or (s.level and int(s.level)) or nil
        local detail = (lvl and MT("levelPrefix", lvl) or "") .. (s.tag == "boss" and MT.bossTag or (s.tag == "rare" and MT.rareTag or MT.eliteTag))
        m = marker(J, s.tag, s.t, s.map, s.x, s.y, s.plevel, (CLS_TEXT[s.tag] and MT["cls_" .. s.tag] or "?") .. ": " .. n, detail)
        if m then
          m.baseDetail = detail
          put(m)
          lastBy[key] = m
        end
      end
    end
  end
  for _, s in ipairs(J.shots) do
    local reasons, manual = {}, false
    for r in gmatch(s.reasons or "", "[^,]+") do
      reasons[#reasons + 1] = SHOT_REASONS[r] and MT["shot_" .. r] or MT.memory
      if r == "manual" then manual = true end
    end
    if manual then
      local detail = (#reasons > 0 and table.concat(reasons, ", ") or MT.memory)
      if s.key and match(s.key, "^%d+_%d+$") then detail = detail .. " · WoWScrnShot_" .. s.key .. ".jpg" end
      put(marker(J, "photo", s.t, s.map, s.x, s.y, s.level or levelAt(J, s.t), MT.memory, detail))
    end
  end
  for _, h in ipairs(J.hs) do
    local b = plain(h.bind)
    put(marker(J, "hearth", h.t, h.map, h.x, h.y, levelAt(J, h.t), MT.hearthTitle, b and MT("hearthTo", b) or MT.hearthOwn))
  end
  for _, f in ipairs(J.fp) do
    local n = npcName(J, f.npc, f.name)
    put(marker(J, "flightpoint", f.t, f.map, f.x, f.y, levelAt(J, f.t), MT.flightPoint, n and MT("flightMaster", n) or nil))
  end
  tsort(out, function(a, b)
    if a.t ~= b.t then return a.t < b.t end
    if a.kind ~= b.kind then return a.kind < b.kind end
    return a.x < b.x
  end)
  for _, m in ipairs(out) do m.baseDetail = nil end
  return out
end

local function finishGaps(J)
  local out = {}
  for _, g in ipairs(J.gaps) do
    local t1 = g.t1 or J.lastT
    local name
    if g.inst then
      local s = J.snap.instances and J.snap.instances[g.inst]
      name = type(s) == "table" and plain(s.name) or nil
    end
    local detail
    if g.kind == "instance" then
      local bits = {}
      if g.kills then bits[#bits + 1] = MT("kills", int(g.kills)) end
      if g.ideaths and g.ideaths > 0 then bits[#bits + 1] = MT(ns.Locale.plural(g.ideaths, "death_one", "death_other"), int(g.ideaths)) end
      if g.bosses and g.bosses > 0 then bits[#bits + 1] = MT(ns.Locale.plural(g.bosses, "boss_one", "boss_other"), int(g.bosses)) end
      detail = MT.gapInstance .. (#bits > 0 and (" · " .. table.concat(bits, ", ")) or "")
    else
      detail = MT.gapLocked
    end
    local title = g.kind == "instance" and (name and MT("instanceNamed", name) or MT.instanceTitle) or MT.trailBroken
    out[#out + 1] = {
      kind = g.kind, t0 = g.t0, t1 = t1, p0 = played(J, g.t0), p1 = played(J, t1), chapter = chapterIndex(J, g.t0),
      mapID = g.map, x = g.x and g.x / 10000 or nil, y = g.y and g.y / 10000 or nil,
      zone = zoneOf(J, g.map), continent = continentOf(J, g.map),
      tip = tip(J, title, g.t0, g.map, levelAt(J, g.t0), detail),
    }
  end
  return out
end

local function finishFlights(J)
  for _, f in ipairs(J.flights) do
    local tf
    for k = #J.tf, 1, -1 do
      local c = J.tf[k]
      if c.t <= f.t1 and c.t >= f.t0 - 60 then tf = c break end
      if c.t < f.t0 - 60 then break end
    end
    local sec = f.t1 - f.t0
    local detail = MT("duration", ns.Journal.Fmt.duration(sec, { seconds = true }) or "?")
    local title = MT.flight
    if tf then
      local from, to = plain(tf.from), plain(tf.to)
      if from and to then title = MT("flightFromTo", from, to) end
    end
    f.zoneFrom, f.zoneTo = zoneOf(J, f.from.mapID), zoneOf(J, f.to.mapID)
    f.contFrom, f.contTo = continentOf(J, f.from.mapID), continentOf(J, f.to.mapID)
    f.seconds = sec
    f.tip = tip(J, title, f.t0, f.from.mapID, levelAt(J, f.t0), detail)
  end
end

local function noteCandidates(J, deaths, specials, flights, lvs, chapterLocal)
  local out = {}
  local d1 = deaths[1]
  if d1 and d1.map and d1.x then
    local label = (d1.global == 1) and MT.noteFirstDeath or MT.noteDeath
    out[#out + 1] = { kind = "first_death", score = 100, mapID = d1.map, x = d1.x / 10000, y = d1.y / 10000, t = d1.t,
      text = disp(when(J, d1.t) .. " · " .. label, Model.TEXT_MAX) }
  end
  local n, item = clusterMax(deaths)
  if n >= 2 and item then
    local spirits = 0
    for _, s in ipairs(J.spirits) do
      if s.map == item.map and s.x and abs(s.x - item.x) <= Model.CLUSTER * 3 and abs(s.y - item.y) <= Model.CLUSTER * 3 then spirits = spirits + 1 end
    end
    local text = (spirits >= 2) and MT("spiritTimes", times(spirits)) or MT("diedTimes", times(n))
    out[#out + 1] = { kind = "death_spot", score = 80 + n, mapID = item.map, x = item.x / 10000, y = item.y / 10000, t = item.t,
      text = disp(text, Model.TEXT_MAX) }
  end
  local best, bestLv
  for _, s in ipairs(specials) do
    local lv = s.level == -1 and 999 or (s.level or 0)
    if s.map and s.x and npcName(J, s.npc, s.name) and (not bestLv or lv > bestLv) then best, bestLv = s, lv end
  end
  if best then
    local nm = npcName(J, best.npc, best.name)
    local lv = best.level == -1 and MT.levelUnknownParen or (best.level and MT("levelParen", int(best.level)) or "")
    out[#out + 1] = { kind = "record_kill", score = 70, mapID = best.map, x = best.x / 10000, y = best.y / 10000, t = best.t,
      text = disp(MT("toughest", nm, lv), Model.TEXT_MAX) }
  end
  local lf
  for _, f in ipairs(flights) do if not lf or f.seconds > lf.seconds then lf = f end end
  if lf and lf.seconds >= 30 then
    out[#out + 1] = { kind = "longest_flight", score = 60, mapID = lf.to.mapID, x = lf.to.x, y = lf.to.y, t = lf.t1,
      text = disp(MT(chapterLocal and "noteFlight" or "noteLongestFlight", ns.Journal.Fmt.duration(lf.seconds, { seconds = true }) or "?"), Model.TEXT_MAX) }
  end
  local top
  for _, l in ipairs(lvs) do if l.level % 10 == 0 and l.map and l.x and (not top or l.level > top.level) then top = l end end
  if top then
    out[#out + 1] = { kind = "milestone", score = 40 + top.level / 10, mapID = top.map, x = top.x / 10000, y = top.y / 10000,
      t = top.t, text = disp(MT("noteMilestone", when(J, top.t), int(top.level)), Model.TEXT_MAX) }
  end
  return out
end

-- Find standstill: if the gap between consecutive trail points exceeds Model.IDLE_GAP played seconds the figure stands still
-- (points only appear after 22 yards); events in between do NOT split the gap. On the axis it lasts Model.IDLE_KEEP s, a flight
-- Model.IDLE_FLIGHT_KEEP s. -> { a, b (played-second interval), q (axis start), k (axis length), keep (default length) }
local function buildIdle(J)
  local A, B, K = {}, {}, {}
  local G, KEEP, FKEEP = Model.IDLE_GAP, Model.IDLE_KEEP, Model.IDLE_FLIGHT_KEEP
  local flightAt = {}
  for _, f in ipairs(J.flights or {}) do
    if type(f.p0) == "number" and f.p0 == f.p0 then flightAt[floor(f.p0 + 0.5)] = true end
  end
  local prev
  for ri, r in ipairs(J.runs) do
    if ri % 64 == 0 then pause() end
    local ts = r.ts
    for i = 1, r.n do
      local t = ts[i]
      if prev and t > prev and t - prev > G then
        local pa, pb = played(J, prev), played(J, t)
        if pb - pa > G then
          local n = #A
          if n == 0 or pa >= B[n] then
            A[n + 1], B[n + 1] = pa, pb
            K[n + 1] = flightAt[floor(pa + 0.5)] and FKEEP or KEEP
          end
        end
      end
      if not prev or t > prev then prev = t end
    end
  end
  local Q, removed = {}, 0
  for i = 1, #A do
    Q[i] = A[i] - removed
    removed = removed + (B[i] - A[i]) - K[i]
  end
  return { a = A, b = B, q = Q, k = K, keep = KEEP }
end

local function buildTotal(J, model, level)
  local chs = model.chapters
  local kills, deaths, quests, shots, moments = 0, 0, 0, 0, 0
  for _, c in ipairs(chs) do
    kills, deaths, quests, shots = kills + (c.stats.kills or 0), deaths + (c.stats.deaths or 0),
      quests + (c.stats.quests or 0), shots + (c.stats.shots or 0)
    moments = moments + (c.stats.moments or 0)
  end
  local from = chs[1] and chs[1].levelFrom or level or 1
  local to = math.max(level or from, from)
  local label = MT("lvShort", int(from) .. ((to ~= from) and ("–" .. int(to)) or ""))
  local a, b = stamp(J, J.firstT), stamp(J, J.lastT)
  local sub = label .. ((a ~= "" and b ~= "") and MT("range", a, b) or "")
  local h = model.header
  local km = ns.Journal.Fmt.km(h.km)
  local n = #chs
  local story = MT(ns.Locale.plural(n, "stays_one", "stays_other"), int(n)) .. ", " .. (h.kmApprox and MT.approx or "")
    .. MT("onFoot", km)
  if h.flights > 0 then story = story .. ", " .. MT(ns.Locale.plural(h.flights, "flights_one", "flights_other"), int(h.flights)) end
  return {
    index = 0, total = true, title = MT.totalTitle, zoneName = MT.totalTitle, label = label, subtitle = sub,
    story = disp(story .. ".", Model.TEXT_MAX), startText = a, endText = b, levelFrom = from, levelTo = to,
    t0 = J.firstT, t1 = J.lastT, p0 = 0, p1 = J.playedTotal, stays = n,
    stats = { played = J.playedTotal, playedText = Model.formatPlayed(J.playedTotal), quests = quests, kills = kills,
      deaths = deaths, shots = shots, moments = moments },
  }
end

local function newJ(db, char, geo)
  local snap = type(char.snapshots) == "table" and char.snapshots or {}
  local info = type(char.info) == "table" and char.info or {}
  return {
    snap = snap, info = info, npcs = type(char.npcs) == "table" and char.npcs or {},
    quests = type(char.quests) == "table" and char.quests or {}, books = type(char.books) == "table" and char.books or {},
    geo = geo, faction = info.faction,
    firstT = huge, lastT = -huge, spT0 = {}, spT1 = {}, spCum = {}, spanOpen = false, tzT = {}, tzV = {},
    tz0 = (type(db.meta) == "table" and tonumber(db.meta.tzOffset)) or 0,
    sT = {}, sM = {}, zn = {}, zoneKey = {}, mainKey = {}, startKey = {}, contOf = {}, sizeOf = {}, nonQual = {},
    lv = {}, kT = {}, kN = {}, kL = {}, kP = {}, specials = {}, deaths = {}, spirits = {}, qt = {}, qaN = 0, shots = {}, hs = {}, hb = {},
    tf = {}, tl = {}, fp = {}, gaps = {}, ib = {}, mo = {}, sz = {}, ex = {}, tb = {}, rt = {}, gs = {}, gm = {}, gu = {},
    du = {}, pk = {}, bk = {}, ta = {}, sp = {}, gT = {}, gV = {}, breaks = {}, evX = {},
  }
end

local function build(db, guid, char, snap, opts)
  local J = newJ(db, char, opts.geo or Journal.Geo)
  local tm, c0 = {}, clock()
  readLog(J, snap, db, guid)
  local cL = clock()
  tm.log = cL - c0
  pause()
  local cT = clock()
  local blocks = trailBlocks(snap, db, guid)
  local trailParse = clock() - cT
  for _, b in ipairs(blocks) do
    if b.start < J.firstT then J.firstT = b.start end
    local e = blockEnd(b)
    if e > J.lastT then J.lastT = e end
  end
  local now = tonumber(opts.now) or time()
  if J.firstT == huge then J.firstT, J.lastT = tonumber(J.info.firstSeen) or now, tonumber(J.info.firstSeen) or now end
  if J.lastT < J.firstT then J.lastT = J.firstT end
  J.startT = math.min(tonumber(J.info.firstSeen) or J.firstT, J.firstT)
  finishSpans(J)
  tsort(J.lv, function(a, b) return a.t < b.t end)

  local c1 = clock()
  local st = {}
  tm.stages = st
  local cs = c1
  local function stage(key)
    local c = clock()
    st[key] = (st[key] or 0) + (c - cs)
    pause()
    cs = clock()
  end
  local stays = buildStays(J, blocks)
  stage("stays")
  local chapters = buildChapters(J, stays)
  J.chapters, J.chT0 = chapters, {}
  for i, c in ipairs(chapters) do J.chT0[i] = c.t0 end
  stage("cut")
  aggregate(J, chapters)
  labelChapters(J, chapters)
  stage("aggregate")
  local c2 = clock()
  tm.chapters = c2 - c1
  pause()
  c2 = clock()
  cs = c2
  decodeTrail(J, blocks)
  stage("decode")
  finishFlights(J)
  stage("flights")
  local c3 = clock()
  tm.trail = trailParse + (c3 - c2)
  pause()
  c3 = clock()
  cs = c3

  local model = { _J = J, _routes = {}, _notes = {}, _kills = {}, _killsN = 0 }
  model.chapters = {}
  for i, c in ipairs(chapters) do
    -- Detours (buildChapters): { zoneID, name } in order, plus the card line "Abstecher: X, Y"
    local detours, names = {}, {}
    for _, z in ipairs(c.detours or {}) do
      local nm = disp(mapName(J, z) or plain(MT("mapN", int(z))), Model.NAME_MAX)
      if nm then
        detours[#detours + 1] = { zoneID = z, name = nm }
        names[#names + 1] = nm
      end
    end
    local detourText = nil
    if #names > 0 then
      detourText = disp(MT(ns.Locale.plural(#names, "detours_one", "detours_other"), table.concat(names, ", ")), Model.TEXT_MAX)
    end
    model.chapters[i] = {
      detours = detours, detourText = detourText,
      index = i, roman = roman(i), title = c.title, titleKind = c.titleKind, label = c.label, startText = c.startText,
      subtitle = c.label, zoneID = c.zoneID, zoneName = c.zoneName and disp(c.zoneName) or nil,
      continentID = c.continentID, levelFrom = c.levelFrom, levelTo = c.levelTo, t0 = c.t0, t1 = c.t1, p0 = c.p0, p1 = c.p1,
      stats = { played = c.played, playedText = Model.formatPlayed(c.played), quests = c.agg.quests, kills = c.agg.kills,
        deaths = #c.agg.deaths, shots = c.agg.shots, moments = c.agg.moN },
      story = story(J, c, chapters[i + 1]),
    }
  end
  stage("story")
  model.markers = buildMarkers(J)
  stage("markers")
  model.gaps = finishGaps(J)
  stage("gaps")
  model.flights = J.flights
  model.runs = J.runs
  model.continents = J.continents
  local levels = {}
  for _, l in ipairs(J.lv) do levels[#levels + 1] = { p = played(J, l.t), level = l.level, t = l.t } end
  local chs = {}
  for i, c in ipairs(model.chapters) do chs[i] = { p0 = c.p0, p1 = c.p1 } end
  model.timeline = { total = J.playedTotal, t0 = J.firstT, t1 = J.lastT, levels = levels, chapters = chs,
    idle = buildIdle(J) }
  local lp = J.lastPoint
  model.current = lp and { mapID = lp.map, x = lp.x / 10000, y = lp.y / 10000, t = lp.t } or nil
  model.empty = (#J.runs == 0 and #J.kT == 0 and #J.qt == 0 and #J.lv == 0 and #J.deaths == 0)

  local info = J.info
  local level = levelAt(J, J.lastT)
  local name, race, class = disp(info.name, Model.NAME_MAX), disp(info.race, Model.NAME_MAX), disp(info.class, Model.NAME_MAX)
  local line = {}
  if name then line[#line + 1] = name end
  if race or class then line[#line + 1] = (race or "") .. ((race and class) and " " or "") .. (class or "") end
  line[#line + 1] = MT("levelN", int(level))
  local km = J.yards * 0.9144 / 1000
  model.header = {
    name = name, race = race, class = class, level = level, line = table.concat(line, " · "),
    km = floor(km * 10 + 0.5) / 10, kmApprox = J.kmApprox, flights = #J.tf, hearths = #J.hs, deaths = #J.deaths,
    played = J.playedTotal, playedText = Model.formatPlayed(J.playedTotal),
  }
  Model.refreshHeader(model, now)
  model.total = buildTotal(J, model, level)
  tm.rest = clock() - c3
  tm.total = clock() - c0
  model.timings = tm
  return model
end

function Model.refreshHeader(model, now)
  local J, h = model._J, model.header
  h.day = math.max(1, floor((now + tzAt(J, now)) / 86400) - floor((J.startT + tzAt(J, J.startT)) / 86400) + 1)
  local km = ns.Journal.Fmt.km(h.km)
  h.stats = MT("statsDay", int(h.day)) .. " · " .. (h.kmApprox and MT.approx or "") .. MT("onFoot", km) .. " · "
    .. MT(ns.Locale.plural(h.flights, "statsFlights_one", "statsFlights_other"), int(h.flights)) .. " · "
    .. MT(ns.Locale.plural(h.hearths, "statsHearths_one", "statsHearths_other"), int(h.hearths))
end

local cache = nil
local job = nil
local readyFns = {}
local prepScheduled = false
Model.readyErrors = 0

local function signature(guid, char, open)
  local log, trail = type(char.log) == "table" and char.log or {}, type(char.trail) == "table" and char.trail or {}
  local ll = type(log[#log]) == "string" and #log[#log] or 0
  local tl = type(trail[#trail]) == "string" and #trail[#trail] or 0
  local ob = open and type(open.block) == "table" and type(open.block.lines) == "table" and #open.block.lines or 0
  local ot = open and type(open.trailBlock) == "table" and type(open.trailBlock.lines) == "table" and #open.trailBlock.lines or 0
  local openStart = open and type(open.block) == "table" and tonumber(open.block.start) or 0
  local trailStart = open and type(open.trailBlock) == "table" and tonumber(open.trailBlock.start) or 0
  return table.concat({ guid, #log, ll, #trail, tl, ob, ot, int(openStart), int(trailStart) }, "|")
end

function Model.invalidate()
  cache, job, logCache, trailCache = nil, nil, nil, nil
end

local function fail(err)
  Model.lastError = (ns.Sanitize and ns.Sanitize.field(tostring(err))) or "?"
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

local function currentSig(db, guid)
  local char = type(db.chars) == "table" and db.chars[guid]
  if type(char) ~= "table" then return nil end
  local Store = ns.Store
  return signature(guid, char, (Store and Store.current == char) and Store or nil)
end

local function asyncOK(opts)
  return Model.ASYNC == true and not opts.sync and type(coroutine) == "table" and type(coroutine.create) == "function"
    and type(C_Timer) == "table" and type(C_Timer.After) == "function"
end

local function inCombat()
  if type(InCombatLockdown) ~= "function" then return false end
  local ok, v = pcall(InCombatLockdown)
  return ok and v == true
end

local function stepJob(j, budget)
  if job ~= j then return true end
  local c0 = clock()
  deadline, inJob = c0 + budget, true
  local ok, res = coroutine.resume(j.co)
  inJob, deadline = false, huge
  local dt = clock() - c0
  j.cpu, j.frames = j.cpu + dt, j.frames + 1
  if budget < huge and dt > j.maxFrame then j.maxFrame = dt end
  if not ok then
    job = nil
    fail(res)
    return true
  end
  if coroutine.status(j.co) ~= "dead" then return false end
  job = nil
  res.timings.cpu, res.timings.frames, res.timings.maxFrame = j.cpu, j.frames, j.maxFrame
  res.stale = currentSig(j.db, j.guid) ~= j.sig
  cache = { db = j.db, guid = j.guid, sig = j.sig, model = res }
  for _, fn in ipairs(readyFns) do
    if not pcall(fn, res) then Model.readyErrors = Model.readyErrors + 1 end
  end
  return true
end

local function schedule(j)
  local function tick()
    if job ~= j then return end
    if j.low and inCombat() then
      C_Timer.After(Model.COMBAT_RETRY, tick)
      return
    end
    local ok, done = pcall(stepJob, j, Model.FRAME_BUDGET)
    if not ok then
      if job == j then job = nil end
      fail(done)
    elseif not done then
      C_Timer.After(0, tick)
    end
  end
  C_Timer.After(0, tick)
end

local function startJob(ctx, sig, opts, low)
  if job and job.db == ctx.db and job.guid == ctx.guid then
    if not low then job.low = false end
    return job
  end
  local snap = snapshot(ctx.char, ctx.open)
  local o = { geo = opts.geo, now = opts.now }
  local j = { db = ctx.db, guid = ctx.guid, sig = sig, low = low, cpu = 0, frames = 0, maxFrame = 0 }
  j.co = coroutine.create(function() return build(ctx.db, ctx.guid, ctx.char, snap, o) end)
  job = j
  schedule(j)
  return j
end

function Model.get(opts)
  opts = opts or {}
  local ctx, why = resolve(opts)
  if not ctx then return nil, why end
  local sig = signature(ctx.guid, ctx.char, ctx.open)
  local now = tonumber(opts.now) or time()
  if not opts.force then
    local mine = cache and cache.db == ctx.db and cache.guid == ctx.guid
    if not mine and job and job.db == ctx.db and job.guid == ctx.guid then
      stepJob(job, huge)
      mine = cache and cache.db == ctx.db and cache.guid == ctx.guid
    end
    if mine and cache.sig == sig then
      cache.model.stale = false
      Model.refreshHeader(cache.model, now)
      return cache.model
    end
    if mine and opts.noRebuild then
      cache.model.stale = true
      Model.refreshHeader(cache.model, now)
      return cache.model
    end
    if mine and asyncOK(opts) then
      startJob(ctx, sig, opts, false)
      cache.model.stale = true
      Model.refreshHeader(cache.model, now)
      return cache.model
    end
  end
  job = nil
  local ok, model = pcall(build, ctx.db, ctx.guid, ctx.char, snapshot(ctx.char, ctx.open), opts)
  if not ok then
    fail(model)
    return nil, "fehler"
  end
  cache = { db = ctx.db, guid = ctx.guid, sig = sig, model = model }
  return model
end

function Model.prepare(opts)
  opts = opts or {}
  if not asyncOK(opts) then return false end
  local ctx = resolve(opts)
  if not ctx then return false end
  local sig = signature(ctx.guid, ctx.char, ctx.open)
  if cache and cache.db == ctx.db and cache.guid == ctx.guid and cache.sig == sig then return false end
  startJob(ctx, sig, opts, true)
  return true
end

function Model.prepareAfterLogin(delay)
  if prepScheduled or not asyncOK({}) then return false end
  delay = tonumber(delay) or Model.PREPARE_DELAY
  if delay ~= delay or delay < 0 or delay > 600 then delay = Model.PREPARE_DELAY end
  prepScheduled = true
  C_Timer.After(delay, function()
    local ok, err = pcall(Model.prepare)
    if not ok then fail(err) end
  end)
  return true
end

function Model.building() return job ~= nil end

function Model.onReady(fn)
  if type(fn) ~= "function" then return false end
  for _, f in ipairs(readyFns) do
    if f == fn then return true end
  end
  readyFns[#readyFns + 1] = fn
  return true
end

function Model.playedAt(model, t) return played(model._J, t) end
function Model.timeAt(model, p) return timeAt(model._J, p) end
function Model.chapterAt(model, t) return chapterIndex(model._J, t) end
function Model.formatWhen(model, t) return when(model._J, t) end
local function axisFind(arr, v)
  local lo, hi, best = 1, #arr, 0
  while lo <= hi do
    local mid = floor((lo + hi) / 2)
    if arr[mid] <= v then best, lo = mid, mid + 1 else hi = mid - 1 end
  end
  return best
end

function Model.toAxis(model, p)
  if type(p) ~= "number" or p ~= p or p == huge or p == -huge then return p end
  local idle = model and model.timeline and model.timeline.idle
  if not idle or #idle.a == 0 then return p end
  local i = axisFind(idle.a, p)
  if i == 0 then return p end
  local a, b, q = idle.a[i], idle.b[i], idle.q[i]
  local k = idle.k and idle.k[i] or idle.keep
  if p < b then return q + (p - a) * k / (b - a) end
  return q + k + (p - b)
end

function Model.fromAxis(model, q)
  if type(q) ~= "number" or q ~= q or q == huge or q == -huge then return q end
  local idle = model and model.timeline and model.timeline.idle
  if not idle or #idle.a == 0 then return q end
  local i = axisFind(idle.q, q)
  if i == 0 then return q end
  local a, b, q0 = idle.a[i], idle.b[i], idle.q[i]
  local k = idle.k and idle.k[i] or idle.keep
  if q < q0 + k then return a + (q - q0) * (b - a) / k end
  return b + (q - q0 - k)
end

function Model.zoneOf(model, mapID)
  if type(mapID) ~= "number" or mapID ~= mapID or isSecret(mapID) then return nil end
  return zoneOf(model._J, mapID)
end

local function viewKey(view)
  view = view or {}
  if view.map then return "m:" .. int(view.map) end
  if view.chapter then return "ch:" .. int(view.chapter) end
  if view.zone then return "z:" .. int(view.zone) end
  if view.continent then return "c:" .. int(view.continent) end
  return "all"
end

local function inView(view, chapter, zone, continent, map)
  view = view or {}
  if view.map then return map == view.map end
  if view.chapter then return chapter == view.chapter end
  if view.zone then return zone == view.zone end
  if view.continent then return continent == nil or continent == view.continent end
  return true
end

local function identity(_, x, y) return x, y end
local function identityAffine() return 0, 1, 0, 1 end

local function finite(v) return type(v) == "number" and v == v and v ~= huge and v ~= -huge end

local function projectPoint(project, map, x, y)
  local ok, vx, vy = pcall(project, map, x, y)
  if ok and type(vx) == "number" and type(vy) == "number" and vx == vx and vy == vy then return vx, vy end
  return nil
end

local dpStack = {}
local function significance(X, Y, s, e, SIG)
  for i = s, e do SIG[i] = 0 end
  SIG[s], SIG[e] = huge, huge
  local st, top = dpStack, 3
  st[1], st[2], st[3] = s, e, huge
  while top > 0 do
    local a, b, par = st[top - 2], st[top - 1], st[top]
    top = top - 3
    if b > a + 1 then
      local ax, ay, bx, by = X[a], Y[a], X[b], Y[b]
      local dx, dy = bx - ax, by - ay
      local len2 = dx * dx + dy * dy
      local best, bi = -1, a + 1
      for i = a + 1, b - 1 do
        local px, py = X[i] - ax, Y[i] - ay
        local d
        if len2 == 0 then
          d = px * px + py * py
        else
          local u = (px * dx + py * dy) / len2
          if u < 0 then u = 0 elseif u > 1 then u = 1 end
          local qx, qy = px - u * dx, py - u * dy
          d = qx * qx + qy * qy
        end
        if d > best then best, bi = d, i end
      end
      local sv = sqrt(best)
      if sv > par then sv = par end
      SIG[bi] = sv
      st[top + 1], st[top + 2], st[top + 3] = a, bi, sv
      st[top + 4], st[top + 5], st[top + 6] = bi, b, sv
      top = top + 6
    end
  end
end

local function playedCursor(J)
  local spT0, spT1, spCum, nSp, lastOpen = J.spT0, J.spT1, J.spCum, #J.spT0, J.spLastOpen
  local i = 0
  return function(t)
    if not (i > 0 and t >= spT0[i] and (i == nSp or t < spT0[i + 1])) then
      i = bsearch(spT0, t)
      if i == 0 then return 0 end
    end
    local d, len = t - spT0[i], spT1[i] - spT0[i]
    if d > len and not (i == nSp and lastOpen) then d = len end
    return spCum[i] + d
  end
end

local function route(model, view, opts)
  view = view or {}
  local project, pkey, affine = opts.project, opts.key, opts.affine
  if type(project) ~= "function" then project = nil end
  if type(affine) ~= "function" then affine = nil end
  local maxSeg = floor(tonumber(opts.maxSegments) or Model.MAX_SEGMENTS)
  if maxSeg > Model.LINE_POOL_MAX then maxSeg = Model.LINE_POOL_MAX end
  if maxSeg < 1 then maxSeg = 1 end
  local ck = viewKey(view) .. "|" .. (pkey or ((project or affine) and "" or "id")) .. "|" .. int(maxSeg)
  local cacheable = (pkey ~= nil) or (project == nil and affine == nil)
  if cacheable then
    local hit = model._routes[ck]
    if hit and not (hit._retryAt and clock() >= hit._retryAt) then return hit end
  end
  local generic = project ~= nil and affine == nil
  if not generic and not affine then affine = identityAffine end
  local affOf, affMiss = {}, false
  local function aff(map)
    local e = affOf[map]
    if e == nil then
      e = false
      local ok, a, b, c, d = pcall(affine, map)
      if ok and finite(a) and finite(b) and finite(c) and finite(d) then e = { a, b, c, d } else affMiss = true end
      affOf[map] = e
    end
    return e
  end
  local function proj1(map, x, y)
    if generic then return projectPoint(project, map, x, y) end
    local e = aff(map)
    if not e then return nil end
    return e[1] + e[2] * x, e[3] + e[4] * y
  end

  local segs = {}
  for _, f in ipairs(model.flights) do
    local vis = inView(view, f.chapter, f.zoneFrom, f.contFrom, f.from.mapID) or inView(view, f.chapter, f.zoneTo, f.contTo, f.to.mapID)
    if vis then
      local x1, y1 = proj1(f.from.mapID, f.from.x, f.from.y)
      local x2, y2 = proj1(f.to.mapID, f.to.x, f.to.y)
      if x1 and x2 and #segs < maxSeg then
        segs[#segs + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, p0 = f.p0, p = f.p1, kind = "flight", chapter = f.chapter }
      end
    end
  end

  local srcs, minX, minY, maxX, maxY, pathLen, total = {}, huge, huge, -huge, -huge, 0, 0
  local function extend(x1, x2, y1, y2)
    if x1 > x2 then x1, x2 = x2, x1 end
    if y1 > y2 then y1, y2 = y2, y1 end
    if x1 < minX then minX = x1 end
    if x2 > maxX then maxX = x2 end
    if y1 < minY then minY = y1 end
    if y2 > maxY then maxY = y2 end
  end
  local useLink = not view.chapter and not view.zone and not view.map
  local J = model._J
  for _, r in ipairs(model.runs) do
    if r.n > 0 and inView(view, r.chapter, r.zone, r.continent, r.mapID) then
      local lx, ly, lt
      local lk = r.link
      -- Whole-world views link every map change. Chapter/zone/map views link too, but only if the previous point lies in the
      -- view itself (a zone/sub-map flip at a border or gate); otherwise a line would reach in from outside.
      if lk and (useLink or inView(view, chapterIndex(J, lk.t), zoneOf(J, lk.mapID), continentOf(J, lk.mapID), lk.mapID)) then
        lx, ly = proj1(lk.mapID, lk.x / 10000, lk.y / 10000)
        lt = lk.t
        if lx then extend(lx, lx, ly, ly) end
      end
      if generic then
        local xs, ys, ts, n = {}, {}, {}, 0
        if lx then n, xs[1], ys[1], ts[1] = 1, lx, ly, lt end
        local rxs, rys, rts, map = r.xs, r.ys, r.ts, r.mapID
        for i = 1, r.n do
          local vx, vy = project(map, rxs[i] / 10000, rys[i] / 10000)
          if type(vx) == "number" and type(vy) == "number" and vx == vx and vy == vy then
            n = n + 1
            xs[n], ys[n], ts[n] = vx, vy, rts[i]
            extend(vx, vx, vy, vy)
            if n > 1 then pathLen = pathLen + abs(vx - xs[n - 1]) + abs(vy - ys[n - 1]) end
            total = total + 1
          else
            if n > 0 then srcs[#srcs + 1] = { xs = xs, ys = ys, ts = ts, n = n, a = 0, b = 1, c = 0, d = 1, chapter = r.chapter } end
            xs, ys, ts, n = {}, {}, {}, 0
          end
        end
        if n > 0 then srcs[#srcs + 1] = { xs = xs, ys = ys, ts = ts, n = n, a = 0, b = 1, c = 0, d = 1, chapter = r.chapter } end
      else
        local e = aff(r.mapID)
        if e then
          local a, b, c, d = e[1], e[2] / 10000, e[3], e[4] / 10000
          extend(a + b * r.minX, a + b * r.maxX, c + d * r.minY, c + d * r.maxY)
          pathLen = pathLen + abs(b) * r.lx + abs(d) * r.ly
          local src = { xs = r.xs, ys = r.ys, ts = r.ts, n = r.n, a = a, b = b, c = c, d = d, chapter = r.chapter }
          if lx then
            src.lx, src.ly, src.lt = lx, ly, lt
            pathLen = pathLen + abs(lx - (a + b * r.xs[1])) + abs(ly - (c + d * r.ys[1]))
          end
          srcs[#srcs + 1] = src
          total = total + r.raw
        end
      end
    end
  end
  local ext = math.max(maxX - minX, maxY - minY)
  if ext <= 0 or ext == -huge then ext = 1 end
  local minEps = ext * Model.SIMPLIFY_MIN
  local preEps = pathLen / (4 * maxSeg)
  if preEps < minEps then preEps = minEps end
  local pre2 = preEps * preEps

  local X, Y, T, parts, k = {}, {}, {}, {}, 0
  for _, s in ipairs(srcs) do
    local s0 = k + 1
    local a, b, c, d, xs, ys, ts, n = s.a, s.b, s.c, s.d, s.xs, s.ys, s.ts, s.n
    local kx, ky, len = nil, nil, 0
    if s.lx then
      k = k + 1
      X[k], Y[k], T[k] = s.lx, s.ly, s.lt
      kx, ky = s.lx, s.ly
    end
    for i = 1, n do
      local vx, vy = a + b * xs[i], c + d * ys[i]
      if kx == nil then
        k = k + 1
        X[k], Y[k], T[k] = vx, vy, ts[i]
        kx, ky = vx, vy
      else
        local dx, dy = vx - kx, vy - ky
        if i == n or dx * dx + dy * dy >= pre2 then
          len = len + abs(dx) + abs(dy)
          k = k + 1
          X[k], Y[k], T[k] = vx, vy, ts[i]
          kx, ky = vx, vy
        end
      end
    end
    if k > s0 then
      parts[#parts + 1] = { s = s0, e = k, chapter = s.chapter, len = len }
    else
      k = s0 - 1
    end
  end

  local budget = maxSeg - #segs
  local truncated = false
  if #parts > budget then
    truncated = true
    local order = {}
    for i in ipairs(parts) do order[i] = i end
    tsort(order, function(a, b)
      if parts[a].len ~= parts[b].len then return parts[a].len > parts[b].len end
      return a < b
    end)
    local keep = {}
    for i = 1, math.max(budget, 0) do keep[order[i]] = true end
    local kept = {}
    for i, pt in ipairs(parts) do if keep[i] then kept[#kept + 1] = pt end end
    parts = kept
  end

  local room = budget - #parts
  local interior = 0
  for _, pt in ipairs(parts) do interior = interior + (pt.e - pt.s - 1) end
  local theta, SIG = -1, nil
  if interior > room then
    SIG = {}
    local all = {}
    for _, pt in ipairs(parts) do
      significance(X, Y, pt.s, pt.e, SIG)
      for i = pt.s + 1, pt.e - 1 do if SIG[i] >= minEps then all[#all + 1] = SIG[i] end end
    end
    theta = minEps
    if #all > room then
      truncated = true
      if room <= 0 then
        theta = huge
      else
        local lo, hi = huge, -huge
        for _, s in ipairs(all) do
          if s < lo then lo = s end
          if s > hi then hi = s end
        end
        local L0, L1 = log(lo), log(hi)
        local B = 256
        local hist = {}
        for i = 1, B do hist[i] = 0 end
        local w = (L1 - L0) / B
        if w <= 0 then w = 1 end
        for _, s in ipairs(all) do
          local i = floor((log(s) - L0) / w) + 1
          if i > B then i = B end
          if i < 1 then i = 1 end
          hist[i] = hist[i] + 1
        end
        local acc, cut = 0, B + 1
        for i = B, 1, -1 do
          if acc + hist[i] > room then break end
          acc = acc + hist[i]
          cut = i
        end
        theta = (cut > B) and huge or math.exp(L0 + (cut - 1) * w)
        if theta < minEps then theta = minEps end
      end
    end
  end

  local playedAt = playedCursor(model._J)
  for _, pt in ipairs(parts) do
    local lastI = pt.s
    local lastP = playedAt(T[lastI])
    for i = pt.s + 1, pt.e do
      if (theta < 0 or SIG[i] >= theta) and #segs < maxSeg then
        local p = playedAt(T[i])
        segs[#segs + 1] = { x1 = X[lastI], y1 = Y[lastI], x2 = X[i], y2 = Y[i], p0 = lastP, p = p, kind = "walk",
          chapter = pt.chapter }
        lastI, lastP = i, p
      end
    end
  end
  for i, s in ipairs(segs) do s.i = i end
  tsort(segs, function(a, b)
    if a.p0 ~= b.p0 then return a.p0 < b.p0 end
    return a.i < b.i
  end)
  for _, s in ipairs(segs) do s.i = nil end
  -- End of the route in view coordinates (latest run), for the live tail between this point and the player arrow.
  local tail
  local lastRun = model.runs[#model.runs]
  if lastRun and lastRun.n > 0 and inView(view, lastRun.chapter, lastRun.zone, lastRun.continent, lastRun.mapID) then
    local tt = lastRun.ts[lastRun.n]
    -- No tail after a break (login, death, release, hearthstone, instance, pause: J.breaks) or from a flight/death point: the
    -- player is then somewhere else on purpose and the route must not be stitched to the arrow.
    local lp, br = model._J.lastPoint, model._J.breaks
    local broken = (br and #br > 0 and br[#br] > tt) or (lp and (lp.mark == "f" or lp.mark == "d"))
    local tx, ty
    if not broken then tx, ty = proj1(lastRun.mapID, lastRun.xs[lastRun.n] / 10000, lastRun.ys[lastRun.n] / 10000) end
    if tx then tail = { vx = tx, vy = ty, t = tt, mapID = lastRun.mapID } end
  end
  local res = { segments = segs, count = #segs, points = total, tolerance = theta < 0 and 0 or theta, truncated = truncated,
    partial = affMiss, tail = tail }
  if cacheable then
    -- Routes with unprojectable maps are cached only briefly (failures are not cached permanently).
    if affMiss then res._retryAt = clock() + Model.ROUTE_RETRY_SEC * 1000 end
    model._routes[ck] = res
  end
  return res
end

function Model.route(model, view, opts)
  opts = opts or {}
  local ok, res = pcall(route, model, view, opts)
  if ok then return res end
  Model.lastError = (ns.Sanitize and ns.Sanitize.field(tostring(res))) or "?"
  return { segments = {}, count = 0, points = 0, tolerance = 0, truncated = false, failed = true }
end

-- Projection for a view: continent from the view, else from chapter/zone/map or the main continent. If Geo has no rect for
-- the map (unknown ID, Retail without the Classic IDs) the fallback "map" uses map coordinates 1:1.
-- -> project, key, mode, map, affine (nil without an affine conversion)
function Model.projectorFor(model, view)
  view = view or {}
  local J = model._J
  local geo = J.geo
  local map = view.map
  if not map and view.chapter then
    local c = model.chapters[view.chapter]
    map = c and c.zoneID
  elseif not map and view.zone then
    map = view.zone
  end
  local cont = view.continent or (map and continentOf(J, map)) or (not map and model.continents[1] and model.continents[1].id) or nil
  if cont and geo and geo.projector then
    local okR = true
    if map and geo.rect then
      local ok, a = pcall(geo.rect, map, cont)
      okR = ok and a ~= nil
    end
    if okR then
      local ok, fn, key, aff = pcall(geo.projector, cont)
      if ok and type(fn) == "function" then
        return fn, key, "continent", map, (type(aff) == "function") and aff or nil
      end
    end
  end
  map = map or (model.current and model.current.mapID)
  return identity, "map:" .. (map and int(map) or "-"), "map", map, identityAffine
end

local KIND_RANK = { milestone = 1, boss = 2, death = 3, rare = 4, photo = 5, hearth = 6, flightpoint = 7, level = 8, elite = 9 }

function Model.markersIn(model, view, project, maxCount)
  project = project or identity
  maxCount = tonumber(maxCount) or Model.MARKERS_MAX
  local out = {}
  for i, m in ipairs(model.markers) do
    if inView(view, m.chapter, m.zone, m.continent, m.mapID) then
      local vx, vy = projectPoint(project, m.mapID, m.x, m.y)
      if vx then out[#out + 1] = { marker = m, vx = vx, vy = vy, i = i } end
    end
  end
  if #out > maxCount then
    tsort(out, function(a, b)
      local ra, rb = KIND_RANK[a.marker.kind] or 99, KIND_RANK[b.marker.kind] or 99
      if ra ~= rb then return ra < rb end
      return a.i < b.i
    end)
    for i = #out, maxCount + 1, -1 do out[i] = nil end
    tsort(out, function(a, b) return a.i < b.i end)
  end
  for _, o in ipairs(out) do o.i = nil end
  return out
end

Model.KILLS_CACHE = 6

-- Kill positions of a view from the KI log lines (with x/y; instance kills missing). Parallel series in time order { n, vx, vy,
-- p (played seconds), t, id (npcID or false), lv (level; -1 = boss; false = unknown) } plus name(id) and stamp(t) lookups. Names
-- are not copied per kill (looked up at tooltip time); the UI bundles in map pixels (Map.bundleKills). Memoised per pkey.
function Model.killsIn(model, view, project, pkey)
  project = project or identity
  local ck = pkey and (viewKey(view) .. "|" .. tostring(pkey)) or nil
  if ck and model._kills[ck] then return model._kills[ck] end
  local J = model._J
  local kT, kP = J.kT, J.kP
  local vx, vy, vp, vt, vi, vl, n = {}, {}, {}, {}, {}, {}, 0
  local kN, kL = J.kN, J.kL
  local ch = view and view.chapter
  local playedAt = playedCursor(J)
  for k = 1, #kT do
    local pk = kP[k]
    if pk then
      local y = pk % 10000
      local r = floor(pk / 10000)
      local x, map = r % 10000, floor(r / 10000)
      local t = kT[k]
      if inView(view, ch and chapterIndex(J, t) or nil, zoneOf(J, map), continentOf(J, map), map) then
        local px, py = projectPoint(project, map, x / 10000, y / 10000)
        if px then
          n = n + 1
          vx[n], vy[n], vt[n] = px, py, t
          vp[n] = playedAt(t)
          vi[n] = kN[k] or false
          vl[n] = kL[k] or false
        end
      end
    end
  end
  local res = { n = n, vx = vx, vy = vy, p = vp, t = vt, id = vi, lv = vl,
    name = function(id) return npcName(J, id) end, stamp = function(t) return stamp(J, t) end }
  if ck then
    if model._killsN >= Model.KILLS_CACHE then model._kills, model._killsN = {}, 0 end
    model._kills[ck] = res
    model._killsN = model._killsN + 1
  end
  return res
end

function Model.levelUpsIn(model, view, project)
  project = project or identity
  local J = model._J
  local out = {}
  for _, l in ipairs(J.lv) do
    if l.level >= 2 and l.level % 5 ~= 0 and l.map and l.x and l.y
      and inView(view, chapterIndex(J, l.t), zoneOf(J, l.map), continentOf(J, l.map), l.map) then
      local vx, vy = projectPoint(project, l.map, l.x / 10000, l.y / 10000)
      if vx then
        local p = played(J, l.t)
        out[#out + 1] = {
          level = l.level, vx = vx, vy = vy, p = p, t = l.t, mapID = l.map,
          tip = tip(J, MT("levelReached", int(l.level)), l.t, l.map, nil, MT("afterPlayed", Model.formatPlayed(p))),
        }
      end
    end
  end
  return out
end

function Model.gapsIn(model, view, project)
  project = project or identity
  local out = {}
  for _, g in ipairs(model.gaps) do
    if inView(view, g.chapter, g.zone, g.continent, g.mapID) then
      local vx, vy
      if g.mapID and g.x then vx, vy = projectPoint(project, g.mapID, g.x, g.y) end
      out[#out + 1] = { gap = g, vx = vx, vy = vy }
    end
  end
  return out
end

function Model.notes(model, view, project)
  project = project or identity
  local J = model._J
  local key = view and view.chapter and ("ch:" .. int(view.chapter)) or "all"
  local cands = model._notes[key]
  if not cands then
    if view and view.chapter then
      local c = J.chapters[view.chapter]
      local flights = {}
      for _, f in ipairs(J.flights) do if f.chapter == view.chapter then flights[#flights + 1] = f end end
      cands = c and noteCandidates(J, c.agg.deaths, c.agg.specials, flights, c.agg.lv, true) or {}
    else
      cands = noteCandidates(J, J.deaths, J.specials, J.flights, J.lv, false)
    end
    model._notes[key] = cands
  end
  local list = {}
  for _, n in ipairs(cands) do
    local zone, cont = zoneOf(J, n.mapID), continentOf(J, n.mapID)
    local ok = true
    if view and view.map then ok = n.mapID == view.map end
    if view and view.zone then ok = zone == view.zone end
    if view and view.continent then ok = cont == nil or cont == view.continent end
    if ok then
      local vx, vy = projectPoint(project, n.mapID, n.x, n.y)
      if vx then
        list[#list + 1] = { text = n.text, kind = n.kind, mapID = n.mapID, x = n.x, y = n.y, vx = vx, vy = vy, score = n.score, t = n.t }
      end
    end
  end
  tsort(list, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.t < b.t
  end)
  for i = Model.NOTES_MAX + 1, #list do list[i] = nil end
  return list
end

-- View settings of the travel map (EveNChronicleDB.ui): the model's only write access. Pages.setSetting additionally writes
-- toast, albumFilter and kampfHunted there; Model.settings does not touch those keys.

local POINTS = { CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true, TOPLEFT = true, TOPRIGHT = true,
  BOTTOMLEFT = true, BOTTOMRIGHT = true }

function Model.settings()
  local db = EveNChronicleDB
  if type(db) ~= "table" then return nil end
  local ui = db.ui
  if type(ui) ~= "table" then
    ui = {}
    db.ui = ui
  end
  -- Same checks on read as on write (setSetting): the SV may be edited by hand or by another addon (type, NaN, infinity, range,
  -- anchor point). ui.scaleSet marks a scale the player chose; without it Frame.defaultScale applies. Old state without the flag:
  -- a value other than 1 was a choice, 1 was only the former default.
  local scaleOk = not isSecret(ui.scale) and type(ui.scale) == "number" and ui.scale >= 0.5 and ui.scale <= 2 -- NaN: false
  if ui.scaleSet ~= true or not scaleOk then ui.scaleSet = nil end
  for k, v in pairs(Model.UI_DEFAULTS) do
    if type(ui[k]) ~= type(v) or isSecret(ui[k]) then ui[k] = v end
  end
  if not Model.SPEEDS[ui.speed] then ui.speed = Model.UI_DEFAULTS.speed end
  if not Model.MAP_COLORS[ui.mapColor] then ui.mapColor = Model.UI_DEFAULTS.mapColor end
  ui.page = nil
  if not (ui.scale >= 0.5 and ui.scale <= 2) then ui.scale = Model.UI_DEFAULTS.scale end -- also catches NaN
  if scaleOk and ui.scaleSet == nil and ui.scale ~= Model.UI_DEFAULTS.scale then ui.scaleSet = true end
  if not (ui.minimapAngle > -huge and ui.minimapAngle < huge) then
    ui.minimapAngle = Model.UI_DEFAULTS.minimapAngle
  elseif ui.minimapAngle < 0 or ui.minimapAngle >= 360 then
    ui.minimapAngle = ui.minimapAngle % 360
  end
  local pos = ui.pos
  if pos ~= nil then
    local okPos = type(pos) == "table" and not isSecret(pos) and POINTS[pos.point] and type(pos.x) == "number"
      and type(pos.y) == "number" and abs(pos.x) <= 10000 and abs(pos.y) <= 10000 -- abs(NaN) <= ... is false
    if okPos then
      if pos.x ~= floor(pos.x + 0.5) or pos.y ~= floor(pos.y + 0.5) then
        ui.pos = { point = pos.point, x = floor(pos.x + 0.5), y = floor(pos.y + 0.5) }
      end
    else
      ui.pos = nil
    end
  end
  return ui
end

function Model.setSetting(key, value)
  local ui = Model.settings()
  if not ui or isSecret(value) then return false end
  if key == "scale" and value == nil then
    ui.scale, ui.scaleSet = Model.UI_DEFAULTS.scale, nil
    return true
  elseif key == "scale" then
    if type(value) ~= "number" or value ~= value or value < 0.5 or value > 2 then return false end
  elseif key == "speed" then
    if not Model.SPEEDS[value] then return false end
  elseif key == "mapColor" then
    if type(value) ~= "string" or not Model.MAP_COLORS[value] then return false end
  elseif key == "minimap" or key == "reduceMotion" or key == "showKills" then
    if type(value) ~= "boolean" then return false end
  elseif key == "minimapAngle" then
    if type(value) ~= "number" or value ~= value then return false end
    value = value % 360
  elseif key == "pos" then
    if value == nil then ui.pos = nil return true end
    if type(value) ~= "table" or not POINTS[value.point] or type(value.x) ~= "number" or type(value.y) ~= "number"
      or abs(value.x) > 10000 or abs(value.y) > 10000 then return false end
    value = { point = value.point, x = floor(value.x + 0.5), y = floor(value.y + 0.5) }
  else
    return false
  end
  ui[key] = value
  if key == "scale" then ui.scaleSet = true end
  return true
end
