-- Schema, character entry, block log, trail stream, text tables, snapshots, screenshots, counters, sessions, flush.
-- Storage format schema 1 (binding, see README 'Log-Format (Vertrag)'). Collectors write only through this API, never to EveNChronicleDB directly.
local _, ns = ...

local Store = {}
ns.Store = Store

local floor, concat, format = math.floor, table.concat, string.format

Store.BLOCK_LINES = 500    -- lines per log block
Store.TRAIL_POINTS = 500   -- points per trail block
Store.RELOAD_WINDOW = 600  -- seconds: fallback reload detection without PLAYER_ENTERING_WORLD arguments
Store.DECIMALS = 2         -- fixed decimals in snapshots
Store.TEXT_TABLES = { quests = true, books = true, npcs = true }
-- Soft caps (protection against bloat from foreign data): new entries above them are not created; diag.limits[<table>] notes when.
-- Existing entries and fields stay unchanged. maps, zones, subzones, instances and encounters apply to snapshots[<group>] (Store.SNAPSHOT_LIMITED).
Store.LIMITS = {
  quests = 2000, books = 500, npcs = 5000, maps = 3000, zones = 3000, subzones = 5000, instances = 500, encounters = 1000,
  items = 6000, spells = 2000, factions = 500, skills = 300, talentNodes = 500, talents = 300, mailseen = 2000,
}
Store.SNAPSHOT_LIMITED = {
  maps = true, zones = true, subzones = true, instances = true, encounters = true,
  items = true, spells = true, factions = true, skills = true, talentNodes = true, talents = true, mailseen = true,
}
Store.COUNTER_KEYS = 2000      -- keys per counter group (default)
-- Other caps per counter group: loot (one itemID per item) and consumables grow fastest over a journey, so they get more room.
Store.COUNTER_LIMITS = { loot = 6000, consumables = 6000 }
-- fields always stored short and single-line (names, titles): Sanitize.field instead of long text
Store.SHORT_FIELDS = { title = true, giver = true, material = true, name = true, questLineName = true, category = true }
Store.CHAR_TABLES = { "info", "log", "trail", "quests", "books", "npcs", "counters", "snapshots", "shots" }

Store.sizes = {}   -- entry counts (see sizeOf)
Store.dropped = 0 -- lines that arrived before login or after logout (not stored)
-- Optional observer: Store.observer = function(code, fields) ... end, called under pcall after every stored append.
-- fields = the line's field texts as in the log (sanitized, '?' for secret, '' for empty, trailing empties dropped).
-- Observer errors count in Store.observerErrors (and diag.limits.observer_error) and abort nothing; appends from the observer do not notify again.
Store.observer = nil
Store.observerErrors = 0
local notifying = false

