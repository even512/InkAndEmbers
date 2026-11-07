// Prueft, ob die gepinnten Fremddaten-Staende noch aktuell sind (nur lesen, nichts wird geaendert oder geladen):
//   - QuestieDB: gepinnte Version (addon/InkAndEmbers_QuestData/InkAndEmbers_QuestData.toc, X-QuestieDB-Version) gegen das neueste
//     STABILE Release (kein Prerelease, kein Entwurf) von github.com/Questie/QuestieDB
//   - What's Training?: gepinnter Commit (PINNED_COMMIT in scripts/build-trainer-data.mjs) gegen master von
//     github.com/fusionpit/WhatsTraining; relevant sind nur Aenderungen unter Classes/Camelot/ (dazu gehoert QuestSpells.lua)
//
// Aufruf:  node scripts/check-data-sources.mjs [--json] [--help]
//   --json   eine Zeile JSON statt Text (fuer automatische Abrufe)
// Netz: nur ueber die GitHub-CLI (`gh api`, feste Endpunkte, kein Shell-Aufruf, Zeitlimit); der Commit kommt aus dem Repo und wird
// vorher als 40-stelliger Hex-Wert geprueft. Kein gh, kein Netz, Zeitlimit, Antwort unlesbar -> "unbekannt" (nie ein falsches "aktuell").
// Exit-Codes: 0 = beide aktuell, 1 = mindestens ein neuerer Stand, 2 = mindestens ein Stand unbekannt und keiner neuer, 3 = Aufruffehler.

import { execFileSync, spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { PINNED_COMMIT } from "./build-trainer-data.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const QUEST_TOC = path.join(ROOT, "addon", "InkAndEmbers_QuestData", "InkAndEmbers_QuestData.toc");
export const QUESTIE_REPO = "Questie/QuestieDB";
export const TRAINING_REPO = "fusionpit/WhatsTraining";
/** Pfade im What's-Training-Repo, deren Aenderung einen neuen Stand bedeutet (Classes/Camelot/<Klasse>.lua und QuestSpells.lua) */
export const TRAINING_PATH = "Classes/Camelot/";
export const GH_TIMEOUT_MS = 30_000;
export const STATUS = Object.freeze({ NEW: "neu", CURRENT: "aktuell", UNKNOWN: "unbekannt" });

const VERSION_RE = /^\d{1,3}\.\d{1,3}\.\d{1,3}$/;
const TAG_RE = /^v(\d{1,3}\.\d{1,3}\.\d{1,3})$/;
const COMMIT_RE = /^[0-9a-f]{40}$/;
/** Die compare-API liefert hoechstens 300 Dateien; ab dieser Zahl ist die Liste moeglicherweise abgeschnitten. */
const COMPARE_FILE_CAP = 300;

// ---------------------------------------------------------------- Parser (ohne Netz)

/** X-QuestieDB-Version aus dem Text der Daten-TOC; null, wenn sie fehlt oder kein x.y.z ist. */
export function parseQuestDataToc(text) {
  const m = /^##\s*X-QuestieDB-Version:[ \t]*(\S+)[ \t]*$/m.exec(String(text ?? ""));
  return m && VERSION_RE.test(m[1]) ? m[1] : null;
}

/** [major, minor, patch] einer Version "x.y.z" */
const parts = (v) => v.split(".").map(Number);

/** -1, 0 oder 1 (a gegen b); beide muessen "x.y.z" sein. */
export function compareVersions(a, b) {
  const x = parts(a);
  const y = parts(b);
  for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] < y[i] ? -1 : 1;
  return 0;
}

/**
 * Antwort von GET /repos/Questie/QuestieDB/releases (JSON-Text oder Array): das hoechste STABILE Release
 * (Tag vX.Y.Z, kein Prerelease, kein Entwurf). Rueckgabe { tag, version, published } oder null (nichts Passendes / kaputt).
 */
