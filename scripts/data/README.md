# Schnappschuss der wago.tools-Tabellen

Eingaben fuer die Karten-Overlays (`Overlays.lua` im Datenaddon `EveN_ForeverChronicle_QuestData`), damit
`node scripts/build-quest-data.mjs` diesen Teil ohne Netz und ohne weitere Quelle reproduzieren kann
(Standard-Pfade des Generators; ueberschreibbar mit `--overlays`/`--overlays-retail` bzw. `CHRONICLE_OVERLAYS`/`CHRONICLE_OVERLAYS_RETAIL`).

| Ordner | Build | Tabellen |
|---|---|---|
| `wago-1.60.1.70170` | WoW Forever (Beta-Build 1.60.1.70170) | `UiMapXMapArt.csv`, `WorldMapOverlay.csv`, `WorldMapOverlayTile.csv` |
| `wago-retail-12.1.5.70575` | Retail 12.1.5.70575 | dieselben drei Tabellen |

Quelle: <https://wago.tools/db2/<Tabelle>/csv?build=<Build>> (oeffentliche Auszuege der Client-Tabellen des Spiels; die
enthaltenen Zahlen stehen ohnehin im erzeugten `Overlays.lua`). Spielwelt-Inhalte (c) Blizzard Entertainment.
Gesamtgroesse rund 0,8 MB. Neue Builds: die drei Tabellen je Build von dort laden und den Ordnernamen anpassen
(der Name steht im Kopf von `Overlays.lua`).

Nicht enthalten (zu gross bzw. fremde Daten): der Forever-Datenbank-Dump (Gebiete, deutsche Namen, Questtypen) und die
QuestieDB. Beschaffung: README, Abschnitt "Questdaten neu erzeugen".
