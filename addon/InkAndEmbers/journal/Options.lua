-- Settings menu under Options -> AddOns -> Ink & Embers (native Settings API). Every row is a proxy setting
-- (Settings.RegisterProxySetting) that reads and writes through the same functions as the book-page checkboxes,
-- /chronik commands and edit mode. Options.refresh() pushes outside changes to the open menu (setting:NotifyUpdate()).
-- Does not open in combat. Without the Settings API the addon stays fully usable via /chronik.
local ADDON_NAME, ns = ...

local Journal = ns.Journal or {}
ns.Journal = Journal

local Options = {}
Journal.Options = Options

Options.NAME = "Ink & Embers"
Options.PREFIX = "EveNChronicle_"
Options.settings = {}
Options.order = {}

-- Texts (Options locale area) are functions, read when the menu is built, never at load.
local TX = ns.Locale.ns("Options", {
  combat = "Die Einstellungen öffnen sich nicht im Kampf. Bitte nach dem Kampf noch einmal.",
  unavailable = "Das Einstellungsmenü ist in diesem Client nicht verfügbar. /chronik hilfe zeigt die Befehle.",
  failed = "Das Einstellungsmenü ließ sich nicht öffnen. Optionen -> AddOns -> Ink & Embers.",
  preview = "Probehören",
  version = "Version %s",
  perChar = "Gilt für diesen Charakter.",
  gBook = "Buch",
  gJourney = "Reise und Karte",
  gTodo = "To Do und Mini-Zettel",
  gQuick = "Schnellnotizen",
  gQuestTracker = "Quest-Tracker",
  questTrackerLabel = "Eigenen Quest-Tracker nutzen",
  questTrackerTip = "Ein Fenster mit To Dos und Quests statt der Tracker von Questie und Blizzard. Blendet den Questie-Tracker und den kompletten Blizzard-Tracker aus, also auch automatische Quest-Hinweise, Erfolge, Szenarien und Berufe. Mini-Zettel und Andocken ruhen so lange. Im Kampf wird erst danach umgeschaltet. Gilt für alle Charaktere (nur WoW Forever).",
  qtModeLabel = "Auswahl",
  qtModeTip = "Welche Quests der Tracker zeigt: nur verfolgte (wie Blizzard, neue Quests werden automatisch verfolgt), alle im Questlog oder die der aktuellen Zone.",
  qtModes = { tracked = "Nur verfolgte", log = "Alle im Questlog", zone = "Aktuelle Zone" },
  qtOrderLabel = "Sortierung",
  qtOrderTip = "Zone: Gruppen je Zone, die aktuelle oben, darin nach Entfernung, mit „Als Nächstes“. Entfernung oder Stufe: eine Liste.",
  qtOrders = { zones = "Zone", distance = "Entfernung", level = "Stufe" },
  qtDoneLabel = "Fertige Quests",
  qtDoneTip = "Abgabebereite Quests in ihrer Zone mit „? Abgeben: NPC“ oder in einer eigenen Gruppe „Abgeben“ ganz oben.",
  qtDones = { inZone = "In ihrer Zone", group = "Eigene Gruppe oben" },
  qtTodoLabel = "To Do im Tracker",
  qtTodoTip = "Lage des To-Do-Abschnitts im Quest-Tracker.",
  qtTodoAt = { top = "Oben", bottom = "Unten" },
  qtHideDoneLabel = "Abgeschlossene Quests ausblenden",
  qtHideDoneTip = "Abgabebereite Quests verschwinden aus der Liste (der Zähler oben zeigt sie weiter).",
  qtHideGroupLabel = "Gruppenquests ausblenden",
  qtHideGroupTip = "Elite- und Gruppenquests verschwinden aus der Liste.",
  qtZoneOnlyLabel = "Nur aktuelle Zone",
  qtZoneOnlyTip = "Zeigt nur Quests, deren Ort in der aktuellen Zone liegt (die Fokus-Quest bleibt sichtbar). Wechselt die Zone, folgt die Liste.",
  qtObjsLabel = "Ziele anzeigen",
  qtObjsTip = "Zeigt unter jeder Quest ihre Ziele mit Zähler.",
  qtDoneObjLabel = "Erledigte Ziele zeigen",
  qtDoneObjTip = "Erledigte Ziele bleiben abgehakt und blass stehen, statt zu verschwinden.",
  qtDistLabel = "Entfernung anzeigen",
  qtDistTip = "Zeigt an jeder Quest die Entfernung, mit Richtungspfeil, wenn das Spiel die Blickrichtung liefert.",
  qtIconsLabel = "Questtyp-Symbole",
  qtIconsTip = "Symbol vor dem Titel: Sammeln, Besiegen, Erkunden oder Gespräch, in der Schwierigkeitsfarbe.",
  qtFocusLabel = "Fokus-Bereich anzeigen",
  qtFocusTip = "Die Fokus-Quest steht als Karte oben im Tracker. Die Zielscheibe an jeder Quest setzt oder löst den Fokus (pro Charakter).",
  qtFocusDistLabel = "Fokus: Kompass und Entfernung",
  qtFocusDistTip = "Pfeil zum Ziel und Entfernung. Liefert das Spiel keine Blickrichtung (etwa in Instanzen), steht nur die Entfernung da.",
  qtFocusBarLabel = "Fokus: Fortschrittsbalken",
  qtFocusBarTip = "Ein schmaler Balken unter jedem Ziel der Fokus-Quest.",
  qtFocusGiverLabel = "Fokus: Questgeber",
  qtFocusGiverTip = "Name des Questgebers (aus QuestieDB, wenn installiert).",
  qtFocusRewLabel = "Fokus: Belohnungen",
  qtFocusRewTip = "EP, Geld und ein Gegenstand in Qualitätsfarbe, soweit das Questlog sie lesbar liefert.",
  qtNotifyLabel = "Hinweis bei Fortschritt",
  qtNotifyTip = "Ist der Tracker eingefahren, erscheint neben dem Griff kurz ein Hinweis mit Quest und Ziel.",
  qtHideInfoLabel = "Blizzard-Questfortschritt ausblenden",
  qtHideInfoTip = "Die gelben Fortschrittszeilen in der Bildschirmmitte („Wolf getötet: 3/10“, „Ziel abgeschlossen“) erscheinen nicht mehr, der Tracker zeigt den Fortschritt selbst. Andere Meldungen und Fehler bleiben. Gilt für alle Charaktere.",
  qtHoverLabel = "Beim Überfahren ausfahren",
  qtHoverTip = "Der Tracker fährt aus, sobald die Maus den rechten Bildschirmrand oder den Griff berührt. Aus: nur per Klick auf den Griff.",
  qtDelayLabel = "Einfahren nach",
  qtDelayTip = "So viele Millisekunden bleibt der Tracker offen, nachdem die Maus ihn verlassen hat. Die Nadel hält ihn ganz offen.",
  qtSyncFocusLabel = "Fokus mit Spiel-Markierung abgleichen",
  qtSyncFocusTip = "Die Fokus-Quest folgt der im Spiel aktiv markierten Quest (Questlog, Weltkarte) und umgekehrt. Bei Problemen hier abschalten.",
  qtBgAlphaLabel = "Hintergrund-Deckkraft",
  qtBgAlphaTip = "Wie dunkel der Hintergrund des ausgefahrenen Trackers ist (Prozent).",
  qtFadeWidthLabel = "Auslauf-Breite",
  qtFadeWidthTip = "Breite des durchsichtigen Auslaufs links am Tracker in Pixeln (0 = harte Kante).",
  qtFadeTimeLabel = "Ausblenddauer",
  qtFadeTimeTip = "So viele Millisekunden dauert das Ausblenden beim Einfahren (0 = sofort).",
  qtFontScaleLabel = "Schriftgröße",
  qtFontScaleTip = "Größe aller Texte im Tracker in Prozent, unabhängig von der Größe des Trackers.",
  qtFontHeadLabel = "Schriftart Überschriften",
  qtFontHeadTip = "Schrift für Kopf, Fokus-Titel und Griff. Enthält alle Schriften des Spiels und der Addons (SharedMedia). Fehlt eine Schrift, gilt die Standardschrift.",
  qtFontTextLabel = "Schriftart Text",
  qtFontTextTip = "Schrift für Questnamen, Ziele und Zonen. Enthält alle Schriften des Spiels und der Addons (SharedMedia). Fehlt eine Schrift, gilt die Standardschrift.",
  qtFontDefault = "Standard",
  qtPanMapLabel = "Karte auf das Ziel schwenken",
  qtPanMapTip = "„Auf Karte zeigen“ öffnet die Weltkarte und zentriert sie auf den Zielpunkt. Bei Kartenproblemen abschalten: dann wird die Karte nur geöffnet.",
  qtScaleLabel = "Größe des Trackers",
  qtScaleTip = "Größe des ausgefahrenen Panels in Prozent. Der Griff am Rand hat eine eigene Größe.",
  qtGripScaleLabel = "Griff-Größe",
  qtGripScaleTip = "Größe des Griffs am rechten Rand samt Füllstand-Pille in Prozent, unabhängig von der Größe des Panels.",
  qtGripAlphaLabel = "Griff-Deckkraft",
  qtGripAlphaTip = "Wie deutlich der Griff am rechten Rand in Ruhe zu sehen ist (10 bis 100 %). Beim Drüberfahren und wenn eine Quest abgabebereit ist, wird er sanft voll sichtbar.",
  qtItemBarLabel = "Leiste für Quest-Gegenstände",
  qtItemBarTip = "Eine eigene, verschiebbare Leiste (Bearbeitungsmodus) mit den Quest-Gegenständen der aktuellen Zone.",
  qtItemBarNearLabel = "Quest-Gegenstände nur im Zielgebiet",
  qtItemBarNearTip = "Ein Quest-Gegenstand erscheint in der Leiste erst, wenn du im Zielgebiet der Quest bist (etwa 140 Yards um den nächsten Zielpunkt), und verschwindet wieder, wenn du dich entfernst. Fertige Quests zeigen ihn nur am Abgabeort. Ohne Zieldaten bleibt er sichtbar. Im Kampf ändert sich die Leiste nicht.",
  qtUnhideLabel = "Ausgeblendete Quests",
  qtUnhideButton = "Wieder zeigen",
  qtUnhideTip = "Holt alle Quests zurück, die du im Tracker ausgeblendet hast (dieser Charakter).",
  qtResetLabel = "Lage des Quest-Trackers",
  qtResetTip = "Setzt Griff, Größe und Leiste für Quest-Gegenstände auf ihre Standardlage zurück.",
  gToasts = "Einblendungen",
  gMedals = "Medaillen",
  gMarks = "Markierung der To-Do-Gegner",
  gFire = "Lagerfeuer",
  gSounds = "Klänge",
  gMisc = "Sonstiges",
  scaleLabel = "Größe des Buchs",
  scaleTip = "Größe des Reisejournals in Prozent.",
  reduceLabel = "Bewegung reduzieren",
  reduceTip = "Keine Aufschlag-Animation und ruhigere Karten-Wiedergabe.",
  minimapLabel = "Minimap-Knopf zeigen",
  minimapTip = "Knopf am Rand der Minikarte: Linksklick öffnet das Buch, Rechtsklick diese Einstellungen.",
  soundsLabel = "Buchgeräusche",
  soundsTip = "Klänge beim Öffnen, Blättern und Schließen des Buchs, bei Begrüßung, Rückblick und erledigten To Dos.",
  resetBookLabel = "Lage und Größe des Buchs",
  resetButton = "Zurücksetzen",
  resetBookTip = "Setzt Größe und Position des Buchs auf den Standard (wie /chronik reset).",
  tutorialLabel = "Einführung",
  tutorialButton = "Ansehen",
  tutorialTip = "Zeigt die kleine Einführung zum Durchblättern noch einmal (wie /chronik tutorial).",
  mapColorLabel = "Kartenfarben",
  mapColorTip = "Gilt für alle Karten im Buch.",
  mapSepia = "Pergament (Sepia)",
  mapOriginal = "Originalfarben",
  killsLabel = "Kämpfe auf der Karte zeigen",
  killsTip = "Schwerter für Kämpfe auf der Zonenkarte (derselbe Haken wie unter der Karte).",
  revealLabel = "Karte aufdecken",
  revealTip = "Zeigt die ganze Zone aufgedeckt, nicht nur selbst erkundete Gebiete (derselbe Haken wie unter der Karte).",
  iconsLabel = "Symbole auf der Kontinentkarte zeigen",
  iconsTip = "Tode, Stufen, Flugpunkte, Notizen und andere Ereignis-Symbole auf der Kontinentkarte; Route und Pfeil bleiben immer (derselbe Haken wie unter der Karte).",
  speedLabel = "Tempo der Wiedergabe",
  speedTip = "Wie schnell die Reise auf der Karte abgespielt wird.",
  speedSlow = "Langsam",
  speedMid = "Mittel",
  speedFast = "Schnell",
  worldMapLabel = "Reise auf der Weltkarte zeigen",
  worldMapTip = "Route, Stufenaufstiege und Kampf-Marken der Reise auch auf der Weltkarte des Spiels (Eintrag \"Reise (Ink & Embers)\" im Kartenfilter).",
  worldPinsLabel = "Orte auf der Weltkarte zeigen",
  worldPinsTip = "Notizen und To Dos mit Ort als Pins auf der Weltkarte des Spiels (Eintrag \"Orte (Ink & Embers)\" im Kartenfilter). Unabhängig von der Reise.",
  fbShown = "Mini-To-Do-Zettel",
  fbStyle = "Notizzettel-Stil",
  fbLocked = "Notizzettel sperren",
  fbCombat = "Im Kampf ausblenden",
  fbEmpty = "Ausblenden, wenn nichts offen ist",
  fbAuto = "Zettel automatisch zeigen, wenn To Dos offen sind",
  fbDock = "To Dos am Questtracker andocken",
  todoDockTip = "Statt des Mini-Zettels stehen die To Dos als eigener Abschnitt im Stil des Questtrackers direkt an ihm (auch an Questie oder Kaliels Tracker) und klappen mit ihm ein. Solange angedockt, ruhen Lage, Stil und Bearbeitungsmodus des Mini-Zettels.",
  fbDockSide = "Lage am Questtracker",
  fbDockSides = { below = "Unter den Quests", above = "Über den Quests" },
  todoDockSideTip = "Wo der angedockte Abschnitt sitzt. Reicht der Platz bis zum Bildschirmrand nicht, weicht er auf die andere Seite aus.",
  fbPad = "Notizblock",
  fbPlain = "Schlicht",
  todoShownTip = "Kleiner Notizzettel mit den offenen To Dos am Bildschirmrand.",
  todoStyleTip = "Aussehen des Mini-Zettels.",
  fbOpen = "Öffnen",
  fbOpenModes = { always = "Immer offen", hover = "Beim Überfahren", click = "Per Klick",
    auto = "Automatisch, sobald To Dos drauf stehen" },
  todoOpenTip = "Wann der Mini-Zettel ganz aufgeklappt ist. Eingeklappt bleibt nur der Kopf mit der Zahl offener To Dos stehen.",
  fbGrow = "Aufklappen nach",
  fbGrowNames = { down = "Unten", up = "Oben" },
  todoGrowTip = "Unten: der Zettel rollt unter dem Kopf auf. Oben: der Kopf bleibt an seiner Stelle, der Zettel rollt über ihm auf.",
  quickStyleLabel = "Stil der Schnellnotiz",
  quickStyleTip = "Aussehen der Schnellnotiz.",
  todoLockedTip = "Mini-Zettel lässt sich nicht verschieben oder in der Größe ändern.",
  todoCombatTip = "Mini-Zettel verschwindet während eines Kampfs.",
  todoEmptyTip = "Mini-Zettel nur zeigen, wenn ein To Do offen ist.",
  todoAutoTip = "Der Mini-Zettel geht von selbst auf, sobald To Dos offen sind (beim Einloggen und wenn ein neues dazukommt). Schließt Ihr ihn mit dem x, bleibt er zu, bis ein neues To Do dazukommt.",
  todoToastLabel = "Neue automatische To Dos melden",
  todoToastTip = "Kleine Einblendung, wenn das Addon selbst ein To Do anlegt, z. B. „Zum Lehrer“ nach einem Stufenaufstieg. Nach dem Erzähler-Zettel, nie im Kampf. Selbst angelegte To Dos melden sich nicht (nur WoW Forever).",
  trainerTodoLabel = "Zum Lehrer automatisch eintragen",
  trainerTodoTip = "Nach einem Stufenaufstieg und beim Anmelden mit neuen Zaubern steht „Zum Lehrer“ als To Do auf der Liste (je Stufe nur einmal); es hakt sich selbst ab, sobald alles gelernt ist (nur WoW Forever).",
  talentHintLabel = "Freie Talentpunkte melden",
  talentHintTip = "Kleine Einblendung, wenn Talentpunkte frei sind – einmal pro Stufe bzw. Sitzung, nie im Kampf (nur WoW Forever).",
  todoResetLabel = "Lage des Mini-Zettels",
  todoResetTip = "Position und Größe des Mini-Zettels auf den Standard (wie /chronik todo reset).",
  quickLabel = "Schnellnotizen zeigen",
  quickTip = "Kleines Feld am Bildschirmrand: schreiben, Enter, schon liegt die Notiz im Notizbuch.",
  toastLabel = "Einblendungen zeigen",
  toastTip = "Kleine Pergament-Einblendungen oben am Bildschirm (wie /chronik toast).",
  toastZoneLabel = "Neue Gebiete melden",
  toastZoneTip = "Einblendung beim ersten Betreten eines Gebiets.",
  toastSoundLabel = "Ton der Einblendungen",
  toastSoundTip = "Klang zu jeder Einblendung (wie /chronik ton). Welcher Klang, steht unter Klänge.",
  welcomeLabel = "Willkommen-Gruß",
  welcomeTip = "Kleiner Zettel am linken Bildschirmrand beim Einloggen: beim ersten Besuch eines Charakters und, wenn Ihr nach einer Pause zurückkehrt, mit dem Stand der Reise.",
  levelSlipLabel = "Stufenaufstieg: Erzähler sagt, was Ihr lernen könnt",
  milestoneSlipLabel = "Meilenstein: Erzähler zieht bei Stufe 10, 20, … Bilanz",
  milestoneSlipTip = "Bei Stufe 10, 20, 30, 40, 50 und 60 blickt der Erzähler auf die letzten zehn Stufen zurück: Zeit ohne AFK, neue Zonen, Gegner, Tode und Euer bester Fund, bei Stufe 60 auf die ganze Reise. Ein Klick öffnet die Meilensteine im Buch. Die Seite im Buch bleibt immer, die Option schaltet nur die Meldung ab (nur WoW Forever).",
  levelSlipTip = "Beim Stufenaufstieg gleitet der Erzähler herein und sagt in ganzen Sätzen: welche Zauber Ihr beim Lehrer lernen könnt, was sie kosten, wo der nächste Lehrer ist und ob Talentpunkte frei sind. Ein Klick darauf öffnet den Lehrplan im Buch. Im Kampf erst danach. Ist die Option aus, bleibt nur die kleine Talentpunkt-Einblendung (nur WoW Forever).",
  welcomeAfterLabel = "Zeigen nach Abwesenheit von",
  welcomeAfterTip = "Wie lange Ihr mindestens weg gewesen sein müsst, damit der Zettel beim Einloggen kommt. „Sofort“ zeigt ihn bei jedem Einloggen (nicht bei /reload). Der erste Besuch eines Charakters wird immer begrüßt.",
  afterNow = "Sofort",
  afterHours = { [3600] = "1 Std.", [7200] = "2 Std.", [14400] = "4 Std.", [28800] = "8 Std.", [86400] = "24 Std." },
  welcomeSeenLabel = "Zettel zeigt: zuletzt gesehen",
  welcomeSeenTip = "Gebiet, in dem Ihr zuletzt wart, und wie lange das her ist.",
  welcomeQuestsLabel = "Zettel zeigt: offene Quests",
  welcomeQuestsTip = "Wie viele Quests im Questlog offen sind.",
  welcomeRestedLabel = "Zettel zeigt: Ruhebonus",
  welcomeRestedTip = "Euren Ruhebonus in Prozent.",
  welcomePlanLabel = "Zettel zeigt: To Do in der Nähe",
  welcomePlanTip = "Ein To Do in der Nähe oder, wenn dort keins wartet, die zuletzt angenommene Quest.",
  narratorLabel = "Erzähler im Willkommen-Gruß",
  narratorTip = "Wer Euch im Willkommen-Gruß empfängt: jemand Eures Volks, bei jedem Gruß ein anderer oder immer derselbe.",
  narratorOwn = "Eigenes Volk",
  narratorRandom = "Zufällig",
  narratorNames = { human = "Mensch", dwarf = "Zwerg", nightelf = "Nachtelf", gnome = "Gnom", orc = "Orc", undead = "Untoter",
    tauren = "Tauren", troll = "Troll", skyborne = "Skyborne" },
  restLabel = "Rückblick bei der Rast",
  restTip = "Rückblick auf die letzte Etappe, wenn Ihr am Lagerfeuer oder im Gasthaus rastet.",
  medalLabel = "Neue Medaillen melden",
  medalTip = "Einblendung, sobald eine Medaillen-Stufe verdient ist. Die Medaillen stehen in der Chronik.",
  marksLabel = "To-Do-Gegner markieren",
  marksTip = "Zeile „To Do“ im Tooltip und Symbol an der Namensplakette von Gegnern, die ein offenes To Do braucht.",
  markSideLabel = "Lage des Symbols",
  markSideTip = "Wo das Symbol an der Namensplakette sitzt. Trägt dort schon ein anderes Addon (z. B. Questie) ein Symbol, rückt unseres automatisch nach außen oder auf die freie Seite.",
  markSideLeft = "Links",
  markSideRight = "Rechts",
  markSideTop = "Oben",
  reunionLabel = "Wiedersehen im Tooltip",
  reunionTip = "Zeigt im Tooltip eines Spielers, mit dem Ihr schon unterwegs wart (Dungeon, Lagerfeuer oder Gruppe), bis zu zwei kurze Erinnerungszeilen. Gilt für alle Charaktere.",
  fireNotesLabel = "Gesprächszettel am Lagerfeuer",
  fireNotesTip = "Sitzt Ihr am Lagerfeuer, schweben drei Zettel mit Gesprächsvorschlägen über dem Feuer. Linksklick sagt den Satz in /sagen, Rechtsklick verwirft ihn. Ein Klick auf die Glut unter den Zetteln holt einen neuen.",
  fireShowLabel = "Am Feuer zeigen",
  fireShowTip = "Rast-Karte und Zettel: erst die Karte, dann die Zettel (Standard) – beides zugleich – oder nur die Zettel (keine Rast-Karte am Lagerfeuer).",
  fireShowCard = "Karte, dann Zettel",
  fireShowBoth = "Beides",
  fireShowNotes = "Nur Zettel",
  fireAddressLabel = "Anrede in den Sätzen",
  fireAddressTip = "Wie die Vorschläge andere ansprechen: du, Ihr oder gemischt (je Zettel zufällig).",
  fireDu = "du",
  fireIhr = "Ihr",
  fireMix = "Gemischt",
  fireSmokeLabel = "Rauchzeichen",
  fireSmokeTip = "Kommt Ihr in die Nähe eines Lagerfeuers, zieht Rauch von links über den oberen Bildrand herein und legt den Schriftzug „Lagerfeuer in der Nähe“ frei. Danach blendet der Rauch in ein kleines Lagerfeuer mit aufsteigender Rauchsäule über, das dort bleibt, solange das Feuer nah ist. Verschieben lässt es sich im Bearbeitungsmodus.",
  firePlatesLabel = "Plaketten beim Hinsetzen einschalten",
  firePlatesTip = "Schaltet beim Hinsetzen die Namensplaketten freundlicher Spieler ein, damit die Chronik erkennt, wer mit am Feuer sitzt; beim Aufstehen kommt die alte Einstellung zurück.",
  shotsLabel = "Automatische Screenshots",
  shotsTip = "Bei besonderen Momenten (Stufenaufstieg, Tod, neues Gebiet, Kills seltener Gegner und Bosse) macht die Chronik selbst einen Screenshot. Abgeschaltet entstehen nur noch Eure eigenen.",
  meterLabel = "Schadensanzeige automatisch einschalten",
  meterTip = "Schaltet die Schadensanzeige des Spiels ein, damit Kämpfe Schaden und Heilung festhalten (wie /chronik messer).",
  showHiddenCharsLabel = "Ausgeblendete Charaktere zeigen",
  showHiddenCharsTip = "Zeigt in der Liste „Andere Bücher“ auch die Charaktere, die Ihr aus der Liste genommen habt (Rechtsklick auf einen Eintrag nimmt ihn wieder auf). Die Daten der Charaktere bleiben immer erhalten.",
  saveReminderLabel = "Speicher-Erinnerung",
  saveReminderTip = "Ein kleines Fenster fragt, ob Ihr die Reise sichern wollt: nach 30 Minuten ohne Sicherung, beim Abflug und nach einem Stufenaufstieg (nie im Kampf oder in Instanzen). WoW speichert Eure Daten nur beim Ausloggen oder Neuladen; bei einem Absturz geht der Stand seit dem letzten Einloggen verloren.",
  saveNowLabel = "Reise sichern",
  saveNowButton = "Jetzt sichern",
  saveNowTip = "Öffnet das Sichern-Fenster. „Sichern“ lädt dort die Oberfläche neu, damit das Spiel Eure Daten speichert.",
  shareLabel = "Reise teilen",
  shareButton = "Link zeigen",
  shareTip = "Erstellt einen Link zu einer Webseite, auf der Ihr all Eure Daten aufbereitet zum Teilen vorfindet.",
  diagLabel = "Diagnose",
  diagButton = "In den Chat",
  diagTip = "Schreibt den Zustand des Addons in den Chat (wie /chronik diag).",
  soundTip = "Klang für „%s“. Beim Auswählen erklingt er zur Probe; „Aus“ macht das Ereignis still.",
  previewTip = "Spielt den gewählten Klang für „%s“ einmal ab.",
})
Options.TEXT = TX