-- Type codes of all log lines (single source; the README table is generated from it: npm run types-doc).
-- fields: list of { name, description } in line order after '<dt>~<code>~'.
ns.Types = {
  L = { order = 10, name = "Login", desc = "Neue Sitzung beginnt (Einloggen).", fields = {
    { "session", "Sitzungsnummer (Index in meta.sessions)" },
    { "build", "Client-Version, z. B. 12.1.5" },
    { "buildNumber", "Build-Nummer, z. B. 70575" },
    { "interface", "Interface-Nummer (16001 Forever, 120105 Retail)" },
    { "locale", "Client-Sprache, z. B. deDE" },
    { "tz", "Zeitzonen-Versatz in Sekunden (Ortszeit minus UTC)" },
  } },
  R = { order = 20, name = "Reload", desc = "Dieselbe Sitzung geht nach einem Reload (Sichern, /reload) weiter.", fields = {
    { "session", "Sitzungsnummer" },
  } },
  S = { order = 30, name = "Gesichert", desc = "Die Oberfläche wird neu geladen, die Daten sind bis hier gesichert. Danach folgt R in derselben Sitzung.", fields = {
    { "session", "Sitzungsnummer" },
  } },
  O = { order = 40, name = "Logout", desc = "Sitzung endet (Ausloggen oder Beenden).", fields = {
    { "session", "Sitzungsnummer" },
    { "duration", "Dauer der Sitzung in Sekunden" },
  } },
  X = { order = 50, name = "Sitzung unterbrochen", desc = "Beim nächsten Login fehlte das Ende der Sitzung (Absturz). Steht als eigener Ein-Zeilen-Block im Log des betroffenen Charakters.", fields = {
    { "session", "Nummer der unterbrochenen Sitzung" },
    { "lastKnown", "letzte bekannte Zeit (Epoch, letzte Sicherung)" },
  } },

  -- Progress: position = map fraction in tenths of a permille (0-9999) on map mapID; map names are in snapshots.maps[mapID].name.
  LV = { order = 100, name = "Level-Up", desc = "Der Charakter hat eine neue Stufe erreicht.", fields = {
    { "level", "neue Stufe" },
    { "mapID", "Karte (uiMapID) am Ort des Level-Ups; Name in snapshots.maps" },
    { "x", "Position West-Ost auf dieser Karte (0-9999)" },
    { "y", "Position Nord-Süd auf dieser Karte (0-9999)" },
    { "sub", "Name der Unterzone (GetSubZoneText, gesäubert, höchstens 60 Bytes), leer wenn ohne Namen oder nicht lesbar" },
  } },
  PL = { order = 110, name = "Spielzeit", desc = "Antwort auf /played (nach Login, Reload und Level-Up angefragt; beim Logout nicht, dort kommt keine Antwort mehr an).", fields = {
    { "total", "gesamte Spielzeit in Sekunden" },
    { "thisLevel", "Spielzeit auf der aktuellen Stufe in Sekunden" },
    { "level", "Stufe des Charakters" },
    { "reason", "Anlass: login, reload, levelup oder leer (andere Anfrage, z. B. eigenes /played)" },
  } },
  XP = { order = 120, name = "Erfahrung", desc = "Ein Erfahrungsgewinn. Zweigleisig erfasst: aus der Chat-Meldung (msg) und als Kontrolle aus der Differenz von PLAYER_XP_UPDATE (diff). Jeder Gewinn steht genau einmal da.", fields = {
    { "source", "Quelle: kill, quest, explore oder other (nur als Differenz erkannt oder nicht zuzuordnen)" },
    { "amount", "Erfahrungspunkte (bei Meldungen der Wert aus der Meldung, bei Differenz die gemessene Änderung); leer bei via unclear" },
    { "rested", "Ruhebonus in Punkten (negativ = Abzug), leer wenn keiner genannt" },
    { "group", "Gruppenbonus in Punkten (negativ = Schlachtzugsmalus), leer wenn keiner" },
    { "target", "Name des getöteten Gegners (kill) bzw. der entdeckten Zone (explore)" },
    { "questID", "Quest, für die die Erfahrung kam (quest), wenn zuordenbar" },
    { "level", "Stufe des Charakters" },
    { "mapID", "Karte (uiMapID), auf der der Gewinn kam" },
    { "via", "Erfassungsweg: msg (Chat-Meldung), diff (nur Differenz) oder unclear (Mehrfach-Stufensprung, Betrag unbekannt, nicht gebucht)" },
  } },
  RS = { order = 130, name = "Ruhezustand", desc = "Ruhe-Erfahrung und Ruhezustand beim Einloggen, Neuladen und Ausloggen.", fields = {
    { "reason", "Anlass: login, reload oder logout" },
    { "rested", "angesammelte Ruhe-Erfahrung in Punkten (leer = keine)" },
    { "resting", "1 = in einem Ruhegebiet (Gasthaus, Stadt), 0 = nicht" },
    { "xp", "Erfahrung auf der aktuellen Stufe" },
    { "xpMax", "Erfahrung, die für die nächste Stufe nötig ist" },
    { "level", "Stufe des Charakters" },
  } },

  -- Quests: the texts are not in the log but in quests[questID] (see long texts).
  QA = { order = 200, name = "Quest angenommen", desc = "Eine Quest wurde angenommen.", fields = {
    { "questID", "Quest-ID; Titel und Texte in quests[questID]" },
    { "level", "Stufe des Charakters" },
    { "qlevel", "Stufe der Quest (leer, wenn nicht lesbar)" },
    { "mapID", "Karte (uiMapID) bei der Annahme" },
    { "npcID", "Questgeber (npcID); Name in npcs[npcID]" },
    { "npc", "Name des Questgebers, nur wenn er keine npcID hat (Objekt, Gegenstand)" },
    { "x", "Spielerposition West-Ost (0-9999), leer wenn nicht lesbar" },
    { "y", "Position Nord-Süd (0-9999), leer wenn nicht lesbar" },
  } },
  QT = { order = 210, name = "Quest abgegeben", desc = "Eine Quest wurde abgegeben.", fields = {
    { "questID", "Quest-ID" },
    { "level", "Stufe des Charakters" },
    { "qlevel", "Stufe der Quest (leer, wenn nicht lesbar)" },
    { "mapID", "Karte (uiMapID) bei der Abgabe" },
    { "xp", "Erfahrung aus der Quest (laut Spiel, ohne Ruhebonus)" },
    { "money", "Geld aus der Quest in Kupfer" },
    { "itemID", "gewähltes Belohnungs-Item (itemID), leer wenn keine Wahl" },
    { "npcID", "Abgabe-NPC (npcID); Name in npcs[npcID]" },
    { "npc", "Name des Abgabe-NPCs, nur wenn er keine npcID hat" },
    { "x", "Spielerposition West-Ost (0-9999), leer wenn nicht lesbar" },
    { "y", "Position Nord-Süd (0-9999), leer wenn nicht lesbar" },
  } },
  QR = { order = 220, name = "Belohnung nachgetragen", desc = "Das gewählte Belohnungs-Item wurde erst nach der Abgabe-Zeile erkannt.", fields = {
    { "questID", "Quest-ID" },
    { "itemID", "gewähltes Belohnungs-Item (itemID)" },
  } },
  QX = { order = 230, name = "Quest abgebrochen", desc = "Eine Quest verschwand aus dem Questlog, ohne abgegeben worden zu sein.", fields = {
    { "questID", "Quest-ID" },
    { "level", "Stufe des Charakters" },
    { "qlevel", "Stufe der Quest (leer, wenn nicht lesbar)" },
    { "mapID", "Karte (uiMapID) beim Abbruch" },
    { "confirmed", "1 = Abbrechen-Knopf wurde erkannt, 0 = nur aus dem Verschwinden der Quest geschlossen" },
  } },
  QO = { order = 240, name = "Questziel-Fortschritt", desc = "Ein Questziel ist vorangekommen (have gestiegen; Ereignisse gebündelt, je Ziel höchstens need bzw. 100 Zeilen, der Endstand have >= need aber immer einmal). Der Stand bei Login, Reload und Annahme wird nicht geschrieben.", fields = {
    { "questID", "Quest-ID" },
    { "idx", "Nummer des Ziels in der Quest (ab 1, Reihenfolge von C_QuestLog.GetQuestObjectives)" },
    { "have", "erreichter Stand nach dem Schritt (bei Fortschrittsbalken Prozent)" },
    { "need", "benötigter Stand (bei Fortschrittsbalken 100), leer wenn nicht lesbar" },
    { "kind", "Zielart laut Spiel: monster, item, object, event, reputation, log, progressbar, …; leer wenn nicht lesbar" },
    { "text", "Zielname ohne Zähler (gesäubert, höchstens 80 Bytes), leer wenn nicht lesbar" },
    { "mapID", "Karte (uiMapID) beim Schritt" },
    { "px", "Spielerposition West-Ost (0-9999), leer wenn nicht lesbar" },
    { "py", "Position Nord-Süd (0-9999), leer wenn nicht lesbar" },
  } },

  -- Books: the full text is in books[key] as fields p1, p2, ... (see long texts).
  BK = { order = 300, name = "Buch gelesen", desc = "Eine Buch-, Brief- oder Schildseite wurde gelesen (in einer Lesesitzung je Seite einmal).", fields = {
    { "key", "Schlüssel des Buches in books (stabiler Hash aus Titel und erster Seite)" },
    { "page", "Seitennummer (ab 1)" },
    { "level", "Stufe des Charakters" },
    { "mapID", "Karte (uiMapID) am Leseort" },
    { "new", "1 = Text dieser Seite wurde neu archiviert, 0 = war schon gespeichert (je Buch und Seite höchstens einmal je Login)" },
  } },

  -- Combat: no combat log (CLEU is blocked): kills from PARTY_KILL, name/level from a unit cache.
  KI = { order = 400, name = "Kill", desc = "Ein Gegner wurde von Euch, Eurem Begleiter oder der Gruppe getötet. Der Name steht in npcs[npcID]. Bis zu 1 s verzögert geschrieben, damit die Kill-Erfahrung dazukommt.", fields = {
    { "npcID", "Gegner (npcID aus der GUID); ? = in der Instanz nicht lesbar" },
    { "level", "Stufe des Gegners (-1 = Boss/??), leer wenn unbekannt" },
    { "cls", "Klassifikation: normal, elite, rare, rareelite, worldboss, trivial, minus; leer wenn unbekannt" },
    { "mapID", "Karte (uiMapID) beim Kill" },
    { "xp", "Erfahrung aus der Kill-Meldung, leer wenn keine kam" },
    { "by", "Todesstoß: self (Ihr), pet (Begleiter), group (Gruppenmitglied); ? = nicht lesbar" },
    { "via", "Erkennung: pk (PARTY_KILL), died (UNIT_DIED plus Erfahrungsmeldung) oder xp (nur Erfahrungsmeldung)" },
    { "name", "Name des Gegners, nur wenn es keine npcID gibt (leer = unbekannt)" },
    { "plevel", "Stufe des Charakters" },
    { "x", "Position des Charakters beim Kill, West-Ost (0-9999); leer, wenn die Karte sie nicht herausgibt (meist in Instanzen). Ältere Zeilen aus der Zeit vor Nachtrag N1 trugen x/y nur bei Rare/Elite/Boss; Leser behandeln fehlende Felder wie leere" },
    { "y", "Position des Charakters beim Kill, Nord-Süd (0-9999); leer wie x" },
  } },
  KF = { order = 410, name = "Kampf", desc = "Ein Kampf ist zu Ende (PLAYER_REGEN_ENABLED). Schaden und Heilung aus dem Schadensmesser, wenn lesbar.", fields = {
    { "duration", "Dauer in Sekunden" },
    { "kills", "getötete Gegner in diesem Kampf (KI-Zeilen)" },
    { "damage", "verursachter Schaden (Schadensmesser), leer wenn nicht lesbar" },
    { "healing", "Heilung (Schadensmesser), leer wenn nicht lesbar" },
    { "taken", "erlittener Schaden (Schadensmesser), leer wenn nicht lesbar" },
    { "hpEnd", "Leben am Kampfende in Prozent (Näherung: das Minimum im Kampf ist nicht lesbar); ? = gesperrt" },
    { "close", "1 = knapper Sieg (Näherung: unter 10 % Leben am Kampfende, nicht tot)" },
    { "dead", "1 = Ihr seid in diesem Kampf gestorben" },
    { "level", "Stufe des Charakters" },
    { "mapID", "Karte (uiMapID) am Kampfende" },
  } },

  -- Death: death report from C_DeathRecap, one DR line per hit after DE.
  DE = { order = 500, name = "Tod", desc = "Ihr seid gestorben. Danach folgen die DR-Zeilen (Todesbericht), eine DC-Zeile (Ursache) und später DB (Wiederbelebung).", fields = {
    { "level", "Stufe des Charakters" },
    { "mapID", "Karte (uiMapID) am Todesort" },
    { "x", "Position West-Ost (0-9999)" },
    { "y", "Position Nord-Süd (0-9999)" },
    { "instance", "1 = in einer Instanz" },
    { "combat", "1 = im Kampf gestorben" },
    { "sub", "Name der Unterzone (GetSubZoneText, gesäubert, höchstens 60 Bytes), leer wenn ohne Namen oder nicht lesbar" },
  } },
  DR = { order = 510, name = "Todesbericht-Treffer", desc = "Ein Eintrag des Todesberichts (C_DeathRecap), in der Reihenfolge des Clients.", fields = {
    { "ago", "Zehntelsekunden vor dem letzten Treffer (0 = Todesstoß)" },
    { "event", "Ereignisart, z. B. SWING_DAMAGE, SPELL_DAMAGE, ENVIRONMENTAL_DAMAGE; ? = gesperrt (ganz gesperrter Eintrag: nur event = ?)" },
    { "npcID", "Verursacher (npcID), Name in npcs[npcID]" },
    { "source", "Name des Verursachers, nur ohne npcID (z. B. Spieler)" },
    { "spellID", "Zauber (spellID), leer bei Nahkampf" },
    { "amount", "Schaden" },
    { "overkill", "Überschaden" },
    { "school", "Schadensschule (Bitmaske)" },
    { "crit", "1 = kritischer Treffer" },
    { "hp", "Euer Leben laut Todesbericht, vermutlich vor dem Treffer (Wert des Clients)" },
    { "env", "Umgebungsschaden-Art (z. B. Falling, Drowning), wenn genannt; ? = gesperrt" },
  } },
  DC = { order = 520, name = "Todesursache", desc = "Zusammenfassung des Todes. Ohne lesbaren Bericht wird die Ursache vermutet (guess = 1).", fields = {
    { "npcID", "Verursacher des Todesstoßes (npcID)" },
    { "source", "Name des Verursachers, nur ohne npcID" },
    { "spellID", "Zauber des Todesstoßes" },
    { "cause", "Ursache: enemy, fall, drown, fatigue, lava, fire, slime, environment oder leer (unbekannt)" },
    { "guess", "1 = Ursache vermutet (Atemleiste bzw. Tod ohne Kampf und ohne Bericht)" },
    { "events", "Zahl der Einträge im Todesbericht; ? = gesperrt" },
    { "maxHP", "maximales Leben laut Todesbericht" },
  } },
  DB = { order = 530, name = "Wiederbelebung", desc = "Ihr lebt wieder.", fields = {
    { "how", "Weg: corpse (Leichenlauf), spirit (Geistheiler), res (Wiederbelebung durch andere oder Seelenstein), unknown" },
    { "guess", "1 = Weg vermutet" },
    { "seconds", "Sekunden seit dem Tod" },
    { "mapID", "Karte (uiMapID) bei der Wiederbelebung" },
    { "x", "Position West-Ost (0-9999)" },
    { "y", "Position Nord-Süd (0-9999)" },
  } },

  -- World: map names in snapshots.maps, visited maps and subzones in snapshots.zones/subzones.
  ZN = { order = 600, name = "Neue Karte", desc = "Erste Ankunft auf einer Karte (Zone, Höhle, Stadt, Instanzkarte).", fields = {
    { "mapID", "Karte (uiMapID)" },
    { "mapType", "Kartentyp: 2 Kontinent, 3 Zone, 4 Dungeon, 5 Mikrokarte, 6 sonstige" },
    { "zone", "zugehörige Hauptzone (uiMapID), leer wenn keine" },
    { "continent", "zugehöriger Kontinent (uiMapID), leer wenn keiner" },
    { "level", "Stufe des Charakters" },
    { "x", "Position West-Ost (0-9999)" },
    { "y", "Position Nord-Süd (0-9999)" },
  } },
  SZ = { order = 610, name = "Neue Unterzone", desc = "Erste Ankunft in einer Unterzone (Name laut Client).", fields = {
    { "mapID", "Karte (uiMapID)" },
    { "name", "Name der Unterzone" },
    { "level", "Stufe des Charakters" },
  } },
  EX = { order = 620, name = "Entdeckt", desc = "Systemmeldung über ein entdecktes Gebiet (mit oder ohne Erfahrung).", fields = {
    { "name", "Name des Gebiets laut Meldung" },
    { "xp", "Erfahrung laut Meldung, leer wenn keine" },
    { "mapID", "Karte (uiMapID)" },
    { "level", "Stufe des Charakters" },
  } },
  FP = { order = 630, name = "Neuer Flugpunkt", desc = "Meldung 'Neue Flugroute entdeckt'. Der Flugmeister ist der Gesprächspartner.", fields = {
    { "npcID", "Flugmeister (npcID), Name in npcs[npcID]" },
    { "mapID", "Karte (uiMapID)" },
    { "x", "Position West-Ost (0-9999)" },
    { "y", "Position Nord-Süd (0-9999)" },
    { "level", "Stufe des Charakters" },
    { "name", "Name des Flugmeisters, nur ohne npcID" },
  } },

  -- Trail: the points are in the own stream chars[guid].trail, the log only holds the pause.
  TP = { order = 650, name = "Spur pausiert", desc = "Die Positionsspur pausiert (eine Zeile je Pause).", fields = {
    { "reason", "instance (Instanz ohne Position), taxi (im Flug) oder unreadable (Position gesperrt)" },
    { "mapID", "Karte (uiMapID), wenn bekannt" },
  } },

  TF = { order = 700, name = "Flug gestartet", desc = "Ein Flug hat begonnen (nach TakeTaxiNode, sobald Ihr in der Luft seid).", fields = {
    { "from", "Name des Start-Flugpunkts" },
    { "to", "Name des Ziel-Flugpunkts" },
    { "cost", "Kosten in Kupfer" },
    { "fromNode", "Start-Knoten (nodeID), leer wenn nicht lesbar" },
    { "toNode", "Ziel-Knoten (nodeID), leer wenn nicht lesbar" },
    { "mapID", "Karte (uiMapID) beim Abflug" },
  } },
  TL = { order = 710, name = "Flug gelandet", desc = "Der Flug ist zu Ende.", fields = {
    { "seconds", "Flugdauer in Sekunden" },
    { "mapID", "Karte (uiMapID) bei der Landung" },
    { "x", "Position West-Ost (0-9999)" },
    { "y", "Position Nord-Süd (0-9999)" },
  } },
  HS = { order = 720, name = "Ruhestein", desc = "Ruhestein, Astraler Rückruf oder Ruhestein-Spielzeug benutzt.", fields = {
    { "spellID", "Zauber (echte ID: 8690 Ruhestein, 556 Astraler Rückruf, sonst das Spielzeug)" },
    { "bind", "Ziel: gebundener Ort laut Client, leer bei Spielzeugen mit eigenem Ziel (Garnison, Dalaran)" },
    { "mapID", "Karte (uiMapID) beim Wirken" },
    { "x", "Position West-Ost (0-9999), leer wenn nicht lesbar" },
    { "y", "Position Nord-Süd (0-9999), leer wenn nicht lesbar" },
  } },
  HB = { order = 730, name = "Neues Zuhause", desc = "Der Ruhestein wurde neu gebunden.", fields = {
    { "bind", "Name des neuen Zuhauses" },
    { "mapID", "Karte (uiMapID)" },
  } },
  TB = { order = 740, name = "Überfahrt (vermutet)", desc = "Kontinentwechsel ohne Flug, Ruhestein, Tod oder Instanz, vermutlich Schiff oder Zeppelin.", fields = {
    { "fromMap", "letzte Karte vorher (uiMapID)" },
    { "toMap", "Karte danach (uiMapID)" },
    { "fromContinent", "Kontinent vorher (uiMapID)" },
    { "toContinent", "Kontinent danach (uiMapID)" },
  } },

  -- Instances: names in snapshots.instances[instanceID].name and snapshots.encounters[encounterID].name.
  IE = { order = 800, name = "Instanz betreten", desc = "Ihr seid in einer Instanz (auch nach Login oder Reload darin, dann resumed = 1).", fields = {
    { "instanceID", "Instanz (instanceID laut GetInstanceInfo)" },
    { "type", "party, raid, pvp, arena oder scenario" },
    { "difficultyID", "Schwierigkeitsgrad (difficultyID)" },
    { "group", "Zahl der Gruppenmitglieder" },
    { "level", "Stufe des Charakters" },
    { "pos", "1 = Position lesbar, 0 = in der Instanz nicht lesbar" },
    { "mapLock", "Addon-Sperre Karte (C_RestrictedActions: 0 aus, 1 startet, 2 aktiv); leer wenn unbekannt" },
    { "chatLock", "Addon-Sperre Chat (wie mapLock)" },
    { "resumed", "1 = der Besuch lief schon vor dem Reload bzw. Login" },
  } },
  IL = { order = 810, name = "Instanz verlassen", desc = "Ihr habt die Instanz verlassen.", fields = {
    { "instanceID", "Instanz" },
    { "seconds", "Dauer des Besuchs in Sekunden" },
    { "kills", "Kills im Besuch" },
    { "deaths", "eigene Tode im Besuch" },
    { "bosses", "besiegte Bosse im Besuch" },
    { "loot", "Funde ab Qualität Grün im Besuch (Stückzahl, aus LT)" },
  } },
  IB = { order = 820, name = "Boss-Kampf", desc = "Ende einer Boss-Begegnung (ENCOUNTER_END), falls der Client sie meldet.", fields = {
    { "encounterID", "Begegnung (encounterID)" },
    { "success", "1 = besiegt, 0 = gescheitert" },
    { "seconds", "Dauer in Sekunden (seit ENCOUNTER_START), leer wenn unbekannt" },
    { "group", "Gruppengröße laut Event" },
    { "difficultyID", "Schwierigkeitsgrad" },
    { "instanceID", "Instanz" },
  } },

  MO = { order = 900, name = "Moment", desc = "Ein Chronik-Moment (Meilenstein). Erste Male stehen zusätzlich in snapshots.moments[kind].", fields = {
    { "kind", "level, kill (Rare/Elite/Boss; Elite nicht in Instanzen, F16), first_rare, first_elite, first_boss, close_win, first_death, continent, first_dungeon, first_raid, boss, first_blue (erster blauer Gegenstand), first_epic (erster lila oder besserer), first_bag (erste Tasche), first_fish (erster Fang beim Angeln), mount (Reittier gelernt), reputation (Rufstufe), profession (Beruf neu oder Stufe 75/150/225/300)" },
    { "value", "Wert: Stufe (level), npcID (kill, first_*), HP-Prozent (close_win), mapID (continent), instanceID (first_dungeon, first_raid), encounterID (boss), itemID (first_blue, first_epic, first_bag, first_fish), Zauber- bzw. Reittier-ID oder Name (mount), factionID oder Name (reputation), Name der Fertigkeit (profession)" },
    { "detail", "level: 1 = hervorgehobene Stufe (10, 20, ... 60); kill und first_*: Klassifikation; close_win: 1 = Näherung; first_blue, first_epic: Qualität; mount: Name; reputation: neue Rufstufe (1-8); profession: Wert der Fertigkeit" },
    { "level", "Stufe des Charakters" },
    { "mapID", "Karte (uiMapID)" },
    { "sub", "Name der Unterzone (GetSubZoneText, gesäubert, höchstens 60 Bytes), leer wenn ohne Namen oder nicht lesbar" },
  } },
  SH = { order = 910, name = "Screenshot", desc = "Ein Screenshot wurde gespeichert (SCREENSHOT_SUCCEEDED). Datei WoWScrnShot_<key>.jpg (Ortszeit), Eintrag in shots[key].", fields = {
    { "key", "MMDDYY_HHMMSS (Ortszeit), Schlüssel in shots" },
    { "reasons", "Anlässe, durch Komma getrennt: levelup, zone, kill, boss, close_win, death, item (erstes Blau/Lila, Reittier); manual = selbst ausgelöst" },
    { "auto", "1 = vom Addon ausgelöst, 0 = selbst ausgelöst" },
    { "level", "Stufe des Charakters" },
    { "mapID", "Karte (uiMapID)" },
    { "x", "Position West-Ost (0-9999), leer wenn nicht lesbar" },
    { "y", "Position Nord-Süd (0-9999), leer wenn nicht lesbar" },
    { "sub", "Name der Unterzone (GetSubZoneText, gesäubert, höchstens 60 Bytes), leer wenn ohne Namen oder nicht lesbar" },
  } },

  -- Economy (Money): amounts in copper; sources/purposes: see GD.source.
  GD = { order = 1000, name = "Gold-Änderung", desc = "Das Geld des Charakters hat sich geändert (PLAYER_MONEY). Quelle bzw. Zweck aus offenen Fenstern und Kontext. Summen je Quelle stehen in counters.money_in und counters.money_out.", fields = {
    { "delta", "Änderung in Kupfer (negativ = Ausgabe); leer bei source = start" },
    { "balance", "Geld nach der Änderung in Kupfer" },
    { "source", "Quelle (Einnahme) bzw. Zweck (Ausgabe): loot, quest, vendor_sell, vendor_buy, repair (Alle reparieren per Hook; Einzelreparatur nur als Näherung: Händler offen und Reparatur-Cursor aktiv), training, taxi, ah, ah_sale, mail, trade, guildbank, other; start (erster Stand), gap (Änderung zwischen letzter Sicherung und Login, z. B. nach einem Absturz)" },
    { "level", "Stufe des Charakters" },
    { "mapID", "Karte (uiMapID)" },
  } },
  AH = { order = 1010, name = "Auktionshaus", desc = "Ein Vorgang im Auktionshaus. post/bid/buy/cancel kommen aus den Aktionen im Fenster, sold/bought aus den Rechnungen der Post (nur wenn die API sie liefert).", fields = {
    { "action", "post (eingestellt), bid (Gebot; auch ein Sofortkauf läuft über PlaceBid und steht hier als bid, die Rechnung liefert später bought), buy (Kauf), cancel (abgebrochen), sold (verkauft laut Rechnung), bought (gekauft laut Rechnung)" },
    { "itemID", "Gegenstand (itemID), leer wenn nicht lesbar" },
    { "name", "Gegenstandsname, nur wenn keine itemID bekannt ist (Rechnungen)" },
    { "count", "Menge" },
    { "price", "Preis in Kupfer: post Sofortkauf bzw. Stückpreis, bid Gebot, buy Stückpreis (Rohstoffe) bzw. Gesamtpreis, sold/bought Verkaufs- bzw. Kaufpreis" },
    { "deposit", "Pfand in Kupfer (post) bzw. Gebühr/Provision (sold)" },
    { "hours", "Laufzeit in Stunden (post)" },
    { "partner", "Käufer bzw. Verkäufer laut Rechnung" },
    { "level", "Stufe des Charakters" },
    { "mapID", "Karte (uiMapID)" },
  } },

  -- Loot: from green quality individually, below only counters (counters.loot). Item key: <itemID>[.s<suffix>][.b<bonusID>...].
  LT = { order = 1100, name = "Fund", desc = "Ein Gegenstand ab Qualität Grün (oder mit unbekannter Qualität) wurde erhalten. Name und Qualität stehen in snapshots.items. Gegenstände darunter zählen nur in counters.loot (bzw. bought, crafted, received, quest_items).", fields = {
    { "item", "Item-Schlüssel: itemID, dann optional .s<Zufallszusatz> und .b<Bonus-ID> (z. B. 2589 oder 1369.s-37.b1486); keine kompletten Links" },
    { "count", "Menge" },
    { "quality", "Qualität: 0 grau, 1 weiß, 2 grün, 3 blau, 4 lila, 5 orange; leer wenn unbekannt" },
    { "source", "Quelle: mob, object, container, fishing (aus dem Beutefenster); vendor, quest, craft, mail, trade, ah, bonus, other (ohne Beutefenster)" },
    { "srcID", "bei mob die npcID (leer, wenn die Quelle nicht lesbar war und die Zuordnung nur aus einem Kill stammt), bei object die Objekt-ID. mob ohne srcID ist eine Näherung: Bei unlesbarer Quelle gilt ein frischer Kill als Quelle" },
    { "level", "Stufe des Charakters" },
    { "mapID", "Karte (uiMapID)" },
    { "x", "Position West-Ost (0-9999), leer wenn nicht lesbar" },
    { "y", "Position Nord-Süd (0-9999), leer wenn nicht lesbar" },
  } },

  -- Gear: snapshot per level-up: snapshots.gear[level] = { [slot] = item key, ilvl }.
  GW = { order = 1200, name = "Ausrüstungswechsel", desc = "Ein Ausrüstungs- oder Taschenplatz hat sich geändert. Slots 1-19 sind die Ausrüstung (INVSLOT: 1 Kopf, 2 Hals, 3 Schulter, 4 Hemd, 5 Brust, 6 Gürtel, 7 Beine, 8 Füße, 9 Handgelenke, 10 Hände, 11-12 Ringe, 13-14 Schmuckstücke, 15 Rücken, 16 Haupthand, 17 Nebenhand, 18 Fernkampf, 19 Wappenrock), höhere Slots sind Taschenplätze.", fields = {
    { "slot", "Platz (INVSLOT)" },
    { "item", "neuer Gegenstand (Item-Schlüssel), leer = Platz ist jetzt leer" },
    { "ilvl", "Gegenstandsstufe, leer wenn nicht lesbar" },
    { "prev", "vorheriger Gegenstand (Item-Schlüssel), leer = Platz war leer" },
    { "level", "Stufe des Charakters" },
    { "mapID", "Karte (uiMapID)" },
  } },

  -- Character: names: snapshots.spells, snapshots.factions, snapshots.skills.
  SP = { order = 1300, name = "Zauber gelernt", desc = "Ein Zauber, eine Fähigkeit oder ein Rang wurde gelernt. Name und Rang stehen in snapshots.spells[spellID].", fields = {
    { "spellID", "Zauber (spellID); leer, wenn der Client nur die Meldung lieferte" },
    { "kind", "spell, ability, passive, recipe, mount, companion; leer wenn unbekannt" },
    { "level", "Stufe des Charakters" },
    { "mapID", "Karte (uiMapID)" },
    { "name", "Name, nur wenn keine spellID bekannt ist" },
  } },
  TA = { order = 1310, name = "Talent", desc = "Ein Talentpunkt wurde vergeben (oder zurückgenommen). Knoten-Daten (Position, Zauber) stehen in snapshots.talentNodes, der Stand je Punktesumme in snapshots.talents[spent] = { [nodeID] = Rang }.", fields = {
    { "nodeID", "Talentknoten (C_Traits nodeID)" },
    { "rank", "neuer Rang des Knotens (0 = zurückgenommen)" },
    { "spent", "ausgegebene Talentpunkte insgesamt" },
    { "unspent", "freie Talentpunkte, leer wenn nicht lesbar" },
    { "level", "Stufe des Charakters" },
  } },
  SK = { order = 1320, name = "Fertigkeit", desc = "Beruf oder Fertigkeit neu gelernt oder gestiegen.", fields = {
    { "name", "Name der Fertigkeit laut Client" },
    { "rank", "neuer Wert" },
    { "max", "Höchstwert, leer wenn unbekannt" },
    { "skillLine", "Fertigkeitslinie (skillLineID), leer wenn unbekannt" },
    { "level", "Stufe des Charakters" },
    { "why", "up (gestiegen), new (neu gelernt)" },
  } },
  RP = { order = 1330, name = "Ruf", desc = "Der Ruf bei einer Fraktion hat sich geändert (Meldung des Clients).", fields = {
    { "faction", "Name der Fraktion laut Client" },
    { "factionID", "Fraktion (factionID), leer wenn nicht auffindbar; Name in snapshots.factions" },
    { "delta", "Änderung (negativ = verschlechtert), leer wenn die Meldung keine Zahl nennt" },
    { "standing", "Stufe nach der Änderung: 1 Hasserfüllt, 2 Feindselig, 3 Unfreundlich, 4 Neutral, 5 Freundlich, 6 Wohlwollend, 7 Respektvoll, 8 Ehrfürchtig; leer wenn nicht lesbar" },
    { "level", "Stufe des Charakters" },
    { "mapID", "Karte (uiMapID)" },
  } },
  RT = { order = 1340, name = "Rufstufe", desc = "Eine Rufstufe wurde erreicht (oder verloren).", fields = {
    { "faction", "Name der Fraktion" },
    { "factionID", "Fraktion (factionID), leer wenn nicht auffindbar" },
    { "standing", "neue Stufe (1-8 wie bei RP), leer wenn nur der Text bekannt ist" },
    { "prev", "vorherige Stufe, leer wenn unbekannt" },
    { "standingName", "Stufe als Text laut Meldung, leer wenn keine Meldung kam" },
    { "level", "Stufe des Charakters" },
  } },

  -- Social: names of other players are foreign text (sanitized).
  GS = { order = 1400, name = "Gruppe gebildet", desc = "Ihr seid einer Gruppe beigetreten oder habt eine gebildet.", fields = {
    { "size", "Zahl der Mitglieder inklusive Euch" },
    { "kind", "party oder raid" },
    { "leader", "1 = Ihr seid Anführer" },
    { "level", "Stufe des Charakters" },
    { "mapID", "Karte (uiMapID)" },
  } },
  GM = { order = 1410, name = "Mitspieler", desc = "Ein Mitspieler ist der Gruppe beigetreten (oder war beim Beitritt schon da).", fields = {
    { "name", "Name des Mitspielers" },
    { "class", "Klasse (englischer Dateiname, z. B. PALADIN)" },
    { "level", "Stufe des Mitspielers, leer wenn nicht lesbar" },
    { "size", "Gruppengröße danach" },
  } },
  GL = { order = 1420, name = "Mitspieler geht", desc = "Ein Mitspieler hat die Gruppe verlassen.", fields = {
    { "name", "Name des Mitspielers" },
    { "class", "Klasse (englischer Dateiname)" },
    { "level", "Stufe des Mitspielers beim Beitritt" },
    { "seconds", "Sekunden gemeinsam in der Gruppe" },
  } },
  GE = { order = 1430, name = "Gruppe beendet", desc = "Die Gruppe ist aufgelöst oder Ihr habt sie verlassen. Die Zähler gelten für die ganze Zeit in der Gruppe (Näherung für gemeinsame Kills, Quests und Instanzen).", fields = {
    { "seconds", "Dauer der Gruppe in Sekunden, leer wenn unbekannt" },
    { "maxSize", "größte Gruppengröße" },
    { "kills", "Kills (KI) in der Gruppe" },
    { "quests", "abgegebene Quests in der Gruppe" },
    { "instances", "betretene Instanzen in der Gruppe" },
    { "level", "Stufe des Charakters" },
    { "mapID", "Karte (uiMapID)" },
  } },
  GI = { order = 1440, name = "Gruppe in Instanz", desc = "Die Gruppe beim Betreten einer Instanz (ergänzt IE).", fields = {
    { "instanceID", "Instanz (instanceID)" },
    { "size", "Zahl der Mitglieder inklusive Euch" },
    { "members", "Mitspieler, durch Komma getrennt, je Name:KLASSE:Stufe (bei großen Gruppen gekürzt)" },
  } },
  GU = { order = 1450, name = "Gilde", desc = "Gildenzugehörigkeit oder Rang hat sich geändert.", fields = {
    { "action", "join (beigetreten), leave (verlassen), change (andere Gilde), rank (anderer Rang), seen (beim ersten Sammeln schon Mitglied)" },
    { "guild", "Gildenname" },
    { "rank", "Rangname" },
    { "rankIndex", "Rangnummer (0 = Gildenmeister)" },
    { "level", "Stufe des Charakters" },
  } },
  DU = { order = 1460, name = "Duell", desc = "Ein Duell ist zu Ende. Der Ausgang steht nur in der Systemmeldung; ohne Meldung bleibt er unbekannt.", fields = {
    { "opponent", "Gegner" },
    { "result", "win (gewonnen), loss (verloren), fled (Ihr seid geflüchtet), opp_fled (der Gegner ist geflüchtet), unknown" },
    { "level", "Stufe des Charakters" },
    { "mapID", "Karte (uiMapID)" },
  } },
  PK = { order = 1470, name = "PvP-Kill", desc = "Ein Spieler wurde von Euch, Eurem Begleiter oder der Gruppe getötet (PARTY_KILL mit Spieler-Ziel). Gesperrte Namen stehen als ?.", fields = {
    { "name", "Name des Spielers; ? = gesperrt" },
    { "class", "Klasse (englischer Dateiname), leer wenn unbekannt" },
    { "level", "Stufe des Spielers, leer wenn unbekannt" },
    { "by", "Todesstoß: self, pet, group; ? = nicht lesbar" },
    { "plevel", "Stufe des Charakters" },
    { "mapID", "Karte (uiMapID)" },
    { "x", "Position West-Ost (0-9999), leer wenn nicht lesbar" },
    { "y", "Position Nord-Süd (0-9999), leer wenn nicht lesbar" },
  } },
  PD = { order = 1480, name = "PvP-Tod", desc = "Ihr wurdet von einem Spieler getötet (Todesstoß laut Todesbericht). Nur bei lesbarem Bericht.", fields = {
    { "name", "Name des Spielers" },
    { "class", "Klasse (englischer Dateiname), leer wenn unbekannt" },
    { "level", "Stufe des Charakters" },
    { "mapID", "Karte (uiMapID)" },
    { "x", "Position West-Ost (0-9999), leer wenn nicht lesbar" },
    { "y", "Position Nord-Süd (0-9999), leer wenn nicht lesbar" },
  } },
  TH = { order = 1490, name = "Handel", desc = "Ein Handel mit einem Spieler wurde abgeschlossen. Abgebrochene Handel zählen nur in counters.trade. Items als Liste Item-Schlüssel[*Menge], durch Komma getrennt.", fields = {
    { "partner", "Handelspartner" },
    { "giveGold", "Eure Gold-Gabe in Kupfer" },
    { "getGold", "Erhaltenes Gold in Kupfer" },
    { "give", "Eure Gegenstände" },
    { "get", "Erhaltene Gegenstände" },
    { "level", "Stufe des Charakters" },
    { "mapID", "Karte (uiMapID)" },
  } },
  PM = { order = 1500, name = "Post erhalten", desc = "Geld oder Gegenstände wurden aus einem Brief genommen. Items wie bei TH.", fields = {
    { "sender", "Absender laut Client" },
    { "money", "genommenes Geld in Kupfer" },
    { "items", "genommene Gegenstände" },
    { "cod", "Nachnahme in Kupfer, leer wenn keine" },
    { "ah", "1 = Brief vom Auktionshaus (Rechnung vorhanden)" },
    { "level", "Stufe des Charakters" },
  } },
  PS = { order = 1510, name = "Post gesendet", desc = "Ein Brief wurde verschickt (bestätigt durch den Client). Items wie bei TH.", fields = {
    { "recipient", "Empfänger" },
    { "money", "mitgeschicktes Geld in Kupfer" },
    { "items", "mitgeschickte Gegenstände" },
    { "cod", "Nachnahme in Kupfer, leer wenn keine" },
    { "level", "Stufe des Charakters" },
  } },

  -- Companions, rest, plans: names of other players are foreign text (sanitized);
  -- if a player's name, class, race or level is secret, the person is skipped.
  WB = { order = 1600, name = "Weggefährte tritt bei", desc = "Ein Gruppen- oder Schlachtzugsmitglied (außer Euch) ist hinzugekommen. Position und Karte sind die des Charakters beim Beitritt (die Position des Mitspielers ist nicht lesbar). Gelesen wird nur außerhalb des Kampfes, höchstens alle 2 s gebündelt.", fields = {
    { "name", "Name-Realm des Mitspielers (gleicher Realm: der eigene Realmname)" },
    { "class", "Klasse (englischer Dateiname, z. B. PALADIN), leer wenn nicht lesbar" },
    { "race", "Volk (englischer Dateiname, z. B. NightElf), leer wenn nicht lesbar" },
    { "level", "Stufe des Mitspielers, leer wenn nicht lesbar" },
    { "mapID", "Karte (uiMapID) des Charakters beim Beitritt" },
    { "x", "Position des Charakters West-Ost (0-9999), leer wenn nicht lesbar" },
    { "y", "Position des Charakters Nord-Süd (0-9999), leer wenn nicht lesbar" },
  } },
  WV = { order = 1610, name = "Weggefährte geht", desc = "Ein Gruppenmitglied hat die Gruppe verlassen, die Gruppe ist zu Ende oder Ihr habt Euch ausgeloggt (Felder wie WB).", fields = {
    { "name", "Name-Realm des Mitspielers" },
    { "class", "Klasse (englischer Dateiname), leer wenn nicht lesbar" },
    { "race", "Volk (englischer Dateiname), leer wenn nicht lesbar" },
    { "level", "Stufe des Mitspielers beim Gehen, leer wenn nicht lesbar" },
    { "mapID", "Karte (uiMapID) des Charakters beim Gehen" },
    { "x", "Position des Charakters West-Ost (0-9999), leer wenn nicht lesbar" },
    { "y", "Position des Charakters Nord-Süd (0-9999), leer wenn nicht lesbar" },
    { "why", "left (Mitspieler gegangen), end (Gruppe zu Ende), logout (Ihr habt Euch ausgeloggt)" },
  } },
  RA = { order = 1700, name = "Rast", desc = "Der Charakter beginnt zu rasten: Ruhegebiet (Gasthaus, Stadt) oder Lagerfeuer bzw. Zelt (Rast-Aura). Höchstens eine Zeile je 5 Minuten. Das Ende steht nicht im Log.", fields = {
    { "kind", "inn (Ruhegebiet laut IsResting) oder fire (Lagerfeuer-/Zelt-Aura)" },
    { "mapID", "Karte (uiMapID)" },
    { "x", "Position West-Ost (0-9999), leer wenn nicht lesbar" },
    { "y", "Position Nord-Süd (0-9999), leer wenn nicht lesbar" },
    { "level", "Stufe des Charakters" },
    { "rested", "Ruhe-Erfahrung in Punkten, leer wenn keine oder nicht lesbar" },
    { "src", "Quelle: Spell-ID der Rast-Aura (Lagerfeuer, Zelt), name (Treffer per Namensmuster ohne lesbare ID) oder inn (Ruhegebiet)" },
  } },
  LF = { order = 1710, name = "Lagerfeuer-Runde", desc = "Der Charakter hat mindestens 60 s am Lagerfeuer gesessen (Sitz-Aura) und ist aufgestanden. Personen: nur wer am Feuer war (Sitz-/Rast-Aura gelesen oder mindestens 20 s in Reichweite, Vorbeilaufende zählen nicht). Namen anderer Spieler sind Fremdtext (gesäubert).", fields = {
    { "mapID", "Karte (uiMapID) beim Hinsetzen" },
    { "x", "Position West-Ost (0-9999), leer wenn nicht lesbar" },
    { "y", "Position Nord-Süd (0-9999), leer wenn nicht lesbar" },
    { "level", "Stufe des Charakters beim Hinsetzen" },
    { "seconds", "Sitzdauer in Sekunden" },
    { "count", "Zahl der Personen am Feuer (alle, auch die nicht ins Feld passten)" },
    { "people", "Personen, je Person guid,name-realm,class,race,level,sex,how (guid ohne Präfix Player-, sex 2/3, how a = Aura gelesen, d = verweilt), mit ; getrennt; höchstens 10 und 250 Bytes, wer nicht passt fällt ganz weg" },
    { "said", "Zahl der per Zettel gesagten Sätze" },
    { "sim", "1 = Probe-Runde aus der Retail-Simulation (/chronik sim feuer), sonst leer; /chronik sim feuer löschen entfernt nur diese" },
  } },
  AF = { order = 1720, name = "AFK-Phase", desc = "Eine Phase als abwesend markiert (AFK, von Hand oder automatisch) ist zu Ende. Die Zeile steht erst am Ende der Phase; Phasen unter 10 Sekunden werden nicht geschrieben. Die Summen stehen in counters.afk (seconds, phases), die längste Phase in snapshots.state.afk.longest.", fields = {
    { "seconds", "Dauer der Phase in Sekunden" },
    { "level", "Stufe des Charakters" },
    { "mapID", "Karte (uiMapID) am Ende, leer wenn unbekannt (why = gap)" },
    { "why", "Ende: end (AFK-Markierung wurde entfernt), logout (Ausloggen) oder gap (Absturz oder Reload ohne Fortsetzung; Ende = letzter bekannter Zeitpunkt)" },
  } },
  VE = { order = 1800, name = "Vorhaben erfüllt", desc = "Ein eigenes To Do (Vorhaben) wurde erledigt: automatisch (Zone betreten, Ort erreicht, Gegner getötet, Gegenstände gefunden) oder von Hand abgehakt (how = hand). Die Liste selbst steht in chars[guid].vorhaben.", fields = {
    { "id", "Nummer des Vorhabens in der Vorhaben-Liste" },
    { "mapID", "Zielkarte des Vorhabens (uiMapID)" },
    { "level", "Stufe des Charakters" },
    { "x", "Position West-Ost (0-9999), leer wenn nicht lesbar" },
    { "y", "Position Nord-Süd (0-9999), leer wenn nicht lesbar" },
    { "text", "Text des Vorhabens (gesäubert, höchstens 120 Zeichen; bei Gegnern/Gegenständen mit Anzahl, z. B. 10× Hasenpfote)" },
    { "how", "Wie erledigt: leer = Zielzone betreten, place = Ort erreicht, kill = Gegner getötet, item = Gegenstände gefunden, hand = von Hand abgehakt" },
  } },
}

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local MAX_INT = 9007199254740991

