// Erzeugt das Datenaddon EveN_ForeverChronicle_QuestData (Rubrik "Offene Quests"): Questliste mit Verfuegbarkeitsfeldern und
// Questgeber mit Kartenpunkten. Daten: QuestieDB (Questie-Team und Beitragende), nur lesend.
//
// Aufruf:  node scripts/build-quest-data.mjs [--questie <QuestieDB_Forever.toc>] [--forever <ordner>] [--corrections <QuestieDB-Ordner>]
//                                            [--out <ordner>] [--fetch] [--help]
//   --questie      QuestieDB im Forever-Stand ("baked" TOC, Vertragsversion 4). Standard (in dieser Reihenfolge): $CHRONICLE_QUESTIE_TOC,
//                  dann WOW_DIR (_classic_beta_, _forever_). Umgebungsvariablen koennen auch in der lokalen .env stehen.
//   --forever      Forever-Datenbank-Dump (Ordner mit zones.json, l10n\deDE\search.json, quest\*.json): Gebiet -> uiMapID, deDE-Namen, Questtyp.
//                  Standard: $CHRONICLE_FOREVER_DB. Beschaffung: README, Abschnitt "Questdaten neu erzeugen".
//   --corrections  QuestieDB-Addonordner mit src\corrections\ (fraktionsabhaengige Korrekturen Horde UND Allianz, Lua nur geparst).
//                  Standard: Ordner der TOC, sonst WOW_DIR\_forever_\..\QuestieDB, sonst WOW_DIR\_classic_beta_\..\QuestieDB;
//                  fehlt alles: fixes.json neben der TOC (nur Horde/neutral, aus der QuestieDB-Vorschau), sonst ohne Korrekturen (Warnung).
//   --overlays     Ordner mit den wago.tools-Tabellen UiMapXMapArt.csv, WorldMapOverlay.csv, WorldMapOverlayTile.csv (Forever-Build):
//                  alle Erkundungs-Overlays je Karte ("aufgedeckte" Zonenkarten). Standard: $CHRONICLE_OVERLAYS, sonst der mitgelieferte
//                  Schnappschuss scripts\data\wago-1.60.1.70170; fehlt der Ordner: Overlays.lua ohne Eintraege (Warnung).
//   --overlays-retail  dasselbe fuer den Retail-Build (Standard: $CHRONICLE_OVERLAYS_RETAIL, sonst scripts\data\wago-retail-12.1.5.70575)
//                  fuer die Retail-uiMapIDs aus journal\MapSpace.lua (ZONES); fehlt der Ordner: overlayRetail leer (Retail zeigt dann nur Erkundetes).
//   --out          Zielordner. Standard: addon\EveN_ForeverChronicle_QuestData (TOC wird mit erzeugt)
//   --fetch        vorher das Skript aus $CHRONICLE_FETCH_SCRIPT (--soft) als Kindprozess ausfuehren (kein eigener Netzcode); offline/ohne Skript ist kein Fehler
// Exit-Codes: 0 = ok, 1 = Fehler (Quelle fehlt/unlesbar, Vertragsversion != 4, Ergebnis unplausibel klein oder Datei zu gross, unbekannte Option)
//
// Ergebnis (reproduzierbar: sortiert, ohne Zeitstempel). Format verbindlich (Entwicklungsnotizen),
// Abschnitt "Datenformat (verbindlich)":
//   Quests.lua  EveNChronicleQuestData.quest  = je Quest "\n<id>\t<Name>\t<reqLvl>\t<qLvl>\t<races>\t<classes>\t<preAll>\t<preAny>\t<exclusive>\t<flags>\t<givers>"
//   Givers.lua  EveNChronicleQuestData.giver  = je Geber "\n<n|o><id>[A|H]\t<Name>\t<uiMapID>:<x>,<y>;...|<uiMapID>:..."
//   Names.lua   EveNChronicleQuestData.questEN / giverEN = "\n<id|Schluessel>\t<englischer Name>" (nur wo der Name oben deutsch ist);
//               questNoDE / giverNoDE = "<id|Schluessel>,..." (ohne deutschen Namen: der deutsche Client fragt seinen Cache)
//   Overlays.lua EveNChronicleQuestData.overlay = je Overlay "\n<uiMapID>\t<Breite>\t<Hoehe>\t<OffsetX>\t<OffsetY>\t<fileDataID>,..."
//               (Pixel der Kartenebene 1, Kacheln 256 zeilenweise)
//               EveNChronicleQuestData.overlayRetail = dasselbe Format fuer die Retail-Karten-IDs (nur Retail-Client)
//   EveN_ForeverChronicle_QuestData.toc (LoadOnDemand, Attribution, Stand)
//
// Sicherheit: reine Datenauswertung lokaler Dateien; Netz nur ueber ein optionales, selbst konfiguriertes Download-Skript
// (feste Argumente, kein Shell-String). Fremddaten mit Grenzen dekodiert (CBOR/zlib wie build-todo-data.mjs); Korrektur-Lua wird mit
// luaparse NUR geparst, nie ausgefuehrt, nur Literale ausgewertet (Groessenlimit je Datei, keine Symlinks). Namen gesaeubert (cleanName),
// Lua-Ausgabe als lange Klammer. Geschrieben wird nur in den Zielordner (atomar je Datei).

