// Kopie aus forever-routen/scripts/lib/questie-fixes.mjs (Stand 2026-11-03); einzige Aenderung: FIXES_SCHEMA ist hier definiert statt aus questie-source importiert.
// Eigenstaendig kopiert, damit dieses Projekt nicht von forever-routen abhaengt. Genutzt von scripts/fetch-questiedb-release.mjs.
// Fraktionsabhaengige QuestieDB-Laufzeitkorrekturen lesen (Delta Datensammler, E2b, Orchestrator-Ergaenzung zu F4).
//
// Warum: Die baked-TOC enthaelt nur die STATISCHEN Korrekturen (die Lua-Dateien des Archivs tragen dort nur noch "return {}").
// Die DYNAMISCHEN Korrekturen (Horde/Allianz, z. B. Geber 211022 statt 211033 fuer die Bibliotheks-Quests) wendet das Addon erst zur
// Laufzeit an; gemessen an 1.0.6-dev.e9a67d1 stehen sie NICHT in der TOC (die TOC hat bei Quest 97286 beide Geber, Npc 5676 hat keine
// Spawns, Item 3713 keine Drops).
//
// Was gelesen wird: genau die Archiv-Eintraege aus FIX_ENTRIES/ENUM_ENTRIES (exakte Namen, fest im Code, siehe fetch-questiedb-release).
// Ausgewertet werden nur die Funktionen LoadDynamic/LoadFactionFixes, darin die lokalen Tabellen, deren Name auf "Horde" endet, und
// direkt zurueckgegebene Tabellen (fraktionsneutral). "...Alliance"-Tabellen werden gezaehlt, aber nicht uebernommen.
//
// Sicherheit: Lua wird mit luaparse NUR GEPARST, nie ausgefuehrt. Ausgewertet werden ausschliesslich Literale (Zahl, Text, Wahrheitswert,
// nil, Minus vor einer Zahl, Tabellen aus Literalen). Schluessel "<alias>.<feld>" werden nur fuer die festen Aliasse questKeys/npcKeys/
// itemKeys/objectKeys ueber die feste Feldliste aufgeloest; "zoneIDs.X"/"factionIDs.X" nur ueber die ebenfalls nur geparsten Literal-
// Tabellen aus enum/zones.lua bzw. enum/factions.lua. Alles andere (Funktionsaufrufe, Index-Ausdruecke wie ({...})[playerClass],
// unbekannte Namen) ist ein Befund und wird NICHT uebernommen (nie geraten). Groessenlimit je Datei; Objekte ohne Prototyp.

import luaparse from "luaparse";
/** Schema von fixes.json (ausgewertete Laufzeitkorrekturen). */
const FIXES_SCHEMA = 1;

export { FIXES_SCHEMA };