local function tx(key) return function() return TX[key] end end
local function txp(key) return function() return TX[key] .. " " .. TX.perChar end end

local function isSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) == true
end

local function say(msg)
  local Core = ns.Core
  if Core and type(Core.print) == "function" then Core.print(msg) elseif type(print) == "function" then print(msg) end
end

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, res = pcall(fn, ...)
  if ok then return res end
  return nil
end

local function F() return Journal.Frame end
local function V() return Journal.View end
local function TT() return Journal.TodoTracker end
local function QN() return Journal.QuickNote end
local function Toast() return Journal.Toast end
local function Sound() return Journal.Sound end

local function ttSetting(key)
  local T = TT()
  local s = T and call(T.settings)
  if type(s) ~= "table" then return nil end
  return s[key]
end

local function peek(key)
  local View = V()
  return View and call(View.peek, key)
end

local function bool(v) return v and true or false end

local function scaleGet()
  local Fr = F()
  local s = Fr and call(Fr.currentScale) or 1
  if type(s) ~= "number" or s ~= s then s = 1 end
  local pct = math.floor(s * 100 + 0.5)
  return math.max(50, math.min(200, pct))
end

local function scaleSet(pct)
  local Fr = F()
  if Fr and type(pct) == "number" then call(Fr.setScale, pct / 100) end
