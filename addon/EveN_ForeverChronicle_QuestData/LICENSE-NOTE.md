# Lizenz-Notiz: EveN_ForeverChronicle_QuestData / License note

**Lizenz / License: GNU General Public License v3 (GPL-3.0)** - voller Text in der Datei `LICENSE` in diesem Ordner /
full text in the file `LICENSE` in this folder. Dieser Ordner ist ein eigenes Werk neben dem Hauptaddon
`EveN_ForeverChronicle` (MIT, Grafiken ausgenommen); er wird nur bei Bedarf nachgeladen (LoadOnDemand).

Dieses Datenaddon enthält Questdaten (Questnamen, Stufen, Voraussetzungen, Questgeber und deren Standorte), die mit
`scripts/build-quest-data.mjs` aus **QuestieDB** abgeleitet (umformatiert und ergänzt) wurden. Den genauen Stand nennen die TOC
(`## X-QuestieDB-Version`) und der Kopf von `Quests.lua` / `Givers.lua`. Die Dateien sind erzeugt; die Quelle zum Erzeugen
(Skript und Quelldaten-Verweis) liegt im Quelltext-Repository des Addons.

- **Quelle / Source:** QuestieDB - Questie-Team und Beitragende (u. a. Muehe, TheCrux/BreakBB, Drejjmit, Dyaxler, Cheeq,
  TechnoHunter, Yttrium und alle weiteren), https://github.com/Questie/QuestieDB
- **Lizenzlage der Quelle:** QuestieDB hat keine eigene formale Lizenz. Laut https://github.com/Questie/QuestieDB/blob/master/LICENSE.md
  fallen importierte Questie-Inhalte unter die GPL-3.0; die Betreiber sind mit Kopien und Forks **unter den Bedingungen der GPLv3**
  einverstanden, können das aber nicht für alle früheren Beitragenden zusagen (nicht abgedeckter Inhalt gilt dort als
  „all rights reserved"). Name und Logo „Questie" sind ausgenommen und werden hier nicht verwendet.
- **Änderungen:** Auswahl, Umformatierung in Tabellen-/Textform, Ergänzung deutscher Namen und Kartenpunkte, Korrekturen
  (siehe Kopf der Dateien).
- **Ergänzend:** Gebiet → Karte und deutsche Namen aus der Forever-Datenbank (data.morthen.net); englische Namen
  (`Names.lua`) aus QuestieDB; Karten-Overlays (`Overlays.lua`, nur Zahlen: Kartenmaße und Texturnummern) aus den
  Client-Tabellen des Forever-Builds über wago.tools. Spielwelt-Inhalte (Namen, Orte, Kartentexturen) © Blizzard Entertainment.

Die Daten dürfen unter den Bedingungen der GPL-3.0 weitergegeben und verändert werden (Quellenangabe, Lizenztext,
Hinweis auf Änderungen beibehalten). Es gibt keine Gewähr.
