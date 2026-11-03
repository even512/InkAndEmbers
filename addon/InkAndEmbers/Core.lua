-- Namespace, event bus with pcall isolation, collector registry, slash command /chronik, diag.
local ADDON_NAME, ns = ...

ns.SCHEMA = 1

local Core = {}
ns.Core = Core

-- Add-on version from the TOC (the packager replaces '@project-version@'); an unreplaced placeholder (local install)
-- or anything unusable gives "dev". Only plain version characters pass, the value ends up in the log and the SV.
function Core.readVersion()
  local api = type(C_AddOns) == "table" and C_AddOns.GetAddOnMetadata or nil
  if type(api) ~= "function" then api = _G.GetAddOnMetadata end
  if type(api) ~= "function" then return "dev" end
  local ok, v = pcall(api, ADDON_NAME, "Version")
  if not ok or type(v) ~= "string" then return "dev" end
  v = string.match(v, "^%s*(.-)%s*$")
  if v == "" or #v > 40 or string.find(v, "@", 1, true) or not string.match(v, "^[%w%._%+%-]+$") then return "dev" end
  return v
end

ns.version = Core.readVersion()

local format, floor, concat = string.format, math.floor, table.concat

-- Texts (German here, English in locales/enUS_core.lua, section 'Core'; pattern: docs/i18n.md). Stored data
-- (diag notes, collector status) stays German and is not translated.
local T = ns.Locale.ns("Core", {
  prefix = "Chronik:",
  handlerOff = "Sammler \"%s\": die Aufzeichnung \"%s\" schlug wiederholt fehl und bleibt bis zum nächsten Neuladen aus. Details: /chronik diag",
  handlersPaused = "Pausierte Aufzeichnungen: %s",
  handlersOff = "Bis zum Neuladen abgeschaltete Aufzeichnungen: %s",
  moreCount = " (+%d weitere)",
  allRunning = "alle Aufzeichnungen laufen",
  someRunning = "%d von %d Aufzeichnungen laufen (Fehlersuche: /chronik diag)",
  waiting = "Die Chronik wartet noch auf Euren Charakter, %s.",
  dateFmt = "%d.%m.%Y %H:%M",
  justNow = "gerade eben",
  ago = "vor %s",
  minShort = "%d Min.",
  entry_one = "Eintrag",
  entry_other = "Einträge",
  status = "Die Chronik schreibt seit %s mit: %s %s, zuletzt gesichert %s, %s.",
  helpTitle = "Befehle:",
  helpToggle = "/chronik - Reisejournal öffnen/schließen (oder eine Taste unter Tastaturbelegung > AddOns > Ink & Embers legen)",
  helpStatus = "/chronik status - Status der Chronik",
  helpOptions = "/chronik optionen - Einstellungen öffnen (Optionen > AddOns > Ink & Embers)",
  helpMinimap = "/chronik minimap - Minimap-Knopf ein-/ausblenden (Rechtsklick auf den Knopf öffnet die Einstellungen)",
  helpToast = "/chronik toast - Einblendungen für neue Medaillen und Gebiete ein-/ausschalten (\"toast test\" zeigt Beispiele)",
  helpSound = "/chronik ton - Ton der Einblendungen ein-/ausschalten",
  helpWelcome = "/chronik willkommen - Begrüßungskarte als Vorschau zeigen",
  helpRest = "/chronik rast - Rückblick \"Seit der letzten Rast\" als Vorschau zeigen",
  helpMeter = "/chronik messer - Schadensanzeige automatisch einschalten: \"messer an\" oder \"messer aus\" (auch in den Einstellungen)",
  helpTodo = "/chronik todo - offene To Dos am Bildschirmrand ein-/ausblenden (\"todo reset\" setzt Lage und Größe zurück)",
  helpNote = "/chronik notiz - Schnellnotiz-Feld ein-/ausblenden (Enter legt eine Notiz an)",
  helpOpen = "/chronik offene - offene Quests (Rubrik \"Offen\" unter Quests); \"offene test\" schaltet den Retail-Testmodus ein (\"test aus\" beendet ihn)",
  helpTrain = "/chronik lehrplan - Lehrplan Eurer Klasse (Rubrik \"Lehrplan\" unter Quests, nur WoW Forever); \"lehrplan status\" zeigt den Stand",
  helpLanguage = "/chronik sprache - Sprache wählen: \"sprache auto\", \"sprache de\" oder \"sprache en\" (wirkt nach /reload)",
  helpReset = "/chronik reset - Größe und Position des Reisejournals zurücksetzen",
  helpSave = "/chronik sichern - Sichern-Fenster öffnen (Sichern lädt die Oberfläche neu)",
  helpBackup = "/chronik sicherung - Stand der Datensicherung: Sicherungskopie dieses Charakters, letztes Speichern, Füllstand der Datei",
  helpHelp = "/chronik hilfe - diese Befehlsliste",
  helpTutorial = "/chronik tutorial - Einführung (kleines Buch zum Durchblättern) erneut zeigen",
  helpDebug = "Fehlersuche:",
  helpDiag = "/chronik diag - Selbsttest aller Schnittstellen (Ergebnis in EveNChronicleDB.diag)",
  helpCampfire = "/chronik feuer - Lagerfeuer: Sitz-Aura, erkannte Mitspieler mit Quelle, Plaketten (\"feuer test\" zeigt die Testanzeige)",
  helpSim = "/chronik sim feuer - Lagerfeuer in Retail simulieren: an|aus|status|setzen|aufstehen|gast|laut|löschen",
  helpAuras = "/chronik auren - listet die aktuellen Buffs (spellID + Name), z.B. am Lagerfeuer abfragen",
  helpCoins = "/chronik muenzen - zeigt, welche Münzgrafik (Auflösung) im Buch genutzt wird",
  helpAliases = "",
  selfTest = "Selbsttest: %d von %d Schnittstellen vorhanden.",
  missing = "Fehlt: %s",
  expectedAbsent = "Auf diesem Client erwartungsgemäß nicht vorhanden: %s",
  collectorsActive = "Sammler aktiv %d/%d.",
  inactive = " Nicht aktiv: %s",
  checkFailed = "%s: Prüfung fehlgeschlagen (%s)",
  labHand = "Handschrift",
  labTodo = "To-Do-Liste",
  labOpenQuests = "Offene Quests",
  labMarks = "Namensplaketten-Markierung",
  labMeter = "Schadensmesser",
  labFire = "Lagerfeuer",
  labRound = "Lagerfeuer-Runde",
  labEditMode = "Bearbeitungsmodus",
  globalStringsMissing = "Texte (GlobalStrings) fehlen: %s",
  details = "Details stehen in EveNChronicleDB.diag (in der Datei nach dem nächsten Sichern).",
  optionsMissing = "Einstellungen: Reisejournal nicht geladen.",
  campfireMissing = "Lagerfeuer: Sammler nicht geladen.",
  simMissing = "Simulation: Sammler Lagerfeuer nicht geladen.",
  aurasMissing = "Auren: Sammler Rast nicht geladen.",
  coinsMissing = "Münzen: Reisejournal nicht geladen, keine Münzquelle gewählt.",
  tutorialMissing = "Einführung: Reisejournal nicht geladen.",
  helpDiagQuests = "/chronik diag retailquests [Karten-ID] - Quest-Schnittstellen des Spiels auf der aktuellen Karte prüfen (Ergebnis in EveNChronicleDB.diag.retailQuests)",
  rqCombat = "Quest-Schnittstellen: bitte außerhalb des Kampfs ausführen.",
  rqNoMap = "Quest-Schnittstellen: keine Karte bestimmbar (Karten-ID angeben, z. B. /chronik diag retailquests 37).",
  rqNoApi = "Quest-Schnittstellen: C_QuestLine fehlt auf diesem Client (Karte %d gespeichert).",
  rqAsked = "Quest-Schnittstellen: Karte %d angefragt, Auswertung in höchstens %d s …",
  rqResult = "Quest-Schnittstellen Karte %d (%s): %d Questreihen, %d Quests, %d erzwungen sichtbar, %d Bonusziele (%s).",
  rqViaEvent = "Antwort erhalten",
  rqViaTimeout = "ohne Antwort, nach Wartezeit",
  rqViaNow = "sofort",
  rqError = "Quest-Schnittstellen: Fehler bei der Auswertung (%s).",
  rqDetails = "Details in EveNChronicleDB.diag.retailQuests[%d] (in der Datei nach /reload).",
  unknownCommand = "Unbekannter Befehl \"%s\". /chronik hilfe zeigt alle Befehle.",
})

