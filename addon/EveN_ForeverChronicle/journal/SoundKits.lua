-- Curated game sounds for the sound picker (journal/Options.lua). IDs match the SOUNDKIT constants in
-- wow-ui-source SoundKitConstants.lua; no invented IDs. At runtime the client SOUNDKIT[c] wins over the stored id.
local _, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local SoundKits = {}
Journal.SoundKits = SoundKits

SoundKits.GROUPS = {
  { key = "book", label = "Buch und Seiten" },
  { key = "quest", label = "Quest und Karte" },
  { key = "coins", label = "Münzen und Schätze" },
  { key = "bells", label = "Glocken und Signale" },
  { key = "fanfare", label = "Fanfaren und Erfolge" },
  { key = "magic", label = "Magie und Funkeln" },
}

SoundKits.LIST = {
  { g = "book", c = "IG_SPELLBOOK_OPEN", id = 829, name = "Zauberbuch öffnen" },
  { g = "book", c = "IG_SPELLBOOK_CLOSE", id = 830, name = "Zauberbuch schließen" },
  { g = "book", c = "IG_ABILITY_OPEN", id = 834, name = "Fähigkeitenbuch öffnen" },
  { g = "book", c = "IG_ABILITY_CLOSE", id = 835, name = "Fähigkeitenbuch schließen" },
  { g = "book", c = "IG_ABILITY_PAGE_TURN", id = 836, name = "Seite umblättern" },
  { g = "book", c = "UI_TRANSMOG_PAGE_TURN", id = 62539, name = "Seite umblättern (Garderobe)" },
  { g = "book", c = "UI_JOURNEYS_OPEN_LORE_BOOK", id = 170567, name = "Sagenbuch öffnen" },
  { g = "book", c = "UI_JOURNEYS_CLOSE_LORE_BOOK", id = 170568, name = "Sagenbuch schließen" },
  { g = "book", c = "UI_TORGHAST_WAYFINDER_PAGING_CLICK", id = 168457, name = "Blättern (Wegfinder)" },
  { g = "book", c = "ACHIEVEMENT_MENU_OPEN", id = 13832, name = "Erfolgsbuch öffnen" },
  { g = "book", c = "ACHIEVEMENT_MENU_CLOSE", id = 13833, name = "Erfolgsbuch schließen" },
  { g = "book", c = "IG_CHARACTER_INFO_OPEN", id = 839, name = "Charakterfenster öffnen" },
  { g = "book", c = "IG_CHARACTER_INFO_CLOSE", id = 840, name = "Charakterfenster schließen" },
  { g = "quest", c = "IG_QUEST_LOG_OPEN", id = 844, name = "Questlog öffnen" },
  { g = "quest", c = "IG_QUEST_LOG_CLOSE", id = 845, name = "Questlog schließen" },
  { g = "quest", c = "IG_QUEST_LOG_ABANDON_QUEST", id = 846, name = "Quest abbrechen" },
  { g = "quest", c = "IG_QUEST_LIST_OPEN", id = 875, name = "Questgeber spricht" },
  { g = "quest", c = "IG_QUEST_LIST_SELECT", id = 877, name = "Quest auswählen" },
  { g = "quest", c = "IG_QUEST_LIST_COMPLETE", id = 878, name = "Quest abgeschlossen" },
  { g = "quest", c = "UI_AUTO_QUEST_COMPLETE", id = 23404, name = "Quest automatisch abgeschlossen" },
  { g = "quest", c = "UI_QUEST_ROLLING_FORWARD_01", id = 43936, name = "Questfortschritt" },
  { g = "quest", c = "UI_WORLDQUEST_START", id = 73275, name = "Weltquest beginnt" },
  { g = "quest", c = "UI_WORLDQUEST_MAP_SELECT", id = 73276, name = "Weltquest auf der Karte wählen" },
  { g = "quest", c = "UI_WORLDQUEST_COMPLETE", id = 73277, name = "Weltquest abgeschlossen" },
  { g = "quest", c = "MAP_PING", id = 3175, name = "Kartenmarkierung (Ping)" },
  { g = "quest", c = "IG_MINIMAP_OPEN", id = 821, name = "Minikarte öffnen" },
  { g = "quest", c = "UI_MAP_WAYPOINT_CLICK_TO_PLACE", id = 170269, name = "Wegpunkt setzen" },
  { g = "quest", c = "UI_MAP_WAYPOINT_SUPER_TRACK_ON", id = 170270, name = "Wegpunkt verfolgen" },
  { g = "quest", c = "UI_MAP_WAYPOINT_REMOVE", id = 170273, name = "Wegpunkt entfernen" },
  { g = "quest", c = "CONTENT_TRACKING_START_TRACKING", id = 231910, name = "Verfolgung starten" },
  { g = "coins", c = "LOOT_WINDOW_COIN_SOUND", id = 120, name = "Münzen klimpern" },
  { g = "coins", c = "IG_BACKPACK_COIN_SELECT", id = 864, name = "Münzen greifen" },
  { g = "coins", c = "IG_BACKPACK_COIN_OK", id = 865, name = "Münzen abgezählt" },
  { g = "coins", c = "MONEY_FRAME_OPEN", id = 891, name = "Geldbeutel öffnen" },
  { g = "coins", c = "MONEY_FRAME_CLOSE", id = 892, name = "Geldbeutel schließen" },
  { g = "coins", c = "TRADING_POST_UI_COLLECTING_COINS", id = 218228, name = "Münzen einsammeln" },
  { g = "coins", c = "TRADING_POST_UI_CURRENCY_TICKER", id = 218232, name = "Münzzähler" },
  { g = "coins", c = "UI_CONTAINER_ITEM_OPEN", id = 143054, name = "Behälter öffnen" },
  { g = "coins", c = "UI_GARRISON_COMMAND_TABLE_CHEST_UNLOCK", id = 44331, name = "Truhe aufschließen" },
  { g = "coins", c = "UI_GARRISON_COMMAND_TABLE_CHEST_UNLOCK_GOLD_SUCCESS", id = 44332, name = "Goldtruhe aufschließen" },
  { g = "coins", c = "IG_BACKPACK_OPEN", id = 862, name = "Rucksack öffnen" },
  { g = "coins", c = "IG_BACKPACK_CLOSE", id = 863, name = "Rucksack schließen" },
  { g = "coins", c = "PUT_DOWN_GEMS", id = 1204, name = "Edelsteine ablegen" },
  { g = "coins", c = "PUT_DOWN_SMALL_CHAIN", id = 1212, name = "Kette ablegen" },
  { g = "coins", c = "ITEM_REPAIR", id = 7994, name = "Amboss (Reparieren)" },
  { g = "bells", c = "READY_CHECK", id = 8960, name = "Bereitschaftscheck" },
  { g = "bells", c = "RAID_WARNING", id = 8959, name = "Schlachtzugswarnung" },
  { g = "bells", c = "ALARM_CLOCK_WARNING_1", id = 18871, name = "Wecker 1" },
  { g = "bells", c = "ALARM_CLOCK_WARNING_2", id = 12867, name = "Wecker 2" },
  { g = "bells", c = "ALARM_CLOCK_WARNING_3", id = 12889, name = "Wecker 3" },
  { g = "bells", c = "TELL_MESSAGE", id = 3081, name = "Flüstern" },
  { g = "bells", c = "UI_EVENT_SCHEDULER_CHIME", id = 278769, name = "Glockenspiel (Terminplaner)" },
  { g = "bells", c = "UI_BNET_TOAST", id = 18019, name = "Battle.net-Hinweis" },
  { g = "bells", c = "UI_71_SOCIAL_QUEUEING_TOAST", id = 79739, name = "Gruppensuche-Hinweis" },
  { g = "bells", c = "LFG_ROLE_CHECK", id = 17317, name = "Rollencheck" },
  { g = "bells", c = "UI_ORDERHALL_TALENT_READY_CHECK", id = 73281, name = "Talent bereit" },
  { g = "bells", c = "RAID_BOSS_EMOTE_WARNING", id = 12197, name = "Boss-Warnung" },
  { g = "bells", c = "UI_GARRISON_TOAST_INVASION_ALERT", id = 44292, name = "Invasionsalarm" },
  { g = "fanfare", c = "UI_GARRISON_MISSION_COMPLETE_MISSION_SUCCESS", id = 43502, name = "Mission erfolgreich (Fanfare)" },
  { g = "fanfare", c = "UI_GARRISON_COMMAND_TABLE_MISSION_SUCCESS_STINGER", id = 44330, name = "Missionserfolg (kurz)" },
  { g = "fanfare", c = "UI_GARRISON_TOAST_MISSION_COMPLETE", id = 44294, name = "Mission abgeschlossen" },
  { g = "fanfare", c = "UI_GARRISON_TOAST_BUILDING_COMPLETE", id = 44295, name = "Gebäude fertig" },
  { g = "fanfare", c = "UI_GARRISON_TOAST_FOLLOWER_GAINED", id = 44296, name = "Anhänger gewonnen" },
  { g = "fanfare", c = "UI_GARRISON_COMMAND_TABLE_FOLLOWER_LEVEL_UP", id = 46893, name = "Anhänger steigt auf" },
  { g = "fanfare", c = "UI_EPICLOOT_TOAST", id = 31578, name = "Epische Beute" },
  { g = "fanfare", c = "UI_LEGENDARY_LOOT_TOAST", id = 63971, name = "Legendäre Beute" },
  { g = "fanfare", c = "UI_RAID_BOSS_DEFEATED", id = 50111, name = "Boss besiegt" },
  { g = "fanfare", c = "UI_DIG_SITE_COMPLETION_TOAST", id = 38326, name = "Grabungsstätte abgeschlossen" },
  { g = "fanfare", c = "LFG_REWARDS", id = 17316, name = "Belohnung (Dungeonbrowser)" },
  { g = "fanfare", c = "UI_MISSION_SUCCESS_CHEERS", id = 74702, name = "Jubel" },
  { g = "fanfare", c = "UI_CHALLENGES_NEW_RECORD", id = 33338, name = "Neuer Rekord" },
  { g = "fanfare", c = "UI_PVP_HONOR_PRESTIGE_RANK_UP", id = 77003, name = "Ehrenrang aufgestiegen" },
  { g = "fanfare", c = "UI_ADVENTURES_ADVENTURER_LEVEL_UP", id = 167127, name = "Abenteurer steigt auf" },
  { g = "fanfare", c = "UI_ADVENTURES_ADVENTURE_SUCCESS_COMPLETE", id = 165974, name = "Abenteuer gelungen" },
  { g = "fanfare", c = "TRADING_POST_UI_PURCHASE_CELEBRATION", id = 218231, name = "Kauf gefeiert (Handelsposten)" },
  { g = "fanfare", c = "TRADING_POST_UI_REWARD_TIER_COMPLETE", id = 218238, name = "Belohnungsstufe erreicht" },
  { g = "fanfare", c = "TRADING_POST_UI_COMPLETED_ACTIVITY_TOAST", id = 219929, name = "Aktivität abgeschlossen" },
  { g = "fanfare", c = "UI_PROFESSIONS_NEW_RECIPE_LEARNED_TOAST", id = 73919, name = "Neues Rezept gelernt" },
  { g = "fanfare", c = "UI_HERO_TALENTS_UNLOCKED", id = 283863, name = "Heldentalente freigeschaltet" },
  { g = "fanfare", c = "UI_CLASS_TALENT_APPLY_COMPLETE", id = 212391, name = "Talente übernommen" },
  { g = "magic", c = "UI_70_ARTIFACT_FORGE_TOAST_TRAIT_AVAILABLE", id = 54133, name = "Artefakt-Eigenschaft verfügbar" },
  { g = "magic", c = "UI_70_ARTIFACT_FORGE_APPEARANCE_APPEARANCE_UNLOCK", id = 54139, name = "Artefakt-Aussehen freigeschaltet" },
  { g = "magic", c = "UI_72_ARTIFACT_FORGE_FINAL_TRAIT_UNLOCKED", id = 83682, name = "Letzte Artefakt-Eigenschaft" },
  { g = "magic", c = "UI_82_HEARTOFAZEROTH_UNLOCKESSENCESLOT", id = 137378, name = "Essenzplatz freigeschaltet" },
  { g = "magic", c = "UI_82_HEARTOFAZEROTH_SLOTESSENCE", id = 131809, name = "Essenz eingesetzt" },
  { g = "magic", c = "UI_80_AZERITEARMOR_FIRSTTIMEFLOURISH", id = 118264, name = "Azerit-Aufblühen" },
  { g = "magic", c = "UI_80_AZERITEARMOR_SELECTBUFF", id = 114993, name = "Azerit-Kraft gewählt" },
  { g = "magic", c = "UI_RUNECARVING_CREATE_COMPLETE", id = 166318, name = "Runenschnitzerei fertig" },
  { g = "magic", c = "UI_RUNECARVING_UPGRADE_COMPLETE", id = 166342, name = "Runenschnitzerei verbessert" },
  { g = "magic", c = "UI_COVENANT_SANCTUM_UNLOCK_UPGRADE", id = 170886, name = "Sanktum-Verbesserung" },
  { g = "magic", c = "UI_COVENANT_CHOICE_CELEBRATION_ANIMATION_BASTION", id = 171877, name = "Feier: Bastion" },
  { g = "magic", c = "UI_COVENANT_CHOICE_CELEBRATION_ANIMATION_ARDENWEALD", id = 171878, name = "Feier: Ardenwald" },
  { g = "magic", c = "UI_COVENANT_CHOICE_CELEBRATION_ANIMATION_REVENDRETH", id = 171876, name = "Feier: Revendreth" },
  { g = "magic", c = "UI_COVENANT_CHOICE_CELEBRATION_ANIMATION_MALDRAXXUS", id = 170833, name = "Feier: Maldraxxus" },
  { g = "magic", c = "ENCHANTMENT_ENCHANT_ANIMATION_START", id = 254764, name = "Verzauberung" },
  { g = "magic", c = "UI_ITEM_UPGRADE_UI_ITEM_UPGRADED_RARE", id = 187607, name = "Aufwertung (selten)" },
  { g = "magic", c = "UI_ITEM_UPGRADE_UI_ITEM_UPGRADED_EPIC", id = 187610, name = "Aufwertung (episch)" },
  { g = "magic", c = "UI_TRANSMOG_APPLY", id = 62542, name = "Transmogrifikation" },
  { g = "magic", c = "CATALOG_SHOP_GOLD_SHIMMER_START", id = 306261, name = "Goldschimmer" },
  { g = "magic", c = "JEWEL_CRAFTING_FINALIZE", id = 10590, name = "Juwelenschleifen vollendet" },
}

local byId = {}
for _, e in ipairs(SoundKits.LIST) do byId[e.id] = e end

local T
do
  local de = {}
  for _, g in ipairs(SoundKits.GROUPS) do de["g_" .. g.key] = g.label end
  for _, e in ipairs(SoundKits.LIST) do de["k" .. e.id] = e.name end
  T = ns.Locale.ns("SoundKits", de)
end

function SoundKits.nameOf(e)
  if type(e) ~= "table" then return "?" end
  return T["k" .. tostring(e.id)]
end

function SoundKits.groupLabel(g)
  if type(g) ~= "table" then return "?" end
  return T["g_" .. tostring(g.key)]
end

function SoundKits.byId(id)
  if type(id) ~= "number" then return nil end
  return byId[id]
end

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

function SoundKits.idOf(e)
  if type(e) ~= "table" then return nil end
  local kit = type(SOUNDKIT) == "table" and SOUNDKIT or nil
  local v = kit and e.c and kit[e.c] or nil
  if not isSecret(v) and type(v) == "number" and v > 0 and v == math.floor(v) then return v end
  return e.id
end
