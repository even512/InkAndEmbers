// InkAndEmbers: Vorschaubilder aller Doppelseiten mit Probedaten (B2b), ohne Spiel.
//
// Aufruf:  node scripts/preview-book.mjs [--only <reiter>[,<reiter>...]] [--profil voll|frisch|zehn] [--lang de|en] [--sperren] [--buch] [--todo] [--help]
//
// Ablauf: Das Addon laeuft in der fengari-VM mit der Frame-Attrappe (tests/helpers/wow-vm.mjs, tests/fixtures/ui-mock.lua) und der
// simulierten Reise 1 -> 60 (tests/fixtures/journey.lua). Je Reiter (und die Unteransichten Tagebuch, Weggefaehrten, Am Feuer, Questtext,
// Fundliste) sammelt der Pruef-Helfer der Sperrflaechen (tests/helpers/keepout.mjs) die sichtbaren Elemente mit ihrer Lage; dieses
// Skript zeichnet sie im Headless-Browser auf das gerenderte Seitenpaar (render-media renderSpreadRaw):
//   - Texte in Ersatzschriften (Morpheus -> Palatino Kapitaelchen, Friz -> Georgia, Arial Narrow; Caveat aus Media/Fonts), Farbe
//     und Groesse wie gesetzt;
//   - Texturen aus Media/*.tga (Texturkoordinaten, weisse Zeichen per Maske eingefaerbt); Texturen des Spiels (Karten, Symbole)
//     erscheinen als schraffierte Platzhalter;
//   - Bedienelemente selbst sind unsichtbar (nur ihre Texturen/Texte).
// Die Attrappe rechnet kein echtes Layout: Textbreiten sind geschaetzt, Drehungen fehlen. Fuer die Gesamtwirkung und die Lage der
// Inhalte reicht das; die Feinabnahme bleibt der Sichttest im Spiel.
//
// --buch (B3): statt der Doppelseiten das ganze Buch samt Einband, Reitern rechts und Unter-Lesezeichen unten (Ebenen nach Frame-Ebene
// der Attrappe): tests/screens/b3-reise.png (Karte), b3-chronik.png (Tagebuch), b3-schaetze.png (Ausruestungsfunde) und
// b3-dropdown.png (Quests, Spaltenkopf-Popup "Gebiet" offen, Papierzettel).
//
// Ergebnis: tests/screens/b2-<reiter>.png (eine Doppelseite, 1076 x 693), b2-<reiter>-<unteransicht>.png und
// tests/screens/b2-uebersicht.png (alle 7 Reiter als Raster 2 x 4); Notizen zusaetzlich als n1-notizen.png und n1-notizen-edit.png. Auf der Konsole je Seite die Ueberlappungen von Inhalt und
// Sperrflaechen (Verzierungen). --sperren zeichnet die Sperrflaechen zusaetzlich rot gestrichelt ein (Arbeitsbild fuer die
// Seiten-Bauer).

import { execFileSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { createVm, ROOT, ADDON_DIR } from "../tests/helpers/wow-vm.mjs";
import { KEEPOUT_LUA_HELPER, findOverlaps, formatOverlaps, keepoutFor, PAGE_W } from "../tests/helpers/keepout.mjs";
import { decodePng, encodePng, KEEPOUT, renderSpreadRaw } from "./render-media.mjs";

export const TABS = ["reise", "chronik", "kampf", "quests", "schaetze", "momente", "notizen"];
const TAB_LABEL = { reise: "Reise", chronik: "Chronik", kampf: "Kampf", quests: "Quests", schaetze: "Schätze", momente: "Momente", notizen: "Notizen" };
const DUNGEONS_CLOSE = `
  local P = NS.Journal.QuestsPage
  local DV = P.dungeonView
  DV.level, DV.mode, DV.all, DV.key, DV.sel, DV.chains, DV.scrollDg = 1, "quests", false, nil, nil, {}, nil
  P:ShowSub("historie")
  C_QuestLog.IsQuestFlaggedCompleted, C_QuestLog.GetNumQuestLogEntries = DV_SAVED.flagged, DV_SAVED.n
  NS.Journal.OpenQuests.invalidate()`;
// Unteransichten: [reiter, name, Lua zum Oeffnen, Lua zum Schliessen]
export const SUBVIEWS = [
  ["reise", "gesamt", "NS.Journal.Frame.selectTotal()", "NS.Journal.Frame.selectTotal()"],
  // T2: To-Do-Seite mit Zielen (Probedaten ohne Sammler: Gegner mit Fortschritt, Gegenstand, Ort mit Entfernung, frei), Zettel auf "Gegner"
  ["reise", "todo", 'local now = time() local L = { ' +
    '{ id = 1, kind = "kill", text = "Gescheckter Eber", need = 10, have = 4, progress = "4/10", created = now - 3 * 86400 }, ' +
    '{ id = 2, kind = "item", text = "Hasenpfote", need = 8, have = 3, progress = "3/8", created = now - 2 * 86400 }, ' +
    '{ id = 3, kind = "place", text = "Der alte Brunnen", mapID = 1411, x = 0.5, y = 0.5, dist = 140, created = now - 86400 }, ' +
    '{ id = 4, kind = "free", text = "Mit dem Zeppelin fliegen", created = now - 3600 }, ' +
    '{ id = 5, kind = "kill", text = "Murloc-Fischer", need = 5, have = 5, progress = "5/5", created = now - 5 * 86400, done = now - 7200 } } ' +
    'NS.Plans = { TEXT_MAX = 120, MAX = 200, nearby = function() return {} end, label = function(p) return p.text end, ' +
    'list = function(f) local o = {} for _, p in ipairs(L) do if f == nil or f == "all" or (f == "open") == (p.done == nil) then o[#o + 1] = p end end return o end } ' +
    'NS.Journal.Frame.showSub("vorhaben") NS.Journal.Vorhaben.setKind("kill") ' +
    'NS.Journal.Vorhaben.pickTarget({ value = 3098, rec = { id = 3098, name = "Gescheckter Eber", level = 5 } }) NS.Journal.Vorhaben.refresh()',
    'NS.Journal.Vorhaben.setKind("free") NS.Journal.Frame.showSub("karte")'],
  // To Do Archiv (erledigte, Zurueckholen/Loeschen) mit offener Rueckfrage "endgueltig loeschen?" an der ersten Zeile
  ["reise", "todo-archiv", 'local now = time() local L = { ' +
    '{ id = 1, kind = "kill", text = "Gescheckter Eber", need = 10, have = 4, progress = "4/10", created = now - 3 * 86400 }, ' +
    '{ id = 5, kind = "kill", text = "Murloc-Fischer", need = 5, have = 5, progress = "5/5", created = now - 5 * 86400, done = now - 7200 }, ' +
    '{ id = 6, kind = "free", text = "Mit dem Zeppelin fliegen", created = now - 6 * 86400, done = now - 86400 }, ' +
    '{ id = 7, kind = "place", text = "Der alte Brunnen", mapID = 1411, x = 0.5, y = 0.5, created = now - 7 * 86400, done = now - 2 * 86400 } } ' +
    'NS.Plans = { TEXT_MAX = 120, MAX = 200, nearby = function() return {} end, label = function(p) return p.text end, ' +
    'list = function(f) local o = {} for _, p in ipairs(L) do if f == nil or f == "all" or (f == "open") == (p.done == nil) then o[#o + 1] = p end end return o end } ' +
    'NS.Journal.Frame.showSub("vorhaben") local V = NS.Journal.Vorhaben V.setView("archive") V.askDelete(5, V.state.rows[1])',
    'NS.Journal.Vorhaben.cancelDelete() NS.Journal.Vorhaben.setView("open") NS.Journal.Frame.showSub("karte")'],
  // To Do: Kartenfenster "Ort waehlen" ueber der Seite (Beobachtung 30.10.), Pinnadel gesetzt
  ["reise", "todo-ort", 'NS.Journal.Frame.showSub("vorhaben") local V = NS.Journal.Vorhaben V.setKind("place") ' +
    'V.state.zone = 1411 V.state.edit:SetText("Der alte Brunnen") V.startPick() V.pickAt(0.42, 0.55)',
    'NS.Journal.Vorhaben.cancelPick() NS.Journal.Vorhaben.state.zone = nil NS.Journal.Vorhaben.setKind("free") NS.Journal.Frame.showSub("karte")'],
  // Zonenansicht einer Zone ohne Reisedaten ("Unentdecktes Kapitel" + gekritzelter Satz), Reise-Feinschliff
  ["reise", "unentdeckt", "NS.Journal.Frame.select({ zone = 1438 })", "NS.Journal.Frame.select(nil)"],
  ["kampf", "tode", "NS.Journal.KampfPage.OpenDeath(NS.Journal.KampfPage, 1)", "NS.Journal.KampfPage.CloseDeath(NS.Journal.KampfPage)"],
  ["chronik", "tagebuch", "NS.Journal.ChronikPage:OpenDiary()", "NS.Journal.ChronikPage:CloseSub()"],
  ["chronik", "weggefaehrten", "NS.Journal.ChronikPage:OpenCompanions()", "NS.Journal.ChronikPage:CloseSub()"],
  ["chronik", "feuer", "NS.Journal.ChronikPage:OpenFire()", "NS.Journal.ChronikPage:CloseSub()"],
  ["quests", "questtext", "NS.Journal.QuestsPage:ToggleTable()", "NS.Journal.QuestsPage:ToggleTable()"],
  // Offene Quests (Unter-Lesezeichen "Offen"): echtes Datenaddon, Untoter Paladin Stufe 8, Zone Tirisfal (gesperrte an) bzw. "Alle Zonen"
  ["quests", "offen", () => OPEN_QUESTS_LUA(1420), 'NS.Journal.QuestsPage:ShowSub("historie")'],
  ["quests", "offen-alle", () => OPEN_QUESTS_LUA("all"), 'NS.Journal.QuestsPage:ShowSub("historie")'],
  // Karte 2 (Beobachtung 30.10.): beide Kontinente, Durotar und Unterstadt (Stadt als eigene Zone)
  ["quests", "offen-kalimdor", () => OPEN_QUESTS_LUA("all", "OV:SetContinent(1414)"), 'NS.Journal.QuestsPage:ShowSub("historie")'],
  ["quests", "offen-ostkoenigreiche", () => OPEN_QUESTS_LUA("all", "OV:SetContinent(1415)"), 'NS.Journal.QuestsPage:ShowSub("historie")'],
  ["quests", "offen-durotar", () => OPEN_QUESTS_LUA(1411), 'NS.Journal.QuestsPage:ShowSub("historie")'],
  ["quests", "offen-unterstadt", () => OPEN_QUESTS_LUA(1458), 'NS.Journal.QuestsPage:ShowSub("historie")'],
  // Dungeons (Unter-Lesezeichen "Dungeons", nur Forever): echtes Datenaddon, Untoter Paladin, Fortschritt aus den Stufen (DUNGEONS_LUA)
  ["quests", "dungeons", () => DUNGEONS_LUA(24), DUNGEONS_CLOSE],
  ["quests", "dungeons-karte", () => DUNGEONS_LUA(24, 'DV:SetMode("map")'), DUNGEONS_CLOSE],
  ["quests", "dungeons-seite", () => DUNGEONS_LUA(24, 'DV:OpenDungeon("721")'), DUNGEONS_CLOSE],
  ["quests", "dungeons-scholomance", () => DUNGEONS_LUA(58, 'DV:SelectDungeon("2057")'), DUNGEONS_CLOSE],
  // 106er-Kette (Fraktionen zusammen, "Alle"): zugeklappt mit Deckel, dann die ganze Kette nach einem Klick auf den Deckel
  ["quests", "dungeons-brs", () => DUNGEONS_LUA(58, 'DV:SetAll(true) DV:OpenDungeon("1583") DV_LONG()'), DUNGEONS_CLOSE],
  ["quests", "dungeons-brs-offen", () => DUNGEONS_LUA(58, 'DV:SetAll(true) DV:OpenDungeon("1583") DV_LONG() local it = DV_MORE() if it then DV:OnItem(it) end'), DUNGEONS_CLOSE],
  // Lehrplan (Unter-Lesezeichen "Lehrplan", nur Forever): Untoter Paladin Stufe 20, ein Teil gelernt, ein Lehrer bekannt, Talentpunkt frei
  ["quests", "lehrplan", () => LEHRPLAN_LUA, 'NS.Journal.QuestsPage:ShowSub("historie") LEHRPLAN_RESTORE()'],
  ["schaetze", "funde", "NS.Journal.SchaetzePage:OpenFunde()", "NS.Journal.SchaetzePage:CloseFunde()"],
  ["schaetze", "quellen", 'NS.Journal.SchaetzePage:SetFlow("bars")', 'NS.Journal.SchaetzePage:SetFlow("levels")'],
  ["schaetze", "besitz", 'NS.Journal.SchaetzePage:SetFlow("hold")', 'NS.Journal.SchaetzePage:SetFlow("levels")'],
  ["momente", "buch", "local P = NS.Journal.MomentePage P:Read(P.view.library.books[1].key)", "NS.Journal.MomentePage:CloseBook()"],
  ["notizen", "edit", 'NS.Journal.NotizenPage:SetMode("edit")', 'NS.Journal.NotizenPage:SetMode("read")'],
];
// Offene Quests: das echte Datenaddon (wird erst beim Oeffnen der Rubrik gelesen), Kartenkunst als Platzhalter-Kachel
const QUEST_DATA_DIR = path.join(ROOT, "addon", "InkAndEmbers_QuestData");
const QUEST_DATA_LUA = () => `
  if not REAL_QUEST_DATA then
    REAL_QUEST_DATA = function()
${readFileSync(path.join(QUEST_DATA_DIR, "Quests.lua"), "utf8")}
${readFileSync(path.join(QUEST_DATA_DIR, "Givers.lua"), "utf8")}
${readFileSync(path.join(QUEST_DATA_DIR, "Names.lua"), "utf8")}
${readFileSync(path.join(QUEST_DATA_DIR, "Overlays.lua"), "utf8")}
${readFileSync(path.join(QUEST_DATA_DIR, "Dungeons.lua"), "utf8")}
    end
    C_AddOns = C_AddOns or {}
    C_AddOns.LoadAddOn = function() REAL_QUEST_DATA() return true end
  end
  local V = NS.Journal.View
  V.zoneArt = function(id) return { w = 1002, h = 668, tileW = 1002, tileH = 668, files = { 100 + id } } end
  V.mapArt = V.zoneArt
  -- Lage der Zonen auf dem Kontinent: die Attrappe kennt keine; fuer das Bild Schein-Rechtecke je Zone (nur Vorschau)
  NS.Journal.Geo.setProvider({ rect = function(id)
    local x, y = ((id * 37) % 70) / 100 + 0.1, ((id * 53) % 70) / 100 + 0.1
    return x, x + 0.08, y, y + 0.08
  end })`;
export const OPEN_QUESTS_LUA = (zone, after = "") => `${QUEST_DATA_LUA()}
  H.units.player.level = 8; H.units.player.raceFile = "Scourge"; H.units.player.classFile = "PALADIN"; H.units.player.faction = "Horde"
  NS.Journal.Pages.setSetting("openZone", ${JSON.stringify(zone)})
  NS.Journal.Pages.setSetting("openLocked", true)
  local P = NS.Journal.QuestsPage
  P:ShowSub("offen")
  local OV = P.openView
  OV:SetZone(${JSON.stringify(zone)})
  ${after}
  if OV.items[2] then OV:SelectQuest(OV.items[2].id, true) end`;

// Dungeons-Vorschau: Untoter Paladin der genannten Stufe; erledigt ist, was deutlich unter seiner Stufe liegt (jede vierte Quest nicht),
// im Log zwei Quests seiner Stufe. Der Geo-Schein von QUEST_DATA_LUA legt die Zonen auf den Kontinent; zu welchem Kontinent eine Zone
// gehoert, kommt aus MapSpace.
export const DUNGEONS_LUA = (level, after = "") => `${QUEST_DATA_LUA()}
  H.units.player.level = ${level}; H.units.player.raceFile = "Scourge"; H.units.player.classFile = "PALADIN"; H.units.player.faction = "Horde"
  local OQ = NS.Journal.OpenQuests
  DV_SAVED = DV_SAVED or { flagged = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted, n = C_QuestLog and C_QuestLog.GetNumQuestLogEntries, info = C_QuestLog and C_QuestLog.GetInfo }
  C_QuestLog = C_QuestLog or {}
  C_QuestLog.IsQuestFlaggedCompleted = function(id)
    local r = OQ.record(id)
    return r ~= nil and (r.level or 99) <= ${level} - 6 and id % 4 ~= 0
  end
  C_QuestLog.GetNumQuestLogEntries = function() return 0, 0 end
  OQ.invalidate()
  local P = NS.Journal.QuestsPage
  P:ShowSub("dungeons")
  DV = P.dungeonView
  function DV_MORE() for _, it in ipairs(DV.items) do if it.kind == "more" then return it end end end
  function DV_LONG() for _, it in ipairs(DV.items) do if it.kind == "more" then DV.ui.list:SetOffset(0) return end end end
  ${after}`;

// Lehrplan-Vorschau: Zauberbuch-Attrappe (Namen aus Zauber-IDs), ein gelernter Teil bis Stufe 12, ein bekannter Lehrer, 1 Talentpunkt frei
export const LEHRPLAN_LUA = `
  local saved = { C_Spell = C_Spell, C_SpellBook = C_SpellBook, GetMoney = GetMoney, C_ClassTalents = C_ClassTalents, C_Traits = C_Traits,
    level = H.units.player.level }
  function LEHRPLAN_RESTORE()
    C_Spell, C_SpellBook, GetMoney, C_ClassTalents, C_Traits = saved.C_Spell, saved.C_SpellBook, saved.GetMoney, saved.C_ClassTalents, saved.C_Traits
    H.units.player.level = saved.level
    NS.Store.dropSnapshot("trainers", 5491)
    NS.Journal.Lehrplan.resetNames()
  end
  H.units.player.level = 20; H.units.player.raceFile = "Scourge"; H.units.player.classFile = "PALADIN"; H.units.player.faction = "Horde"
  LP_NAMES = { [465] = "Aura der Hingabe", [19740] = "Segen der Macht", [20271] = "Richturteil", [498] = "Göttlicher Schutz",
    [639] = "Heiliges Licht", [679] = "Hammer der Gerechtigkeit", [21082] = "Siegel des Kreuzfahrers", [853] = "Hammer der Gerechtigkeit" }
  C_Spell = { GetSpellName = function(id) return LP_NAMES[id] or ("Zauberspruch des Lichts " .. id) end,
    GetSpellSubtext = function(id) return id % 3 == 0 and "Rang 2" or nil end, GetSpellTexture = function(id) return 135900 + id % 50 end,
    RequestLoadSpellData = function() end }
  LP_KNOWN = {}
  for _, e in ipairs(NS.Journal.Lehrplan.parse("PALADIN").list) do if e.level <= 12 then LP_KNOWN[e.id] = true end end
  C_SpellBook = { IsSpellKnown = function(id) return LP_KNOWN[id] == true end }
  GetMoney = function() return 31250 end
  C_ClassTalents = { GetActiveConfigID = function() return 7 end }
  C_Traits = { GetConfigInfo = function() return { treeIDs = { 11 } } end, GetTreeCurrencyInfo = function() return { { quantity = 1 } } end }
  NS.Store.putSnapshot("trainers", 5491, { name = "Lehrer Zackenbart", mapID = 1458, x = 0.6, y = 0.7, class = "PALADIN" }, true)
  NS.Journal.Lehrplan.resetNames()
  NS.Journal.QuestsPage:ShowSub("lehrplan")`;

// N1: Vorschaubilder der Notizen (Lesen / Bearbeiten) zusaetzlich unter diesen Namen
export const N1_SHOTS = { notizen: "n1-notizen", "notizen-edit": "n1-notizen-edit" };
// Polish P2: Probedaten-Profile. "voll" = Reise 1 -> 60 (b2-*), "frisch" = neuer Charakter Stufe 1 ohne Daten (leer-*),
// "zehn" = rund 10 Minuten Spielzeit, Stufe 2, ein paar Kills/Quests (zehn-*, tests/fixtures/zehn-minuten.lua).
export const PROFILES = { voll: "b2", frisch: "leer", zehn: "zehn" };
// Ansichten der Leerzustands-Vorschau je Profil frisch/zehn: alle Seiten und Unterseiten ausser Kampf und Ausruestungsfunde.
// [reiter, name (leer: Standardansicht), Lua zum Oeffnen, Lua zum Schliessen]
export const EMPTY_VIEWS = [
  ["reise", "", "", ""],
  ["reise", "gesamt", 'NS.Journal.Frame.showSub("gesamt")', 'NS.Journal.Frame.showSub("karte")'],
  ["reise", "todo", 'NS.Journal.Frame.showSub("vorhaben")', 'NS.Journal.Frame.showSub("karte")'],
  ["chronik", "", "", ""],
  ["chronik", "tagebuch", "NS.Journal.ChronikPage:OpenDiary()", "NS.Journal.ChronikPage:CloseSub()"],
  ["chronik", "weggefaehrten", "NS.Journal.ChronikPage:OpenCompanions()", "NS.Journal.ChronikPage:CloseSub()"],
  ["quests", "", "", ""],
  ["quests", "questtext", "NS.Journal.QuestsPage:ToggleTable()", "NS.Journal.QuestsPage:ToggleTable()"],
  ["schaetze", "", "", ""],
  ["schaetze", "quellen", 'NS.Journal.SchaetzePage:SetFlow("bars")', 'NS.Journal.SchaetzePage:SetFlow("levels")'],
  ["momente", "", "", ""],
  ["notizen", "", "", ""],
];
const SCREENS = path.join(ROOT, "tests", "screens");
const MEDIA = path.join(ADDON_DIR, "Media");

// Sammler mit allem, was zum Zeichnen noetig ist (Abwandlung von KO_COLLECT, gleiche Lage-Rechnung)
export const PREVIEW_LUA = `
function KO_FULL(t)
  return (tostring(t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T[^|]*|t", "●"):gsub("|H[^|]*|h", ""):gsub("|h", ""))
end
` + KEEPOUT_LUA_HELPER.replace("function KO_COLLECT(", "function KO_PREVIEW(")
  // UI.measureWidth = "class": Textbreite aus GetStringWidth (Zeichenklassen je Schrift, tests/fixtures/ui-mock.lua) statt 0,5 x Schrift
  .replace("local tw = chars(o._text) * size * 0.5", 'local tw = (UI.measureWidth == "class") and o:GetStringWidth() or chars(o._text) * size * 0.5')
  .replace('item = { kind = "text", label = cut(plain(c._text), 28), rect = { l, t, tw, th } }',
    'item = { kind = "text", label = cut(plain(c._text), 28), full = KO_FULL(c._text), rect = { l, t, tw, th } }')
  .replace('item = { kind = "control", label = (c._text and cut(plain(c._text), 22)) or kind, rect = { r[1], r[2], r[3], r[4] } }',
    'item = { kind = "control", label = (c._text and cut(plain(c._text), 22)) or kind, full = (kind == "EditBox" and c._text and c._text ~= "") and KO_FULL(c._text) or nil, rect = { r[1], r[2], r[3], r[4] } }')
  // To Do u. ae.: ganzflaechiges Blatt (Pergament) einer Ueberlagerung ueber der Karten-Ebene mitzeichnen, damit es abdeckt, was
  // darunter liegt (KO_BIG_MIN = Frame-Ebene; der Keepout-Sammler laesst so grosse Texturen weg). Im Bericht zaehlt es nicht.
  .replace("r[3] * r[4] <= pageArea * 0.35", "(r[3] * r[4] <= pageArea * 0.35 or (KO_BIG_MIN and (o._level or 0) >= KO_BIG_MIN))")
  .replace('item = { kind = "tex", label = cut(name, 28), rect = { r[1], r[2], r[3], r[4] } }',
    'item = { kind = "tex", label = cut(name, 28), big = r[3] * r[4] > pageArea * 0.35 or nil, rect = { r[1], r[2], r[3], r[4] } }')
  .replace("out[#out + 1] = { kind = item.kind, label = item.label, x = rc[1] + ox, y = rc[2] + oy, w = rc[3], h = rc[4] }",
    `out[#out + 1] = { kind = item.kind, label = item.label, x = rc[1] + ox, y = rc[2] + oy, w = rc[3], h = rc[4],
              full = item.full, big = item.big, font = c._font and c._font[1] or nil, size = c._font and c._font[2] or nil, color = c._color,
              tex = type(c._tex) == "string" and c._tex or nil, coords = c._coords, jh = c._justifyH, desat = c._desat,
              alpha = c._alpha, wrap = c._wordWrap, fw = c._w, ml = c._maxLines, sw = c._kind == "FontString" and c:GetStringWidth() or nil, shOff = c._shadowOff, shCol = c._shadowColor, sp = c._spacing, ux = item.rect[1] + ox, uy = item.rect[2] + oy, uw = item.rect[3], uh = item.rect[4],
              lvl = (c._kind == "Texture" or c._kind == "FontString") and (o._level or 0) or (c._level or 0) }`);

// Ausruestungsfunde (B2d): ein paar Dutzend Beute-Eintraege ab Gruen, damit die Fundliste (Schaetze -> Unteransicht) Zeilen hat
const FUNDE_LUA = `
  local S, FU = NS.Store, NS.Journal.Funde
  local c = S.char()
  c.snapshots.items = c.snapshots.items or {}
  local LOCS = { "INVTYPE_HEAD", "INVTYPE_CHEST", "INVTYPE_FEET", "INVTYPE_FINGER", "INVTYPE_2HWEAPON", "INVTYPE_LEGS", "INVTYPE_SHOULDER" }
  local NAMES = { "Grüner Helm", "Wams des Wanderers", "Stiefel der Mühle", "Ring der Dämmerung", "Zweihänder des Südens",
    "Beinlinge der Wache", "Schulterstücke der Jägerin", "Handschuhe des Schmieds" }
  FUNDE_LOC = {}
  for i = 1, 36 do
    local id = 6000 + i
    FUNDE_LOC[id] = LOCS[(i - 1) % #LOCS + 1]
    c.snapshots.items[id] = { name = NAMES[(i - 1) % #NAMES + 1] .. " " .. i, quality = 2 + (i % 3 == 0 and 1 or 0) }
    H.now = H.now + 90
    S.append("LT", tostring(id), 1, c.snapshots.items[id].quality, i % 4 == 0 and "quest" or "mob", "", 10 + i, 1420 + i % 2, 5000, 5000)
  end
  FU.source = { ["C_Item.GetItemInfoInstant"] = function(id) return id, "Rüstung", "Leder", FUNDE_LOC[id], 133070 end,
    ["C_Item.GetItemNameByID"] = function(id) return nil end, ["C_Item.RequestLoadItemDataByID"] = function() end }
  return "ok"`;

// Notizen (N1): ein paar Probe-Notizen (angeheftet, mit Markup, Symbolen und Link), die erste mit Pinnadel
const NOTES_LUA = String.raw`
  local N = NS.Journal.Notes
  local function add(title, body, pinned, onMap)
    H.now = H.now + 3600
    local id = N.create({ title = title, body = body })
    if pinned then N.setPinned(id, true) end
    if onMap then local n = NS.Store.char().notes.list[#NS.Store.char().notes.list] n.mapID, n.x, n.y = 1429, 0.42, 0.61 N.setOnMap(id, true) end
    return id
  end
  add("Händler für Leinenstoff", "Der Schneider in Goldhain kauft {gruen}Leinenstoff{/} zum guten Preis.", false, false)
  add("Wolfsrudel am Nordhang", "- {tod} **Vorsicht** nach Einbruch der Nacht\n- drei Elitewölfe {rt8}", false, false)
  add("Kräuterroute", "Friedensblume wächst entlang des Flusses. Silberblatt eher an den Hängen.", false, false)
  add("Erzader am See", "# Was ich brauche\n- Kupfererz {rt1}\n- Stoff: |Hitem:2589:0|h[Leinenstoff]|h\n[ ] 10 Kupferbarren schmelzen\n[x] Spitzhacke gekauft\n---\n{rot}Achtung:{/} Der **Murloc-Anführer** {selten} streift um den See.\nZurück zum {ruhestein} in Goldhain.", true, true)
  return "ok"`;

const HELP = `Vorschaubilder aller Doppelseiten mit Probedaten (Headless-Browser)

Aufruf:
  node scripts/preview-book.mjs [--only reise,chronik,...] [--profil voll|frisch|zehn] [--lang de|en] [--sperren] [--help]

  --only     nur diese Reiter (mit ihren Unteransichten)
  --lang     Sprache der Oberflaeche: de (Standard) oder en (Spielsprache enUS); Bilder heissen dann en-b2-<reiter>.png usw.
  --sperren  Sperrflaechen (Verzierungen) rot gestrichelt einzeichnen
  --profil   Probedaten: voll (Reise 1-60, Standard, b2-*), frisch (neuer Charakter Stufe 1, leer-*),
             zehn (10 Minuten Spielzeit, Stufe 2, zehn-*); frisch/zehn zeigen alle Seiten/Unterseiten ausser
             Kampf und Ausruestungsfunde
  --buch     ganzes Buch mit Einband und Unter-Lesezeichen (B3): b3-reise/-chronik/-schaetze/-dropdown.png
  --todo     Notizzettel am Bildschirmrand in beiden Stilen (Z3): todo-tracker-notizblock.png, todo-tracker-schlicht.png
  --groessen (mit --todo) zusaetzlich beide Stile klein/mittel/gross mit 1 und 8 Eintraegen, 2x vergroessert (Naehte pruefen):
             <praefix>-<stil>-<groesse>-<n>.png, Praefix ueber --praefix <name> (Standard todo-var)
Ziel: tests/screens/b2-<reiter>.png, b2-<reiter>-<unteransicht>.png, b2-uebersicht.png`;

export function findBrowser() {
  const list = [process.env.CHROME_PATH, "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
    "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe", "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
    "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe", "/usr/bin/google-chrome", "/usr/bin/chromium"].filter(Boolean);
  return list.find((p) => existsSync(p));
}

export function screenshot(browser, tmp, html, w, h, png) {
  const file = path.join(tmp, `p${Math.random().toString(36).slice(2)}.html`);
  writeFileSync(file, html, "utf8");
  execFileSync(browser, ["--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
    "--default-background-color=FFFFFFFF", `--user-data-dir=${path.join(tmp, "profile")}`, `--window-size=${w},${h}`,
    "--virtual-time-budget=3000", `--screenshot=${png}`, pathToFileURL(file).href], { stdio: "ignore", timeout: 90000 });
}

/** TGA (Typ 2, 32 bit) lesen -> { w, h, rgba } */
function readTga(file) {
  const b = readFileSync(file);
  const w = b.readUInt16LE(12), h = b.readUInt16LE(14), off = 18 + b[0];
  const top = (b[17] & 0x20) !== 0;
  const out = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) {
    const sy = top ? y : h - 1 - y;
    for (let x = 0; x < w; x++) {
      const s = off + (sy * w + x) * 4, d = (y * w + x) * 4;
      out[d] = b[s + 2]; out[d + 1] = b[s + 1]; out[d + 2] = b[s]; out[d + 3] = b[s + 3];
    }
  }
  return { w, h, rgba: out };
}

