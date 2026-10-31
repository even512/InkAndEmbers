# EveN_ForeverChronicle

Reise-Chronik als WoW-Addon für **WoW Forever**. Das Addon schreibt jede Levelreise als Ereignis-Chronik mit (Zeit, Ort,
Level) und zeigt sie als Reisejournal im Spiel (`/chronik`). Gespeichert wird account-weit in `EveNChronicleDB`, getrennt je
Charakter; das Log-Format (siehe unten) ist ein fester Vertrag, auf dem auch Auswertungen außerhalb des Spiels aufsetzen können.

Umfang: Kern, Speicher, Muster, Säubern und Sichern-Hinweis, dazu die Sammler `Progress`
(Level-Up, /played, Erfahrung, Ruhe-XP), `Quests` (Lebenslauf, Textarchiv, Questlinien), `Books`, `Combat` (Kills,
Kämpfe, knappe Siege), `Death` (Todesbericht, Ursache, Weg zurück), `World` (erste Ankunft, Entdeckungen, Flugpunkte),
`Trail` (Positionsspur), `Travel` (Flüge, Ruhestein, Überfahrten), `Instance` (Besuche, Bosse, Beute) und `Moments`
(Meilensteine, Auto-Screenshots). Dazu `Money` (Gold-Verlauf nach Quelle und Zweck, Auktionshaus), `Loot` (Funde ab
Grün einzeln, darunter Zähler), `Gear` (Ausrüstungswechsel, Schnappschuss je Level), `Character` (Zauber, Talente, Berufe,
Ruf, Werte je Level), `Social` (Gruppen, Gilde, Duelle, PvP, Handel, Post) und `Extras` (Verbrauch, Emotes, Angeln).

## Voraussetzungen
- Node 20 oder neuer (nur für Tests und Installationsskript; das Addon selbst braucht nichts)
- WoW Forever bzw. der Retail-Client (für den Test) installiert

## Installation
1. `npm install`
2. `.env.example` nach `.env` kopieren und `WOW_DIR` setzen, z. B. `WOW_DIR=D:\World of Warcraft`
   (`.env` bleibt lokal und ist in `.gitignore`).
3. Addon installieren:
   - Forever: `npm run install-addon`  (nach `<WOW_DIR>\_forever_\Interface\AddOns\EveN_ForeverChronicle`)
   - Retail-Test: `npm run install-addon -- --retail`  (nach `_retail_`, in der kopierten TOC wird `## Interface: 120105` gesetzt)
   - Vorschau ohne Schreiben: zusätzlich `-- --dry-run`
4. Bei NEUEN Dateien (z. B. neue `.tga`/`.ttf`) das Spiel komplett neu starten, sonst reicht `/reload`.

`install-addon` arbeitet inkrementell (unveränderte Dateien werden nicht angefasst, Überzähliges im eigenen Addon-Ordner entfernt), folgt keinen Symlinks und bricht mit einer
klaren Meldung ab, wenn `.env`/`WOW_DIR` oder der Ordner `_forever_`/`_retail_` fehlt.

## Befehle
| Befehl | Zweck |
|---|---|
| `npm test` | vitest: Addon in einer Lua-VM (fengari) gegen eine nachgebaute WoW-API (Kern, Speicher, Muster, Sichern, alle Sammler, Größentest 1→60, dauert rund 30 s) |
| `npm run check` | Syntaxcheck aller `.lua`-Dateien mit luaparse (Lua 5.1) |
| `npm run types-doc` | Kürzel-Tabelle unten aus `ns.Types` (Store.lua) neu schreiben (`-- --check` prüft nur) |
| `npm run install-addon` | Addon in den WoW-Ordner kopieren (siehe oben, `--help` zeigt alle Optionen) |
| `npm run data` | Datenaddons neu erzeugen: `build-todo-data.mjs` (Gegner/Gegenstände) und `build-quest-data.mjs --fetch` (offene Quests). Braucht Eingaben, die nicht im Repo liegen, siehe „Questdaten neu erzeugen“. Mit gesetztem `CHRONICLE_FETCH_SCRIPT` holt `--fetch` vorher den aktuellen QuestieDB-Stand, ohne das Skript wird der vorhandene Stand benutzt |

## Datenquellen und Lizenz
- **Offene Quests** (`addon/EveN_ForeverChronicle_QuestData`, LoadOnDemand): erzeugt von `scripts/build-quest-data.mjs` aus
  **QuestieDB** (Questie-Team und Beitragende; Release-Kanal `preview`, Stand steht in der TOC `## X-QuestieDB-Version` und im
  Kopf jeder Lua-Datei), fraktionsabhängige Korrekturen (Horde **und** Allianz) aus den Korrektur-Dateien eines installierten
  QuestieDB-Addons (`WOW_DIR\_forever_`, nur geparst, nie ausgeführt), Gebiet → Karte und deutsche Namen aus der
  Forever-Datenbank (data.morthen.net), englische Namen für nicht-deutsche Clients (`Names.lua`) und
  alle Karten-Overlays je Zone (`Overlays.lua`, aufgedeckte Zonenkarten; wago.tools-Tabellen, als Schnappschuss in
  `scripts/data`). Format: Kopfkommentar von `scripts/build-quest-data.mjs`.
- **Gegner/Gegenstände** (`addon/EveN_ForeverChronicle_Data`): `scripts/build-todo-data.mjs`, ebenfalls aus QuestieDB und der
  Forever-Datenbank.
