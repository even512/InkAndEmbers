// InkAndEmbers: Vorschaubild der Willkommen-Karte (journal/Begleiter.lua + journal/Toast.lua), ohne Spiel.
//
// Aufruf:  node scripts/render-welcome.mjs [--lang de|en] [--volk <id>[,<id>...]] [--erst] [--help]
//
// Ablauf: Das Addon laeuft in der fengari-VM mit der Frame-Attrappe (tests/fixtures/ui-mock.lua, Textbreiten nach Zeichenklassen wie
// im Layout-Test). Die Karte "Willkommen zurueck" (bzw. mit --erst die Karte des ersten Logins) wird mit Probedaten in die
// Toast-Warteschlange gelegt; dieses Skript liest Papier, Erzaehler-Portraet und die Textzeilen samt Lage, Schrift und Farbe aus dem
// Frame und zeichnet sie im Headless-Browser nach (Texturen aus Media/*.tga, Spectral aus Media/Fonts/Spectral).
// Die Attrappe rechnet Textbreiten nur geschaetzt; Umbruch und Lage stammen aber aus dem echten Lua-Code.
//
// Ergebnis: tests/screens/welcome-<sprache>-<volk>.png (Karte auf dunklem Grund, 2-fach).

import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { ADDON_DIR, createVm, ROOT } from "../tests/helpers/wow-vm.mjs";
import { decodeTga, encodePng, NARRATOR_IDS } from "./render-media.mjs";
import { findBrowser, screenshot } from "./preview-book.mjs";

const MEDIA = path.join(ADDON_DIR, "Media");
const SCREENS = path.join(ROOT, "tests", "screens");
export const LANGS = { de: "deDE", en: "enUS" };
const PAD = 40;
const ZOOM = 2;

const HELP = `Vorschaubild der Willkommen-Karte (ohne Spiel)

Aufruf:
  node scripts/render-welcome.mjs [--lang de|en] [--volk <id>[,<id>...]] [--erst] [--help]

  --lang   Sprache (Standard: de)
  --volk   Erzaehler (${NARRATOR_IDS.join(", ")}); Standard: undead,skyborne
  --erst   Karte des allerersten Logins statt "Willkommen zurueck"
  --help   diese Hilfe

Ergebnis: tests/screens/welcome-<sprache>-<volk>.png. Browser: Chrome oder Edge (CHROME_PATH).`;

// Probedaten "Willkommen zurueck": lange Namen, damit Umbruch und Kuerzen sichtbar werden
export const SUMMARY_LUA = `{ name = "Lenu", level = 23, lastZone = "Silberwald", lastSeenAgo = 7200,
  openQuests = { count = 7, lastAccepted = "Die Verlassenen von Grabesruh und das verlorene Tagebuch", names = { "A", "B" } },
  restedPct = 85, vorhabenNearby = {} }`;
export const FIRST_LUA = `{ name = "Lenu", first = true }`;

/** VM mit Karte -> Liste der gezeichneten Teile { kind, tex|text, x, y, w, h, font, size, color } */
export function cardItems({ lang = "de", volk = "undead", first = false } = {}) {
  const locale = LANGS[lang];
  if (!locale) throw new Error(`Unbekannte Sprache: ${lang} (${Object.keys(LANGS).join(", ")})`);
  if (!NARRATOR_IDS.includes(volk)) throw new Error(`Unbekanntes Volk: ${volk} (${NARRATOR_IDS.join(", ")})`);
  const UIMOCK = readFileSync(path.join(ROOT, "tests", "fixtures", "ui-mock.lua"), "utf8");
  const vm = createVm({ setup: `GetLocale = function() return "${locale}" end\n${UIMOCK}` });
  vm.boot();
  vm.exec(`UI.measureText = true; UI.measureWidth = "class"
    local J = NS.Journal
    J.Pages.setSetting("narrator", ${JSON.stringify(volk)})
    local item = J.Begleiter.welcomeItem(${first ? FIRST_LUA : SUMMARY_LUA})
    item.key = "welcome:preview"
    J.Toast.enqueue(item)`);
  const items = vm.lua(`
    local f = NS.Journal.Toast.getFrame()
    local out = {}
    local function pt(o)
      local p = o._points[1]
      if not p then return 0, 0 end
      if p[1] == "ALL" then return 0, 0 end
      return p[4] or 0, -(p[5] or 0), p[1]
    end
    out[#out + 1] = { kind = "tex", tex = f.paper._tex, x = 0, y = 0, w = f._w, h = f._h }
    if f.icon._shown and f.icon._tex then
      local x, y = pt(f.icon)
      out[#out + 1] = { kind = "tex", tex = f.icon._tex, x = x - f.icon._w / 2, y = y - f.icon._h / 2, w = f.icon._w, h = f.icon._h }
    end
    local list = { f.cardHead, f.cardTitle }
    for _, fs in ipairs(f.cardLines) do list[#list + 1] = fs end
    for _, fs in ipairs(list) do
      if fs._shown and type(fs._text) == "string" and fs._text ~= "" then
        local x, y = pt(fs)
        out[#out + 1] = { kind = "text", text = fs._text, x = x, y = y, w = fs._w, h = fs._h, font = fs._font[1], size = fs._font[2],
          color = fs._color, justify = fs._justifyH }
      end
    end
    return out`);
  const errors = vm.errors();
  if (errors.length) throw new Error("Lua-Fehler: " + errors.join("\n"));
  return items;
}

