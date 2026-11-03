// Laedt ein STABILES QuestieDB-Release (GitHub, Questie/QuestieDB) und legt die Daten-TOC fuer "npm run data" lokal ab.
//
// Aufruf:  node scripts/fetch-questiedb-release.mjs [--tag vX.Y.Z] [--preview] [--soft] [--force] [--dry-run]
//                                                   [--from-zip <Datei> [--release-json <Datei>]] [--help]
//   (ohne Option)  neuestes Release, das weder Prerelease noch Entwurf ist (GitHub-API, nur zur Tag-Wahl)
//   --tag vX.Y.Z   genau diese stabile Version (Format vMAJOR.MINOR.PATCH), z. B. zum Reproduzieren
//   --sha256 <hex> Pin: erwartete SHA-256 des Archivs (aus einer unabhaengigen Quelle); verlangt --tag oder --from-zip.
//                  release.json und ZIP kommen sonst vom selben Host (akzeptiertes Restrisiko); der Pin schliesst es.
//   --preview      AUSDRUECKLICH den instabilen Kanal "preview" benutzen (nie der Standard)
//   --soft         Fehler/offline ist kein Fehler (Exit 0); bisherige Daten bleiben
//   --force        auch laden, wenn die Version unveraendert ist, und die Plausibilitaetspruefung uebergehen
//   --dry-run      laden und pruefen, aber nichts schreiben
//   --from-zip     ein bereits geladenes QuestieDB-Forever.zip (lokale Datei) statt des Downloads (offline/Test);
//                  mit --release-json <Datei> wird es gegen die Pruefsumme der release.json geprueft, sonst nur mit Warnung
//
// Ablauf: release.json des Releases laden und pruefen (Version = Tag, Contract-Bereich, SHA-256 und Groesse von
// QuestieDB-Forever.zip), dann das Archiv laden, gegen SHA-256/Groesse pruefen und NUR im Speicher entpacken. Gelesen werden die
// TOC "QuestieDB/QuestieDB_Forever.toc" (im "baked"-Modus der komplette Datenbestand) und die fest benannten Korrektur-Dateien
// (scripts/lib/questie-fixes.mjs; deren fraktionsabhaengige Korrekturen stehen nicht in der TOC). Korrektur-Lua wird mit luaparse nur
// GEPARST, nie ausgefuehrt; abgelegt wird nur das Ergebnis als JSON.
//
// Ausgabe (nicht eingecheckt, data-capture/ ist gitignored):
//   data-capture/questiedb-release/Interface/AddOns/QuestieDB/QuestieDB_Forever.toc   (gleiche Pfad-Endung wie im Spielordner)
//   data-capture/questiedb-release/Interface/AddOns/QuestieDB/src/corrections/...   (die fest benannten Korrektur-Lua-Dateien, byte-gleich aus dem
//       Archiv; sie werden von scripts/build-quest-data.mjs nur GEPARST (Horde UND Allianz) und passen so immer zur geladenen TOC)
//   data-capture/questiedb-release/stamp.json   (Version, Kanal, Contract-Bereich, Commit, Groessen, SHA-256 von Archiv und TOC)
//   data-capture/questiedb-release/fixes.json   (ausgewertete Horde-/fraktionsneutrale Laufzeitkorrekturen, an die TOC gebunden)
//
// Sicherheit: nur https, Host-Allowlist (api.github.com, github.com + GitHub-Release-Asset-Hosts), Umleitungen nur innerhalb der
// Allowlist und hoechstens MAX_REDIRECTS, Zeit- und Groessenlimit beim Lesen (Streaming), keine Zugangsdaten (GitHub-API ohne Token,
// Limit 60 Abfragen/Stunde). Die Download-Adressen werden aus dem validierten Tag selbst gebaut, nie aus der API-Antwort uebernommen.
// Entpacken nur im Speicher; kein Pfad aus dem Archiv wird Dateipfad. Geschrieben wird nur in den festen Ordner (atomar, kein Symlink).
// Bausteine (Allowlist, Streaming-Lesen mit Fristen, Zip-Leser, Korrektur-Parser) stammen aus forever-routen
// (scripts/fetch-questie-preview.mjs, scripts/lib/zip-reader.mjs, scripts/lib/questie-fixes.mjs, Stand 2026-11-03) und sind hier eigenstaendig kopiert.
// Exit-Codes: 0 = ok / aktuell / offline mit vorhandenen Daten / --soft; 1 = Fehler (bisherige Daten bleiben unveraendert).