local function finite(v)
  return type(v) == "number" and v == v and v < MAX_INT and v > -MAX_INT
end

-- integer as text (never tostring). Non-finite or too large numbers -> ''.
-- '%d' only in the 32-bit range (Lua 5.1 formats %d via long, 32-bit on Windows); above it '%.0f' (exact, no exponent).
local function int(v)
  if isSecret(v) or not finite(v) then return "" end
  local f = floor(v)
  if f >= -2147483648 and f <= 2147483647 then return format("%d", f) end
  return format("%.0f", f)
end
Store.int = int

-- a field value as log text: secret -> '?' (unreadable), nil -> ''
local function formatField(v)
  if isSecret(v) then return "?" end
  if v == nil then return "" end
  local t = type(v)
  if t == "number" then return int(v) end
  if t == "boolean" then return v and "1" or "0" end
  if t == "string" then return ns.Sanitize.field(v) end
  return ""
end
Store.formatField = formatField

local function sub(t, k)
  local v = t[k]
  if type(v) ~= "table" then
    v = {}
    t[k] = v
  end
  return v
end

-- line '<dt>~<code>~<f1>~...', trailing empty fields are dropped
local function buildLine(dt, code, ...)
  local parts = { int(dt), code }
  local n = select("#", ...)
  for i = 1, n do parts[i + 2] = formatField((select(i, ...))) end
  local last = #parts
  while last > 2 and parts[last] == "" do
    parts[last] = nil
    last = last - 1
  end
  return concat(parts, "~")