-- English command names -> the German ones the modules know (the German ones stay valid)
local COMMAND_ALIASES = {
  options = "optionen", settings = "optionen", einstellungen = "optionen", config = "optionen",
  welcome = "willkommen", rest = "rast", sound = "ton", meter = "messer", note = "notiz",
  language = "sprache", lang = "sprache", save = "sichern", backup = "sicherung", campfire = "feuer", lagerfeuer = "feuer",
  open = "offene", quests = "offene", auras = "auren", buffs = "auren", coins = "muenzen", ["münzen"] = "muenzen",
  training = "lehrplan", trainer = "lehrplan", lehrer = "lehrplan",
  anleitung = "tutorial", einfuehrung = "tutorial", ["einführung"] = "tutorial", intro = "tutorial",
}

-- Errors are counted per handler (collector x event/signal/timer/hook), not per collector: MAX_ERRORS errors of one handler
-- within ERROR_WINDOW seconds pause it for PAUSE_SECS; the MAX_PAUSES-th pause in a session keeps it off until the reload.
-- Single errors over hours never switch anything off. An init error gets one new try after INIT_RETRY seconds.
Core.MAX_ERRORS = 3
Core.ERROR_WINDOW = 60
Core.PAUSE_SECS = 300
Core.MAX_PAUSES = 3
Core.INIT_RETRY = 10
-- never register (Midnight/Forever: ADDON_ACTION_FORBIDDEN)
Core.FORBIDDEN_EVENTS = { COMBAT_LOG_EVENT_UNFILTERED = true, COMBAT_LOG_EVENT = true }
-- base APIs for /chronik diag (in addition to every collector's requires)
Core.BASE_APIS = {
  "C_Timer.After", "C_Timer.NewTicker", "UnitGUID", "UnitName", "UnitLevel", "UnitRace", "UnitClass",
  "UnitFactionGroup", "GetRealmName", "GetBuildInfo", "GetLocale", "InCombatLockdown", "IsInInstance", "ReloadUI",
  "issecretvalue", "hooksecurefunc", "UnitTokenFromGUID", "UnitClassification", "UnitXP", "UnitXPMax", "GetXPExhaustion",
  "IsResting", "RequestTimePlayed", "Screenshot", "GetMoney", "UnitPosition", "UnitOnTaxi",
  "C_Map.GetBestMapForUnit", "C_Map.GetPlayerMapPosition", "C_DeathRecap.GetRecapEvents",
  "C_DamageMeter.GetCombatSessionFromType", "C_QuestLog.GetTitleForQuestID", "C_QuestLog.GetInfo",
  "GetQuestID", "GetTitleText", "GetQuestText", "GetObjectiveText", "GetProgressText", "GetRewardText",
  "ItemTextGetText", "ItemTextGetPage", "TaxiNodeName", "TaxiNodeCost", "C_Item.GetItemInfo",
  "C_Traits.GetConfigInfo", "C_ClassTalents.GetActiveConfigID", "C_Reputation.GetFactionDataByIndex",
  "C_SkillInfo.GetSkillLineInfo", "GetProfessions", "C_AuctionHouse", "C_GameRules.GetForeverExperiencePreset",
  "C_RestrictedActions.GetAddOnRestrictionState", "C_Secrets.ShouldUnitIdentityBeSecret",
  -- optional, diagnostics only: combat, death, world, travel, instances, quest lines
  "UnitHealthMax", "UnitIsDeadOrGhost", "UnitIsGhost", "C_DeathRecap.GetRecapMaxHealth", "C_DeathInfo.GetCorpseMapPosition",
  "C_DamageMeter.IsDamageMeterAvailable", "C_Map.GetMapInfo", "GetZoneText", "GetSubZoneText", "GetRealZoneText",
  "GetInstanceInfo", "GetNumGroupMembers", "TakeTaxiNode", "TaxiNodeGetType", "NumTaxiNodes", "C_TaxiMap.GetAllTaxiNodes",
  "GetBindLocation", "C_QuestLine.GetQuestLineInfo", "C_QuestLine.GetQuestLineQuests", "GetTaxiMapID", "UnitHealth",
  -- optional, diagnostics only: economy, loot, gear, character, social, extras
  "RepairAllItems", "InRepairMode", "C_AuctionHouse.PostItem", "C_AuctionHouse.PostCommodity", "C_AuctionHouse.PlaceBid",
  "C_AuctionHouse.ConfirmCommoditiesPurchase", "C_AuctionHouse.CancelAuction", "GetInboxNumItems", "GetInboxHeaderInfo",
  "GetInboxInvoiceInfo", "GetInboxItemLink", "GetInboxItem", "TakeInboxMoney", "TakeInboxItem", "AutoLootMailItem",
  "SendMail", "GetSendMailItem", "GetSendMailMoney", "GetSendMailCOD", "GetNumLootItems", "GetLootSlotLink", "GetLootSlotInfo",
  "GetLootSourceInfo", "IsFishingLoot", "C_Item.GetItemInfoInstant", "C_Item.GetItemQualityByID", "C_Item.GetItemSpell",
  "C_Item.GetItemID", "C_Item.GetDetailedItemLevelInfo", "GetInventoryItemLink", "GetInventoryItemQuality",
  "GetAverageItemLevel", "C_Container.GetContainerNumSlots", "C_Container.GetContainerItemInfo", "C_Spell.GetSpellName",
  "C_Spell.GetSpellSubtext", "C_MountJournal.GetMountFromSpell", "C_Traits.GetTreeNodes", "C_Traits.GetNodeInfo",
  "C_Traits.GetEntryInfo", "C_Traits.GetDefinitionInfo", "C_Traits.GetTreeCurrencyInfo", "GetProfessionInfo",
  "C_Reputation.GetNumFactions", "UnitStat", "UnitArmor", "UnitPowerMax", "UnitAttackPower", "GetCritChance",
  "GetSpellCritChance", "GetDodgeChance", "GetParryChance", "GetBlockChance", "GetSpellBonusDamage", "GetSpellBonusHealing",
  "GetGuildInfo", "IsInGroup", "IsInRaid", "UnitIsGroupLeader", "UnitIsPlayer", "GetPlayerInfoByGUID", "StartDuel",
  "GetPlayerTradeMoney", "GetTargetTradeMoney", "GetTradePlayerItemLink", "GetTradeTargetItemLink",
  "GetTradePlayerItemInfo", "GetTradeTargetItemInfo", "DoEmote",
  -- optional, diagnostics only: companions, rest/campfire, welcome, plans
  "UnitFullName", "UnitExists", "UnitIsUnit", "GetNormalizedRealmName", "C_UnitAuras.GetPlayerAuraBySpellID",
  "C_QuestLog.GetNumQuestLogEntries",
  -- optional, diagnostics only: campfire talk (players at the fire, nameplate switch, send on click)
  "C_ChatInfo.SendChatMessage", "CheckInteractDistance", "C_UnitAuras.GetUnitAuraBySpellID", "C_CVar.GetCVar",
  "C_CVar.SetCVar", "UnitSex", "SitStandOrDescendStart",
  -- optional, diagnostics only: version, game rules, companion, loot rolls, durability, quest tags, bags, stats, day/night, pvp, jump
  "C_AddOns.GetAddOnMetadata", "C_GameRules.IsHardcoreActive", "C_GameRules.GetActiveGameMode",
  "C_GameRules.GetCurrentGameModeRecordID", "UnitCreatureFamily", "C_PetInfo.GetPetHappiness", "C_PetInfo.GetPetLoyalty",
  "C_PetInfo.GetPetTrainingPoints", "C_StableInfo.GetNumStableSlots", "RollOnLoot", "GetLootRollItemLink",
  "GetInventoryItemDurability", "C_QuestLog.IsEliteQuest", "C_QuestLog.GetQuestTagInfo", "C_QuestLog.GetSuggestedGroupSize",
  "C_Container.GetContainerNumFreeSlots", "UnitUsesAmmo", "GetInventoryItemCount", "UnitDefenseSkill",
  "C_DateAndTime.IsDayTime", "UnitIsPVP", "JumpOrAscendStart",
}

-- APIs whose absence is normal on some clients: reported as expected in /chronik diag, not as an error.
-- No collector depends on them (professions come from GetProfessions and the skill-increase message).
Core.EXPECTED_ABSENT = {
  ["C_SkillInfo.GetSkillLineInfo"] = "fehlt (erwartet auf Retail)", -- stored as-is in diag.apis, not translated
  ["C_GameRules.GetForeverExperiencePreset"] = "fehlt (nur auf Forever vorhanden)",
  -- Forever-exclusive names (warcraft.wiki.gg, Category:Exclusive_API/forever)
  ["C_PetInfo.GetPetHappiness"] = "fehlt (nur auf Forever vorhanden)",
  ["C_PetInfo.GetPetLoyalty"] = "fehlt (nur auf Forever vorhanden)",
  ["C_PetInfo.GetPetTrainingPoints"] = "fehlt (nur auf Forever vorhanden)",
  ["C_StableInfo.GetNumStableSlots"] = "fehlt (nur auf Forever vorhanden)",
  ["C_QuestLog.IsEliteQuest"] = "fehlt (nur auf Forever vorhanden)",
  ["C_DateAndTime.IsDayTime"] = "fehlt (nur auf Forever vorhanden)",
  ["UnitDefenseSkill"] = "fehlt (nur auf Forever vorhanden)",
  ["UnitUsesAmmo"] = "fehlt (nur auf Forever vorhanden)",
  -- Retail-only counterparts: not expected on Forever
  ["C_QuestLog.GetSuggestedGroupSize"] = "fehlt (erwartet auf Forever)",
}

-- special enemies: classification -> tag, used by Moments (kind kill/first_*).
-- level -1 (boss, '??') always counts as 'boss'; nil for normal enemies and secret values.
local SPECIAL = { elite = "elite", rare = "rare", rareelite = "rare", worldboss = "boss" }
function Core.specialTag(cls, level)
  local sec = type(issecretvalue) == "function" and issecretvalue or nil
  if type(level) == "number" and not (sec and sec(level)) and level == -1 then return "boss" end
  if type(cls) ~= "string" or (sec and sec(cls)) then return nil end
  return SPECIAL[cls]
end

local function prefix() return "|cff4fc3f7" .. T.prefix .. "|r " end

local registry = {}
local order = {}
local handlers = {}
local listeners = {}
local registered = {}
local byDef = {}
local signals = {}

local frame = CreateFrame("Frame")
Core.frame = frame
Core.started = false

local function nowGT()
  return type(GetTime) == "function" and GetTime() or 0
end

local function getDb()
  return ns.Store and ns.Store.db
end

local function errText(err)
  local ok, s = pcall(tostring, err)
  if not ok or type(s) ~= "string" then s = "?" end
  return ns.Sanitize and ns.Sanitize.field(s) or s
end

-- Output and errors

-- switch word (German or English) -> true (on), false (off) or nil (not a switch word); case-insensitive
local ON_WORDS = { an = true, ein = true, on = true }
local OFF_WORDS = { aus = true, off = true }
function Core.onOff(word)
  if type(word) ~= "string" then return nil end
  word = string.lower(word)
  if ON_WORDS[word] then return true end
  if OFF_WORDS[word] then return false end
  return nil
end

function Core.print(msg)
  local line = prefix() .. msg
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage(line)
  else
    print(line)
  end
end

-- errors in the core (Store/Save/slash): never rethrown, only noted in diag.core
function Core.coreError(err)
  Core.lastCoreError, Core.lastCoreErrorAt = errText(err), time()
  Core.coreErrors = (Core.coreErrors or 0) + 1
  Core.syncDiag()
end

function Core.safe(fn, ...)
  if type(fn) ~= "function" then return false end
  local ok, err = pcall(fn, ...)
  if not ok then Core.coreError(err) end
  return ok
end

-- copies the registry state (and missing GlobalStrings) to EveNChronicleDB.diag
function Core.syncDiag()
  local db = getDb()
  if not db or type(db.diag) ~= "table" then return end
  local d = db.diag
  if type(d.collectors) ~= "table" then d.collectors = {} end
  local gt = nowGT()
  for _, e in ipairs(order) do
    local old = type(d.collectors[e.name]) == "table" and d.collectors[e.name] or {}
    -- handlers: paused ones (key -> epoch when they resume) and ones off until the reload (key -> true)
    local paused, off
    for key, h in pairs(e.hs) do
      if h.off then
        off = off or {}
        off[key] = true
      elseif h.pausedUntil and gt < h.pausedUntil then
        paused = paused or {}
        paused[key] = h.resumeAt
      end
    end
    d.collectors[e.name] = {
      status = e.status,
      note = e.note,
      errors = e.errors,
      rejectedEvents = e.rejected,
      unknownEvents = e.unknown,
      disabledAt = e.disabledAt,
      lastError = e.lastError or old.lastError,
      lastErrorAt = e.lastErrorAt or old.lastErrorAt,
      lastEvent = e.lastEvent or old.lastEvent,
      firstError = e.firstError or old.firstError,
      firstErrorAt = e.firstErrorAt or old.firstErrorAt,
      pauses = e.pauseCount,
      paused = paused,
      off = off,
      initRetried = e.initRetried,
    }
  end
  local missing = ns.Patterns and ns.Patterns.missing
  if missing and next(missing) then
    if type(d.patterns) ~= "table" then d.patterns = {} end
    for name in pairs(missing) do d.patterns[name] = "fehlt" end
  end
  if Core.lastCoreError then
    d.core = { lastError = Core.lastCoreError, lastErrorAt = Core.lastCoreErrorAt, errors = Core.coreErrors }
  end
  if ns.Store and ns.Store.dropped and ns.Store.dropped > 0 then d.droppedLines = ns.Store.dropped end
end

-- Events

local function registerFrameEvent(event)
  if registered[event] then return true end
  if Core.FORBIDDEN_EVENTS[event] then return false end
  local ok = pcall(frame.RegisterEvent, frame, event)
  if not ok then return false end
  registered[event] = true
  return true
end

-- internal listener (Store/Save): runs before the collectors, errors land in diag.core
function Core.on(event, fn)
  if type(event) ~= "string" or type(fn) ~= "function" or Core.FORBIDDEN_EVENTS[event] then return false end
  local list = listeners[event]
  if not list then
    list = {}
    listeners[event] = list
  end
  list[#list + 1] = fn
  return registerFrameEvent(event)
end

local function notify(event, ...)
  local list = listeners[event]
  if not list then return end
  for i = 1, #list do Core.safe(list[i], event, ...) end
end

-- Handler state of a collector: e.hs[key] = { fails = {GetTime of recent errors}, pauses = n, pausedUntil = GetTime,
-- resumeAt = epoch, off = true }. key = event name, signal name, "after", "ticker" or "hook:<name>"; memory only (reload resets).
-- true while the handler is paused or off; a pause that has run out is lifted here (no timer needed)
local function handlerBlocked(e, key)
  local h = e.hs[key]
  if not h then return false end
  if h.off then return true end
  if h.pausedUntil then
    if nowGT() < h.pausedUntil then return true end
    h.pausedUntil, h.resumeAt = nil, nil
    h.fails = {}
    Core.syncDiag()
  end
  return false
end

-- key: which handler failed (nil = unknown, counted under "?"); noPause: count only (one-shot timers)
function Core.collectorFailed(e, err, key, noPause)
  key = type(key) == "string" and key or "?"
  local at, msg = time(), errText(err)
  e.errors = e.errors + 1
  e.lastError, e.lastErrorAt, e.lastEvent = msg, at, key
  if not e.firstError then e.firstError, e.firstErrorAt = msg, at end
  if e.active and not noPause then
    local h = e.hs[key]
    if not h then
      h = { fails = {}, pauses = 0 }
      e.hs[key] = h
    end
    if not h.off and not h.pausedUntil then
      local t, kept = nowGT(), {}
      for _, f in ipairs(h.fails) do
        if t - f < Core.ERROR_WINDOW then kept[#kept + 1] = f end
      end
      kept[#kept + 1] = t
      h.fails = kept
      if #kept >= Core.MAX_ERRORS then
        h.fails = {}
        h.pauses = h.pauses + 1
        e.pauseCount = (e.pauseCount or 0) + 1
        if h.pauses >= Core.MAX_PAUSES then
          h.off, h.offAt = true, at
          Core.print(T("handlerOff", e.name, key))
        else
          h.pausedUntil, h.resumeAt = t + Core.PAUSE_SECS, at + Core.PAUSE_SECS
        end
      end
    end
  end
  Core.syncDiag()
end

-- paused (until resumeAt) and permanently-off (until reload) handlers, as sorted "Collector:key" lists
function Core.handlerStates()
  local paused, off = {}, {}
  local t = nowGT()
  for _, e in ipairs(order) do
    for key, h in pairs(e.hs) do
      if h.off then
        off[#off + 1] = e.name .. ":" .. key
      elseif h.pausedUntil and t < h.pausedUntil then
        paused[#paused + 1] = { name = e.name .. ":" .. key, left = h.pausedUntil - t }
      end
    end
  end
  table.sort(paused, function(a, b) return a.name < b.name end)
  table.sort(off)
  return paused, off
end

local function printHandlerStates()
  local paused, off = Core.handlerStates()
  if #paused > 0 then
    local items = {}
    for i, p in ipairs(paused) do items[i] = format("%s (%s)", p.name, T("minShort", math.max(1, math.ceil(p.left / 60)))) end
    Core.print(T("handlersPaused", concat(items, ", ")))
  end
  if #off > 0 then Core.print(T("handlersOff", concat(off, ", "))) end
end

local function dispatch(event, ...)
  local list = handlers[event]
  if not list then return end
  for i = 1, #list do
    local e = list[i]
    if e.active and type(e.def.onEvent) == "function" and not handlerBlocked(e, event) then
      local ok, err = pcall(e.def.onEvent, e.def, event, ...)
      if not ok then Core.collectorFailed(e, err, event) end
    end
  end
end

-- internal signals between collectors (e.g. FC_KILL from Combat to Moments); never sent to the client frame.
-- receivers run under pcall like events; an error counts against the receiver, never the sender.
Core.SIGNAL_PREFIX = "FC_"

function Core.emit(signal, ...)
  local list = signals[signal]
  if not list then return end
  for i = 1, #list do
    local e = list[i]
    if e.active and type(e.def.onEvent) == "function" and not handlerBlocked(e, signal) then
      local ok, err = pcall(e.def.onEvent, e.def, signal, ...)
      if not ok then Core.collectorFailed(e, err, signal) end
    end
  end
end

-- Collector registry

-- 'C_DeathRecap.GetRecapEvents' -> value in _G (or nil)
function Core.resolve(path)
  if type(path) ~= "string" then return nil end
  local v = _G
  for part in string.gmatch(path, "[^%.]+") do
    if type(v) ~= "table" then return nil end
    v = v[part]
  end
  return v
end

local function available(path)
  local t = type(Core.resolve(path))
  return t == "function" or t == "table", t
end

function Core.checkRequires(requires)
  local missing = {}
  if type(requires) == "table" then
    for _, path in ipairs(requires) do
      if not available(path) then missing[#missing + 1] = tostring(path) end
    end
  end
  return missing
end

local function addHandler(event, e)
  local list = handlers[event]
  if not list then
    list = {}
    handlers[event] = list
  end
  for i = 1, #list do
    if list[i] == e then return end
  end
  list[#list + 1] = e
end

-- UNIT_* events for specific units only: own frame per collector, RegisterUnitEvent (fallback: RegisterEvent
-- and filter on the first argument). Returns false if the event cannot be registered.
local function registerUnitEvent(e, event, units)
  if not e.unitFrame then
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(_, ev, unit, ...)
      local filter = e.unitFilter[ev]
      if not e.active or type(e.def.onEvent) ~= "function" then return end
      if filter and not (type(unit) == "string" and filter[unit]) then return end
      if handlerBlocked(e, ev) then return end
      local ok, err = pcall(e.def.onEvent, e.def, ev, unit, ...)
      if not ok then Core.collectorFailed(e, err, ev) end
    end)
    e.unitFrame, e.unitFilter = f, {}
  end
  local f = e.unitFrame
  if #units >= 1 and #units <= 2 and type(f.RegisterUnitEvent) == "function"
    and pcall(f.RegisterUnitEvent, f, event, units[1], units[2]) then
    return true
  end
  if not pcall(f.RegisterEvent, f, event) then return false end
  local set = {}
  for _, u in ipairs(units) do set[u] = true end
  e.unitFilter[event] = set
  return true
end

local startCollector

-- a failed init gets exactly one new try after INIT_RETRY seconds (an API may only be ready after the login)
local function scheduleInitRetry(e)
  if e.initRetried or type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return end
  e.initRetried = true
  pcall(C_Timer.After, Core.INIT_RETRY, function()
    if e.status ~= "disabled" or not e.initFailed then return end
    e.status, e.initFailed, e.note, e.disabledAt = "registered", nil, nil, nil
    startCollector(e)
    Core.syncDiag()
  end)
end

function startCollector(e)
  if e.status ~= "registered" then return end
  local def = e.def
  local missing = Core.checkRequires(def.requires)
  if #missing > 0 then
    e.status = "missing"
    e.note = "fehlt: " .. concat(missing, ", ")
    return
  end
  e.active = true -- already during init so Core.after/ticker/hook work there
  e.status = "active"
  e.hookCalls = {}
  if type(def.init) == "function" then
    local ok, err = pcall(def.init, def)
    if not ok then
      local at, msg = time(), errText(err)
      e.active = false
      e.errors = e.errors + 1
      e.lastError, e.lastErrorAt, e.lastEvent = msg, at, "init"
      if not e.firstError then e.firstError, e.firstErrorAt = msg, at end
      e.status = "disabled"
      e.note = "Start fehlgeschlagen"
      e.disabledAt = at
      e.initFailed = true
      -- what the failed init started must not run twice after the retry: cancel its tickers, drop its timers (e.gen)
      e.gen = e.gen + 1
      for _, h in ipairs(e.tickerHandles) do pcall(h.Cancel, h) end
      e.tickerHandles = {}
      scheduleInitRetry(e)
      return
    end
  end
  local rejected, unknown = {}, {}
  local function sortEvent(event, units)
    if type(event) ~= "string" then
      unknown[#unknown + 1] = "?"
    elseif Core.FORBIDDEN_EVENTS[event] then
      rejected[#rejected + 1] = event
    elseif units then
      if not registerUnitEvent(e, event, units) then unknown[#unknown + 1] = event end
    elseif registerFrameEvent(event) then
      addHandler(event, e)
    else
      unknown[#unknown + 1] = event
    end
  end
  if type(def.events) == "table" then
    for _, event in ipairs(def.events) do sortEvent(event) end
  end
  if type(def.unitEvents) == "table" then
    local names = {}
    for event in pairs(def.unitEvents) do names[#names + 1] = event end
    table.sort(names)
    for _, event in ipairs(names) do
      local units = def.unitEvents[event]
      local list = {}
      if type(units) == "table" then
        for _, u in ipairs(units) do if type(u) == "string" then list[#list + 1] = u end end
      end
      if #list > 0 then sortEvent(event, list) else unknown[#unknown + 1] = event end
    end
  end
  if type(def.signals) == "table" then
    for _, sig in ipairs(def.signals) do
      if type(sig) == "string" and string.sub(sig, 1, #Core.SIGNAL_PREFIX) == Core.SIGNAL_PREFIX then
        local list = signals[sig]
        if not list then
          list = {}
          signals[sig] = list
        end
        list[#list + 1] = e
      else
        unknown[#unknown + 1] = type(sig) == "string" and sig or "?"
      end
    end
  end
  if #rejected > 0 then e.rejected = concat(rejected, ", ") end
  if #unknown > 0 then e.unknown = concat(unknown, ", ") end
  if e.rejected then e.note = "gesperrt (nie registriert): " .. e.rejected end
  if e.unknown then e.note = (e.note and (e.note .. "; ") or "") .. "Event unbekannt: " .. e.unknown end
end

-- timers and hooks for collectors: run under pcall, errors count against the collector, inactive collectors do nothing
local function entryOf(def)
  return type(def) == "table" and byDef[def] or nil
end

-- key = handler name for the pause logic; key nil = one-shot timers: errors are counted but never pause (nothing repeats)
-- gen: timers and tickers made by an init that failed later are dropped (e.gen counts failed inits); hooks cannot be undone
-- and therefore keep working across the retry (see Core.hook)
local function guarded(e, fn, key, keepGen)
  local gen = e.gen
  return function(...)
    if not e.active or (not keepGen and e.gen ~= gen) or (key and handlerBlocked(e, key)) then return end
    local ok, err = pcall(fn, e.def, ...)
    if not ok then Core.collectorFailed(e, err, key or "after", key == nil) end
  end
end

local NO_HANDLE = { Cancel = function() end, IsCancelled = function() return true end }

function Core.after(def, sec, fn)
  local e = entryOf(def)
  if not e or not e.active or type(fn) ~= "function" then return false end
  C_Timer.After(sec, guarded(e, fn))
  return true
end

-- ticker: fn(self) every sec seconds; returns a handle with Cancel(); ends when the collector is disabled
function Core.ticker(def, sec, fn)
  local e = entryOf(def)
  if not e or not e.active or type(fn) ~= "function" then return NO_HANDLE end
  local handle
  e.tickers = (e.tickers or 0) + 1
  local key = "ticker#" .. e.tickers
  local run = guarded(e, fn, key)
  local gen = e.gen
  handle = C_Timer.NewTicker(sec, function(...)
    local h = e.hs[key]
    if not e.active or e.gen ~= gen or (h and h.off) then
      if handle then handle:Cancel() end
      return
    end
    run(...)
  end)
  e.tickerHandles[#e.tickerHandles + 1] = handle
  return handle
end

-- hooksecurefunc for collectors: Core.hook(self, 'GlobalFunction', fn) or Core.hook(self, table, 'method', fn).
-- fn(self, ...) gets the original call's arguments; returns true if the hook is in place.
function Core.hook(def, tblOrName, name, fn)
  local e = entryOf(def)
  if not e or not e.active or type(hooksecurefunc) ~= "function" then return false end
  local key
  if type(tblOrName) == "string" then
    if type(name) ~= "function" or type(_G[tblOrName]) ~= "function" then return false end
    key = "hook:" .. tblOrName
  else
    if type(tblOrName) ~= "table" or type(name) ~= "string" or type(fn) ~= "function" or type(tblOrName[name]) ~= "function" then
      return false
    end
    -- one error counter per table and function name (e.g. the OnAccept of two different dialogs)
    local id = e.tblIds[tblOrName]
    if not id then
      e.tblCount = e.tblCount + 1
      id = e.tblCount
      e.tblIds[tblOrName] = id
    end
    key = "hook:t" .. id .. "." .. name
  end
  -- the n-th hook on the same target during one init run: if an earlier (failed) init already installed it, it stays
  -- (hooksecurefunc cannot be undone, a second one would count everything twice)
  local n = (e.hookCalls[key] or 0) + 1
  e.hookCalls[key] = n
  if n <= (e.hookDone[key] or 0) then return true end
  local ok
  if type(tblOrName) == "string" then
    ok = pcall(hooksecurefunc, tblOrName, guarded(e, name, key, true))
  else
    ok = pcall(hooksecurefunc, tblOrName, name, guarded(e, fn, key, true))
  end
  if ok then e.hookDone[key] = n end
  return ok and true or false
end

-- def = { events = {...}, unitEvents = { UNIT_X = { "player" } }, signals = { "FC_KILL", ... }, requires = { "C_X.Y", ... },
--         init = fn(self), onEvent = fn(self, event, ...) }
-- self is the def table itself (collectors keep their state in it); def.name is set.
function ns.RegisterCollector(name, def)
  if type(name) ~= "string" or not string.match(name, "^[%w_]+$") or registry[name] or type(def) ~= "table" then
    Core.coreError("Sammler ungueltig oder doppelt: " .. tostring(name))
    return false
  end
  def.name = name
  local e = { name = name, def = def, status = "registered", errors = 0, active = false, hs = {},
    gen = 0, tickerHandles = {}, tblIds = setmetatable({}, { __mode = "k" }), tblCount = 0, hookCalls = {}, hookDone = {} }
  registry[name] = e
  byDef[def] = e
  order[#order + 1] = e
  if Core.started then
    startCollector(e)
    Core.syncDiag()
  end
  return true
end
Core.RegisterCollector = ns.RegisterCollector

function Core.startAll()
  Core.started = true
  for _, e in ipairs(order) do startCollector(e) end
  Core.syncDiag()
end

function Core.collectorCounts()
  local active = 0
  for _, e in ipairs(order) do
    if e.active then active = active + 1 end
  end
  return active, #order
end

function Core.collector(name)
  return registry[name]
end

-- Lifecycle

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if (...) == ADDON_NAME then
      if ns.Locale then Core.safe(ns.Locale.apply) end -- language from the SavedVariables, before anything else
      Core.safe(ns.Store.init)
      Core.syncDiag()
    end
  elseif event == "PLAYER_LOGIN" then
    Core.safe(ns.Store.login)
  elseif event == "PLAYER_ENTERING_WORLD" and not Core.started then
    Core.safe(ns.Store.beginSession, ...)
    Core.startAll()
  elseif event == "PLAYER_LOGOUT" then
    dispatch(event, ...) -- collectors write their last lines first
    notify(event, ...)
    Core.safe(ns.Store.logout)
    Core.syncDiag()
    return
  end
  notify(event, ...)
  dispatch(event, ...)
end)

registerFrameEvent("ADDON_LOADED")
registerFrameEvent("PLAYER_LOGIN")
registerFrameEvent("PLAYER_ENTERING_WORLD")
registerFrameEvent("PLAYER_LOGOUT")

-- Slash /chronik

local function shortList(list, max)
  if #list <= max then return concat(list, ", ") end
  local head = {}
  for i = 1, max do head[i] = list[i] end
  return concat(head, ", ") .. T("moreCount", #list - max)
end

function Core.statusLine()
  local active, total = Core.collectorCounts()
  local Store = ns.Store
  local char = Store and Store.char()
  local running = active >= total and T.allRunning or T("someRunning", active, total)
  if not char then
    return T("waiting", running)
  end
  local since = date(T.dateFmt, char.info.firstSeen)
  local secs = math.max(0, time() - (Store.loginAt or time()))
  local Fmt = ns.Journal and ns.Journal.Fmt
  local ago = (secs < 60 and T.justNow) or T("ago", (Fmt and Fmt.duration(secs)) or T("minShort", floor(secs / 60)))
  local n = floor(char.lineCount or 0)
  local count = (Fmt and Fmt.int(n)) or tostring(n)
  return T("status", since, count, T(ns.Locale.plural(n, "entry_one", "entry_other")), ago, running)
end

-- help lines in display order (empty texts are skipped)
local HELP = {
  "helpTitle", "helpToggle", "helpStatus", "helpOptions", "helpMinimap", "helpToast", "helpSound", "helpWelcome", "helpTutorial", "helpRest",
  "helpMeter", "helpTodo", "helpNote", "helpOpen", "helpTrain", "helpLanguage", "helpReset", "helpSave", "helpBackup", "helpHelp", "helpAliases", "helpDebug", "helpDiag",
  "helpDiagQuests", "helpCampfire", "helpSim", "helpAuras", "helpCoins",
}

-- Development tools (the campfire simulation, /chronik sim) exist only where journal/SimPanel.lua is part of the addon folder;
-- the release package leaves that file out (.pkgmeta), then the command and its help line are absent.
function Core.hasDevTools()
  return ns.SimPanel ~= nil
end

-- Help lines about WoW Forever only parts, left out in Retail: the campfire talk (never starts there) and the trainer plan.
local function helpHiddenInRetail(key)
  local J = ns.Journal
  if key == "helpCampfire" then
    local ms = J and J.MapSpace
    return ms ~= nil and type(ms.fireTalkHidden) == "function" and ms.fireTalkHidden() == true
  elseif key == "helpTrain" then
    local lp = J and J.Lehrplan
    return lp ~= nil and type(lp.active) == "function" and lp.active() == false
  end
  return false
end

function Core.printHelp()
  for _, key in ipairs(HELP) do
    local line = T[key]
    if line ~= "" and (key ~= "helpSim" or Core.hasDevTools()) and not helpHiddenInRetail(key) then Core.print(line) end
  end
end

local function probeRestrictions()
  local out = {}
  local api = C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState
  if type(api) ~= "function" then return nil end
  for kind = 0, 5 do
    local ok, state = pcall(api, kind)
    if ok and not (issecretvalue and issecretvalue(state)) and type(state) == "number" then out[kind + 1] = state end
  end
  return out
end

function Core.runDiag()
  local list, seen = {}, {}
  local function add(path)
    if type(path) == "string" and not seen[path] then
      seen[path] = true
      list[#list + 1] = path
    end
  end
  for _, p in ipairs(Core.BASE_APIS) do add(p) end
  for _, e in ipairs(order) do
    if type(e.def.requires) == "table" then
      for _, p in ipairs(e.def.requires) do add(p) end
    end
  end
  local apis, missing, expected = {}, {}, {}
  for _, p in ipairs(list) do
    local ok, t = available(p)
    if ok then
      apis[p] = t
    elseif Core.EXPECTED_ABSENT[p] or (p == "C_AddOns.GetAddOnMetadata" and type(_G.GetAddOnMetadata) == "function") then
      apis[p] = Core.EXPECTED_ABSENT[p] or "fehlt (globales GetAddOnMetadata als Rückfall vorhanden)"
      expected[#expected + 1] = p
    else
      apis[p] = "fehlt"
      missing[#missing + 1] = p
    end
  end

  local db = getDb()
  if db then
    local d = db.diag
    d.apis = apis
    d.lastRun = time()
    local build, buildNumber, _, interface = GetBuildInfo()
    d.client = { build = build, buildNumber = tonumber(buildNumber), interface = tonumber(interface), locale = GetLocale() }
    d.restrictions = probeRestrictions()
    d.state = {
      inCombat = InCombatLockdown() and true or false,
      inInstance = IsInInstance() and true or false,
      healthSecret = issecretvalue and issecretvalue(UnitHealth and UnitHealth("player")) and true or false,
    }
    Core.syncDiag()
  end

  -- expected-absent APIs count neither as present nor missing (own line)
  local counted = #list - #expected
  Core.print(T("selfTest", counted - #missing, counted))
  if #missing > 0 then Core.print(T("missing", shortList(missing, 8))) end
  if #expected > 0 then Core.print(T("expectedAbsent", shortList(expected, 4))) end
  local active, total = Core.collectorCounts()
  local inactive = {}
  for _, e in ipairs(order) do
    if not e.active then inactive[#inactive + 1] = e.name .. " (" .. (e.note or e.status) .. ")" end
  end
  local line = T("collectorsActive", active, total)
  if #inactive > 0 then line = line .. T("inactive", shortList(inactive, 4)) end
  Core.print(line)
  printHandlerStates()
  -- handwriting: fresh probe on the toolkit's invisible FontString, with a reason on fallback
  local diary = ns.Journal and ns.Journal.Widgets and ns.Journal.Widgets.Diary
  if diary and type(diary.handStatus) == "function" then
    local ok, hand = pcall(diary.handStatus)
    Core.print(ok and tostring(hand) or T("checkFailed", T.labHand, tostring(hand)))
  end
  -- to-do lists (add-on InkAndEmbers_Data, LoadOnDemand): fresh load attempt (not in combat), then the status
  local todoData = ns.Journal and ns.Journal.TodoData
  if todoData and type(todoData.diagLine) == "function" then
    if type(todoData.retry) == "function" then pcall(todoData.retry) end
    for _, kind in ipairs({ "npc", "item" }) do
      local ok, line = pcall(todoData.diagLine, kind)
      Core.print(ok and tostring(line) or T("checkFailed", T.labTodo, tostring(line)))
    end
  end
  -- open quests (add-on InkAndEmbers_QuestData, LoadOnDemand): fresh load attempt (not in combat), then the status
  local openQuests = ns.Journal and ns.Journal.OpenQuests
  if openQuests and type(openQuests.diagLine) == "function" then
    if type(openQuests.retry) == "function" then pcall(openQuests.retry) end
    local ok, line = pcall(openQuests.diagLine)
    Core.print(ok and tostring(line) or T("checkFailed", T.labOpenQuests, tostring(line)))
  end
  -- installed QuestieDB add-on (version and contract from its TOC only) next to the data extract; nil in Retail = no line
  if openQuests and type(openQuests.qdbDiagLine) == "function" then
    local ok, line = pcall(openQuests.qdbDiagLine)
    if ok and type(line) == "string" then Core.print(line) end
  end
  -- to-do enemies on the nameplate: seen/marked/last failure reason
  local marks = ns.Journal and ns.Journal.TodoMarks
  if marks and type(marks.diagLine) == "function" then
    local ok, line = pcall(marks.diagLine)
    Core.print(ok and tostring(line) or T("checkFailed", T.labMarks, tostring(line)))
    if ok and db and db.diag and type(marks.state) == "table" and type(marks.state.diag) == "table" then
      local s = marks.state.diag
      db.diag.todoMarks = { seen = s.seen, forbidden = s.forbidden, marked = s.marked, reason = s.reason, how = s.how, anchor = s.anchor }
    end
  end
  if ns.Trainer and type(ns.Trainer.diagLine) == "function" then
    local ok, line = pcall(ns.Trainer.diagLine)
    if ok then Core.print(tostring(line)) end
  end
  if type(ns.meterStatus) == "function" then
    local ok, line, now, last = pcall(ns.meterStatus)
    Core.print(ok and tostring(line) or T("checkFailed", T.labMeter, tostring(line)))
    if ok and db and db.diag then db.diag.meter = { now = now, last = last } end
  end
  if ns.Rest and type(ns.Rest.fireStatus) == "function" then
    local ok, line = pcall(ns.Rest.fireStatus)
    Core.print(ok and tostring(line) or T("checkFailed", T.labFire, tostring(line)))
  end
  if ns.Campfire and type(ns.Campfire.statusLine) == "function" then
    local ok, line = pcall(ns.Campfire.statusLine)
    Core.print(ok and tostring(line) or T("checkFailed", T.labRound, tostring(line)))
  end
  local editMode = ns.Journal and ns.Journal.EditMode
  if editMode and type(editMode.diagLine) == "function" then
    local ok, line = pcall(editMode.diagLine)
    Core.print(ok and tostring(line) or T("checkFailed", T.labEditMode, tostring(line)))
  end
  local gsMissing = {}
  for name in pairs(ns.Patterns and ns.Patterns.missing or {}) do gsMissing[#gsMissing + 1] = name end
  if #gsMissing > 0 then
    table.sort(gsMissing)
    Core.print(T("globalStringsMissing", shortList(gsMissing, 4)))
  end
  local access = ns.Journal and ns.Journal.Access
  local perf = access and access.perfLine and access.perfLine()
  if perf then Core.print(perf) end
  Core.print(T.details)
end

-- /chronik diag retailquests [uiMapID]: one-time probe of the runtime quest APIs (C_QuestLine & co.) on the current or
-- given map, Retail and Forever. Asks RequestQuestLinesForMap, waits for QUESTLINE_UPDATE (at most QPROBE_WAIT s, then
-- reads anyway), copies every list entry raw (plain values only, secrets as "<secret>") to
-- EveNChronicleDB.diag.retailQuests[uiMapID] (one record per map, the oldest dropped beyond QPROBE_MAPS) and prints one
-- summary line. Every API call runs in pcall; a missing function is noted as "MISSING", never an error.
Core.QPROBE_WAIT = 3     -- seconds to wait for QUESTLINE_UPDATE
Core.QPROBE_MAPS = 20    -- maps kept in diag.retailQuests
Core.QPROBE_MAX = 200    -- entries per copied list
Core.QPROBE_DETAIL = 40  -- quests with extra lookups (classification, difficulty ...)
Core.QPROBE_LOG = 35     -- quest log entries with objectives
Core.QPROBE_REASK = 1    -- new requests when QUESTLINE_UPDATE says requestRequired

local function qSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function qFn(path)
  local t = _G
  for part in string.gmatch(path, "[^%.]+") do
    if type(t) ~= "table" then return nil end
    t = t[part]
  end
  return type(t) == "function" and t or nil
end

-- status "OK" | "MISSING" | "ERROR", then the first four results (ERROR: a short message)
local function qCall(path, ...)
  local f = qFn(path)
  if not f then return "MISSING" end
  local r = { pcall(f, ...) }
  if not r[1] then return "ERROR", string.sub(errText(r[2]), 1, 120) end
  return "OK", r[2], r[3], r[4], r[5]
end

local function qVal(path, ...)
  local s, a = qCall(path, ...)
  if s == "OK" then return a end
  return s
end

-- plain SV copy: numbers, booleans, short strings, tables up to depth 3 (QPROBE_MAX keys each); no functions, no secrets
local function qPlain(v, depth)
  depth = depth or 0
  if qSecret(v) then return "<secret>" end
  local tv = type(v)
  if tv == "number" then return (v == v and v ~= math.huge and v ~= -math.huge) and v or tostring(v) end
  if tv == "boolean" then return v end
  if tv == "string" then return ns.Sanitize and ns.Sanitize.field(string.sub(v, 1, 120)) or string.sub(v, 1, 80) end
  if tv == "table" and depth < 3 then
    local o, n = {}, 0
    for k, x in pairs(v) do
      if not qSecret(k) and (type(k) == "string" or type(k) == "number") and type(x) ~= "function" then
        n = n + 1
        if n > Core.QPROBE_MAX then o._cut = true break end
        o[k] = qPlain(x, depth + 1)
      end
    end
    return o
  end
  return nil
end

local function qNum(v)
  if qSecret(v) or type(v) ~= "number" or v ~= v then return nil end
  return v
end

-- stores a record under its map; beyond QPROBE_MAPS the oldest record (smallest 'at') goes
local function qStore(mapID, rec)
  local db = getDb()
  if not db then return false end
  db.diag = type(db.diag) == "table" and db.diag or {}
  local all = type(db.diag.retailQuests) == "table" and db.diag.retailQuests or {}
  -- old single-record form (no per-map keys): start fresh
  if all.mapID ~= nil then all = {} end
  db.diag.retailQuests = all
  all[mapID] = rec
  while true do
    local n, oldKey, oldAt = 0, nil, nil
    for k, r in pairs(all) do
      n = n + 1
      local at = type(r) == "table" and tonumber(r.at) or 0
      if k ~= mapID and (oldAt == nil or at < oldAt) then oldKey, oldAt = k, at end
    end
    if n <= Core.QPROBE_MAPS or oldKey == nil then break end
    all[oldKey] = nil
  end
  return true
end

-- counts of a quest line list: distinct quest lines, distinct quests
local function qCounts(list)
  local lines, quests, nl, nq = {}, {}, 0, 0
  if type(list) ~= "table" then return 0, 0 end
  for _, q in ipairs(list) do
    if type(q) == "table" then
      local l, id = qNum(q.questLineID), qNum(q.questID)
      if l and not lines[l] then lines[l] = true nl = nl + 1 end
      if id and not quests[id] then quests[id] = true nq = nq + 1 end
    end
  end
  return nl, nq
end

local function qCount(t)
  return type(t) == "table" and #t or 0
end

-- reads everything once the wait is over (via = "event" | "timeout" | "now")
local function qCollect(out, mapID)
  local s, lines = qCall("C_QuestLine.GetAvailableQuestLines", mapID)
  out.questLines = { status = s, list = s == "OK" and qPlain(lines) or nil, err = s == "ERROR" and lines or nil }
  out.extra = {}
  if s == "OK" and type(lines) == "table" then
    for i, q in ipairs(lines) do
      if i > Core.QPROBE_DETAIL then break end
      local id = type(q) == "table" and qNum(q.questID) or nil
      if id then
        out.extra[#out.extra + 1] = { id = id,
          trivial = qPlain(qVal("C_QuestLog.IsQuestTrivial", id)),
          class = qPlain(qVal("C_QuestInfoSystem.GetQuestClassification", id)),
          diff = qPlain(qVal("C_QuestLog.GetQuestDifficultyLevel", id)),
          done = qPlain(qVal("C_QuestLog.IsQuestFlaggedCompleted", id)),
          title = qPlain(qVal("C_QuestLog.GetTitleForQuestID", id)) }
      end
    end
    local qlid = type(lines[1]) == "table" and qNum(lines[1].questLineID) or nil
    if qlid then out.lineQuests = { id = qlid, list = qPlain(qVal("C_QuestLine.GetQuestLineQuests", qlid)) } end
  end
  local fs, force = qCall("C_QuestLine.GetForceVisibleQuests", mapID)
  out.forceVisible = { status = fs, list = fs == "OK" and qPlain(force) or nil, err = fs == "ERROR" and force or nil }
  out.tasks = qPlain(qVal("C_TaskQuest.GetQuestsOnMap", mapID))
  out.logOnMap = qPlain(qVal("C_QuestLog.GetQuestsOnMap", mapID))
  out.log = {}
  local n = qNum(qVal("C_QuestLog.GetNumQuestLogEntries")) or 0
  for i = 1, math.min(n, Core.QPROBE_LOG) do
    local info = qVal("C_QuestLog.GetInfo", i)
    local id = type(info) == "table" and qNum(info.questID) or nil
    if id and id > 0 and info.isHeader ~= true then
      local _, wm, wx, wy = qCall("C_QuestLog.GetNextWaypoint", id)
      out.log[#out.log + 1] = { id = id, title = qPlain(info.title),
        objectives = qPlain(qVal("C_QuestLog.GetQuestObjectives", id)), waypoint = qPlain({ wm, wx, wy }) }
    end
  end
end

-- the player and client state of the record
local function qPlayer()
  local _, race = qCall("UnitRace", "player")
  local _, class = qCall("UnitClass", "player")
  local _, faction, factionName = qCall("UnitFactionGroup", "player")
  return {
    level = qPlain(qVal("UnitLevel", "player")), race = qPlain(race), class = qPlain(class),
    faction = qPlain(faction), factionName = qPlain(factionName),
    chromie = qPlain(qVal("C_PlayerInfo.IsPlayerInChromieTime")),
    chromieID = qPlain(qVal("UnitChromieTimeID", "player")),
    trackHidden = qPlain(qVal("C_Minimap.IsTrackingHiddenQuests")),
    trackAccount = qPlain(qVal("C_Minimap.IsTrackingAccountCompletedQuests")),
  }
end

-- token of the running probe: a new command supersedes the old one (its event/timer then do nothing)
Core.qprobeToken = 0

function Core.diagRetailQuests(mapArg)
  if type(InCombatLockdown) == "function" then
    local ok, v = pcall(InCombatLockdown)
    if ok and not qSecret(v) and v == true then
      Core.print(T.rqCombat)
      return false
    end
  end
  local mapID = qNum(tonumber(mapArg))
  if not mapID then mapID = qNum(qVal("C_Map.GetBestMapForUnit", "player")) end
  if not mapID or mapID <= 0 or mapID ~= floor(mapID) or mapID > 2147483647 then
    Core.print(T.rqNoMap)
    return false
  end
  Core.qprobeToken = Core.qprobeToken + 1
  local token = Core.qprobeToken
  local info = qVal("C_Map.GetMapInfo", mapID)
  local build, buildNumber, interface
  if type(GetBuildInfo) == "function" then
    local okB, a, b, _, d = pcall(GetBuildInfo)
    if okB then build, buildNumber, interface = a, b, d end
  end
  local out = {
    at = time(), mapID = mapID, mapName = type(info) == "table" and qPlain(info.name) or nil,
    mapType = type(info) == "table" and qPlain(info.mapType) or nil, parentMapID = type(info) == "table" and qPlain(info.parentMapID) or nil,
    client = { project = qPlain(rawget(_G, "WOW_PROJECT_ID")), mainline = qPlain(rawget(_G, "WOW_PROJECT_MAINLINE")),
      build = qPlain(build), buildNumber = qPlain(buildNumber), interface = qPlain(interface) },
    player = qPlayer(), events = {}, requests = 0,
  }
  local hasLines = qFn("C_QuestLine.GetAvailableQuestLines") ~= nil
  local hasRequest = qFn("C_QuestLine.RequestQuestLinesForMap") ~= nil
  local frame = Core.qprobeFrame
  local done = false

  local function finish(via)
    if done or token ~= Core.qprobeToken then return end
    done = true
    if frame then pcall(frame.UnregisterAllEvents, frame) end
    out.via = via
    out.waited = (type(GetTime) == "function" and out.t0) and (GetTime() - out.t0) or nil
    local ok, err = pcall(qCollect, out, mapID)
    if not ok then out.error = string.sub(errText(err), 1, 200) end
    qStore(mapID, out)
    if not hasLines then
      Core.print(T("rqNoApi", mapID))
    else
      local nl, nq = qCounts(out.questLines and out.questLines.list)
      local name = type(out.mapName) == "string" and out.mapName ~= "<secret>" and out.mapName or "?"
      local viaText = (via == "event" and T.rqViaEvent) or (via == "timeout" and T.rqViaTimeout) or T.rqViaNow
      Core.print(T("rqResult", mapID, name, nl, nq, qCount(out.forceVisible and out.forceVisible.list), qCount(out.tasks), viaText))
    end
    if out.error then Core.print(T("rqError", out.error)) end
    Core.print(T("rqDetails", mapID))
  end

  -- without the request API or a timer nothing can be waited for: read at once
  local canWait = hasRequest and type(C_Timer) == "table" and type(C_Timer.After) == "function" and type(CreateFrame) == "function"
  if not canWait then
    if hasRequest then out.request = qCall("C_QuestLine.RequestQuestLinesForMap", mapID) else out.request = "MISSING" end
    finish("now")
    return true
  end
  if not frame then
    local okF, f = pcall(CreateFrame, "Frame")
    if okF and f then frame = f Core.qprobeFrame = f end
  end
  if frame then
    pcall(frame.UnregisterAllEvents, frame)
    local okR, errR = pcall(frame.RegisterEvent, frame, "QUESTLINE_UPDATE")
    if not okR then out.eventError = string.sub(errText(errR), 1, 120) end
    frame:SetScript("OnEvent", function(_, event, requestRequired)
      if done or token ~= Core.qprobeToken then return end
      if #out.events < 20 then
        out.events[#out.events + 1] = { e = event, requestRequired = qPlain(requestRequired), t = type(GetTime) == "function" and GetTime() or nil }
      end
      if requestRequired == true and out.requests <= Core.QPROBE_REASK then
        out.requests = out.requests + 1
        qCall("C_QuestLine.RequestQuestLinesForMap", mapID)
        return
      end
      Core.safe(finish, "event")
    end)
  end
  out.t0 = type(GetTime) == "function" and GetTime() or nil
  out.requests = 1
  out.request = qCall("C_QuestLine.RequestQuestLinesForMap", mapID)
  Core.print(T("rqAsked", mapID, Core.QPROBE_WAIT))
  local okT = pcall(C_Timer.After, Core.QPROBE_WAIT, function() Core.safe(finish, "timeout") end)
  if not okT then finish("now") end
  return true
end

function Core.slash(msg)
  local cmd = string.lower(string.match(type(msg) == "string" and msg or "", "^%s*(%S*)") or "")
  cmd = COMMAND_ALIASES[cmd] or cmd
  local rest = string.match(type(msg) == "string" and msg or "", "^%s*%S*%s+(%S*)") or ""
  local access = ns.Journal and ns.Journal.Access
  local toast = ns.Journal and ns.Journal.Toast
  if cmd == "" and access then
    access.toggle()
  elseif cmd == "" or cmd == "status" then
    Core.print(Core.statusLine())
    printHandlerStates()
  elseif cmd == "optionen" then
    local options = ns.Journal and ns.Journal.Options
    if options then options.open() else Core.print(T.optionsMissing) end
  elseif cmd == "minimap" and access then
    access.toggleMinimap()
  elseif cmd == "reset" and access then
    access.reset()
  elseif (cmd == "toast" or cmd == "zettel" or cmd == "ton") and toast then
    toast.slash(cmd, rest)
  elseif (cmd == "willkommen" or cmd == "rast") and ns.Journal and ns.Journal.Begleiter then
    ns.Journal.Begleiter.slash(cmd)
  elseif cmd == "todo" and ns.Journal and ns.Journal.TodoTracker then
    ns.Journal.TodoTracker.slash(rest)
  elseif (cmd == "offene" or cmd == "offen") and ns.Journal and ns.Journal.OpenQuests then
    ns.Journal.OpenQuests.slash(string.match(type(msg) == "string" and msg or "", "^%s*%S+%s+(.-)%s*$") or "")
  elseif cmd == "lehrplan" and ns.Trainer then
    ns.Trainer.slash(rest)
  elseif cmd == "notiz" and ns.Journal and ns.Journal.QuickNote then
    ns.Journal.QuickNote.slash(rest)
  elseif cmd == "messer" and type(ns.meterSlash) == "function" then
    ns.meterSlash(rest)
  elseif cmd == "sprache" and ns.Locale then
    Core.print(ns.Locale.slash(rest))
  elseif cmd == "diag" then
    if string.lower(rest) == "retailquests" then
      Core.diagRetailQuests(string.match(type(msg) == "string" and msg or "", "^%s*%S+%s+%S+%s+(%d+)"))
    else
      Core.runDiag()
    end
  elseif cmd == "feuer" then
    if ns.Campfire and ns.Campfire.slash then
      ns.Campfire.slash(rest)
    else
      Core.print(T.campfireMissing)
    end
  elseif cmd == "sim" and Core.hasDevTools() then
    -- whole rest of the line (name and class of the dummy guest need several words)
    local all = string.match(type(msg) == "string" and msg or "", "^%s*%S+%s+(.-)%s*$") or ""
    if ns.SimPanel and ns.SimPanel.devSlash and ns.SimPanel.devSlash(all) then
      -- developer switch handled (journal/SimPanel.lua)
    elseif all == "" and ns.SimPanel and ns.SimPanel.toggle then
      ns.SimPanel.toggle() -- no arguments: simulation window (journal/SimPanel.lua)
    elseif ns.Campfire and ns.Campfire.simSlash then
      ns.Campfire.simSlash(all)
    else
      Core.print(T.simMissing)
    end
  elseif cmd == "auren" then
    if ns.Rest and ns.Rest.listAuras then
      ns.Rest.listAuras()
    else
      Core.print(T.aurasMissing)
    end
  elseif cmd == "muenzen" then
    local texts = ns.Journal and ns.Journal.Texts
    if texts and texts.coinReport then
      for _, line in ipairs(texts.coinReport()) do Core.print(line) end
    else
      Core.print(T.coinsMissing)
    end
  elseif cmd == "sichern" then
    ns.Save.show()
  elseif cmd == "sicherung" and ns.Guard then
    ns.Guard.slash()
  elseif cmd == "tutorial" then
    local tutorial = ns.Journal and ns.Journal.Tutorial
    if tutorial then tutorial.slash() else Core.print(T.tutorialMissing) end
  elseif cmd == "hilfe" or cmd == "help" or cmd == "?" then
    Core.printHelp() -- command list only; the introduction is under 'tutorial' (journal/Tutorial.lua)
  else
    Core.print(T("unknownCommand", ns.Sanitize.field(cmd)))
  end
  -- a switch via command: an open options menu re-reads the values (journal/Options.lua)
  local options = ns.Journal and ns.Journal.Options
  if options and type(options.refresh) == "function" then options.refresh() end
end

SLASH_EVENCHRONICLE1 = "/chronik"
if type(SlashCmdList) == "table" then
  SlashCmdList.EVENCHRONICLE = function(msg) Core.safe(Core.slash, msg) end
end