const texCache = new Map();
/** Addon-Textur (Interface\\AddOns\\InkAndEmbers\\Media\\X) -> data-URL (PNG) | null */
function texUrl(tex) {
  const m = /Media\\(.+)$/i.exec(tex || "");
  if (!m) return null;
  const rel = m[1].replace(/\\/g, "/");
  if (texCache.has(rel)) return texCache.get(rel);
  let url = null;
  const tga = path.join(MEDIA, rel.endsWith(".tga") ? rel : rel + ".tga");
  if (existsSync(tga)) {
    const t = readTga(tga);
    // data-URL: Masken (mask-image) laedt Chrome von file:// nicht (CORS), eingefaerbte Zeichen fehlten sonst
    url = "data:image/png;base64," + encodePng(t.w, t.h, t.rgba).toString("base64");
  }
  texCache.set(rel, url);
  return url;
}

const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const rgba = (c, a = 1) => (Array.isArray(c) ? `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${(c[3] ?? 1) * a})` : null);
// weisse Zeichen, die im Spiel per SetVertexColor eingefaerbt werden
const WHITE_TEX = /(DiaryCircle|DiaryStroke|Stroke|Arrow|Dash|Disc|Glow|RoundRect|RoundRing|ClockBar|Grave|Markers|Sword|MapFade|PageFade|TodoMarks)$/i;
const DIARY_MARK_WHITE = /DiaryMarks$/i;

