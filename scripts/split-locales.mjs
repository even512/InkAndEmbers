// Einmaliger Locale-Split (1.1.0, Etappe E2 "modular"): verschiebt die L.add-Bloecke der Modul-Bereiche aus den Kern-Locales
// addon/InkAndEmbers/locales/<lang>_<gruppe>.lua in addon/InkAndEmbers_<Modul>/locales/<lang>.lua. Bloecke werden Zeile fuer
// Zeile uebernommen (inkl. der Kommentarzeilen direkt darueber), nichts wird umgeschrieben. Idempotent: ein zweiter Lauf findet
// keine Modul-Bloecke mehr im Kern und aendert nichts.
// Aufruf: node scripts/split-locales.mjs [--dry-run]
// Pruefung: Anzahl der Bloecke je Bereich vorher = nachher (Kern + Module); die Schluesselmengen vergleicht der Test
// tests/locale-split.test.mjs (Kern + alle Module geladen = jede Sprache hat jeden Bereich wie vorher).
// Exit-Codes: 0 ok, 1 Pruefung fehlgeschlagen.

import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const CORE_LOCALES = path.join(ROOT, "addon", "InkAndEmbers", "locales");
export const LANGS = ["enUS", "ptBR", "frFR", "esES", "ruRU", "itIT"];
const GROUPS = ["core", "journal", "model", "pages"];

// Bereich -> Modul-Ordner (Zuordnung aus dem Delta "modular", Abschnitt Locales; OpenQuests & Co. bleiben im Kern:
// Entscheidung 2)
export const AREA_MODULE = {
  "p.QuestsOffen": "InkAndEmbers_Quests", "p.QuestsDungeons": "InkAndEmbers_Quests", "p.QuestsZonen": "InkAndEmbers_Quests",
  QuestTrackActions: "InkAndEmbers_QuestTracker", QuestTrackerHide: "InkAndEmbers_QuestTracker",
  QuestItemBar: "InkAndEmbers_QuestTracker", QuestTracker: "InkAndEmbers_QuestTracker",
  "m.Rezepte": "InkAndEmbers_Crafting", "m.Rezeptbuch": "InkAndEmbers_Crafting", "m.Handwerk": "InkAndEmbers_Crafting",
  "p.Handwerk": "InkAndEmbers_Crafting", "p.HandwerkRezeptbuch": "InkAndEmbers_Crafting",
  "p.PlaeneHandwerk": "InkAndEmbers_Crafting",
  // the areas j.Einkaufszettel, ProfessionBar, AuctionDock and p.HandwerkSkillpunkt of 1.0 were removed with the work order (W5)
  // Werkauftrag (1.1.0): building blocks (W1) and the areas of the stages W2-W4 (locales/<lang>_werkbar|_werkdock|_werkplan.lua)
  WerkBarKit: "InkAndEmbers_Crafting", WerkBar: "InkAndEmbers_Crafting", WerkDock: "InkAndEmbers_Crafting", WerkPlan: "InkAndEmbers_Crafting",
  "m.Lehrplan": "InkAndEmbers_Plans", "p.Plaene": "InkAndEmbers_Plans", "p.QuestsLehrplan": "InkAndEmbers_Plans",
  Vorhaben: "InkAndEmbers_Plans", TodoTracker: "InkAndEmbers_Plans", TodoMarks: "InkAndEmbers_Plans",
  "m.CampfireTexts": "InkAndEmbers_Campfire", Smoke: "InkAndEmbers_Campfire", FireNotes: "InkAndEmbers_Campfire",
  "p.ChronikViews.Fire": "InkAndEmbers_Campfire",
};

const LANG_NAME = { enUS: "English", ptBR: "Brazilian Portuguese", frFR: "French", esES: "Spanish", ruRU: "Russian", itIT: "Italian" };
const ADD_RE = /^L\.add\("([A-Za-z]+)", "([^"]+)"/;