const texUrl = (tex) => {
  const m = /Media\\(.+)$/i.exec(tex || "");
  if (!m) return null;
  const file = path.join(MEDIA, m[1].replace(/\\/g, "/") + ".tga");
  if (!existsSync(file)) return null;
  const t = decodeTga(readFileSync(file));
  return "data:image/png;base64," + encodePng(t.w, t.h, t.rgba).toString("base64");
};
const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const rgb = (c) => (Array.isArray(c) ? `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${c[3] ?? 1})` : "#2b2118");

function fontCss(file, size) {
  const f = String(file || "").toUpperCase();
  if (f.includes("SPECTRAL-SEMIBOLD")) return `font-family:'Spectral';font-weight:600;font-size:${size}px`;
  if (f.includes("SPECTRAL")) return `font-family:'Spectral';font-weight:400;font-size:${size}px`;
  if (f.includes("MORPHEUS")) return `font-family:'Palatino Linotype',serif;font-variant:small-caps;font-size:${size}px`;
  return `font-family:Georgia,serif;font-size:${size}px`;
}

export function cardHtml(items) {
  const reg = pathToFileURL(path.join(MEDIA, "Fonts", "Spectral", "Spectral-Regular.ttf")).href;
  const semi = pathToFileURL(path.join(MEDIA, "Fonts", "Spectral", "Spectral-SemiBold.ttf")).href;
  const paper = items[0];
  const body = items.map((it) => {
    if (it.kind === "tex") {
      const url = texUrl(it.tex);
      return url ? `<img src="${url}" style="position:absolute;left:${it.x}px;top:${it.y}px;width:${it.w}px;height:${it.h}px">` : "";
    }
    const lines = it.text.split("\n").map(esc).join("<br>");
    // WoW: Zeilenhoehe ~ Schriftgroesse; Box wie gesetzt (Breite textW), linksbuendig
    return `<div style="position:absolute;left:${it.x}px;top:${it.y}px;width:${it.w}px;color:${rgb(it.color)};${fontCss(it.font, it.size)};line-height:${Math.round(it.size * 1.27)}px;white-space:nowrap">${lines}</div>`;
  }).join("\n");
  return `<!doctype html><html><head><meta charset="utf-8"><style>
@font-face{font-family:'Spectral';src:url('${reg}');font-weight:400}
@font-face{font-family:'Spectral';src:url('${semi}');font-weight:600}
html,body{margin:0;padding:0;background:#25301f;overflow:hidden}
#s{position:absolute;left:${PAD}px;top:${PAD}px;width:${paper.w}px;height:${paper.h}px;transform:scale(${ZOOM});transform-origin:0 0}
body{background:radial-gradient(circle at 30% 40%,#4a5a3a,#1d241a)}
</style></head><body><div id="s">${body}</div></body></html>`;
}

export function main(argv) {
  const known = new Set(["--lang", "--volk", "--erst", "--help", "-h"]);
  for (let i = 0; i < argv.length; i++) {
    if (!known.has(argv[i])) throw new Error(`Unbekannte Option: ${argv[i]}\nHilfe: node scripts/render-welcome.mjs --help`);
    if (argv[i] === "--lang" || argv[i] === "--volk") i++;
  }
  if (argv.includes("--help") || argv.includes("-h")) {
    console.log(HELP);
    return;
  }
  const li = argv.indexOf("--lang");
  const lang = li >= 0 ? argv[li + 1] : "de";
  const vi = argv.indexOf("--volk");
  const volks = (vi >= 0 ? argv[vi + 1] || "" : "undead,skyborne").split(",").filter(Boolean);
  if (!LANGS[lang]) throw new Error(`--lang braucht ${Object.keys(LANGS).join(" oder ")}`);
  for (const v of volks) if (!NARRATOR_IDS.includes(v)) throw new Error(`Unbekanntes Volk: ${v} (${NARRATOR_IDS.join(", ")})`);
  const first = argv.includes("--erst");
  const browser = findBrowser();
  if (!browser) throw new Error("Kein Chrome/Edge gefunden. Pfad ueber die Umgebungsvariable CHROME_PATH angeben.");
  mkdirSync(SCREENS, { recursive: true });
  const tmp = mkdtempSync(path.join(os.tmpdir(), "even-welcome-"));
  try {
    for (const volk of volks) {
      const items = cardItems({ lang, volk, first });
      const paper = items[0];
      const file = path.join(SCREENS, `welcome-${lang}-${volk}${first ? "-erst" : ""}.png`);
      screenshot(browser, tmp, cardHtml(items), paper.w * ZOOM + 2 * PAD, paper.h * ZOOM + 2 * PAD, file);
      console.log(`  ${path.relative(ROOT, file)}`);
    }
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    main(process.argv.slice(2));
  } catch (err) {
    console.error(`FEHLER: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  }
}
