# Lizenz-Notiz: InkAndEmbers_Data / License note

**Lizenz / License: GNU General Public License v3 (GPL-3.0)** - voller Text in der Datei `LICENSE` in diesem Ordner /
full text in the file `LICENSE` in this folder. Dieser Ordner ist ein eigenes Werk neben dem Hauptaddon
`InkAndEmbers` (MIT, Grafiken ausgenommen); er wird nur bei Bedarf nachgeladen (LoadOnDemand).

Dieses Datenaddon enthält die Gegner-, Gegenstands- und Gebietslisten für die To-Do-Ziele (`Npcs.lua`, `Items.lua`,
`Zones.lua` sowie die englischen Namenslisten `NpcsEn.lua`, `ItemsEn.lua`, `ZonesEn.lua`), mit `scripts/build-todo-data.mjs` aus **QuestieDB** und der Forever-Datenbank abgeleitet (umformatiert und
ergänzt). Den genauen Stand nennt der Kopf der Dateien.

- **Quelle / Source:** QuestieDB - Questie-Team und Beitragende (u. a. Muehe, TheCrux/BreakBB, Drejjmit, Dyaxler, Cheeq,
  TechnoHunter, Yttrium und alle weiteren), https://github.com/Questie/QuestieDB (Stand 1.0.12, stabiles Release)
- **Lizenzlage der Quelle:** QuestieDB hat keine eigene formale Lizenz. Laut https://github.com/Questie/QuestieDB/blob/master/LICENSE.md
  fallen importierte Questie-Inhalte unter die GPL-3.0; die Betreiber sind mit Kopien und Forks **unter den Bedingungen der GPLv3**
  einverstanden, können das aber nicht für alle früheren Beitragenden zusagen (nicht abgedeckter Inhalt gilt dort als
  „all rights reserved"). Name und Logo „Questie" sind ausgenommen und werden hier nicht verwendet.
- **Änderungen:** Auswahl, Umformatierung in Textform, Ergänzung deutscher Namen und Gebietszuordnung aus der
  Forever-Datenbank (data.morthen.net).
- Spielwelt-Inhalte (Namen von Gegnern, Gegenständen, Gebieten) © Blizzard Entertainment.

Die Daten dürfen unter den Bedingungen der GPL-3.0 weitergegeben und verändert werden (Quellenangabe, Lizenztext,
Hinweis auf Änderungen beibehalten). Es gibt keine Gewähr.

**Zusatz / Addition - `Recipes.lua`:** Die Berufsrezepte (Pläne > Handwerk) stammen aus **"What's Training?"** (Sveng/fusionpit,
https://github.com/fusionpit/WhatsTraining, `Crafting/Recipes/Camelot`, Lizenz **MIT**, Copyright (c) 2019; Lizenztext unverändert in
`LICENSE-WhatsTraining.txt`), umgeformt in ein kompaktes Textformat mit `scripts/build-recipe-data.mjs` (nichts hinzugefügt, Rezepte ohne
Quelle ausgelassen). MIT-lizenzierter Inhalt darf in diesem GPL-3.0-Ordner mitgeliefert werden; der MIT-Hinweis bleibt dabei erhalten. /
The profession recipes in `Recipes.lua` come from "What's Training?" (MIT, see `LICENSE-WhatsTraining.txt`), converted by
`scripts/build-recipe-data.mjs`; the MIT notice is kept.