function fontCss(file, size) {
  const f = String(file || "").toUpperCase();
  const px = `${size || 12}px`;
  if (f.includes("MORPHEUS")) return `font-family:'Palatino Linotype','Book Antiqua',serif;font-variant:small-caps;font-size:${px};letter-spacing:0.02em`;
  if (f.includes("ARIALN")) return `font-family:'Arial Narrow','Arial',sans-serif;font-stretch:condensed;font-size:${px}`;
  if (f.includes("CAVEAT")) return `font-family:'Caveat';font-weight:700;font-size:${px}`;
  if (f.includes("FRIZQT")) return `font-family:'Friz Quadrata TT','Friz Quadrata Std','Friz Quadrata',Georgia,'Times New Roman',serif;font-size:${px}`;
  return `font-family:Georgia,'Times New Roman',serif;font-size:${px}`;
}
// Schatten einer Schrift (SetShadowOffset/SetShadowColor; WoW-y zeigt nach oben)
const textShadow = (it) => (Array.isArray(it.shOff) && (it.shOff[0] || it.shOff[1]) && Array.isArray(it.shCol)
  ? `text-shadow:${it.shOff[0]}px ${-it.shOff[1]}px 0 ${rgba(it.shCol)};` : "");

function itemHtml(tmp, it) {
  // N1: Inhalt eines Eingabefelds (EditBox) als mehrzeiliger Text oben links im Feld (Einzug wie SetTextInsets ca. 6 px)
  if (it.kind === "control" && it.full) {
    const color = rgba(it.color) || "rgba(43,33,24,0.9)";
    return `<div style="position:absolute;left:${it.x + 6}px;top:${it.y + 3}px;width:${Math.max(it.w - 12, 1)}px;height:${Math.max(it.h - 6, 1)}px;color:${color};${fontCss(it.font, it.size)};line-height:1.35;white-space:pre-wrap;overflow:hidden">${esc(it.full)}</div>`;
  }
  if (it.kind === "text") {
    const color = rgba(it.color) || "rgba(43,33,24,0.9)";
    const jh = it.jh === "RIGHT" ? "right" : it.jh === "CENTER" ? "center" : "left";
    const multi = it.h > (it.size || 12) * 1.7;
    // SetSpacing (Notizblock-Zeilen): Zeilenvorschub = Schriftgroesse + Abstand, erste Zeile bleibt oben (wie im Client)
    const sz = it.size || 12;
    const lh = it.sp > 0 ? `line-height:${sz + it.sp}px;margin-top:${-((sz + it.sp) - sz * 1.2) / 2}px` : "line-height:1.2";
    return `<div style="position:absolute;left:${it.x}px;top:${it.y}px;width:${Math.max(it.w, 1) + (multi ? 0 : 60)}px;${multi ? `height:${it.h}px;` : ""}${jh === "right" && !multi ? `margin-left:-60px;` : ""}${jh === "center" && !multi ? `margin-left:-30px;` : ""}text-align:${jh};color:${color};${textShadow(it)}${fontCss(it.font, it.size)};${lh};white-space:${multi ? "normal" : "nowrap"};overflow:${it.sp > 0 ? "visible" : "hidden"}">${esc(it.full ?? it.label)}</div>`;
  }
  if (it.kind !== "tex") return "";
  const alpha = it.alpha ?? 1;
  if (it.tex === "color") {
    const c = rgba(it.color, alpha);
    return c ? `<div style="position:absolute;left:${it.x}px;top:${it.y}px;width:${it.w}px;height:${it.h}px;background:${c}"></div>` : "";
  }
  const url = texUrl(it.tex);
  if (!url) {
    // Textur des Spiels (Karte, Icons, Modelle): Platzhalter
    return `<div style="position:absolute;left:${it.x}px;top:${it.y}px;width:${it.w}px;height:${it.h}px;background:repeating-linear-gradient(45deg,rgba(107,80,52,0.14) 0 6px,rgba(107,80,52,0.05) 6px 12px);outline:1px solid rgba(107,80,52,0.25)"></div>`;
  }
  // Texturkoordinaten (4 oder 8 Werte) -> Ausschnitt; gerechnet auf dem ungekuerzten Rechteck (ux/uy/uw/uh), dann beschnitten
  let l = 0, r = 1, t = 0, b = 1;
  const c = it.coords;
  // Drehung um 90 Grad (8 Werte, UL und LL mit gleichem v, verschiedenem u; B2f Play/Pause): ungedreht zeichnen und per CSS drehen
  if (Array.isArray(c) && c.length >= 8 && !it.rot && Math.abs(c[0] - c[2]) > 1e-6 && Math.abs(c[1] - c[3]) < 1e-6) {
    const cx = it.x + it.w / 2, cy = it.y + it.h / 2;
    const us = [c[0], c[2], c[4], c[6]], vs = [c[1], c[3], c[5], c[7]];
    const box = { x: cx - it.h / 2, y: cy - it.w / 2, w: it.h, h: it.w };
    return itemHtml(tmp, { ...it, ...box, ux: box.x, uy: box.y, uw: box.w, uh: box.h,
      coords: [Math.min(...us), Math.max(...us), Math.min(...vs), Math.max(...vs)], rot: c[0] > c[2] ? -90 : 90 });
  }
  if (Array.isArray(c) && c.length >= 8) {
    const us = [c[0], c[2], c[4], c[6]], vs = [c[1], c[3], c[5], c[7]];
    l = Math.min(...us); r = Math.max(...us); t = Math.min(...vs); b = Math.max(...vs);
  } else if (Array.isArray(c) && c.length >= 4) [l, r, t, b] = c;
  const flipX = r < l, flipY = b < t;
  const L = Math.min(l, r), R = Math.max(l, r), T = Math.min(t, b), B = Math.max(t, b);
  const uw = it.uw || it.w, uh = it.uh || it.h;
  const bw = uw / Math.max(1e-6, R - L), bh = uh / Math.max(1e-6, B - T);
  const bx = -L * bw - (it.x - (it.ux ?? it.x)), by = -T * bh - (it.y - (it.uy ?? it.y));
  const tf = flipX || flipY || it.rot ? `transform:${it.rot ? `rotate(${it.rot}deg) ` : ""}scale(${flipX ? -1 : 1},${flipY ? -1 : 1});` : "";
  const white = WHITE_TEX.test(it.tex) || (DIARY_MARK_WHITE.test(it.tex) && !(L >= 0.5 && T < 0.25));
  const tint = it.color && white ? rgba(it.color, alpha) : null;
  const pos = `${bx}px ${by}px`, size = `${bw}px ${bh}px`;
  if (tint) {
    return `<div style="position:absolute;left:${it.x}px;top:${it.y}px;width:${it.w}px;height:${it.h}px;${tf}background:${tint};-webkit-mask-image:url('${url}');-webkit-mask-size:${size};-webkit-mask-position:${pos};-webkit-mask-repeat:no-repeat"></div>`;
  }
  const op = it.color && !white ? (it.color[3] ?? 1) * alpha : alpha;
  // B3: gleichmaessig abgedunkelte farbige Texturen (SetVertexColor(v, v, v), z. B. inaktive Lesezeichen) als Helligkeitsfilter
  const c3 = Array.isArray(it.color) && !white ? it.color : null;
  const dim = c3 && Math.abs(c3[0] - c3[1]) < 1e-3 && Math.abs(c3[1] - c3[2]) < 1e-3 && c3[0] < 0.999 ? c3[0] : null;
  const filter = it.desat ? "filter:grayscale(1) brightness(0.7);" : (dim !== null ? `filter:brightness(${dim});` : "");
  return `<div style="position:absolute;left:${it.x}px;top:${it.y}px;width:${it.w}px;height:${it.h}px;${tf}background:url('${url}') no-repeat;background-size:${size};background-position:${pos};opacity:${op};${filter}"></div>`;
}