- **Lizenzlage QuestieDB:** keine eindeutige Lizenz; die Betreiber erlauben Kopien unter **GPLv3**, für ältere Beiträge ist das
  nicht gesichert („im Zweifel all rights reserved"), Name und Logo „Questie" ausgenommen —
  https://github.com/Questie/QuestieDB/blob/master/LICENSE.md . Die abgeleiteten Daten liegen deshalb in eigenen,
  abschaltbaren Datenaddons unter **GPL-3.0** mit Quellenangabe (`LICENSE`, `LICENSE-NOTE.md` im jeweiligen Ordner).
  Spielwelt-Inhalte © Blizzard Entertainment.

## Questdaten neu erzeugen
Die Datenaddons (`addon/EveN_ForeverChronicle_QuestData`, `addon/EveN_ForeverChronicle_Data`) sind eingecheckt und werden
mitgeliefert; neu erzeugt werden müssen sie nur bei neuem QuestieDB-Stand oder neuem Spiel-Build. Die Generatoren
(`npm run data`, einzeln `node scripts/build-quest-data.mjs` und `node scripts/build-todo-data.mjs`, `--help` zeigt alle Optionen)
lesen nur lokale Dateien und schreiben nur in den Zielordner. Die Ausgabe ist reproduzierbar (sortiert, ohne Zeitstempel):
gleiche Eingaben ergeben byte-gleiche Dateien.

Eingaben und ihre Beschaffung (Pfade per Option oder als Umgebungsvariable bzw. Zeile in der lokalen `.env`, siehe `.env.example`):

| Eingabe | Option / Variable | Woher |
|---|---|---|
| QuestieDB im Forever-Stand (`QuestieDB_Forever.toc`, Quests, NPCs, Objekte, Gegenstände) | `--questie` / `CHRONICLE_QUESTIE_TOC`, sonst automatisch unter `WOW_DIR\_forever_\Interface\AddOns\QuestieDB` bzw. `_classic_beta_` | öffentlich: das QuestieDB-Addon (https://github.com/Questie/QuestieDB, Release-Kanal `preview`; per Addon-Verwaltung oder Release-ZIP) |
| Korrekturen je Fraktion (`src/corrections/…` von QuestieDB, nur geparst) | `--corrections`, sonst Ordner der TOC bzw. `WOW_DIR` | im selben QuestieDB-Addon; fehlen sie, gibt der Generator eine Warnung aus (Allianz-Geber können dann falsch sein) |
| Zonen-Zuordnung (Gebiet → Karte, Instanzen), deutsche Namen, Questtypen | `--forever` / `CHRONICLE_FOREVER_DB` | Dump der Forever-Datenbank von https://data.morthen.net : `data/forever/zones.json`, `data/forever/search.json`, `data/forever/l10n/deDE/search.json` und `data/forever/quest/*.json`, in dieselbe Ordnerstruktur gelegt (der Ordner `forever`). Es gibt keine Garantie auf dauerhafte Verfügbarkeit oder eine freie Lizenz; die Daten sind nicht im Repo |
| Karten-Overlays (aufgedeckte Zonenkarten) | `--overlays`, `--overlays-retail` / `CHRONICLE_OVERLAYS`, `CHRONICLE_OVERLAYS_RETAIL` | Schnappschuss im Repo (`scripts/data`, rund 0,8 MB, Quelle und Neubeschaffung dort in der README): wago.tools-Tabellen `UiMapXMapArt`, `WorldMapOverlay`, `WorldMapOverlayTile` je Build |

Ablauf: Eingaben bereitstellen, `.env` anlegen (oder die Optionen angeben), `npm run data`; danach `npm test` (der Test
„baut aus den lokalen Quellen genau den eingecheckten Stand“ läuft nur, wenn die Eingaben vorhanden sind) und
`npm run install-addon`. Fehlt eine Eingabe, bricht der Generator mit einer Meldung ab, die den fehlenden Pfad und die
passende Option nennt.

## Lizenz
- Hauptaddon `addon/EveN_ForeverChronicle`: **MIT** (© 2026 EveN); die Grafiken und Medien (Ordner `Media`, Bilddateien) sind
  davon ausgenommen: alle Rechte vorbehalten, soweit Schutz besteht. Siehe `addon/EveN_ForeverChronicle/LICENSE`.
- Datenaddons `EveN_ForeverChronicle_QuestData` und `EveN_ForeverChronicle_Data`: **GPL-3.0**.
- Eingebettete Bibliotheken, Schriften (SIL OFL) und Klänge (CC0) behalten ihre Lizenz:
  `addon/EveN_ForeverChronicle/THIRD-PARTY.md`.
- Teile der Grafiken sind mit KI-Werkzeugen (Google Gemini) entstanden und vom Autor bearbeitet.

## Release (CurseForge)
Pakete baut der BigWigs-Packager aus einem Tag `v*` (`.pkgmeta`, `.github/workflows/release.yml`, Secret `CF_API_KEY` als Secret der Umgebung `release`, Actions auf Commit-SHA gepinnt);
Tags mit `beta` bzw. `alpha` im Namen werden als Beta/Alpha hochgeladen. Die Simulation (`journal/SimPanel.lua`, `/chronik sim`)
gehört nicht ins Paket. Vor einem Tag: `npm run check`.

## Unterstützen
Unterstützung: folgt
(Nur hier und auf der CurseForge-Seite, nie im Spiel.)

## Ingame-Befehle
| Befehl | Zweck |
|---|---|
| `/chronik` | Reisejournal öffnen/schließen (auch Minimap-Knopf, Addon-Menü, Tastenkürzel) |
| `/chronik status` | Statuszeile: sammelt seit …, Ereignisse, zuletzt gesichert vor X min, Sammler aktiv a/b |
| `/chronik minimap` | Minimap-Knopf ein-/ausblenden |
| `/chronik reset` | Größe und Position des Reisejournals auf Standard (Rettungsweg, falls das Fenster zu groß geraten ist) |
| `/chronik toast` | Toast für neue Medaillen und neue Gebiete ein-/ausschalten (`an`/`aus`; `test` zeigt zwei Beispiele; `zettel` bleibt als stiller Alias). Schlichtes Ein-/Ausblenden, keine Animationen. Nie im Kampf, höchstens 3 wartend, Klick öffnet Chronik bzw. Reise-Karte |
| `/chronik ton` | Ton des Toasts ein-/ausschalten (spielt beim Einschalten beide Töne vor und nennt die Sound-IDs) |
| `/chronik diag` | Selbsttest aller Schnittstellen und Sammler, Ergebnis nach `EveNChronicleDB.diag` |
| `/chronik sichern` | öffnet das Sichern-Fenster (gesichert wird erst per Klick auf „Sichern", das lädt die Oberfläche neu) |
| `/chronik hilfe` | Befehlsliste |

Nach 60 min ohne Sichern erscheint rechts oben ein kleines Fenster „Reise sichern?". Im Kampf und in Instanzen
wartet es auf den nächsten erlaubten Moment. „Später" verschiebt um 30 min.

## Ordnerstruktur
```
addon/EveN_ForeverChronicle/   das Addon (TOC, Core, Store, Zone, Context, Patterns, Sanitize, Save, collectors/)
  journal/                     Reisejournal: Model.lua (Kapitel, Route, Marker, Notizen; liest nur, schreibt nur EveNChronicleDB.ui), Geo.lua (Kartenumrechnung, austauschbar)
scripts/                       check-lua.mjs, install-addon.mjs, types-doc.mjs, build-todo-data.mjs, build-quest-data.mjs
```

## Log-Format (Vertrag)
Dieser Abschnitt ist der Vertrag für die spätere Webseite. Die Kürzel-Tabelle unten wird aus `ns.Types` in
`addon/EveN_ForeverChronicle/Store.lua` erzeugt (`npm run types-doc`),.

### Datei und Schema
Der Client schreibt `WTF\Account\<KONTO>\SavedVariables\EveN_ForeverChronicle.lua` mit der Variable `EveNChronicleDB`:

```
EveNChronicleDB = {
  schema = 1,                 -- Format-Version, ein Leser prüft sie zuerst
  addonVersion = "<Version laut TOC>",
  meta = {
    sessions = { {            -- account-weit, chronologisch
      guid, start, stop,      -- Epoch (UTC); stop = Logout; fehlt bei offener (Reload) oder unterbrochener Sitzung
      lastSave,               -- letzte Sicherung (Logout oder Reload)
      build, buildNumber, interface, locale, tz,
      reloads,                -- Anzahl Reloads in der Sitzung
      interrupted, lastKnown, -- Absturz erkannt: true + letzte bekannte Zeit
    }, … },
    tzOffset,                 -- Ortszeit minus UTC (Sekunden) der letzten Sitzung
    reloadAt,                 -- nur zwischen Reload-Logout und nächstem Login gesetzt
  },
  diag = { collectors, apis, patterns, client, restrictions, state, core, lastRun },
  chars = { ["Player-…"] = {
    info = { name, realm, race, raceFile, class, classFile, faction, factionName, firstSeen, lastSeen },
    lineCount,                -- Zahl aller Log-Zeilen (für die Statuszeile)
    log = { "<Block>", … },   -- nur Strings, nie Zeilen-Tabellen
    trail = { "<Spur-Block>", … },  -- Positionsspur, eigener Strom (siehe unten)
    quests = { [questID] = { firstAt, <feld>, <feld>At, … } }, books = { [schlüssel] = { firstAt, … } },
    npcs = { [npcID] = "Name" },
    counters = { [gruppe] = { [schlüssel] = n } },
    snapshots = { [art] = { [schlüssel] = { at, … } } },  -- z. B. Ausrüstung und Werte je Level
    shots = { ["MMDDYY_HHMMSS"] = { at, … } },             -- Screenshot-Zuordnung (Ortszeit im Dateinamen)
  } },
}
```

Eine Sitzung reicht vom Einloggen bis zum Ausloggen (`O`, `stop`). Ein Reload (Sichern-Knopf, `/reload`) setzt dieselbe
Sitzung fort: `S` beim Neuladen (`stop` bleibt leer, `reloadAt` gesetzt), `R` danach, `reloads` wird hochgezählt. Die
Reload-Kennung gilt nur 2 s; ein geblockter Reload mit späterer Abmeldung zählt als normales Logout. Ein Absturz ohne
jedes Speichern seit dem Login hinterlässt keine Spur: Die Datei kennt diese Sitzung nicht. Fehlt beim nächsten Einloggen das Ende, war es ein Absturz: Die Sitzung
bekommt `interrupted = true`, und der betroffene Charakter bekommt eine `X`-Zeile.

### Blockformat
- Jeder Eintrag in `log` ist **ein String** mit 1–500 Zeilen, getrennt durch `\n`.
- Erste Zeile ist der Block-Kopf `#~<epoch>~<session>`. `<epoch>` ist `time()` (UTC-Sekunden) beim Öffnen des
  Blocks, `<session>` der Index in `meta.sessions` (0 = unbekannt).
- Jede weitere Zeile hat die Form `<dt>~<kürzel>~<feld1>~<feld2>~…`. `<dt>` sind Sekunden seit `<epoch>` des Kopfes,
  die absolute Zeit ist also `epoch + dt`.
- Ein neuer Block beginnt nach 500 Zeilen und nach jedem Login bzw. Reload. Beim Logout oder Reload wird der offene
  Block geschlossen.
- Leere Felder am Zeilenende fallen weg. Ein Leser behandelt fehlende Felder wie leere.

### Spur-Strom (`trail`)
- Eigener Strom je Charakter, getrennt vom Log. Jeder Eintrag ist ein String mit 1–500 Punkten.
- Kopf `#~<epoch>~<mapID>`, danach Zeilen `<dt>~<x>~<y>` oder `<dt>~<x>~<y>~<mark>`. `<dt>` sind Sekunden seit
  `<epoch>`, `x`/`y` die Kartenkoordinaten in Zehntel-Promille (0–9999) auf der Karte `<mapID>` (uiMapID).
- `<mark>` kennzeichnet Pflichtpunkte, die unabhängig vom Abstand gesetzt werden: `z` Zonenwechsel, `d` Tod, `f` Abflug,
  `l` Landung. Ohne Markierung ist es ein Bewegungspunkt: ab 22 Yards Abstand (Weltposition) bzw. ohne Weltposition ab
  0,3 % der Karte, geprüft alle 3 s. Im Flug pausiert die Spur, im Kampf läuft sie weiter. Ohne lesbare Position (Instanz)
  steht einmal je Pause eine `TP`-Zeile im Log.
- Ein neuer Block beginnt bei Kartenwechsel, nach 500 Punkten und nach Login bzw. Reload. Beim Logout wird der offene
  Block geschlossen.

### Schnappschüsse und Screenshots
- `snapshots[art][schlüssel]`: Zahlen mit höchstens 2 Nachkommastellen (gerundet, als Zahl gespeichert), Texte gesäubert,
  `at` = Zeitpunkt. Pro Schlüssel wird nur einmal geschrieben, außer der Sammler ersetzt ausdrücklich.
- `shots[schlüssel]`: Der Schlüssel `MMDDYY_HHMMSS` ist die Ortszeit wie im Dateinamen `WoWScrnShot_MMDDYY_HHMMSS.jpg`,
  `at` ist die Epoch (UTC). Die Webseite ordnet Dateien mit ±2 s Toleranz zu. Felder: `reasons` (Anlässe wie in `SH`),
  `auto` (`true` = vom Addon ausgelöst), `level`, `mapID`.
- Auto-Screenshots (F6): nie im Kampf, höchstens einer je 10 s. Anlässe im Kampf warten bis Kampfende + 0,5 s, weitere
  Anlässe werden zum nächsten Bild zusammengefasst. Level-Up nach 1,5 s, Tod erst nach dem Freilassen des Geistes.
  Elite-Kills in Instanzen sind kein Anlass (dort ist fast jeder Gegner Elite), Rare und Boss schon.
- Feste Schnappschuss-Gruppen (E4, siehe auch "Zähler und Namens-Caches" unten): `items[itemID]` (`name`, `quality`),
  `spells[spellID]` (`name`, `rank`), `factions[factionID]` (`name`), `skills[skillLineID]` (`name`), `gear[level]` (Ausrüstung nach dem
  Level-Up: `[slot] = Item-Schlüssel`, `ilvl`), `stats[level]` (Werte nach dem Level-Up: `str`, `agi`, `sta`, `int`, `spi`, `armor`,
  `health`, `power`, `crit`, `spellCrit`, `dodge`, `parry`, `block`, `attackPower`, `spellPower`, `healing`), `talents[spent]`
  (`[nodeID] = Rang` bei dieser Punktesumme), `talentNodes[nodeID]` (`x`, `y`, `spellID`, `maxRanks`), `mailseen[Rechnung]`
  (interner Stand der Auktionshaus-Rechnungen: je Rechnung ein Eintrag `Art:Name:Partner:Preis:Gebot:Menge`, der entfernt wird, sobald
  die Rechnung nicht mehr im Postfach liegt; ist die Obergrenze erreicht, merkt sich der Sammler den Stand nur für die Sitzung und
  vermerkt `diag.limits["mailseen.session"]`) und `state.money`, `state.group`, `state.guild`, `state.talents` (interne
  Stände über Reloads; `state.talents` hat `ok = 1` neben den Rängen). Die älteren Gruppen: `maps[mapID]` (Kartenname), `zones[mapID]` / `subzones["<mapID>:<Name>"]` /
  `continents[mapID]` (erste Ankunft: `seen`, `level`, `at`), `instances[instanceID]` (`name`, `type`),
  `encounters[encounterID]` (`name`), `moments[kind]` (erstes Mal: `seen`, `value`, `detail`, `level`, `at`) und
  `state.instance` (laufender Instanzbesuch: `open`, `id`, `start`, `kills`, `deaths`, `bosses`; überlebt Reloads).

### Zähler und Namens-Caches (E4)
- `counters[gruppe][schlüssel] = n`: Geld in Kupfer, sonst Stückzahlen.
  - `money_in[quelle]`, `money_out[zweck]`: Summen aus GD (loot, quest, vendor_sell, vendor_buy, repair, training, taxi, ah, ah_sale, mail,
    trade, guildbank, other, gap), `ah[aktion]`. `repair`: "Alle reparieren" wird per Hook erkannt; eine **Einzelreparatur** (Reparatur-Cursor)
    nur als Näherung, nämlich wenn beim Geldabgang ein Händler offen ist und `InRepairMode()` wahr ist (bleibt der Cursor aktiv, kann ein
    Kauf im selben Moment als `repair` gebucht werden; fehlt `InRepairMode`, steht die Einzelreparatur als `vendor_buy`).
    `PlaceBid` dient auch dem Sofortkauf: er steht als `bid` im AH-Log, die Rechnung der Post liefert später `bought`.
  - Beute: `loot[itemID]` (Funde unter Grün aus Beutefenstern, Menge), `bought`, `crafted`, `received`, `quest_items` (dasselbe nach Weg),
    `loot_quality[0-5]` (alle Funde nach Qualität).
  - Charakter: `gather[ore|herb|leather]` (Näherung aus der Gegenstandsklasse Handwerkswaren: Erz und Kräuter aus Objekten, Leder aus Gegnern).
  - Soziales: `mates[Name]` (wie oft gruppiert), `duels[ergebnis]`, `pvp[kills|deaths]`, `trade[completed|cancelled]`, `mail[received|sent]`.
  - Extras: `consumables[itemID]` (Benutzungen), `consumed[potion|elixir|flask|food_drink|bandage|other]` (Essen und Trinken sind nicht
    trennbar), `reagents[itemID]` (Näherung: Abnahme der Reagenzien kurz nach einem eigenen Zauber, nicht beim Händler, in der Post, im Handel,
    in der Bank oder im Auktionshaus), `emotes[TOKEN]` (`unknown`: Text-Emote ohne Token), `fishing[itemID]`.
  - `unreadable[...]`: gesperrte Meldungen (Secret Values), die nicht gelesen werden konnten: `loot_msg`, `money_msg`, `emote_msg`.
- Item-Schlüssel (LT, GW, TH, PM, PS, snapshots.gear): `<itemID>`, bei Zufallszusatz oder Bonus-IDs `<itemID>.s<suffix>.b<bonusID>…`
  (Zufallszusatz = suffixID ungleich 0, höchstens 8 Bonus-IDs). Nie ein Link. Die Qualität steht in `snapshots.items` und in LT.
- Gesperrte oder fehlende Schnittstellen werden nicht geraten: Felder bleiben leer oder `?`, die Zähler unter `unreadable` zeigen, was
  nicht lesbar war. Beute-Meldungen, Rechnungen, Gruppen und Handel brauchen lesbare Chat-Meldungen und Einheiten.
- Meilensteine über das interne Signal `FC_MOMENT` an Moments (MO): `first_blue`, `first_epic` (Qualität 3 bzw. ab 4, beim Fund oder Anlegen,
  mit Screenshot-Anlass `item`), `first_bag`, `mount` (mit Screenshot-Anlass `item`), `reputation` (Rufstufe erreicht), `profession`
  (Beruf neu gelernt oder Wert über 75, 150, 225, 300).
- Gruppen-Näherung: GE zählt alle Kills (KI), abgegebenen Quests und betretenen Instanzen, solange Ihr in der Gruppe seid (nicht nur
  gemeinsame). GI nennt die Mitspieler beim Betreten einer Instanz (die Gruppengröße steht auch in IE).

### Werte und Escape-Regeln
- Zahlen sind immer Ganzzahlen (`%d`), nie `1e+09` oder Nachkommastellen. Brüche werden vorher skaliert
  (z. B. Kartenkoordinaten in Zehntel-Promille).
- Wahrheitswerte sind `1` / `0`. Ein leeres Feld heißt „kein Wert". `?` heißt: Der Wert war im Client gesperrt
  (Secret Value, nicht lesbar).
- Texte in Feldern sind gesäubert: Farbcodes, Texturen und Steuerzeichen sind entfernt, Links auf ihren Anzeigetext
  reduziert. Außerdem wird `~` zu `-`, ein Zeilenumbruch zu einem Leerzeichen und `|` zu `/`. Höchstens 250 Bytes.
- Langtexte (Quest- und Buchtexte) stehen nicht im Log, sondern in `quests`/`books`. Sie sind ebenso gesäubert,
  behalten aber ihre Absätze (`\n`). Jedes Feld wird nur einmal geschrieben (`firstAt` = Zeit des ersten Eintrags,
  ein später ergänztes Feld `f` bekommt zusätzlich `fAt`, z. B. `progressAt`).
- Die Webseite gibt alle Texte nur escaped aus, nie als HTML.
- Quests: `quests[questID]` mit `title`, `detail` (Annahmetext), `objectives`, `progress`, `reward`, `rewardMoney`, `choices` (Zahl der
  Wahl-Items), `giver`/`giverNpc`, `qlevel`, `mapID`; `firstAt` und `<feld>At` zeigen, wann jedes Feld erstmals erfasst wurde.
  Seit R2 zusätzlich `rewardChoices` (alle Wahl-Items des Abgabefensters) und `rewardItems` (feste Belohnungs-Items), je eine
  Liste `{ { id = itemID, n = Anzahl (nur wenn > 1) }, … }` (höchstens 10, erfasst bei `QUEST_COMPLETE`); Name und Qualität
  stehen in `snapshots.items`. Welches Wahl-Item genommen wurde, steht wie bisher in QT/QR. Ältere Einträge haben die Listen nicht.
  Verlauf je Quest = QA/QT/QX per questID + Textfelder; fehlt `<feld>At`, gilt `firstAt`.
  Seit R3 zusätzlich `category`: der Kopf (Header) über der Quest im Questlog bei der Annahme (z. B. die Zone); fehlt er, fehlt
  das Feld. Quests, die schon archiviert sind und noch im Questlog stehen, bekommen ihn beim nächsten Questlog-Abgleich nachgetragen.
  Unterwegs-Schritte stehen als `QO` im Log (je Ziel nur echter Zuwachs von `have`, Ereignisse gebündelt, je Ziel höchstens
  `need` bzw. 100 Zeilen, der Endstand `have >= need` aber immer einmal); der Stand beim Login, Reload und bei der Annahme wird nur gemerkt, nicht geschrieben.
- Questketten (F15): `questLine` (questLineID), `questLineName`, `questLinePos` (Position der Quest in der Kette, ab 1) und
  `questLineLen` (Zahl der Quests der Kette), soweit `C_QuestLine` sie lesbar liefert; sonst fehlen die Felder. Erfasst
  bei Dialog, Annahme oder Abgabe, jeweils nur einmal.
- Bücher: `books[key]` mit `title`, `material`, `mapID`, Seiten als `p1`, `p2`, … (HTML entfernt, Absätze als `\n`) und `pages`
  (Seitenzahl, sobald die letzte Seite gelesen wurde). Der Schlüssel `key` ist ein stabiler 16-stelliger Hash aus Titel, Material und
  erster Seite. Gelesen werden nur Seiten, die der Spieler selbst aufschlägt.
- Namens-Caches: `npcs[npcID]` (Questgeber, Gegner, Flugmeister, Todesverursacher) und `snapshots.maps[mapID].name`
  (Kartennamen für alle `mapID`-Felder).
- Weiche Obergrenzen: höchstens 2000 Quests, 500 Bücher, 5000 NPC-Namen, 2000 Schlüssel je Zähler-Gruppe (`loot` und `consumables`: 6000) sowie in
  `snapshots` 3000 Karten (`maps`), 3000 besuchte Karten (`zones`), 5000 Unterzonen, 500 Instanzen, 1000 Begegnungen, 6000 Gegenstände
  (`items`), 2000 Zauber (`spells`), 500 Fraktionen, 300 Fertigkeiten, 500 Talentknoten, 300 Talentstände und 2000 Rechnungen (`mailseen`);
  darüber werden keine neuen Einträge angelegt, `diag.limits` vermerkt es (z. B. `snapshots.maps`). Namen und Titel
  (`title`, `giver`, `material`, `name`, `questLineName`, `category`) stehen einzeilig.
- Kampf ohne Kampflog: `COMBAT_LOG_EVENT_UNFILTERED` ist gesperrt und wird nie registriert. Ein Kill (`KI`) kommt aus
  `PARTY_KILL`; Name, Stufe und Klassifikation stammen aus einem Cache (Ziel, Mouseover, Namensplaketten, höchstens 200
  Einträge) oder der noch sichtbaren Einheit. „Knapper Sieg" (`KF.close`) ist eine **Näherung**: Leben am Kampfende unter
  10 %, weil das Leben im Kampf gesperrt ist. Ursachen in `DC` und Wege in `DB` mit `guess = 1` sind vermutet.
- Position bei **allen** Kills (Nachtrag N1): `KI` trägt `x`/`y` (Position des Charakters beim Kill) auch bei normalen Gegnern, leer
  nur wenn die Karte sie nicht herausgibt (meist in Instanzen). Ältere Zeilen trugen `x`/`y` nur bei Rare/Elite/Boss und bleiben
  gültig: Felder am Zeilenende können fehlen, Leser behandeln sie wie leere.
- Unterzone (Nachtrag N3): `MO`, `SH`, `LV` und `DE` tragen als **letztes** Feld `sub` den Namen der Unterzone
  (`GetSubZoneText`, wie jedes Feld gesäubert, höchstens 60 Bytes), leer ohne Namen oder wenn gesperrt. Zeilen ohne `sub` bleiben gültig.
- Beobachter (Nachtrag N2, nur für Code im Addon, kein Datenformat): `Store.observer = function(code, fields) … end` wird nach
  jedem gespeicherten `Store.append` in `pcall` gerufen (`fields` = Feldtexte wie im Log, Gesperrtes als `?`). Ohne Beobachter
  kostet ein Append nur eine Abfrage; Fehler im Beobachter zählen in `Store.observerErrors` und `diag.limits.observer_error`.
- `/played` (F10): angefragt bei Login/Reload und nach dem Level-Up, bewusst **nicht** beim Logout (die Antwort käme nach dem
  Abmelden nicht mehr an). Anlass in `PL`: `login`, `reload`, `levelup`.
- `XP` mit `via=unclear`: Mehrfach-Stufensprung, Betrag unbekannt und deshalb nicht gebucht.

### Größe (Größentest)
Der Größentest erzeugt über die echte Store-API eine Reise 1 → 60 mit allen Kürzeln: 20.000 Kills mit Erfahrung, rund 8.000
Kämpfe, 600 Quests mit allen Texten, über 10.000 Gold-Änderungen, Funde, Tode mit Todesbericht, Gruppen, Handel, Post, Talente, Berufe,
Ruf und 120.000 Spurpunkte (alle 3 s ein Punkt über 100 Stunden, der Worst-Case). Gemessen (Stand Nachträge N1–N3): **7,09 MB** SV-Datei (7.436.602 Bytes; MB = 1024 × 1024 Bytes, dezimal also 7,44 MB)
(Log 3,3 MB in 143 Blöcken mit 71.250 Zeilen, Spur 1,7 MB in 240 Blöcken; vor N1 und N3: 6,90 MB), **33.700 verschiedene / 99.713 gesamte Konstanten**
(Limit von Lua 5.1: 262.143, Ziel höchstens 50 % = 131.071). Der Test prüft außerdem, dass jedes Kürzel vorkommt, alle Zahlen ganzzahlig
sind und die Datei in einer frischen Lua-VM fehlerfrei lädt.

### Kürzel
<!-- types:begin (erzeugt aus ns.Types, npm run types-doc) -->
| Kürzel | Bedeutung | Felder (nach `<dt>~<kürzel>~`, in dieser Reihenfolge) |
|---|---|---|
| `L` | **Login**: Neue Sitzung beginnt (Einloggen). | 1. `session`: Sitzungsnummer (Index in meta.sessions)<br>2. `build`: Client-Version, z. B. 12.1.5<br>3. `buildNumber`: Build-Nummer, z. B. 70575<br>4. `interface`: Interface-Nummer (16001 Forever, 120105 Retail)<br>5. `locale`: Client-Sprache, z. B. deDE<br>6. `tz`: Zeitzonen-Versatz in Sekunden (Ortszeit minus UTC) |
| `R` | **Reload**: Dieselbe Sitzung geht nach einem Reload (Sichern, /reload) weiter. | 1. `session`: Sitzungsnummer |
| `S` | **Gesichert**: Die Oberfläche wird neu geladen, die Daten sind bis hier gesichert. Danach folgt R in derselben Sitzung. | 1. `session`: Sitzungsnummer |
| `O` | **Logout**: Sitzung endet (Ausloggen oder Beenden). | 1. `session`: Sitzungsnummer<br>2. `duration`: Dauer der Sitzung in Sekunden |
| `X` | **Sitzung unterbrochen**: Beim nächsten Login fehlte das Ende der Sitzung (Absturz). Steht als eigener Ein-Zeilen-Block im Log des betroffenen Charakters. | 1. `session`: Nummer der unterbrochenen Sitzung<br>2. `lastKnown`: letzte bekannte Zeit (Epoch, letzte Sicherung) |
| `LV` | **Level-Up**: Der Charakter hat eine neue Stufe erreicht. | 1. `level`: neue Stufe<br>2. `mapID`: Karte (uiMapID) am Ort des Level-Ups; Name in snapshots.maps<br>3. `x`: Position West-Ost auf dieser Karte (0-9999)<br>4. `y`: Position Nord-Süd auf dieser Karte (0-9999)<br>5. `sub`: Name der Unterzone (GetSubZoneText, gesäubert, höchstens 60 Bytes), leer wenn ohne Namen oder nicht lesbar |
| `PL` | **Spielzeit**: Antwort auf /played (nach Login, Reload und Level-Up angefragt; beim Logout nicht, dort kommt keine Antwort mehr an). | 1. `total`: gesamte Spielzeit in Sekunden<br>2. `thisLevel`: Spielzeit auf der aktuellen Stufe in Sekunden<br>3. `level`: Stufe des Charakters<br>4. `reason`: Anlass: login, reload, levelup oder leer (andere Anfrage, z. B. eigenes /played) |
| `XP` | **Erfahrung**: Ein Erfahrungsgewinn. Zweigleisig erfasst: aus der Chat-Meldung (msg) und als Kontrolle aus der Differenz von PLAYER_XP_UPDATE (diff). Jeder Gewinn steht genau einmal da. | 1. `source`: Quelle: kill, quest, explore oder other (nur als Differenz erkannt oder nicht zuzuordnen)<br>2. `amount`: Erfahrungspunkte (bei Meldungen der Wert aus der Meldung, bei Differenz die gemessene Änderung); leer bei via unclear<br>3. `rested`: Ruhebonus in Punkten (negativ = Abzug), leer wenn keiner genannt<br>4. `group`: Gruppenbonus in Punkten (negativ = Schlachtzugsmalus), leer wenn keiner<br>5. `target`: Name des getöteten Gegners (kill) bzw. der entdeckten Zone (explore)<br>6. `questID`: Quest, für die die Erfahrung kam (quest), wenn zuordenbar<br>7. `level`: Stufe des Charakters<br>8. `mapID`: Karte (uiMapID), auf der der Gewinn kam<br>9. `via`: Erfassungsweg: msg (Chat-Meldung), diff (nur Differenz) oder unclear (Mehrfach-Stufensprung, Betrag unbekannt, nicht gebucht) |
| `RS` | **Ruhezustand**: Ruhe-Erfahrung und Ruhezustand beim Einloggen, Neuladen und Ausloggen. | 1. `reason`: Anlass: login, reload oder logout<br>2. `rested`: angesammelte Ruhe-Erfahrung in Punkten (leer = keine)<br>3. `resting`: 1 = in einem Ruhegebiet (Gasthaus, Stadt), 0 = nicht<br>4. `xp`: Erfahrung auf der aktuellen Stufe<br>5. `xpMax`: Erfahrung, die für die nächste Stufe nötig ist<br>6. `level`: Stufe des Charakters |
| `QA` | **Quest angenommen**: Eine Quest wurde angenommen. | 1. `questID`: Quest-ID; Titel und Texte in quests[questID]<br>2. `level`: Stufe des Charakters<br>3. `qlevel`: Stufe der Quest (leer, wenn nicht lesbar)<br>4. `mapID`: Karte (uiMapID) bei der Annahme<br>5. `npcID`: Questgeber (npcID); Name in npcs[npcID]<br>6. `npc`: Name des Questgebers, nur wenn er keine npcID hat (Objekt, Gegenstand)<br>7. `x`: Spielerposition West-Ost (0-9999), leer wenn nicht lesbar<br>8. `y`: Position Nord-Süd (0-9999), leer wenn nicht lesbar |
| `QT` | **Quest abgegeben**: Eine Quest wurde abgegeben. | 1. `questID`: Quest-ID<br>2. `level`: Stufe des Charakters<br>3. `qlevel`: Stufe der Quest (leer, wenn nicht lesbar)<br>4. `mapID`: Karte (uiMapID) bei der Abgabe<br>5. `xp`: Erfahrung aus der Quest (laut Spiel, ohne Ruhebonus)<br>6. `money`: Geld aus der Quest in Kupfer<br>7. `itemID`: gewähltes Belohnungs-Item (itemID), leer wenn keine Wahl<br>8. `npcID`: Abgabe-NPC (npcID); Name in npcs[npcID]<br>9. `npc`: Name des Abgabe-NPCs, nur wenn er keine npcID hat<br>10. `x`: Spielerposition West-Ost (0-9999), leer wenn nicht lesbar<br>11. `y`: Position Nord-Süd (0-9999), leer wenn nicht lesbar |
| `QR` | **Belohnung nachgetragen**: Das gewählte Belohnungs-Item wurde erst nach der Abgabe-Zeile erkannt. | 1. `questID`: Quest-ID<br>2. `itemID`: gewähltes Belohnungs-Item (itemID) |
| `QX` | **Quest abgebrochen**: Eine Quest verschwand aus dem Questlog, ohne abgegeben worden zu sein. | 1. `questID`: Quest-ID<br>2. `level`: Stufe des Charakters<br>3. `qlevel`: Stufe der Quest (leer, wenn nicht lesbar)<br>4. `mapID`: Karte (uiMapID) beim Abbruch<br>5. `confirmed`: 1 = Abbrechen-Knopf wurde erkannt, 0 = nur aus dem Verschwinden der Quest geschlossen |
| `QO` | **Questziel-Fortschritt**: Ein Questziel ist vorangekommen (have gestiegen; Ereignisse gebündelt, je Ziel höchstens need bzw. 100 Zeilen, der Endstand have >= need aber immer einmal). Der Stand bei Login, Reload und Annahme wird nicht geschrieben. | 1. `questID`: Quest-ID<br>2. `idx`: Nummer des Ziels in der Quest (ab 1, Reihenfolge von C_QuestLog.GetQuestObjectives)<br>3. `have`: erreichter Stand nach dem Schritt (bei Fortschrittsbalken Prozent)<br>4. `need`: benötigter Stand (bei Fortschrittsbalken 100), leer wenn nicht lesbar<br>5. `kind`: Zielart laut Spiel: monster, item, object, event, reputation, log, progressbar, …; leer wenn nicht lesbar<br>6. `text`: Zielname ohne Zähler (gesäubert, höchstens 80 Bytes), leer wenn nicht lesbar<br>7. `mapID`: Karte (uiMapID) beim Schritt<br>8. `px`: Spielerposition West-Ost (0-9999), leer wenn nicht lesbar<br>9. `py`: Position Nord-Süd (0-9999), leer wenn nicht lesbar |
| `BK` | **Buch gelesen**: Eine Buch-, Brief- oder Schildseite wurde gelesen (in einer Lesesitzung je Seite einmal). | 1. `key`: Schlüssel des Buches in books (stabiler Hash aus Titel und erster Seite)<br>2. `page`: Seitennummer (ab 1)<br>3. `level`: Stufe des Charakters<br>4. `mapID`: Karte (uiMapID) am Leseort<br>5. `new`: 1 = Text dieser Seite wurde neu archiviert, 0 = war schon gespeichert (je Buch und Seite höchstens einmal je Login) |
| `KI` | **Kill**: Ein Gegner wurde von Euch, Eurem Begleiter oder der Gruppe getötet. Der Name steht in npcs[npcID]. Bis zu 1 s verzögert geschrieben, damit die Kill-Erfahrung dazukommt. | 1. `npcID`: Gegner (npcID aus der GUID); ? = in der Instanz nicht lesbar<br>2. `level`: Stufe des Gegners (-1 = Boss/??), leer wenn unbekannt<br>3. `cls`: Klassifikation: normal, elite, rare, rareelite, worldboss, trivial, minus; leer wenn unbekannt<br>4. `mapID`: Karte (uiMapID) beim Kill<br>5. `xp`: Erfahrung aus der Kill-Meldung, leer wenn keine kam<br>6. `by`: Todesstoß: self (Ihr), pet (Begleiter), group (Gruppenmitglied); ? = nicht lesbar<br>7. `via`: Erkennung: pk (PARTY_KILL), died (UNIT_DIED plus Erfahrungsmeldung) oder xp (nur Erfahrungsmeldung)<br>8. `name`: Name des Gegners, nur wenn es keine npcID gibt (leer = unbekannt)<br>9. `plevel`: Stufe des Charakters<br>10. `x`: Position des Charakters beim Kill, West-Ost (0-9999); leer, wenn die Karte sie nicht herausgibt (meist in Instanzen). Ältere Zeilen aus der Zeit vor Nachtrag N1 trugen x/y nur bei Rare/Elite/Boss; Leser behandeln fehlende Felder wie leere<br>11. `y`: Position des Charakters beim Kill, Nord-Süd (0-9999); leer wie x |
| `KF` | **Kampf**: Ein Kampf ist zu Ende (PLAYER_REGEN_ENABLED). Schaden und Heilung aus dem Schadensmesser, wenn lesbar. | 1. `duration`: Dauer in Sekunden<br>2. `kills`: getötete Gegner in diesem Kampf (KI-Zeilen)<br>3. `damage`: verursachter Schaden (Schadensmesser), leer wenn nicht lesbar<br>4. `healing`: Heilung (Schadensmesser), leer wenn nicht lesbar<br>5. `taken`: erlittener Schaden (Schadensmesser), leer wenn nicht lesbar<br>6. `hpEnd`: Leben am Kampfende in Prozent (Näherung: das Minimum im Kampf ist nicht lesbar); ? = gesperrt<br>7. `close`: 1 = knapper Sieg (Näherung: unter 10 % Leben am Kampfende, nicht tot)<br>8. `dead`: 1 = Ihr seid in diesem Kampf gestorben<br>9. `level`: Stufe des Charakters<br>10. `mapID`: Karte (uiMapID) am Kampfende |
| `DE` | **Tod**: Ihr seid gestorben. Danach folgen die DR-Zeilen (Todesbericht), eine DC-Zeile (Ursache) und später DB (Wiederbelebung). | 1. `level`: Stufe des Charakters<br>2. `mapID`: Karte (uiMapID) am Todesort<br>3. `x`: Position West-Ost (0-9999)<br>4. `y`: Position Nord-Süd (0-9999)<br>5. `instance`: 1 = in einer Instanz<br>6. `combat`: 1 = im Kampf gestorben<br>7. `sub`: Name der Unterzone (GetSubZoneText, gesäubert, höchstens 60 Bytes), leer wenn ohne Namen oder nicht lesbar |
| `DR` | **Todesbericht-Treffer**: Ein Eintrag des Todesberichts (C_DeathRecap), in der Reihenfolge des Clients. | 1. `ago`: Zehntelsekunden vor dem letzten Treffer (0 = Todesstoß)<br>2. `event`: Ereignisart, z. B. SWING_DAMAGE, SPELL_DAMAGE, ENVIRONMENTAL_DAMAGE; ? = gesperrt (ganz gesperrter Eintrag: nur event = ?)<br>3. `npcID`: Verursacher (npcID), Name in npcs[npcID]<br>4. `source`: Name des Verursachers, nur ohne npcID (z. B. Spieler)<br>5. `spellID`: Zauber (spellID), leer bei Nahkampf<br>6. `amount`: Schaden<br>7. `overkill`: Überschaden<br>8. `school`: Schadensschule (Bitmaske)<br>9. `crit`: 1 = kritischer Treffer<br>10. `hp`: Euer Leben laut Todesbericht, vermutlich vor dem Treffer (Wert des Clients)<br>11. `env`: Umgebungsschaden-Art (z. B. Falling, Drowning), wenn genannt; ? = gesperrt |
| `DC` | **Todesursache**: Zusammenfassung des Todes. Ohne lesbaren Bericht wird die Ursache vermutet (guess = 1). | 1. `npcID`: Verursacher des Todesstoßes (npcID)<br>2. `source`: Name des Verursachers, nur ohne npcID<br>3. `spellID`: Zauber des Todesstoßes<br>4. `cause`: Ursache: enemy, fall, drown, fatigue, lava, fire, slime, environment oder leer (unbekannt)<br>5. `guess`: 1 = Ursache vermutet (Atemleiste bzw. Tod ohne Kampf und ohne Bericht)<br>6. `events`: Zahl der Einträge im Todesbericht; ? = gesperrt<br>7. `maxHP`: maximales Leben laut Todesbericht |
| `DB` | **Wiederbelebung**: Ihr lebt wieder. | 1. `how`: Weg: corpse (Leichenlauf), spirit (Geistheiler), res (Wiederbelebung durch andere oder Seelenstein), unknown<br>2. `guess`: 1 = Weg vermutet<br>3. `seconds`: Sekunden seit dem Tod<br>4. `mapID`: Karte (uiMapID) bei der Wiederbelebung<br>5. `x`: Position West-Ost (0-9999)<br>6. `y`: Position Nord-Süd (0-9999) |
| `ZN` | **Neue Karte**: Erste Ankunft auf einer Karte (Zone, Höhle, Stadt, Instanzkarte). | 1. `mapID`: Karte (uiMapID)<br>2. `mapType`: Kartentyp: 2 Kontinent, 3 Zone, 4 Dungeon, 5 Mikrokarte, 6 sonstige<br>3. `zone`: zugehörige Hauptzone (uiMapID), leer wenn keine<br>4. `continent`: zugehöriger Kontinent (uiMapID), leer wenn keiner<br>5. `level`: Stufe des Charakters<br>6. `x`: Position West-Ost (0-9999)<br>7. `y`: Position Nord-Süd (0-9999) |
| `SZ` | **Neue Unterzone**: Erste Ankunft in einer Unterzone (Name laut Client). | 1. `mapID`: Karte (uiMapID)<br>2. `name`: Name der Unterzone<br>3. `level`: Stufe des Charakters |
| `EX` | **Entdeckt**: Systemmeldung über ein entdecktes Gebiet (mit oder ohne Erfahrung). | 1. `name`: Name des Gebiets laut Meldung<br>2. `xp`: Erfahrung laut Meldung, leer wenn keine<br>3. `mapID`: Karte (uiMapID)<br>4. `level`: Stufe des Charakters |
| `FP` | **Neuer Flugpunkt**: Meldung 'Neue Flugroute entdeckt'. Der Flugmeister ist der Gesprächspartner. | 1. `npcID`: Flugmeister (npcID), Name in npcs[npcID]<br>2. `mapID`: Karte (uiMapID)<br>3. `x`: Position West-Ost (0-9999)<br>4. `y`: Position Nord-Süd (0-9999)<br>5. `level`: Stufe des Charakters<br>6. `name`: Name des Flugmeisters, nur ohne npcID |
| `TP` | **Spur pausiert**: Die Positionsspur pausiert (eine Zeile je Pause). | 1. `reason`: instance (Instanz ohne Position), taxi (im Flug) oder unreadable (Position gesperrt)<br>2. `mapID`: Karte (uiMapID), wenn bekannt |
| `TF` | **Flug gestartet**: Ein Flug hat begonnen (nach TakeTaxiNode, sobald Ihr in der Luft seid). | 1. `from`: Name des Start-Flugpunkts<br>2. `to`: Name des Ziel-Flugpunkts<br>3. `cost`: Kosten in Kupfer<br>4. `fromNode`: Start-Knoten (nodeID), leer wenn nicht lesbar<br>5. `toNode`: Ziel-Knoten (nodeID), leer wenn nicht lesbar<br>6. `mapID`: Karte (uiMapID) beim Abflug |
| `TL` | **Flug gelandet**: Der Flug ist zu Ende. | 1. `seconds`: Flugdauer in Sekunden<br>2. `mapID`: Karte (uiMapID) bei der Landung<br>3. `x`: Position West-Ost (0-9999)<br>4. `y`: Position Nord-Süd (0-9999) |
| `HS` | **Ruhestein**: Ruhestein, Astraler Rückruf oder Ruhestein-Spielzeug benutzt. | 1. `spellID`: Zauber (echte ID: 8690 Ruhestein, 556 Astraler Rückruf, sonst das Spielzeug)<br>2. `bind`: Ziel: gebundener Ort laut Client, leer bei Spielzeugen mit eigenem Ziel (Garnison, Dalaran)<br>3. `mapID`: Karte (uiMapID) beim Wirken<br>4. `x`: Position West-Ost (0-9999), leer wenn nicht lesbar<br>5. `y`: Position Nord-Süd (0-9999), leer wenn nicht lesbar |
| `HB` | **Neues Zuhause**: Der Ruhestein wurde neu gebunden. | 1. `bind`: Name des neuen Zuhauses<br>2. `mapID`: Karte (uiMapID) |
| `TB` | **Überfahrt (vermutet)**: Kontinentwechsel ohne Flug, Ruhestein, Tod oder Instanz, vermutlich Schiff oder Zeppelin. | 1. `fromMap`: letzte Karte vorher (uiMapID)<br>2. `toMap`: Karte danach (uiMapID)<br>3. `fromContinent`: Kontinent vorher (uiMapID)<br>4. `toContinent`: Kontinent danach (uiMapID) |
| `IE` | **Instanz betreten**: Ihr seid in einer Instanz (auch nach Login oder Reload darin, dann resumed = 1). | 1. `instanceID`: Instanz (instanceID laut GetInstanceInfo)<br>2. `type`: party, raid, pvp, arena oder scenario<br>3. `difficultyID`: Schwierigkeitsgrad (difficultyID)<br>4. `group`: Zahl der Gruppenmitglieder<br>5. `level`: Stufe des Charakters<br>6. `pos`: 1 = Position lesbar, 0 = in der Instanz nicht lesbar<br>7. `mapLock`: Addon-Sperre Karte (C_RestrictedActions: 0 aus, 1 startet, 2 aktiv); leer wenn unbekannt<br>8. `chatLock`: Addon-Sperre Chat (wie mapLock)<br>9. `resumed`: 1 = der Besuch lief schon vor dem Reload bzw. Login |
| `IL` | **Instanz verlassen**: Ihr habt die Instanz verlassen. | 1. `instanceID`: Instanz<br>2. `seconds`: Dauer des Besuchs in Sekunden<br>3. `kills`: Kills im Besuch<br>4. `deaths`: eigene Tode im Besuch<br>5. `bosses`: besiegte Bosse im Besuch<br>6. `loot`: Funde ab Qualität Grün im Besuch (Stückzahl, aus LT) |
| `IB` | **Boss-Kampf**: Ende einer Boss-Begegnung (ENCOUNTER_END), falls der Client sie meldet. | 1. `encounterID`: Begegnung (encounterID)<br>2. `success`: 1 = besiegt, 0 = gescheitert<br>3. `seconds`: Dauer in Sekunden (seit ENCOUNTER_START), leer wenn unbekannt<br>4. `group`: Gruppengröße laut Event<br>5. `difficultyID`: Schwierigkeitsgrad<br>6. `instanceID`: Instanz |
| `MO` | **Moment**: Ein Chronik-Moment (Meilenstein). Erste Male stehen zusätzlich in snapshots.moments[kind]. | 1. `kind`: level, kill (Rare/Elite/Boss; Elite nicht in Instanzen, F16), first_rare, first_elite, first_boss, close_win, first_death, continent, first_dungeon, first_raid, boss, first_blue (erster blauer Gegenstand), first_epic (erster lila oder besserer), first_bag (erste Tasche), first_fish (erster Fang beim Angeln), mount (Reittier gelernt), reputation (Rufstufe), profession (Beruf neu oder Stufe 75/150/225/300)<br>2. `value`: Wert: Stufe (level), npcID (kill, first_*), HP-Prozent (close_win), mapID (continent), instanceID (first_dungeon, first_raid), encounterID (boss), itemID (first_blue, first_epic, first_bag, first_fish), Zauber- bzw. Reittier-ID oder Name (mount), factionID oder Name (reputation), Name der Fertigkeit (profession)<br>3. `detail`: level: 1 = hervorgehobene Stufe (10, 20, ... 60); kill und first_*: Klassifikation; close_win: 1 = Näherung; first_blue, first_epic: Qualität; mount: Name; reputation: neue Rufstufe (1-8); profession: Wert der Fertigkeit<br>4. `level`: Stufe des Charakters<br>5. `mapID`: Karte (uiMapID)<br>6. `sub`: Name der Unterzone (GetSubZoneText, gesäubert, höchstens 60 Bytes), leer wenn ohne Namen oder nicht lesbar |
| `SH` | **Screenshot**: Ein Screenshot wurde gespeichert (SCREENSHOT_SUCCEEDED). Datei WoWScrnShot_<key>.jpg (Ortszeit), Eintrag in shots[key]. | 1. `key`: MMDDYY_HHMMSS (Ortszeit), Schlüssel in shots<br>2. `reasons`: Anlässe, durch Komma getrennt: levelup, zone, kill, boss, close_win, death, item (erstes Blau/Lila, Reittier); manual = selbst ausgelöst<br>3. `auto`: 1 = vom Addon ausgelöst, 0 = selbst ausgelöst<br>4. `level`: Stufe des Charakters<br>5. `mapID`: Karte (uiMapID)<br>6. `x`: Position West-Ost (0-9999), leer wenn nicht lesbar<br>7. `y`: Position Nord-Süd (0-9999), leer wenn nicht lesbar<br>8. `sub`: Name der Unterzone (GetSubZoneText, gesäubert, höchstens 60 Bytes), leer wenn ohne Namen oder nicht lesbar |
| `GD` | **Gold-Änderung**: Das Geld des Charakters hat sich geändert (PLAYER_MONEY). Quelle bzw. Zweck aus offenen Fenstern und Kontext. Summen je Quelle stehen in counters.money_in und counters.money_out. | 1. `delta`: Änderung in Kupfer (negativ = Ausgabe); leer bei source = start<br>2. `balance`: Geld nach der Änderung in Kupfer<br>3. `source`: Quelle (Einnahme) bzw. Zweck (Ausgabe): loot, quest, vendor_sell, vendor_buy, repair (Alle reparieren per Hook; Einzelreparatur nur als Näherung: Händler offen und Reparatur-Cursor aktiv), training, taxi, ah, ah_sale, mail, trade, guildbank, other; start (erster Stand), gap (Änderung zwischen letzter Sicherung und Login, z. B. nach einem Absturz)<br>4. `level`: Stufe des Charakters<br>5. `mapID`: Karte (uiMapID) |
| `AH` | **Auktionshaus**: Ein Vorgang im Auktionshaus. post/bid/buy/cancel kommen aus den Aktionen im Fenster, sold/bought aus den Rechnungen der Post (nur wenn die API sie liefert). | 1. `action`: post (eingestellt), bid (Gebot; auch ein Sofortkauf läuft über PlaceBid und steht hier als bid, die Rechnung liefert später bought), buy (Kauf), cancel (abgebrochen), sold (verkauft laut Rechnung), bought (gekauft laut Rechnung)<br>2. `itemID`: Gegenstand (itemID), leer wenn nicht lesbar<br>3. `name`: Gegenstandsname, nur wenn keine itemID bekannt ist (Rechnungen)<br>4. `count`: Menge<br>5. `price`: Preis in Kupfer: post Sofortkauf bzw. Stückpreis, bid Gebot, buy Stückpreis (Rohstoffe) bzw. Gesamtpreis, sold/bought Verkaufs- bzw. Kaufpreis<br>6. `deposit`: Pfand in Kupfer (post) bzw. Gebühr/Provision (sold)<br>7. `hours`: Laufzeit in Stunden (post)<br>8. `partner`: Käufer bzw. Verkäufer laut Rechnung<br>9. `level`: Stufe des Charakters<br>10. `mapID`: Karte (uiMapID) |
| `LT` | **Fund**: Ein Gegenstand ab Qualität Grün (oder mit unbekannter Qualität) wurde erhalten. Name und Qualität stehen in snapshots.items. Gegenstände darunter zählen nur in counters.loot (bzw. bought, crafted, received, quest_items). | 1. `item`: Item-Schlüssel: itemID, dann optional .s<Zufallszusatz> und .b<Bonus-ID> (z. B. 2589 oder 1369.s-37.b1486); keine kompletten Links<br>2. `count`: Menge<br>3. `quality`: Qualität: 0 grau, 1 weiß, 2 grün, 3 blau, 4 lila, 5 orange; leer wenn unbekannt<br>4. `source`: Quelle: mob, object, container, fishing (aus dem Beutefenster); vendor, quest, craft, mail, trade, ah, bonus, other (ohne Beutefenster)<br>5. `srcID`: bei mob die npcID (leer, wenn die Quelle nicht lesbar war und die Zuordnung nur aus einem Kill stammt), bei object die Objekt-ID. mob ohne srcID ist eine Näherung: Bei unlesbarer Quelle gilt ein frischer Kill als Quelle<br>6. `level`: Stufe des Charakters<br>7. `mapID`: Karte (uiMapID)<br>8. `x`: Position West-Ost (0-9999), leer wenn nicht lesbar<br>9. `y`: Position Nord-Süd (0-9999), leer wenn nicht lesbar |
| `GW` | **Ausrüstungswechsel**: Ein Ausrüstungs- oder Taschenplatz hat sich geändert. Slots 1-19 sind die Ausrüstung (INVSLOT: 1 Kopf, 2 Hals, 3 Schulter, 4 Hemd, 5 Brust, 6 Gürtel, 7 Beine, 8 Füße, 9 Handgelenke, 10 Hände, 11-12 Ringe, 13-14 Schmuckstücke, 15 Rücken, 16 Haupthand, 17 Nebenhand, 18 Fernkampf, 19 Wappenrock), höhere Slots sind Taschenplätze. | 1. `slot`: Platz (INVSLOT)<br>2. `item`: neuer Gegenstand (Item-Schlüssel), leer = Platz ist jetzt leer<br>3. `ilvl`: Gegenstandsstufe, leer wenn nicht lesbar<br>4. `prev`: vorheriger Gegenstand (Item-Schlüssel), leer = Platz war leer<br>5. `level`: Stufe des Charakters<br>6. `mapID`: Karte (uiMapID) |
| `SP` | **Zauber gelernt**: Ein Zauber, eine Fähigkeit oder ein Rang wurde gelernt. Name und Rang stehen in snapshots.spells[spellID]. | 1. `spellID`: Zauber (spellID); leer, wenn der Client nur die Meldung lieferte<br>2. `kind`: spell, ability, passive, recipe, mount, companion; leer wenn unbekannt<br>3. `level`: Stufe des Charakters<br>4. `mapID`: Karte (uiMapID)<br>5. `name`: Name, nur wenn keine spellID bekannt ist |
| `TA` | **Talent**: Ein Talentpunkt wurde vergeben (oder zurückgenommen). Knoten-Daten (Position, Zauber) stehen in snapshots.talentNodes, der Stand je Punktesumme in snapshots.talents[spent] = { [nodeID] = Rang }. | 1. `nodeID`: Talentknoten (C_Traits nodeID)<br>2. `rank`: neuer Rang des Knotens (0 = zurückgenommen)<br>3. `spent`: ausgegebene Talentpunkte insgesamt<br>4. `unspent`: freie Talentpunkte, leer wenn nicht lesbar<br>5. `level`: Stufe des Charakters |
| `SK` | **Fertigkeit**: Beruf oder Fertigkeit neu gelernt oder gestiegen. | 1. `name`: Name der Fertigkeit laut Client<br>2. `rank`: neuer Wert<br>3. `max`: Höchstwert, leer wenn unbekannt<br>4. `skillLine`: Fertigkeitslinie (skillLineID), leer wenn unbekannt<br>5. `level`: Stufe des Charakters<br>6. `why`: up (gestiegen), new (neu gelernt) |
| `RP` | **Ruf**: Der Ruf bei einer Fraktion hat sich geändert (Meldung des Clients). | 1. `faction`: Name der Fraktion laut Client<br>2. `factionID`: Fraktion (factionID), leer wenn nicht auffindbar; Name in snapshots.factions<br>3. `delta`: Änderung (negativ = verschlechtert), leer wenn die Meldung keine Zahl nennt<br>4. `standing`: Stufe nach der Änderung: 1 Hasserfüllt, 2 Feindselig, 3 Unfreundlich, 4 Neutral, 5 Freundlich, 6 Wohlwollend, 7 Respektvoll, 8 Ehrfürchtig; leer wenn nicht lesbar<br>5. `level`: Stufe des Charakters<br>6. `mapID`: Karte (uiMapID) |
| `RT` | **Rufstufe**: Eine Rufstufe wurde erreicht (oder verloren). | 1. `faction`: Name der Fraktion<br>2. `factionID`: Fraktion (factionID), leer wenn nicht auffindbar<br>3. `standing`: neue Stufe (1-8 wie bei RP), leer wenn nur der Text bekannt ist<br>4. `prev`: vorherige Stufe, leer wenn unbekannt<br>5. `standingName`: Stufe als Text laut Meldung, leer wenn keine Meldung kam<br>6. `level`: Stufe des Charakters |
| `GS` | **Gruppe gebildet**: Ihr seid einer Gruppe beigetreten oder habt eine gebildet. | 1. `size`: Zahl der Mitglieder inklusive Euch<br>2. `kind`: party oder raid<br>3. `leader`: 1 = Ihr seid Anführer<br>4. `level`: Stufe des Charakters<br>5. `mapID`: Karte (uiMapID) |
| `GM` | **Mitspieler**: Ein Mitspieler ist der Gruppe beigetreten (oder war beim Beitritt schon da). | 1. `name`: Name des Mitspielers<br>2. `class`: Klasse (englischer Dateiname, z. B. PALADIN)<br>3. `level`: Stufe des Mitspielers, leer wenn nicht lesbar<br>4. `size`: Gruppengröße danach |
| `GL` | **Mitspieler geht**: Ein Mitspieler hat die Gruppe verlassen. | 1. `name`: Name des Mitspielers<br>2. `class`: Klasse (englischer Dateiname)<br>3. `level`: Stufe des Mitspielers beim Beitritt<br>4. `seconds`: Sekunden gemeinsam in der Gruppe |
| `GE` | **Gruppe beendet**: Die Gruppe ist aufgelöst oder Ihr habt sie verlassen. Die Zähler gelten für die ganze Zeit in der Gruppe (Näherung für gemeinsame Kills, Quests und Instanzen). | 1. `seconds`: Dauer der Gruppe in Sekunden, leer wenn unbekannt<br>2. `maxSize`: größte Gruppengröße<br>3. `kills`: Kills (KI) in der Gruppe<br>4. `quests`: abgegebene Quests in der Gruppe<br>5. `instances`: betretene Instanzen in der Gruppe<br>6. `level`: Stufe des Charakters<br>7. `mapID`: Karte (uiMapID) |
| `GI` | **Gruppe in Instanz**: Die Gruppe beim Betreten einer Instanz (ergänzt IE). | 1. `instanceID`: Instanz (instanceID)<br>2. `size`: Zahl der Mitglieder inklusive Euch<br>3. `members`: Mitspieler, durch Komma getrennt, je Name:KLASSE:Stufe (bei großen Gruppen gekürzt) |
| `GU` | **Gilde**: Gildenzugehörigkeit oder Rang hat sich geändert. | 1. `action`: join (beigetreten), leave (verlassen), change (andere Gilde), rank (anderer Rang), seen (beim ersten Sammeln schon Mitglied)<br>2. `guild`: Gildenname<br>3. `rank`: Rangname<br>4. `rankIndex`: Rangnummer (0 = Gildenmeister)<br>5. `level`: Stufe des Charakters |
| `DU` | **Duell**: Ein Duell ist zu Ende. Der Ausgang steht nur in der Systemmeldung; ohne Meldung bleibt er unbekannt. | 1. `opponent`: Gegner<br>2. `result`: win (gewonnen), loss (verloren), fled (Ihr seid geflüchtet), opp_fled (der Gegner ist geflüchtet), unknown<br>3. `level`: Stufe des Charakters<br>4. `mapID`: Karte (uiMapID) |
| `PK` | **PvP-Kill**: Ein Spieler wurde von Euch, Eurem Begleiter oder der Gruppe getötet (PARTY_KILL mit Spieler-Ziel). Gesperrte Namen stehen als ?. | 1. `name`: Name des Spielers; ? = gesperrt<br>2. `class`: Klasse (englischer Dateiname), leer wenn unbekannt<br>3. `level`: Stufe des Spielers, leer wenn unbekannt<br>4. `by`: Todesstoß: self, pet, group; ? = nicht lesbar<br>5. `plevel`: Stufe des Charakters<br>6. `mapID`: Karte (uiMapID)<br>7. `x`: Position West-Ost (0-9999), leer wenn nicht lesbar<br>8. `y`: Position Nord-Süd (0-9999), leer wenn nicht lesbar |
| `PD` | **PvP-Tod**: Ihr wurdet von einem Spieler getötet (Todesstoß laut Todesbericht). Nur bei lesbarem Bericht. | 1. `name`: Name des Spielers<br>2. `class`: Klasse (englischer Dateiname), leer wenn unbekannt<br>3. `level`: Stufe des Charakters<br>4. `mapID`: Karte (uiMapID)<br>5. `x`: Position West-Ost (0-9999), leer wenn nicht lesbar<br>6. `y`: Position Nord-Süd (0-9999), leer wenn nicht lesbar |
| `TH` | **Handel**: Ein Handel mit einem Spieler wurde abgeschlossen. Abgebrochene Handel zählen nur in counters.trade. Items als Liste Item-Schlüssel[*Menge], durch Komma getrennt. | 1. `partner`: Handelspartner<br>2. `giveGold`: Eure Gold-Gabe in Kupfer<br>3. `getGold`: Erhaltenes Gold in Kupfer<br>4. `give`: Eure Gegenstände<br>5. `get`: Erhaltene Gegenstände<br>6. `level`: Stufe des Charakters<br>7. `mapID`: Karte (uiMapID) |
| `PM` | **Post erhalten**: Geld oder Gegenstände wurden aus einem Brief genommen. Items wie bei TH. | 1. `sender`: Absender laut Client<br>2. `money`: genommenes Geld in Kupfer<br>3. `items`: genommene Gegenstände<br>4. `cod`: Nachnahme in Kupfer, leer wenn keine<br>5. `ah`: 1 = Brief vom Auktionshaus (Rechnung vorhanden)<br>6. `level`: Stufe des Charakters |
| `PS` | **Post gesendet**: Ein Brief wurde verschickt (bestätigt durch den Client). Items wie bei TH. | 1. `recipient`: Empfänger<br>2. `money`: mitgeschicktes Geld in Kupfer<br>3. `items`: mitgeschickte Gegenstände<br>4. `cod`: Nachnahme in Kupfer, leer wenn keine<br>5. `level`: Stufe des Charakters |
| `WB` | **Weggefährte tritt bei**: Ein Gruppen- oder Schlachtzugsmitglied (außer Euch) ist hinzugekommen. Position und Karte sind die des Charakters beim Beitritt (die Position des Mitspielers ist nicht lesbar). Gelesen wird nur außerhalb des Kampfes, höchstens alle 2 s gebündelt. | 1. `name`: Name-Realm des Mitspielers (gleicher Realm: der eigene Realmname)<br>2. `class`: Klasse (englischer Dateiname, z. B. PALADIN), leer wenn nicht lesbar<br>3. `race`: Volk (englischer Dateiname, z. B. NightElf), leer wenn nicht lesbar<br>4. `level`: Stufe des Mitspielers, leer wenn nicht lesbar<br>5. `mapID`: Karte (uiMapID) des Charakters beim Beitritt<br>6. `x`: Position des Charakters West-Ost (0-9999), leer wenn nicht lesbar<br>7. `y`: Position des Charakters Nord-Süd (0-9999), leer wenn nicht lesbar |
| `WV` | **Weggefährte geht**: Ein Gruppenmitglied hat die Gruppe verlassen, die Gruppe ist zu Ende oder Ihr habt Euch ausgeloggt (Felder wie WB). | 1. `name`: Name-Realm des Mitspielers<br>2. `class`: Klasse (englischer Dateiname), leer wenn nicht lesbar<br>3. `race`: Volk (englischer Dateiname), leer wenn nicht lesbar<br>4. `level`: Stufe des Mitspielers beim Gehen, leer wenn nicht lesbar<br>5. `mapID`: Karte (uiMapID) des Charakters beim Gehen<br>6. `x`: Position des Charakters West-Ost (0-9999), leer wenn nicht lesbar<br>7. `y`: Position des Charakters Nord-Süd (0-9999), leer wenn nicht lesbar<br>8. `why`: left (Mitspieler gegangen), end (Gruppe zu Ende), logout (Ihr habt Euch ausgeloggt) |
| `RA` | **Rast**: Der Charakter beginnt zu rasten: Ruhegebiet (Gasthaus, Stadt) oder Lagerfeuer bzw. Zelt (Rast-Aura). Höchstens eine Zeile je 5 Minuten. Das Ende steht nicht im Log. | 1. `kind`: inn (Ruhegebiet laut IsResting) oder fire (Lagerfeuer-/Zelt-Aura)<br>2. `mapID`: Karte (uiMapID)<br>3. `x`: Position West-Ost (0-9999), leer wenn nicht lesbar<br>4. `y`: Position Nord-Süd (0-9999), leer wenn nicht lesbar<br>5. `level`: Stufe des Charakters<br>6. `rested`: Ruhe-Erfahrung in Punkten, leer wenn keine oder nicht lesbar<br>7. `src`: Quelle: Spell-ID der Rast-Aura (Lagerfeuer, Zelt), name (Treffer per Namensmuster ohne lesbare ID) oder inn (Ruhegebiet) |
| `LF` | **Lagerfeuer-Runde**: Der Charakter hat mindestens 60 s am Lagerfeuer gesessen (Sitz-Aura) und ist aufgestanden. Personen: nur wer am Feuer war (Sitz-/Rast-Aura gelesen oder mindestens 20 s in Reichweite, Vorbeilaufende zählen nicht). Namen anderer Spieler sind Fremdtext (gesäubert). | 1. `mapID`: Karte (uiMapID) beim Hinsetzen<br>2. `x`: Position West-Ost (0-9999), leer wenn nicht lesbar<br>3. `y`: Position Nord-Süd (0-9999), leer wenn nicht lesbar<br>4. `level`: Stufe des Charakters beim Hinsetzen<br>5. `seconds`: Sitzdauer in Sekunden<br>6. `count`: Zahl der Personen am Feuer (alle, auch die nicht ins Feld passten)<br>7. `people`: Personen, je Person guid,name-realm,class,race,level,sex,how (guid ohne Präfix Player-, sex 2/3, how a = Aura gelesen, d = verweilt), mit ; getrennt; höchstens 10 und 250 Bytes, wer nicht passt fällt ganz weg<br>8. `said`: Zahl der per Zettel gesagten Sätze<br>9. `sim`: 1 = Probe-Runde aus der Retail-Simulation (/chronik sim feuer), sonst leer; /chronik sim feuer löschen entfernt nur diese |
| `VE` | **Vorhaben erfüllt**: Ein eigenes To Do (Vorhaben) wurde erledigt: automatisch (Zone betreten, Ort erreicht, Gegner getötet, Gegenstände gefunden) oder von Hand abgehakt (how = hand). Die Liste selbst steht in chars[guid].vorhaben. | 1. `id`: Nummer des Vorhabens in der Vorhaben-Liste<br>2. `mapID`: Zielkarte des Vorhabens (uiMapID)<br>3. `level`: Stufe des Charakters<br>4. `x`: Position West-Ost (0-9999), leer wenn nicht lesbar<br>5. `y`: Position Nord-Süd (0-9999), leer wenn nicht lesbar<br>6. `text`: Text des Vorhabens (gesäubert, höchstens 120 Zeichen; bei Gegnern/Gegenständen mit Anzahl, z. B. 10× Hasenpfote)<br>7. `how`: Wie erledigt: leer = Zielzone betreten, place = Ort erreicht, kill = Gegner getötet, item = Gegenstände gefunden, hand = von Hand abgehakt |
<!-- types:end -->
