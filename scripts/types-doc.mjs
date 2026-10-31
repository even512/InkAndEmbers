// Erzeugt die Kuerzel-Tabelle "Log-Format (Vertrag)" der README aus ns.Types (Store.lua).
// Aufruf: node scripts/types-doc.mjs          -> README aktualisieren
//         node scripts/types-doc.mjs --check  -> nur pruefen (Exit 1, wenn die README nicht dem Code entspricht)

import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { createVm, ROOT } from "../tests/helpers/wow-vm.mjs";

export const README = path.join(ROOT, "README.md");
export const BEGIN = "<!-- types:begin (erzeugt aus ns.Types, npm run types-doc) -->";
export const END = "<!-- types:end -->";

const cell = (s) => String(s).replace(/\|/g, "\\|").replace(/\r?\n/g, " ");

/** Liste der Typen aus der Lua-VM, sortiert nach order */
export function readTypes() {
  const vm = createVm();
  const types = vm.lua(`
    local out = {}
    for code, t in pairs(NS.Types) do
      out[#out + 1] = { code = code, order = t.order, name = t.name, desc = t.desc, fields = t.fields }
    end
    return out
  `);
  return types.sort((a, b) => a.order - b.order || (a.code < b.code ? -1 : 1));
}

export function renderTypesTable(types = readTypes()) {
  const rows = ["| Kürzel | Bedeutung | Felder (nach `<dt>~<kürzel>~`, in dieser Reihenfolge) |", "|---|---|---|"];
  for (const t of types) {
    const fields = (t.fields ?? []).map((f, i) => `${i + 1}. \`${cell(f[0])}\`: ${cell(f[1] ?? "")}`).join("<br>");
    rows.push(`| \`${cell(t.code)}\` | **${cell(t.name)}**: ${cell(t.desc)} | ${fields || "(keine)"} |`);
  }
  return rows.join("\n");
}

function splice(readme, table) {
  const a = readme.indexOf(BEGIN);
  const b = readme.indexOf(END);
  if (a < 0 || b < a) throw new Error("README: Marker fuer die Kuerzel-Tabelle fehlen");
  return readme.slice(0, a + BEGIN.length) + "\n" + table + "\n" + readme.slice(b);
}

/** true, wenn die README-Tabelle dem Code entspricht */
export function readmeInSync() {
  const readme = readFileSync(README, "utf8").replace(/\r\n/g, "\n");
  return splice(readme, renderTypesTable()) === readme;
}

const isMain = process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href;
if (isMain) {
  const readme = readFileSync(README, "utf8").replace(/\r\n/g, "\n");
  const next = splice(readme, renderTypesTable());
  if (process.argv.includes("--check")) {
    if (next !== readme) {
      console.error("README: Kuerzel-Tabelle veraltet. Bitte 'npm run types-doc' ausfuehren.");
      process.exit(1);
    }
    console.log("README: Kuerzel-Tabelle aktuell.");
  } else {
    writeFileSync(README, next, "utf8");
    console.log(`README: Kuerzel-Tabelle geschrieben (${path.relative(ROOT, README)}).`);
  }
}