import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { closeSync, existsSync, lstatSync, openSync, readdirSync, readFileSync, readSync } from "node:fs";
import { mkdir, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import luaparse from "luaparse";
import { cleanName, configPath, defaultSources, luaLong, openQuestie } from "./build-todo-data.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const QUEST_DATA_ADDON = "EveN_ForeverChronicle_QuestData";
const DEFAULT_OUT = path.join(ROOT, "addon", QUEST_DATA_ADDON);
// wago.tools-Tabellen: Umgebung/.env, sonst der mitgelieferte Schnappschuss unter scripts/data (siehe scripts/data/README.md)
const DEFAULT_OVERLAYS = configPath("CHRONICLE_OVERLAYS") ?? path.join(ROOT, "scripts", "data", "wago-1.60.1.70170");
const DEFAULT_OVERLAYS_RETAIL = configPath("CHRONICLE_OVERLAYS_RETAIL") ?? path.join(ROOT, "scripts", "data", "wago-retail-12.1.5.70575");
const MAP_SPACE_FILE = path.join(ROOT, "addon", "EveN_ForeverChronicle", "journal", "MapSpace.lua");
export const OVERLAY_TILE = 256;
const MAX_CSV_BYTES = 4 * 1024 * 1024;
const MAIN_TOC = path.join(ROOT, "addon", "EveN_ForeverChronicle", "EveN_ForeverChronicle.toc");
const FETCH_TIMEOUT_MS = 240_000;

export const MAX_FILE_BYTES = 600 * 1024; // je Datei
export const MIN_QUESTS_WITH_GIVER = 3000;
export const MIN_GIVERS = 1000;
export const UNSURE_ABOVE = 30;
export const MAX_POINTS_PER_MAP = 4;
const MAX_LEVEL = 100;
const MAX_ID = 10_000_000;
const MAX_FIX_FILE_BYTES = 1024 * 1024;
const LICENSE_URL = "https://github.com/Questie/QuestieDB/blob/master/LICENSE.md";
const PLACEHOLDER = /\(Only GM|\bUNUSED\b|\bDEPRECATED\b|\bNYI\b|\bzzOLD|\[PH\]|^\[|^<.*>$/i;

// QuestieDB-Feldnummern (src/meta/questMeta.lua, npcMeta.lua, objectMeta.lua)
export const QF = Object.freeze({
  name: 1, startedBy: 2, requiredLevel: 4, questLevel: 5, requiredRaces: 6, requiredClasses: 7, preQuestGroup: 12, preQuestSingle: 13,
  exclusiveTo: 16, zoneOrSort: 17, requiredSkill: 18, requiredMinRep: 19, requiredMaxRep: 20, specialFlags: 24,
  breadcrumbForQuestId: 27, requiredSpell: 30, requiredMaxLevel: 32,
});
const NF = Object.freeze({ name: 1, spawns: 7 });
const OF = Object.freeze({ name: 1, spawns: 4 });
/** Feldname der Korrektur-Dateien -> Feldnummer (nur die Felder, die das Datenaddon braucht). */
const FIX_FIELDS = Object.freeze({
  quest: { startedBy: QF.startedBy, requiredLevel: QF.requiredLevel, questLevel: QF.questLevel, requiredRaces: QF.requiredRaces,
    requiredClasses: QF.requiredClasses, preQuestGroup: QF.preQuestGroup, preQuestSingle: QF.preQuestSingle, exclusiveTo: QF.exclusiveTo,
    zoneOrSort: QF.zoneOrSort, requiredSkill: QF.requiredSkill, requiredMinRep: QF.requiredMinRep, requiredMaxRep: QF.requiredMaxRep,
    specialFlags: QF.specialFlags, breadcrumbForQuestId: QF.breadcrumbForQuestId, requiredSpell: QF.requiredSpell, requiredMaxLevel: QF.requiredMaxLevel },
  npc: { spawns: NF.spawns },
  object: { spawns: OF.spawns },
});
/** Korrektur-Dateien (feste Namen, Forever vor legacy = Vorrang wie QuestieDB registry: ForeverDynamic > EraDynamic). */
export const FIX_FILES = Object.freeze([
  { rel: "src/corrections/Forever/foreverQuestFixes.lua", datatype: "quest" },
  { rel: "src/corrections/Forever/foreverNPCFixes.lua", datatype: "npc" },
  { rel: "src/corrections/Forever/foreverObjectFixes.lua", datatype: "object" },
  { rel: "src/corrections/Forever/legacy/classicQuestFixes.lua", datatype: "quest" },
  { rel: "src/corrections/Forever/legacy/classicNPCFixes.lua", datatype: "npc" },
  { rel: "src/corrections/Forever/legacy/classicObjectFixes.lua", datatype: "object" },
]);
const ENUM_FILES = Object.freeze([
  { rel: "src/corrections/enum/zones.lua", table: "zoneIDs" },
  { rel: "src/corrections/enum/factions.lua", table: "factionIDs" },
]);
const KEY_ALIAS = Object.freeze({ quest: "questKeys", npc: "npcKeys", object: "objectKeys" });
const DYNAMIC_FUNCTIONS = new Set(["LoadDynamic", "LoadFactionFixes"]);
/** Forever-DB-Questtypen, die als Gruppe/Dungeon/Raid/PvP/Event gelten */
const GROUP_TYPES = new Set(["Group", "Dungeon", "Raid", "PvP", "World Event"]);
/** Kategorien (negatives zoneOrSort) ausserhalb der Gruppe "event", die ebenfalls g bekommen: Battlegrounds, Epic, Legendary */
const GROUP_SORTS = new Set([-25, -1, -344]);
const ALLIANCE_RACES = 1 | 4 | 8 | 64;
const HORDE_RACES = 2 | 16 | 32 | 128;
const TWO32 = 4294967296;

const HELP = `EveN_ForeverChronicle: Datenaddon ${QUEST_DATA_ADDON} (offene Quests: Questliste + Questgeber) erzeugen

Aufruf:
  node scripts/build-quest-data.mjs [--questie <toc>] [--forever <ordner>] [--corrections <QuestieDB-Ordner>] [--out <ordner>] [--fetch]

Quellen (lokal; die Pfade koennen auch als Umgebungsvariablen bzw. in der lokalen .env stehen, siehe README "Questdaten neu erzeugen"):
  --questie      QuestieDB_Forever.toc (Standard: CHRONICLE_QUESTIE_TOC, sonst WOW_DIR aus Umgebung/.env)
  --forever      Forever-Datenbank-Dump (Standard: CHRONICLE_FOREVER_DB)
  --corrections  QuestieDB-Addonordner mit src\\corrections (Standard: neben der TOC, sonst WOW_DIR\\_forever_ bzw. _classic_beta_)
  --overlays     wago.tools-CSV-Ordner fuer die Karten-Overlays (Standard: CHRONICLE_OVERLAYS, sonst scripts\data\wago-1.60.1.70170)
  --overlays-retail  dasselbe fuer den Retail-Build (Standard: CHRONICLE_OVERLAYS_RETAIL, sonst scripts\data\wago-retail-12.1.5.70575)
  --out          Zielordner (Standard: addon\\${QUEST_DATA_ADDON})
  --fetch        vorher das Skript aus CHRONICLE_FETCH_SCRIPT mit --soft ausfuehren (optional; offline oder ohne Skript ist kein Fehler)
`;

// ---------------------------------------------------------------- Argumente / Pfade

export function parseArgs(argv) {
  const out = { help: false, fetch: false, questie: null, forever: null, corrections: null, out: null, overlays: null, "overlays-retail": null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--help" || a === "-h") out.help = true;
    else if (a === "--fetch") out.fetch = true;
    else if (a === "--questie" || a === "--forever" || a === "--out" || a === "--corrections" || a === "--overlays" || a === "--overlays-retail") {
      const v = argv[++i];
      if (!v || v.startsWith("--")) throw new Error(`Option ${a} braucht einen Pfad.`);
      if (v.includes("\0")) throw new Error(`Option ${a}: ungueltiger Pfad.`);
      out[a.slice(2)] = path.resolve(v);
    } else throw new Error(`Unbekannte Option bzw. unerwartetes Argument: ${a}\nHilfe: node scripts/build-quest-data.mjs --help`);
  }
  return out;
}

/** Kandidaten fuer den Korrektur-Ordner (QuestieDB-Addonordner) zur gewaehlten TOC */
export function correctionCandidates(questieToc) {
  const out = [path.dirname(questieToc)];
  for (const p of defaultSources().questie) {
    if (p.includes(`${path.sep}_forever_${path.sep}`)) out.push(path.dirname(p));
  }
  for (const p of defaultSources().questie) {
    if (p.includes(`${path.sep}_classic_beta_${path.sep}`)) out.push(path.dirname(p));
  }
  return [...new Set(out)];
}

const hasCorrections = (dir) => FIX_FILES.every((f) => isRealFile(path.join(dir, ...f.rel.split("/"))));

function isRealFile(file) {
  try {
    const st = lstatSync(file);
    return st.isFile() && !st.isSymbolicLink();
  } catch {
    return false;
  }
}

/** "## Version:" aus dem Kopf einer TOC (nur die ersten 8 KB) */
function tocVersion(file) {
  let fd;
  try {
    fd = openSync(file, "r");
    const buf = Buffer.alloc(8192);
    const n = readSync(fd, buf, 0, buf.length, 0);
    return cleanName(/^## Version:\s*(.+?)\s*$/m.exec(buf.toString("utf8", 0, n))?.[1]) || undefined;
  } catch {
    return undefined;
  } finally {
    if (fd !== undefined) closeSync(fd);
  }
}

// ---------------------------------------------------------------- Korrekturen (Lua nur geparst)

class NonLiteral extends Error {}

const numberOf = (node) => {
  if (node?.type === "NumericLiteral" && Number.isFinite(node.value)) return node.value;
  if (node?.type === "UnaryExpression" && node.operator === "-" && node.argument?.type === "NumericLiteral" && Number.isFinite(node.argument.value)) return -node.argument.value;
  return undefined;
};
const memberName = (node) =>
  node?.type === "MemberExpression" && node.indexer === "." && node.base?.type === "Identifier" && node.identifier?.type === "Identifier"
    ? { base: node.base.name, name: node.identifier.name }
    : undefined;
const latinToUtf8 = (s) => Buffer.from(s, "latin1").toString("utf8");

/** Literal auswerten (Zahl, Text, Wahrheitswert, nil, Enum-Bezug, Tabelle aus Literalen); sonst NonLiteral. Tabellen ohne Schluessel -> Array. */
export function literalValue(node, enums, depth = 0) {
  if (depth > 12) throw new NonLiteral("zu tief");
  const n = numberOf(node);
  if (n !== undefined) return n;
  switch (node?.type) {
    case "StringLiteral":
      return latinToUtf8(String(node.value ?? ""));
    case "BooleanLiteral":
      return node.value === true;
    case "NilLiteral":
      return null;
    case "MemberExpression": {
      const m = memberName(node);
      const t = m && Object.prototype.hasOwnProperty.call(enums, m.base) ? enums[m.base] : undefined;
      if (t && t.has(m.name)) return t.get(m.name);
      throw new NonLiteral("Bezug");
    }
    case "TableConstructorExpression": {
      const list = [];
      const keyed = Object.create(null);
      let hasKeys = false;
      for (const f of node.fields ?? []) {
        if (f.type === "TableValue") list.push(literalValue(f.value, enums, depth + 1));
        else if (f.type === "TableKeyString") {
          hasKeys = true;
          keyed[f.key.name] = literalValue(f.value, enums, depth + 1);
        } else if (f.type === "TableKey") {
          hasKeys = true;
          const k = literalValue(f.key, enums, depth + 1);
          if (typeof k !== "number" && typeof k !== "string") throw new NonLiteral("Schluessel");
          keyed[String(k)] = literalValue(f.value, enums, depth + 1);
        } else throw new NonLiteral("Tabellenfeld");
      }
      if (!hasKeys) return list;
      list.forEach((v, i) => {
        keyed[String(i + 1)] = v;
      });
      return keyed;
    }
    default:
      throw new NonLiteral(node?.type ?? "?");
  }
}

function parseLuaFile(file) {
  if (!isRealFile(file)) throw new Error(`Korrektur-Datei fehlt oder ist keine echte Datei: ${file}`);
  const buf = readFileSync(file);
  if (buf.length > MAX_FIX_FILE_BYTES) throw new Error(`Korrektur-Datei zu gross: ${file}`);
  return luaparse.parse(buf.toString("latin1"), { luaVersion: "5.1", comments: false, scope: false, locations: false, encodingMode: "pseudo-latin1" });
}

function parseEnum(file, table) {
  const out = new Map();
  if (!isRealFile(file)) return out;
  for (const st of parseLuaFile(file).body) {
    if (st.type !== "AssignmentStatement" || st.variables.length !== 1 || st.init.length !== 1) continue;
    const target = memberName(st.variables[0]);
    if (!target || target.name !== table || st.init[0].type !== "TableConstructorExpression") continue;
    for (const f of st.init[0].fields) {
      const v = f.type === "TableKeyString" ? numberOf(f.value) : undefined;
      if (v !== undefined && Number.isSafeInteger(v)) out.set(f.key.name, v);
    }
  }
  return out;
}

const emptyFixes = () => ({ quest: new Map(), npc: new Map(), object: new Map() });

/**
 * Liest die dynamischen (fraktionsabhaengigen) Korrekturen eines QuestieDB-Ordners. Ergebnis: { horde, alliance } je
 * { quest|npc|object: Map<id, Map<feldNr, wert>> } (fraktionsneutrale Tabellen in beiden). Erste Datei gewinnt je Feld (Forever vor legacy).
 */
export function readCorrections(dir) {
  const enums = Object.create(null);
  for (const e of ENUM_FILES) enums[e.table] = parseEnum(path.join(dir, ...e.rel.split("/")), e.table);
  const views = { horde: emptyFixes(), alliance: emptyFixes() };
  const counts = { horde: 0, alliance: 0, neutral: 0, nonLiteral: 0, ignoredFields: 0 };
  for (const { rel, datatype } of FIX_FILES) {
    const ast = parseLuaFile(path.join(dir, ...rel.split("/")));
    const alias = KEY_ALIAS[datatype];
    for (const st of ast.body) {
      if (st.type !== "FunctionDeclaration" || st.identifier?.type !== "MemberExpression" || !DYNAMIC_FUNCTIONS.has(st.identifier.identifier?.name)) continue;
      for (const inner of st.body) {
        let faction;
        let table;
        if (inner.type === "LocalStatement" && inner.variables.length === 1 && inner.init.length === 1 && inner.init[0].type === "TableConstructorExpression") {
          const name = inner.variables[0].name;
          faction = /Horde$/.test(name) ? "horde" : /Alliance$/.test(name) ? "alliance" : "neutral";
          table = inner.init[0];
        } else if (inner.type === "ReturnStatement" && inner.arguments.length === 1 && inner.arguments[0].type === "TableConstructorExpression") {
          faction = "neutral";
          table = inner.arguments[0];
        } else continue;
        for (const ent of table.fields) {
          const id = ent.type === "TableKey" ? numberOf(ent.key) : undefined;
          if (!Number.isSafeInteger(id) || id <= 0 || id > MAX_ID || ent.value?.type !== "TableConstructorExpression") continue;
          for (const fn of ent.value.fields) {
            const key = fn.type === "TableKey" ? memberName(fn.key) : undefined;
            const nr = key && key.base === alias ? FIX_FIELDS[datatype][key.name] : undefined;
            if (nr === undefined) {
              counts.ignoredFields++;
              continue;
            }
            let value;
            try {
              value = literalValue(fn.value, enums);
            } catch (err) {
              if (!(err instanceof NonLiteral)) throw err;
              counts.nonLiteral++;
              continue;
            }
            const targets = faction === "neutral" ? ["horde", "alliance"] : [faction];
            let used = false;
            for (const v of targets) {
              const rec = views[v][datatype].get(id) ?? new Map();
              if (rec.has(nr)) continue;
              rec.set(nr, value);
              views[v][datatype].set(id, rec);
              used = true;
            }
            if (used) counts[faction]++;
          }
        }
      }
    }
  }
  return { ...views, counts };
}

/** Rueckfall: fixes.json der QuestieDB-Vorschau (nur Horde/neutral, an die TOC gebunden) -> Horde-Sicht; Allianz ohne Korrekturen. */
export function readFixesJson(file, tocSha256) {
  const data = JSON.parse(readFileSync(file, "utf8"));
  if (data?.tocSha256 !== tocSha256) throw new Error("fixes.json gehoert zu einer anderen TOC");
  const horde = emptyFixes();
  let n = 0;
  for (const datatype of ["quest", "npc", "object"]) {
    for (const [idText, fields] of Object.entries(data?.[datatype] ?? {})) {
      const id = Number(idText);
      if (!Number.isSafeInteger(id) || id <= 0 || id > MAX_ID || !fields || typeof fields !== "object") continue;
      const rec = new Map();
      for (const [name, value] of Object.entries(fields)) {
        const nr = FIX_FIELDS[datatype][name];
        if (nr !== undefined) rec.set(nr, value);
      }
      if (rec.size) {
        horde[datatype].set(id, rec);
        n += rec.size;
      }
    }
  }
  return { horde, alliance: emptyFixes(), counts: { horde: n, alliance: 0, neutral: 0, nonLiteral: 0, ignoredFields: 0 } };
}

// ---------------------------------------------------------------- Forever-Datenbank (Zonen, Namen, Typ)

function readJson(file) {
  return JSON.parse(readFileSync(file, "utf8"));
}

const isObj = (v) => typeof v === "object" && v !== null && !Array.isArray(v);

/** areaId -> uiMapID (eigene uiMapId, sonst Eltern-Kette bis 8 Stufen), Instanzen erkannt */
export function createZoneResolver(zonesRaw) {
  const zones = new Map();
  for (const [key, value] of Object.entries(isObj(zonesRaw?.zones) ? zonesRaw.zones : {})) {
    const areaId = Number(key);
    if (!Number.isSafeInteger(areaId) || !isObj(value)) continue;
    zones.set(areaId, {
      uiMapId: Number.isSafeInteger(value.uiMapId) ? value.uiMapId : undefined,
      parent: Number.isSafeInteger(value.parent) ? value.parent : undefined,
      instance: value.instanceType === "dungeon" || value.instanceType === "raid" || value.instanceType === "battleground",
    });
  }
  const cache = new Map();
  const resolveMapId = (areaId) => {
    if (cache.has(areaId)) return cache.get(areaId);
    let cur = areaId;
    let result;
    for (let d = 0; d < 8 && cur !== undefined; d++) {
      const z = zones.get(cur);
      if (!z) break;
      if (z.uiMapId !== undefined) {
        result = z.uiMapId;
        break;
      }
      cur = z.parent;
    }
    cache.set(areaId, result);
    return result;
  };
  const sortGroups = isObj(zonesRaw?.sortGroups) ? zonesRaw.sortGroups : {};
  return {
    size: zones.size,
    resolveMapId,
    isInstance: (areaId) => zones.get(areaId)?.instance === true,
    sortGroup: (sort) => (typeof sortGroups[String(sort)] === "string" ? sortGroups[String(sort)] : undefined),
  };
}

/** Forever-Datenbank: Zonen, deDE-Namen (Quest/NPC/Objekt), Questtyp und "wiederholbar" aus den Quest-Splittern */
export function openForeverQuests(dir) {
  const zones = createZoneResolver(readJson(path.join(dir, "zones.json")));
  const deFile = path.join(dir, "l10n", "deDE", "search.json");
  const de = existsSync(deFile) ? readJson(deFile) : {};
  const type = new Map();
  const repeatable = new Set();
  const qdir = path.join(dir, "quest");
  if (existsSync(qdir)) {
    const files = readdirSync(qdir, { withFileTypes: true }).filter((e) => e.isFile() && /^\d+\.json$/.test(e.name)).map((e) => e.name).sort();
    for (const f of files) {
      for (const [k, q] of Object.entries(readJson(path.join(qdir, f)) ?? {})) {
        const id = Number(k);
        if (!Number.isSafeInteger(id) || !isObj(q)) continue;
        if (typeof q.type === "string") type.set(id, q.type);
        if (q.repeatable === true) repeatable.add(id);
      }
    }
  }
  const pick = (m, id) => (isObj(m) && typeof m[String(id)] === "string" ? m[String(id)] : undefined);
  return {
    zones,
    type,
    repeatable,
    deQuest: (id) => pick(de.quest, id),
    deNpc: (id) => pick(de.npc, id),
    deObject: (id) => pick(de.object, id),
  };
}

// ---------------------------------------------------------------- Zusammenfuehren

const asList = (v) => (Array.isArray(v) ? v : isObj(v) ? Object.keys(v).sort((a, b) => Number(a) - Number(b)).map((k) => v[k]) : []);
const int = (v) => (Number.isInteger(v) ? v : typeof v === "number" && Number.isFinite(v) ? Math.round(v) : undefined);
const idList = (v) => [...new Set(asList(v).map(int).filter((x) => Number.isSafeInteger(x) && x > 0 && x <= MAX_ID))].sort((a, b) => a - b);
const positive = (v) => {
  const n = int(v);
  return n !== undefined && n > 0;
};
const sameValue = (a, b) => JSON.stringify(a) === JSON.stringify(b);

/** Spawns {[areaId] = {{x,y},...}} -> Map uiMapID -> [[x,y], ...] (0..100, ohne Instanzen/unbekannte Gebiete) */
export function spawnsToMaps(spawns, zones, stats) {
  const out = new Map();
  if (!isObj(spawns) && !Array.isArray(spawns)) return out;
  const entries = Array.isArray(spawns) ? spawns.map((v, i) => [String(i + 1), v]) : Object.entries(spawns);
  for (const [areaText, pts] of entries) {
    const areaId = Number(areaText);
    if (!Number.isSafeInteger(areaId)) continue;
    if (zones.isInstance(areaId)) {
      if (stats) stats.instancePoints++;
      continue;
    }
    const mapId = zones.resolveMapId(areaId);
    if (mapId === undefined) {
      if (stats) stats.unmappedPoints++;
      continue;
    }
    for (const p of asList(pts)) {
      const xy = asList(p);
      const x = xy[0];
      const y = xy[1];
      if (typeof x !== "number" || typeof y !== "number" || !(x >= 0 && x <= 100) || !(y >= 0 && y <= 100)) continue;
      if (!out.has(mapId)) out.set(mapId, []);
      out.get(mapId).push([x, y]);
    }
  }
  return out;
}

/** Hoechstens max Punkte je Karte, deterministisch: auf 1 Nachkommastelle gerundet, ohne Doppelte, sortiert, dann Farthest-Point-Sampling. */
export function thinPoints(points, max = MAX_POINTS_PER_MAP) {
  const seen = new Set();
  const uniq = [];
  for (const [x, y] of points) {
    const p = [Math.round(x * 10) / 10, Math.round(y * 10) / 10];
    const k = `${p[0]},${p[1]}`;
    if (seen.has(k)) continue;
    seen.add(k);
    uniq.push(p);
  }
  uniq.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  if (uniq.length <= max) return uniq;
  const d2 = (a, b) => (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2;
  const chosen = [0];
  const minD = uniq.map((p) => d2(p, uniq[0]));
  while (chosen.length < max) {
    let best = -1;
    for (let i = 0; i < uniq.length; i++) if (best < 0 || minD[i] > minD[best]) best = i;
    chosen.push(best);
    for (let i = 0; i < uniq.length; i++) minD[i] = Math.min(minD[i], d2(uniq[i], uniq[best]));
  }
  return chosen.map((i) => uniq[i]).sort((a, b) => a[0] - b[0] || a[1] - b[1]);
}

/** Kartenpunkte als Text "<map>:<x>,<y>;...|<map>:..." (Karten aufsteigend, x/y mit 1 Nachkommastelle) */
export function formatLocations(maps) {
  return [...maps.keys()]
    .sort((a, b) => a - b)
    .map((m) => `${m}:${thinPoints(maps.get(m)).map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`).join(";")}`)
    .join("|");
}

/** Flags in fester Reihenfolge u r g s k */
export function flagString(f) {
  return (f.u ? "u" : "") + (f.r ? "r" : "") + (f.g ? "g" : "") + (f.s ? "s" : "") + (f.k ? "k" : "");
}

/** "Beta-Daten unsicher": requiredLevel > 30, ohne requiredLevel questLevel > 30 */
export function isUnsure(reqLvl, qLvl) {
  return reqLvl !== undefined ? reqLvl > UNSURE_ABOVE : qLvl !== undefined && qLvl > UNSURE_ABOVE;
}

/** Fraktionen zweier Rassenmasken zusammenlegen: je Seite die Bits der eigenen Fraktions-Sicht, obere Bits vereinigt. */
export function mergeRaceMasks(h, a) {
  if (h === undefined || a === undefined) return undefined; // eine Sicht ohne Einschraenkung -> keine Einschraenkung
  const lo = ((h % TWO32) & HORDE_RACES) | ((a % TWO32) & ALLIANCE_RACES) | ((h % TWO32) & ~255 & 0xffffffff) | ((a % TWO32) & ~255 & 0xffffffff);
  const hi = Math.floor(h / TWO32) | Math.floor(a / TWO32);
  return hi * TWO32 + (lo >>> 0);
}

/**
 * Baut Quest- und Geber-Liste. q = openQuestie(...), fdb = openForeverQuests(...), fixes = { horde, alliance } (Map je Datentyp).
 * Liefert { quests: [...], givers: Map key -> { name, loc }, stats }.
 */
export function buildQuestData(q, fdb, fixes) {
  const stats = { total: 0, skippedName: 0, withGiver: 0, instancePoints: 0, unmappedPoints: 0, de: 0, factionGiverQuests: 0, factionRaceQuests: 0, unsure: 0 };
  const views = ["horde", "alliance"];
  const fx = (view, kind, id, nr) => fixes[view]?.[kind]?.get(id);
  // Feld aus Sicht einer Fraktion: Korrektur vor TOC
  const get = (view, kind, id, nr) => {
    const rec = fx(view, kind, id);
    if (rec && rec.has(nr)) {
      const v = rec.get(nr);
      return v === null ? undefined : v;
    }
    const tocKind = kind === "quest" ? "Quest" : kind === "npc" ? "Npc" : "Object";
    return q.field(tocKind, id, nr);
  };

  // Geber: Standort je Fraktions-Sicht; gleich -> ein Schluessel ohne Endung, verschieden -> <key>A / <key>H
  const giverCache = new Map(); // "n123" -> { horde: locText, alliance: locText, name }
  const giverInfo = (t, id) => {
    const key = `${t}${id}`;
    if (giverCache.has(key)) return giverCache.get(key);
    const kind = t === "n" ? "npc" : "object";
    const field = t === "n" ? NF.spawns : OF.spawns;
    const loc = {};
    for (const v of views) loc[v] = formatLocations(spawnsToMaps(get(v, kind, id, field), fdb.zones, stats));
    const tocKind = t === "n" ? "Npc" : "Object";
    const en = cleanName(q.field(tocKind, id, t === "n" ? NF.name : OF.name));
    const de = cleanName(q.deDE(tocKind, id)) || cleanName(t === "n" ? fdb.deNpc(id) : fdb.deObject(id));
    const fallback = `${t === "n" ? "NPC" : "Objekt"} ${id}`;
    const info = { key, loc, name: de || en || fallback, en: en || de || fallback, hasDe: Boolean(de) };
    giverCache.set(key, info);
    return info;
  };
  const givers = new Map();
  const addGiver = (key, g, loc) => {
    if (!givers.has(key)) givers.set(key, { name: g.name, en: g.en, hasDe: g.hasDe, loc });
  };

  const quests = [];
  for (const id of q.ids("Quest")) {
    stats.total++;
    const en = cleanName(q.field("Quest", id, QF.name));
    if (!en || PLACEHOLDER.test(en)) {
      stats.skippedName++;
      continue;
    }
    const de = cleanName(q.deDE("Quest", id)) || cleanName(fdb.deQuest(id));
    if (de) stats.de++;
    const H = (nr) => get("horde", "quest", id, nr);
    const A = (nr) => get("alliance", "quest", id, nr);
    const lvl = (v) => {
      const n = int(v);
      return n !== undefined && n >= 1 && n <= MAX_LEVEL ? n : undefined;
    };
    const reqLvl = lvl(H(QF.requiredLevel));
    const qLvl = lvl(H(QF.questLevel));

    // Masken (Rassen ggf. je Fraktion verschieden)
    const maskOf = (v) => (typeof v === "number" && Number.isFinite(v) && v > 0 ? Math.round(v) : undefined);
    let races = maskOf(H(QF.requiredRaces));
    const racesA = maskOf(A(QF.requiredRaces));
    if (races !== racesA) {
      races = mergeRaceMasks(races, racesA);
      stats.factionRaceQuests++;
    }
    const classes = maskOf(H(QF.requiredClasses));

    const preAll = idList(H(QF.preQuestGroup));
    const preAny = idList(H(QF.preQuestSingle));
    const exclusive = [...new Set([...idList(H(QF.exclusiveTo)), ...idList([H(QF.breadcrumbForQuestId)])])].filter((x) => x !== id).sort((a, b) => a - b);

    // Flags (je Sicht, vereinigt)
    const f = { u: isUnsure(reqLvl, qLvl), r: false, g: false, s: false, k: false };
    for (const view of [H, A]) {
      const special = int(view(QF.specialFlags));
      if (special !== undefined && special % 2 === 1) f.r = true;
      const zs = int(view(QF.zoneOrSort));
      if (zs !== undefined && zs < 0) {
        f.k = true;
        if (fdb.zones.sortGroup(zs) === "event" || GROUP_SORTS.has(zs)) f.g = true;
      } else if (zs !== undefined && zs > 0 && fdb.zones.isInstance(zs)) f.g = true;
      if (idList(view(QF.requiredSkill)).length || asList(view(QF.requiredMinRep)).length || asList(view(QF.requiredMaxRep)).length ||
        positive(view(QF.requiredSpell)) || positive(view(QF.requiredMaxLevel))) f.s = true;
    }
    if (fdb.repeatable.has(id)) f.r = true;
    if (GROUP_TYPES.has(fdb.type.get(id))) f.g = true;
    if (f.u) stats.unsure++;

    // Geber je Sicht -> Schluessel
    const keysOf = (view) => {
      const sb = asList(get(view, "quest", id, QF.startedBy));
      const out = [];
      for (const [t, list] of [["n", sb[0]], ["o", sb[1]]]) {
        for (const gid of idList(list)) out.push(giverInfo(t, gid));
      }
      return out;
    };
    const perView = { horde: keysOf("horde"), alliance: keysOf("alliance") };
    const refs = new Map(); // key -> { name, loc }
    const inView = { horde: new Set(), alliance: new Set() };
    for (const v of views) {
      for (const g of perView[v]) if (g.loc[v]) inView[v].add(g.key);
    }
    const byKey = new Map([...perView.horde, ...perView.alliance].map((g) => [g.key, g]));
    let factionSpecific = false;
    for (const [key, g] of byKey) {
      const h = inView.horde.has(key);
      const a = inView.alliance.has(key);
      if (h && a && g.loc.horde === g.loc.alliance) refs.set(key, { g, loc: g.loc.horde });
      else {
        if (h) refs.set(`${key}H`, { g, loc: g.loc.horde });
        if (a) refs.set(`${key}A`, { g, loc: g.loc.alliance });
        if (h || a) factionSpecific = true;
      }
    }
    if (factionSpecific) stats.factionGiverQuests++;
    const giverKeys = [...refs.keys()].sort();
    for (const k of giverKeys) addGiver(k, refs.get(k).g, refs.get(k).loc);
    if (giverKeys.length) stats.withGiver++;

    quests.push({ id, name: de || en, en, hasDe: Boolean(de), reqLvl, qLvl, races, classes, preAll, preAny, exclusive, flags: flagString(f), givers: giverKeys });
  }
  quests.sort((a, b) => a.id - b.id);
  return { quests, givers, stats };
}

// ---------------------------------------------------------------- Ausgabe

const opt = (v) => (v === undefined ? "" : String(v));

export function questBlob(list) {
  return (
    list
      .map((r) => `\n${r.id}\t${r.name}\t${opt(r.reqLvl)}\t${opt(r.qLvl)}\t${opt(r.races)}\t${opt(r.classes)}\t${r.preAll.join(",")}\t${r.preAny.join(",")}\t${r.exclusive.join(",")}\t${r.flags}\t${r.givers.join(",")}`)
      .join("") + "\n"
  );
}

export function giverBlob(givers) {
  const keys = [...givers.keys()].sort();
  return keys.map((k) => `\n${k}\t${givers.get(k).name}\t${givers.get(k).loc}`).join("") + "\n";
}

/** Englische Namen (nur wo der Hauptname deutsch ist und abweicht): "\n<id|Schluessel>\t<Name>" */
export function enBlob(rows) {
  return rows.filter((r) => r.hasDe && r.en && r.en !== r.name).map((r) => `\n${r.key}\t${r.en}`).join("") + "\n";
}

/** Schluessel ohne deutschen Namen, kommagetrennt (Reihenfolge der Eingabe) */
export function noDeList(rows) {
  return rows.filter((r) => !r.hasDe).map((r) => r.key).join(",");
}

// ---------------------------------------------------------------- Karten-Overlays (aufgedeckte Zonenkarten)

/** Minimaler CSV-Leser (wago.tools: Kopfzeile; Anfuehrungszeichen werden respektiert) -> [{ Spalte: Text }] */
export function parseCsv(text) {
  const rows = [];
  for (const line of text.split(/\r?\n/)) {
    if (line === "") continue;
    const cells = [];
    let cur = "";
    let quoted = false;
    for (let i = 0; i < line.length; i++) {
      const c = line[i];
      if (quoted) {
        if (c === '"' && line[i + 1] === '"') {
          cur += '"';
          i++;
        } else if (c === '"') quoted = false;
        else cur += c;
      } else if (c === '"') quoted = true;
      else if (c === ",") {
        cells.push(cur);
        cur = "";
      } else cur += c;
    }
    cells.push(cur);
    rows.push(cells);
  }
  const head = rows.shift() ?? [];
  return rows.map((r) => Object.fromEntries(head.map((h, i) => [h, r[i]])));
}

function readCsv(dir, name) {
  const file = path.join(dir, `${name}.csv`);
  if (!isRealFile(file)) throw new Error(`${name}.csv fehlt oder ist keine echte Datei (${dir})`);
  const buf = readFileSync(file);
  if (buf.length > MAX_CSV_BYTES) throw new Error(`${name}.csv zu gross`);
  return parseCsv(buf.toString("utf8"));
}

const csvInt = (row, col) => {
  const text = row[col];
  if (typeof text !== "string" || !/^-?\d+$/.test(text)) return undefined;
  const n = Number(text);
  return Number.isSafeInteger(n) ? n : undefined;
};

/**
 * Alle Erkundungs-Overlays der Karten mapIds aus den wago.tools-Tabellen (UiMapXMapArt PhaseID 0 -> WorldMapOverlay ->
 * WorldMapOverlayTile, Ebene 0). Overlays mit unvollstaendigen Kacheln oder unplausiblen Massen werden verworfen (gezaehlt).
 * -> { list: [{ id, map, w, h, x, y, files: [fileDataID, ...] }], skipped, maps }
 */
export function readOverlays(dir, mapIds) {
  const want = new Set(mapIds);
  const artOf = new Map();
  for (const r of readCsv(dir, "UiMapXMapArt")) {
    const map = csvInt(r, "UiMapID");
    const art = csvInt(r, "UiMapArtID");
    if (csvInt(r, "PhaseID") === 0 && map !== undefined && art !== undefined && want.has(map) && !artOf.has(map)) artOf.set(map, art);
  }
  const mapOfArt = new Map([...artOf].map(([m, a]) => [a, m]));
  const tiles = new Map();
  for (const r of readCsv(dir, "WorldMapOverlayTile")) {
    const oid = csvInt(r, "WorldMapOverlayID");
    const fid = csvInt(r, "FileDataID");
    const row = csvInt(r, "RowIndex");
    const col = csvInt(r, "ColIndex");
    if (oid === undefined || fid === undefined || fid <= 0 || row === undefined || col === undefined || csvInt(r, "LayerIndex") !== 0) continue;
    if (!tiles.has(oid)) tiles.set(oid, new Map());
    tiles.get(oid).set(`${row}:${col}`, fid);
  }
  const list = [];
  let skipped = 0;
  for (const r of readCsv(dir, "WorldMapOverlay")) {
    const id = csvInt(r, "ID");
    const map = mapOfArt.get(csvInt(r, "UiMapArtID"));
    if (id === undefined || map === undefined) continue;
    const w = csvInt(r, "TextureWidth");
    const h = csvInt(r, "TextureHeight");
    const x = csvInt(r, "OffsetX");
    const y = csvInt(r, "OffsetY");
    if (!(w > 0 && h > 0 && w <= 4096 && h <= 4096 && x >= 0 && y >= 0 && x <= 4096 && y <= 4096)) {
      skipped++;
      continue;
    }
    const cols = Math.ceil(w / OVERLAY_TILE);
    const rows = Math.ceil(h / OVERLAY_TILE);
    const t = tiles.get(id);
    const files = [];
    for (let j = 0; j < rows && t; j++) for (let k = 0; k < cols; k++) if (t.has(`${j}:${k}`)) files.push(t.get(`${j}:${k}`));
    if (files.length !== rows * cols) {
      skipped++;
      continue;
    }
    list.push({ id, map, w, h, x, y, files });
  }
  list.sort((a, b) => a.map - b.map || a.id - b.id);
  return { list, skipped, maps: new Set(list.map((o) => o.map)).size };
}

export function overlayBlob(list) {
  return list.map((o) => `\n${o.map}\t${o.w}\t${o.h}\t${o.x}\t${o.y}\t${o.files.join(",")}`).join("") + "\n";
}

/** Retail-uiMapIDs aus MapSpace.lua (ZONES: Kandidaten-Karten aller Zonen/Kontinente), aufsteigend */
export function retailMapIds(file = MAP_SPACE_FILE) {
  const ids = new Set();
  for (const line of readFileSync(file, "utf8").split(/\r?\n/)) {
    if (!/^\s*\[\d+\] = \{ c = /.test(line)) continue;
    for (const m of line.matchAll(/\{\s*(\d+)\s*[,}]/g)) ids.add(Number(m[1]));
  }
  return [...ids].sort((a, b) => a - b);
}

/** Karten-IDs aller Geber-Punkte (aufsteigend) */
export function giverMapIds(givers) {
  const ids = new Set();
  for (const g of givers.values()) {
    for (const part of String(g.loc ?? "").split("|")) {
      const m = Number(part.split(":")[0]);
      if (Number.isSafeInteger(m) && m > 0) ids.add(m);
    }
  }
  return [...ids].sort((a, b) => a - b);
}

function luaQuote(s) {
  return '"' + s.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
}

const ATTRIBUTION = (version) =>
  `Daten: QuestieDB (Questie-Team und Beitragende: Muehe, TheCrux/BreakBB, Drejjmit, Dyaxler, Cheeq, TechnoHunter, Yttrium und alle weiteren), Stand ${version}. ` +
  "Lizenz: GPL-3.0 (QuestieDB LICENSE.md: Weitergabe unter GPLv3; siehe LICENSE und LICENSE-NOTE.md); umformatiert und ergaenzt durch scripts/build-quest-data.mjs. Spielwelt-Inhalte (c) Blizzard Entertainment.";

const ATTRIBUTION_EN = (version) =>
  `Data: QuestieDB (Questie team and contributors: Muehe, TheCrux/BreakBB, Drejjmit, Dyaxler, Cheeq, TechnoHunter, Yttrium and all others), version ${version}. ` +
  "License: GPL-3.0 (QuestieDB LICENSE.md: redistribution under GPLv3; see LICENSE and LICENSE-NOTE.md); reformatted and extended by scripts/build-quest-data.mjs. Game world content (c) Blizzard Entertainment.";

const HEAD = (what, version, info) =>
  `-- ${QUEST_DATA_ADDON}: ${what}. GENERATED by scripts/build-quest-data.mjs, do not edit by hand.\n` +
  `-- ${ATTRIBUTION_EN(version)}\n` +
  `-- License: GPL-3.0 (see LICENSE and LICENSE-NOTE.md); status of the source: ${LICENSE_URL}\n` +
  `-- Sources: ${info}\n` +
  "-- Loaded on demand only (LoadOnDemand) by journal/model/OpenQuests.lua of the main addon; format: see the open-quests data format in the development notes.\n" +
  "EveNChronicleQuestData = EveNChronicleQuestData or {}\n";

export function tocText(version, iface) {
  return [
    `## Interface: ${iface}`,
    "## Title: EveN Forever Chronicle - Quest data",
    "## Title-deDE: EveN Forever Chronicle - Questdaten",
    "## Notes: Open quests and quest givers for EveN Forever Chronicle (data: QuestieDB). Loaded on demand only.",
    "## Notes-deDE: Offene Quests und Questgeber für EveN Forever Chronicle (Daten: QuestieDB). Wird nur bei Bedarf geladen.",
    "## Author: EveN",
    "## Version: @project-version@",
    "## LoadOnDemand: 1",
    "## Dependencies: EveN_ForeverChronicle",
    `## X-QuestieDB-Version: ${version}`,
    `## X-Attribution: ${ATTRIBUTION(version)}`,
    "## X-License: GPL-3.0",
    `## X-Source-License: ${LICENSE_URL}`,
    "",
    "Quests.lua",
    "Givers.lua",
    "Names.lua",
    "Overlays.lua",
    "",
  ].join("\n");
}

async function writeAtomic(file, text) {
  const tmp = `${file}.tmp`;
  await writeFile(tmp, text, "utf8");
  await rename(tmp, file);
}

const sha256 = (text) => createHash("sha256").update(text).digest("hex");

/** Anzahl abweichender Feldwerte zweier Korrektur-Sichten ({ quest|npc|object: Map<id, Map<nr, wert>> }) */
export function compareFixes(a, b) {
  let diff = 0;
  for (const dt of ["quest", "npc", "object"]) {
    const keys = new Set();
    for (const [id, rec] of a[dt]) for (const nr of rec.keys()) keys.add(`${id}:${nr}`);
    for (const [id, rec] of b[dt]) for (const nr of rec.keys()) keys.add(`${id}:${nr}`);
    for (const k of keys) {
      const [id, nr] = k.split(":").map(Number);
      if (!sameValue(a[dt].get(id)?.get(nr), b[dt].get(id)?.get(nr))) diff++;
    }
  }
  return diff;
}

/** Korrekturen laden: Ordner (Horde+Allianz) vor fixes.json (nur Horde) vor nichts. */
export function loadCorrections({ questie, corrections, tocSha }) {
  const fixesJson = path.join(path.dirname(questie), "..", "..", "..", "fixes.json");
  const dirs = corrections ? [corrections] : correctionCandidates(questie);
  for (const dir of dirs) {
    if (!hasCorrections(dir)) {
      if (corrections) throw new Error(`Im Korrektur-Ordner fehlen Dateien (${FIX_FILES.map((f) => f.rel).join(", ")}): ${corrections}`);
      continue;
    }
    const fixes = readCorrections(dir);
    // Abgleich: Horde-Sicht muss zur fixes.json der Preview passen (gleiche Korrekturen trotz evtl. anderer Ordner-Version)
    let check = "kein fixes.json zum Abgleich";
    if (existsSync(fixesJson)) {
      try {
        const diff = compareFixes(fixes.horde, readFixesJson(fixesJson, tocSha).horde);
        check = diff === 0 ? "Horde-Sicht = fixes.json der TOC" : `WARNUNG: ${diff} Abweichungen zur fixes.json der TOC (Korrektur-Ordner hat anderen Stand)`;
      } catch (err) {
        check = `fixes.json nicht vergleichbar (${err.message})`;
      }
    }
    return { fixes, factions: "horde+alliance", check, source: `${dir} (QuestieDB ${tocVersion(path.join(dir, "QuestieDB_Forever.toc")) ?? "?"})` };
  }
  if (existsSync(fixesJson)) {
    try {
      return { fixes: readFixesJson(fixesJson, tocSha), factions: "horde", source: `${fixesJson} (nur Horde/neutral)` };
    } catch (err) {
      return { fixes: { horde: emptyFixes(), alliance: emptyFixes(), counts: {} }, factions: "none", source: `keine (${err.message})` };
    }
  }
  return { fixes: { horde: emptyFixes(), alliance: emptyFixes(), counts: {} }, factions: "none", source: "keine gefunden" };
}

/** limits (nur fuer Tests mit Mini-Daten): { minQuests, minGivers, maxFileBytes } */
export async function build({ questie, forever, corrections = null, overlays = DEFAULT_OVERLAYS, overlaysRetail = DEFAULT_OVERLAYS_RETAIL, mapSpaceFile = MAP_SPACE_FILE, out, limits = {} }) {
  const minQuests = limits.minQuests ?? MIN_QUESTS_WITH_GIVER;
  const minGivers = limits.minGivers ?? MIN_GIVERS;
  const maxBytes = limits.maxFileBytes ?? MAX_FILE_BYTES;
  const tocRaw = readFileSync(questie, "utf8");
  const q = openQuestie(tocRaw);
  const fdb = openForeverQuests(forever);
  const corr = loadCorrections({ questie, corrections, tocSha: sha256(tocRaw) });
  const data = buildQuestData(q, fdb, corr.fixes);
  const version = cleanName(q.version);
  const info = `QuestieDB ${version}; faction corrections ${corr.factions}; Forever database (data.morthen.net, zones/deDE/type)`;
  const withGiver = data.quests.filter((r) => r.givers.length).length;
  const questText =
    HEAD("quest list", version, info) +
    `-- Quests: ${data.quests.length}, with giver location: ${withGiver}, with German name: ${data.stats.de}, beta data unsure: ${data.stats.unsure}\n` +
    `EveNChronicleQuestData.version = ${luaQuote(version)}\n` +
    `EveNChronicleQuestData.factions = ${luaQuote(corr.factions)}\n` +
    `EveNChronicleQuestData.quest = ${luaLong(questBlob(data.quests))}\n`;
  const giverText =
    HEAD("quest givers with map points", version, info) +
    `-- Givers: ${data.givers.size}\n` +
    `EveNChronicleQuestData.giver = ${luaLong(giverBlob(data.givers))}\n`;
  const qRows = data.quests.map((r) => ({ key: String(r.id), name: r.name, en: r.en, hasDe: r.hasDe }));
  const gRows = [...data.givers.keys()].sort().map((k) => ({ key: k, ...data.givers.get(k) }));
  const nEn = (rows) => rows.filter((r) => r.hasDe && r.en && r.en !== r.name).length;
  const nNoDe = (rows) => rows.filter((r) => !r.hasDe).length;
  const namesText =
    HEAD("English names and names without a German translation", version, info) +
    `-- English names: quests ${nEn(qRows)}, givers ${nEn(gRows)}; without German name: quests ${nNoDe(qRows)}, givers ${nNoDe(gRows)}\n` +
    `EveNChronicleQuestData.questEN = ${luaLong(enBlob(qRows))}\n` +
    `EveNChronicleQuestData.giverEN = ${luaLong(enBlob(gRows))}\n` +
    `EveNChronicleQuestData.questNoDE = ${luaQuote(noDeList(qRows))}\n` +
    `EveNChronicleQuestData.giverNoDE = ${luaQuote(noDeList(gRows))}\n`;
  let ov = { list: [], skipped: 0, maps: 0, source: "keine" };
  if (overlays && existsSync(overlays)) ov = { ...readOverlays(overlays, giverMapIds(data.givers)), source: overlays };
  let ovR = { list: [], skipped: 0, maps: 0, source: "keine" };
  if (overlaysRetail && existsSync(overlaysRetail)) ovR = { ...readOverlays(overlaysRetail, retailMapIds(mapSpaceFile)), source: overlaysRetail };
  const overlayText =
    `-- ${QUEST_DATA_ADDON}: all exploration overlays per map (uncovered zone maps). GENERATED by scripts/build-quest-data.mjs, do not edit by hand.\n` +
    "-- License: GPL-3.0 (see LICENSE and LICENSE-NOTE.md); numbers from the client tables of the game, (c) Blizzard Entertainment.\n" +
    `-- Source: wago.tools UiMapXMapArt/WorldMapOverlay/WorldMapOverlayTile (${ov.source === "keine" ? "none" : path.basename(ov.source)}); integers only.\n` +
    "-- overlay = per overlay \"\\n<uiMapID>\\t<width>\\t<height>\\t<offsetX>\\t<offsetY>\\t<fileDataID>,...\" (pixels of art layer 1, 256 tiles row by row)\n" +
    "EveNChronicleQuestData = EveNChronicleQuestData or {}\n" +
    `-- Overlays: ${ov.list.length} on ${ov.maps} maps\n` +
    `EveNChronicleQuestData.overlay = ${luaLong(overlayBlob(ov.list))}\n` +
    `-- Retail overlays (${ovR.source === "keine" ? "none" : path.basename(ovR.source)}): ${ovR.list.length} on ${ovR.maps} maps; same format, Retail uiMapIDs (Retail client only)\n` +
    `EveNChronicleQuestData.overlayRetail = ${luaLong(overlayBlob(ovR.list))}\n`;
  const iface = /^## Interface:[ \t]*(.+?)[ \t]*$/m.exec(readFileSync(MAIN_TOC, "utf8"))?.[1] ?? "16001";
  const toc = tocText(version, iface);
  const sizes = { quest: Buffer.byteLength(questText), giver: Buffer.byteLength(giverText), names: Buffer.byteLength(namesText),
    overlay: Buffer.byteLength(overlayText) };
  if (Object.values(sizes).some((n) => n > maxBytes)) {
    throw new Error(`Datei zu gross (Quests.lua ${sizes.quest} B, Givers.lua ${sizes.giver} B, Names.lua ${sizes.names} B, Overlays.lua ${sizes.overlay} B; Grenze ${maxBytes} B)`);
  }
  if (withGiver < minQuests || data.givers.size < minGivers) {
    throw new Error(`Ergebnis unplausibel klein (Quests mit Geber ${withGiver}, Geber ${data.givers.size})`);
  }
  await mkdir(out, { recursive: true });
  await writeAtomic(path.join(out, "Quests.lua"), questText);
  await writeAtomic(path.join(out, "Givers.lua"), giverText);
  await writeAtomic(path.join(out, "Names.lua"), namesText);
  await writeAtomic(path.join(out, "Overlays.lua"), overlayText);
  await writeAtomic(path.join(out, `${QUEST_DATA_ADDON}.toc`), toc);
  return { ...data, withGiver, sizes, questieVersion: version, corrections: corr, badValues: q.stats.badValues, overlays: ov, overlaysRetail: ovR };
}

/** --fetch: optionales Download-Skript (CHRONICLE_FETCH_SCRIPT) als Kindprozess (feste Argumente, keine Shell). Fehler/offline/nicht konfiguriert = Hinweis, kein Abbruch. */
export function runFetch({ script = configPath("CHRONICLE_FETCH_SCRIPT"), spawn = spawnSync } = {}) {
  if (!script) return { ok: false, reason: "kein Download-Skript konfiguriert (CHRONICLE_FETCH_SCRIPT); vorhandener Stand wird benutzt." };
  if (!isRealFile(script)) return { ok: false, reason: `Download-Skript nicht gefunden (${script}); vorhandener Stand wird benutzt.` };
  const r = spawn(process.execPath, [script, "--soft"], { cwd: path.resolve(path.dirname(script), ".."), stdio: "inherit", shell: false, timeout: FETCH_TIMEOUT_MS, windowsHide: true });
  if (r.error) return { ok: false, reason: `Download-Skript nicht ausfuehrbar (${r.error.message}); vorhandener Stand wird benutzt.` };
  if (r.status !== 0) return { ok: false, reason: `Download-Skript endete mit ${r.status ?? r.signal}; vorhandener Stand wird benutzt.` };
  return { ok: true };
}

export async function main(argv) {
  const opts = parseArgs(argv);
  if (opts.help) {
    console.log(HELP);
    return null;
  }
  if (opts.fetch) {
    const f = runFetch();
    if (!f.ok) console.log(`Hinweis: ${f.reason}`);
  }
  const def = defaultSources();
  const questie = opts.questie ?? def.questie.find((p) => existsSync(p));
  if (!questie || !existsSync(questie)) {
    throw new Error(`QuestieDB_Forever.toc nicht gefunden (gesucht: ${opts.questie ?? (def.questie.join(", ") || "nichts konfiguriert")}). Pfad mit --questie angeben oder CHRONICLE_QUESTIE_TOC bzw. WOW_DIR setzen (README, Abschnitt "Questdaten neu erzeugen").`);
  }
  const forever = opts.forever ?? def.forever;
  if (!forever || !existsSync(path.join(forever, "zones.json"))) {
    throw new Error(`Forever-Datenbank nicht gefunden (${forever ?? "nicht konfiguriert"}). Dump-Ordner mit zones.json mit --forever angeben oder CHRONICLE_FOREVER_DB setzen (README, Abschnitt "Questdaten neu erzeugen").`);
  }
  const out = opts.out ?? DEFAULT_OUT;
  const overlays = opts.overlays ?? DEFAULT_OVERLAYS;
  const overlaysRetail = opts["overlays-retail"] ?? DEFAULT_OVERLAYS_RETAIL;
  if (!existsSync(overlaysRetail)) console.log(`WARNUNG: Retail-Overlay-Tabellen nicht gefunden (${overlaysRetail}) - Retail zeigt nur Erkundetes.`);
  if (!existsSync(overlays)) console.log(`WARNUNG: Overlay-Tabellen nicht gefunden (${overlays}) - Zonenkarten zeigen nur Erkundetes.`);
  const r = await build({ questie, forever, corrections: opts.corrections, overlays, overlaysRetail, out });
  const s = r.stats;
  console.log(`QuestieDB ${r.questieVersion}: ${questie}`);
  console.log(`Fraktionskorrekturen (${r.corrections.factions}): ${r.corrections.source}; ${JSON.stringify(r.corrections.fixes.counts)}`);
  if (r.corrections.check) console.log(`Abgleich: ${r.corrections.check}`);
  if (r.corrections.factions !== "horde+alliance") console.log("WARNUNG: Allianz-Korrekturen fehlen - Geber fuer Allianz-Charaktere koennen teils falsch sein.");
  console.log(`Forever-Datenbank: ${forever}`);
  console.log(`Quests: ${r.quests.length} (mit Geber-Ort ${r.withGiver}, deDE ${s.de}, unsicher >${UNSURE_ABOVE}: ${s.unsure}, Platzhalter verworfen ${s.skippedName})`);
  console.log(`Fraktionsabhaengig: Geber bei ${s.factionGiverQuests} Quests, Rassenmaske bei ${s.factionRaceQuests} Quests`);
  console.log(`Geber: ${r.givers.size}; Punkte verworfen: Instanz ${s.instancePoints}, ohne Karte ${s.unmappedPoints}`);
  console.log(`Overlays: ${r.overlays.list.length} auf ${r.overlays.maps} Karten (verworfen ${r.overlays.skipped}); Quelle ${r.overlays.source}`);
  console.log(`Retail-Overlays: ${r.overlaysRetail.list.length} auf ${r.overlaysRetail.maps} Karten (verworfen ${r.overlaysRetail.skipped}); Quelle ${r.overlaysRetail.source}`);
  console.log(`Dateigroessen: Quests.lua ${r.sizes.quest} B, Givers.lua ${r.sizes.giver} B, Names.lua ${r.sizes.names} B, Overlays.lua ${r.sizes.overlay} B`);
  if (r.badValues) console.log(`Hinweis: ${r.badValues} QuestieDB-Werte nicht dekodierbar (als fehlend behandelt).`);
  console.log(`Ziel: ${out}`);
  return r;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).catch((err) => {
    console.error(`FEHLER: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  });
}