/** Korrektur-Dateien (exakte Archiv-Namen) mit Datentyp. */
export const FIX_ENTRIES = Object.freeze([
  { entry: "QuestieDB/src/corrections/Forever/foreverQuestFixes.lua", datatype: "quest" },
  { entry: "QuestieDB/src/corrections/Forever/foreverNPCFixes.lua", datatype: "npc" },
  { entry: "QuestieDB/src/corrections/Forever/foreverItemFixes.lua", datatype: "item" },
  { entry: "QuestieDB/src/corrections/Forever/foreverObjectFixes.lua", datatype: "object" },
  { entry: "QuestieDB/src/corrections/Forever/legacy/classicQuestFixes.lua", datatype: "quest" },
  { entry: "QuestieDB/src/corrections/Forever/legacy/classicNPCFixes.lua", datatype: "npc" },
  { entry: "QuestieDB/src/corrections/Forever/legacy/classicItemFixes.lua", datatype: "item" },
  { entry: "QuestieDB/src/corrections/Forever/legacy/classicObjectFixes.lua", datatype: "object" },
]);
/** Enum-Dateien fuer zoneIDs.X / factionIDs.X (nur geparst, nur Zahl-Literale). */
export const ENUM_ENTRIES = Object.freeze([
  { entry: "QuestieDB/src/corrections/enum/zones.lua", table: "zoneIDs" },
  { entry: "QuestieDB/src/corrections/enum/factions.lua", table: "factionIDs" },
]);
/** Groesste Korrektur-/Enum-Datei (gemessen: 34 KB). */
export const MAX_FIX_FILE_BYTES = 1024 * 1024;
/** Fraktion, deren Laufzeitkorrekturen uebernommen werden (plus fraktionsneutrale); "...Alliance"-Tabellen werden nur gezaehlt (counts.allianceSkipped). */
export const FIXES_FACTION = "horde";
const MAX_ID = 10_000_000;
const MAX_FINDINGS = 2000;
/** Funktionen mit dynamischen Korrekturen (QuestieDB manifest.lua: dynamic = LoadDynamic bzw. LoadFactionFixes). */
const DYNAMIC_FUNCTIONS = new Set(["LoadDynamic", "LoadFactionFixes"]);
/** Feste Aliasse der Feldschluessel je Datentyp. */
const KEY_ALIAS = Object.freeze({ quest: "questKeys", npc: "npcKeys", item: "itemKeys", object: "objectKeys" });
/** Bekannte Feldnamen je Datentyp (QuestieDB src/meta/*Meta.lua). Unbekannte Namen sind ein Befund. */
export const KNOWN_FIELDS = Object.freeze({
  quest: new Set(["name", "startedBy", "finishedBy", "requiredLevel", "questLevel", "requiredRaces", "requiredClasses", "objectivesText", "triggerEnd", "objectives", "sourceItemId", "preQuestGroup", "preQuestSingle", "childQuests", "inGroupWith", "exclusiveTo", "zoneOrSort", "requiredSkill", "requiredMinRep", "requiredMaxRep", "requiredSourceItems", "nextQuestInChain", "questFlags", "specialFlags", "parentQuest", "reputationReward", "breadcrumbForQuestId", "breadcrumbs", "extraObjectives", "requiredSpell", "requiredSpecialization", "requiredMaxLevel", "availableUntilCompleted", "availableStartingWith", "requiredRanks", "disabledByQuest"]),
  npc: new Set(["name", "minLevelHealth", "maxLevelHealth", "minLevel", "maxLevel", "rank", "spawns", "waypoints", "zoneID", "questStarts", "questEnds", "factionID", "friendlyToFaction", "subName", "npcFlags"]),
  item: new Set(["name", "npcDrops", "objectDrops", "itemDrops", "startQuest", "questRewards", "flags", "foodType", "itemLevel", "requiredLevel", "ammoType", "class", "subClass", "vendors", "relatedQuests", "teachesSpell"]),
  object: new Set(["name", "questStarts", "questEnds", "spawns", "zoneID", "factionID", "waypoints"]),
});

/** Nicht-Literal (Befund). */
class NonLiteral extends Error {
  constructor(what) {
    super(what);
    this.name = "NonLiteral";
  }
}

const textOf = (buf) => Buffer.from(buf).toString("latin1");
/** luaparse liefert Strings im Modus pseudo-latin1 Byte fuer Byte; zurueck nach UTF-8. */
const utf8 = (s) => Buffer.from(s, "latin1").toString("utf8");

function parseLua(buf, entry) {
  if (!Buffer.isBuffer(buf) && !(buf instanceof Uint8Array)) throw new Error(`${entry}: keine Bytes`);
  if (buf.length > MAX_FIX_FILE_BYTES) throw new Error(`${entry}: zu gross (${buf.length} Byte)`);
  return luaparse.parse(textOf(buf), { luaVersion: "5.1", comments: false, scope: false, locations: true, encodingMode: "pseudo-latin1" });
}

/** Zahl-Literal oder -Zahl. */
function numberOf(node) {
  if (node?.type === "NumericLiteral" && typeof node.value === "number" && Number.isFinite(node.value)) return node.value;
  if (node?.type === "UnaryExpression" && node.operator === "-" && node.argument?.type === "NumericLiteral" && Number.isFinite(node.argument.value)) return -node.argument.value;
  return undefined;
}

/** Name einer Mitglieds-Referenz `<base>.<name>` (nur Punkt, nur Bezeichner); sonst undefined. */
function memberName(node) {
  if (node?.type !== "MemberExpression" || node.indexer !== "." || node.base?.type !== "Identifier" || node.identifier?.type !== "Identifier") return undefined;
  return { base: node.base.name, name: node.identifier.name };
}

/**
 * Wertet einen Literal-Ausdruck aus. `enums` = { zoneIDs: Map, factionIDs: Map }. Wirft NonLiteral bei allem anderen.
 * Tabellen: nur Array-Teil -> Array; mit Schluesseln (Zahl/Text/Enum) -> Objekt ohne Prototyp; gemischt -> Objekt (Array-Teil ab 1).
 */