import { createHash, randomBytes } from "node:crypto";
import { lstat, mkdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { ENUM_ENTRIES, FIX_ENTRIES, FIXES_SCHEMA, MAX_FIX_FILE_BYTES, parseQuestieFixes } from "./lib/questie-fixes.mjs";
import { readZipEntries, ZIP_LIMITS, ZipError } from "./lib/zip-reader.mjs";

// ---------------------------------------------------------------- Konstanten

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const REPO = "Questie/QuestieDB";
export const API_URL = `https://api.github.com/repos/${REPO}/releases?per_page=30`;
export const ASSET_ZIP = "QuestieDB-Forever.zip";
export const ASSET_JSON = "release.json";
/** Erlaubte Hosts (exakt). github.com leitet auf einen Asset-Host um; welcher, hat GitHub schon gewechselt. */
export const ALLOWED_HOSTS = Object.freeze(["api.github.com", "github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"]);
/** Name des einzigen Eintrags, der als Datenquelle aus dem Archiv gelesen wird (exakter Vergleich). */
export const TOC_ENTRY = "QuestieDB/QuestieDB_Forever.toc";
/** Archiv 1.0.10: 13,2 MB; 64 MB laesst Luft fuer Wachstum. */
export const MAX_ZIP_BYTES = ZIP_LIMITS.maxArchiveBytes;
/** TOC 1.0.10: rund 16 MB entpackt; 32 MB = Lese-Limit. */
export const MAX_TOC_BYTES = 32 * 1024 * 1024;
export const MAX_JSON_BYTES = 2 * 1024 * 1024;
export const REQUEST_TIMEOUT_MS = 120_000;
/** Gesamtfrist ueber alle Abrufe inkl. Umleitungen, Wartezeit und Wiederholung. */
export const TOTAL_DEADLINE_MS = 180_000;
export const MAX_REDIRECTS = 5;
const MAX_RETRIES = 1;
const RETRY_WAIT_MS = 2000;
/** Neue TOC muss mindestens diesen Anteil der Quests der bisherigen haben (sonst abgeschnitten/kaputt), ab MIN_PLAUSIBLE_BASE. */
export const MIN_PLAUSIBLE_RATIO = 0.5;
export const MIN_PLAUSIBLE_BASE = 50;
/** Hoechster Contract, dessen Entity-Format wir kennen (Contract 5+ ist laut Vertrag additiv: Warnung, kein Abbruch). */
export const KNOWN_CONTRACT_VERSION = 4;
/** Wir lesen nur Entity-Felder des baked-Formats: das Release muss mindestens diesen Contract zusichern koennen (Untergrenze <= 4). */
export const STAMP_SCHEMA = 1;
const USER_AGENT = "InkAndEmbers-datenbau/1.0 (Hobbyprojekt, lokal; QuestieDB-Release)";
const TAG_RE = /^v\d{1,3}\.\d{1,3}\.\d{1,3}$/;
const VERSION_RE = /^[0-9A-Za-z.+_-]{1,40}$/;
const COMMIT_RE = /^[0-9a-f]{7,40}$/;
const SHA_RE = /^[0-9a-f]{64}$/;
/** Feld S = Kopf-/Statusfeld, das jede Entitaet der baked-TOC genau einmal hat. */
const ENTITY_RE = /^## X-(Quest|Npc|Object|Item)-(\d{1,8})-S:/;

export const OUT_DIR = path.join(ROOT, "data-capture", "questiedb-release");
export const TOC_SEGMENTS = ["Interface", "AddOns", "QuestieDB", "QuestieDB_Forever.toc"];

export const HELP = [
  "fetch-questiedb-release: stabiles QuestieDB-Forever-Release von GitHub laden (nur die Daten-TOC, nichts wird ausgefuehrt).",
  "",
  "Aufruf: node scripts/fetch-questiedb-release.mjs [--tag vX.Y.Z [--sha256 <hex>]] [--preview] [--soft] [--force] [--dry-run]",
  "                                                  [--from-zip <Datei> [--release-json <Datei>]]",
  "",
  `Quelle: https://github.com/${REPO}/releases (Standard: neuestes Nicht-Prerelease; --preview nur auf ausdruecklichen Wunsch)`,
  "Ausgabe: data-capture/questiedb-release/ (TOC + stamp.json + fixes.json, nicht eingecheckt).",
  "Pruefung: SHA-256 und Groesse laut release.json, Contract-Bereich, Variante Forever, Modus baked.",
].join("\n");

// ---------------------------------------------------------------- Fehler und Argumente

/** Fehler beim Abruf/Pruefen. network = voruebergehend (offline, Zeitlimit, 5xx). */
export class FetchError extends Error {
  constructor(message, { network = false } = {}) {
    super(message);
    this.name = "FetchError";
    this.network = network;
  }
}

/** Argumente lesen; wirft bei Unbekanntem. */
export function parseArgs(argv) {
  const out = { soft: false, force: false, dryRun: false, help: false, preview: false, tag: undefined, sha256: undefined, fromZip: undefined, releaseJson: undefined };
  const value = (i, name) => {
    const v = argv[i + 1];
    if (v === undefined || v.startsWith("--")) throw new Error(`${name} braucht einen Wert.`);
    return v;
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--soft") out.soft = true;
    else if (a === "--force") out.force = true;
    else if (a === "--dry-run") out.dryRun = true;
    else if (a === "--preview") out.preview = true;
    else if (a === "--help") out.help = true;
    else if (a === "--tag") {
      out.tag = value(i++, "--tag");
      if (!TAG_RE.test(out.tag)) throw new Error(`--tag: erwartet vMAJOR.MINOR.PATCH (stabile Version), nicht "${out.tag.slice(0, 40)}".`);
    } else if (a === "--sha256") {
      out.sha256 = value(i++, "--sha256").toLowerCase();
      if (!SHA_RE.test(out.sha256)) throw new Error("--sha256: erwartet 64 Hex-Zeichen.");
    } else if (a === "--from-zip") out.fromZip = value(i++, "--from-zip");
    else if (a === "--release-json") out.releaseJson = value(i++, "--release-json");
    else throw new Error(`Unbekanntes Argument: ${a}`);
  }
  if (out.tag && out.preview) throw new Error("--tag und --preview schliessen sich aus.");
  if (out.sha256 && !out.tag && out.fromZip === undefined) throw new Error("--sha256 gilt nur zusammen mit --tag oder --from-zip.");
  if (out.releaseJson !== undefined && out.fromZip === undefined) throw new Error("--release-json gilt nur zusammen mit --from-zip.");
  return out;
}

// ---------------------------------------------------------------- Netz (Allowlist)

/** Prueft ein Ziel gegen die Allowlist: nur https, Host exakt erlaubt, Standard-Port, keine Zugangsdaten. Liefert die URL. */
export function checkUrl(value) {
  let url;
  try {
    url = value instanceof URL ? value : new URL(String(value));
  } catch {
    throw new FetchError("Ungueltiges Download-Ziel.");
  }
  if (url.protocol !== "https:") throw new FetchError(`Ziel nicht erlaubt (nur https): ${url.protocol}`);
  if (url.username !== "" || url.password !== "") throw new FetchError("Ziel nicht erlaubt (Zugangsdaten in der Adresse).");
  if (url.port !== "") throw new FetchError(`Ziel nicht erlaubt (Port ${url.port}).`);
  if (!ALLOWED_HOSTS.includes(url.hostname)) throw new FetchError(`Ziel nicht erlaubt (Host ${url.hostname} nicht in der Allowlist).`);
  return url;
}

/** Download-Adresse eines Release-Assets, aus dem validierten Tag gebaut ("preview" nur mit ausdruecklichem Wunsch). */
export function assetUrl(tag, name) {
  if (tag !== "preview" && !TAG_RE.test(tag)) throw new FetchError("Ungueltiger Release-Tag.");
  if (name !== ASSET_ZIP && name !== ASSET_JSON) throw new FetchError("Ungueltiger Asset-Name.");
  return `https://github.com/${REPO}/releases/download/${tag}/${name}`;
}

const deadlineError = (ms) => new FetchError(`Gesamtfrist von ${Math.round(ms / 1000)} s fuer den Download ueberschritten (GitHub zu langsam); abgebrochen.`, { network: true });

/** Liest den Body streamend und bricht beim ersten Byte ueber `maxBytes` ab; laeuft die Gesamtfrist ab, wird nie ein abgeschnittener Body geliefert. */
async function readBodyLimited(res, maxBytes, deadline, deadlineMs) {
  if (!res.body) return Buffer.alloc(0);
  const chunks = [];
  let total = 0;
  const reader = res.body.getReader();
  const onAbort = () => reader.cancel().catch(() => {});
  deadline?.addEventListener("abort", onAbort, { once: true });
  try {
    for (;;) {
      if (deadline?.aborted) throw deadlineError(deadlineMs);
      const { done, value } = await reader.read();
      if (deadline?.aborted) throw deadlineError(deadlineMs);
      if (done) break;
      total += value.byteLength;
      if (total > maxBytes) {
        await reader.cancel().catch(() => {});
        throw new FetchError(`Antwort zu gross (mehr als ${maxBytes} Byte); abgebrochen.`);
      }
      chunks.push(value);
    }
  } catch (err) {
    if (err instanceof FetchError) throw err;
    if (deadline?.aborted) throw deadlineError(deadlineMs);
    throw new FetchError("Netzwerkfehler beim Lesen der Antwort (Verbindung oder Zeitlimit).", { network: true });
  } finally {
    deadline?.removeEventListener("abort", onAbort);
  }
  return Buffer.concat(chunks, total);
}

/** Ein Abruf mit kontrollierten Umleitungen (nur innerhalb der Allowlist). Liefert den Body als Buffer. */
export async function download({ url, fetchImpl = fetch, maxBytes, timeoutMs = REQUEST_TIMEOUT_MS, deadline, deadlineMs = TOTAL_DEADLINE_MS, accept = "application/octet-stream" }) {
  const overall = deadline ?? AbortSignal.timeout(deadlineMs);
  let target = checkUrl(url);
  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    target = checkUrl(target);
    if (overall.aborted) throw deadlineError(deadlineMs);
    let res;
    try {
      res = await fetchImpl(target, {
        redirect: "manual",
        credentials: "omit",
        headers: { "User-Agent": USER_AGENT, Accept: accept },
        signal: AbortSignal.any([AbortSignal.timeout(timeoutMs), overall]),
      });
    } catch (err) {
      if (overall.aborted) throw deadlineError(deadlineMs);
      const code = err?.cause?.code ?? err?.name ?? "unbekannt";
      throw new FetchError(`Netzwerkfehler bei ${target.hostname}: ${/^[A-Za-z0-9_]{1,40}$/.test(code) ? code : "unbekannt"}`, { network: true });
    }
    if (res.status >= 300 && res.status < 400) {
      await res.body?.cancel().catch(() => {});
      const location = res.headers.get("location");
      if (!location) throw new FetchError(`Umleitung ohne Ziel (HTTP ${res.status}).`);
      let next;
      try {
        next = new URL(location, target);
      } catch {
        throw new FetchError("Umleitung auf ein ungueltiges Ziel.");
      }
      target = checkUrl(next); // vor dem naechsten Abruf: nur innerhalb der Allowlist
      continue;
    }
    if (res.status !== 200) {
      await res.body?.cancel().catch(() => {});
      throw new FetchError(`Download fehlgeschlagen (HTTP ${res.status} von ${target.hostname}).`, { network: res.status >= 500 || res.status === 429 });
    }
    const declared = Number(res.headers.get("content-length") ?? 0);
    if (Number.isFinite(declared) && declared > maxBytes) {
      await res.body?.cancel().catch(() => {});
      throw new FetchError(`Antwort zu gross (${declared} Byte angekuendigt, erlaubt bis ${maxBytes}).`);
    }
    return readBodyLimited(res, maxBytes, overall, deadlineMs);
  }
  throw new FetchError(`Zu viele Umleitungen (mehr als ${MAX_REDIRECTS}).`);
}