/** HTML einer Doppelseite: Papier (PNG) + Elemente (Pixel der Doppelseite, y + KEEPOUT.top) */
function spreadHtml(tmp, paperPng, items, decor) {
  const caveat = pathToFileURL(path.join(MEDIA, "Fonts", "Caveat-Bold.ttf")).href;
  const top = KEEPOUT.top;
  // P2: nach Frame-Ebene, darin erst Texturen, dann Texte (wie --buch); Ueberlagerungen wie das To-Do-Blatt decken so ab.
  // N1: Eingabefelder mit Inhalt (control + full) zeichnen wie Texte.
  const drawn = items.filter((i) => i.kind === "tex" || i.kind === "text" || (i.kind === "control" && i.full));
  const sorted = drawn.map((it, i) => ({ it, i })).sort((a, b) => (a.it.lvl ?? 0) - (b.it.lvl ?? 0)
    || (a.it.kind !== "tex") - (b.it.kind !== "tex") || a.i - b.i).map((e) => e.it);
  const body = sorted.map((i) => itemHtml(tmp, { ...i, y: i.y + top, uy: (i.uy ?? i.y) + top })).join("\n");
  const deco = (decor || []).map((d) => `<div style="position:absolute;left:${d.x}px;top:${d.y + top}px;width:${d.w}px;height:${d.h}px;outline:1.5px dashed rgba(200,0,0,0.75);background:rgba(255,0,0,0.06)"></div>`).join("");
  return `<!doctype html><html><head><meta charset="utf-8"><style>
@font-face{font-family:'Caveat';src:url('${caveat}');font-weight:700}
html,body{margin:0;padding:0;background:#fff;overflow:hidden}
#s{position:relative;width:${KEEPOUT.w}px;height:${KEEPOUT.h}px;background:url('${pathToFileURL(paperPng).href}') no-repeat}
</style></head><body><div id="s">${body}${deco}</div></body></html>`;
}

