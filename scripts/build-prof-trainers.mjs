// Erzeugt addon/InkAndEmbers_Data/ProfTrainers.lua (Werkauftrag, Etappe W1): Berufslehrer mit Kartenpunkten fuer den
// Lehrer-Schritt der Route (Wegpunkt, naechster Lehrer). Daten: QuestieDB (Questie-Team und Beitragende), nur lesend.
//
// Aufruf:  node scripts/build-prof-trainers.mjs [--questie <QuestieDB_Forever.toc>] [--forever <ordner>] [--out <ordner>] [--help]
//   --questie  QuestieDB im Forever-Stand (Standard wie scripts/build-todo-data.mjs: data-capture\questiedb-release, sonst
//              CHRONICLE_QUESTIE_TOC, sonst WOW_DIR aus Umgebung/.env)
//   --forever  Forever-Datenbank-Dump (zones.json fuer Gebiet -> uiMapID, l10n\deDE\search.json fuer deutsche Namen).
//              Standard: $CHRONICLE_FOREVER_DB
//   --out      Zielordner. Standard: addon\InkAndEmbers_Data (die TOC dort ist fest und nennt ProfTrainers.lua)
// Exit-Codes: 0 = ok, 1 = Fehler (Quelle fehlt/unlesbar, Ergebnis unplausibel klein oder zu gross, unbekannte Option)
//
// Auswahl: NPCs mit Lehrer-Flag (npcFlags & 16), deren Untertitel (subName) einen Beruf nennt ("Journeyman Blacksmith",
// "Mining Trainer", "Expert Tailor", ...). Klassen-, Reit-, Tier- und Waffenlehrer fallen heraus. Rangstufe aus dem Untertitel:
// Junior/Apprentice 75, Journeyman 150, Expert 225, Artisan/Master/Superior 300, sonst 0 (unbekannt). Spezialisierungs-Lehrer
// (Drachenschuppen, Goblin, Waffenschmied, ...) bekommen die Art "s" und werden im Spiel nur auf Wunsch gewaehlt.
// Ergebnis (reproduzierbar: nach NPC-ID sortiert, ohne Zeitstempel):
//   EveNChronicleProfTrainerData = { source, version, trainers = "<zeilen>" }
//   je Lehrer "\n<npcID>\t<skillLine>\t<stufe>\t<fraktion A|H|leer>\t<art s|leer>\t<uiMapID>:<x>,<y>;...|<uiMapID>:...\t<Name de>\t<Name en>"
//   (x/y 0..100 mit 1 Nachkommastelle, hoechstens 4 Punkte je Karte; Instanzen und unbekannte Gebiete ohne Punkt)
//
// Sicherheit: reine Datenauswertung lokaler Dateien, kein Netz. Dekodierung und Namensreinigung wie build-todo-data.mjs
// (cleanName, lange Lua-Klammer); geschrieben wird nur in den Zielordner (atomar).

