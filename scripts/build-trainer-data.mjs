// Erzeugt die Lehrplan-Daten (Klassenlehrer-Zauber je Klasse) fuer das Hauptaddon aus "What's Training?" (MIT).
//
// Aufruf:  node scripts/build-trainer-data.mjs --src <ordner> [--out <ordner>] [--unpinned] [--help]
//   --src       lokaler Stand von https://github.com/fusionpit/WhatsTraining (Branch "master") im gepinnten Commit
//               (PINNED_COMMIT unten). Gelesen werden nur LICENSE und Classes/Camelot/<Klasse>.lua + HunterPets.lua + QuestSpells.lua.
//   --out       Zielordner. Standard: addon\InkAndEmbers\data (Datei TrainerSpells.lua + LICENSE-WhatsTraining.txt)
//   --unpinned  Quelldateien duerfen vom gepinnten Stand abweichen (SHA-256); der Kopf der Ausgabe nennt das dann.
// Exit-Codes: 0 = ok, 1 = Fehler (Quelle fehlt/unlesbar, Hash weicht ab, Ergebnis unplausibel, unbekannte Option)
//
// Ergebnis (reproduzierbar: sortiert, ohne Zeitstempel):
//   TrainerSpells.lua  ns.TrainerSpells = { source, commit, spells = { [KLASSE] = "<zeilen>" }, pets = { HUNTER = "<zeilen>" }, groups = {...}, quests = {...} }
//     spells: je Zauber eine Zeile "<stufe>\t<id>\t<kupfer>\t<vorgaenger,...>\t<talent-id>\t<fraktion A|H>\t<volk-id>"
//             (leere Felder = keine Angabe), sortiert nach Stufe, dann Reihenfolge der Quelle
//     pets:   Jaeger-Tierfaehigkeiten (Beast Training, class.petAbilityIds in HunterPets.lua), gleiches Zeilenformat wie spells;
//             diese IDs stehen NICHT in spells.HUNTER (Tierausbilder, kein Klassenlehrer)
//     groups: Ranggruppen, die sich im Zauberbuch ersetzen ("overriddenGroups"): "<id,id,...>;<id,...>"
//     quests: Zauber aus Klassenquests: je Zeile "<id>\t<stufe>\t<voelker,...>\t<quests,...>\t<gebiete,...>"
//   LICENSE-WhatsTraining.txt  der Lizenztext der Quelle (MIT, unveraendert)
//
// Sicherheit: reine Auswertung lokaler Dateien, kein Netz, kein Ausfuehren von Lua (luaparse liefert nur den Syntaxbaum;
// ausgewertet werden ausschliesslich Tabellen, Zahlen, Zeichenketten und Verweise auf lokale Tabellen). Jeder Wert wird
// gegen Grenzen geprueft (IDs, Stufen, Preise); die Ausgabe enthaelt nur Ziffern, Kommas, Tabs, Zeilenumbrueche und A/H.

