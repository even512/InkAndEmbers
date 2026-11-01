// Erzeugt das Datenaddon InkAndEmbers_Data (To-Do-Ziele, Z2): Gegnerliste und Gegenstandsliste.
//
// Aufruf:  node scripts/build-todo-data.mjs [--questie <QuestieDB_Forever.toc>] [--forever <ordner>] [--out <ordner>] [--help]
//   --questie  QuestieDB im Forever-Stand ("baked" TOC, Vertragsversion 4). Standard: erste vorhandene von
//              $CHRONICLE_QUESTIE_TOC, <WOW_DIR>\_classic_beta_\...\QuestieDB_Forever.toc, <WOW_DIR>\_forever_\...\QuestieDB_Forever.toc
//              (WOW_DIR und CHRONICLE_QUESTIE_TOC aus der Umgebung oder .env)
//   --forever  Forever-Datenbank (Dump von data.morthen.net, siehe README "Questdaten neu erzeugen"). Standard: $CHRONICLE_FOREVER_DB
//   --out      Zielordner. Standard: addon\InkAndEmbers_Data (dort liegt auch die feste TOC)
// Exit-Codes: 0 = ok, 1 = Fehler (Quelle fehlt/unlesbar, Ergebnis unplausibel oder zu gross, unbekannte Option)
//
// Ergebnis (reproduzierbar: sortiert, ohne Zeitstempel; nur aus den lokalen Quellen):
//   Npcs.lua   EveNChronicleTodoData.npc   = eine Zeichenkette, je Gegner "\n<id>\t<Name>\t<min>\t<max>\t<rang>\t<zone>"
//              (max leer = wie min; rang "" normal, "e" Elite, "r" selten, "R" selten-Elite, "b" Boss; zone = Gebiets-ID oder leer)
//   Items.lua  EveNChronicleTodoData.item  = eine Zeichenkette, je Gegenstand "\n<id>\t<Name>\t<qualitaet>" (qualitaet leer = unbekannt)
//   Zones.lua  EveNChronicleTodoData.zones = { [gebietsID] = "Name", ... } (nur Gebiete, die in der Gegnerliste vorkommen)
//   Namen: deDE bevorzugt (Forever-Datenbank, dann QuestieDB-Uebersetzung), sonst Englisch. Sortiert nach Name, dann ID.
//   Englische Namen (nur fuer englische Addon-Sprache, siehe journal/model/TodoData.lua): je Liste eine zweite Datei,
//   die nur laeuft, wenn das Hauptaddon vor dem Laden EveNChronicleTodoLang = "enUS" gesetzt hat:
//   NpcsEn.lua    EveNChronicleTodoData.npcEn    = je Gegner "\n<id>\t<englischer Name>", sortiert nach dem englischen Namen
//   ItemsEn.lua   EveNChronicleTodoData.itemEn   = je Gegenstand "\n<id>\t<englischer Name>", sortiert nach dem englischen Namen
//   ZonesEn.lua   EveNChronicleTodoData.zonesEn  = { [gebietsID] = "Name", ... } (nur Gebiete, deren englischer Name vom deutschen abweicht)
//   Stufe, Rang und Gebiet stehen nur in der deutschen Liste (gleiche IDs); Verknuepfung immer ueber die ID.
// Gegner-Filter (Heuristik, Recherche "To-Do-Gegnerliste"): mit Spawn, Stufe (max) 1..MAX_LEVEL, nicht freundlich zu beiden Fraktionen,
//   keine Dienst-Flags (alles ausser Gossip: Questgeber, Haendler, Lehrer, Flugmeister, ...), keine Platzhalter-Namen.
// Gegenstands-Filter: Beute (Gegner, Objekt, Behaelter) oder Questbelohnung laut QuestieDB, Name bekannt.
//
// Sicherheit: reine Datenauswertung lokaler Dateien, kein Netz. Fremddaten werden mit Grenzen dekodiert (CBOR-Tiefe/-Groesse,
// Base64/zlib nur ueber Node), Namen von Steuerzeichen, Tabs, Zeilenumbruechen und "|" (WoW-Escape) befreit; die Lua-Ausgabe
// nutzt lange Klammern mit einer Stufe, die im Inhalt nicht vorkommt. Geschrieben wird nur in den Zielordner (atomar je Datei).

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { mkdir, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { inflateSync } from "node:zlib";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const DATA_ADDON = "InkAndEmbers_Data";
const DEFAULT_OUT = path.join(ROOT, "addon", DATA_ADDON);
const QUESTIE_REL = path.join("Interface", "AddOns", "QuestieDB", "QuestieDB_Forever.toc");

export const MAX_LEVEL = 62;
export const MAX_LIST_BYTES = 600 * 1024; // je Liste (Datei)
const MAX_NAME_BYTES = 80;
const SERVICE_FLAGS_MASK = ~1; // alle NPC-Flags ausser Gossip (1)
const PLACEHOLDER = /\(Only GM|\bUNUSED\b|\bDND\b|\bzzOLD|\[PH\]|^\[|\bTEST\b|\bTrigger\b|\bInvisible\b|\bDummy\b|\bDEPRECATED\b|\bNYI\b/i;

// QuestieDB-Feldnummern (src/meta/npcMeta.lua, itemMeta.lua)
const NPC = { name: 1, minLevel: 4, maxLevel: 5, rank: 6, spawns: 7, zoneID: 9, friendlyToFaction: 13, npcFlags: 15 };
const NPC_TABLE_FIELDS = new Set([7, 8, 10, 11]);
const ITEM = { name: 1, npcDrops: 2, objectDrops: 3, itemDrops: 4, questRewards: 6 };
const ITEM_TABLE_FIELDS = new Set([2, 3, 4, 6, 14, 15]);
// Tabellen-Felder von Quest/Objekt (questMeta/objectMeta; genutzt von scripts/build-quest-data.mjs)
const QUEST_TABLE_FIELDS = new Set([2, 3, 8, 9, 10, 12, 13, 14, 15, 16, 18, 19, 20, 21, 26, 28, 29, 35]);
const OBJECT_TABLE_FIELDS = new Set([2, 3, 4, 7]);
// QuestieDB-Rang (0 normal, 1 Elite, 2 selten-Elite, 3 Boss, 4 selten) bzw. Forever-Datenbank-Text -> Kurzzeichen
const RANK_NUM = { 0: "", 1: "e", 2: "R", 3: "b", 4: "r" };
const RANK_TEXT = { Normal: "", Elite: "e", "Rare Elite": "R", Boss: "b", Rare: "r" };

const HELP = `InkAndEmbers: Datenaddon ${DATA_ADDON} (Gegner- und Gegenstandsliste) erzeugen

Aufruf:
  node scripts/build-todo-data.mjs [--questie <QuestieDB_Forever.toc>] [--forever <ordner>] [--out <ordner>]

Quellen (nur lokal, nichts wird heruntergeladen):
  --questie   QuestieDB im Forever-Stand (Standard: CHRONICLE_QUESTIE_TOC, sonst WOW_DIR aus Umgebung/.env)
  --forever   Forever-Datenbank-Dump (Standard: CHRONICLE_FOREVER_DB aus Umgebung/.env)
  --out       Zielordner (Standard: addon\\${DATA_ADDON})
`;

// ---------------------------------------------------------------- Argumente / Pfade

export function parseArgs(argv) {
  const out = { help: false, questie: null, forever: null, out: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--help" || a === "-h") out.help = true;
    else if (a === "--questie" || a === "--forever" || a === "--out") {
      const v = argv[++i];
      if (!v || v.startsWith("--")) throw new Error(`Option ${a} braucht einen Pfad.`);
      if (v.includes("\0")) throw new Error(`Option ${a}: ungueltiger Pfad.`);
      out[a.slice(2)] = path.resolve(v);
    } else throw new Error(`Unbekannte Option bzw. unerwartetes Argument: ${a}\nHilfe: node scripts/build-todo-data.mjs --help`);
  }
  return out;
}

/** Konfigurationswert: Umgebungsvariable, sonst Zeile NAME=Wert aus der lokalen .env (nur feste Namen, siehe .env.example); "" wenn nicht gesetzt */
export function configValue(name) {
  if (!/^[A-Z][A-Z0-9_]*$/.test(name)) throw new Error(`Ungueltiger Konfigurationsname: ${name}`);
  const fromEnv = process.env[name];
  if (typeof fromEnv === "string" && fromEnv.trim() !== "") return fromEnv.trim();
  const envFile = path.join(ROOT, ".env");
  if (!existsSync(envFile)) return "";
  const re = new RegExp(`^\s*${name}\s*=\s*(.*?)\s*$`);
  for (const line of readFileSync(envFile, "utf8").split(/\r?\n/)) {
    const m = re.exec(line);
    if (m) return m[1].replace(/^"(.*)"$/, "$1").replace(/^'(.*)'$/, "$1");
  }
  return "";
}

/** Absoluter Pfad aus der Konfiguration (Umgebung/.env), sonst null */
export function configPath(name) {
  const v = configValue(name);
  return v && !v.includes("\0") && path.isAbsolute(v) ? path.resolve(v) : null;
}

/** Standard-Quellen ohne feste Verzeichnisse: CHRONICLE_QUESTIE_TOC, CHRONICLE_FOREVER_DB, WOW_DIR (Umgebung oder .env). forever = null, wenn nicht gesetzt. */
export function defaultSources() {
  const questie = [];
  const toc = configPath("CHRONICLE_QUESTIE_TOC");
  if (toc) questie.push(toc);
  const wow = configValue("WOW_DIR");
  if (wow && path.isAbsolute(wow)) {
    questie.push(path.join(wow, "_classic_beta_", QUESTIE_REL), path.join(wow, "_forever_", QUESTIE_REL));
  }
  return { questie, forever: configPath("CHRONICLE_FOREVER_DB") };
}

// ---------------------------------------------------------------- CBOR (begrenzt) und TOC-Metadaten

const CBOR_LIMITS = { depth: 32, items: 2_000_000, bytes: 64 * 1024 * 1024 };

function halfToNumber(h) {
  const s = h & 0x8000 ? -1 : 1;
  const e = (h >> 10) & 0x1f;
  const f = h & 0x3ff;
  if (e === 0) return s * 2 ** -14 * (f / 1024);
  if (e === 31) return f ? NaN : s * Infinity;
  return s * 2 ** (e - 15) * (1 + f / 1024);
}

/** CBOR dekodieren: Zahlen, Texte/Bytes (als UTF-8-Text), Arrays, Maps (Objekt ohne Prototyp), true/false/null. */
export function decodeCbor(buf) {
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  let pos = 0;
  let count = 0;
  const need = (n) => {
    if (pos + n > buf.length) throw new Error("CBOR: Daten zu kurz");
  };
  const readLen = (info) => {
    if (info < 24) return info;
    if (info === 24) { need(1); return buf[pos++]; }
    if (info === 25) { need(2); const v = dv.getUint16(pos); pos += 2; return v; }
    if (info === 26) { need(4); const v = dv.getUint32(pos); pos += 4; return v; }
    if (info === 27) {
      need(8);
      const v = dv.getUint32(pos) * 2 ** 32 + dv.getUint32(pos + 4);
      pos += 8;
      return v;
    }
    throw new Error("CBOR: unbestimmte Laenge wird nicht unterstuetzt");
  };
  const item = (depth) => {
    if (depth > CBOR_LIMITS.depth) throw new Error("CBOR: zu tief verschachtelt");
    if (++count > CBOR_LIMITS.items) throw new Error("CBOR: zu viele Elemente");
    need(1);
    const ib = buf[pos++];
    const major = ib >> 5;
    const info = ib & 31;
    if (major === 7) {
      if (info === 20) return false;
      if (info === 21) return true;
      if (info === 22 || info === 23) return null;
      if (info === 25) { need(2); const v = halfToNumber(dv.getUint16(pos)); pos += 2; return v; }
      if (info === 26) { need(4); const v = dv.getFloat32(pos); pos += 4; return v; }
      if (info === 27) { need(8); const v = dv.getFloat64(pos); pos += 8; return v; }
      if (info < 20) return null;
      throw new Error("CBOR: unbekannter einfacher Wert");
    }
    const len = readLen(info);
    switch (major) {
      case 0: return len;
      case 1: return -1 - len;
      case 2:
      case 3: {
        if (len > CBOR_LIMITS.bytes) throw new Error("CBOR: Zeichenkette zu gross");
        need(len);
        const s = buf.toString("utf8", pos, pos + len);
        pos += len;
        return s;
      }
      case 4: {
        if (len > CBOR_LIMITS.items) throw new Error("CBOR: Array zu gross");
        const arr = new Array(len);
        for (let i = 0; i < len; i++) arr[i] = item(depth + 1);
        return arr;
      }
      case 5: {
        if (len > CBOR_LIMITS.items) throw new Error("CBOR: Map zu gross");
        const obj = Object.create(null);
        for (let i = 0; i < len; i++) {
          const k = item(depth + 1);
          obj[String(k)] = item(depth + 1);
        }
        return obj;
      }
      case 6: return item(depth + 1); // Tag: Inhalt
      default: throw new Error("CBOR: unbekannter Typ");
    }
  };
  return item(0);
}

/** "## Schluessel: Wert"-Zeilen der TOC als Map; Teilzeilen ("~n~" + Schluessel-1..n) werden zusammengesetzt. */
export function parseTocMeta(text) {
  const raw = new Map();
  for (const line of text.split(/\r?\n/)) {
    if (!line.startsWith("## ")) continue;
    const i = line.indexOf(":", 3);
    if (i < 0) continue;
    raw.set(line.slice(3, i).trim(), line.slice(i + 1).trim());
  }
  const get = (key) => {
    const v = raw.get(key);
    if (v === undefined) return undefined;
    const m = /^~(\d+)~$/.exec(v);
    if (!m) return v;
    const parts = [];
    for (let i = 1; i <= Number(m[1]); i++) {
      const p = raw.get(`${key}-${i}`);
      if (p === undefined) throw new Error(`QuestieDB: Teil ${i} von ${key} fehlt`);
      parts.push(p);
    }
    return parts.join("");
  };
  return { raw, get };
}

const b64 = (s) => Buffer.from(s, "base64");
const decodeRow = (s) => decodeCbor(b64(s));
const decodeBlock = (s) => decodeCbor(inflateSync(b64(s), { maxOutputLength: CBOR_LIMITS.bytes }));

const asList = (v) => (Array.isArray(v) ? v : v && typeof v === "object" ? Object.values(v) : []);
/** Spalte (Array oder Map Position->Wert, 1-basiert wie Lua) an Position p */
const colAt = (col, p) => (Array.isArray(col) ? col[p - 1] : col && typeof col === "object" ? col[String(p)] : undefined);

/** Lesezugriff auf eine QuestieDB-"baked"-TOC: ids(kind), field(kind, id, nr), deDE(kind, id). */
export function openQuestie(text) {
  const meta = parseTocMeta(text);
  if (meta.get("X-Contract-Version") !== "4") throw new Error(`QuestieDB: Vertragsversion ${meta.get("X-Contract-Version") ?? "?"} statt 4`);
  if (meta.get("X-Flavor") !== "Forever") throw new Error(`QuestieDB: Variante ${meta.get("X-Flavor") ?? "?"} statt Forever`);
  const tableFields = { Npc: NPC_TABLE_FIELDS, Item: ITEM_TABLE_FIELDS, Quest: QUEST_TABLE_FIELDS, Object: OBJECT_TABLE_FIELDS };
  const stats = { badValues: 0 };
  const idCache = {};
  const l10nCache = {};
  const ids = (kind) => {
    if (!idCache[kind]) {
      const enc = meta.get(`X-${kind}-IDS`);
      if (!enc) throw new Error(`QuestieDB: X-${kind}-IDS fehlt`);
      idCache[kind] = asList(decodeBlock(enc)).filter((x) => Number.isInteger(x));
    }
    return idCache[kind];
  };
  const safe = (fn) => {
    try {
      return fn();
    } catch {
      stats.badValues++;
      return undefined;
    }
  };
  const field = (kind, id, nr) => {
    const s = meta.raw.get(`X-${kind}-${id}-S`);
    if (s === undefined) return undefined;
    const row = safe(() => decodeRow(s));
    if (!row || typeof row !== "object") return undefined;
    if (!tableFields[kind].has(nr)) return row[String(nr)] ?? undefined;
    const p = row.p;
    if (typeof p !== "number" || Math.floor(p / 2 ** (nr - 1)) % 2 !== 1) return undefined;
    const t = meta.get(`X-${kind}-${id}-${nr}`);
    return t === undefined ? undefined : safe(() => decodeRow(t));
  };
  const deDE = (kind, id) => {
    if (!(kind in l10nCache)) {
      const enc = meta.get(`X-l10n-deDE-${kind}`);
      const block = enc ? safe(() => decodeBlock(enc)) : undefined;
      const col = block ? colAt(block, 1) : undefined; // Spalte 1 = name (src/l10n/overlay.lua)
      const pos = new Map();
      ids(kind).forEach((x, i) => pos.set(x, i + 1));
      l10nCache[kind] = { col, pos };
    }
    const c = l10nCache[kind];
    const p = c.pos.get(id);
    const v = p && c.col ? colAt(c.col, p) : undefined;
    return typeof v === "string" && v !== "" ? v : undefined;
  };
  return { version: meta.get("Version") ?? "?", ids, field, deDE, stats, has: (kind, id) => meta.raw.has(`X-${kind}-${id}-S`) };
}

// ---------------------------------------------------------------- Forever-Datenbank

function readJson(file) {
  return JSON.parse(readFileSync(file, "utf8"));
}

/** Forever-Datenbank: npc/item-Eintraege (en), deDE-Namen, Zonen, Spawn-Kenntnis aus npc/*.json */
export function openForever(dir) {
  const search = readJson(path.join(dir, "search.json"));
  const de = readJson(path.join(dir, "l10n", "deDE", "search.json"));
  const zonesEn = readJson(path.join(dir, "zones.json"));
  const zonesDe = existsSync(path.join(dir, "l10n", "deDE", "zones.json")) ? readJson(path.join(dir, "l10n", "deDE", "zones.json")) : {};
  if (!Array.isArray(search?.npc) || !Array.isArray(search?.item)) throw new Error("Forever-Datenbank: search.json ohne npc/item");
  const npc = new Map();
  for (const r of search.npc) {
    if (!Array.isArray(r) || !Number.isInteger(r[0])) continue;
    npc.set(r[0], { name: r[1], min: r[3], max: r[4], react: r[5], zone: r[6], rank: r[7], flags: r[8] });
  }
  const item = new Map();
  for (const r of search.item) {
    if (!Array.isArray(r) || !Number.isInteger(r[0])) continue;
    item.set(r[0], { name: r[1], quality: r[2] });
  }
  const spawns = new Map(); // id -> hat Spawn
  const npcDir = path.join(dir, "npc");
  if (existsSync(npcDir)) {
    for (const f of readdirSafe(npcDir)) {
      if (!/^\d+\.json$/.test(f)) continue;
      const data = readJson(path.join(npcDir, f));
      for (const [k, v] of Object.entries(data ?? {})) {
        const has = v && typeof v.spawns === "object" && Object.values(v.spawns).some((pts) => Array.isArray(pts) && pts.length > 0);
        spawns.set(Number(k), has);
      }
    }
  }
  const zoneName = (id) => {
    const deName = zonesDe?.[String(id)];
    const en = zonesEn?.zones?.[String(id)]?.name;
    return typeof deName === "string" && deName ? deName : typeof en === "string" ? en : undefined;
  };
  const zoneNameEn = (id) => {
    const en = zonesEn?.zones?.[String(id)]?.name;
    return typeof en === "string" ? en : undefined;
  };
  return { npc, item, deNpc: de?.npc ?? {}, deItem: de?.item ?? {}, spawns, zoneName, zoneNameEn };
}

/** Dateinamen eines Ordners (nur echte Dateien, sortiert) */
function readdirSafe(dir) {
  return readdirSync(dir, { withFileTypes: true }).filter((e) => e.isFile()).map((e) => e.name).sort();
}

// ---------------------------------------------------------------- Zusammenfuehren

/** Name saeubern: keine Steuerzeichen, Tabs, Zeilenumbrueche, kein "|"; Leerraum zusammengezogen, Laenge begrenzt. */
export function cleanName(s) {
  if (typeof s !== "string") return "";
  let v = s.replace(/[\u0000-\u001f\u007f|\u200b-\u200f\u2028\u2029\ufeff]/g, " ").replace(/\s+/g, " ").trim();
  while (Buffer.byteLength(v, "utf8") > MAX_NAME_BYTES) v = v.slice(0, -1);
  return v;
}

/** Suchschluessel wie TodoData.lua: klein, ae/oe/ue/ss statt Umlaut */
export function foldKey(s) {
  return s.toLowerCase().replace(/ä/g, "ae").replace(/ö/g, "oe").replace(/ü/g, "ue").replace(/ß/g, "ss");
}

const int = (v) => (Number.isInteger(v) ? v : typeof v === "number" && Number.isFinite(v) ? Math.round(v) : undefined);

function hasSpawn(v) {
  if (!v || typeof v !== "object") return false;
  return Object.values(v).some((pts) => asList(pts).length > 0);
}

export function buildNpcs(q, f) {
  const ids = new Set([...q.ids("Npc"), ...f.npc.keys()]);
  const out = [];
  const st = { total: ids.size, de: 0, skipped: { friendly: 0, flags: 0, spawn: 0, level: 0, name: 0 } };
  for (const id of [...ids].sort((a, b) => a - b)) {
    const m = f.npc.get(id);
    const qName = q.field("Npc", id, NPC.name);
    const en = cleanName(m?.name ?? qName);
    if (!en || PLACEHOLDER.test(en)) { st.skipped.name++; continue; }
    const react = typeof m?.react === "string" ? m.react : q.field("Npc", id, NPC.friendlyToFaction);
    if (react === "AH") { st.skipped.friendly++; continue; }
    const flags = int(m?.flags) ?? int(q.field("Npc", id, NPC.npcFlags)) ?? 0;
    if ((flags & SERVICE_FLAGS_MASK) !== 0) { st.skipped.flags++; continue; }
    const spawn = hasSpawn(q.field("Npc", id, NPC.spawns)) || f.spawns.get(id) === true;
    if (!spawn) { st.skipped.spawn++; continue; }
    let min = int(m?.min) ?? int(q.field("Npc", id, NPC.minLevel));
    let max = int(m?.max) ?? int(q.field("Npc", id, NPC.maxLevel));
    if (min === undefined) min = max;
    if (max === undefined) max = min;
    if (min === undefined || min < 1 || max > MAX_LEVEL) { st.skipped.level++; continue; }
    if (max < min) [min, max] = [max, min];
    const de = cleanName(f.deNpc[String(id)]) || cleanName(q.deDE("Npc", id));
    if (de) st.de++;
    const qRank = int(q.field("Npc", id, NPC.rank));
    const rank = typeof m?.rank === "string" && m.rank in RANK_TEXT ? RANK_TEXT[m.rank] : (RANK_NUM[qRank] ?? "");
    const zone = int(q.field("Npc", id, NPC.zoneID)) || int(m?.zone) || 0;
    out.push({ id, name: de || en, en, min, max, rank, zone: zone > 0 ? zone : 0 });
  }
  return { list: sortByName(out), stats: st };
}

export function buildItems(q, f) {
  const out = [];
  const st = { total: 0, de: 0, skipped: { source: 0, name: 0 } };
  for (const id of q.ids("Item")) {
    st.total++;
    const src = [ITEM.npcDrops, ITEM.objectDrops, ITEM.itemDrops, ITEM.questRewards].some((nr) => asList(q.field("Item", id, nr)).length > 0);
    if (!src) { st.skipped.source++; continue; }
    const m = f.item.get(id);
    const en = cleanName(m?.name ?? q.field("Item", id, ITEM.name));
    if (!en || PLACEHOLDER.test(en)) { st.skipped.name++; continue; }
    const de = cleanName(f.deItem[String(id)]) || cleanName(q.deDE("Item", id));
    if (de) st.de++;
    const quality = int(m?.quality);
    out.push({ id, name: de || en, en, quality: quality !== undefined && quality >= 0 && quality <= 7 ? quality : undefined });
  }
  return { list: sortByName(out), stats: st };
}

function sortByName(list, prop = "name") {
  return list
    .map((r) => ({ r, k: foldKey(r[prop]) }))
    .sort((a, b) => (a.k < b.k ? -1 : a.k > b.k ? 1 : a.r.id - b.r.id))
    .map((x) => x.r);
}

// ---------------------------------------------------------------- Ausgabe

export function npcBlob(list) {
  return list.map((r) => `\n${r.id}\t${r.name}\t${r.min}\t${r.max === r.min ? "" : r.max}\t${r.rank}\t${r.zone || ""}`).join("") + "\n";
}

/** Englische Namensliste: je Eintrag "\n<id>\t<englischer Name>", sortiert nach dem englischen Namen (dann ID) */
export function enBlob(list) {
  return sortByName(list, "en").map((r) => `\n${r.id}\t${r.en}`).join("") + "\n";
}

export function itemBlob(list) {
  return list.map((r) => `\n${r.id}\t${r.name}\t${r.quality ?? ""}`).join("") + "\n";
}

/** Lua-Literal fuer eine lange Zeichenkette: [==[ ... ]==] mit freier Stufe; erster Zeilenumbruch nach "[" wird von Lua verworfen. */
export function luaLong(s) {
  let level = 1;
  while (s.includes("]" + "=".repeat(level) + "]")) level++;
  const eq = "=".repeat(level);
  return `[${eq}[\n${s}]${eq}]`;
}

function luaQuote(s) {
  return '"' + s.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
}

const HEAD = (what, info) =>
  `-- InkAndEmbers_Data: ${what}. GENERATED by scripts/build-todo-data.mjs, do not edit by hand.\n` +
  "-- License: GPL-3.0 (see LICENSE and LICENSE-NOTE.md). Data: QuestieDB (Questie team and contributors, https://github.com/Questie/QuestieDB; license status: https://github.com/Questie/QuestieDB/blob/master/LICENSE.md); reformatted and extended by scripts/build-todo-data.mjs. Game world content (c) Blizzard Entertainment.\n" +
  `-- Sources: ${info}\n` +
  "-- Loaded on demand only (LoadOnDemand) by journal/model/TodoData.lua of the main addon; format described there.\n" +
  "EveNChronicleTodoData = EveNChronicleTodoData or {}\n";

// Wache der englischen Dateien: laufen nur, wenn das Hauptaddon vor dem Laden EveNChronicleTodoLang = "enUS" gesetzt hat
const EN_GUARD = 'if EveNChronicleTodoLang ~= "enUS" then return end\n';

async function writeAtomic(file, text) {
  const tmp = `${file}.tmp`;
  await writeFile(tmp, text, "utf8");
  await rename(tmp, file);
}

export async function build({ questie, forever, out }) {
  const q = openQuestie(readFileSync(questie, "utf8"));
  const f = openForever(forever);
  const npcs = buildNpcs(q, f);
  const items = buildItems(q, f);
  const zones = new Map();
  for (const r of npcs.list) {
    if (r.zone && !zones.has(r.zone)) {
      const n = cleanName(f.zoneName(r.zone));
      if (n) zones.set(r.zone, n);
      else r.zone = 0;
    }
  }
  const info = `QuestieDB ${cleanName(q.version)}, Forever database (data.morthen.net)`;
  const npcText = HEAD("enemy list", info) +
    `-- Enemies: ${npcs.list.length}, with German name: ${npcs.stats.de}\n` +
    `EveNChronicleTodoData.npc = ${luaLong(npcBlob(npcs.list))}\n`;
  const itemText = HEAD("item list", info) +
    `-- Items: ${items.list.length}, with German name: ${items.stats.de}\n` +
    `EveNChronicleTodoData.item = ${luaLong(itemBlob(items.list))}\n`;
  const zoneText = HEAD("zone names of the enemy list", info) +
    "EveNChronicleTodoData.zones = {\n" +
    [...zones.entries()].sort((a, b) => a[0] - b[0]).map(([id, n]) => `  [${id}] = ${luaQuote(n)},\n`).join("") +
    "}\n";
  const zonesEn = new Map();
  for (const id of zones.keys()) {
    const n = cleanName(f.zoneNameEn(id));
    if (n && n !== zones.get(id)) zonesEn.set(id, n);
  }
  const zoneLines = (m) => "{\n" + [...m.entries()].sort((a, b) => a[0] - b[0]).map(([id, n]) => `  [${id}] = ${luaQuote(n)},\n`).join("") + "}\n";
  const npcEnText = HEAD("enemy list, English names", info) + EN_GUARD +
    `-- Enemies: ${npcs.list.length}\n` +
    `EveNChronicleTodoData.npcEn = ${luaLong(enBlob(npcs.list))}\n`;
  const itemEnText = HEAD("item list, English names", info) + EN_GUARD +
    `-- Items: ${items.list.length}\n` +
    `EveNChronicleTodoData.itemEn = ${luaLong(enBlob(items.list))}\n`;
  const zoneEnText = HEAD("zone names of the enemy list, English", info) + EN_GUARD +
    "EveNChronicleTodoData.zonesEn = " + zoneLines(zonesEn);
  const sizes = {
    npc: Buffer.byteLength(npcText), item: Buffer.byteLength(itemText), zones: Buffer.byteLength(zoneText),
    npcEn: Buffer.byteLength(npcEnText), itemEn: Buffer.byteLength(itemEnText), zonesEn: Buffer.byteLength(zoneEnText),
  };
  if (Math.max(sizes.npc, sizes.item, sizes.npcEn, sizes.itemEn) > MAX_LIST_BYTES) {
    throw new Error(`Liste zu gross (Gegner ${sizes.npc}/${sizes.npcEn} B, Gegenstaende ${sizes.item}/${sizes.itemEn} B; Grenze ${MAX_LIST_BYTES} B)`);
  }
  if (npcs.list.length < 1000 || items.list.length < 1000) {
    throw new Error(`Ergebnis unplausibel klein (Gegner ${npcs.list.length}, Gegenstaende ${items.list.length})`);
  }
  await mkdir(out, { recursive: true });
  await writeAtomic(path.join(out, "Npcs.lua"), npcText);
  await writeAtomic(path.join(out, "Items.lua"), itemText);
  await writeAtomic(path.join(out, "Zones.lua"), zoneText);
  await writeAtomic(path.join(out, "NpcsEn.lua"), npcEnText);
  await writeAtomic(path.join(out, "ItemsEn.lua"), itemEnText);
  await writeAtomic(path.join(out, "ZonesEn.lua"), zoneEnText);
  return { npcs, items, zones: zones.size, zonesEn: zonesEn.size, sizes, questieVersion: q.version, badValues: q.stats.badValues };
}

export async function main(argv) {
  const opts = parseArgs(argv);
  if (opts.help) {
    console.log(HELP);
    return null;
  }
  const def = defaultSources();
  const questie = opts.questie ?? def.questie.find((p) => existsSync(p));
  if (!questie || !existsSync(questie)) {
    throw new Error(`QuestieDB_Forever.toc nicht gefunden (gesucht: ${opts.questie ?? (def.questie.join(", ") || "nichts konfiguriert")}). Pfad mit --questie angeben oder CHRONICLE_QUESTIE_TOC bzw. WOW_DIR setzen (README, Abschnitt "Questdaten neu erzeugen").`);
  }
  const forever = opts.forever ?? def.forever;
  if (!forever || !existsSync(path.join(forever, "search.json"))) {
    throw new Error(`Forever-Datenbank nicht gefunden (${forever ?? "nicht konfiguriert"}). Dump-Ordner mit --forever angeben oder CHRONICLE_FOREVER_DB setzen (README, Abschnitt "Questdaten neu erzeugen").`);
  }
  const out = opts.out ?? DEFAULT_OUT;
  const r = await build({ questie, forever, out });
  const pct = (a, b) => (b ? ((100 * a) / b).toFixed(1) : "0.0");
  console.log(`QuestieDB ${r.questieVersion}: ${questie}`);
  console.log(`Forever-Datenbank: ${forever}`);
  console.log(`Gegner: ${r.npcs.list.length} (deDE ${r.npcs.stats.de} = ${pct(r.npcs.stats.de, r.npcs.list.length)} %), ausgefiltert ${JSON.stringify(r.npcs.stats.skipped)}`);
  console.log(`Gegenstaende: ${r.items.list.length} (deDE ${r.items.stats.de} = ${pct(r.items.stats.de, r.items.list.length)} %), ausgefiltert ${JSON.stringify(r.items.stats.skipped)}`);
  console.log(`Gebiete: ${r.zones}; Dateigroessen: Npcs.lua ${r.sizes.npc} B, Items.lua ${r.sizes.item} B, Zones.lua ${r.sizes.zones} B`);
  console.log(`Englisch: NpcsEn.lua ${r.sizes.npcEn} B, ItemsEn.lua ${r.sizes.itemEn} B, ZonesEn.lua ${r.sizes.zonesEn} B (${r.zonesEn} abweichende Gebietsnamen)`);
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