// Sprache der Vorschau: "de" (Standard) oder "en" (Dateien mit Praefix en-); auch volle Locales ("deDE", "enUS") sind erlaubt
export const LANGS = { de: "deDE", en: "enUS" };

// measure: true (Standard: Zeichenzahl x Schrift x Faktor) oder "class" (Zeichenklassen je Schrift, Layout-Test je Sprache)
export function bootVm({ profil = "voll", lang = "de", measure = true } = {}) {
  const locale = LANGS[lang] || (/^[a-z]{2}[A-Z]{2}$/.test(lang) ? lang : null);
  if (!locale) throw new Error(`Unbekannte Sprache: ${lang} (${Object.keys(LANGS).join(", ")})`);
  if (!PROFILES[profil]) throw new Error(`Unbekanntes Profil: ${profil} (${Object.keys(PROFILES).join(", ")})`);
  const UIMOCK = readFileSync(path.join(ROOT, "tests", "fixtures", "ui-mock.lua"), "utf8");
  const vm = createVm({ setup: `GetLocale = function() return "${locale}" end
${UIMOCK}` });
  vm.boot();
  vm.exec("NS.Journal.Index.ASYNC = false");
  if (profil === "voll") {
    vm.exec("JOURNEY_ROUTE = true");
    vm.exec(readFileSync(path.join(ROOT, "tests", "fixtures", "journey.lua"), "utf8"));
    vm.exec("H.units.player.level = 60");
  } else if (profil === "zehn") {
    vm.exec(readFileSync(path.join(ROOT, "tests", "fixtures", "zehn-minuten.lua"), "utf8"));
  }
  vm.exec(`UI.measureText = true; UI.measureWidth = ${measure === "class" ? '"class"' : "true"}; JF = NS.Journal.Frame`);
  if (profil === "voll") {
    vm.exec(FUNDE_LUA);
    vm.exec(NOTES_LUA);
  }
  vm.slash("/chronik");
  vm.exec(PREVIEW_LUA + "\nreturn 'ok'");
  return vm;
}

const collect = (vm) => {
  const all = vm.lua(`local over = NS.Journal.Frame.state.over
    KO_BIG_MIN = over and ((over._level or 0) + 1) or nil
    local r = KO_PREVIEW(NS.Journal.Frame.state.spread, 0, 0, ${PAGE_W * 2 * 666})
    KO_BIG_MIN = nil
    return r`);
  return Array.isArray(all) ? all : [];
};

// B3: das ganze Buch (Fenster samt Einband, Reiter rechts, Unter-Lesezeichen unten) in Fenster-Pixeln, mit Rand rundherum
export const BOOK_PAD = 24;
export const BOOK_SHOTS = [
  ["b3-reise", "reise", ""],
  ["b3-chronik", "chronik", 'NS.Journal.Frame.showSub("tagebuch")'],
  ["b3-schaetze", "schaetze", 'NS.Journal.Frame.showSub("funde")'],
  // Spaltenkopf-Popup "Gebiet" offen, Maus ueber dem dritten Eintrag (Tintenstrich)
  ["b3-dropdown", "quests", 'local Q = NS.Journal.QuestsPage Q:TogglePopup("area") local r = Q.ui.lists.area.rows[3] r._scripts.OnEnter(r)'],
];

export function bookHtml(items, w, h) {
  const caveat = pathToFileURL(path.join(MEDIA, "Fonts", "Caveat-Bold.ttf")).href;
  // Zeichenfolge: Frame-Ebene des Besitzers, darin erst Texturen, dann Texte, sonst Reihenfolge des Anlegens
  const sorted = items.map((it, i) => ({ it, i })).sort((a, b) => (a.it.lvl ?? 0) - (b.it.lvl ?? 0)
    || (a.it.kind === "text") - (b.it.kind === "text") || a.i - b.i).map((e) => e.it);
  const body = sorted.map((i) => itemHtml(null, { ...i, x: i.x + BOOK_PAD, y: i.y + BOOK_PAD, ux: (i.ux ?? i.x) + BOOK_PAD, uy: (i.uy ?? i.y) + BOOK_PAD })).join("\n");
  return `<!doctype html><html><head><meta charset="utf-8"><style>
@font-face{font-family:'Caveat';src:url('${caveat}');font-weight:700}
html,body{margin:0;padding:0;background:#2a231d;overflow:hidden}
#s{position:relative;width:${w}px;height:${h}px}
</style></head><body><div id="s">${body}</div></body></html>`;
}

function bookShots(vm, browser, tmp) {
  const geo = vm.lua("local F = NS.Journal.Frame return { F.W, F.H, F.TABS_OUT, F.SUBTABS_OUT, F.RIM }");
  const [W, H, TOUT, SOUT, RIM] = geo;
  const w = W + TOUT + 2 * BOOK_PAD, h = H + SOUT + 2 * BOOK_PAD;
  for (const [name, tab, open] of BOOK_SHOTS) {
    vm.lua(`return NS.Journal.Frame.showPage(${JSON.stringify(tab)})`);
    if (open) vm.exec(open);
    let items = vm.lua(`return KO_PREVIEW(NS.Journal.Frame.state.frame, 0, 0, 1e12)`);
    items = Array.isArray(items) ? items : [];
    if (tab === "reise") {
      const [mx, my, mw, mh] = vm.lua("local M = NS.Journal.Frame.MAP return { M.x, M.y, M.w, M.h }").map((v, i) => v + (i < 2 ? RIM : 0));
      const inMap = (i) => i.x >= mx && i.y >= my && i.x + i.w <= mx + mw && i.y + i.h <= my + mh;
      items = items.filter((i) => !inMap(i));
      items.push({ kind: "tex", tex: "MAP", x: mx + 20, y: my + 20, w: mw - 40, h: mh - 40, lvl: 99, label: "Karte" },
        { kind: "text", full: "Karte (Kunst aus dem Spiel)", x: mx + 20, y: my + mh / 2 - 8, w: mw - 40, h: 16, size: 13, jh: "CENTER",
          font: "ARIALN", color: [0.42, 0.31, 0.2, 0.8], label: "Karte", lvl: 99 });
    }
    const file = path.join(SCREENS, `${name}.png`);
    screenshot(browser, tmp, bookHtml(items, w, h), w, h, file);
    console.log(`  ${path.relative(ROOT, file)}  (${items.length} Elemente, ganzes Buch)`);
    if (tab === "quests") vm.exec("NS.Journal.QuestsPage:ClosePopup()");
  }
  vm.lua(`return NS.Journal.Frame.showPage("reise")`);
}

