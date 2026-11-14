// Erzeugt die Rezeptdaten (Pläne > Handwerk "Als Nächstes lernen") fuer das Daten-Addon aus "What's Training?" (MIT).
//
// Aufruf:  node scripts/build-recipe-data.mjs --src <ordner> [--out <ordner>] [--unpinned] [--help]
//   --src       lokaler Stand von https://github.com/fusionpit/WhatsTraining im gepinnten Commit (PINNED_COMMIT aus
//               scripts/build-trainer-data.mjs, derselbe Pin wie die Lehrplan-Daten). Gelesen werden nur LICENSE und
//               Crafting/Recipes/Camelot/<Beruf>.lua.
//   --out       Zielordner. Standard: addon\InkAndEmbers_Data (Datei Recipes.lua + LICENSE-WhatsTraining.txt)
//   --unpinned  Quelldateien duerfen vom gepinnten Stand abweichen (SHA-256); der Kopf der Ausgabe nennt das dann.
// Exit-Codes: 0 = ok, 1 = Fehler (Quelle fehlt/unlesbar, Hash weicht ab, Ergebnis unplausibel, unbekannte Option)
//
// Ergebnis (reproduzierbar: sortiert, ohne Zeitstempel):
//   Recipes.lua   EveNChronicleRecipeData = { source, commit, date, license, skills = { [skillLineID] = "<zeilen>" } }
//     je Rezept eine Zeile, Felder durch Tab getrennt (leere Felder = keine Angabe), sortiert nach Mindestskill, dann Zauber-ID:
//       <skill>  <spellID>  <quellen>  <kupfer>  <fraktion A|H>  <merchantFavor>  <rang J|E|A>  <stufe>  <ruf-id:stufe[,...]>
//     quellen: Buchstaben T = Lehrer, V = Haendler, Q = Quest, D = Beute/Drop, C = durch anderes Rezept hergestellt, O = Weltobjekt (Reihenfolge fest)
//     rang:    J = Geselle, E = Experte, A = Meister (Rang-Zauber des Lehrers; stufe = noetige Charakterstufe)
//     ruf:     "<id>:<stufe>", bei Alliance- und Horde-Fraktion mehrere mit Komma. Stufe (4 neutral, 5 wohlwollend, 6 respektvoll, 7 ehrfuerchtig, 8 erhaben)
//   Nicht uebernommen: Rezepte ohne Quelle (automatisch gelernt), Gegenstands-IDs, NPC-/Gebiets-/Questlisten, Namen.
//   LICENSE-WhatsTraining.txt  der Lizenztext der Quelle (MIT, unveraendert)
//
// Sicherheit: reine Auswertung lokaler Dateien, kein Netz, kein Ausfuehren von Lua (luaparse liefert nur den Syntaxbaum;
// ausgewertet werden ausschliesslich Tabellen, Zahlen, Zeichenketten, Wahrheitswerte und Verweise ns.L.FACTION_<n>, deren Wert
// verworfen wird). Jeder Wert wird gegen Grenzen geprueft; die Ausgabe enthaelt nur Ziffern, Doppelpunkt, Tabs, Zeilenumbrueche
// und die Buchstaben T V Q D C O A H J E.

