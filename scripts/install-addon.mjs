// Installiert das Addon InkAndEmbers und seine Datenaddons InkAndEmbers_Data (LoadOnDemand, To-Do-Listen) und
// InkAndEmbers_QuestData (LoadOnDemand, offene Quests) in den WoW-Ordner (alle bei jedem Lauf, je in ihren eigenen Addon-Ordner).
//
// Aufruf:  node scripts/install-addon.mjs [--retail] [--dry-run] [--help]
//   (ohne Flag)  Ziel: <WOW_DIR>\_forever_\Interface\AddOns\<addon>, Interface-Zeile der kopierten TOCs wird auf 16001 gesetzt
//   --retail     Ziel: <WOW_DIR>\_retail_\Interface\AddOns\<addon>, Interface-Zeile der kopierten TOCs wird auf 120105 gesetzt
// In den Quell-TOCs steht fuer das Release "## Interface: 120105, 16001" und "## Version: @project-version@" (ersetzt der Packager);
// lokal setzt dieses Skript je Spielversion einen einzelnen Interface-Wert und ersetzt @project-version@ durch <package.json-Version>-dev.
// Alte Ordner EveN_ForeverChronicle* (vor der Umbenennung) im Ziel werden mitentfernt (LEGACY_ADDONS), damit nicht zwei Kopien laufen.
//   --dry-run    zeigt nur, was passieren wuerde; schreibt und loescht nichts
// WOW_DIR kommt aus der Datei .env im Projektordner (siehe .env.example).
// Exit-Codes: 0 = ok, 1 = Fehler (fehlende/ungueltige Config, Quelle fehlt, Schreibfehler, unbekannte Option)
//
// Sicherheit:
// - Installiert wird inkrementell: unveraenderte Dateien (byte-gleich, echte Datei) werden nicht angefasst, geaenderte/neue geschrieben,
//   nur Eintraege entfernt, die es in der Quelle nicht (mehr) gibt. So bleibt z. B. eine vom laufenden Client geoeffnete Schrift unberuehrt.
// - Geschrieben und entfernt wird ausschliesslich in <WOW_DIR>\<_forever_|_retail_>\Interface\AddOns\InkAndEmbers und
//   ...\Interface\AddOns\InkAndEmbers_Data bzw. _QuestData (Allowlist ADDONS; Pfad wird normalisiert, muss innerhalb von WOW_DIR liegen
//   und auf \Interface\AddOns\<addon> enden).
// - Symlinks/Junctions werden nirgends gefolgt: weder im Zielpfad noch in der Quelle (Symlink im Ziel = Abbruch).
// - Kopiert werden nur Dateien mit Endung .toc/.lua/.xml/.tga/.ttf/.txt/.ogg/.md (.ttf = Handschrift Caveat, .txt = deren OFL-Lizenz bzw. Klang-Lizenzen, .ogg = CC0-Buchklaenge bis MAX_OGG_BYTES, .md = Lizenz-Notizen) sowie die Datei LICENSE (ohne Endung), jeweils mit harmlosem Namen (Allowlist), Unterordner nur mit harmlosem Namen.
// - Entfernt wird nur Ueberzaehliges im eigenen Addon-Ordner (Links per unlink, nie gefolgt), nie etwas ausserhalb.
// - Das Ziel wird unmittelbar vor dem ersten Schreiben/Loeschen erneut geprueft (kein Link, echter Ordner).