end

local function blockHeader(start, tag)
  return "#~" .. int(start) .. "~" .. int(tag or 0)
end

local function text(v)
  if isSecret(v) or v == nil then return nil end
  local s = ns.Sanitize.field(v)
  if s == "" then return nil end
  return s
end

-- Database

function Store.init()
  local db = EveNChronicleDB
  if type(db) ~= "table" then db = {} end
  if type(db.schema) ~= "number" then
    db.schema = ns.SCHEMA
  elseif db.schema > ns.SCHEMA then
    Store.futureSchema = db.schema -- newer file: rebuild nothing, only note it
  end
  db.addonVersion = ns.version
  local meta = sub(db, "meta")
  sub(meta, "sessions")
  local diag = sub(db, "diag")
  if Store.futureSchema then diag.schemaWarning = "Datei hat Schema " .. int(Store.futureSchema) .. ", Addon kennt " .. int(ns.SCHEMA) end
  sub(db, "chars")
  EveNChronicleDB = db
  Store.db = db
  Store.hookReload()
end

Store.RELOAD_FLAG_TTL = 2 -- seconds: how long the reload flag is valid (if the reload happens, the UI is gone before)

-- detects a reload (save button, /reload, addon list). The flag expires after RELOAD_FLAG_TTL so a blocked reload
-- followed by a real logout is not taken as an open session (crash).
function Store.markReload()
  local at = GetTime()
  Store.reloadFlagAt = at
  C_Timer.After(Store.RELOAD_FLAG_TTL, function()
    if Store.reloadFlagAt == at then Store.reloadFlagAt = nil end
  end)