/** Abruf mit einer Wiederholung bei voruebergehenden Fehlern, alles innerhalb EINER Gesamtfrist. */
export async function downloadWithRetry(opts = {}) {
  const deadlineMs = opts.deadlineMs ?? TOTAL_DEADLINE_MS;
  const deadline = opts.deadline ?? AbortSignal.timeout(deadlineMs);
  let last;
  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    if (attempt > 0) {
      await new Promise((resolve) => {
        const t = setTimeout(resolve, opts.retryWaitMs ?? RETRY_WAIT_MS);
        deadline.addEventListener("abort", () => (clearTimeout(t), resolve(undefined)), { once: true });
      });
    }
    if (deadline.aborted) throw deadlineError(deadlineMs);
    try {
      return await download({ ...opts, deadline, deadlineMs });
    } catch (err) {
      if (!(err instanceof FetchError) || !err.network || deadline.aborted) throw err;
      last = err;
    }
  }
  throw last;
}

// ---------------------------------------------------------------- Release waehlen und release.json pruefen

/**
 * Aus der API-Antwort (Liste der Releases) das neueste stabile waehlen: kein Prerelease, kein Entwurf, Tag vMAJOR.MINOR.PATCH.
 * Die API liefert neueste zuerst; zur Sicherheit wird nach Version sortiert. Liefert den Tag oder wirft.
 */