// Notizzettel am Bildschirmrand (Z3, journal/TodoTracker.lua): beide Stile mit Probe-To-Dos (alle vier Arten, Fortschritt, Entfernung,
// ein gerade erledigtes durchgestrichen, mehr als acht offene -> "+n weitere"), je einmal vor hellem und dunklem Spielhintergrund.
export const TODO_PLANS_LUA = String.raw`
  local list = {}
  local function add(text, kind, extra)
    local p = { id = #list + 1, text = text, kind = kind, created = #list + 1 }
    for k, v in pairs(extra or {}) do p[k] = v end
    list[#list + 1] = p
  end
  add("Hasenpfoten sammeln", "item", { progress = "4/10", need = 10, have = 4 })
  add("Den Leuchtturm von Westfall besuchen", "place", { dist = 120 })
  add("Kobolde in der Jaspismine vertreiben", "kill", { progress = "7/12" })
  add("Rezept für Gewürzbrot lernen und gleich zwei Laibe für die Reise backen", "free")
  add("Greifenmeister in Eisenschmiede finden", "place", { dist = 1240 })
  add("Murloc-Späher am Ufer", "kill", { progress = "2/8" })
  add("Leinenstoff für Verbände", "item", { progress = "13/20" })
  add("Stufe 20 erreichen", "free")
  add("Die Höhle der Klagen erkunden", "free")
  add("Zusatzziel", "free")
  TODO_LIST = list
  NS.Plans = { list = function(f)
    local o, d = {}, {}
    for _, p in ipairs(list) do if p.done then d[#d + 1] = p else o[#o + 1] = p end end
    if f == "open" then return o elseif f == "done" then return d end
    for _, p in ipairs(d) do o[#o + 1] = p end
    return o
  end }
  return "ok"`;
export const TODO_SHOTS = [["todo-tracker-notizblock", "pad"], ["todo-tracker-schlicht", "plain"]];
const TODO_BACKDROPS = [
  "linear-gradient(160deg,#9db7c9 0%,#c9c2a4 55%,#8d9a63 100%)", // hell: Himmel, Sand, Wiese
  "linear-gradient(160deg,#1b2430 0%,#2b2a22 55%,#17201a 100%)", // dunkel: Nacht, Hoehle
];

function todoShots(browser, tmp, opts = { sizes: false, prefix: "todo-var" }) {
  const UIMOCK = readFileSync(path.join(ROOT, "tests", "fixtures", "ui-mock.lua"), "utf8");
  const vm = createVm({ setup: UIMOCK });
  vm.boot();
  vm.exec("UI.measureText = true; UI.measureWidth = true");
  vm.exec(TODO_PLANS_LUA);
  vm.exec("TODO_ALL = {} for i, p in ipairs(TODO_LIST) do TODO_ALL[i] = p end");
  vm.exec("NS.Journal.TodoTracker.set(\"shown\", true) NS.Journal.TodoTracker.refresh()"); // Standard: ausgeblendet
  // Zeilenhoehe naeher am Client: die Attrappe rechnet jede Schrift mit 0,55 x Groesse je Zeichen; Caveat ist deutlich schmaler
  vm.exec(String.raw`
    local function chars(t) t = tostring(t or "") return utf8.len(t) or #t end
    local function k(fs) local f = fs._font and tostring(fs._font[1] or ""):upper() or "" return f:find("CAVEAT", 1, true) and 0.40 or 0.52 end
    local function patch(fs)
      fs.SetSpacing = function(self, v) self._spacing = v end
      fs.GetStringWidth = function(self) return chars(self._text) * (self._font and self._font[2] or 12) * k(self) end
      fs.GetStringHeight = function(self)
        local size = self._font and self._font[2] or 12
        local lines = math.max(1, math.ceil(self:GetStringWidth() / math.max(1, self._w or 1)))
        return math.min(lines, self._maxLines or lines) * math.ceil(size * 1.2)
      end
    end
    for _, r in ipairs(NS.Journal.TodoTracker.state.rows) do patch(r.text) patch(r.extra) end
    patch(NS.Journal.TodoTracker.state.title) patch(NS.Journal.TodoTracker.state.count)
    NS.Journal.TodoTracker.state.sig = nil
    NS.Journal.TodoTracker.refresh()`);
  // ein To Do gerade erledigt: bleibt kurz durchgestrichen stehen
  vm.exec("TODO_LIST[3].done = 1; NS.Journal.TodoTracker.refresh()");
  vm.exec(PREVIEW_LUA + "\nreturn 'ok'");
  for (const [name, style] of TODO_SHOTS) todoShot(vm, browser, tmp, name, style, 1);
  // Schnellnotiz (Notizblock-Stil, teilt Textur und Aufteilung mit dem Notizzettel): Titel und Beispieltext
  vm.exec("local Q = NS.Journal.QuickNote Q.build() Q.state.frame:Show() Q.state.edit:SetText('Gewuerzbrot kaufen') Q.applyStyle()");
  for (const [name, style] of TODO_SHOTS) todoShot(vm, browser, tmp, name.replace("todo-tracker", "todo-schnellnotiz"), style, 2, "NS.Journal.QuickNote.state.frame");
  if (opts.sizes) {
    for (const [size, [fw, fh]] of Object.entries(TODO_SIZES)) {
      for (const n of [1, 8]) {
        vm.exec(`local TT = NS.Journal.TodoTracker
          for i = #TODO_LIST, 1, -1 do if i > ${n} then table.remove(TODO_LIST, i) end end
          for _, p in ipairs(TODO_ALL) do if p.id <= ${n} then p.done = nil; TODO_LIST[p.id] = p end end
          TT.state.prevOrder, TT.state.lingering, TT.state.sig = {}, {}, nil
          TT.set("size", { w = ${fw}, h = ${fh} }) TT.place() TT.refresh() TT.layout()`);
        for (const [, style] of TODO_SHOTS) {
          const label = style === "pad" ? "notizblock" : "schlicht";
          todoShot(vm, browser, tmp, `${opts.prefix}-${label}-${size}-${n}`, style, 2);
        }
      }
    }
  }
  const errs = vm.errors();
  if (errs.length) console.log(`  Lua-Fehler in der Attrappe:\n    ${errs.join("\n    ")}`);
}

// Groessen der Varianten (--groessen): klein nahe der Mindestgroesse, mittel = Standard, gross
const TODO_SIZES = { klein: [190, 170], mittel: [250, 250], gross: [400, 480] };

function todoShot(vm, browser, tmp, name, style, zoom, frame = "NS.Journal.TodoTracker.state.frame") {
  const caveat = pathToFileURL(path.join(MEDIA, "Fonts", "Caveat-Bold.ttf")).href;
  {
    vm.exec(`NS.Journal.TodoTracker.setStyle(${JSON.stringify(style)})`);
    if (frame.includes("QuickNote")) vm.exec("NS.Journal.QuickNote.applyStyle()");
    const [w, h] = vm.lua(`local f = ${frame} return { f:GetWidth(), f:GetHeight() }`);
    let items = vm.lua(`return KO_PREVIEW(${frame}, 0, 0, 1e12)`);
    items = Array.isArray(items) ? items : [];
    const sorted = items.filter((i) => i.kind === "tex" || i.kind === "text").map((it, i) => ({ it, i }))
      .sort((a, b) => (a.it.lvl ?? 0) - (b.it.lvl ?? 0) || (a.it.kind === "text") - (b.it.kind === "text") || a.i - b.i).map((e) => e.it);
    const PAD = 28, cw = w + 2 * PAD, ch = h + 2 * PAD;
    const cells = TODO_BACKDROPS.map((bg, k) => {
      // Inhalt auf das Fenster beschnitten (einzeilig gekuerzte Zeilen enden im Client mit "…", die Vorschau schneidet nur ab)
      const body = sorted.map((i) => itemHtml(null, i)).join("\n");
      return `<div style="position:absolute;left:${k * cw}px;top:0;width:${cw}px;height:${ch}px;background:${bg}"></div>
<div style="position:absolute;left:${k * cw + PAD}px;top:${PAD}px;width:${w}px;height:${h}px;overflow:hidden">${body}</div>`;
    }).join("\n");
    const html = `<!doctype html><html><head><meta charset="utf-8"><style>
@font-face{font-family:'Caveat';src:url('${caveat}');font-weight:700}
html,body{margin:0;padding:0;overflow:hidden}
#s{position:relative;width:${2 * cw}px;height:${ch}px;zoom:${zoom}}
</style></head><body><div id="s">${cells}</div></body></html>`;
    const file = path.join(SCREENS, `${name}.png`);
    screenshot(browser, tmp, html, 2 * cw * zoom, ch * zoom, file);
    console.log(`  ${path.relative(ROOT, file)}  (${sorted.length} Elemente, Stil ${style}, ${w} x ${h}${zoom > 1 ? `, ${zoom}x` : ""}, hell und dunkel)`);
  }
}