end

function Store.reloadPending()
  local at = Store.reloadFlagAt
  return at ~= nil and GetTime() - at < Store.RELOAD_FLAG_TTL
end

function Store.hookReload()
  if Store.hooked or type(hooksecurefunc) ~= "function" then return end
  Store.hooked = true
  if type(ReloadUI) == "function" then pcall(hooksecurefunc, "ReloadUI", Store.markReload) end
  if type(C_UI) == "table" and type(C_UI.Reload) == "function" then pcall(hooksecurefunc, C_UI, "Reload", Store.markReload) end
end

function Store.login()
  local db = Store.db
  if not db then return end
  local guid = UnitGUID("player")
  if isSecret(guid) or type(guid) ~= "string" or guid == "" then
    error("Spieler-GUID nicht lesbar")
  end
  local char = sub(db.chars, guid)
  for _, k in ipairs(Store.CHAR_TABLES) do sub(char, k) end
  local info, now = char.info, time()
  local fresh = not info.firstSeen
  if fresh then info.firstSeen = now end
  info.name = text(UnitName("player")) or info.name
  info.realm = text(GetRealmName and GetRealmName()) or info.realm
  local raceName, raceFile = UnitRace("player")
  info.race, info.raceFile = text(raceName) or info.race, text(raceFile) or info.raceFile
  local className, classFile = UnitClass("player")
  info.class, info.classFile = text(className) or info.class, text(classFile) or info.classFile
  local factionFile, factionName = UnitFactionGroup("player")
  info.faction, info.factionName = text(factionFile) or info.faction, text(factionName) or info.factionName
  info.lastSeen = now
  if type(char.lineCount) ~= "number" then char.lineCount = 0 end
  Store.guid, Store.current, Store.loginAt = guid, char, now
  -- first session of this character with the addon: time and level at that login (journal/Toast.lua keeps medals
  -- earned by the start state of an existing character quiet); memory only, nil on every later login
  local level = nil
  if fresh and type(UnitLevel) == "function" then
    local ok, v = pcall(UnitLevel, "player")
    if ok and not isSecret(v) and finite(v) then level = v end
  end
  Store.fresh = fresh and { at = now, level = level } or nil
  Store.sizes = {}
  Store.openBlock()