import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { mkdir, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import luaparse from "luaparse";
import { PINNED_COMMIT, PINNED_DATE, SOURCE_SHA256 as TRAINER_SHA256 } from "./build-trainer-data.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export { PINNED_COMMIT, PINNED_DATE };
export const DEFAULT_OUT = path.join(ROOT, "addon", "InkAndEmbers_Data");
export const SOURCE_URL = "https://github.com/fusionpit/WhatsTraining/tree/master/Crafting/Recipes/Camelot";
/** Beruf-Datei -> skillLine-ID (dieselben IDs wie das SK-Feld der Chronik) */
export const PROFESSIONS = {
  Alchemy: 171, Blacksmithing: 164, Cooking: 185, Enchanting: 333, Engineering: 202, FirstAid: 129, Fishing: 356, Herbalism: 182,
  Leatherworking: 165, Mining: 186, Skinning: 393, Tailoring: 197,
};
// SHA-256 der Quelldateien im gepinnten Commit (Pruefung, dass genau dieser Stand eingelesen wird)
export const SOURCE_SHA256 = {
  LICENSE: TRAINER_SHA256.LICENSE,
  "Crafting/Recipes/Camelot/Alchemy.lua": "d169d023ee6a98a588989e99a6458229cd12b80206833cd9f8d9b19cf0a06000",
  "Crafting/Recipes/Camelot/Blacksmithing.lua": "ad6dd3d587735eae0aab52eb4a9d0c0dfede6d228e760afa2fff100d26ae65c0",
  "Crafting/Recipes/Camelot/Cooking.lua": "13a5f0217880a6f157d324171c38d623d706b7bb9753b605de5c0372c9f7720a",
  "Crafting/Recipes/Camelot/Enchanting.lua": "947fa83a811a06d3db6a1a26ef1963997c006a055b538f46600e79c37ec78975",
  "Crafting/Recipes/Camelot/Engineering.lua": "d18f7d430eab38dcddd0cafdbf766368327571315b30f116db9b2cf6370fb5d8",
  "Crafting/Recipes/Camelot/FirstAid.lua": "bdd9a714e13f8f413a07777233fa9057300f8120ee5941ad7246164c633d8b62",
  "Crafting/Recipes/Camelot/Fishing.lua": "861243d61f0d3f9f0f7ba60fefb5ee74d7808836b527c05ac2bde33f9e60a416",
  "Crafting/Recipes/Camelot/Herbalism.lua": "e176851f1023cc0f1f91acc29da89eac0f0a814c2f6c37623946be3be1ec884f",
  "Crafting/Recipes/Camelot/Leatherworking.lua": "5f82113d8629f8ffb624e003fe1eaadce3a3f954da6580e5d88adf03a3f33c6d",
  "Crafting/Recipes/Camelot/Mining.lua": "bb4d60664c175fc0f91752e343661d8c48a19d072892e18d5541d77dc13ec396",
  "Crafting/Recipes/Camelot/Skinning.lua": "38941f22f14b06efef893bd9882f698a3e5d0627abdbbbdb25a9b3684b02551a",
  "Crafting/Recipes/Camelot/Tailoring.lua": "1c8dd497b8ca066e88dc879978fb15e2ddacfb2f09de8433708003ac67d74b34",
};
export const LIMITS = { id: 2147483647, skill: 600, level: 60, cost: 10000000, favor: 100000, minPerSkill: 3, minTotal: 1000, srcBytes: 256 * 1024, outBytes: 160 * 1024 };
const SOURCES = { trainer: "T", vendor: "V", quest: "Q", drop: "D", crafted: "C", world_object: "O" };
const SOURCE_ORDER = ["trainer", "vendor", "quest", "drop", "crafted", "world_object"];
const RANKS = { Journeyman: "J", Expert: "E", Artisan: "A" };

const HELP = `InkAndEmbers: Rezeptdaten (Pläne > Handwerk) aus "What's Training?" erzeugen

Aufruf:
  node scripts/build-recipe-data.mjs --src <ordner> [--out <ordner>] [--unpinned]

  --src       lokaler Stand von github.com/fusionpit/WhatsTraining (Commit ${PINNED_COMMIT.slice(0, 7)}, wie build-trainer-data.mjs)
  --out       Zielordner (Standard: addon\\InkAndEmbers_Data)
  --unpinned  abweichenden Quellstand zulassen (sonst Abbruch bei anderem SHA-256)
`;

export function parseArgs(argv) {
  const out = { help: false, src: null, out: null, unpinned: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--help" || a === "-h") out.help = true;
    else if (a === "--unpinned") out.unpinned = true;
    else if (a === "--src" || a === "--out") {
      const v = argv[++i];
      if (!v || v.startsWith("--")) throw new Error(`Option ${a} braucht einen Pfad.`);
      if (v.includes("\0")) throw new Error(`Option ${a}: ungueltiger Pfad.`);
      out[a.slice(2)] = path.resolve(v);
    } else throw new Error(`Unbekannte Option bzw. unerwartetes Argument: ${a}\nHilfe: node scripts/build-recipe-data.mjs --help`);
  }
  return out;
}

// ---------------------------------------------------------------- Lua-Tabellen auswerten (ohne Ausfuehren)

function stringValue(node) {
  const raw = node.raw;
  if (typeof raw !== "string" || raw.length < 2) throw new Error("Zeichenkette nicht lesbar");
  const q = raw[0];
  if ((q !== '"' && q !== "'") || raw[raw.length - 1] !== q) throw new Error("Nur einfache Zeichenketten erlaubt");
  const body = raw.slice(1, -1);
  if (!/^[A-Za-z0-9 _-]*$/.test(body)) throw new Error(`Zeichenkette mit unerwarteten Zeichen: ${body.slice(0, 20)}`);
  return body;
}

/** ns.L.FACTION_<n> (Name der Ruf-Fraktion, wird zur Laufzeit vom Spiel geliefert) -> "" (Wert verworfen) */
function isFactionName(node) {
  return node.type === "MemberExpression" && node.indexer === "." && /^FACTION_\d{1,6}$/.test(node.identifier?.name ?? "")
    && node.base.type === "MemberExpression" && node.base.indexer === "." && node.base.identifier?.name === "L"
    && node.base.base.type === "Identifier" && node.base.base.name === "ns";
}

export function evalNode(node, depth = 0) {
  if (depth > 8) throw new Error("Tabelle zu tief verschachtelt");
  switch (node.type) {
    case "NumericLiteral":
      return node.value;
    case "StringLiteral":
      return stringValue(node);
    case "BooleanLiteral":
      return node.value;
    case "UnaryExpression":
      if (node.operator === "-" && node.argument.type === "NumericLiteral") return -node.argument.value;
      throw new Error(`Ausdruck nicht erlaubt: ${node.operator}`);
    case "MemberExpression":
      if (isFactionName(node)) return "";
      throw new Error("Ausdruck nicht erlaubt: MemberExpression");
    case "TableConstructorExpression": {
      const arr = [];
      const obj = {};
      let isObj = false;
      for (const f of node.fields) {
        if (f.type === "TableValue") arr.push(evalNode(f.value, depth + 1));
        else if (f.type === "TableKeyString") {
          isObj = true;
          obj[f.key.name] = evalNode(f.value, depth + 1);
        } else throw new Error(`Tabellenfeld nicht erlaubt: ${f.type}`);
      }
      if (isObj && arr.length) throw new Error("Gemischte Tabelle nicht erlaubt");
      return isObj ? obj : arr;
    }
    default:
      throw new Error(`Ausdruck nicht erlaubt: ${node.type}`);
  }
}

/** Berufsdatei -> { skillLine, entries: [Roheintrag] } ("ns.Recipes[<skillLine>] = { ... }"; alles andere ist verboten) */
export function readRecipeFile(text, file = "?") {
  if (typeof text !== "string" || text.length > LIMITS.srcBytes) throw new Error(`${file}: Quelldatei fehlt oder ist zu gross`);
  const ast = luaparse.parse(text, { luaVersion: "5.1", comments: false });
  let found = null;
  for (const st of ast.body) {
    if (st.type === "LocalStatement") continue; // "local _, ns = ..."
    if (st.type !== "AssignmentStatement" || st.variables.length !== 1 || st.init.length !== 1) throw new Error(`${file}: unerwartete Anweisung ${st.type}`);
    const v = st.variables[0];
    const init = st.init[0];
    if (v.type === "MemberExpression") continue; // "ns.Recipes = ns.Recipes or {}"
    if (v.type !== "IndexExpression" || v.base.type !== "MemberExpression" || v.base.identifier?.name !== "Recipes" || v.index.type !== "NumericLiteral") {
      throw new Error(`${file}: unerwartete Zuweisung`);
    }
    if (found) throw new Error(`${file}: mehrere Berufe in einer Datei`);
    if (init.type !== "TableConstructorExpression") throw new Error(`${file}: Rezeptliste ist keine Tabelle`);
    const entries = evalNode(init);
    if (!Array.isArray(entries)) throw new Error(`${file}: Rezeptliste ist keine Liste`);
    found = { skillLine: v.index.value, entries };
  }
  if (!found) throw new Error(`${file}: keine Rezeptliste gefunden`);
  return found;
}

const isId = (v) => Number.isInteger(v) && v > 0 && v <= LIMITS.id;

/** Roheintrag -> { skill, spell, src, cost, faction, favor, rank, level, rep } oder null (keine Quelle: automatisch gelernt) */
export function convertEntry(e, where = "?") {
  if (!e || typeof e !== "object" || Array.isArray(e)) throw new Error(`${where}: Eintrag unlesbar`);
  if (!isId(e.spell)) throw new Error(`${where}: ungueltige Zauber-ID`);
  const skill = e.skill ?? 0;
  if (!Number.isInteger(skill) || skill < 0 || skill > LIMITS.skill) throw new Error(`${where} ${e.spell}: ungueltiger Skill`);
  if (e.source === undefined) return null;
  if (!Array.isArray(e.source) || e.source.length === 0 || e.source.length > 6 || !e.source.every((s) => Object.prototype.hasOwnProperty.call(SOURCES, s))) {
    throw new Error(`${where} ${e.spell}: ungueltige Quelle`);
  }
  const src = SOURCE_ORDER.filter((s) => e.source.includes(s)).map((s) => SOURCES[s]).join("");
  const cost = e.cost ?? 0;
  if (!Number.isInteger(cost) || cost < 0 || cost > LIMITS.cost) throw new Error(`${where} ${e.spell}: ungueltiger Preis`);
  const favor = e.merchantFavor ?? 0;
  if (!Number.isInteger(favor) || favor < 0 || favor > LIMITS.favor) throw new Error(`${where} ${e.spell}: ungueltiges Merchant's Favor`);
  let rank = "";
  let level = "";
  if (e.rank !== undefined) {
    if (!Object.prototype.hasOwnProperty.call(RANKS, e.rank)) throw new Error(`${where} ${e.spell}: ungueltiger Rang`);
    rank = RANKS[e.rank];
    const lv = e.level ?? 0;
    if (!Number.isInteger(lv) || lv < 0 || lv > LIMITS.level) throw new Error(`${where} ${e.spell}: ungueltige Stufe`);
    level = lv;
  }
  let rep = "";
  if (e.reputation !== undefined) {
    // Gruppen zu je drei Werten (Fraktions-ID, Ruf-Stufe, Name): Alliance- und Horde-Fraktion koennen beide genannt sein
    const r = e.reputation;
    if (!Array.isArray(r) || r.length < 3 || r.length > 12 || r.length % 3 !== 0) throw new Error(`${where} ${e.spell}: ungueltiger Ruf`);
    const parts = [];
    for (let i = 0; i < r.length; i += 3) {
      if (!isId(r[i]) || !Number.isInteger(r[i + 1]) || r[i + 1] < 1 || r[i + 1] > 8 || typeof r[i + 2] !== "string") throw new Error(`${where} ${e.spell}: ungueltiger Ruf`);
      parts.push(`${r[i]}:${r[i + 1]}`);
    }
    rep = parts.join(",");
  }
  // Fraktion: nur wenn JEDE Fundstelle (Haendler/Quest) an eine Fraktion gebunden ist und es keinen Lehrer/Drop gibt (side = ausdruecklich)
  let faction = "";
  const refs = [...(Array.isArray(e.vendors) ? e.vendors : []), ...(Array.isArray(e.quests) ? e.quests : [])];
  for (const r of refs) {
    if (!r || typeof r !== "object" || (r.faction !== undefined && r.faction !== "Alliance" && r.faction !== "Horde")) throw new Error(`${where} ${e.spell}: ungueltige Fraktion`);
  }
  if (e.side !== undefined) {
    if (e.side !== "Alliance" && e.side !== "Horde") throw new Error(`${where} ${e.spell}: ungueltige Seite`);
    faction = e.side[0];
  } else if (refs.length > 0 && !/[TD]/.test(src)) {
    const set = new Set(refs.map((r) => r.faction ?? ""));
    if (set.size === 1 && !set.has("")) faction = [...set][0][0];
  }
  return { skill, spell: e.spell, src, cost, faction, favor: favor || "", rank, level, rep };
}

export function recipeLines(list) {
  return list
    .map((r) => [r.skill, r.spell, r.src, r.cost || "", r.faction, r.favor, r.rank, r.level, r.rep].join("\t"))
    .join("\n");
}

// ---------------------------------------------------------------- Ausgabe

function luaString(s) {
  if (!/^[0-9:,\tTVQDCOAHJE\n]*$/.test(s)) throw new Error("Ausgabe enthaelt unerwartete Zeichen");
  return '"' + s.replace(/\t/g, "\\t").replace(/\n/g, "\\n") + '"';
}

export function render({ skills, commit, pinned }) {
  const lines = [];
  lines.push("-- InkAndEmbers_Data: profession recipes for Pläne > Handwerk. GENERATED by scripts/build-recipe-data.mjs, do not edit by hand.");
  lines.push("-- Source: \"What's Training?\" by Sveng/fusionpit, branch \"master\", Crafting/Recipes/Camelot/*.lua");
  lines.push(`-- (${SOURCE_URL}), commit ${commit}${pinned ? "" : " (UNPINNED: source differs from the pinned hashes)"}.`);
  lines.push("-- Licensed under the MIT License, Copyright (c) 2019 - full text in LICENSE-WhatsTraining.txt (unchanged). The rest of this");
  lines.push("-- add-on is GPL-3.0 (see LICENSE); MIT code may be included in it.");
  lines.push("-- Changes: converted to a compact text format (one line per recipe); only spell id, minimum skill, source, price, faction,");
  lines.push("-- Merchant's Favor, rank step and reputation kept; recipes without a source (learned automatically) left out; nothing added.");
  lines.push("-- skills[skillLineID]: \"<skill>\\t<spellID>\\t<sources T V Q D C O>\\t<copper>\\t<faction A|H>\\t<merchant's favor>\\t<rank J E A>\\t<char level>\\t<faction id:standing[,...]>\"");
  lines.push("-- Loaded on demand only (LoadOnDemand) by journal/model/Rezepte.lua of the main add-on, in the same load as the to-do lists.");
  lines.push("EveNChronicleRecipeData = {");
  lines.push(`  source = "WhatsTraining", commit = "${commit.slice(0, 12)}", date = "${PINNED_DATE}", license = "MIT",`);
  lines.push("  skills = {");
  for (const id of Object.values(PROFESSIONS).sort((a, b) => a - b)) lines.push(`    [${id}] = ${luaString(recipeLines(skills[id]))},`);
  lines.push("  },");
  lines.push("}");
  return lines.join("\n") + "\n";
}

function sha256(buf) {
  return createHash("sha256").update(buf).digest("hex");
}

async function writeAtomic(file, text) {
  const tmp = file + ".tmp";
  await writeFile(tmp, text, "utf8");
  await rename(tmp, file);
}

export function readSources(src, { unpinned = false } = {}) {
  const read = (rel) => {
    const file = path.join(src, ...rel.split("/"));
    if (!existsSync(file)) throw new Error(`Quelldatei fehlt: ${rel} (unter ${src})`);
    const buf = readFileSync(file);
    if (buf.length > LIMITS.srcBytes) throw new Error(`Quelldatei zu gross: ${rel}`);
    const ok = sha256(buf) === SOURCE_SHA256[rel];
    if (!ok && !unpinned) throw new Error(`${rel} weicht vom gepinnten Stand ${PINNED_COMMIT.slice(0, 7)} ab (SHA-256). Commit auschecken oder --unpinned.`);
    return { text: buf.toString("utf8"), ok };
  };
  let pinned = true;
  const license = read("LICENSE");
  pinned = pinned && license.ok;
  if (!/MIT License/.test(license.text) || !/Permission is hereby granted, free of charge/.test(license.text)) {
    throw new Error("LICENSE der Quelle ist nicht der erwartete MIT-Text");
  }
  const skills = {};
  const dropped = {};
  for (const [name, expected] of Object.entries(PROFESSIONS)) {
    const rel = `Crafting/Recipes/Camelot/${name}.lua`;
    const f = read(rel);
    pinned = pinned && f.ok;
    const { skillLine, entries } = readRecipeFile(f.text, rel);
    if (skillLine !== expected) throw new Error(`${rel}: skillLine ${skillLine} statt ${expected}`);
    const list = [];
    let none = 0;
    const seen = new Set();
    for (const e of entries) {
      const r = convertEntry(e, name);
      if (!r) {
        none++;
        continue;
      }
      if (seen.has(r.spell)) throw new Error(`${name}: Zauber ${r.spell} doppelt`);
      seen.add(r.spell);
      list.push(r);
    }
    list.sort((a, b) => a.skill - b.skill || a.spell - b.spell);
    if (list.length < LIMITS.minPerSkill) throw new Error(`${name}: unplausible Anzahl Rezepte (${list.length})`);
    skills[skillLine] = list;
    dropped[name] = none;
  }
  const total = Object.values(skills).reduce((n, l) => n + l.length, 0);
  if (total < LIMITS.minTotal) throw new Error(`unplausible Gesamtzahl Rezepte (${total})`);
  return { license: license.text, skills, dropped, pinned };
}

export async function build({ src, out = DEFAULT_OUT, unpinned = false }) {
  const s = readSources(src, { unpinned });
  const text = render({ skills: s.skills, commit: PINNED_COMMIT, pinned: s.pinned });
  if (Buffer.byteLength(text) > LIMITS.outBytes) throw new Error(`Ergebnis zu gross (${Buffer.byteLength(text)} B)`);
  await mkdir(out, { recursive: true });
  await writeAtomic(path.join(out, "Recipes.lua"), text);
  await writeAtomic(path.join(out, "LICENSE-WhatsTraining.txt"), s.license.endsWith("\n") ? s.license : s.license + "\n");
  const counts = Object.fromEntries(Object.entries(PROFESSIONS).map(([n, id]) => [n, s.skills[id].length]));
  return { counts, dropped: s.dropped, bytes: Buffer.byteLength(text), pinned: s.pinned, out };
}

export async function main(argv) {
  const opts = parseArgs(argv);
  if (opts.help) {
    console.log(HELP);
    return null;
  }
  if (!opts.src) throw new Error("Quelle fehlt: --src <ordner> (lokaler Stand von WhatsTraining, Branch master).");
  const r = await build({ src: opts.src, out: opts.out ?? DEFAULT_OUT, unpinned: opts.unpinned });
  console.log(`What's Training? ${PINNED_COMMIT.slice(0, 7)}${r.pinned ? " (gepinnt)" : " (UNGEPINNT)"}: ${JSON.stringify(r.counts)}`);
  console.log(`Recipes.lua: ${r.bytes} B -> ${r.out}`);
  return r;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).catch((err) => {
    console.error(`FEHLER: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  });
}