export function pickStableTag(list) {
  if (!Array.isArray(list)) throw new FetchError("GitHub-Antwort unerwartet (keine Release-Liste).");
  const tags = [];
  for (const r of list) {
    if (!r || typeof r !== "object" || r.prerelease !== false || r.draft !== false) continue;
    if (typeof r.tag_name === "string" && TAG_RE.test(r.tag_name)) tags.push(r.tag_name);
  }
  if (!tags.length) throw new FetchError("Kein stabiles QuestieDB-Release gefunden.");
  const key = (t) => t.slice(1).split(".").map(Number);
  tags.sort((a, b) => {
    const x = key(a);
    const y = key(b);
    return y[0] - x[0] || y[1] - x[1] || y[2] - x[2];
  });
  return tags[0];
}

const isObj = (v) => typeof v === "object" && v !== null && !Array.isArray(v);
const isInt = (v, min, max) => Number.isSafeInteger(v) && v >= min && v <= max;

/**
 * release.json pruefen (Schema, Version = Tag, Contract-Bereich, Eintrag fuer QuestieDB-Forever.zip). Liefert
 * { version, contractVersion, minSupportedContract, producerCommit, sha256, bytes }. `tag` null = Tag nicht pruefen (--from-zip).
 */
export function checkReleaseJson(json, { tag = null, preview = false } = {}) {
  const q = isObj(json) ? json.questiedb : null;
  if (!isObj(q)) throw new FetchError("release.json: Abschnitt \"questiedb\" fehlt.");
  if (typeof q.version !== "string" || !VERSION_RE.test(q.version)) throw new FetchError("release.json: Version fehlt oder ist ungueltig.");
  if (tag && !preview && q.version !== tag.slice(1)) throw new FetchError(`release.json: Version ${q.version} passt nicht zum Tag ${tag}.`);
  if (!isInt(q.contractVersion, 1, 1000) || !isInt(q.minSupportedContract, 1, 1000)) throw new FetchError("release.json: contractVersion/minSupportedContract fehlen oder sind ungueltig.");
  if (q.minSupportedContract > q.contractVersion) throw new FetchError("release.json: minSupportedContract ist groesser als contractVersion.");
  // Unser Bedarf: Entity-Felder des baked-Formats, bekannt bis KNOWN_CONTRACT_VERSION. Gibt das Release erst ab einem hoeheren Contract
  // Kompatibilitaet zu, kann es die Entity-Felder nicht mehr in der bekannten Form garantieren -> Abbruch.
  if (q.minSupportedContract > KNOWN_CONTRACT_VERSION) {
    throw new FetchError(`Release unterstuetzt erst Contract ${q.minSupportedContract} aufwaerts; dieser Build kennt Contract 1 bis ${KNOWN_CONTRACT_VERSION}. Abbruch.`);
  }
  const arts = Array.isArray(q.artifacts) ? q.artifacts.filter((a) => isObj(a) && a.file === ASSET_ZIP) : [];
  if (arts.length !== 1) throw new FetchError(`release.json: Eintrag fuer ${ASSET_ZIP} fehlt oder ist mehrfach vorhanden.`);
  const art = arts[0];
  if (typeof art.sha256 !== "string" || !SHA_RE.test(art.sha256)) throw new FetchError("release.json: SHA-256 fehlt oder ist ungueltig.");
  if (!isInt(art.bytes, 1, MAX_ZIP_BYTES)) throw new FetchError(`release.json: Groesse fehlt oder ist unzulaessig (erlaubt bis ${MAX_ZIP_BYTES} Byte).`);
  const commit = typeof q.producerCommit === "string" && COMMIT_RE.test(q.producerCommit) ? q.producerCommit : "";
  return { version: q.version, contractVersion: q.contractVersion, minSupportedContract: q.minSupportedContract, producerCommit: commit, sha256: art.sha256, bytes: art.bytes };
}