import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { mkdir, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import luaparse from "luaparse";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const DEFAULT_OUT = path.join(ROOT, "addon", "InkAndEmbers", "data");
export const PINNED_COMMIT = "567bfa06720351aa90ac2a73409cfe83ff61eed3";
export const PINNED_DATE = "2026-11-12";
export const SOURCE_URL = "https://github.com/fusionpit/WhatsTraining/tree/master/Classes/Camelot";
export const CLASSES = ["DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR"];
const FILE_OF = { DRUID: "Druid", HUNTER: "Hunter", MAGE: "Mage", PALADIN: "Paladin", PRIEST: "Priest", ROGUE: "Rogue",
  SHAMAN: "Shaman", WARLOCK: "Warlock", WARRIOR: "Warrior" };
// SHA-256 der Quelldateien im gepinnten Commit (Pruefung, dass genau dieser Stand eingelesen wird)
export const SOURCE_SHA256 = {
  LICENSE: "64c4e54df59cc6516ddffd512abb053e7cee2e064d2af53ce5ada164be4a67fa",
  "Classes/Camelot/Druid.lua": "f7c0d12506755c1d2f5ff49331521b2662f9feed7d5dfeddd5dbbbf98a12bc71",
  "Classes/Camelot/Hunter.lua": "f59906a497e649012f3fc6ab4654d27ed91e0920cfbabc173e791f5014595734",
  "Classes/Camelot/HunterPets.lua": "94166ba1c57cbc008448c1b516233bcf9d3116db97a0d4b085b6a65c4fa9cf0f",
  "Classes/Camelot/Mage.lua": "1a36177de4ed5aafb96a862a284e804f1a3cac818ac2d79136fb64fb6859a794",
  "Classes/Camelot/Paladin.lua": "0114021808896ef896b77f42106e9ebdd350a8953aed5711a4e51622283df9a1",
  "Classes/Camelot/Priest.lua": "cc67119a0247f9c24d2c18a424935484746865b6da8452390f415eb73993a5a9",
  "Classes/Camelot/Rogue.lua": "134d482e20a766e844c1bc1da56d91feae67fdefb8e59f8b9d96f869d7592539",
  "Classes/Camelot/Shaman.lua": "20c180d59af1dde44c2ab648955b221f2771e4ae0424ee130f0840689f4972bc",
  "Classes/Camelot/Warlock.lua": "f1d16dbb32888ebc039b6761e282d9ed60b31915790d4ad05612a01946d0a869",
  "Classes/Camelot/Warrior.lua": "31a56c69bfc43ba5f0e68e11999c3f4e6a47edd7a40df526082b0626416b00cf",
  "Classes/Camelot/QuestSpells.lua": "0f26c61f566330ed3abb3e17b88df966752b2b2f365b3cbf0a00e1c674d3be5f",
};
export const LIMITS = { id: 2147483647, level: 60, cost: 10000000, perClassMin: 40, perClassMax: 400, petMin: 20, petMax: 100, srcBytes: 256 * 1024, outBytes: 128 * 1024 };

const HELP = `InkAndEmbers: Lehrplan-Daten (Klassenlehrer-Zauber) aus "What's Training?" erzeugen

Aufruf:
  node scripts/build-trainer-data.mjs --src <ordner> [--out <ordner>] [--unpinned]

  --src       lokaler Stand von github.com/fusionpit/WhatsTraining (Branch master, Commit ${PINNED_COMMIT.slice(0, 7)})
  --out       Zielordner (Standard: addon\\InkAndEmbers\\data)
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
    } else throw new Error(`Unbekannte Option bzw. unerwartetes Argument: ${a}\nHilfe: node scripts/build-trainer-data.mjs --help`);
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

/** Wert eines Ausdrucks: Tabellen (Array/Objekt), Zahlen, Zeichenketten, Wahrheitswerte, Verweise auf lokale Tabellen */
export function evalNode(node, env, depth = 0) {
  if (depth > 12) throw new Error("Tabelle zu tief verschachtelt");
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
    case "Identifier":
      if (!Object.prototype.hasOwnProperty.call(env, node.name)) throw new Error(`Unbekannter Bezeichner: ${node.name}`);
      return env[node.name];
    case "TableConstructorExpression": {
      const arr = [];
      const obj = {};
      let isObj = false;
      for (const f of node.fields) {
        if (f.type === "TableValue") arr.push(evalNode(f.value, env, depth + 1));
        else if (f.type === "TableKeyString") {
          isObj = true;
          obj[f.key.name] = evalNode(f.value, env, depth + 1);
        } else if (f.type === "TableKey") {
          isObj = true;
          const k = evalNode(f.key, env, depth + 1);
          if (typeof k !== "number" && typeof k !== "string") throw new Error("Tabellenschluessel nicht erlaubt");
          obj[String(k)] = evalNode(f.value, env, depth + 1);
        } else throw new Error(`Tabellenfeld nicht erlaubt: ${f.type}`);
      }
      if (isObj && arr.length) throw new Error("Gemischte Tabelle nicht erlaubt");
      return isObj ? obj : arr;
    }
    default:
      throw new Error(`Ausdruck nicht erlaubt: ${node.type}`);
  }
}

/** "class.spellsByLevel = {...}" usw.: { locals, fields: { "class.spellsByLevel": value, "wt.QuestSpells": ... } } */
export function readAssignments(text) {
  if (typeof text !== "string" || text.length > LIMITS.srcBytes) throw new Error("Quelldatei fehlt oder ist zu gross");
  const ast = luaparse.parse(text, { luaVersion: "5.1", comments: false });
  const env = {};
  const fields = {};
  for (const st of ast.body) {
    if (st.type === "LocalStatement") {
      st.variables.forEach((v, i) => {
        const init = st.init[i];
        if (init && init.type === "TableConstructorExpression") env[v.name] = evalNode(init, env);
      });
    } else if (st.type === "AssignmentStatement") {
      st.variables.forEach((v, i) => {
        if (v.type !== "MemberExpression" || v.base.type !== "Identifier" || v.indexer !== ".") return;
        const name = `${v.base.name}.${v.identifier.name}`;
        const init = st.init[i];
        if (!init) return;
        fields[name] = init.type === "Identifier" ? (env[init.name] ?? null) : init.type === "TableConstructorExpression" ? evalNode(init, env) : null;
      });
    }
  }
  return { locals: env, fields };
}

const isId = (v) => Number.isInteger(v) && v > 0 && v <= LIMITS.id;
function idList(v, what) {
  if (v === undefined) return [];
  if (!Array.isArray(v) || v.length > 32 || !v.every(isId)) throw new Error(`${what}: ungueltige ID-Liste`);
  return v;
}

/** Klassendatei -> { spells: [{ level, id, cost, req, talent, faction, race }], groups: [[id...]] } */
export function parseClassFile(text, cls = "?") {
  const { fields } = readAssignments(text);
  const byLevel = fields["class.spellsByLevel"];
  if (!byLevel || typeof byLevel !== "object" || Array.isArray(byLevel)) throw new Error(`${cls}: class.spellsByLevel fehlt`);
  const spells = [];
  const levels = Object.keys(byLevel).map(Number).sort((a, b) => a - b);
  for (const level of levels) {
    if (!Number.isInteger(level) || level < 1 || level > LIMITS.level) throw new Error(`${cls}: ungueltige Stufe ${level}`);
    const list = byLevel[String(level)];
    if (!Array.isArray(list)) throw new Error(`${cls}: Stufe ${level} ist keine Liste`);
    for (const e of list) {
      if (!e || typeof e !== "object" || Array.isArray(e)) throw new Error(`${cls}: Eintrag auf Stufe ${level} unlesbar`);
      if (!isId(e.id)) throw new Error(`${cls}: ungueltige Zauber-ID auf Stufe ${level}`);
      const cost = e.cost ?? 0;
      if (!Number.isInteger(cost) || cost < 0 || cost > LIMITS.cost) throw new Error(`${cls}: ungueltiger Preis bei ${e.id}`);
      if (e.requiredTalentId !== undefined && !isId(e.requiredTalentId)) throw new Error(`${cls}: ungueltige Talent-ID bei ${e.id}`);
      if (e.faction !== undefined && e.faction !== "Alliance" && e.faction !== "Horde") throw new Error(`${cls}: ungueltige Fraktion bei ${e.id}`);
      if (e.race !== undefined && !(Number.isInteger(e.race) && e.race > 0 && e.race < 1000)) throw new Error(`${cls}: ungueltiges Volk bei ${e.id}`);
      spells.push({ level, id: e.id, cost, req: idList(e.requiredIds, `${cls} ${e.id}`), talent: e.requiredTalentId ?? null,
        faction: e.faction ? e.faction[0] : "", race: e.race ?? null });
    }
  }
  const groups = [];
  const og = fields["class.overriddenGroups"];
  if (og !== undefined && og !== null) {
    if (!Array.isArray(og)) throw new Error(`${cls}: overriddenGroups ist keine Liste`);
    for (const g of og) groups.push(idList(g, `${cls} Ranggruppe`));
  }
  if (spells.length < LIMITS.perClassMin || spells.length > LIMITS.perClassMax) {
    throw new Error(`${cls}: unplausible Anzahl Zauber (${spells.length})`);
  }
  return { spells, groups };
}

/** HunterPets.lua -> sortierte Liste der Tierfaehigkeiten-IDs (class.petAbilityIds = { [id] = true, ... }) */
export function parsePetIds(text) {
  const { fields } = readAssignments(text);
  const t = fields["class.petAbilityIds"];
  if (!t || typeof t !== "object" || Array.isArray(t)) throw new Error("HUNTER: class.petAbilityIds fehlt");
  const ids = [];
  for (const [k, v] of Object.entries(t)) {
    const id = Number(k);
    if (!isId(id) || v !== true) throw new Error("HUNTER: ungueltiger Eintrag in petAbilityIds");
    ids.push(id);
  }
  if (ids.length < LIMITS.petMin || ids.length > LIMITS.petMax) throw new Error(`HUNTER: unplausible Anzahl Tierfaehigkeiten (${ids.length})`);
  return ids.sort((a, b) => a - b);
}

/** Zauberliste der Klasse in { spells, pets } trennen: pets = Zeilen mit einer ID aus petIds (Reihenfolge der Quelle bleibt) */
export function splitPets(spells, petIds) {
  const set = new Set(petIds);
  const found = new Set();
  const rest = [];
  const pets = [];
  for (const s of spells) {
    if (set.has(s.id)) {
      pets.push(s);
      found.add(s.id);
    } else rest.push(s);
  }
  for (const id of set) if (!found.has(id)) throw new Error(`HUNTER: Tierfaehigkeit ${id} steht nicht in Hunter.lua`);
  if (rest.length < LIMITS.perClassMin) throw new Error(`HUNTER: unplausible Anzahl Klassenzauber (${rest.length})`);
  return { spells: rest, pets };
}

/** QuestSpells.lua -> { [KLASSE]: [{ id, level, races, quests, areas }] } */
export function parseQuestSpells(text) {
  const { fields, locals } = readAssignments(text);
  const qs = fields["wt.QuestSpells"] ?? locals.QuestSpells;
  if (!qs || typeof qs !== "object" || Array.isArray(qs)) throw new Error("QuestSpells fehlt");
  const out = {};
  for (const cls of Object.keys(qs).sort()) {
    if (!CLASSES.includes(cls)) throw new Error(`QuestSpells: unbekannte Klasse ${cls}`);
    const list = [];
    for (const idText of Object.keys(qs[cls]).sort((a, b) => Number(a) - Number(b))) {
      const id = Number(idText);
      if (!isId(id)) throw new Error(`QuestSpells ${cls}: ungueltige ID`);
      const variants = qs[cls][idText];
      if (!Array.isArray(variants)) throw new Error(`QuestSpells ${cls} ${id}: keine Liste`);
      for (const v of variants) {
        const level = v.level ?? 0;
        if (!Number.isInteger(level) || level < 0 || level > LIMITS.level) throw new Error(`QuestSpells ${cls} ${id}: Stufe`);
        const areas = v.area !== undefined ? [v.area] : idList(v.areas, `QuestSpells ${cls} ${id}`);
        list.push({ id, level, races: idList(v.races, `QuestSpells ${cls} ${id}`), quests: idList(v.quests, `QuestSpells ${cls} ${id}`),
          areas: idList(areas, `QuestSpells ${cls} ${id}`) });
      }
    }
    out[cls] = list;
  }
  return out;
}

// ---------------------------------------------------------------- Ausgabe

const field = (v) => (v === null || v === undefined ? "" : String(v));
export function spellLines(spells) {
  return spells.map((s) => [s.level, s.id, s.cost, s.req.join(","), field(s.talent), s.faction, field(s.race)].join("\t")).join("\n");
}
export function questLines(list) {
  return list.map((q) => [q.id, q.level, q.races.join(","), q.quests.join(","), q.areas.join(",")].join("\t")).join("\n");
}
function luaString(s) {
  if (!/^[0-9,;\tAH\n]*$/.test(s)) throw new Error("Ausgabe enthaelt unerwartete Zeichen");
  return '"' + s.replace(/\t/g, "\\t").replace(/\n/g, "\\n") + '"';
}

export function render({ classes, quests, commit, pinned, pets = { HUNTER: [] } }) {
  const lines = [];
  lines.push("-- Lehrplan data: class trainer spells for WoW Forever. GENERATED by scripts/build-trainer-data.mjs, do not edit by hand.");
  lines.push("-- Source: \"What's Training?\" by Sveng/fusionpit, branch \"master\", Classes/Camelot/*.lua (incl. HunterPets.lua)");
  lines.push(`-- (${SOURCE_URL}), commit ${commit}${pinned ? "" : " (UNPINNED: source differs from the pinned hashes)"}.`);
  lines.push("-- Licensed under the MIT License, Copyright (c) 2019 - full text in data/LICENSE-WhatsTraining.txt (unchanged).");
  lines.push("-- Changes: converted to a compact text format (one line per spell); nothing added.");
  lines.push("-- spells[CLASS]: \"<level>\\t<spellID>\\t<copper>\\t<required ids,>\\t<talent id>\\t<faction A|H>\\t<race id>\"");
  lines.push("-- pets.HUNTER: hunter pet abilities (Beast Training), same line format as spells; not part of spells.HUNTER");
  lines.push("-- groups[CLASS]: ranks that replace each other in the spellbook, \"id,id;id,id\"");
  lines.push("-- quests[CLASS]: spells from class quests, \"<spellID>\\t<level>\\t<race ids,>\\t<quest ids,>\\t<area ids,>\"");
  lines.push("local _, ns = ...");
  lines.push("ns.TrainerSpells = {");
  lines.push(`  source = "WhatsTraining", commit = "${commit.slice(0, 12)}", date = "${PINNED_DATE}", license = "MIT",`);
  lines.push("  spells = {");
  for (const cls of CLASSES) lines.push(`    ${cls} = ${luaString(spellLines(classes[cls].spells))},`);
  lines.push("  },");
  lines.push("  pets = {");
  lines.push(`    HUNTER = ${luaString(spellLines(pets.HUNTER))},`);
  lines.push("  },");
  lines.push("  groups = {");
  for (const cls of CLASSES) {
    const g = classes[cls].groups.map((x) => x.join(",")).join(";");
    if (g) lines.push(`    ${cls} = ${luaString(g)},`);
  }
  lines.push("  },");
  lines.push("  quests = {");
  for (const cls of CLASSES) if (quests[cls] && quests[cls].length) lines.push(`    ${cls} = ${luaString(questLines(quests[cls]))},`);
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
  const classes = {};
  for (const cls of CLASSES) {
    const f = read(`Classes/Camelot/${FILE_OF[cls]}.lua`);
    pinned = pinned && f.ok;
    classes[cls] = parseClassFile(f.text, cls);
  }
  const hp = read("Classes/Camelot/HunterPets.lua");
  pinned = pinned && hp.ok;
  const split = splitPets(classes.HUNTER.spells, parsePetIds(hp.text));
  classes.HUNTER = { ...classes.HUNTER, spells: split.spells };
  const pets = { HUNTER: split.pets };
  const q = read("Classes/Camelot/QuestSpells.lua");
  pinned = pinned && q.ok;
  return { license: license.text, classes, pets, quests: parseQuestSpells(q.text), pinned };
}

export async function build({ src, out = DEFAULT_OUT, unpinned = false }) {
  const s = readSources(src, { unpinned });
  const text = render({ classes: s.classes, pets: s.pets, quests: s.quests, commit: PINNED_COMMIT, pinned: s.pinned });
  if (Buffer.byteLength(text) > LIMITS.outBytes) throw new Error(`Ergebnis zu gross (${Buffer.byteLength(text)} B)`);
  await mkdir(out, { recursive: true });
  await writeAtomic(path.join(out, "TrainerSpells.lua"), text);
  await writeAtomic(path.join(out, "LICENSE-WhatsTraining.txt"), s.license.endsWith("\n") ? s.license : s.license + "\n");
  const counts = Object.fromEntries(CLASSES.map((c) => [c, s.classes[c].spells.length]));
  counts.HUNTER_PETS = s.pets.HUNTER.length;
  return { counts, bytes: Buffer.byteLength(text), pinned: s.pinned, out };
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
  console.log(`TrainerSpells.lua: ${r.bytes} B -> ${r.out}`);
  return r;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).catch((err) => {
    console.error(`FEHLER: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  });
}