export function literalValue(node, enums, depth = 0) {
  if (depth > 12) throw new NonLiteral("zu tief verschachtelt");
  const n = numberOf(node);
  if (n !== undefined) return n;
  switch (node?.type) {
    case "StringLiteral":
      if (typeof node.value !== "string") throw new NonLiteral("Text ohne Wert");
      return utf8(node.value);
    case "BooleanLiteral":
      return node.value === true;
    case "NilLiteral":
      return null;
    case "MemberExpression": {
      const m = memberName(node);
      const table = m && Object.prototype.hasOwnProperty.call(enums, m.base) ? enums[m.base] : undefined;
      if (m && table && table.has(m.name)) return table.get(m.name);
      throw new NonLiteral(m ? `Bezug ${m.base}.${m.name}` : "Bezug");
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
          if (typeof k !== "number" && typeof k !== "string") throw new NonLiteral("Tabellenschluessel");
          keyed[String(k)] = literalValue(f.value, enums, depth + 1);
        } else throw new NonLiteral(`Tabellenfeld ${f.type}`);
      }
      if (!hasKeys) return list;
      list.forEach((v, i) => {
        keyed[String(i + 1)] = v;
      });
      return keyed;
    }
    default:
      throw new NonLiteral(`Ausdruck ${node?.type ?? "?"}`);
  }
}

/** Enum-Datei: `<irgendwas>.<table> = { NAME = Zahl, ... }` -> Map NAME -> Zahl (nur Zahl-Literale; Rest gezaehlt). */
export function parseEnumFile(buf, entry, table) {
  const ast = parseLua(buf, entry);
  const out = new Map();
  let skipped = 0;
  for (const st of ast.body) {
    if (st.type !== "AssignmentStatement" || st.variables.length !== 1 || st.init.length !== 1) continue;
    const target = memberName(st.variables[0]);
    if (!target || target.name !== table || st.init[0].type !== "TableConstructorExpression") continue;
    for (const f of st.init[0].fields) {
      const v = f.type === "TableKeyString" ? numberOf(f.value) : undefined;
      if (v === undefined || !Number.isSafeInteger(v)) {
        skipped++;
        continue;
      }
      out.set(f.key.name, v);
    }
  }
  return { map: out, skipped };
}

const isDynamicFunction = (st) =>
  st.type === "FunctionDeclaration" && st.identifier?.type === "MemberExpression" && st.identifier.indexer === ":" && DYNAMIC_FUNCTIONS.has(st.identifier.identifier?.name);

/**
 * Eine Korrektur-Datei auswerten. Liefert { blocks: [{ faction: "horde"|"neutral"|"alliance", name, line, table }], hints, findings }.
 * `table` = TableConstructorExpression-Knoten (noch nicht ausgewertet).
 */
function collectBlocks(ast, entry) {
  const blocks = [];
  const findings = [];
  let hints = 0;
  for (const st of ast.body) {
    // QuestieCorrections.itemObjectiveFirst[...] = true: Reihenfolge-Hinweise fuer das Addon, keine Entitaetsdaten
    if (st.type === "AssignmentStatement") {
      hints++;
      continue;
    }
    if (!isDynamicFunction(st)) continue;
    for (const inner of st.body) {
      if (inner.type === "LocalStatement" && inner.init.length === 1 && inner.variables.length === 1 && inner.init[0].type === "TableConstructorExpression") {
        const name = inner.variables[0].name;
        const faction = /Horde$/.test(name) ? "horde" : /Alliance$/.test(name) ? "alliance" : "neutral";
        blocks.push({ faction, name, line: inner.loc?.start.line ?? 0, table: inner.init[0] });
      } else if (inner.type === "ReturnStatement" && inner.arguments.length === 1 && inner.arguments[0].type === "TableConstructorExpression") {
        blocks.push({ faction: "neutral", name: "return", line: inner.loc?.start.line ?? 0, table: inner.arguments[0] });
      }
    }
  }
  if (blocks.length === 0) findings.push({ entry, reason: "keine dynamische Korrektur-Tabelle gefunden" });
  return { blocks, hints, findings };
}

/**
 * Wertet die Korrektur-Dateien aus. `files` = Map<Archivname, Bytes> (nur Namen aus FIX_ENTRIES/ENUM_ENTRIES werden angesehen).
 * Liefert das Objekt fuer data-capture/questie-preview/fixes.json (ohne Stempel):
 *   { schema, quest|npc|item|object: { "<id>": { "<feld>": wert } }, sources: { "<datentyp>:<id>:<feld>": "<datei>" },
 *     counts: { read, horde, neutral, allianceSkipped, nonLiteral, unknownField, emptyBlocks, hints, files, missingFiles }, findings: [...] }
 * Spaetere Dateien in FIX_ENTRIES ueberschreiben fruehere NICHT: die Forever-Dateien stehen vorne und haben Vorrang (QuestieDB registry.lua:
 * ForeverDynamic 1500 > EraDynamic 100).
 */