import { existsSync } from "node:fs";
import { lstat, mkdir, readdir, readFile, rmdir, unlink, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const ADDON_NAME = "InkAndEmbers";
export const DATA_ADDON_NAME = "InkAndEmbers_Data";
export const QUEST_DATA_ADDON_NAME = "InkAndEmbers_QuestData";
/** alte Ordnernamen (vor der Umbenennung); werden im Ziel entfernt, sonst liefen zwei Kopien (nur diese drei Namen, exakt) */
export const LEGACY_ADDONS = Object.freeze(["EveN_ForeverChronicle", "EveN_ForeverChronicle_Data", "EveN_ForeverChronicle_QuestData"]);
/** einzige Addon-Ordner, in die geschrieben werden darf (Hauptaddon zuerst) */
export const ADDONS = Object.freeze([ADDON_NAME, DATA_ADDON_NAME, QUEST_DATA_ADDON_NAME]);
const SOURCE_DIR = path.join(ROOT, "addon", ADDON_NAME);
const TOC_NAME = `${ADDON_NAME}.toc`;
export const RETAIL_INTERFACE = "120105";
export const FOREVER_INTERFACE = "16001";
const ALLOWED_EXT = new Set([".toc", ".lua", ".xml", ".tga", ".ttf", ".txt", ".ogg", ".md"]);
const ALLOWED_NAMES = new Set(["LICENSE"]); // Lizenzdatei ohne Endung (je Addon-Ordner)
export const VERSION_PLACEHOLDER = "@project-version@";
const NAME_OK = /^[A-Za-z0-9_.-]+$/;
const MAX_FILE_BYTES = 1024 * 1024;
const MAX_OGG_BYTES = 512 * 1024; // kurze Buchklaenge (je ca. 10 KB)
const MAX_TGA_BYTES = 1024 * 1024 * 4 + 1024; // 1024 x 1024 x 32 bit + Kopf
const MAX_DEPTH = 3;
const KNOWN_FLAGS = new Set(["--retail", "--dry-run", "--help", "-h"]);

const HELP = `InkAndEmbers: Addon und Datenaddon in den WoW-Ordner installieren

Aufruf:
  npm run install-addon [-- --retail] [-- --dry-run]
  node scripts/install-addon.mjs [--retail] [--dry-run] [--help]

Optionen:
  --retail    nach <WOW_DIR>\\_retail_ installieren und in den kopierten TOCs
              die Interface-Zeile auf ${RETAIL_INTERFACE} setzen (Retail-Test)
  --dry-run   nur anzeigen, was passieren wuerde; nichts schreiben oder loeschen
  --help, -h  diese Hilfe

Ohne --retail wird nach <WOW_DIR>\\_forever_ installiert (Interface ${FOREVER_INTERFACE}).
In beiden Faellen wird @project-version@ in den TOCs durch <package.json-Version>-dev ersetzt.
Zielordner: <WOW_DIR>\\<_forever_|_retail_>\\Interface\\AddOns\\${ADDON_NAME}
       und  <WOW_DIR>\\<_forever_|_retail_>\\Interface\\AddOns\\${DATA_ADDON_NAME} (Datenaddon, LoadOnDemand)

Konfiguration: WOW_DIR steht in der Datei .env im Projektordner (Vorlage: .env.example),
z. B.  WOW_DIR=D:\\World of Warcraft
Inkrementell: unveraenderte Dateien werden nicht angefasst, geaenderte/neue geschrieben,
nur Ueberzaehliges im eigenen Addon-Ordner entfernt.
Bei NEUEN Dateien (z. B. neue .tga/.ttf/.ogg) das Spiel komplett neu starten, sonst reicht /reload.
`;

/** Wert eines Schluessels aus .env-Text lesen (KEY=Wert, optional in Anfuehrungszeichen, # beginnt Kommentarzeile). */
export function parseEnvValue(text, key) {
  for (const line of text.split(/\r?\n/)) {
    if (/^\s*#/.test(line)) continue;
    const m = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/.exec(line);
    if (!m || m[1] !== key) continue;
    let v = m[2];
    if (/^".*"$/.test(v) || /^'.*'$/.test(v)) v = v.slice(1, -1);
    return v;
  }
  return undefined;
}

/** Kommandozeile pruefen; wirft bei unbekannten Flags oder Positionsargumenten. */
export function parseArgs(argv) {
  const unknown = argv.filter((a) => !KNOWN_FLAGS.has(a));
  if (unknown.length) {
    throw new Error(`Unbekannte Option bzw. unerwartetes Argument: ${unknown.join(" ")}\nHilfe: npm run install-addon -- --help`);
  }
  return { help: argv.includes("--help") || argv.includes("-h"), retail: argv.includes("--retail"), dry: argv.includes("--dry-run") };
}

/** Beide Pfade normalisiert, Vergleich unter Windows ohne Gross-/Kleinschreibung. */
function norm(p) {
  const r = path.resolve(p);
  return process.platform === "win32" ? r.toLowerCase() : r;
}

/** liegt child echt innerhalb von parent? */
export function isInside(parent, child) {
  const rel = path.relative(norm(parent), norm(child));
  return rel !== "" && !rel.startsWith("..") && !path.isAbsolute(rel);
}

/**
 * Zielordner bestimmen und gegen die Allowlist pruefen.
 * Ergebnis endet immer auf <_forever_|_retail_>\Interface\AddOns\<addonName> und liegt innerhalb von WOW_DIR.
 * addonName muss in ADDONS stehen (Standard: Hauptaddon).
 */
export function resolveTarget(wowDir, retail, addonName = ADDON_NAME) {
  if (!ADDONS.includes(addonName)) throw new Error(`Addon ausserhalb der Allowlist: ${printable(addonName)}`);
  const v = String(wowDir ?? "").trim().replace(/^"(.*)"$/, "$1");
  if (v === "") throw new Error("WOW_DIR ist leer.");
  if (v.includes("\0")) throw new Error("WOW_DIR enthaelt ungueltige Zeichen.");
  if (!path.isAbsolute(v)) throw new Error(`WOW_DIR muss ein absoluter Pfad sein (erhalten: "${v}").`);
  const base = path.resolve(v);
  const flavor = retail ? "_retail_" : "_forever_";
  const flavorDir = path.join(base, flavor);
  const addons = path.join(flavorDir, "Interface", "AddOns");
  const target = path.join(addons, addonName);
  const tail = target.split(path.sep).slice(-3).join("\\").toLowerCase();
  if (tail !== `interface\\addons\\${addonName.toLowerCase()}` || !isInside(base, target)) {
    throw new Error(`Zielpfad ausserhalb der Allowlist (\\Interface\\AddOns\\${addonName} innerhalb von WOW_DIR).`);
  }
  return { base, flavor, flavorDir, addons, target };
}

/** Interface-Zeile der TOC auf den Retail-Wert setzen; wirft, wenn keine genau eine Zeile gefunden wird. */
export function rewriteInterface(tocText, value = RETAIL_INTERFACE) {
  const re = /^## *Interface *:.*$/gm;
  const hits = tocText.match(re) ?? [];
  if (hits.length !== 1) throw new Error(`TOC muss genau eine "## Interface:"-Zeile haben (gefunden: ${hits.length}).`);
  return tocText.replace(re, `## Interface: ${value}`);
}

/** @project-version@ der TOC durch einen lokalen Wert ersetzen (der Packager macht das im Release selbst). */
export function rewriteVersion(tocText, value) {
  return tocText.split(VERSION_PLACEHOLDER).join(value);
}

/** Groessenlimit je Endung (.tga gross, .ogg klein, sonst 1 MB) */
export function maxBytes(name) {
  const ext = path.extname(name).toLowerCase();
  if (ext === ".tga") return MAX_TGA_BYTES;
  if (ext === ".ogg") return MAX_OGG_BYTES;
  return MAX_FILE_BYTES;
}

/** Quellordner einlesen: Liste {rel, from, size} aller erlaubten Dateien; Fremdes wird gemeldet (skipped). Folgt keinen Symlinks. */
export async function listSource(dir = SOURCE_DIR, rel = "", depth = 0, acc = { files: [], skipped: [] }) {
  if (depth > MAX_DEPTH) throw new Error(`Quellordner zu tief verschachtelt: ${rel}`);
  const entries = await readdir(dir, { withFileTypes: true });
  for (const e of entries) {
    const relPath = rel ? `${rel}/${e.name}` : e.name;
    const from = path.join(dir, e.name);
    if (!NAME_OK.test(e.name) || e.name.includes("..")) {
      acc.skipped.push(relPath);
    } else if (e.isDirectory()) {
      await listSource(from, relPath, depth + 1, acc);
    } else if (e.isFile() && (ALLOWED_EXT.has(path.extname(e.name).toLowerCase()) || ALLOWED_NAMES.has(e.name))) {
      const st = await lstat(from);
      if (st.size > maxBytes(e.name)) throw new Error(`Datei zu gross: ${relPath}`);
      acc.files.push({ rel: relPath, from, size: st.size });
    } else {
      acc.skipped.push(relPath);
    }
  }
  acc.files.sort((a, b) => a.rel.localeCompare(b.rel));
  return acc;
}

async function isRealDir(p) {
  try {
    const st = await lstat(p);
    return st.isDirectory() && !st.isSymbolicLink();
  } catch {
    return false;
  }
}

async function loadWowDir() {
  const envFile = path.join(ROOT, ".env");
  if (existsSync(envFile)) {
    const v = parseEnvValue(await readFile(envFile, "utf8"), "WOW_DIR");
    if (v) return v;
  }
  return "";
}

/** Dateiname fuer die Ausgabe: nur druckbare ASCII-Zeichen (Steuer- und Escape-Zeichen aus fremden Namen werden zu "?"). */
export function printable(name) {
  return String(name).replace(/[^ -~]/g, "?");
}

/** Einen Eintrag im Addon-Ordner entfernen: Links (Symlink/Junction) und Dateien per unlink, echte Ordner rekursiv. Folgt nie einem Link. */
async function removeEntry(p) {
  const st = await lstat(p);
  if (st.isSymbolicLink() || !st.isDirectory()) {
    await unlink(p);
    return;
  }
  for (const name of await readdir(p)) await removeEntry(path.join(p, name));
  await rmdir(p);
}

/** lstat, aber ENOENT/ENOTDIR -> null. */
async function lstatOrNull(p) {
  try {
    return await lstat(p);
  } catch (err) {
    if (err && (err.code === "ENOENT" || err.code === "ENOTDIR")) return null;
    throw err;
  }
}

/** Schluessel fuer Namensvergleiche: unter Windows ohne Gross-/Kleinschreibung. */
const key = (rel) => (process.platform === "win32" ? rel.toLowerCase() : rel);

/**
 * Addon-Ordner inkrementell an die Quelle angleichen (der Ordner selbst bleibt).
 * 1. Jede Quelldatei: liegt am Ziel schon eine echte Datei (kein Link) mit byte-gleichem Inhalt, wird sie nicht angefasst.
 *    Sonst wird sie geschrieben; steht am Zielpfad ein Ordner oder Link, wird der vorher entfernt.
 * 2. Danach werden Eintraege entfernt, die es in der Quelle nicht (mehr) gibt (Links per unlink, nie gefolgt).
 * Prueft das Ziel unmittelbar vor dem ersten Schreiben/Loeschen erneut (kein Link, echter Ordner).
 * opts: { dry, log, tocOut, tocName } - dry schreibt/loescht nichts; tocOut ersetzt den Inhalt der TOC tocName (Standard: TOC des
 * Hauptaddons; Retail-Umschreibung).
 * Rueckgabe: { written, unchanged, removed }.
 */
export async function syncTarget(target, files, opts = {}) {
  const { dry = false, log = () => {}, tocOut, tocName = TOC_NAME } = opts;
  const res = { written: 0, unchanged: 0, removed: 0 };

  // Zielordner unmittelbar vor dem ersten Schreiben/Loeschen erneut pruefen.
  const tst = await lstatOrNull(target);
  if (tst && (tst.isSymbolicLink() || !tst.isDirectory())) throw new Error(`Zielordner ist ein Symlink oder kein Ordner; Abbruch: ${target}`);
  if (!tst && !dry) await mkdir(target);
  let targetReal = Boolean(tst);
  const planned = new Set(); // im Trockenlauf bereits als "wuerde entfernen" gezaehlte Pfade

  const wantFiles = new Set();
  const wantDirs = new Set();
  for (const f of files) {
    const parts = f.rel.split("/");
    wantFiles.add(key(f.rel));
    for (let i = 1; i < parts.length; i++) wantDirs.add(key(parts.slice(0, i).join("/")));
  }

  // Phase 1: Dateien angleichen.
  for (const f of files) {
    const parts = f.rel.split("/");
    const to = path.join(target, ...parts);
    if (!isInside(target, to)) throw new Error(`Ungueltiger Dateipfad: ${f.rel}`);

    // Zwischenordner: muessen echte Ordner sein; Datei oder Link an ihrer Stelle wird entfernt (Trockenlauf: nur gemeldet).
    let chainClean = targetReal;
    for (let i = 1; i < parts.length && chainClean; i++) {
      const dirRel = parts.slice(0, i).join("/");
      const dirPath = path.join(target, ...parts.slice(0, i));
      if (!isInside(target, dirPath)) throw new Error(`Ungueltiger Dateipfad: ${f.rel}`);
      const st = await lstatOrNull(dirPath);
      if (!st) {
        chainClean = false;
      } else if (st.isSymbolicLink() || !st.isDirectory()) {
        if (!planned.has(dirPath)) {
          log(`  ${dry ? "wuerde entfernen" : "entferne"} (Ordner erwartet): ${printable(dirRel)}`);
          res.removed++;
        }
        if (dry) {
          planned.add(dirPath);
          chainClean = false;
        } else {
          await removeEntry(dirPath);
        }
      }
    }

    const data = f.rel === tocName && tocOut !== undefined ? Buffer.from(tocOut, "utf8") : await readFile(f.from);
    let existed = false;
    if (chainClean) {
      const st = await lstatOrNull(to);
      if (st) {
        existed = true;
        if (st.isFile() && !st.isSymbolicLink()) {
          if (st.size === data.length && (await readFile(to)).equals(data)) {
            res.unchanged++;
            continue;
          }
        } else {
          log(`  ${dry ? "wuerde entfernen" : "entferne"} (Datei erwartet): ${printable(f.rel)}`);
          res.removed++;
          if (dry) planned.add(to);
          else await removeEntry(to);
        }
      }
    }
    log(`  ${dry ? "wuerde " : ""}${existed ? (dry ? "aktualisieren" : "aktualisiere") : dry ? "kopieren" : "kopiere"}: ${f.rel}`);
    res.written++;
    if (dry) continue;
    await mkdir(path.dirname(to), { recursive: true });
    await writeFile(to, data);
  }

  // Phase 2: Ueberzaehliges im Ziel entfernen (rekursiv, Links nie folgen).
  const sweep = async (dir, rel) => {
    for (const name of await readdir(dir)) {
      const childRel = rel ? `${rel}/${name}` : name;
      const childPath = path.join(dir, name);
      if (!isInside(target, childPath)) throw new Error(`Ungueltiger Dateipfad: ${childRel}`);
      const st = await lstat(childPath);
      const real = !st.isSymbolicLink();
      if (real && st.isDirectory() && wantDirs.has(key(childRel))) {
        await sweep(childPath, childRel);
      } else if (real && st.isFile() && wantFiles.has(key(childRel))) {
        continue;
      } else if (planned.has(childPath)) {
        continue;
      } else {
        log(`  ${dry ? "wuerde entfernen" : "entferne"}: ${printable(childRel)}`);
        res.removed++;
        if (!dry) await removeEntry(childPath);
      }
    }
  };
  // Existiert das Ziel (noch) nicht (Trockenlauf auf frischem Ziel), gibt es nichts zu entfernen.
  targetReal = Boolean(await lstatOrNull(target));
  if (targetReal) await sweep(target, "");
  return res;
}

/**
 * Alte Addon-Ordner (LEGACY_ADDONS) unter <...>\Interface\AddOns entfernen. Nur exakt diese Namen, nur direkt in addonsDir,
 * Links werden per unlink entfernt und nie gefolgt. Rueckgabe: Anzahl entfernter (bzw. im Trockenlauf gefundener) Ordner.
 */
export async function removeLegacy(addonsDir, opts = {}) {
  const { dry = false, log = () => {} } = opts;
  let n = 0;
  for (const name of LEGACY_ADDONS) {
    const p = path.join(addonsDir, name);
    if (!isInside(addonsDir, p) || path.dirname(norm(p)) !== norm(addonsDir)) throw new Error(`Ungueltiger Altordner: ${printable(name)}`);
    if (!(await lstatOrNull(p))) continue;
    log(`  ${dry ? "wuerde alten Ordner entfernen" : "entferne alten Ordner"}: ${name}`);
    n++;
    if (!dry) await removeEntry(p);
  }
  return n;
}

export async function main(argv) {
  const opts = parseArgs(argv);
  if (opts.help) {
    console.log(HELP);
    return;
  }

  const wowDir = await loadWowDir();
  if (!wowDir) {
    throw new Error(
      "WOW_DIR ist nicht konfiguriert. Lege im Projektordner eine Datei .env an (Vorlage: .env.example), z. B.\n" +
        "  WOW_DIR=D:\\World of Warcraft",
    );
  }
  const t = resolveTarget(wowDir, opts.retail);
  if (!(await isRealDir(t.base))) throw new Error(`WOW_DIR existiert nicht, ist kein Ordner oder ein Symlink: ${t.base}`);
  if (!(await isRealDir(t.flavorDir))) {
    throw new Error(`Der Ordner ${t.flavor} fehlt unter WOW_DIR (${t.flavorDir}). Ist die Spielversion installiert und WOW_DIR richtig?`);
  }
  if (!(await isRealDir(path.join(t.flavorDir, "Interface"))) || !(await isRealDir(t.addons))) {
    throw new Error(`Der Ordner Interface\\AddOns fehlt unter ${t.flavorDir} (oder ist ein Symlink). Stimmt WOW_DIR?`);
  }

  const devVersion = `${JSON.parse(await readFile(path.join(ROOT, "package.json"), "utf8")).version}-dev`;
  const iface = opts.retail ? RETAIL_INTERFACE : FOREVER_INTERFACE;
  // Quellen beider Addons vollstaendig pruefen und vorbereiten, bevor an einem Ziel irgendetwas angefasst wird.
  const jobs = [];
  for (const name of ADDONS) {
    const tocName = `${name}.toc`;
    const src = await listSource(name === ADDON_NAME ? SOURCE_DIR : path.join(ROOT, "addon", name));
    const toc = src.files.find((f) => f.rel === tocName);
    if (!toc) throw new Error(`Im Quellordner addon\\${name} fehlt ${tocName}.`);
    const tocText = await readFile(toc.from, "utf8");
    const target = name === ADDON_NAME ? t : resolveTarget(wowDir, opts.retail, name);
    jobs.push({ name, tocName, src, tocOut: rewriteVersion(rewriteInterface(tocText, iface), devVersion), t: target, exists: false });
  }

  // Zielordner: duerfen nicht existieren oder muessen echte Ordner (kein Symlink) sein.
  for (const job of jobs) {
    try {
      const st = await lstat(job.t.target);
      if (st.isSymbolicLink() || !st.isDirectory()) throw new Error(`Zielordner ist ein Symlink oder kein Ordner; Abbruch: ${job.t.target}`);
      job.exists = true;
    } catch (err) {
      if (!err || err.code !== "ENOENT") throw err;
    }
  }

  const dry = opts.dry;
  console.log(dry ? "Trockenlauf (--dry-run): es wird nichts geschrieben oder geloescht." : `Installiere ${ADDONS.join(" und ")} ...`);
  for (const job of jobs) {
    console.log(`Ziel: ${job.t.target}  (${opts.retail ? "Retail" : "Forever"}, Interface ${iface}, Version ${devVersion})`);
    if (!job.exists && !dry) console.log("  Addon-Ordner wird neu angelegt.");
    const r = await syncTarget(job.t.target, job.src.files, { dry, log: (line) => console.log(line), tocOut: job.tocOut, tocName: job.tocName });
    for (const s of job.src.skipped) console.log(`  uebersprungen (nicht erlaubt): ${printable(s)}`);
    console.log(
      `${job.name} fertig${dry ? " (Trockenlauf)" : ""}: ${r.written} neu/geaendert, ${r.unchanged} unveraendert, ${r.removed} entfernt.${dry ? " Es wurde nichts geschrieben oder geloescht." : ""}`,
    );
  }
  const legacy = await removeLegacy(t.addons, { dry, log: (line) => console.log(line) });
  if (legacy) console.log(`Alte Ordner ${dry ? "gefunden" : "entfernt"}: ${legacy}.`);
  if (!dry) console.log("Hinweis: Bei NEUEN Dateien oder einem neuen Addon-Ordner das Spiel komplett neu starten, sonst reicht /reload. Neu: Textur WelcomeBack.tga (Willkommen-zurück-Zettel), also /reload, im Zweifel Spiel neu starten.");
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).catch((err) => {
    console.error(`FEHLER: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  });
}