export function main(argv) {
  if (argv.includes("--help") || argv.includes("-h")) return console.log(HELP);
  const oi = argv.indexOf("--only");
  const only = oi >= 0 ? String(argv[oi + 1] || "").split(",").filter(Boolean) : TABS;
  if (!PREVIEW_LUA.includes("full = KO_FULL") || !PREVIEW_LUA.includes("ux = item.rect[1]") || !PREVIEW_LUA.includes("KO_BIG_MIN and") || !PREVIEW_LUA.includes("big = r[3]")) throw new Error("preview-book: Sammler passt nicht mehr zu tests/helpers/keepout.mjs");
  for (const id of only) if (!TABS.includes(id)) throw new Error(`Unbekannter Reiter: ${id} (${TABS.join(", ")})`);
  const marks = argv.includes("--sperren");
  const pi = argv.indexOf("--profil");
  const profil = pi >= 0 ? String(argv[pi + 1] || "") : "voll";
  if (!PROFILES[profil]) throw new Error(`Unbekanntes Profil: ${profil} (${Object.keys(PROFILES).join(", ")})`);
  const li = argv.indexOf("--lang");
  const lang = li >= 0 ? String(argv[li + 1] || "") : "de";
  if (!LANGS[lang]) throw new Error(`Unbekannte Sprache: ${lang} (${Object.keys(LANGS).join(", ")})`);
  const prefix = (lang === "de" ? "" : lang + "-") + PROFILES[profil];
  const browser = findBrowser();
  if (!browser) throw new Error("Kein Chrome/Edge gefunden. Pfad ueber die Umgebungsvariable CHROME_PATH angeben.");
  mkdirSync(SCREENS, { recursive: true });
  const tmp = mkdtempSync(path.join(os.tmpdir(), "even-preview-"));
  try {
    if (argv.includes("--todo")) {
      const pi2 = argv.indexOf("--praefix");
      const prefix = pi2 >= 0 ? String(argv[pi2 + 1] || "") : "todo-var";
      if (!/^[a-z0-9-]+$/.test(prefix)) throw new Error("--praefix: nur a-z, 0-9 und -");
      todoShots(browser, tmp, { sizes: argv.includes("--groessen"), prefix });
      return;
    }
    const vm = bootVm({ profil, lang });
    if (argv.includes("--buch")) {
      bookShots(vm, browser, tmp);
      const errs = vm.errors();
      if (errs.length) console.log(`  Lua-Fehler in der Attrappe:\n    ${errs.join("\n    ")}`);
      return;
    }
    const shots = [];
    const report = [];
    const shoot = (id, name, decor) => {
      let items = collect(vm);
      // Reise-Karte: die Kartenkunst kommt aus dem Spiel; ohne sie waeren die Zeichen nur Rauschen -> Platzhalter statt Inhalt
      const map = id === "reise" ? vm.lua("local M = NS.Journal.Frame.MAP return { M.x, M.y, M.w, M.h }") : null;
      if (map) {
        const [mx, my, mw, mh] = map;
        const inMap = (i) => i.x >= mx && i.y >= my && i.x + i.w <= mx + mw && i.y + i.h <= my + mh;
        items = items.filter((i) => !inMap(i));
        items.unshift({ kind: "tex", tex: "MAP", x: mx + 20, y: my + 20, w: mw - 40, h: mh - 40, label: "Karte" },
          { kind: "text", full: "Karte (Kunst aus dem Spiel)", x: mx + 20, y: my + mh / 2 - 8, w: mw - 40, h: 16, size: 13, jh: "CENTER",
            font: "ARIALN", color: [0.42, 0.31, 0.2, 0.8], label: "Karte" });
      }
      const paper = path.join(tmp, `paper_${id}.png`);
      if (!existsSync(paper)) {
        const img = renderSpreadRaw(browser, tmp, id);
        writeFileSync(paper, encodePng(img.w, img.h, img.rgba));
      }
      const file = path.join(SCREENS, `${prefix}-${name}.png`);
      screenshot(browser, tmp, spreadHtml(tmp, paper, items, marks ? decor : null), KEEPOUT.w, KEEPOUT.h, file);
      const img = decodePng(readFileSync(file));
      if (img.w !== KEEPOUT.w || img.h !== KEEPOUT.h) throw new Error(`${name}: Screenshot ${img.w}x${img.h}`);
      const content = items.filter((i) => i.kind !== "control" && !i.big);
      const hits = findOverlaps(content, decor, { minArea: 4 });
      report.push(`[keepout] ${name}: ${hits.length} Ueberlappungen\n${formatOverlaps(id, hits, 30)}`);
      console.log(`  ${path.relative(ROOT, file)}  (${items.length} Elemente, ${hits.length} Ueberlappungen mit Verzierungen)`);
      if (profil === "voll" && lang === "de" && N1_SHOTS[name]) {
        const copy = path.join(SCREENS, `${N1_SHOTS[name]}.png`);
        copyFileSync(file, copy);
        console.log(`  ${path.relative(ROOT, copy)}  (Kopie)`);
      }
      return file;
    };
    if (profil !== "voll") {
      // Leerzustaende (P2): jede Seite/Unterseite ausser Kampf und Ausruestungsfunde
      for (const id of only) {
        if (id === "kampf") continue;
        if (vm.lua(`return JF.showPage(${JSON.stringify(id)})`) !== true) throw new Error(`Seite ${id} laesst sich nicht zeigen`);
        const decor = keepoutFor(vm, id);
        for (const [tab, name, open, close] of EMPTY_VIEWS) {
          if (tab !== id) continue;
          if (open) vm.exec(open);
          shoot(id, name ? `${id}-${name}` : id, decor);
          if (close) vm.exec(close);
        }
      }
      const errs = vm.errors();
      if (errs.length) console.log(`  Lua-Fehler in der Attrappe:\n    ${errs.join("\n    ")}`);
      console.log(report.join("\n"));
      return;
    }
    for (const id of only) {
      if (id !== "reise" && vm.lua(`return JF.showPage(${JSON.stringify(id)})`) !== true) throw new Error(`Seite ${id} laesst sich nicht zeigen`);
      if (id === "reise") vm.lua(`return JF.showPage("reise")`);
      const decor = keepoutFor(vm, id);
      shots.push([id, shoot(id, id, decor)]);
      for (const [tab, name, open, close] of SUBVIEWS) {
        if (tab !== id) continue;
        vm.exec(typeof open === "function" ? open() : open);
        shoot(id, `${id}-${name}`, decor);
        vm.exec(close);
      }
    }
    const errs = vm.errors();
    if (errs.length) console.log(`  Lua-Fehler in der Attrappe:\n    ${errs.join("\n    ")}`);
    // Uebersicht 2 x 4 (nur bei allen Reitern)
    if (only.length === TABS.length) {
      const s = 0.5, gap = 16, lab = 22;
      const cw = Math.round(KEEPOUT.w * s), ch = Math.round(KEEPOUT.h * s);
      const rowsN = Math.ceil(shots.length / 2);
      const W = 2 * cw + 3 * gap, H = rowsN * (ch + lab) + (rowsN + 1) * gap;
      const cells = shots.map(([id, file], i) => {
        const col = i % 2, row = Math.floor(i / 2);
        const x = gap + col * (cw + gap), y = gap + row * (ch + lab + gap);
        return `<div style="position:absolute;left:${x}px;top:${y}px;font:600 15px Georgia,serif;color:#f1ddb8">${esc(TAB_LABEL[id] ?? id)}</div>
<img src="${pathToFileURL(file).href}" style="position:absolute;left:${x}px;top:${y + lab}px;width:${cw}px;height:${ch}px">`;
      }).join("\n");
      const file = path.join(SCREENS, "b2-uebersicht.png");
      screenshot(browser, tmp, `<!doctype html><html><body style="margin:0;background:#4d2b19;overflow:hidden"><div style="position:relative;width:${W}px;height:${H}px">${cells}</div></body></html>`, W, H, file);
      console.log(`  ${path.relative(ROOT, file)}  (Uebersicht 2 x ${rowsN})`);
    }
    console.log(report.join("\n"));
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    main(process.argv.slice(2));
  } catch (err) {
    console.error(`FEHLER: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  }
}