end

function Store.char()
  return Store.current
end

-- number of entries in a table, counted once and then tracked (Store.sizes, cleared on every login)
local function sizeOf(tbl, id)
  local n = Store.sizes[id]
  if n == nil then
    n = 0
    for _ in pairs(tbl) do n = n + 1 end
    Store.sizes[id] = n
  end
  return n
end

-- notes in diag.limits[id] when a cap (or fallback path) first took effect
function Store.noteLimit(id)
  local diag = Store.db and Store.db.diag
  if type(diag) == "table" and type(id) == "string" then
    if type(diag.limits) ~= "table" then diag.limits = {} end
    if diag.limits[id] == nil then diag.limits[id] = floor(time()) end
  end
end

-- true if a new entry still fits in tbl; otherwise notes it in diag.limits and returns false
local function roomFor(tbl, id, limit)
  if sizeOf(tbl, id) < limit then return true end
  Store.noteLimit(id)
  return false
end

function Store.ready()
  return Store.current ~= nil and Store.block ~= nil
end

-- Block log

function Store.openBlock()
  Store.block = { start = time(), lines = {} }
end

function Store.flush()
  local b, char = Store.block, Store.current
  Store.block = nil
  if not b or not char then return end
  if #b.lines > 0 then
    char.log[#char.log + 1] = blockHeader(b.start, Store.session) .. "\n" .. concat(b.lines, "\n")
  end
end

local function observerFields(...)
  local fields, last = {}, 0
  for i = 1, select("#", ...) do
    local f = formatField((select(i, ...)))
    fields[i] = f
    if f ~= "" then last = i end
  end
  for i = #fields, last + 1, -1 do fields[i] = nil end
  return fields
end

-- calls the observer with code and field texts, only if one is registered; building and call share one pcall so a failure never aborts the append
local function notifyObserver(obs, code, ...)
  if type(obs) ~= "function" or notifying then return end
  notifying = true
  local ok = pcall(function(...) obs(code, observerFields(...)) end, ...)
  notifying = false
  if not ok then
    Store.observerErrors = Store.observerErrors + 1
    Store.noteLimit("observer_error")
  end
end

-- new log line. An unknown code is a programming error (throws, the core counts it against the collector).
function Store.append(code, ...)
  if isSecret(code) or type(code) ~= "string" or not ns.Types[code] then
    error("Store.append: unbekanntes Typ-Kuerzel " .. (type(code) == "string" and code or "?"), 2)
  end
  local b = Store.block
  if not b or not Store.current then
    Store.dropped = Store.dropped + 1
    return false
  end
  b.lines[#b.lines + 1] = buildLine(time() - b.start, code, ...)
  Store.current.lineCount = Store.current.lineCount + 1
  if #b.lines >= Store.BLOCK_LINES then
    Store.flush()
    Store.openBlock()
  end
  if Store.observer ~= nil then notifyObserver(Store.observer, code, ...) end
  return true
end

-- Trail stream: chars[guid].trail, blocks per mapID. Header '#~<epoch>~<mapID>', lines '<dt>~<x>~<y>[~<mark>]'.
-- Marks for mandatory points (regardless of distance): z zone change, d death, f takeoff, l landing.
Store.TRAIL_MARKS = { z = true, d = true, f = true, l = true }

function Store.flushTrail()
  local t, char = Store.trailBlock, Store.current
  Store.trailBlock = nil
  if not t or not char or #t.lines == 0 then return end
  char.trail[#char.trail + 1] = blockHeader(t.start, t.mapID) .. "\n" .. concat(t.lines, "\n")
end

-- a trail point: x, y = map fraction 0..1 (like C_Map.GetPlayerMapPosition), converted only via Zone.coord.
-- mark = optional mark from Store.TRAIL_MARKS. New block on map change or when full.
function Store.trailPoint(mapID, x, y, mark)
  if not Store.current or not Store.block then return false end
  if isSecret(mapID) or not finite(mapID) or mapID <= 0 then return false end
  local coord = ns.Zone and ns.Zone.coord
  if type(coord) ~= "function" then return false end
  local cx, cy = coord(x), coord(y)
  if not cx or not cy then return false end
  if isSecret(mark) or not Store.TRAIL_MARKS[mark] then mark = nil end
  mapID = floor(mapID)
  local t = Store.trailBlock
  if t and t.mapID ~= mapID then
    Store.flushTrail()
    t = nil
  end
  if not t then
    t = { start = time(), mapID = mapID, lines = {} }
    Store.trailBlock = t
  end
  local line = int(time() - t.start) .. "~" .. int(cx) .. "~" .. int(cy)
  if mark then line = line .. "~" .. mark end
  t.lines[#t.lines + 1] = line
  if #t.lines >= Store.TRAIL_POINTS then Store.flushTrail() end
  return true
end

-- Text tables, snapshots, screenshots, counters

local function normKey(key)
  if isSecret(key) or key == nil then return nil end
  if type(key) == "number" then
    if not finite(key) then return nil end
    return floor(key)
  end
  if type(key) == "string" then
    local s = ns.Sanitize.field(key)
    if s ~= "" then return s end
  end
  return nil
end

-- value for a table: strings (longText or field), numbers (integer or fixed decimals), booleans, tables.
local function cleanValue(v, depth, opts)
  if isSecret(v) or v == nil then return nil end
  local t = type(v)
  if t == "string" then
    if opts.short then return text(v) end
    return ns.Sanitize.longText(v)
  end
  if t == "number" then
    if not finite(v) then return nil end
    if opts.decimals then
      local m = 10 ^ opts.decimals
      return floor(v * m + 0.5) / m
    end
    return floor(v)
  end
  if t == "boolean" then return v end
  if t == "table" and depth < 4 then
    local out, any = {}, false
    for k, x in pairs(v) do
      local ck, cx = normKey(k), cleanValue(x, depth + 1, opts)
      if ck ~= nil and cx ~= nil then
        out[ck] = cx
        any = true
      end
    end
    if any then return out end
  end
  return nil
end

local LONG = {}
local SNAPSHOT = { short = true, decimals = Store.DECIMALS }
local SHORT = { short = true }

-- writes fields into chars[guid][table][key], each field only once (never overwrites).
-- fields = table or string (e.g. npcs[npcID] = name). The entry gets firstAt; a field added later gets its own fAt (e.g. progressAt).
-- returns the number of newly written fields (0 = nothing new).
function Store.putText(tableName, key, fields)
  local char = Store.current
  if not char or not Store.TEXT_TABLES[tableName] then return 0 end
  local k = normKey(key)
  if k == nil then return 0 end
  local tbl = sub(char, tableName)
  if isSecret(fields) then return 0 end
  local limit = Store.LIMITS[tableName]
  if type(fields) == "string" then
    if tbl[k] ~= nil then return 0 end
    local v = text(fields)
    if not v then return 0 end
    if limit and not roomFor(tbl, tableName, limit) then return 0 end
    tbl[k] = v
    Store.sizes[tableName] = (Store.sizes[tableName] or 0) + 1
    return 1
  end
  if type(fields) ~= "table" then return 0 end
  local entry = tbl[k]
  if entry ~= nil and type(entry) ~= "table" then return 0 end
  local existed, now, added = entry ~= nil, floor(time()), 0
  for f, v in pairs(fields) do
    if type(f) == "string" and f ~= "firstAt" and (entry == nil or entry[f] == nil) then
      local cv = cleanValue(v, 0, Store.SHORT_FIELDS[f] and SHORT or LONG)
      if cv ~= nil then
        if entry == nil then
          if limit and not roomFor(tbl, tableName, limit) then return added end
          entry = { firstAt = now }
          tbl[k] = entry
          Store.sizes[tableName] = (Store.sizes[tableName] or 0) + 1
        end
        entry[f] = cv
        if existed and entry[f .. "At"] == nil then entry[f .. "At"] = now end
        added = added + 1
      end
    end
  end
  return added
end

-- snapshot (gear, values per level): chars[guid].snapshots[kind][key] = { at, ... }.
-- numbers keep fixed decimals (Store.DECIMALS), texts are sanitized as field.
-- default: write once; replace = true replaces. Returns true if written.
function Store.putSnapshot(kind, key, values, replace)
  local char = Store.current
  if not char or isSecret(kind) or type(kind) ~= "string" or isSecret(values) or type(values) ~= "table" then return false end
  local g, k = text(kind), normKey(key)
  if not g or k == nil then return false end
  local group = sub(sub(char, "snapshots"), g)
  local isNew = group[k] == nil
  if not isNew and not replace then return false end
  local clean = cleanValue(values, 0, SNAPSHOT)
  if type(clean) ~= "table" then return false end
  local limit = Store.SNAPSHOT_LIMITED[g] and Store.LIMITS[g]
  if isNew and limit then
    if not roomFor(group, "snapshots." .. g, limit) then return false end
    Store.sizes["snapshots." .. g] = (Store.sizes["snapshots." .. g] or 0) + 1
  end
  clean.at = floor(time())
  group[k] = clean
  return true
end

-- removes a snapshot entry (e.g. a settled bill) and keeps the entry count (Store.sizes) in step, freeing room under the soft cap.
-- returns true if something was removed.
function Store.dropSnapshot(kind, key)
  local char = Store.current
  if not char or isSecret(kind) or type(kind) ~= "string" then return false end
  local g, k = text(kind), normKey(key)
  if not g or k == nil then return false end
  local snaps = char.snapshots
  local group = type(snaps) == "table" and snaps[g] or nil
  if type(group) ~= "table" or group[k] == nil then return false end
  group[k] = nil
  local id = "snapshots." .. g
  if Store.sizes[id] ~= nil then Store.sizes[id] = math.max(0, Store.sizes[id] - 1) end
  return true
end

-- screenshot mapping: chars[guid].shots['MMDDYY_HHMMSS'] = { at = epoch, ... }. The key is the part of the file name
-- WoWScrnShot_<key>.<format> (local time). Returns the key, or nil if already present.
function Store.putShot(fields)
  local char = Store.current
  if not char then return nil end
  local now = time()
  local stamp = date("%m%d%y_%H%M%S", now)
  local shots = sub(char, "shots")
  if shots[stamp] ~= nil then return nil end
  local entry = (not isSecret(fields) and type(fields) == "table") and cleanValue(fields, 0, SHORT) or nil
  if type(entry) ~= "table" then entry = {} end
  entry.at = floor(now)
  shots[stamp] = entry
  return stamp
end

-- item cache: snapshots.items[itemID] = { name, quality } (first time only; cap Store.LIMITS.items).
function Store.noteItem(itemID, name, quality)
  if isSecret(itemID) or type(itemID) ~= "number" then return false end
  return Store.putSnapshot("items", itemID, { name = name, quality = (type(quality) == "number" and not isSecret(quality)) and quality or nil })
end

-- counter: chars[guid].counters[group][key] += n (default 1).
function Store.count(group, key, n)
  local char = Store.current
  if not char or isSecret(group) or type(group) ~= "string" then return false end
  local g, k = ns.Sanitize.field(group), normKey(key)
  if g == "" or k == nil then return false end
  if isSecret(n) then return false end
  if n ~= nil and not finite(n) then return false end
  local grp = sub(sub(char, "counters"), g)
  if grp[k] == nil and not roomFor(grp, "counters." .. g, Store.COUNTER_LIMITS[g] or Store.COUNTER_KEYS) then return false end
  if grp[k] == nil then Store.sizes["counters." .. g] = (Store.sizes["counters." .. g] or 0) + 1 end
  grp[k] = (tonumber(grp[k]) or 0) + floor(n or 1)
  return true
end

-- Sessions and time

-- local time minus UTC in seconds (includes DST)
function Store.tzOffset(now)
  local ok, res = pcall(function()
    local utc = date("!*t", now)
    utc.isdst = date("*t", now).isdst
    return now - time(utc)
  end)
  if ok and type(res) == "number" then return floor(res) end
  return 0
end

local function markInterrupted(db, index, s, now)
  s.interrupted = true
  s.lastKnown = floor(tonumber(s.lastSave) or tonumber(s.start) or now)
  local char = type(s.guid) == "string" and db.chars[s.guid]
  if type(char) == "table" and type(char.log) == "table" then
    char.log[#char.log + 1] = blockHeader(now, index) .. "\n" .. buildLine(0, "X", index, s.lastKnown)
    char.lineCount = (tonumber(char.lineCount) or 0) + 1
  end
end

-- first PLAYER_ENTERING_WORLD: new session or continuation after a reload; a session without an end -> interrupted.
-- Whether it was a reload is decided by the PEW arguments alone (fallback: meta.reloadAt younger than RELOAD_WINDOW).
function Store.beginSession(isInitialLogin, isReloadingUi)
  local db, guid = Store.db, Store.guid
  if not db or not guid then return end
  local meta, now = db.meta, time()
  local sessions = meta.sessions
  local last = sessions[#sessions]
  local reload
  if isReloadingUi ~= nil then
    reload = isReloadingUi == true
  else
    reload = type(meta.reloadAt) == "number" and now - meta.reloadAt <= Store.RELOAD_WINDOW
  end
  meta.reloadAt = nil
  local tz = Store.tzOffset(now)
  meta.tzOffset = tz

  if reload and type(last) == "table" and last.guid == guid and not last.interrupted then
    last.stop = nil -- open until the next logout
    last.reloads = (tonumber(last.reloads) or 0) + 1
    Store.session = #sessions
    Store.append("R", Store.session)
    return
  end

  if type(last) == "table" and last.stop == nil and not last.interrupted then
    markInterrupted(db, #sessions, last, now)
  end
  local build, buildNumber, _, interface = GetBuildInfo()
  local locale = GetLocale and GetLocale()
  sessions[#sessions + 1] = {
    guid = guid,
    start = now,
    build = text(build),
    buildNumber = tonumber(buildNumber),
    interface = tonumber(interface),
    locale = text(locale),
    tz = tz,
  }
  Store.session = #sessions
  Store.append("L", Store.session, build, buildNumber, tonumber(interface), locale, tz)
end

-- PLAYER_LOGOUT: with a valid reload flag: S, the session stays open (stop nil, reloadAt). Otherwise O and stop.
-- A session without stop at the next fresh login was a crash (X).
function Store.logout()
  local db = Store.db
  if not db then return end
  local now = time()
  local s = Store.session and db.meta.sessions[Store.session]
  local reloading = Store.reloadPending()
  if Store.current then
    if reloading then
      Store.append("S", Store.session)
    else
      Store.append("O", Store.session, s and (now - (tonumber(s.start) or now)))
    end
    Store.current.info.lastSeen = now
  end
  Store.flush()
  Store.flushTrail()
  if type(s) == "table" then
    s.lastSave = now
    if reloading then
      s.stop = nil
      db.meta.reloadAt = now
    else
      s.stop = now
    end
  end
end