/** Archiv-Bytes gegen die Angaben der release.json pruefen (Groesse und SHA-256, vor jedem Entpacken). */
export function verifyArchive(zip, rel) {
  if (zip.length !== rel.bytes) throw new FetchError(`Archiv hat ${zip.length} statt ${rel.bytes} Byte (laut release.json); abgelehnt.`);
  if (sha256(zip) !== rel.sha256) throw new FetchError("SHA-256 des Archivs passt nicht zur release.json; abgelehnt.");
}

// ---------------------------------------------------------------- TOC pruefen

/**
 * Prueft den TOC-Text (Kopfzeilen) und zaehlt die Entitaeten. Wirft FetchError bei falscher Variante/Modus oder ohne Quest-Daten.
 * Liefert { version, buildCommit, contractVersion, flavor, mode, counts: { quests, npcs, objects, items } }.
 */
export function inspectToc(text) {
  const head = { version: "", buildCommit: "", contractVersion: 0, flavor: "", mode: "" };
  const ids = { Quest: new Set(), Npc: new Set(), Object: new Set(), Item: new Set() };
  for (const line of text.split("\n")) {
    if (!line.startsWith("## ")) continue;
    const m = ENTITY_RE.exec(line);
    if (m) {
      ids[m[1]].add(Number(m[2]));
      continue;
    }
    const sep = line.indexOf(":");
    if (sep < 0) continue;
    const key = line.slice(3, sep).trim();
    const val = line.slice(sep + 1).trim();
    if (key === "Version" && VERSION_RE.test(val)) head.version = val;
    else if (key === "X-BUILD-COMMIT" && COMMIT_RE.test(val)) head.buildCommit = val;
    else if (key === "X-Contract-Version" && /^\d{1,4}$/.test(val)) head.contractVersion = Number(val);
    else if (key === "X-Flavor" && VERSION_RE.test(val)) head.flavor = val;
    else if (key === "X-Mode" && VERSION_RE.test(val)) head.mode = val;
  }
  if (head.flavor !== "Forever") throw new FetchError(`TOC ist nicht die Forever-Variante (X-Flavor: ${head.flavor || "fehlt"}).`);
  if (head.mode !== "baked") throw new FetchError(`TOC ist nicht im baked-Modus (X-Mode: ${head.mode || "fehlt"}); die Daten stehen dann nicht in der TOC.`);
  if (head.contractVersion < 1) throw new FetchError("TOC ohne gueltige X-Contract-Version.");
  const counts = { quests: ids.Quest.size, npcs: ids.Npc.size, objects: ids.Object.size, items: ids.Item.size };
  if (counts.quests === 0 || counts.npcs === 0) throw new FetchError("TOC enthaelt keine Quest-/NPC-Daten (Format geaendert oder beschaedigt).");
  return { ...head, counts };
}

/** Archiv-Bytes -> geprueftes Ergebnis { toc: Buffer, text, info, modified } (wirft FetchError). */
export function extractToc(zipBytes) {
  let entries;
  try {
    entries = readZipEntries(zipBytes, [TOC_ENTRY], { ...ZIP_LIMITS, maxUncompressedBytes: MAX_TOC_BYTES, maxTotalUncompressedBytes: MAX_TOC_BYTES });
  } catch (err) {
    if (err instanceof ZipError) throw new FetchError(`Archiv abgelehnt: ${err.message}`);
    throw err;
  }
  const entry = entries.get(TOC_ENTRY);
  if (!entry || entry.data.length === 0) throw new FetchError(`Archiv abgelehnt: "${TOC_ENTRY}" ist leer.`);
  let text;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(entry.data);
  } catch {
    throw new FetchError("TOC ist kein gueltiges UTF-8.");
  }
  return { toc: entry.data, text, info: inspectToc(text), modified: entry.modified };
}

/**
 * Korrektur-Dateien (nur die fest benannten Eintraege) im Speicher entpacken und auswerten. Fehlt einer oder ist er beschaedigt, ist das
 * ein Befund (nie ein Abbruch). Liefert das Ergebnis von parseQuestieFixes plus files: [{ entry, bytes, sha256 }].
 */