export function newestStable(json) {
  let list = json;
  if (typeof json === "string") {
    try {
      list = JSON.parse(json);
    } catch {
      return null;
    }
  }
  if (!Array.isArray(list)) return null;
  let best = null;
  for (const r of list) {
    if (!r || typeof r !== "object" || r.prerelease !== false || r.draft !== false) continue;
    const m = typeof r.tag_name === "string" ? TAG_RE.exec(r.tag_name) : null;
    if (!m) continue;
    if (!best || compareVersions(m[1], best.version) > 0) {
      best = { tag: r.tag_name, version: m[1], published: typeof r.published_at === "string" ? r.published_at.slice(0, 10) : null };
    }
  }
  return best;
}

/**
 * Antwort von GET /repos/fusionpit/WhatsTraining/compare/<gepinnt>...master (JSON-Text oder Objekt), reduziert auf
 * { status, aheadBy, relevant: [Dateien unter Classes/Camelot/], truncated }; null bei Unbrauchbarem.
 */
export function parseCompare(json, prefix = TRAINING_PATH) {
  let o = json;
  if (typeof json === "string") {
    try {
      o = JSON.parse(json);
    } catch {
      return null;
    }
  }
  if (!o || typeof o !== "object" || typeof o.status !== "string" || !Number.isSafeInteger(o.ahead_by)) return null;
  const files = Array.isArray(o.files) ? o.files : [];
  const names = files.map((f) => (f && typeof f.filename === "string" ? f.filename : ""));
  return {
    status: o.status,
    aheadBy: o.ahead_by,
    relevant: names.filter((n) => n.startsWith(prefix)).slice(0, 20),
    truncated: names.length >= COMPARE_FILE_CAP,
  };
}

// ---------------------------------------------------------------- Bewertung

const short = (c) => String(c).slice(0, 7);

/** pinned: "x.y.z" oder null; latest: Ergebnis von newestStable oder null (Netz/Antwort unbrauchbar) */
export function judgeQuestie(pinned, latest, why = "") {
  if (!pinned) return { name: "QuestieDB", status: STATUS.UNKNOWN, text: "gepinnte Version nicht lesbar (X-QuestieDB-Version in der Daten-TOC)" };
  if (!latest) return { name: "QuestieDB", status: STATUS.UNKNOWN, text: `gepinnt ${pinned}, neuester Stand nicht abrufbar${why ? ` (${why})` : ""}` };
  if (compareVersions(latest.version, pinned) > 0) {
    return { name: "QuestieDB", status: STATUS.NEW, text: `gepinnt ${pinned}, neuestes stabiles Release ${latest.version}${latest.published ? ` (${latest.published})` : ""}` };
  }
  return { name: "QuestieDB", status: STATUS.CURRENT, text: `gepinnt ${pinned}, neuestes stabiles Release ${latest.version}` };
}

/** pinned: 40-stelliger Commit; cmp: Ergebnis von parseCompare oder null */
export function judgeTraining(pinned, cmp, why = "") {
  const name = "What's Training";
  if (!COMMIT_RE.test(String(pinned))) return { name, status: STATUS.UNKNOWN, text: "gepinnter Commit nicht lesbar (PINNED_COMMIT in build-trainer-data.mjs)" };
  if (!cmp) return { name, status: STATUS.UNKNOWN, text: `gepinnt ${short(pinned)}, master nicht abrufbar${why ? ` (${why})` : ""}` };
  if (cmp.status === "identical") return { name, status: STATUS.CURRENT, text: `gepinnt ${short(pinned)} = master` };
  if (cmp.status !== "ahead") {
    return { name, status: STATUS.UNKNOWN, text: `gepinnt ${short(pinned)}, Vergleich mit master nicht eindeutig (Status ${cmp.status.slice(0, 20)})` };
  }
  if (cmp.relevant.length > 0) {
    return { name, status: STATUS.NEW, text: `gepinnt ${short(pinned)}, master ${cmp.aheadBy} Commits weiter, geaendert unter ${TRAINING_PATH}: ${cmp.relevant.slice(0, 5).map((f) => f.slice(TRAINING_PATH.length)).join(", ")}${cmp.relevant.length > 5 ? ", ..." : ""}` };
  }
  if (cmp.truncated) return { name, status: STATUS.UNKNOWN, text: `gepinnt ${short(pinned)}, master ${cmp.aheadBy} Commits weiter, Dateiliste zu lang zum sicheren Pruefen` };
  return { name, status: STATUS.CURRENT, text: `gepinnt ${short(pinned)}, master ${cmp.aheadBy} Commits weiter, ${TRAINING_PATH} unveraendert` };
}