end

local function speedSet(v)
  local Fr = F()
  if Fr and Fr.state and Fr.state.st then
    call(Fr.setSpeed, v)
  else
    local View = V()
    if View then call(View.set, "speed", v) end
  end
end

local function speedOptions()
  local P = Journal.Playback
  local names = (P and P.SPEED_NAMES) or { [20] = TX.speedSlow, [60] = TX.speedMid, [180] = TX.speedFast }
  return { { value = 20, label = names[20] }, { value = 60, label = names[60] }, { value = 180, label = names[180] } }
end

local function ttText(key, fallback)
  local T = TT()
  local t = T and T.TEXT and T.TEXT[key]
  return type(t) == "string" and t or fallback
end

local function LT() return ns.Locale.T end

local function reload()
  local Save = ns.Save
  if Save and type(Save.show) == "function" then call(Save.show) end
end

-- Parts that only make sense in WoW Forever are hidden in Retail (items and groups with hidden = function; read on registering).
-- foreverOnly: trainer plan (Lehrplan) items; fireHidden: the campfire talk never starts in Retail (MapSpace.fireTalkHidden).
local function foreverOnly()
  local L = Journal.Lehrplan
  return L ~= nil and type(L.active) == "function" and L.active() == false
end

local function fireHidden()
  local ms = Journal.MapSpace
  return ms ~= nil and type(ms.fireTalkHidden) == "function" and ms.fireTalkHidden() == true