export function extractFixes(zipBytes) {
  const files = new Map();
  const meta = [];
  const findings = [];
  const limits = { ...ZIP_LIMITS, maxCompressedBytes: MAX_FIX_FILE_BYTES, maxUncompressedBytes: MAX_FIX_FILE_BYTES, maxTotalUncompressedBytes: MAX_FIX_FILE_BYTES };
  for (const { entry } of [...FIX_ENTRIES, ...ENUM_ENTRIES]) {
    try {
      const got = readZipEntries(zipBytes, [entry], limits).get(entry);
      if (!got) continue;
      files.set(entry, got.data);
      meta.push({ entry, bytes: got.data.length, sha256: sha256(got.data) });
    } catch (err) {
      if (!(err instanceof ZipError)) throw err;
      if (!/fehlt im Zip-Archiv/.test(err.message)) findings.push({ entry, reason: `nicht lesbar: ${err.message}` });
    }
  }
  let parsed;
  try {
    parsed = parseQuestieFixes(files);
  } catch (err) {
    throw new FetchError(`Laufzeitkorrekturen nicht auswertbar (${err instanceof Error ? err.message : "unbekannt"}).`);
  }
  return { ...parsed, files: meta, buffers: files, findings: [...findings, ...parsed.findings] };
}

// ---------------------------------------------------------------- Stempel und Ablage

const sha256 = (buf) => createHash("sha256").update(buf).digest("hex");
const mb = (bytes) => (bytes / (1024 * 1024)).toFixed(1).replace(".", ",");

/** Pfade fuer einen Projektordner (Tests: Wegwerf-Ordner). */
export function releasePaths(root = ROOT) {
  const dir = path.join(root, "data-capture", "questiedb-release");
  return { dir, tocFile: path.join(dir, ...TOC_SEGMENTS), stampFile: path.join(dir, "stamp.json"), fixesFile: path.join(dir, "fixes.json") };
}

/** Stempel lesen und Form pruefen; null wenn fehlend/ungueltig. */
export async function readStamp(stampFile) {
  let s;
  try {
    s = JSON.parse(await readFile(stampFile, "utf8"));
  } catch {
    return null;
  }
  if (!isObj(s) || s.schema !== STAMP_SCHEMA || typeof s.version !== "string" || typeof s.zipSha256 !== "string" || typeof s.tocSha256 !== "string") return null;
  if (!isObj(s.counts) || !Number.isSafeInteger(s.counts.quests)) return null;
  return s;
}

/**
 * Vor dem Schreiben: data-capture und die Ordner darunter bis zur TOC duerfen, soweit vorhanden, kein Symlink/Junction sein
 * (lstat meldet Junctions unter Windows als Symlink) und muessen Ordner sein. Sonst Abbruch.
 */
export async function assertNoLinks(root, tocFile) {
  const base = path.resolve(root);
  const rel = path.relative(base, path.dirname(path.resolve(tocFile)));
  if (rel === "" || rel.startsWith("..") || path.isAbsolute(rel)) throw new FetchError("Ablageort liegt nicht im Projektordner; abgebrochen.");
  let current = base;
  for (const seg of rel.split(path.sep)) {
    current = path.join(current, seg);
    let st;
    try {
      st = await lstat(current);
    } catch (err) {
      if (err && err.code === "ENOENT") return; // ab hier wird neu angelegt
      throw new FetchError(`Ablageort nicht pruefbar (${path.relative(base, current)}).`);
    }
    if (st.isSymbolicLink()) throw new FetchError(`Ablageort ist ein Symlink/Junction (${path.relative(base, current)}); abgebrochen, nichts geschrieben.`);
    if (!st.isDirectory()) throw new FetchError(`Ablageort ist kein Ordner (${path.relative(base, current)}); abgebrochen.`);
  }
}

/** Atomar schreiben: zufaellig benannte temporaere Datei (exklusiv angelegt), dann umbenennen; Ziel darf kein Symlink sein. */
async function writeAtomic(file, data) {
  try {
    if ((await lstat(file)).isSymbolicLink()) throw new FetchError(`Ziel ist ein Symlink, Abbruch: ${path.basename(file)}`);
  } catch (err) {
    if (err instanceof FetchError) throw err;
    if (!(err && err.code === "ENOENT")) throw new FetchError(`Ziel nicht pruefbar: ${path.basename(file)}`);
  }
  const tmp = `${file}.${randomBytes(8).toString("hex")}.tmp`;
  try {
    await writeFile(tmp, data, { flag: "wx" });
    for (let attempt = 0; ; attempt++) {
      try {
        await rename(tmp, file);
        return;
      } catch (err) {
        if (attempt >= 4 || !err || (err.code !== "EPERM" && err.code !== "EBUSY" && err.code !== "EACCES")) throw err;
        await new Promise((r) => setTimeout(r, 50 * (attempt + 1)));
      }
    }
  } finally {
    await rm(tmp, { force: true });
  }
}

/** Lokale Datei fuer --from-zip/--release-json lesen (regulaere Datei, kein Symlink, Groessenlimit). */
async function readLocal(file, maxBytes, what) {
  const full = path.resolve(String(file));
  let st;
  try {
    st = await lstat(full);
  } catch {
    throw new FetchError(`${what} nicht gefunden: ${path.basename(full)}`);
  }
  if (st.isSymbolicLink() || !st.isFile()) throw new FetchError(`${what} ist keine normale Datei: ${path.basename(full)}`);
  if (st.size > maxBytes) throw new FetchError(`${what} zu gross (${st.size} Byte, erlaubt bis ${maxBytes}).`);
  return readFile(full);
}

function parseJson(buf, what) {
  try {
    return JSON.parse(buf.toString("utf8"));
  } catch {
    throw new FetchError(`${what}: kein gueltiges JSON.`);
  }
}

// ---------------------------------------------------------------- Ablauf