/** Exit-Code aus den Einzelergebnissen: neuer Stand schlaegt unbekannt, unbekannt schlaegt aktuell. */
export function exitCodeOf(results) {
  if (results.some((r) => r.status === STATUS.NEW)) return 1;
  if (results.some((r) => r.status === STATUS.UNKNOWN)) return 2;
  return 0;
}

const LABEL = { [STATUS.NEW]: "NEUER STAND", [STATUS.CURRENT]: "aktuell", [STATUS.UNKNOWN]: "UNBEKANNT (nicht geprueft)" };
export const formatResult = (r) => `${r.name}: ${r.text} -> ${LABEL[r.status]}`;

// ---------------------------------------------------------------- Netz (gh api)

/** gh api <endpoint>; Rueckgabe { ok, text, why }. `run` ist austauschbar (Tests). */
export function ghApi(endpoint, run = execFileSync) {
  try {
    const text = run("gh", ["api", endpoint], { encoding: "utf8", timeout: GH_TIMEOUT_MS, maxBuffer: 16 * 1024 * 1024, windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
    return { ok: true, text: String(text) };
  } catch (e) {
    const code = e && typeof e === "object" ? e.code : "";
    const why = code === "ENOENT" ? "gh nicht installiert" : code === "ETIMEDOUT" ? "Zeitlimit" : "gh api fehlgeschlagen";
    return { ok: false, text: "", why };
  }
}

/** Beide Pruefungen; pins = { questie: "x.y.z"|null, training: commit }, run = gh-Ersatz fuer Tests */
export function check(pins, run = execFileSync) {
  const rel = ghApi(`repos/${QUESTIE_REPO}/releases?per_page=30`, run);
  const latest = rel.ok ? newestStable(rel.text) : null;
  const questie = judgeQuestie(pins.questie, latest, rel.ok ? "keine stabile Version in der Antwort" : rel.why);
  let cmp = null;
  let why = "";
  if (COMMIT_RE.test(String(pins.training))) {
    const r = ghApi(`repos/${TRAINING_REPO}/compare/${pins.training}...master`, run);
    cmp = r.ok ? parseCompare(r.text) : null;
    why = r.ok ? "Antwort unlesbar" : r.why;
  }
  const training = judgeTraining(pins.training, cmp, why);
  return [questie, training];
}

/** Gepinnte Staende aus dem Repo lesen (Daten-TOC, build-trainer-data.mjs) */
export function readPins(tocFile = QUEST_TOC) {
  let questie = null;
  try {
    questie = parseQuestDataToc(readFileSync(tocFile, "utf8"));
  } catch {
    questie = null;
  }
  return { questie, training: PINNED_COMMIT };
}

export function main(argv, { run = execFileSync, pins = readPins(), out = (s) => console.log(s) } = {}) {
  const known = new Set(["--json", "--help"]);
  const bad = argv.find((a) => !known.has(a));
  if (bad !== undefined) {
    out(`Unbekanntes Argument: ${bad.slice(0, 40)}. Aufruf: node scripts/check-data-sources.mjs [--json]`);
    return 3;
  }
  if (argv.includes("--help")) {
    out("check-data-sources: prueft QuestieDB (Release) und What's Training (master, Classes/Camelot) gegen den neuesten oeffentlichen Stand.\nAufruf: node scripts/check-data-sources.mjs [--json]\nExit: 0 aktuell, 1 neuerer Stand, 2 unbekannt, 3 Aufruffehler.");
    return 0;
  }
  const results = check(pins, run);
  const code = exitCodeOf(results);
  if (argv.includes("--json")) out(JSON.stringify({ code, results }));
  else {
    for (const r of results) out(formatResult(r));
    out(code === 0 ? "Alle Fremddaten-Staende aktuell." : code === 1 ? "Mindestens ein neuerer Stand: vor dem Release klaeren (docs/release-hotfix.md)." : "Mindestens ein Stand konnte nicht geprueft werden: nicht als aktuell werten, spaeter wiederholen.");
  }
  return code;
}

// ---------------------------------------------------------------- Automatischer Abruf

/** Hoechstens eine Pruefung je Intervall; der Zeitpunkt zaehlt auch bei einem Fehlversuch (kein Hammern bei Netzproblemen). */
export const FEED_INTERVAL_MS = 6 * 60 * 60 * 1000;
export const FEED_TIMEOUT_MS = 90_000;

/**
 * Fuer automatische Abrufe: ruft (hoechstens alle 6 Stunden) dieses Skript mit --json als Kindprozess auf (feste Argumente, keine
 * Shell, Zeitlimit) und meldet einen NEUEN Stand als Text. Veraendert nur `state.dataAt` (Zeitpunkt des Versuchs) und
 * `state.dataText` (zuletzt gemeldeter Text); schreibt sonst nichts. Rueckgabe { changed, text, warn }:
 *   changed  = der zu meldende Text hat sich gegenueber dem zuletzt gemeldeten geaendert (auch auf "" = nichts Neues mehr)
 *   text     = "<Name>: <Text>" je neuem Stand, mit " | " getrennt; "" = kein neuer Stand
 *   warn     = Hinweistext bei Fehler/unbekanntem Stand (dann bleibt der zuletzt gemeldete Text unveraendert), sonst null
 */
export function feedCheck(state, nowMs = Date.now(), { run = spawnSync, script = fileURLToPath(import.meta.url) } = {}) {
  const none = { changed: false, text: "", warn: null };
  const last = Number.isFinite(state.dataAt) ? state.dataAt : 0;
  if (nowMs - last < FEED_INTERVAL_MS && nowMs >= last) return none;
  state.dataAt = nowMs;
  const r = run(process.execPath, [script, "--json"], { encoding: "utf8", timeout: FEED_TIMEOUT_MS, windowsHide: true, shell: false, maxBuffer: 1024 * 1024 });
  if (!r || r.error || ![0, 1, 2].includes(r.status)) return { ...none, warn: "Datenstaende: Pruefung nicht ausfuehrbar" };
  let j;
  try {
    j = JSON.parse(String(r.stdout ?? ""));
  } catch {
    return { ...none, warn: "Datenstaende: Antwort der Pruefung unlesbar" };
  }
  const ok = j && Array.isArray(j.results) && j.results.every((x) => x && typeof x.name === "string" && typeof x.text === "string" && Object.values(STATUS).includes(x.status));
  if (!ok) return { ...none, warn: "Datenstaende: Antwort der Pruefung unlesbar" };
  const news = j.results.filter((x) => x.status === STATUS.NEW);
  if (news.length === 0 && j.results.some((x) => x.status === STATUS.UNKNOWN)) return { ...none, warn: "Datenstaende: Stand nicht pruefbar (Netz oder gh)" };
  const text = news.map((x) => `${x.name}: ${x.text}`).join(" | ").slice(0, 600);
  const changed = text !== (typeof state.dataText === "string" ? state.dataText : "");
  state.dataText = text;
  return { changed, text, warn: null };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