end

-- the own quest tracker exists only in WoW Forever (journal/QuestTrackerHide.lua, client switch MapSpace.retailClient)
local function questTrackerHidden()
  local Q = Journal.QuestTrackerHide
  return not (Q and type(Q.available) == "function" and Q.available() == true)
end

-- quest tracker switches (journal/model/QuestTrack.lua settings; account-wide)
local function qtGet(key)
  local Q = Journal.QuestTrack
  if not (Q and type(Q.settings) == "function") then return nil end
  local ok, s = pcall(Q.settings)
  if not ok or type(s) ~= "table" then return nil end
  local g, k = key:match("^(%a+)%.(%a+)$")
  if g then return type(s[g]) == "table" and s[g][k] or nil end
  return s[key]
end

local function qtSet(key, value)
  local Q = Journal.QuestTrack
  if Q and type(Q.set) == "function" then call(Q.set, key, value) end
end

local function qtCheck(key, setting, default)
  return { kind = "check", key = key, hidden = questTrackerHidden, enabledBy = "questTracker", label = tx(key .. "Label"),
    default = default, tip = tx(key .. "Tip"),
    get = function() return qtGet(setting) == true end,
    set = function(v) qtSet(setting, bool(v)) end }
end

local function qtChoice(key, setting, default, values, names)
  return { kind = "dropdown", key = key, hidden = questTrackerHidden, enabledBy = "questTracker", label = tx(key .. "Label"),
    default = default, varType = "string", tip = tx(key .. "Tip"),
    options = function()
      local n = TX[names]
      local list = {}
      for i, v in ipairs(values) do list[i] = { value = v, label = type(n) == "table" and n[v] or v } end
      return list
    end,
    get = function()
      local v = qtGet(setting)
      for _, x in ipairs(values) do if x == v then return v end end
      return default
    end,
    set = function(v) qtSet(setting, v) end }
end