export function parseQuestieFixes(files) {
  const out = { schema: FIXES_SCHEMA, quest: Object.create(null), npc: Object.create(null), item: Object.create(null), object: Object.create(null), sources: Object.create(null) };
  const counts = { read: 0, horde: 0, neutral: 0, allianceSkipped: 0, nonLiteral: 0, unknownField: 0, emptyBlocks: 0, hints: 0, files: 0, missingFiles: 0, overridden: 0 };
  const findings = [];
  const find = (f) => {
    if (findings.length < MAX_FINDINGS) findings.push(f);
  };
  const enums = Object.create(null);
  for (const { entry, table } of ENUM_ENTRIES) {
    const buf = files.get(entry);
    if (!buf) {
      enums[table] = new Map();
      find({ entry, reason: "Enum-Datei fehlt im Archiv; Bezuege darauf bleiben unaufgeloest" });
      continue;
    }
    try {
      enums[table] = parseEnumFile(buf, entry, table).map;
    } catch (err) {
      enums[table] = new Map();
      find({ entry, reason: `Enum-Datei nicht lesbar (${err instanceof Error ? err.message.slice(0, 120) : "?"})` });
    }
  }
  for (const { entry, datatype } of FIX_ENTRIES) {
    const buf = files.get(entry);
    if (!buf) {
      counts.missingFiles++;
      find({ entry, reason: "Korrektur-Datei fehlt im Archiv" });
      continue;
    }
    let ast;
    try {
      ast = parseLua(buf, entry);
    } catch (err) {
      find({ entry, reason: `nicht parsebar (${err instanceof Error ? err.message.slice(0, 120) : "?"})` });
      continue;
    }
    counts.files++;
    const { blocks, hints, findings: blockFindings } = collectBlocks(ast, entry);
    counts.hints += hints;
    for (const f of blockFindings) find(f);
    const alias = KEY_ALIAS[datatype];
    for (const block of blocks) {
      if (block.table.fields.length === 0) {
        counts.emptyBlocks++;
        continue;
      }
      for (const ent of block.table.fields) {
        const idNum = ent.type === "TableKey" ? numberOf(ent.key) : undefined;
        if (idNum === undefined || !Number.isSafeInteger(idNum) || idNum <= 0 || idNum > MAX_ID || ent.value?.type !== "TableConstructorExpression") {
          find({ entry, block: block.name, line: ent.loc?.start.line ?? block.line, reason: "Eintrag ohne Zahl-ID oder ohne Tabelle" });
          continue;
        }
        for (const fieldNode of ent.value.fields) {
          const line = fieldNode.loc?.start.line ?? 0;
          const key = fieldNode.type === "TableKey" ? memberName(fieldNode.key) : undefined;
          if (!key || key.base !== alias) {
            counts.nonLiteral++;
            find({ entry, datatype, id: idNum, line, reason: "Feldschluessel ist kein <" + alias + ">.<feld>" });
            continue;
          }
          if (!KNOWN_FIELDS[datatype].has(key.name)) {
            counts.unknownField++;
            find({ entry, datatype, id: idNum, field: key.name, line, reason: "unbekanntes Feld" });
            continue;
          }
          if (block.faction === "alliance") {
            counts.allianceSkipped++;
            continue;
          }
          let value;
          try {
            value = literalValue(fieldNode.value, enums);
          } catch (err) {
            if (!(err instanceof NonLiteral)) throw err;
            counts.nonLiteral++;
            find({ entry, datatype, id: idNum, field: key.name, line, reason: `kein Literal (${err.message}), nicht uebernommen` });
            continue;
          }
          const bucket = out[datatype];
          const rec = (bucket[String(idNum)] ??= Object.create(null));
          const srcKey = `${datatype}:${idNum}:${key.name}`;
          if (Object.prototype.hasOwnProperty.call(rec, key.name)) {
            // Vorrang: zuerst gelesene Datei (Forever vor legacy) gewinnt
            counts.overridden++;
            continue;
          }
          rec[key.name] = value;
          out.sources[srcKey] = entry.split("/").pop();
          counts.read++;
          if (block.faction === "horde") counts.horde++;
          else counts.neutral++;
        }
      }
    }
  }
  return { ...out, counts, findings };
}
