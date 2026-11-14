// Listet für eine Übersetzung fehlende, veraltete und abweichende Schlüssel gegen die deutschen Quelltexte (Locale.ns).
// Für Übersetzer: fehlende Texte werden mit dem englischen Text gezeigt, der bis zur Übersetzung angezeigt wird.
// Aufruf: node scripts/locale-missing.mjs <lang>          z. B. ptBR, frFR, esES, ruRU, itIT (Bericht, Exit 0)
//         node scripts/locale-missing.mjs <lang> --summary  nur die Zahlen je Bereich und der Anteil uebersetzter Schluessel
// esMX hat keine eigenen Dateien (Rueckfall esES -> enUS): der Bericht dafuer zeigt alles als fehlend.
// Exit 2 bei unbekannter Sprache oder Sprache deDE (die Quelle selbst).

import path from "node:path";
import { pathToFileURL } from "node:url";
import { createVm } from "../tests/helpers/wow-vm.mjs";

const oneLine = (v) => {
  if (typeof v === "string") return JSON.stringify(v).slice(0, 160);
  return v === undefined || v === null ? "(kein Text)" : `(${Array.isArray(v) ? "Liste" : typeof v})`;
};

/** { lang, areas: [{ area, missing: [{ key, en }], extra: [key], mismatch: [key] }], totals, keys, translated } (keys = Schluessel im Original, translated = Anteil in % ohne fehlende) */
export function localeReport(lang) {
  const vm = createVm({ collectors: true });
  const known = vm.lua(`local out = {} for k in pairs(NS.Locale.LANGS) do out[#out + 1] = k end table.sort(out) return out`) ?? [];
  if (typeof lang !== "string" || !known.includes(lang) || lang === "deDE") {
    return { lang, error: `Unbekannte Sprache "${lang}". Möglich: ${known.filter((l) => l !== "deDE").join(", ")}` };
  }
  const rows = vm.lua(`
    local L, lang = NS.Locale, ${JSON.stringify(lang)}
    local out, keys = {}, 0
    for _, area in ipairs(L.areas()) do
      do
        for _ in pairs(L.tables.deDE[area] or {}) do keys = keys + 1 end
        local r = L.missing(lang, area)
        local en = L.tables.enUS[area] or {}
        local miss = {}
        for i, k in ipairs(r.missing) do miss[i] = { key = k, en = en[k] } end
        if #miss > 0 or #r.extra > 0 or #r.mismatch > 0 then
          out[#out + 1] = { area = area, missing = miss, extra = r.extra, mismatch = r.mismatch }
        end
      end
    end
    return { areas = out, keys = keys }`) ?? {};
  const arr = (v) => (Array.isArray(v) ? v : []);
  const areas = arr(rows.areas).map((r) => ({ area: r.area, missing: arr(r.missing), extra: arr(r.extra), mismatch: arr(r.mismatch) }));
  const totals = { missing: 0, extra: 0, mismatch: 0 };
  for (const a of areas) for (const k of Object.keys(totals)) totals[k] += a[k].length;
  const keys = rows.keys ?? 0;
  const translated = keys > 0 ? Math.round((1000 * (keys - totals.missing)) / keys) / 10 : 0;
  return { lang, areas, totals, keys, translated };
}

export function main(argv) {
  const lang = argv[0];
  const summary = argv.includes("--summary");
  const rep = localeReport(lang);
  if (rep.error) {
    console.error(rep.error);
    return 2;
  }
  for (const a of rep.areas) {
    console.log(`[${a.area}] fehlend ${a.missing.length}, veraltet ${a.extra.length}, Platzhalter abweichend ${a.mismatch.length}`);
    if (summary) continue;
    for (const m of a.missing) console.log(`  fehlt     ${m.key} = ${oneLine(m.en)}`);
    for (const k of a.extra) console.log(`  veraltet  ${k} (im Original nicht mehr vorhanden, kann weg)`);
    for (const k of a.mismatch) console.log(`  abweichend ${k} (Platzhalter/Form anders als im Original, Text wird nicht verwendet)`);
  }
  const t = rep.totals;
  console.log(`${rep.lang}: ${t.missing} fehlend, ${t.extra} veraltet, ${t.mismatch} mit abweichenden Platzhaltern (Bereiche: ${rep.areas.length}); ${rep.translated} % von ${rep.keys} Schlüsseln übersetzt.`);
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  process.exitCode = main(process.argv.slice(2));
}