-- font choice: "" = default, else a font name (built-in or from LibSharedMedia); a name that is gone shows as default
local function qtFont(key, setting)
  return { kind = "dropdown", key = key, hidden = questTrackerHidden, enabledBy = "questTracker", label = tx(key .. "Label"),
    default = "", varType = "string", tip = tx(key .. "Tip"),
    options = function()
      local list = { { value = "", label = TX.qtFontDefault or "Default" } }
      local Tr = Journal.QuestTracker
      local names = Tr and type(Tr.fontList) == "function" and call(Tr.fontList) or nil
      for _, n in ipairs(type(names) == "table" and names or {}) do list[#list + 1] = { value = n, label = n } end
      return list
    end,
    get = function()
      local v = qtGet(setting)
      local Tr = Journal.QuestTracker
      if type(v) == "string" and v ~= "" and Tr and type(Tr.fontFile) == "function" and call(Tr.fontFile, v) then return v end
      return ""
    end,
    set = function(v) qtSet(setting, type(v) == "string" and v or "") end }
end

local function smokeHidden()
  local S = Journal.Smoke
  return S ~= nil and S.active() == false
end

function Options.isHidden(entry)
  if type(entry.hidden) ~= "function" then return false end
  local ok, v = pcall(entry.hidden)
  return ok and v == true
end

Options.GROUPS = {
  -- First row under the panel title: the installed version (ns.version: "v1.0.5" from a release, "1.0.5-dev+<commit>" locally).
  -- Section header without rows, so it needs no extra widget and stays small.
  { title = function() return TX("version", ns.version) end, items = {} },
  {
    title = "Sprache / Language",
    items = {
      { kind = "dropdown", key = "locale", label = function() return LT().name end, default = "auto", varType = "string",
        tip = function() return LT().tip end,
        options = function()
          local Lc = ns.Locale
          local list = {}
          for i, s in ipairs(Lc.SETTINGS) do list[i] = { value = s, label = Lc.label(s) } end
          return list
        end,
        get = function() return ns.Locale.setting end,
        set = function(v)
          local Lc = ns.Locale
          local ok, changed = Lc.set(v)
          if ok and changed then say(LT()("changed", Lc.label(v))) end
        end },
      { kind = "button", key = "localeReload", label = function() return LT().reloadLabel end,
        button = function() return LT().reloadButton end, tip = function() return LT().reloadTip end,
        click = reload },
    },
  },
  {
    title = tx("gBook"),
    items = {
      { kind = "slider", key = "scale", label = tx("scaleLabel"), tip = tx("scaleTip"),
        min = 50, max = 200, step = 5, default = 75, get = scaleGet, set = scaleSet },
      { kind = "check", key = "reduceMotion", label = tx("reduceLabel"), default = false,
        tip = tx("reduceTip"),
        get = function() return bool(peek("reduceMotion")) end,
        set = function(v)
          local View, Fr = V(), F()
          if View then call(View.set, "reduceMotion", v) end
          if Fr then call(Fr.refresh) end
        end },
      { kind = "check", key = "minimap", label = tx("minimapLabel"), default = true,
        tip = tx("minimapTip"),
        get = function() return peek("minimap") ~= false end,
        set = function(v) local A = Journal.Access if A then call(A.setMinimap, v) end end },
      { kind = "check", key = "bookSounds", label = tx("soundsLabel"), default = true,
        tip = tx("soundsTip"),
        get = function() local S = Sound() return not S or S.enabled() end,
        set = function(v) local S = Sound() if S then S.setEnabled(v) end end },
      { kind = "button", key = "resetBook", label = tx("resetBookLabel"), button = tx("resetButton"),
        tip = tx("resetBookTip"),
        click = function() local A = Journal.Access if A then call(A.reset) end end },
      { kind = "button", key = "tutorial", label = tx("tutorialLabel"), button = tx("tutorialButton"),
        tip = tx("tutorialTip"),
        click = function() local Tu = Journal.Tutorial if Tu then call(Tu.open, 1) end end },
    },
  },
  {
    title = tx("gJourney"),
    items = {
      { kind = "dropdown", key = "mapColor", label = tx("mapColorLabel"), default = "sepia", varType = "string",
        tip = tx("mapColorTip"),
        options = function() return { { value = "sepia", label = TX.mapSepia }, { value = "original", label = TX.mapOriginal } } end,
        get = function() return peek("mapColor") == "original" and "original" or "sepia" end,
        set = function(v) local Fr = F() if Fr then call(Fr.setMapColor, v) end end },
      { kind = "check", key = "showKills", label = tx("killsLabel"), default = true,
        tip = tx("killsTip"),
        get = function() return peek("showKills") ~= false end,
        set = function(v) local Fr = F() if Fr then call(Fr.setShowKills, v) end end },
      { kind = "check", key = "revealMap", label = tx("revealLabel"), default = false,
        tip = tx("revealTip"),
        get = function() return peek("revealMap") == true end,
        set = function(v) local Fr = F() if Fr then call(Fr.setRevealMap, v) end end },
      { kind = "check", key = "showIcons", label = tx("iconsLabel"), default = true,
        tip = tx("iconsTip"),
        get = function() return peek("showIcons") ~= false end,
        set = function(v) local Fr = F() if Fr then call(Fr.setShowIcons, v) end end },
      { kind = "dropdown", key = "speed", label = tx("speedLabel"), default = 60, varType = "number",
        tip = tx("speedTip"),
        options = speedOptions,
        get = function() local v = peek("speed") return (v == 20 or v == 60 or v == 180) and v or 60 end,
        set = speedSet },
      { kind = "check", key = "worldMap", label = tx("worldMapLabel"), default = true,
        tip = tx("worldMapTip"),
        get = function() local WL = Journal.WorldLayer return not WL or WL.enabled() end,
        set = function(v) local WL = Journal.WorldLayer if WL then call(WL.setEnabled, v) end end },
      { kind = "check", key = "worldPins", label = tx("worldPinsLabel"), default = true,
        tip = tx("worldPinsTip"),
        get = function() local WL = Journal.WorldLayer return not WL or WL.placesEnabled() end,
        set = function(v) local WL = Journal.WorldLayer if WL then call(WL.setPlacesEnabled, v) end end },
    },
  },
  {
    title = tx("gTodo"),
    items = {
      { kind = "check", key = "todoShown", label = function() return ttText("optShown", TX.fbShown) end, default = false,
        tip = txp("todoShownTip"),
        get = function() return ttSetting("shown") == true end,
        set = function(v) local T = TT() if T then call(T.setShown, v) end end },
      { kind = "check", key = "todoDock", label = function() return ttText("optDock", TX.fbDock) end, default = false,
        tip = txp("todoDockTip"),
        get = function() return ttSetting("dock") == true end,
        set = function(v) local T = TT() if T and T.setDock then call(T.setDock, v) end end },
      { kind = "dropdown", key = "todoDockSide", label = function() return ttText("dockSideLabel", TX.fbDockSide) end, default = "below",
        varType = "string", tip = txp("todoDockSideTip"),
        options = function()
          local T = TT()
          local names = (T and T.TEXT and T.TEXT.dockSide) or TX.fbDockSides
          return { { value = "below", label = names.below }, { value = "above", label = names.above } }
        end,
        get = function() return ttSetting("dockSide") == "above" and "above" or "below" end,
        set = function(v) local T = TT() if T and T.setDockSide then call(T.setDockSide, v) end end },
      { kind = "dropdown", key = "todoStyle", label = function() return ttText("styleLabel", TX.fbStyle) end, default = "pad", varType = "string",
        tip = txp("todoStyleTip"),
        options = function()
          local T = TT()
          local names = (T and T.TEXT and T.TEXT.style) or { pad = TX.fbPad, plain = TX.fbPlain }
          return { { value = "pad", label = names.pad }, { value = "plain", label = names.plain } }
        end,
        get = function() return ttSetting("style") == "plain" and "plain" or "pad" end,
        set = function(v) local T = TT() if T then call(T.setStyle, v) end end },
      { kind = "dropdown", key = "todoOpen", label = function() return ttText("openLabel", TX.fbOpen) end, default = "always", varType = "string",
        tip = txp("todoOpenTip"),
        options = function()
          local T = TT()
          local names = (T and T.TEXT and T.TEXT.openModes) or TX.fbOpenModes
          local list = {}
          for i, m in ipairs((T and T.OPEN_MODES) or { "always", "hover", "click", "auto" }) do list[i] = { value = m, label = names[m] } end
          return list
        end,
        get = function() local v = ttSetting("open") return type(v) == "string" and v or "always" end,
        set = function(v) local T = TT() if T and T.setOpen then call(T.setOpen, v) end end },
      { kind = "dropdown", key = "todoGrow", label = function() return ttText("growLabel", TX.fbGrow) end, default = "down", varType = "string",
        tip = txp("todoGrowTip"),
        options = function()
          local T = TT()
          local names = (T and T.TEXT and T.TEXT.grow) or TX.fbGrowNames
          return { { value = "down", label = names.down }, { value = "up", label = names.up } }
        end,
        get = function() local v = ttSetting("grow") return v == "up" and "up" or "down" end,
        set = function(v) local T = TT() if T and T.setGrow then call(T.setGrow, v) end end },
      { kind = "check", key = "todoLocked", label = function() return ttText("optLocked", TX.fbLocked) end, default = false,
        tip = txp("todoLockedTip"),
        get = function() return ttSetting("locked") == true end,
        set = function(v) local T = TT() if T then call(T.setLocked, v) end end },
      { kind = "check", key = "todoCombat", label = function() return ttText("optCombat", TX.fbCombat) end, default = false,
        tip = txp("todoCombatTip"),
        get = function() return ttSetting("combatHide") == true end,
        set = function(v) local T = TT() if T then call(T.setCombatHide, v) end end },
      { kind = "check", key = "todoEmpty", label = function() return ttText("optEmpty", TX.fbEmpty) end, default = true,
        tip = txp("todoEmptyTip"),
        get = function() return ttSetting("hideEmpty") == true end,
        set = function(v) local T = TT() if T then call(T.setHideEmpty, v) end end },
      { kind = "check", key = "todoAuto", label = function() return ttText("optAuto", TX.fbAuto) end, default = true,
        tip = txp("todoAutoTip"),
        get = function() return ttSetting("autoShow") == true end,
        set = function(v) local T = TT() if T and T.setAutoShow then call(T.setAutoShow, v) end end },
      { kind = "check", key = "trainerTodo", hidden = foreverOnly, label = tx("trainerTodoLabel"), default = true,
        tip = tx("trainerTodoTip"),
        get = function() local P = Journal.Pages return not P or P.setting("trainerTodo") ~= false end,
        set = function(v) local P = Journal.Pages if P then P.setSetting("trainerTodo", bool(v)) end end },
      { kind = "check", key = "professionBar", hidden = function() return foreverOnly() or Journal.ProfessionBar == nil end, default = true,
        label = function() local B = Journal.ProfessionBar return B and B.TEXT.optLabel or "" end,
        tip = function() local B = Journal.ProfessionBar return B and B.TEXT.optTip or "" end,
        get = function() local B = Journal.ProfessionBar return not B or B.setting() end,
        set = function(v) local B = Journal.ProfessionBar if B then call(B.setEnabled, bool(v)) end end },
      { kind = "check", key = "auctionDock", hidden = function() return foreverOnly() or Journal.AuctionDock == nil end, default = true,
        label = function() local B = Journal.AuctionDock return B and B.TEXT.optLabel or "" end,
        tip = function() local B = Journal.AuctionDock return B and B.TEXT.optTip or "" end,
        get = function() local B = Journal.AuctionDock return not B or B.setting() end,
        set = function(v) local B = Journal.AuctionDock if B then call(B.setEnabled, bool(v)) end end },
      { kind = "button", key = "todoReset", label = tx("todoResetLabel"), button = tx("resetButton"),
        tip = tx("todoResetTip"),
        click = function() local T = TT() if T then call(T.reset) end end },
    },
  },
  {
    title = tx("gQuestTracker"), hidden = questTrackerHidden,
    items = {
      { kind = "check", key = "questTracker", hidden = questTrackerHidden, label = tx("questTrackerLabel"), default = false,
        tip = tx("questTrackerTip"),
        get = function() local Q = Journal.QuestTrackerHide return Q ~= nil and Q.storedOn() == true end,
        set = function(v) local Q = Journal.QuestTrackerHide if Q then call(Q.setEnabled, bool(v)) end end },
      qtChoice("qtMode", "mode", "tracked", { "tracked", "log", "zone" }, "qtModes"),
      qtChoice("qtOrder", "order", "zones", { "zones", "distance", "level" }, "qtOrders"),
      qtChoice("qtDone", "done", "inZone", { "inZone", "group" }, "qtDones"),
      qtChoice("qtTodo", "panel.todo", "top", { "top", "bottom" }, "qtTodoAt"),
      qtCheck("qtHideDone", "filter.done", false),
      qtCheck("qtHideGroup", "filter.group", false),
      qtCheck("qtZoneOnly", "filter.zoneOnly", false),
      qtCheck("qtObjs", "look.objs", true),
      { kind = "check", key = "qtDoneObj", hidden = questTrackerHidden, enabledBy = "questTracker", label = tx("qtDoneObjLabel"),
        default = true, tip = tx("qtDoneObjTip"),
        get = function() return qtGet("look.doneObj") ~= "hide" end,
        set = function(v) qtSet("look.doneObj", bool(v) and "strike" or "hide") end },
      qtCheck("qtDist", "look.dist", false),
      qtCheck("qtIcons", "look.icons", true),
      qtCheck("qtFocus", "focus.show", true),
      qtCheck("qtFocusDist", "focus.dist", true),
      qtCheck("qtFocusBar", "focus.bar", true),
      qtCheck("qtFocusGiver", "focus.giver", true),
      qtCheck("qtFocusRew", "focus.rewards", true),
      qtCheck("qtNotify", "panel.notify", true),
      qtCheck("qtHideInfo", "panel.hideInfo", true),
      qtCheck("qtHover", "panel.hover", true),
      { kind = "slider", key = "qtDelay", hidden = questTrackerHidden, enabledBy = "questTracker", label = tx("qtDelayLabel"), tip = tx("qtDelayTip"),
        min = 0, max = 2000, step = 100, default = 600, format = function(v) return string.format("%d ms", math.floor((tonumber(v) or 0) + 0.5)) end,
        get = function() return qtGet("panel.delay") or 600 end,
        set = function(v) qtSet("panel.delay", tonumber(v)) end },
      { kind = "slider", key = "qtScale", hidden = questTrackerHidden, enabledBy = "questTracker", label = tx("qtScaleLabel"), tip = tx("qtScaleTip"),
        min = 80, max = 140, step = 5, default = 100,
        get = function() return math.floor((qtGet("panel.scale") or 1) * 100 + 0.5) end,
        set = function(v) qtSet("panel.scale", (tonumber(v) or 100) / 100) end },
      { kind = "slider", key = "qtGripScale", hidden = questTrackerHidden, enabledBy = "questTracker", label = tx("qtGripScaleLabel"), tip = tx("qtGripScaleTip"),
        min = 70, max = 160, step = 5, default = 100, format = function(v) return string.format("%d %%", math.floor((tonumber(v) or 0) + 0.5)) end,
        get = function() return math.floor((qtGet("panel.gripScale") or 1) * 100 + 0.5) end,
        set = function(v) qtSet("panel.gripScale", (tonumber(v) or 100) / 100) end },
      { kind = "slider", key = "qtGripAlpha", hidden = questTrackerHidden, enabledBy = "questTracker", label = tx("qtGripAlphaLabel"), tip = tx("qtGripAlphaTip"),
        min = 10, max = 100, step = 5, default = 40, format = function(v) return string.format("%d %%", math.floor((tonumber(v) or 0) + 0.5)) end,
        get = function() return math.floor((qtGet("panel.gripAlpha") or 0.4) * 100 + 0.5) end,
        set = function(v) qtSet("panel.gripAlpha", (tonumber(v) or 40) / 100) end },
      qtCheck("qtSyncFocus", "panel.syncFocus", true),
      qtCheck("qtPanMap", "panel.panMap", true),
      { kind = "slider", key = "qtBgAlpha", hidden = questTrackerHidden, enabledBy = "questTracker", label = tx("qtBgAlphaLabel"), tip = tx("qtBgAlphaTip"),
        min = 50, max = 100, step = 2, default = 96, format = function(v) return string.format("%d %%", math.floor((tonumber(v) or 0) + 0.5)) end,
        get = function() return math.floor((qtGet("panel.bgAlpha") or 0.96) * 100 + 0.5) end,
        set = function(v) qtSet("panel.bgAlpha", (tonumber(v) or 96) / 100) end },
      { kind = "slider", key = "qtFadeWidth", hidden = questTrackerHidden, enabledBy = "questTracker", label = tx("qtFadeWidthLabel"), tip = tx("qtFadeWidthTip"),
        min = 0, max = 120, step = 4, default = 36, format = function(v) return string.format("%d px", math.floor((tonumber(v) or 0) + 0.5)) end,
        get = function() return qtGet("panel.fadeWidth") or 36 end,
        set = function(v) qtSet("panel.fadeWidth", tonumber(v)) end },
      { kind = "slider", key = "qtFadeTime", hidden = questTrackerHidden, enabledBy = "questTracker", label = tx("qtFadeTimeLabel"), tip = tx("qtFadeTimeTip"),
        min = 0, max = 1000, step = 50, default = 300, format = function(v) return string.format("%d ms", math.floor((tonumber(v) or 0) + 0.5)) end,
        get = function() return math.floor((qtGet("panel.fadeTime") or 0.3) * 1000 + 0.5) end,
        set = function(v) qtSet("panel.fadeTime", (tonumber(v) or 300) / 1000) end },
      { kind = "slider", key = "qtFontScale", hidden = questTrackerHidden, enabledBy = "questTracker", label = tx("qtFontScaleLabel"), tip = tx("qtFontScaleTip"),
        min = 80, max = 150, step = 5, default = 100, format = function(v) return string.format("%d %%", math.floor((tonumber(v) or 0) + 0.5)) end,
        get = function() return math.floor((qtGet("panel.fontScale") or 1) * 100 + 0.5) end,
        set = function(v) qtSet("panel.fontScale", (tonumber(v) or 100) / 100) end },
      qtFont("qtFontHead", "panel.fontHead"),
      qtFont("qtFontText", "panel.fontText"),
      qtCheck("qtItemBar", "panel.itemBar", true),
      qtCheck("qtItemBarNear", "panel.itemBarNear", true),
      { kind = "button", key = "qtUnhide", hidden = questTrackerHidden, enabledBy = "questTracker", label = tx("qtUnhideLabel"), button = tx("qtUnhideButton"),
        tip = tx("qtUnhideTip"),
        click = function() local Q = Journal.QuestTrack if Q then call(Q.clearHidden) end end },
      { kind = "button", key = "qtReset", hidden = questTrackerHidden, enabledBy = "questTracker", label = tx("qtResetLabel"), button = tx("resetButton"),
        tip = tx("qtResetTip"),
        click = function() local Tr = Journal.QuestTracker if Tr and Tr.resetPlace then call(Tr.resetPlace) end end },
    },
  },
  {
    title = tx("gQuick"),
    items = {
      { kind = "check", key = "quickShown", label = tx("quickLabel"), default = false,
        tip = txp("quickTip"),
        get = function() local Q = QN() local s = Q and call(Q.settings) return type(s) == "table" and s.shown == true end,
        set = function(v) local Q = QN() if Q then call(Q.setShown, v) end end },
      { kind = "dropdown", key = "quickStyle", label = tx("quickStyleLabel"), default = "pad", varType = "string",
        tip = txp("quickStyleTip"),
        options = function()
          local T = TT()
          local names = (T and T.TEXT and T.TEXT.style) or { pad = TX.fbPad, plain = TX.fbPlain }
          return { { value = "pad", label = names.pad }, { value = "plain", label = names.plain } }
        end,
        get = function() local Q = QN() local s = Q and call(Q.settings) return type(s) == "table" and s.style == "plain" and "plain" or "pad" end,
        set = function(v) local Q = QN() if Q then call(Q.setStyle, v) end end },
    },
  },
  {
    title = tx("gToasts"),
    items = {
      { kind = "check", key = "toast", label = tx("toastLabel"), default = true,
        tip = tx("toastTip"),
        get = function() local T = Toast() return not T or T.enabled() end,
        set = function(v) local T = Toast() if T then call(T.setEnabled, v) end end },
      { kind = "check", key = "toastZone", label = tx("toastZoneLabel"), default = true,
        tip = tx("toastZoneTip"),
        get = function() local T = Toast() return not T or T.kindOn("zone") end,
        set = function(v) local T = Toast() if T then call(T.setKind, "zone", v) end end },
      { kind = "check", key = "toastSound", label = tx("toastSoundLabel"), default = true,
        tip = tx("toastSoundTip"),
        get = function() local T = Toast() return not T or T.soundOn() end,
        set = function(v) local T = Toast() if T then call(T.setSound, v) end end },
      { kind = "check", key = "talentHint", hidden = foreverOnly, label = tx("talentHintLabel"), default = true,
        tip = tx("talentHintTip"),
        get = function() local P = Journal.Pages return not P or P.setting("talentHint") ~= false end,
        set = function(v) local P = Journal.Pages if P then P.setSetting("talentHint", bool(v)) end end },
      { kind = "check", key = "todoToast", hidden = foreverOnly, label = tx("todoToastLabel"), default = true,
        tip = tx("todoToastTip"),
        get = function() local P = Journal.Pages return not P or P.setting("todoToast") ~= false end,
        set = function(v) local P = Journal.Pages if P then P.setSetting("todoToast", bool(v)) end end },
      { kind = "check", key = "welcome", label = tx("welcomeLabel"), default = true,
        tip = tx("welcomeTip"),
        get = function() local B = Journal.Begleiter return not B or B.welcomeOn() end,
        set = function(v) local B = Journal.Begleiter if B then call(B.setWelcome, v) end end },
      { kind = "dropdown", key = "narrator", label = tx("narratorLabel"), default = "own", varType = "string",
        tip = tx("narratorTip"),
        options = function()
          local list = { { value = "own", label = TX.narratorOwn }, { value = "random", label = TX.narratorRandom } }
          local names = TX.narratorNames or {}
          for _, id in ipairs((Journal.Theme and Journal.Theme.NARRATORS) or {}) do
            list[#list + 1] = { value = id, label = names[id] or id }
          end
          return list
        end,
        get = function() local B = Journal.Begleiter return B and B.narratorChoice() or "own" end,
        set = function(v) local B = Journal.Begleiter if B then call(B.setNarrator, v) end end },
      { kind = "check", key = "levelSlip", hidden = foreverOnly, label = tx("levelSlipLabel"), default = true,
        tip = tx("levelSlipTip"),
        get = function() local P = Journal.Pages return not P or P.setting("levelSlip") ~= false end,
        set = function(v) local P = Journal.Pages if P then P.setSetting("levelSlip", bool(v)) end end },
      { kind = "check", key = "milestoneSlip", hidden = foreverOnly, label = tx("milestoneSlipLabel"), default = true,
        tip = tx("milestoneSlipTip"),
        get = function() local P = Journal.Pages return not P or P.setting("milestoneSlip") ~= false end,
        set = function(v) local P = Journal.Pages if P then P.setSetting("milestoneSlip", bool(v)) end end },
      -- the next five depend on the greeting: greyed out while it is off (enabledBy)
      { kind = "dropdown", key = "welcomeAfter", label = tx("welcomeAfterLabel"), default = 3600, varType = "number",
        tip = tx("welcomeAfterTip"), enabledBy = "welcome",
        options = function()
          local list = { { value = 0, label = TX.afterNow } }
          for _, sec in ipairs({ 3600, 7200, 14400, 28800, 86400 }) do list[#list + 1] = { value = sec, label = TX.afterHours[sec] } end
          return list
        end,
        get = function() local B = Journal.Begleiter return B and B.afterSeconds() or 3600 end,
        set = function(v) local B = Journal.Begleiter if B then call(B.setAfter, v) end end },
      { kind = "check", key = "welcomeSeen", label = tx("welcomeSeenLabel"), default = true,
        tip = tx("welcomeSeenTip"), enabledBy = "welcome",
        get = function() local B = Journal.Begleiter return not B or B.infoOn("seen") end,
        set = function(v) local B = Journal.Begleiter if B then call(B.setInfo, "seen", v) end end },
      { kind = "check", key = "welcomeQuests", label = tx("welcomeQuestsLabel"), default = true,
        tip = tx("welcomeQuestsTip"), enabledBy = "welcome",
        get = function() local B = Journal.Begleiter return not B or B.infoOn("quests") end,
        set = function(v) local B = Journal.Begleiter if B then call(B.setInfo, "quests", v) end end },
      { kind = "check", key = "welcomeRested", label = tx("welcomeRestedLabel"), default = true,
        tip = tx("welcomeRestedTip"), enabledBy = "welcome",
        get = function() local B = Journal.Begleiter return not B or B.infoOn("rested") end,
        set = function(v) local B = Journal.Begleiter if B then call(B.setInfo, "rested", v) end end },
      { kind = "check", key = "welcomePlan", label = tx("welcomePlanLabel"), default = true,
        tip = tx("welcomePlanTip"), enabledBy = "welcome",
        get = function() local B = Journal.Begleiter return not B or B.infoOn("plan") end,
        set = function(v) local B = Journal.Begleiter if B then call(B.setInfo, "plan", v) end end },
      { kind = "check", key = "restReview", label = tx("restLabel"), default = false,
        tip = tx("restTip"),
        get = function() local B = Journal.Begleiter return not B or B.restOn() end,
        set = function(v) local B = Journal.Begleiter if B then call(B.setRest, v) end end },
    },
  },
  {
    title = tx("gMedals"),
    items = {
      { kind = "check", key = "toastMedal", label = tx("medalLabel"), default = true,
        tip = tx("medalTip"),
        get = function() local T = Toast() return not T or T.kindOn("medal") end,
        set = function(v) local T = Toast() if T then call(T.setKind, "medal", v) end end },
    },
  },
  {
    title = tx("gMarks"),
    items = {
      { kind = "check", key = "todoMarks", label = tx("marksLabel"), default = true,
        tip = txp("marksTip"),
        get = function() return ttSetting("marks") ~= false end,
        set = function(v) local TM = Journal.TodoMarks if TM then call(TM.setEnabled, v) end end },
      { kind = "dropdown", key = "todoMarkSide", label = tx("markSideLabel"), default = "left", varType = "string",
        tip = txp("markSideTip"),
        options = function()
          return { { value = "left", label = TX.markSideLeft }, { value = "right", label = TX.markSideRight },
            { value = "top", label = TX.markSideTop } }
        end,
        get = function() local TM = Journal.TodoMarks return TM and TM.side() or "left" end,
        set = function(v) local TM = Journal.TodoMarks if TM then call(TM.setSide, v) end end },
      { kind = "check", key = "reunion", label = tx("reunionLabel"), default = true,
        tip = tx("reunionTip"),
        get = function() local R = Journal.Reunion return not R or R.enabled() end,
        set = function(v) local R = Journal.Reunion if R then call(R.setEnabled, v) end end },
    },
  },
  {
    title = tx("gFire"), hidden = fireHidden,
    items = {
      { kind = "check", key = "fireNotes", label = tx("fireNotesLabel"), default = true,
        tip = tx("fireNotesTip"),
        get = function() local F = Journal.FireNotes return not F or F.settings().notes end,
        set = function(v) local F = Journal.FireNotes if F then call(F.setEnabled, v) end end },
      { kind = "dropdown", key = "fireShow", label = tx("fireShowLabel"), default = "cardFirst", varType = "string",
        tip = tx("fireShowTip"),
        options = function()
          return { { value = "cardFirst", label = TX.fireShowCard }, { value = "both", label = TX.fireShowBoth },
            { value = "notesOnly", label = TX.fireShowNotes } }
        end,
        get = function() local F = Journal.FireNotes return F and F.settings().show or "cardFirst" end,
        set = function(v) local F = Journal.FireNotes if F then call(F.setShow, v) end end },
      { kind = "dropdown", key = "fireAddress", label = tx("fireAddressLabel"), default = "du", varType = "string",
        tip = tx("fireAddressTip"),
        options = function()
          return { { value = "du", label = TX.fireDu }, { value = "ihr", label = TX.fireIhr }, { value = "mix", label = TX.fireMix } }
        end,
        get = function() local CT = Journal.CampfireTalk return CT and CT.settings().address or "du" end,
        set = function(v) local CT = Journal.CampfireTalk if CT then call(CT.setAddress, v) end end },
      { kind = "check", key = "fireSmoke", label = tx("fireSmokeLabel"), default = true, hidden = smokeHidden,
        tip = tx("fireSmokeTip"),
        get = function() local S = Journal.Smoke return not S or S.settings().enabled end,
        set = function(v) local S = Journal.Smoke if S then call(S.setEnabled, v) end end },
      { kind = "check", key = "firePlates", label = tx("firePlatesLabel"), default = true,
        tip = tx("firePlatesTip"),
        get = function() local C = ns.Campfire return not C or C.settings().showFriendPlates ~= false end,
        set = function(v) local C = ns.Campfire if C then call(C.set, "showFriendPlates", v and true or false) end end },
    },
  },
  { title = tx("gSounds"), sounds = true, items = {} },
  {
    title = tx("gMisc"),
    items = {
      { kind = "check", key = "autoShots", label = tx("shotsLabel"), default = true,
        tip = tx("shotsTip"),
        get = function() local P = Journal.Pages return not P or P.setting("autoShots") ~= false end,
        set = function(v) local P = Journal.Pages if P then P.setSetting("autoShots", bool(v)) end end },
      { kind = "check", key = "meterAuto", label = tx("meterLabel"), default = true,
        tip = tx("meterTip"),
        get = function() return type(ns.meterAutoOn) ~= "function" or ns.meterAutoOn() end,
        set = function(v) if type(ns.meterSlash) == "function" then call(ns.meterSlash, v and "an" or "aus") end end },
      { kind = "check", key = "showHiddenChars", label = tx("showHiddenCharsLabel"), default = false,
        tip = tx("showHiddenCharsTip"),
        get = function() local P = Journal.Pages return P ~= nil and P.setting("showHiddenChars") == true end,
        set = function(v) local P = Journal.Pages if P then P.setSetting("showHiddenChars", bool(v)) end end },
      { kind = "check", key = "saveReminder", label = tx("saveReminderLabel"), default = false,
        tip = tx("saveReminderTip"),
        get = function() local S = ns.Save return S ~= nil and S.enabled() end,
        set = function(v) local P = Journal.Pages if P then P.setSetting("saveReminder", bool(v)) end end },
      -- the label carries the quiet status line; it is refreshed when the menu is opened (Options.open), never by a ticker
      { kind = "button", key = "saveNow", label = function() return Options.saveNowLabel() end, button = tx("saveNowButton"),
        tip = tx("saveNowTip"),
        click = function() local S = ns.Save if S and type(S.offer) == "function" then S.offer() end end },
      { kind = "button", key = "share", label = tx("shareLabel"), button = tx("shareButton"),
        tip = tx("shareTip"),
        click = function() local S = Journal.Share if S and type(S.open) == "function" then call(S.open, "journey") end end },
      { kind = "button", key = "diag", label = tx("diagLabel"), button = tx("diagButton"),
        tip = tx("diagTip"),
        click = function() local Core = ns.Core if Core then call(Core.runDiag) end end },
    },
  },
}

do
  local S = Sound()
  for _, g in ipairs(Options.GROUPS) do
    if g.sounds and S then
      for _, e in ipairs(S.EVENTS) do
        g.items[#g.items + 1] = { kind = "sound", key = "sound_" .. e.key, event = e.key, default = "default",
          varType = "string",
          label = function() return S.eventLabel(e) end,
          tip = function() return TX("soundTip", S.eventLabel(e)) end,
          get = function() return S.choice(e.key) end,
          set = function(v) if S.setChoice(e.key, v) then S.preview(e.key, v) end end }
      end
    end
  end
end

local applying = false

local function varType(kind, item)
  local VT = type(Settings) == "table" and Settings.VarType or nil
  local t = item.varType or (kind == "check" and "boolean") or (kind == "slider" and "number") or "string"
  if VT then
    if t == "boolean" then return VT.Boolean or t end
    if t == "number" then return VT.Number or t end
    return VT.String or t
  end
  return t
end

local function txt(v)
  if type(v) == "function" then
    local ok, s = pcall(v)
    return ok and s or ""
  end
  return v
end

local function textContainer(list)
  local c = Settings.CreateControlTextContainer()
  for _, o in ipairs(list) do c:Add(o.value, o.label) end
  return c:GetData()
end

local function soundMenu(item, setting)
  return function(root)
    local S, K, San = Sound(), Journal.SoundKits, ns.Sanitize
    if not S or type(root) ~= "table" or type(root.CreateButton) ~= "function" then return end
    local function radio(desc, text, key)
      desc:CreateRadio(text, function() return S.choice(item.event) == key end, function() setting:SetValue(key) end, key)
    end
    if K then
      local game = root:CreateButton(S.TEXT.game)
      for _, g in ipairs(K.GROUPS) do
        local sub = game:CreateButton(K.groupLabel(g))
        for _, e in ipairs(K.LIST) do
          if e.g == g.key then radio(sub, K.nameOf(e), "kit:" .. e.id) end
        end
      end
    end
    local own = root:CreateButton(S.TEXT.own)
    for _, f in ipairs(S.FILES) do radio(own, S.fileName(f), "file:" .. f.file) end
    local lsm = root:CreateButton(S.TEXT.lsm)
    local names = S.lsmNames()
    if #names == 0 then
      if type(lsm.CreateTitle) == "function" then lsm:CreateTitle(S.TEXT.lsmEmpty) end
    else
      if type(lsm.SetScrollMode) == "function" then lsm:SetScrollMode(480) end
      for _, n in ipairs(names) do radio(lsm, (San and San.display(n, 60)) or "?", "lsm:" .. n) end
    end
  end
end

local inits = {}

-- greys a row out while the row it depends on (item.enabledBy = key of a check) is off: the client's own parent mechanism
-- (initializer:SetParentInitializer(parent, predicate)); clients without it simply keep the row enabled
local function bindParent(init, item)
  local parent = item.enabledBy and inits[item.enabledBy]
  if type(init) ~= "table" or not parent then return end
  local function enabled()
    local ok, v = pcall(parent.item.get)
    return not ok or v == true
  end
  if type(init.SetParentInitializer) == "function" then
    pcall(init.SetParentInitializer, init, parent.init, enabled)
  elseif type(init.AddModifyPredicate) == "function" then
    pcall(init.AddModifyPredicate, init, enabled)
  end
end

-- "Reise sichern: Zuletzt gesichert vor N min" (status line of Save.lua), without Save just the plain label
function Options.saveNowLabel()
  local S = ns.Save
  local line = S and type(S.statusText) == "function" and call(S.statusText)
  if type(line) ~= "string" then return TX.saveNowLabel end
  return TX.saveNowLabel .. ": " .. line
end

local buttonInits = {}

-- re-reads the labels of button rows that carry live text (the settings list reads the initializer name when a row is shown)
local function refreshButtonLabels()
  for _, b in pairs(buttonInits) do
    local init = b.init
    local data = type(init) == "table" and type(init.GetData) == "function" and call(init.GetData, init)
    if type(data) == "table" then data.name = txt(b.item.label) end
  end
end

local function register(category, layout, item)
  local var = Options.PREFIX .. item.key
  if item.kind == "button" then
    if type(CreateSettingsButtonInitializer) ~= "function" then return end
    local init = CreateSettingsButtonInitializer(txt(item.label), txt(item.button), function() item.click() end, txt(item.tip), true)
    layout:AddInitializer(init)
    bindParent(init, item)
    if item.key == "saveNow" then buttonInits[item.key] = { init = init, item = item } end
    return
  end
  local get, set = item.get, item.set
  local label, tip = txt(item.label), txt(item.tip)
  local setting = Settings.RegisterProxySetting(category, var, varType(item.kind, item), label, item.default,
    function()
      local ok, v = pcall(get)
      if not ok or v == nil or isSecret(v) then return item.default end
      return v
    end,
    function(v)
      applying = true
      pcall(set, v)
      applying = false
    end)
  Options.settings[item.key] = setting
  Options.order[#Options.order + 1] = item.key
  if item.kind == "check" then
    local init = Settings.CreateCheckbox(category, setting, tip)
    inits[item.key] = { init = init, item = item }
    bindParent(init, item)
  elseif item.kind == "slider" then
    local opts = Settings.CreateSliderOptions(item.min, item.max, item.step)
    local M = rawget(_G, "MinimalSliderWithSteppersMixin")
    if type(opts.SetLabelFormatter) == "function" and type(M) == "table" and type(M.Label) == "table" and M.Label.Right then
      opts:SetLabelFormatter(M.Label.Right, item.format or function(v) return string.format("%d %%", math.floor((tonumber(v) or 0) + 0.5)) end)
    end
    local sInit = Settings.CreateSlider(category, setting, opts, tip)
    bindParent(sInit, item)
  elseif item.kind == "dropdown" then
    local init = Settings.CreateDropdown(category, setting, function() return textContainer(item.options()) end, tip)
    inits[item.key] = { init = init, item = item }
    bindParent(init, item)
  elseif item.kind == "sound" then
    local S = Sound()
    local init = Settings.CreateDropdown(category, setting, function()
      return textContainer({ { value = "default", label = S.TEXT.default }, { value = "off", label = S.TEXT.off } })
    end, tip)
    if type(init) == "table" then
      init.customOptionHandler = soundMenu(item, setting)
      init.getSelectionTextFunc = function() return S.label(S.choice(item.event)) end
    end
    if type(CreateSettingsButtonInitializer) == "function" then
      local btn = CreateSettingsButtonInitializer(label, Options.TEXT.preview, function() S.preview(item.event) end,
        TX("previewTip", label), false)
      layout:AddInitializer(btn)
    end
  end
end

function Options.register()
  if Options.category then return true end
  if type(Settings) ~= "table" or type(Settings.RegisterVerticalLayoutCategory) ~= "function"
    or type(Settings.RegisterProxySetting) ~= "function" then
    return false
  end
  local function fail(err)
    Options.lastError = tostring(err)
    local Core = ns.Core
    if Core and type(Core.coreError) == "function" then pcall(Core.coreError, err) end
  end
  local ok, category, layout = pcall(Settings.RegisterVerticalLayoutCategory, Options.NAME)
  if not ok or type(category) ~= "table" or type(layout) ~= "table" then
    fail(category)
    return false
  end
  Options.category = category
  for _, g in ipairs(Options.GROUPS) do
    if not Options.isHidden(g) then
      if type(CreateSettingsListSectionHeaderInitializer) == "function" then
        local okH, err = pcall(function() layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(txt(g.title))) end)
        if not okH then fail(err) end
      end
      for _, item in ipairs(g.items) do
        if not Options.isHidden(item) then
          local okI, err = pcall(register, category, layout, item)
          if not okI then fail(err) end
        end
      end
    end
  end
  local okR, err = pcall(Settings.RegisterAddOnCategory, category)
  if not okR then fail(err) end
  Options.categoryID = type(category.GetID) == "function" and category:GetID() or category.ID
  return true
end

function Options.open()
  if inCombat() then
    say(Options.TEXT.combat)
    return false
  end
  if not Options.register() then
    say(Options.TEXT.unavailable)
    return false
  end
  if type(Settings.OpenToCategory) ~= "function" or Options.categoryID == nil then
    say(Options.TEXT.unavailable)
    return false
  end
  refreshButtonLabels()
  local ok = pcall(Settings.OpenToCategory, Options.categoryID)
  if not ok then say(Options.TEXT.failed) end
  return ok
end

function Options.refresh()
  if applying or not Options.category then return end
  local panel = rawget(_G, "SettingsPanel")
  if type(panel) == "table" and type(panel.IsShown) == "function" and not panel:IsShown() then return end
  for _, key in ipairs(Options.order) do
    local s = Options.settings[key]
    if type(s) == "table" and type(s.NotifyUpdate) == "function" then pcall(s.NotifyUpdate, s) end
  end
end

do
  local T, Q = TT(), QN()
  if T and type(T.listeners) == "table" then T.listeners[#T.listeners + 1] = function() Options.refresh() end end
  if Q and type(Q.listeners) == "table" then Q.listeners[#Q.listeners + 1] = function() Options.refresh() end end
  local C = ns.Campfire
  if C and type(C.onSettingsChanged) == "function" then C.onSettingsChanged(function() Options.refresh() end) end
  local S = Sound()
  if S and type(S.onMedia) == "function" then
    S.onMedia(function() Options.refresh() end)
    S.lsm()
  end
end

-- Register on ADDON_LOADED, after Locale.apply: the chosen language is only known once the SavedVariables are loaded.
do
  local Core = ns.Core
  local hooked = Core and type(Core.on) == "function"
    and Core.on("ADDON_LOADED", function(_, name) if name == ADDON_NAME then Options.register() end end)
  if not hooked then Options.register() end
end
