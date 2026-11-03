-- Open quests ("Offen" under Quests): pure logic. Source: addon InkAndEmbers_QuestData (LoadOnDemand, built
-- from QuestieDB by scripts/build-quest-data.mjs), loaded on the first call (never in combat or before login, in pcall;
-- a failure keeps its reason and retries after OpenQuests.RETRY s).
-- It sets the global EveNChronicleQuestData, which is parsed once into compact records and cleared.
-- quest = string, per quest "\n<id>\t<name>\t<reqLvl>\t<qLvl>\t<races>\t<classes>\t<preAll>\t<preAny>\t<excl>\t<flags>\t<givers>"
--   races/classes = bitmasks (decimal, empty = no restriction); race bits 0-7 = Human, Orc, Dwarf, Night Elf, Undead,
--   Tauren, Gnome, Troll, higher bits = non-classic races;
--   classes: Warrior 1, Paladin 2, Hunter 4, Rogue 8, Priest 16, Shaman 64, Mage 128, Warlock 256, Druid 1024;
--   preAll/preAny/excl = quest IDs;
--   flags: u (beta data unsure), r (repeatable), g (group/dungeon/raid/PvP/event), s (profession/reputation/spell/max
--   level required, not checkable), k (category quest);
--   givers = keys "n<id>[A|H]" (NPC) / "o<id>[A|H]" (object), comma-separated, suffix A/H = Alliance/Horde only; empty
--   givers = no map point, the quest never appears in the open list.
-- giver = string, per giver "\n<n|o><id>\t<name>\t<uiMapID>:<x>,<y>;<x>,<y>|<uiMapID>:..." (x/y 0-100 percent of the
-- map, y from the top).
-- Names: quest/giver carry the German name where one exists; questEN/giverEN ("\n<id|key>\t<English name>") replace it
-- in a non-German client, questNoDE/giverNoDE ("<id|key>,...") list the ones without a German name. The client's own
-- cache wins where it answers (quest titles; NPC names only for giverNoDE in a German client), never in the retail test.
-- overlay = per overlay "\n<uiMapID>\t<w>\t<h>\t<offsetX>\t<offsetY>\t<fileDataID>,..." (all exploration overlays,
-- pixels of art layer 1): uncovered zone maps (OpenQuests.overlays). overlayRetail = the same for the retail map IDs
-- (retail client); overlay is used in the data map space (Forever).
-- Map IDs and points in and out of this API are the client's: Forever uses the data's (Classic) IDs, the retail client
-- ALWAYS the retail IDs of the same zones with converted points (Journal.MapSpace).
-- A quest is "open" when it is not completed (C_QuestLog.IsQuestFlaggedCompleted or "turned in" in the Chronik log),
-- not in the quest log, race and class fit, min level <= level, all preAll are done, one preAny is done and no excl
-- quest is done or accepted; otherwise "locked".
-- Beta data unsure: flag u, min level > 30, or (without min level) quest level > 30.
-- Retail client: list/zones/available/footer/diagLine/clientZone go to Journal.OpenQuestsRetail (runtime source from
-- the game's world map, journal/model/OpenQuestsRetail.lua); the data addon is never loaded there. The test mode and
-- OpenQuests.ALLOW_RETAIL keep the data addon in the retail map space. Forever is unchanged.
-- Live source (Forever, change "questiedb"): when the addon QuestieDB is installed and fits (OpenQuestsQDB.probe: no retail,
-- loaded, baked, flavor Forever, contract 1 in range, OpenQuests.QDB_LIVE), quests and givers are read from it
-- (journal/model/OpenQuestsQDB.lua) in a coroutine with a time budget per frame (QDB_BUDGET_MS, never in combat), started
-- on the first load. Until it is finished the data addon answers; then its quests/givers are replaced (overlays stay from
-- the data addon, its flags r/g are added, they carry the Forever database's quest type). Failure or no fitting QuestieDB:
-- the data addon stays. OpenQuests.sourceInfo() tells source and reason (diagnostics), the footer names the source.
-- The retail client never touches QuestieDB.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local OpenQuests = {}
Journal.OpenQuests = OpenQuests

local find, sub, gsub, gmatch, match, lower, format = string.find, string.sub, string.gsub, string.gmatch, string.match, string.lower, string.format
local floor, tonumber, tostring, sort, max, min = math.floor, tonumber, tostring, table.sort, math.max, math.min

OpenQuests.ADDON = "InkAndEmbers_QuestData"
OpenQuests.GLOBAL = "EveNChronicleQuestData"
OpenQuests.RETRY = 10 -- seconds until the next load attempt after a failure
OpenQuests.UNSURE_LEVEL = 30 -- from level > 30 the data is unconfirmed for Forever
OpenQuests.NAME_MAX = 80
OpenQuests.RADIUS = 0.012
OpenQuests.MAX_PINS = 300
OpenQuests.TOOLTIP_LINES = 10
OpenQuests.NAME_REQUESTS = 60 -- client quest-title loads per evaluation (only quests without a German name)
OpenQuests.NPC_TRIES = 3 -- tooltip lookups per NPC without a German name

-- texts (German here, English in locales/enUS_model.lua, scope "m.OpenQuests"; read only on use)
local T = ns.Locale.ns("m.OpenQuests", {
  level = "Stufe %d nötig",
  prequest = "Vorquest fehlt: %s",
  prequestMore = "Vorquest fehlt: %s (+%d weitere)",
  prequestAny = "Vorquest fehlt: %s",
  exclusive = "schließt sich mit %s aus",
  foreignRace = "nur für andere Völker",
  foreignClass = "nur für andere Klassen",
  foreignFaction = "nur für die andere Fraktion",
  notChecked = "Beruf/Ruf nicht geprüft",
  raceUnsure = "Volk nicht sicher geprüft",
  unsureLabel = "Beta-Daten unsicher",
  unsureTip = "Stufe über 30: Forever-Stand unbestätigt",
  testLabel = "Testmodus (Retail): Inhalte nicht aussagekräftig",
  footer = "Daten: QuestieDB %s (Addon-Auszug)",
  footerNoVersion = "Daten: QuestieDB (Addon-Auszug)",
  footerLive = "Daten: QuestieDB %s (live)",
  footerLiveNoVersion = "Daten: QuestieDB (live)",
  -- source of the data (OpenQuests.sourceInfo, diagnostics)
  sourceLive = "live",
  sourceExtract = "Addon-Auszug %s (%s)",
  sourceExtractNone = "Addon-Auszug nicht geladen (%s)",
  srcREADY = "QuestieDB passt, wird beim Öffnen gelesen",
  srcBUILDING = "QuestieDB wird gelesen",
  srcWAITING = "QuestieDB wartet auf das Kampfende",
  srcRETAIL = "Retail nutzt QuestieDB nie",
  srcOFF = "QuestieDB-Quelle abgeschaltet",
  srcNO_API = "Addon-Schnittstelle fehlt",
  srcNOT_LOADED = "QuestieDB nicht geladen",
  srcNO_LIB = "LibQuestieDB fehlt oder ist unvollständig",
  srcNOT_BAKED = "QuestieDB läuft im Quellmodus",
  srcFLAVOR = "QuestieDB nicht für Forever",
  srcCONTRACT = "QuestieDB-Version passt nicht (Vertrag)",
  srcZONES = "Zonendaten von QuestieDB fehlen",
  srcEMPTY = "QuestieDB lieferte keine Quests",
  srcFAILED = "Fehler beim Lesen aus QuestieDB",
  srcNO_TIMER = "Zeitgeber fehlt",
  todoText = "Quest annehmen: %s",
  more = "… und %d weitere",
  mapFallback = "Karte %d",
  questFallback = "Quest %d",
  kalimdor = "Kalimdor",
  easternKingdoms = "Östliche Königreiche",
  -- load reasons of the data addon (OpenQuests.REASONS)
  DISABLED = "im Addon-Menü deaktiviert",
  DEP_DISABLED = "Ink & Embers ist im Addon-Menü deaktiviert",
  MISSING = "Zusatzaddon InkAndEmbers_QuestData nicht installiert",
  DEP_MISSING = "Ink & Embers fehlt",
  INTERFACE_VERSION = "Zusatzaddon veraltet (Spielversion)",
  INCOMPATIBLE = "Zusatzaddon passt nicht zu dieser Spielversion",
  CORRUPT = "Zusatzaddon beschädigt",
  RETAIL = "In Retail kommen die offenen Quests aus der Weltkarte des Spiels",
  NO_QUESTLINE = "Die Weltkarte des Spiels liefert keine Quest-Angebote (Schnittstelle fehlt)",
  BANNED = "vom Spiel gesperrt",
  INSECURE = "vom Spiel gesperrt",
  NOT_DEMAND_LOADED = "nicht auf Abruf ladbar (LoadOnDemand fehlt)",
  COMBAT = "im Kampf (wird danach geladen)",
  NOT_LOGGED_IN = "noch nicht angemeldet",
  NO_API = "Ladefunktion fehlt",
  NO_DATA = "Zusatzaddon geladen, aber ohne Questliste (neu installieren)",
  ERROR = "Fehler beim Laden",
  UNKNOWN = "unbekannter Grund",
  notTried = "noch nicht versucht",
  depMissing = "abhängiges Addon fehlt (%s)",
  diagLoaded = "Offene Quests: geladen (%d Quests, %d Geber%s)",
  diagVersion = ", Stand %s",
  diagNotLoaded = "Offene Quests: nicht geladen: %s",
  diagQdb = "QuestieDB installiert: %s (Contract %s) · Quelle: %s",
  diagQdbNone = "QuestieDB nicht installiert · Quelle: %s",
  diagQdbUnknown = "?",
  testOff = "Offene Quests: Testmodus aus.",
  testOn = "Offene Quests: Testmodus an (Volk %s, Klasse %s, Stufe %s). %s",
  testLevelUsage = "Offene Quests: /chronik offene test stufe <Zahl>",
  testRaceUsage = "Offene Quests: Volk-Kennung z. B. Scourge, Human, Orc, NightElf, Dwarf, Gnome, Tauren, Troll",
  testClassUsage = "Offene Quests: Klassen-Kennung z. B. PALADIN, WARRIOR, MAGE, PRIEST, DRUID",
})
OpenQuests.TEXT = T
-- label/tooltip "Beta-Daten unsicher": read in the active language on access
setmetatable(OpenQuests, { __index = function(_, k)
  if k == "unsureLabel" or k == "unsureTip" then return T[k] end
end })

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if not r[1] then return nil end
  for i = 2, #r do
    if isSecret(r[i]) then return nil end
  end
  return r[2], r[3], r[4]
end

local function num(v)
  if isSecret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function display(s)
  local S_ = ns.Sanitize
  return S_ and S_.display(s, OpenQuests.NAME_MAX) or nil
end

local function inCombat()
  if type(InCombatLockdown) ~= "function" then return false end
  local ok, v = pcall(InCombatLockdown)
  return ok and not isSecret(v) and v == true
end

local function now()
  if type(GetTime) ~= "function" then return 0 end
  local ok, t = pcall(GetTime)
  return (ok and not isSecret(t) and type(t) == "number") and t or 0
end

local function loggedIn()
  if type(IsLoggedIn) ~= "function" then return true end
  local ok, v = pcall(IsLoggedIn)
  if not ok or isSecret(v) then return true end
  return v ~= false and v ~= nil
end

-- session state (tests: OpenQuests._state). data = parsed data; gen = evaluation generation (rises on every event);
-- eval = cached evaluation { gen, key, items = {...} }; flag = cache of IsQuestFlaggedCompleted; turned = quests turned
-- in this session
local S = { tried = false, loadCalls = 0, data = nil, reason = nil, nextTry = nil, gen = 0, eval = nil, flag = {}, turned = {}, test = nil,
  levelHint = nil, evalCount = 0 }
OpenQuests._state = S

local EMPTY = {}

local function idList(s)
  if s == nil or s == "" then return nil end
  local out
  for d in gmatch(s, "%d+") do
    local n = tonumber(d)
    if n and n > 0 and n <= 2147483647 then
      out = out or {}
      out[#out + 1] = n
    end
  end
  return out
end

-- one shared, read-only table per flag text (records never change their flag table in place)
local FLAG_SETS = {}

local function flagSet(s)
  if s == nil or s == "" then return EMPTY end
  local f = FLAG_SETS[s]
  if f then return f end
  for c in gmatch(s, "[urgsk]") do
    f = f or {}
    f[c] = true
  end
  f = f or EMPTY
  FLAG_SETS[s] = f
  return f
end

-- records hold only the fields that are set (a constructor listing nil fields reserves their slots); giver key lists are
-- shared per giver text (read-only)
local function parseQuests(blob)
  local quests, count, keyLists = {}, 0, {}
  for line in gmatch(blob, "\n([^\n]*)") do
    local id, name, req, ql, races, classes, preAll, preAny, excl, flags, givers =
      match(line, "^(%d+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t?([^\t]*)$")
    id = id and tonumber(id)
    if id and id > 0 and not quests[id] then
      local keys
      if givers and givers ~= "" then
        keys = keyLists[givers]
        if keys == nil then
          for key in gmatch(givers, "[no]%d+[AH]?") do
            keys = keys or {}
            keys[#keys + 1] = key
          end
          keyLists[givers] = keys or false
        end
        keys = keys or nil
      end
      local minL = tonumber(req)
      local qLevel = tonumber(ql)
      local q = { id = id, name = name, minLevel = (minL and minL > 0) and floor(minL) or 0, races = tonumber(races) or 0,
        classes = tonumber(classes) or 0, flags = flagSet(flags) }
      q.level = (qLevel and qLevel > 0) and floor(qLevel) or nil
      q.givers = keys
      q.preAll = idList(preAll)
      q.preAny = idList(preAny)
      q.excl = idList(excl)
      quests[id] = q
      count = count + 1
    end
  end
  return quests, count
end

-- "\n<key>\t<name>" -> map key -> name (empty names skipped)
local function parseNames(blob)
  local out = {}
  if type(blob) ~= "string" then return out end
  for key, name in gmatch(blob, "\n([^\t\n]+)\t([^\n]+)") do
    if not out[key] then out[key] = name end
  end
  return out
end

local function parseKeys(text)
  local out = {}
  if type(text) ~= "string" then return out end
  for key in gmatch(text, "[^,]+") do out[key] = true end
  return out
end

-- overlay blob -> map ID -> list of { textureWidth, textureHeight, offsetX, offsetY, fileDataIDs } (the shape of
-- C_MapExplorationInfo.GetExploredMapTextures, so View.overlayTiles cuts them like explored ones)
local function parseOverlays(blob)
  local out = {}
  if type(blob) ~= "string" then return out end
  for line in gmatch(blob, "\n([^\n]+)") do
    local mid, w, h, x, y, files = match(line, "^(%d+)\t(%d+)\t(%d+)\t(%d+)\t(%d+)\t([%d,]+)$")
    mid, w, h, x, y = tonumber(mid), tonumber(w), tonumber(h), tonumber(x), tonumber(y)
    if mid and w and h and x and y and w > 0 and h > 0 then
      local ids = {}
      for f in gmatch(files, "%d+") do ids[#ids + 1] = tonumber(f) end
      local list = out[mid]
      if not list then
        list = {}
        out[mid] = list
      end
      list[#list + 1] = { textureWidth = w, textureHeight = h, offsetX = x, offsetY = y, fileDataIDs = ids }
    end
  end
  return out
end

local function clientGerman()
  local L = ns.Locale
  local loc = L and L.clientLocale and L.clientLocale() or nil
  return loc == "deDE"
end

local function parseGivers(blob)
  local givers, count = {}, 0
  for line in gmatch(blob, "\n([^\n]*)") do
    local kind, id, fac, name, maps = match(line, "^([no])(%d+)([AH]?)\t([^\t]*)\t?([^\t]*)$")
    if kind then
      local g = { kind = kind == "n" and "npc" or "object", id = tonumber(id), name = name, maps = {},
        faction = fac == "A" and "Alliance" or fac == "H" and "Horde" or nil }
      for part in gmatch(maps or "", "[^|]+") do
        local mid, pts = match(part, "^(%d+):(.*)$")
        mid = mid and tonumber(mid)
        if mid and mid > 0 then
          local points = {}
          for x, y in gmatch(pts, "([%d%.]+),([%d%.]+)") do
            local px, py = tonumber(x), tonumber(y)
            if px and py and px >= 0 and px <= 100 and py >= 0 and py <= 100 then points[#points + 1] = { px / 100, py / 100 } end
          end
          if #points > 0 then g.maps[#g.maps + 1] = { mapID = floor(mid), points = points } end
        end
      end
      givers[kind .. id .. fac] = g
      count = count + 1
    end
  end
  return givers, count
end

-- adopt the data addon's global table (valid parts only), parse it, drop the raw data and the global
local function adopt()
  local g = _G[OpenQuests.GLOBAL]
  if type(g) ~= "table" then return false end
  _G[OpenQuests.GLOBAL] = nil
  if type(g.quest) ~= "string" or sub(g.quest, 1, 1) ~= "\n" then return false end
  local ok, quests, nq = pcall(parseQuests, g.quest)
  if not ok or nq == 0 then return false end
  local givers, ng = {}, 0
  if type(g.giver) == "string" and sub(g.giver, 1, 1) == "\n" then
    local ok2, gv, n2 = pcall(parseGivers, g.giver)
    if ok2 then givers, ng = gv, n2 end
  end
  local version = type(g.version) == "string" and display(g.version) or nil
  local factions = type(g.factions) == "string" and match(g.factions, "^[%l+]+$") and sub(g.factions, 1, 20) or nil
  -- names in the client language: German client keeps the German names (and asks its cache for the rest), any other
  -- client gets the English ones
  local german = clientGerman()
  local okN, qEN = pcall(parseNames, g.questEN)
  local okG, gEN = pcall(parseNames, g.giverEN)
  if not german then
    if okN then for key, name in pairs(qEN) do local q = quests[tonumber(key)] if q then q.name = name end end end
    if okG then for key, name in pairs(gEN) do local gv = givers[key] if gv then gv.name = name end end end
  else
    local okQ, qNo = pcall(parseKeys, g.questNoDE)
    if okQ then for key in pairs(qNo) do local q = quests[tonumber(key)] if q then q.noDE = true end end end
    local okK, gNo = pcall(parseKeys, g.giverNoDE)
    if okK then for key in pairs(gNo) do local gv = givers[key] if gv then gv.noDE = true end end end
  end
  local okO, overlays = pcall(parseOverlays, g.overlay)
  local okR, overlaysRetail = pcall(parseOverlays, g.overlayRetail)
  S.data = { quests = quests, givers = givers, nQuests = nq, nGivers = ng, version = version, factions = factions,
    overlays = okO and overlays or {}, overlaysRetail = okR and overlaysRetail or {}, german = german }
  S.eval = nil
  S.index = nil
  return true
end

local function fail(reason, wait)
  S.reason = reason
  S.nextTry = wait and (now() + OpenQuests.RETRY) or nil
  return false
end

local function loaded()
  S.reason, S.nextTry = nil, nil
  return true
end

local function cleanReason(r)
  if isSecret(r) or type(r) ~= "string" then return nil end
  r = match(r, "^[%u%d_]+$")
  return r and sub(r, 1, 40) or nil
end

-- Retail client (Journal.MapSpace.retailClient: project id AND interface version, so Forever is never taken for Retail): the QuestieDB data does not
-- match retail zones, so the data addon stays unloaded there and the world map source (Journal.OpenQuestsRetail) answers;
-- the test mode (OpenQuests.setTest) and OpenQuests.ALLOW_RETAIL (tests of the retail map space) keep the data addon.
function OpenQuests.retailClient()
  local ms = Journal.MapSpace
  return ms ~= nil and ms.retailClient() == true
end

-- Switch for the retail world map source (OpenQuestsRetail, C_QuestLine). ON: tested in the game (Retail 12.1.5, Tirisfal, level 5:
-- filled list). false = "Open" stays locked in Retail (reason RETAIL) as in 0.9.2. The diagnostic /chronik diag retailquests
-- does not depend on it.
OpenQuests.RETAIL_SOURCE = true

-- the retail world map source when it is in charge, else nil
local function retailSource()
  if S.test or OpenQuests.ALLOW_RETAIL or not OpenQuests.retailClient() then return nil end
  local R = Journal.OpenQuestsRetail
  return (R and R.active and R.active()) and R or nil
end
OpenQuests.retailSource = retailSource

-- ---------------------------------------------------------------- live source QuestieDB (Forever)

OpenQuests.QDB_LIVE = true -- decision F5: automatic, no setting; false = always the data addon
OpenQuests.QDB_BUDGET_MS = 4 -- work per frame (debugprofilestop)
OpenQuests.QDB_STEP_ITEMS = 150 -- quests per frame at most (the only limit without a clock)
OpenQuests.QDB_COMBAT_WAIT = 2 -- seconds between checks while in combat
OpenQuests.QDB_FRAME_DELAY = 0 -- C_Timer.After delay between steps (0 = next frame)

-- S.live = { state = "off"|"building"|"waiting"|"done"|"failed", reason, version, job, steps, maxStep, ms }
local function qdb() return Journal.OpenQuestsQDB end

local function clockFn()
  local f = rawget(_G, "debugprofilestop")
  if type(f) ~= "function" then return nil end
  return function()
    local ok, v = pcall(f)
    return (ok and num(v)) or 0
  end
end

local function after(sec, fn)
  if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return false end
  return (pcall(C_Timer.After, sec, fn))
end

local function liveVersion()
  local Q = qdb()
  local ok, v = pcall(Q.version)
  return ok and type(v) == "string" and display(v) or nil
end

-- the finished job replaces quests/givers; overlays and the flags r/g (Forever database quest type) of the data addon stay
local function finishLive(L, job)
  if job.nQuests == 0 then
    L.state, L.reason = "failed", "EMPTY"
    return
  end
  local old = S.data
  if old then
    for id, q in pairs(job.quests) do
      local o = old.quests[id]
      local add = o and o.flags and ((o.flags.r and not q.flags.r) or (o.flags.g and not q.flags.g))
      if add then
        local f = {}
        for k in pairs(q.flags) do f[k] = true end
        if o.flags.r then f.r = true end
        if o.flags.g then f.g = true end
        q.flags = f
      end
    end
  end
  S.data = { quests = job.quests, givers = job.givers, nQuests = job.nQuests, nGivers = job.nGivers, version = L.version,
    overlays = old and old.overlays or {}, overlaysRetail = old and old.overlaysRetail or {}, german = job.ctx.german, live = true }
  L.state, L.reason, L.job = "done", "ACTIVE", nil
  L.quests, L.givers = job.nQuests, job.nGivers
  L.sharedQuests, L.sharedGivers = job.sharedQuests, job.sharedGivers
  S.reason, S.nextTry, S.pending = nil, nil, nil
  S.index = nil
  OpenQuests.invalidate()
  OpenQuests._changed()
end

-- one frame of the live job; never in combat (waits), re-scheduled with C_Timer.After(0)
local function liveStep()
  local L = S.live
  if not L or (L.state ~= "building" and L.state ~= "waiting") then return end
  if inCombat() then
    L.state = "waiting"
    if not after(OpenQuests.QDB_COMBAT_WAIT, liveStep) then L.state, L.reason = "failed", "NO_TIMER" end
    return
  end
  L.state = "building"
  L.frames = (L.frames or 0) + 1
  local Q = qdb()
  if not L.job then
    local ok, usable, why, lib = pcall(Q.probe)
    if not ok or not usable then
      L.state, L.reason = "failed", ok and why or "FAILED"
      return
    end
    -- base = the data addon's records: equal live records are shared instead of copied (memory)
    local okJ, job = pcall(Q.newJob, lib, { german = clientGerman(), empty = EMPTY, base = S.data })
    if not okJ or type(job) ~= "table" then
      L.state, L.reason = "failed", "FAILED"
      return
    end
    L.job = job
  end
  local job = L.job
  local okS, r = pcall(Q.step, job, OpenQuests.QDB_BUDGET_MS, clockFn(), OpenQuests.QDB_STEP_ITEMS)
  L.steps, L.maxStep, L.ms = job.steps, job.maxStep, job.ms
  if not okS or r == "error" then
    L.state, L.reason, L.job = "failed", (okS and job.fail) or "FAILED", nil
    return
  end
  if r == "done" then
    finishLive(L, job)
    return
  end
  if not after(OpenQuests.QDB_FRAME_DELAY, liveStep) then L.state, L.reason, L.job = "failed", "NO_TIMER", nil end
end
OpenQuests._liveStep = liveStep

-- start the live source once (after login); without a fitting QuestieDB the reason is kept and the data addon answers
local function startLive()
  if S.live or S.test or not loggedIn() then return end
  local Q = qdb()
  if not (Q and type(Q.probe) == "function") then
    S.live = { state = "off", reason = "NO_LIB" }
    return
  end
  local ok, usable, why = pcall(Q.probe)
  if not ok then
    S.live = { state = "off", reason = "FAILED" }
    return
  end
  if not usable then
    S.live = { state = "off", reason = why }
    return
  end
  S.live = { state = "building", reason = "BUILDING", version = liveVersion() }
  if not after(OpenQuests.QDB_FRAME_DELAY, liveStep) then S.live.state, S.live.reason = "failed", "NO_TIMER" end
end
OpenQuests._startLive = startLive

local SRC_TEXT = { READY = "srcREADY", BUILDING = "srcBUILDING", WAITING = "srcWAITING", RETAIL = "srcRETAIL",
  OFF = "srcOFF", NO_API = "srcNO_API", NOT_LOADED = "srcNOT_LOADED", NO_LIB = "srcNO_LIB", NOT_BAKED = "srcNOT_BAKED",
  FLAVOR = "srcFLAVOR", CONTRACT = "srcCONTRACT", ZONES = "srcZONES", EMPTY = "srcEMPTY", FAILED = "srcFAILED", NO_TIMER = "srcNO_TIMER" }

-- source of the open quests (diagnostics): { source = "questiedb"|"extract", reason = KEY, reasonText, version, text,
-- quests, givers, steps, maxStep (ms of the longest frame), ms, frames }. Reads nothing in retail beyond the client check.
function OpenQuests.sourceInfo()
  local L = S.live
  local reason
  if L then
    reason = L.state == "waiting" and "WAITING" or L.reason
  elseif OpenQuests.retailClient() then
    reason = "RETAIL"
  else
    local Q = qdb()
    local ok, usable, why = false, false, "NO_LIB"
    if Q and type(Q.probe) == "function" then ok, usable, why = pcall(Q.probe) end
    reason = not ok and "FAILED" or (usable and "READY" or why)
  end
  local live = L ~= nil and L.state == "done"
  if live then reason = "ACTIVE" end
  reason = (reason == "ACTIVE" or SRC_TEXT[reason]) and reason or "FAILED"
  local d = S.data
  local info = { source = live and "questiedb" or "extract", reason = reason, reasonText = SRC_TEXT[reason] and T[SRC_TEXT[reason]] or nil,
    version = live and L.version or (d and not d.live and d.version) or nil, quests = L and L.quests, givers = L and L.givers,
    steps = L and L.steps, maxStep = L and L.maxStep, ms = L and L.ms, frames = L and L.frames }
  if live then
    info.text = T.sourceLive
  elseif info.version then
    info.text = T("sourceExtract", info.version, info.reasonText)
  else
    info.text = T("sourceExtractNone", info.reasonText)
  end
  return info
end

local function loadData()
  if not S.test and not OpenQuests.ALLOW_RETAIL and OpenQuests.retailClient() then return fail("RETAIL") end
  if not OpenQuests.retailClient() then startLive() end
  if S.data then return true end
  if adopt() then return loaded() end
  if inCombat() then return fail("COMBAT") end
  if not loggedIn() then return fail("NOT_LOGGED_IN") end
  if S.nextTry and now() < S.nextTry then return false end
  local api = type(C_AddOns) == "table" and C_AddOns.LoadAddOn or nil
  if type(api) ~= "function" then api = type(LoadAddOn) == "function" and LoadAddOn or nil end
  if not api then return fail("NO_API", true) end
  S.tried = true
  S.loadCalls = S.loadCalls + 1
  local ok, isLoaded, reason = pcall(api, OpenQuests.ADDON)
  if not ok then return fail("ERROR", true) end
  if adopt() then return loaded() end
  if isSecret(isLoaded) or not isLoaded then return fail(cleanReason(reason) or "UNKNOWN", true) end
  return fail("NO_DATA", true)
end

function OpenQuests.available()
  local R = retailSource()
  if R then return R.available() end
  if not S.data or not S.live then loadData() end -- loadData also starts the live source once
  return S.data ~= nil
end

function OpenQuests.retry()
  if not S.data then
    S.nextTry = nil
    loadData()
  end
  return S.data ~= nil
end

local REASON_KEYS = { DISABLED = true, DEP_DISABLED = true, MISSING = true, DEP_MISSING = true, INTERFACE_VERSION = true,
  INCOMPATIBLE = true, CORRUPT = true, BANNED = true, INSECURE = true, NOT_DEMAND_LOADED = true, COMBAT = true,
  NOT_LOGGED_IN = true, NO_API = true, NO_DATA = true, ERROR = true, UNKNOWN = true, RETAIL = true, NO_QUESTLINE = true }
OpenQuests.REASONS = setmetatable({}, { __index = function(_, k)
  if type(k) == "string" and REASON_KEYS[k] then return T[k] end
end })

function OpenQuests.reasonText(reason)
  if type(reason) ~= "string" then return T.notTried end
  local t = OpenQuests.REASONS[reason]
  if t then return t end
  if find(reason, "^DEP_") then return T("depMissing", reason) end
  return reason
end

function OpenQuests.status()
  local d = S.data
  return { loaded = d ~= nil, reason = S.reason, tried = S.tried, quests = d and d.nQuests or 0, givers = d and d.nGivers or 0,
    version = d and d.version or nil, factions = d and d.factions or nil, test = S.test ~= nil,
    source = (d and d.live) and "questiedb" or "extract" }
end

function OpenQuests.diagLine()
  local R = retailSource()
  if R then return R.diagLine() end
  local d = S.data
  local line
  if d then
    line = T("diagLoaded", d.nQuests, d.nGivers, d.version and T("diagVersion", d.version) or "")
  else
    line = T("diagNotLoaded", OpenQuests.reasonText(S.reason))
  end
  if S.test then line = line .. " · " .. T.testLabel end
  return line
end

-- The one source line of /chronik diag: "QuestieDB installed: x.y.z (Contract n) · Source: live" or
-- "… · Source: bundled extract x.y.z (reason)". Version/contract come ONLY from the TOC metadata of the separate add-on
-- QuestieDB (OpenQuestsQDB.version/contract, in pcall); never any data rows, never in Retail (nil -> no line). The values end
-- up in the chat window, so only plain version characters pass (else "?").
function OpenQuests.qdbDiagLine()
  if OpenQuests.retailClient() then return nil end
  local Q = qdb()
  if not Q or type(Q.version) ~= "function" or not Q.metaAvailable() then return nil end
  local okV, version, bad = pcall(Q.version)
  if not okV then version, bad = nil, nil end
  local okC, contract, badC = pcall(Q.contract)
  if not okC then contract, badC = nil, nil end
  local source = OpenQuests.sourceInfo().text
  if not version and not bad then return T("diagQdbNone", source) end
  return T("diagQdb", version or T.diagQdbUnknown, contract or T.diagQdbUnknown, source)
end

function OpenQuests.footer()
  local R = retailSource()
  if R then return R.footer() end
  local d = S.data
  if d and d.live then return d.version and T("footerLive", d.version) or T.footerLiveNoVersion end
  if d and d.version then return T("footer", d.version) end
  return T.footerNoVersion
end

local RACE_BIT = { Human = 1, Orc = 2, Dwarf = 4, NightElf = 8, Scourge = 16, Tauren = 32, Gnome = 64, Troll = 128 }
local CLASS_BIT = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 }
local ALL_ALLIANCE, ALL_HORDE = 77, 178 -- 1+4+8+64 | 2+16+32+128
OpenQuests.RACE_BIT, OpenQuests.CLASS_BIT = RACE_BIT, CLASS_BIT

local function hasBit(mask, bit)
  return floor((mask % (bit * 2)) / bit) == 1
end

local function anyBit(mask, set)
  for b = 0, 10 do
    local bit = 2 ^ b
    if hasBit(set, bit) and hasBit(mask, bit) then return true end
  end
  return false
end

-- identifier (race/class) as a short token or nil (secret, wrong type, special characters)
local function token(v)
  if isSecret(v) or type(v) ~= "string" then return nil end
  return match(v, "^[%a_]+$") and sub(v, 1, 40) or nil
end

-- faction: test mode and classic races from the race, else UnitFactionGroup (Skyborne etc.)
local function factionOf(raceBit)
  if raceBit then return hasBit(ALL_ALLIANCE, raceBit) and "Alliance" or "Horde" end
  if S.test then return nil end
  local name = call(UnitFactionGroup, "player")
  if name == "Alliance" or name == "Horde" then return name end
  return nil
end

local function playerLevel()
  local lv = num(call(UnitLevel, "player"))
  if lv and S.levelHint and lv >= S.levelHint then S.levelHint = nil end -- the client has caught up
  if lv and S.levelHint and S.levelHint > lv then lv = S.levelHint end
  return lv and floor(lv) or S.levelHint or 1
end

-- profile of the player (or the test profile)
local function profile()
  local p = {}
  if S.test then
    p.race, p.class = S.test.race, S.test.class
    p.level = S.test.level or playerLevel()
  else
    local _, raceToken = call(UnitRace, "player")
    local _, classToken = call(UnitClass, "player")
    p.race, p.class = token(raceToken), token(classToken)
    p.level = playerLevel()
  end
  p.raceBit = p.race and RACE_BIT[p.race] or nil
  p.classBit = p.class and CLASS_BIT[p.class] or nil
  p.faction = factionOf(p.raceBit)
  p.test = S.test ~= nil
  return p
end

local function profileKey(p)
  return table.concat({ tostring(p.race), tostring(p.class), tostring(p.level), tostring(p.faction), p.test and "T" or "-" }, "|")
end

-- Chronik log: set of turned-in quests (QT lines) and whether the state is complete (index finished and current).
-- Without a finished index (e.g. right after login)
-- the evaluation is not kept but recomputed on the next call or Index.onReady. OpenQuests.chronikProvider replaces the
-- query (tests; returns set[, complete = true]).
local function chronikDone()
  local set = {}
  if type(OpenQuests.chronikProvider) == "function" then
    local ok, r, complete = pcall(OpenQuests.chronikProvider)
    if ok and type(r) == "table" then
      for k, v in pairs(r) do
        if type(k) == "number" and v then set[k] = true elseif type(v) == "number" then set[v] = true end
      end
    end
    return set, complete ~= false
  end
  local I = Journal.Index
  if not (I and I.get and I.list and I.num) then return set, true end
  local ok, index = pcall(I.get, { noRebuild = true })
  if not ok or type(index) ~= "table" then return set, false end
  local complete = index.stale ~= true
  local ok2, recs = pcall(I.list, index, "QT")
  if not ok2 or type(recs) ~= "table" then return set, false end
  for _, rec in ipairs(recs) do
    local id = I.num(rec, "QT", "questID")
    if id then set[floor(id)] = true end
  end
  return set, complete
end

-- IsQuestFlaggedCompleted: only a real true counts; secret/error/nil = not done; asked once per state
local function flagged(id)
  local c = S.flag[id]
  if c ~= nil then return c end
  local v = false
  local api = type(C_QuestLog) == "table" and C_QuestLog.IsQuestFlaggedCompleted or nil
  if type(api) == "function" then
    local ok, r = pcall(api, id)
    v = ok and not isSecret(r) and r == true
  end
  S.flag[id] = v
  return v
end

-- quests in the quest log (set); empty in test mode (the retail client's IDs are meaningless)
local function questLogSet()
  local set = {}
  if S.test then return set end
  local C = type(C_QuestLog) == "table" and C_QuestLog or nil
  if not C then return set end
  local n = num(call(C.GetNumQuestLogEntries))
  if not n or type(C.GetInfo) ~= "function" then return set end
  for i = 1, min(floor(n), 400) do
    local ok, info = pcall(C.GetInfo, i)
    if ok and type(info) == "table" and not isSecret(info) and not info.isHeader then
      local qid = num(info.questID)
      if qid and qid > 0 then set[floor(qid)] = true end
    end
  end
  return set
end

local function mapSpace() return Journal.MapSpace end

-- map space: retail client always "retail"; Forever "data"; unknown client (tests without WOW_PROJECT_ID): test mode = "retail"
local function space()
  local M = mapSpace()
  local c = M and M.client and M.client() or nil
  if c then return c end
  return S.test and "retail" or "data"
end
OpenQuests.space = space

-- maps of a giver in map space sp: { { mapID, points }, ... } (points converted, collected per target map) and whether
-- points without a counterpart were dropped;
-- computed once per giver and space
local function clientMaps(g, sp)
  if sp ~= "retail" then return g.maps, false end
  g.cm = g.cm or {}
  local c = g.cm[sp]
  if c then return c.maps, c.lost end
  local M = mapSpace()
  local maps, byID, lost = {}, {}, false
  for _, m in ipairs(g.maps) do
    for _, pt in ipairs(m.points) do
      local oid, x, y
      if M and M.toClient then oid, x, y = M.toClient(m.mapID, pt[1], pt[2], sp) end
      if oid then
        local e = byID[oid]
        if not e then
          e = { mapID = oid, points = {} }
          byID[oid] = e
          maps[#maps + 1] = e
        end
        e.points[#e.points + 1] = { x, y }
      else
        lost = true
      end
    end
  end
  g.cm[sp] = { maps = maps, lost = lost }
  return maps, lost
end

-- data map -> map in the client's map space (nil = no counterpart)
local function mapOut(fid)
  local M = mapSpace()
  if not (M and M.mapToClient) then return fid end
  return M.mapToClient(fid, space())
end

-- client map -> data map (nil = no counterpart)
local function mapIn(oid)
  local M = mapSpace()
  if not (M and M.fromClient) then return oid end
  return M.fromClient(oid, space())
end

-- stored map ID into the client's map space: already there -> unchanged; else mapped as a data map; else nil
function OpenQuests.clientZone(id)
  id = num(id)
  if not id then return nil end
  id = floor(id)
  if retailSource() then return id end -- world map source: every retail uiMapID is its own
  if mapIn(id) then return id end
  local M = mapSpace()
  return M and M.mapToClient and M.mapToClient(id, space()) or nil
end

-- map name: client (C_Map.GetMapInfo), else the fixed name from MapSpace (deDE/enUS), else "Karte <id>"
function OpenQuests.mapName(mapID)
  mapID = num(mapID)
  if not mapID then return nil end
  mapID = floor(mapID)
  local info = type(C_Map) == "table" and call(C_Map.GetMapInfo, mapID) or nil
  local name = type(info) == "table" and not isSecret(info) and info.name or nil
  local d = type(name) == "string" and not isSecret(name) and display(name) or nil
  if not d then
    local M = mapSpace()
    local fixed = M and M.name and M.name(mapID) or nil
    d = fixed and display(fixed) or nil
  end
  return d or T("mapFallback", mapID)
end

local function raceCheck(mask, p)
  if mask == 0 then return true end
  local classic = mask % 256
  if p.raceBit then
    if classic ~= 0 and hasBit(classic, p.raceBit) then return true end
    -- reason: does the quest belong to the other faction?
    if classic ~= 0 then
      local own = hasBit(ALL_ALLIANCE, p.raceBit) and ALL_ALLIANCE or ALL_HORDE
      if not anyBit(classic, own) then return false, "faction" end
    end
    return false, "race"
  end
  -- race without a classic bit (Skyborne etc.): meaning of the upper bits unknown -> via the faction, with a note
  if classic == 0 then return true, nil, true end
  if p.faction == "Alliance" then
    if anyBit(classic, ALL_ALLIANCE) then return true, nil, true end
    return false, "faction"
  elseif p.faction == "Horde" then
    if anyBit(classic, ALL_HORDE) then return true, nil, true end
    return false, "faction"
  end
  return true, nil, true
end

local function classCheck(mask, p)
  if mask == 0 then return true end
  local low = mask % 4294967296
  local classic = low % 2048
  if classic == 0 then return false end -- non-classic classes only
  if p.classBit then return hasBit(classic, p.classBit) end
  return false -- class without a classic bit: only quests without a class restriction
end

-- client lookups only where the IDs mean something: Forever client (data map space), no test mode
local function clientNames()
  return not S.test and space() == "data"
end

-- quest title from the client cache (its language; nil = not cached). Quests without a German name in a German client
-- are requested (QUEST_DATA_LOAD_RESULT -> names refreshed), at most OpenQuests.NAME_REQUESTS per evaluation.
local function clientTitle(q)
  local C = type(C_QuestLog) == "table" and C_QuestLog or nil
  if not C then return nil end
  local t = call(C.GetTitleForQuestID, q.id)
  if type(t) == "string" and t ~= "" then return t end
  if q.noDE and not q.requested and type(C.RequestLoadQuestByID) == "function" then
    S.requests = S.requests or { gen = -1, n = 0 }
    if S.requests.gen ~= S.gen then S.requests.gen, S.requests.n = S.gen, 0 end
    if S.requests.n < OpenQuests.NAME_REQUESTS then
      S.requests.n = S.requests.n + 1
      q.requested = true
      S.pending = S.pending or {}
      S.pending[q.id] = q
      call(C.RequestLoadQuestByID, q.id)
    end
  end
  return nil
end

local function nameOf(data, id)
  local q = data.quests[id]
  if q then
    if not q.dname then
      local client = clientNames() and clientTitle(q) or nil
      q.dname = display(client or q.name) or T("questFallback", id)
    end
    return q.dname
  end
  return T("questFallback", id)
end

-- NPC name from the client (tooltip data of the creature link), only for givers without a German name in a German client
local function clientNpcName(g)
  if not (g.noDE and g.kind == "npc" and clientNames()) then return nil end
  if (g.tries or 0) >= OpenQuests.NPC_TRIES then return nil end
  g.tries = (g.tries or 0) + 1
  local CTI = type(C_TooltipInfo) == "table" and C_TooltipInfo or nil
  if not (CTI and type(CTI.GetHyperlink) == "function") then
    g.tries = OpenQuests.NPC_TRIES
    return nil
  end
  local data = call(CTI.GetHyperlink, "unit:Creature-0-0-0-0-" .. floor(g.id) .. "-0000000000")
  local line = type(data) == "table" and type(data.lines) == "table" and data.lines[1] or nil
  local text = type(line) == "table" and line.leftText or nil
  if isSecret(text) or type(text) ~= "string" or text == "" then return nil end
  g.tries = OpenQuests.NPC_TRIES
  return text
end

local function giverName(g)
  if not g.dname then
    local client = clientNpcName(g)
    if client then
      g.dname = display(client) or "?"
    elseif g.noDE and g.kind == "npc" and clientNames() and (g.tries or 0) < OpenQuests.NPC_TRIES then
      return display(g.name) or "?" -- not cached yet: ask again next time
    else
      g.dname = display(g.name) or "?"
    end
  end
  return g.dname
end

local function joinNames(data, ids, limit, sep)
  local parts = {}
  for i = 1, min(#ids, limit) do parts[i] = nameOf(data, ids[i]) end
  return table.concat(parts, sep)
end

local function isUnsure(q)
  if q.flags.u then return true end
  local th = OpenQuests.UNSURE_LEVEL
  if q.minLevel > 0 then return q.minLevel > th end
  return (q.level or 0) > th
end

-- does the giver apply to this faction? (suffix A/H; unknown faction = all)
local function giverFits(g, faction)
  return g.faction == nil or faction == nil or g.faction == faction
end

-- static index per faction and map space: maps per quest (maps = Forever IDs, cmaps = client maps);
-- quests without a fitting giver with a map point are missing (never in the open list)
local function buildIndex(faction, sp)
  local fkey = (faction or "-") .. "|" .. sp
  S.index = S.index or {}
  if S.index[fkey] then return S.index[fkey] end
  local d = S.data
  local idx = { maps = {}, cmaps = {}, quests = {}, space = sp }
  local n = 0
  for id, q in pairs(d.quests) do
    local maps, seen, cmaps, cseen = {}, {}, {}, {}
    for _, key in ipairs(q.givers or EMPTY) do
      local g = d.givers[key]
      if g and giverFits(g, faction) then
        for _, m in ipairs(g.maps) do
          if not seen[m.mapID] then
            seen[m.mapID] = true
            maps[#maps + 1] = m.mapID
          end
        end
        for _, m in ipairs((clientMaps(g, sp))) do
          if not cseen[m.mapID] then
            cseen[m.mapID] = true
            cmaps[#cmaps + 1] = m.mapID
          end
        end
      end
    end
    if #maps > 0 then
      sort(maps)
      sort(cmaps)
      idx.maps[id] = maps
      idx.cmaps[id] = cmaps
      n = n + 1
      idx.quests[n] = q
    end
  end
  sort(idx.quests, function(a, b) return a.id < b.id end)
  S.index[fkey] = idx
  return idx
end

-- evaluation of all quests; result per quest: { q, state = "open"|"locked"|"foreign", reasons, notes, raceUnsure }
local function evaluate()
  local p = profile()
  local sp = space()
  local key = profileKey(p) .. "|" .. sp
  local ev = S.eval
  if ev and ev.gen == S.gen and ev.key == key and not ev.partial then return ev end
  local d = S.data
  local idx = buildIndex(p.faction, sp)
  S.flag = {}
  S.evalCount = S.evalCount + 1
  local chronik, complete = chronikDone()
  local testDone = S.test and S.test.doneSet or nil
  local inLog = questLogSet()
  local function done(id)
    if chronik[id] or S.turned[id] then return true end
    if testDone and testDone[id] then return true end
    if S.test then return false end
    return flagged(id)
  end
  local items = {}
  for _, q in ipairs(idx.quests) do
    local id = q.id
    if not done(id) and not inLog[id] then
      local reasons, notes
      local state = "open"
      local okR, whyR, unsureR = raceCheck(q.races, p)
      if not okR then
        state = "foreign"
        reasons = { { kind = whyR or "race", text = whyR == "faction" and T.foreignFaction or T.foreignRace } }
      elseif not classCheck(q.classes, p) then
        state = "foreign"
        reasons = { { kind = "class", text = T.foreignClass } }
      else
        reasons = {}
        if q.minLevel > 0 and q.minLevel > p.level then
          reasons[#reasons + 1] = { kind = "level", need = q.minLevel, text = T("level", q.minLevel) }
        end
        if q.preAll then
          local missing = {}
          for _, pid in ipairs(q.preAll) do
            if not done(pid) then missing[#missing + 1] = pid end
          end
          if #missing > 0 then
            local text
            if #missing == 1 then
              text = T("prequest", nameOf(d, missing[1]))
            else
              text = T("prequestMore", nameOf(d, missing[1]), #missing - 1)
            end
            reasons[#reasons + 1] = { kind = "prequest", ids = missing, text = text }
          end
        end
        if q.preAny then
          local any = false
          for _, pid in ipairs(q.preAny) do
            if done(pid) then any = true break end
          end
          if not any then
            local text = T("prequestAny", joinNames(d, q.preAny, 3, " / ") .. (#q.preAny > 3 and " …" or ""))
            reasons[#reasons + 1] = { kind = "prequest", ids = q.preAny, text = text }
          end
        end
        if q.excl then
          for _, xid in ipairs(q.excl) do
            if done(xid) or inLog[xid] then
              reasons[#reasons + 1] = { kind = "exclusive", ids = { xid }, text = T("exclusive", nameOf(d, xid)) }
              break
            end
          end
        end
        if #reasons > 0 then state = "locked" end
        if q.flags.s then
          notes = notes or {}
          notes[#notes + 1] = T.notChecked
        end
        if unsureR then
          notes = notes or {}
          notes[#notes + 1] = T.raceUnsure
        end
      end
      items[#items + 1] = { q = q, state = state, reasons = reasons, notes = notes }
    end
  end
  ev = { gen = S.gen, key = key, items = items, profile = p, idx = idx, partial = not complete or nil }
  S.eval = ev
  return ev
end

-- special-kind filter: nil = visible, else the name of the hiding kind
local KIND_FLAGS = { { "g", "group" }, { "r", "repeatable" }, { "k", "category" } }
local function blockedBy(q, kinds)
  for _, kf in ipairs(KIND_FLAGS) do
    -- category quest with a class restriction = class quest (own switch), else profession/other category
    if kf[1] == "k" and q.flags.k and q.classes ~= 0 then
      if not (kinds and kinds.class == true) then return "class" end
    elseif q.flags[kf[1]] and not (kinds and kinds[kf[2]] == true) then
      return kf[2]
    end
  end
  return nil
end

-- key of a query (result cache per evaluation)
local function kindsKey(scope, opts)
  local k = opts.kinds or EMPTY
  return table.concat({ tostring(scope), opts.locked == true and "L" or "-", opts.foreign == true and "F" or "-",
    k.group == true and "g" or "-", k.repeatable == true and "r" or "-", k.class == true and "c" or "-", k.category == true and "k" or "-" }, "|")
end

local function cleanOpts(opts)
  if type(opts) ~= "table" or isSecret(opts) then return EMPTY end
  return opts
end

-- output givers of a quest in map space sp: with onlyMap only this map (client map), else all; unmapped = points
-- without a counterpart
-- in the client's map space were dropped (reported only without onlyMap)
local function giverOut(d, q, onlyMap, faction, sp)
  local out = {}
  local unmapped = false
  for _, key in ipairs(q.givers or EMPTY) do
    local g = d.givers[key]
    if g and giverFits(g, faction) then
      local gname = giverName(g)
      local maps, lost = clientMaps(g, sp)
      if lost and onlyMap == nil then unmapped = true end
      for _, m in ipairs(maps) do
        if onlyMap == nil or m.mapID == onlyMap then
          local pts = {}
          for i, pt in ipairs(m.points) do pts[i] = { pt[1], pt[2] } end
          out[#out + 1] = { key = key, kind = g.kind, id = g.id, name = gname, mapID = m.mapID, points = pts }
        end
      end
    end
  end
  sort(out, function(a, b)
    if a.mapID ~= b.mapID then return a.mapID < b.mapID end
    return a.key < b.key
  end)
  return out, unmapped
end

local function flagsOut(q)
  local f = {}
  for k in pairs(q.flags) do f[k] = true end
  if isUnsure(q) then f.u = true end
  return f
end

local function sortOpen(a, b)
  local la, lb = a.level or 999, b.level or 999
  if la ~= lb then return la < lb end
  local na, nb = lower(a.name), lower(b.name)
  if na ~= nb then return na < nb end
  return a.id < b.id
end

local function sortLocked(a, b)
  if a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end
  return sortOpen(a, b)
end

local function emptyResult(scope, mapID, extra)
  local r = { scope = scope, mapID = mapID, open = {}, locked = {}, openCount = 0, lockedCount = 0,
    hidden = { group = 0, repeatable = 0, class = 0, category = 0, total = 0 }, foreign = 0, noLocation = 0, test = S.test ~= nil }
  if extra then for k, v in pairs(extra) do r[k] = v end end
  return r
end

function OpenQuests.list(scope, opts)
  local R = retailSource()
  if R then return R.list(scope, cleanOpts(opts)) end
  opts = cleanOpts(opts)
  local mapID
  if scope ~= "all" then
    scope = num(scope)
    if not scope then return emptyResult("all", nil, { invalid = true }) end
    scope = floor(scope)
    mapID = scope
  end
  if not OpenQuests.available() then
    return emptyResult(scope, mapID, { unavailable = true, reason = S.reason })
  end
  -- map in the client's map space without a data map behind it (retail: e.g. a Forever ID): nothing to show
  if mapID and not mapIn(mapID) then return emptyResult(scope, mapID, { unmapped = true }) end
  local d = S.data
  local ev = evaluate()
  -- result kept per state and query (same table; do not modify): the UI can tie selection and pins to the quests
  local ckey = kindsKey(scope, opts)
  ev.cache = ev.cache or {}
  if ev.cache[ckey] then return ev.cache[ckey] end
  local res = emptyResult(scope, mapID)
  ev.cache[ckey] = res
  for _, it in ipairs(ev.items) do
    local q = it.q
    local maps = ev.idx.maps[q.id]
    local inScope = true
    if mapID then
      inScope = false
      for _, m in ipairs(ev.idx.cmaps[q.id]) do
        if m == mapID then inScope = true break end
      end
    end
    if inScope then
      if it.state == "foreign" then
        if opts.foreign == true then
          it = { q = q, state = "locked", reasons = it.reasons, notes = it.notes } -- locked with reason (race/class/faction)
        else
          res.foreign = res.foreign + 1
          it = nil
        end
      end
      if it then
        local blocked = blockedBy(q, opts.kinds)
        if blocked then
          res.hidden[blocked] = res.hidden[blocked] + 1
          res.hidden.total = res.hidden.total + 1
        else
          local givers, unmapped = giverOut(d, q, mapID, ev.profile.faction, ev.idx.space)
          local noLoc = #maps == 0 or (#givers == 0 and not mapID)
          local out = {
            id = q.id, name = nameOf(d, q.id), level = q.level, minLevel = q.minLevel, unsure = isUnsure(q), flags = flagsOut(q),
            state = it.state, givers = givers, noLocation = noLoc, reasons = it.state == "locked" and it.reasons or {}, notes = it.notes or {},
          }
          if unmapped then out.unmapped = true end
          if noLoc then res.noLocation = res.noLocation + 1 end
          if it.state == "open" then
            res.openCount = res.openCount + 1
            res.open[#res.open + 1] = out
          else
            res.lockedCount = res.lockedCount + 1
            if opts.locked == true then res.locked[#res.locked + 1] = out end
          end
        end
      end
    end
  end
  sort(res.open, sortOpen)
  sort(res.locked, sortLocked)
  return res
end

function OpenQuests.zones(opts)
  local R = retailSource()
  if R then return R.zones(cleanOpts(opts)) end
  opts = cleanOpts(opts)
  local out = { total = { open = 0, locked = 0 }, zones = {} }
  if not OpenQuests.available() then
    out.unavailable, out.reason = true, S.reason
    return out
  end
  local ev = evaluate()
  -- like list: kept per evaluation state and query (same table; do not modify)
  local zkey = "zones|" .. kindsKey("z", opts)
  ev.cache = ev.cache or {}
  if ev.cache[zkey] then return ev.cache[zkey] end
  ev.cache[zkey] = out
  local per = {}
  for _, it in ipairs(ev.items) do
    local q = it.q
    local st = it.state
    if st == "foreign" and opts.foreign == true then st = "locked" end
    if st ~= "foreign" and not blockedBy(q, opts.kinds) then
      local field = st == "open" and "open" or "locked"
      out.total[field] = out.total[field] + 1
      for _, oid in ipairs(ev.idx.cmaps[q.id]) do
        local z = per[oid]
        if not z then
          z = { mapID = oid, open = 0, locked = 0 }
          per[oid] = z
        end
        z[field] = z[field] + 1
      end
    end
  end
  for _, z in pairs(per) do
    if z.open > 0 or (opts.locked == true and z.locked > 0) then
      z.name = OpenQuests.mapName(z.mapID)
      out.zones[#out.zones + 1] = z
    end
  end
  sort(out.zones, function(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.mapID < b.mapID
  end)
  return out
end

local function cluster(items, radius)
  local cl = {}
  local r2 = radius * radius
  for _, it in ipairs(items) do
    local best, bd
    for _, c in ipairs(cl) do
      local dx, dy = c.x - it.x, c.y - it.y
      local dd = dx * dx + dy * dy
      if dd <= r2 and (not bd or dd < bd) then best, bd = c, dd end
    end
    if best then
      best.n = best.n + 1
      best.sx, best.sy = best.sx + it.x, best.sy + it.y
      best.x, best.y = best.sx / best.n, best.sy / best.n
      best.items[#best.items + 1] = it
    else
      cl[#cl + 1] = { x = it.x, y = it.y, sx = it.x, sy = it.y, n = 1, items = { it } }
    end
  end
  return cl
end

function OpenQuests.pins(result, opts)
  opts = cleanOpts(opts)
  local out = { pins = {}, count = 0, truncated = false }
  if type(result) ~= "table" or not result.mapID then return out end
  local limit = num(opts.maxPins)
  limit = limit and max(1, floor(limit)) or OpenQuests.MAX_PINS
  local radius = num(opts.radius)
  radius = (radius and radius > 0) and radius or OpenQuests.RADIUS
  local items = {}
  local function collect(list)
    for _, q in ipairs(list) do
      for _, g in ipairs(q.givers) do
        if g.mapID == result.mapID then
          for _, pt in ipairs(g.points) do items[#items + 1] = { x = pt[1], y = pt[2], q = q, g = g } end
        end
      end
    end
  end
  collect(result.open)
  collect(result.locked)
  sort(items, function(a, b)
    if a.x ~= b.x then return a.x < b.x end
    if a.y ~= b.y then return a.y < b.y end
    if a.g.key ~= b.g.key then return a.g.key < b.g.key end
    return a.q.id < b.q.id
  end)
  local cl = cluster(items, radius)
  local tries = 0
  while #cl > limit and tries < 8 do
    radius = radius * 1.6
    cl = cluster(items, radius)
    tries = tries + 1
  end
  if #cl > limit then
    out.truncated = true
    sort(cl, function(a, b) return a.n > b.n end)
    for i = #cl, limit + 1, -1 do cl[i] = nil end
  end
  sort(cl, function(a, b)
    if a.x ~= b.x then return a.x < b.x end
    return a.y < b.y
  end)
  for _, c in ipairs(cl) do
    local seen, quests, names, nameSeen = {}, {}, {}, {}
    local open, locked = 0, 0
    for _, it in ipairs(c.items) do
      if not seen[it.q.id] then
        seen[it.q.id] = true
        quests[#quests + 1] = it.q
        if it.q.state == "open" then open = open + 1 else locked = locked + 1 end
      end
      if not nameSeen[it.g.key] then
        nameSeen[it.g.key] = true
        names[#names + 1] = it.g.name
      end
    end
    sort(quests, function(a, b)
      if a.state ~= b.state then return a.state == "open" end
      return sortOpen(a, b)
    end)
    sort(names)
    out.pins[#out.pins + 1] = { mapID = result.mapID, x = c.x, y = c.y, count = #quests, open = open, locked = locked,
      grey = open == 0, quests = quests, givers = names }
  end
  out.count = #out.pins
  return out
end

function OpenQuests.tooltipLines(pin, maxLines)
  local lines = {}
  if type(pin) ~= "table" or type(pin.quests) ~= "table" then return lines end
  maxLines = num(maxLines)
  maxLines = maxLines and max(1, floor(maxLines)) or OpenQuests.TOOLTIP_LINES
  for i = 1, min(#pin.quests, maxLines) do
    local q = pin.quests[i]
    lines[#lines + 1] = "[" .. (q.level and tostring(q.level) or "?") .. "] " .. q.name
  end
  if #pin.quests > maxLines then lines[#lines + 1] = T("more", #pin.quests - maxLines) end
  return lines
end

-- fallback if the client returns no continent for a zone: fixed assignment from MapSpace (Forever and retail IDs)
local function fixedContinent(mid)
  local M = mapSpace()
  return M and M.continentOf and M.continentOf(mid) or nil
end

function OpenQuests.continents()
  local list = { { f = 1414, text = T.kalimdor }, { f = 1415, text = T.easternKingdoms } }
  local out = {}
  for _, c in ipairs(list) do
    local oid = mapOut(c.f)
    if oid then out[#out + 1] = { id = oid, name = c.text } end
  end
  return out
end

local function geo() return Journal.Geo end

function OpenQuests.zonePins(result, contID, opts)
  opts = cleanOpts(opts)
  local out = { pins = {}, unplaced = 0 }
  if type(result) ~= "table" then return out end
  contID = num(contID)
  local perMap = {}
  local function add(list, field)
    for _, q in ipairs(list) do
      local seenMap = {}
      for _, g in ipairs(q.givers) do
        local z = perMap[g.mapID]
        if not z then
          z = { mapID = g.mapID, open = 0, locked = 0, sx = 0, sy = 0, n = 0 }
          perMap[g.mapID] = z
        end
        if not seenMap[g.mapID] then
          seenMap[g.mapID] = true
          z[field] = z[field] + 1
        end
        for _, pt in ipairs(g.points) do
          z.sx, z.sy, z.n = z.sx + pt[1], z.sy + pt[2], z.n + 1
        end
      end
    end
  end
  add(result.open or EMPTY, "open")
  add(result.locked or EMPTY, "locked")
  local G = geo()
  local project = contID and G and G.projector and select(1, G.projector(contID)) or nil
  local ids = {}
  for mid in pairs(perMap) do ids[#ids + 1] = mid end
  sort(ids)
  for _, mid in ipairs(ids) do
    local z = perMap[mid]
    local include = true
    if contID then
      local cont = G and G.continentOf and num(call(G.continentOf, mid)) or nil
      if not cont then cont = fixedContinent(mid) end
      include = cont == contID
    end
    if include then
      local x, y
      if contID and z.n > 0 then
        -- one pin per zone at its centre on the continent (cities included: they are zones of their own); only without a
        -- rect the projected centre of its givers
        if G and G.rect then
          local a, b, c, d = G.rect(mid, contID)
          a, b, c, d = num(a), num(b), num(c), num(d)
          if a and b and c and d then x, y = (a + b) / 2, (c + d) / 2 end
        end
        if not x and project then x, y = project(mid, z.sx / z.n, z.sy / z.n) end
      elseif not contID and z.n > 0 then
        x, y = z.sx / z.n, z.sy / z.n
      end
      if x and y then
        out.pins[#out.pins + 1] = { mapID = mid, name = OpenQuests.mapName(mid), x = x, y = y, count = z.open + z.locked, open = z.open,
          locked = z.locked, grey = z.open == 0 }
      else
        out.unplaced = out.unplaced + 1
      end
    end
  end
  return out
end

-- all exploration overlays of a client map (uncovered map) in the shape of GetExploredMapTextures, or nil: Forever uses
-- the data's map IDs, the retail client the retail overlay table (retail IDs); nothing known = the client's explored ones
function OpenQuests.overlays(mapID)
  mapID = num(mapID)
  local d = S.data
  if not (mapID and d) then return nil end
  local list = space() == "retail" and d.overlaysRetail or d.overlays
  return list and list[floor(mapID)] or nil
end

-- names changed (client cache answered): callback of the view
function OpenQuests.onNames(fn)
  S.onNames = type(fn) == "function" and fn or nil
end

-- new content for the view (names arrived, retail world map answered): one redraw after 0.5 s
local function changed()
  if S.namesQueued or not S.onNames then return end
  S.namesQueued = true
  local function fire()
    S.namesQueued = nil
    if S.onNames then pcall(S.onNames) end
  end
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    local ok = pcall(C_Timer.After, 0.5, fire)
    if ok then return end
  end
  fire()
end
OpenQuests._changed = changed

local function namesArrived(id)
  local q = S.pending and S.pending[id]
  if not q then return end
  S.pending[id] = nil
  q.dname = nil
  S.eval = nil
  changed()
end
OpenQuests._namesArrived = namesArrived

function OpenQuests.addTodo(q, opts)
  opts = cleanOpts(opts)
  if type(q) ~= "table" or isSecret(q) then return nil, "kein-ort" end
  local mapID, x, y
  if opts.mapID then
    mapID, x, y = num(opts.mapID), num(opts.x), num(opts.y)
  else
    local g = opts.giver
    if type(g) ~= "table" then
      for _, cand in ipairs(q.givers or EMPTY) do
        if cand.points and cand.points[1] then g = cand break end
      end
    end
    if type(g) == "table" and g.points and g.points[1] then mapID, x, y = num(g.mapID), num(g.points[1][1]), num(g.points[1][2]) end
  end
  if not (mapID and x and y) then return nil, "kein-ort" end
  local Plans = ns.Plans
  if not (Plans and type(Plans.add) == "function") then return nil, "kein-plan" end
  local name = type(q.name) == "string" and q.name or T("questFallback", q.id or 0)
  local ok, id, why = pcall(Plans.add, { kind = "place", mapID = mapID, x = x, y = y, text = T("todoText", name) })
  if not ok then return nil, "kein-plan" end
  return id, why
end

function OpenQuests.test()
  return S.test
end

function OpenQuests.setTest(on, prof)
  if not on then
    S.test = nil
  else
    prof = type(prof) == "table" and prof or {}
    local lv = num(prof.level)
    local t = { race = token(prof.race) or (S.test and S.test.race) or "Scourge",
      class = token(prof.class) and string.upper(token(prof.class)) or (S.test and S.test.class) or "PALADIN",
      level = lv and max(1, min(floor(lv), 80)) or (S.test and S.test.level) or nil, doneSet = {}, done = {} }
    if type(prof.done) == "table" then
      for _, id in ipairs(prof.done) do
        id = num(id)
        if id then
          t.doneSet[floor(id)] = true
          t.done[#t.done + 1] = floor(id)
        end
      end
    end
    S.test = t
  end
  OpenQuests.invalidate()
  return S.test
end

function OpenQuests.testLabel()
  return S.test and T.testLabel or nil
end

local function say(msg)
  if ns.Core and ns.Core.print then ns.Core.print(msg) end
end

-- /chronik offene [test [aus|status|stufe N|volk TOKEN|klasse TOKEN]]
function OpenQuests.slash(rest)
  rest = type(rest) == "string" and rest or ""
  local sub1, arg1, arg2 = match(rest, "^%s*(%S*)%s*(%S*)%s*(%S*)")
  sub1 = lower(sub1 or "")
  if sub1 == "test" then
    arg1 = lower(arg1 or "")
    if arg1 == "aus" or arg1 == "off" then
      OpenQuests.setTest(false)
      say(T.testOff)
    elseif arg1 == "status" then
      local t = S.test
      if t then
        say(T("testOn", t.race, t.class, tostring(t.level or playerLevel()), T.testLabel))
      else
        say(T.testOff)
      end
    elseif arg1 == "stufe" or arg1 == "volk" or arg1 == "klasse" or arg1 == "level" or arg1 == "race" or arg1 == "class" then
      arg1 = ({ level = "stufe", race = "volk", class = "klasse" })[arg1] or arg1
      local t = S.test or OpenQuests.setTest(true)
      if arg1 == "stufe" then
        local lv = tonumber(arg2)
        if not lv then say(T.testLevelUsage) else OpenQuests.setTest(true, { level = lv, race = t.race, class = t.class, done = t.done }) end
      elseif arg1 == "volk" then
        local tk = token(arg2)
        if not tk or not RACE_BIT[tk] then say(T.testRaceUsage) else OpenQuests.setTest(true, { race = tk, class = t.class, level = t.level, done = t.done }) end
      else
        local tk = token(arg2)
        tk = tk and string.upper(tk) or nil
        if not tk or not CLASS_BIT[tk] then say(T.testClassUsage) else OpenQuests.setTest(true, { race = t.race, class = tk, level = t.level, done = t.done }) end
      end
      local t2 = S.test
      if t2 then say(T("testOn", t2.race, t2.class, tostring(t2.level or playerLevel()), T.testLabel)) end
    else
      OpenQuests.setTest(true)
      local t = S.test
      say(T("testOn", t.race, t.class, tostring(t.level or playerLevel()), T.testLabel))
    end
    if type(OpenQuests.openPage) == "function" then pcall(OpenQuests.openPage) end
    return
  end
  if type(OpenQuests.openPage) == "function" then
    local ok, opened = pcall(OpenQuests.openPage)
    if ok and opened then return end
  end
  OpenQuests.available()
  say(OpenQuests.diagLine())
end

function OpenQuests.invalidate()
  S.gen = S.gen + 1
  S.eval = nil
  S.flag = {}
end

function OpenQuests.onEvent(event, arg)
  if event == "QUEST_DATA_LOAD_RESULT" then
    local id = num(arg)
    if id then namesArrived(floor(id)) end
    return
  end
  if event == "QUEST_TURNED_IN" then
    local id = num(arg)
    if id and id > 0 then S.turned[floor(id)] = true end
  elseif event == "PLAYER_LEVEL_UP" then
    local lv = num(arg)
    if lv and lv > 0 then S.levelHint = floor(lv) end
  end
  local R = retailSource()
  if R and R.onEvent then R.onEvent(event, arg) end
  OpenQuests.invalidate()
end

-- index finished (Chronik log complete): discard a preliminary evaluation
if Journal.Index and type(Journal.Index.onReady) == "function" then
  pcall(Journal.Index.onReady, function()
    if S.eval and S.eval.partial then OpenQuests.invalidate() end
  end)
end

OpenQuests.EVENTS = { "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "QUEST_ACCEPTED", "QUEST_REMOVED",
  "QUEST_DATA_LOAD_RESULT" }
if ns.Core and ns.Core.on then
  for _, ev in ipairs(OpenQuests.EVENTS) do
    ns.Core.on(ev, function(event, a) OpenQuests.onEvent(event, a) end)
  end
end