/**
 * Ablauf (exportiert fuer Tests). opts: root (Wegwerf-Ordner), fetchImpl (Netz-Ersatz), log/warn (Ausgabe), now (Zeit).
 * Liefert { status: "updated" | "current" | "kept" | "failed" | "dry-run" | "help", exitCode, ... }; wirft nur bei Argumentfehlern.
 */
export async function main(argv, opts = {}) {
  const args = parseArgs(argv);
  const log = opts.log ?? ((m) => console.log(m));
  const warn = opts.warn ?? ((m) => console.error(m));
  if (args.help) {
    log(HELP);
    return { status: "help", exitCode: 0 };
  }
  const root = opts.root ?? ROOT;
  const paths = releasePaths(root);
  const before = await readStamp(paths.stampFile);
  const fetchImpl = opts.fetchImpl ?? fetch;
  const deadlineMs = opts.deadlineMs ?? TOTAL_DEADLINE_MS;
  const deadline = AbortSignal.timeout(deadlineMs);
  const net = { fetchImpl, retryWaitMs: opts.retryWaitMs, deadline, deadlineMs };

  try {
    let tag = null;
    let rel;
    let zip;
    if (args.fromZip !== undefined) {
      log("Lese QuestieDB-Archiv aus lokaler Datei ...");
      zip = await readLocal(args.fromZip, MAX_ZIP_BYTES, "Archiv");
      if (args.sha256 && sha256(zip) !== args.sha256) throw new FetchError("SHA-256 des Archivs passt nicht zum angegebenen Pin (--sha256); abgelehnt.");
      if (args.releaseJson !== undefined) {
        rel = checkReleaseJson(parseJson(await readLocal(args.releaseJson, MAX_JSON_BYTES, "release.json"), "release.json"));
        verifyArchive(zip, rel);
      } else {
        warn("WARNUNG: --from-zip ohne --release-json: das Archiv wird NICHT gegen eine Pruefsumme geprueft.");
      }
    } else {
      if (args.preview) {
        warn("WARNUNG: --preview benutzt den instabilen Kanal \"preview\" (nur auf ausdruecklichen Wunsch).");
        tag = "preview";
      } else if (args.tag) tag = args.tag;
      else {
        log("Suche das neueste stabile QuestieDB-Release bei api.github.com ...");
        const list = parseJson(await downloadWithRetry({ ...net, url: API_URL, maxBytes: MAX_JSON_BYTES, accept: "application/vnd.github+json" }), "GitHub-Antwort");
        tag = pickStableTag(list);
      }
      log(`Pruefe QuestieDB-Release ${tag} bei github.com ...`);
      const relBuf = await downloadWithRetry({ ...net, url: assetUrl(tag, ASSET_JSON), maxBytes: MAX_JSON_BYTES });
      rel = checkReleaseJson(parseJson(relBuf, "release.json"), { tag, preview: args.preview });
      if (args.sha256 && rel.sha256 !== args.sha256) throw new FetchError("SHA-256 laut release.json passt nicht zum angegebenen Pin (--sha256); abgelehnt.");
      if (before && !args.force && before.version === rel.version && before.zipSha256 === rel.sha256 && before.channel === (args.preview ? "preview" : "stable")) {
        const fixesOk = await readFile(paths.fixesFile, "utf8").then((t) => JSON.parse(t)?.tocSha256 === before.tocSha256, () => false);
        if (fixesOk) {
          log(`QuestieDB ${rel.version} ist bereits geladen (${before.fetchedAt}). Kein Download noetig.`);
          return { status: "current", exitCode: 0, version: rel.version };
        }
      }
      zip = await downloadWithRetry({ ...net, url: assetUrl(tag, ASSET_ZIP), maxBytes: Math.min(MAX_ZIP_BYTES, rel.bytes) });
      verifyArchive(zip, rel);
      if (args.sha256 && sha256(zip) !== args.sha256) throw new FetchError("SHA-256 des Archivs passt nicht zum angegebenen Pin (--sha256); abgelehnt.");
      log(`Archiv geladen und Pruefsumme stimmt: ${mb(zip.length)} MB.`);
    }

    const { toc, info, modified } = extractToc(zip);
    if (rel) {
      if (info.version !== rel.version) throw new FetchError(`TOC-Version ${info.version || "?"} passt nicht zur release.json (${rel.version}); abgelehnt.`);
      if (info.contractVersion !== rel.contractVersion) throw new FetchError(`TOC-Contract ${info.contractVersion} passt nicht zur release.json (${rel.contractVersion}); abgelehnt.`);
    }
    const contractMin = rel?.minSupportedContract ?? 1;
    if (info.contractVersion > KNOWN_CONTRACT_VERSION) warn(`HINWEIS: Contract ${info.contractVersion} (bekannt bis ${KNOWN_CONTRACT_VERSION}); das Release sichert Kompatibilitaet ab Contract ${contractMin} zu. Daten bitte pruefen.`);
    const fixes = extractFixes(zip);
    log(`QuestieDB ${info.version}: ${info.counts.quests} Quest-, ${info.counts.npcs} NPC-, ${info.counts.objects} Objekt-, ${info.counts.items} Item-Eintraege (TOC ${mb(toc.length)} MB, Contract ${info.contractVersion}).`);
    const fc = fixes.counts;
    log(`  Laufzeitkorrekturen: ${fc.read} gelesen (${fc.horde} Horde, ${fc.neutral} fraktionsneutral), ${fc.allianceSkipped} Allianz uebergangen, ${fc.nonLiteral} nicht-literal (nicht uebernommen), ${fc.files}/${FIX_ENTRIES.length} Dateien.`);
    if (fc.missingFiles > 0) warn(`WARNUNG: ${fc.missingFiles} Korrektur-Datei(en) fehlen im Archiv - Laufzeitkorrekturen unvollstaendig (siehe fixes.json "findings").`);

    const previous = before?.counts?.quests ?? 0;
    if (!args.force && previous >= MIN_PLAUSIBLE_BASE && info.counts.quests < previous * MIN_PLAUSIBLE_RATIO) {
      throw new FetchError(`Neues Release deutlich kleiner als bisher (${info.counts.quests} statt ${previous} Quests) - vermutlich unvollstaendig. Mit --force trotzdem uebernehmen.`);
    }
    if (args.dryRun) {
      log("Trockenlauf (--dry-run): es wurde nichts geschrieben.");
      return { status: "dry-run", exitCode: 0, version: info.version, counts: info.counts };
    }

    const corrFiles = [...FIX_ENTRIES, ...ENUM_ENTRIES].filter((e) => fixes.buffers.has(e.entry));
    const stamp = {
      schema: STAMP_SCHEMA,
      source: args.fromZip !== undefined ? "file" : `https://github.com/${REPO}/releases/tag/${tag}`,
      channel: args.preview ? "preview" : "stable",
      verified: Boolean(rel),
      tag: tag ?? "",
      entry: TOC_ENTRY,
      version: info.version,
      buildCommit: info.buildCommit,
      contractVersion: info.contractVersion,
      minSupportedContract: contractMin,
      flavor: info.flavor,
      archiveModified: modified,
      fetchedAt: (opts.now ?? new Date()).toISOString(),
      zipBytes: zip.length,
      zipSha256: sha256(zip),
      tocBytes: toc.length,
      tocSha256: sha256(toc),
      counts: info.counts,
    };
    const fixesOut = { schema: FIXES_SCHEMA, tocSha256: stamp.tocSha256, version: info.version, quest: fixes.quest, npc: fixes.npc, item: fixes.item, object: fixes.object, sources: fixes.sources, counts: fixes.counts, files: fixes.files, findings: fixes.findings };
    // Stempel zuerst entfernen: ein Abbruch zwischen TOC und Stempel gilt nie als gueltiger Stand
    try {
      await assertNoLinks(root, paths.tocFile);
      await mkdir(path.dirname(paths.tocFile), { recursive: true });
      await rm(paths.stampFile, { force: true });
      await writeAtomic(paths.tocFile, toc);
      // Korrektur-Dateien: feste Namen aus FIX_ENTRIES/ENUM_ENTRIES (nie aus dem Archiv), alte Staende vorher entfernen
      const addonDir = path.dirname(paths.tocFile);
      await rm(path.join(addonDir, "src"), { recursive: true, force: true });
      for (const { entry } of corrFiles) {
        const target = path.join(addonDir, ...entry.slice("QuestieDB/".length).split("/"));
        await assertNoLinks(root, target);
        await mkdir(path.dirname(target), { recursive: true });
        await writeAtomic(target, fixes.buffers.get(entry));
      }
      await writeAtomic(paths.fixesFile, JSON.stringify(fixesOut) + "\n");
      await writeAtomic(paths.stampFile, JSON.stringify(stamp, null, 2) + "\n");
    } catch (err) {
      throw new FetchError(`Release konnte nicht gespeichert werden (${err instanceof Error ? err.message : "unbekannt"}).`);
    }
    log(`Geschrieben: data-capture/questiedb-release (${info.version}, SHA-256 ${stamp.tocSha256.slice(0, 12)}...).`);
    return { status: "updated", exitCode: 0, version: info.version, counts: info.counts, stamp, fixesCounts: fixes.counts };
  } catch (err) {
    const e = err instanceof FetchError ? err : new FetchError(`Unerwarteter Fehler: ${err instanceof Error ? err.message : String(err)}`);
    return failure(e, args, { log, warn, root });
  }
}

async function failure(err, args, { log, warn, root }) {
  const after = await readStamp(releasePaths(root).stampFile);
  const kept = after !== null;
  const msg = kept
    ? `QuestieDB-Release nicht aktualisiert (${err.message}). Bisheriger Stand bleibt in Gebrauch (${after.version}, geladen ${after.fetchedAt}).`
    : `QuestieDB-Release konnte nicht geladen werden (${err.message}). Es gibt noch keinen geladenen Stand; als Rueckfall dient CHRONICLE_QUESTIE_TOC bzw. die QuestieDB aus WOW_DIR (.env).`;
  if (args.soft || (err.network && kept)) {
    (kept ? log : warn)(msg);
    return { status: kept ? "kept" : "failed", exitCode: 0, reason: err.message };
  }
  warn(`FEHLER: ${msg}`);
  return { status: kept ? "kept" : "failed", exitCode: 1, reason: err.message };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2))
    .then((r) => {
      process.exitCode = r.exitCode;
    })
    .catch((err) => {
      console.error(`FEHLER: ${err instanceof Error ? err.message : String(err)}`);
      console.error("Der bisherige Stand (falls vorhanden) bleibt unveraendert.");
      process.exitCode = 1;
    });
}