import { existsSync, readFileSync } from "node:fs";
import { mkdir, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { cleanName, defaultSources, luaLong, openQuestie, parseArgs, stampedMinContract } from "./build-todo-data.mjs";
import { createZoneResolver, formatLocations, spawnsToMaps } from "./build-quest-data.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const DEFAULT_OUT = path.join(ROOT, "addon", "InkAndEmbers_Data");
export const OUT_FILE = "ProfTrainers.lua";
export const GLOBAL = "EveNChronicleProfTrainerData";
export const MIN_TRAINERS = 60;
export const MAX_BYTES = 120 * 1024;
const TRAINER_FLAG = 16;
// QuestieDB-Feldnummern (src/meta/npcMeta.lua): wie build-todo-data.mjs, dazu subName 14
const NPC = { name: 1, spawns: 7, friendlyToFaction: 13, subName: 14, npcFlags: 15 };

// Untertitel -> Berufslinie (skillLine-ID); Reihenfolge zaehlt (erste Regel gewinnt)
export const PROFESSION_RULES = [
  [/\bfirst aid\b|\bphysician\b|\btrauma surgeon\b|\bmedic\b/i, 129],
  [/blacksmith|armorsmith|weaponsmith|armor crafter|weapon crafter/i, 164],
  [/leatherwork|leathercraft/i, 165],
  [/tailor/i, 197],
  [/alchemi|alchemy/i, 171],
  [/engineer/i, 202],
  [/enchant/i, 333],
  [/herbalis/i, 182],
  [/\bmining\b|\bminer\b/i, 186],
  [/skinn/i, 393],
  [/\bcook\b|cooking|butcher/i, 185],
  [/fisher|fishing/i, 356],
];
const SPECIAL = /dragonscale|elemental|tribal|goblin|gnome|gnomish|shadoweave|mooncloth|spellfire|armorsmith|weaponsmith|armor crafter|weapon crafter/i;

/** Untertitel -> { line, cap, special } oder null (kein Berufslehrer) */
export function professionOf(subName) {
  if (typeof subName !== "string" || subName.trim() === "") return null;
  const s = subName.trim();
  if (/riding|pet trainer|weapon master|portal/i.test(s)) return null;
  const rule = PROFESSION_RULES.find(([re]) => re.test(s));
  if (!rule) return null;
  let cap = 0;
  if (/\b(junior|apprentice)\b/i.test(s)) cap = 75;
  else if (/\bjourneyman\b/i.test(s)) cap = 150;
  else if (/\bexpert\b/i.test(s)) cap = 225;
  else if (/\b(artisan|master|grand master|superior)\b/i.test(s)) cap = 300;
  return { line: rule[1], cap, special: SPECIAL.test(s) };
}

const int = (v) => (Number.isInteger(v) ? v : typeof v === "number" && Number.isFinite(v) ? Math.round(v) : undefined);

/** QuestieDB + Zonen -> Liste { id, line, cap, faction, special, loc, name, en } */
export function buildProfTrainers(q, zones, deName = () => undefined) {
  const out = [];
  const stats = { trainers: 0, noProfession: 0, noPoint: 0, noName: 0 };
  for (const id of [...q.ids("Npc")].sort((a, b) => a - b)) {
    const flags = int(q.field("Npc", id, NPC.npcFlags)) ?? 0;
    if ((flags & TRAINER_FLAG) === 0) continue;
    stats.trainers++;
    const prof = professionOf(q.field("Npc", id, NPC.subName));
    if (!prof) { stats.noProfession++; continue; }
    const en = cleanName(q.field("Npc", id, NPC.name));
    if (!en) { stats.noName++; continue; }
    const maps = spawnsToMaps(q.field("Npc", id, NPC.spawns), zones);
    const loc = formatLocations(maps);
    if (!loc) { stats.noPoint++; continue; }
    const react = q.field("Npc", id, NPC.friendlyToFaction);
    const faction = react === "A" || react === "H" ? react : "";
    const de = cleanName(deName(id)) || cleanName(q.deDE("Npc", id)) || en;
    out.push({ id, line: prof.line, cap: prof.cap, faction, special: prof.special, loc, name: de, en });
  }
  return { list: out, stats };
}

export function trainerBlob(list) {
  return list.map((r) => `\n${r.id}\t${r.line}\t${r.cap}\t${r.faction}\t${r.special ? "s" : ""}\t${r.loc}\t${r.name}\t${r.en}`).join("") + "\n";
}

export function renderFile(list, version) {
  const v = cleanName(version) || "?";
  return "-- InkAndEmbers_Data: profession trainers with map points. GENERATED by scripts/build-prof-trainers.mjs, do not edit by hand.\n" +
    "-- License: GPL-3.0 (see LICENSE and LICENSE-NOTE.md). Data: QuestieDB (Questie team and contributors, https://github.com/Questie/QuestieDB; license status: https://github.com/Questie/QuestieDB/blob/master/LICENSE.md); reformatted by scripts/build-prof-trainers.mjs. Game world content (c) Blizzard Entertainment.\n" +
    `-- Sources: QuestieDB ${v}, Forever database (data.morthen.net, zones and German names)\n` +
    "-- Loaded on demand only (LoadOnDemand, same load as the to-do lists) by journal/model/LehrerOrte.lua of the main addon.\n" +
    "-- trainers: per trainer \"\\n<npcID>\\t<skillLine>\\t<cap>\\t<faction A|H|>\\t<kind s|>\\t<uiMapID>:<x>,<y>;...|...\\t<name de>\\t<name en>\"\n" +
    `-- Trainers: ${list.length}\n` +
    `${GLOBAL} = {\n  source = "QuestieDB", version = ${JSON.stringify(v)},\n  trainers = ${luaLong(trainerBlob(list))},\n}\n`;
}

async function writeAtomic(file, text) {
  const tmp = `${file}.tmp`;
  await writeFile(tmp, text, "utf8");
  await rename(tmp, file);
}

export async function build({ questie, forever, out, minTrainers = MIN_TRAINERS }) {
  const q = openQuestie(readFileSync(questie, "utf8"), { minSupportedContract: stampedMinContract(questie) });
  const zones = createZoneResolver(JSON.parse(readFileSync(path.join(forever, "zones.json"), "utf8")));
  const deFile = path.join(forever, "l10n", "deDE", "search.json");
  const de = existsSync(deFile) ? JSON.parse(readFileSync(deFile, "utf8")) : {};
  const deName = (id) => (de?.npc && typeof de.npc[String(id)] === "string" ? de.npc[String(id)] : undefined);
  const r = buildProfTrainers(q, zones, deName);
  if (r.list.length < minTrainers) throw new Error(`Ergebnis unplausibel klein (${r.list.length} Berufslehrer, erwartet mindestens ${minTrainers})`);
  const text = renderFile(r.list, q.version);
  if (Buffer.byteLength(text) > MAX_BYTES) throw new Error(`Datei zu gross (${Buffer.byteLength(text)} B, Grenze ${MAX_BYTES} B)`);
  await mkdir(out, { recursive: true });
  await writeAtomic(path.join(out, OUT_FILE), text);
  return { ...r, bytes: Buffer.byteLength(text), version: q.version };
}

export async function main(argv) {
  const opts = parseArgs(argv);
  if (opts.help) {
    console.log("InkAndEmbers: Berufslehrer-Datei ProfTrainers.lua erzeugen\n\nAufruf:\n  node scripts/build-prof-trainers.mjs [--questie <toc>] [--forever <ordner>] [--out <ordner>]");
    return null;
  }
  const def = defaultSources();
  const questie = opts.questie ?? def.questie.find((p) => existsSync(p));
  if (!questie || !existsSync(questie)) throw new Error("QuestieDB_Forever.toc nicht gefunden (--questie, CHRONICLE_QUESTIE_TOC oder WOW_DIR setzen).");
  const forever = opts.forever ?? def.forever;
  if (!forever || !existsSync(path.join(forever, "zones.json"))) throw new Error(`Forever-Datenbank nicht gefunden (${forever ?? "nicht konfiguriert"}); --forever oder CHRONICLE_FOREVER_DB setzen.`);
  const out = opts.out ?? DEFAULT_OUT;
  const r = await build({ questie, forever, out });
  console.log(`QuestieDB ${r.version}: ${r.list.length} Berufslehrer (Lehrer gesamt ${r.stats.trainers}, ohne Beruf ${r.stats.noProfession}, ohne Kartenpunkt ${r.stats.noPoint}), ${r.bytes} B -> ${path.join(out, OUT_FILE)}`);
  return r;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).catch((err) => {
    console.error(`FEHLER: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  });
}