/** Bloecke einer Locale-Datei: { area, lang, from, to } (from = erste Kommentarzeile darueber, to = Zeile mit "})") */
export function blocks(lines) {
  const out = [];
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(ADD_RE);
    if (!m) continue;
    let end = i;
    if (!/\}\)\s*$/.test(lines[i])) {
      end = lines.findIndex((l, j) => j > i && /^\}\)\s*$/.test(l));
      if (end < 0) throw new Error(`Block ohne Ende: ${m[2]} (Zeile ${i + 1})`);
    }
    let from = i;
    const floor = out.length ? out[out.length - 1].to + 1 : 0;
    // Kommentarzeilen und Text-Helfer (local function, z. B. fire() vor m.CampfireTexts) direkt darueber gehoeren zum Block
    while (from - 1 >= floor && /^(--|local function )/.test(lines[from - 1])) from--;
    out.push({ lang: m[1], area: m[2], from, to: end });
    i = end;
  }
  return out;
}

function header(lang, folder) {
  return [
    `-- ${LANG_NAME[lang]} strings of the module ${folder} (moved from the core locales in 1.1.0 by scripts/split-locales.mjs).`,
    "-- One L.add block per area, same keys as L.ns in the module's code (deDE is the source in the code).",
    "local _, ns = ...",
    "local L = ns.Locale",
    "",
  ];
}

/** Zaehlt Bloecke je Bereich/Sprache ueber Kern- und Modul-Locales */
export function countBlocks() {
  const n = {};
  const add = (file) => {
    if (!existsSync(file)) return;
    for (const b of blocks(readFileSync(file, "utf8").split(/\r?\n/))) {
      const k = `${b.lang}|${b.area}`;
      n[k] = (n[k] ?? 0) + 1;
    }
  };
  for (const f of readdirSync(CORE_LOCALES)) add(path.join(CORE_LOCALES, f));
  for (const folder of new Set(Object.values(AREA_MODULE))) {
    const dir = path.join(ROOT, "addon", folder, "locales");
    if (existsSync(dir)) for (const f of readdirSync(dir)) add(path.join(dir, f));
  }
  return n;
}

export function split({ dry = false } = {}) {
  const before = countBlocks();
  const targets = {}; // folder -> lang -> [lines]
  const writes = [];
  let moved = 0;
  for (const lang of LANGS) {
    for (const g of GROUPS) {
      const file = path.join(CORE_LOCALES, `${lang}_${g}.lua`);
      if (!existsSync(file)) continue;
      const text = readFileSync(file, "utf8");
      const eol = text.includes("\r\n") ? "\r\n" : "\n";
      const lines = text.split(/\r?\n/);
      const drop = new Set();
      for (const b of blocks(lines)) {
        const folder = AREA_MODULE[b.area];
        if (!folder) continue;
        if (b.lang !== lang) throw new Error(`${file}: Block ${b.area} hat Sprache ${b.lang}`);
        const part = lines.slice(b.from, b.to + 1);
        ((targets[folder] ??= {})[lang] ??= []).push(...part, "");
        for (let i = b.from; i <= b.to; i++) drop.add(i);
        // eine Leerzeile hinter dem Block mitnehmen (sonst bleiben doppelte Leerzeilen stehen)
        if (lines[b.to + 1] === "" && b.to + 2 < lines.length) drop.add(b.to + 1);
        moved++;
      }
      if (drop.size) writes.push({ file, text: lines.filter((_, i) => !drop.has(i)).join(eol) });
    }
  }
  for (const [folder, byLang] of Object.entries(targets)) {
    for (const [lang, part] of Object.entries(byLang)) {
      const file = path.join(ROOT, "addon", folder, "locales", `${lang}.lua`);
      if (existsSync(file)) throw new Error(`${file} gibt es schon (Split schon gelaufen?)`);
      while (part.length && part[part.length - 1] === "") part.pop();
      writes.push({ file, text: [...header(lang, folder), ...part, ""].join("\n"), mkdir: true });
    }
  }
  if (!dry) {
    for (const w of writes) {
      if (w.mkdir) mkdirSync(path.dirname(w.file), { recursive: true });
      writeFileSync(w.file, w.text, "utf8");
    }
  }
  const after = dry ? before : countBlocks();
  const keys = new Set([...Object.keys(before), ...Object.keys(after)]);
  const diff = [...keys].filter((k) => before[k] !== after[k]);
  return { moved, files: writes.length, diff };
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const r = split({ dry: process.argv.includes("--dry-run") });
  console.log(`Locale-Split: ${r.moved} Bloecke verschoben, ${r.files} Datei(en) geschrieben.`);
  if (r.diff.length) {
    console.error(`FEHLER: Blockzahl abweichend fuer ${r.diff.join(", ")}`);
    process.exitCode = 1;
  }
}
