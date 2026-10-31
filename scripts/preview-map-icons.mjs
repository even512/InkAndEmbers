// EveN_ForeverChronicle: Vorschau der Kartensymbole (Media/MapIcons.tga, MapKill.tga, MapCurrent.tga) auf Pergament, ohne Spiel.
//
// Aufruf:  node scripts/preview-map-icons.mjs [--help]
// Ergebnis: tests/screens/map-icons.png. Obere Reihe: alle Symbole in Spielgroesse (Theme.MARKER_SIZE bzw. Map.*_SIZE), mittlere
// Reihe 3-fach, untere Reihe die Spielerposition in Blickrichtung 0, 45, 135 und 270 Grad. Die Groessen liest das Skript aus dem
// Addon (fengari-VM), damit Vorschau und Spiel nicht auseinanderlaufen. Braucht Chrome oder Edge (CHROME_PATH optional).

import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { createVm } from "../tests/helpers/wow-vm.mjs";
import { MAP_ICON_ATLAS, MAP_ICON_IDS } from "./cut-icons.mjs";
import { decodePng, encodePng, MEDIA_DIR } from "./render-media.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const OUT = path.join(ROOT, "tests", "screens", "map-icons.png");

const LABELS = {
  level: "Stufenaufstieg", milestone: "Meilenstein", death: "Tod", rare: "Seltener", elite: "Elite", boss: "Boss", photo: "Foto/Moment",
  hearth: "Ruhestein", flightpoint: "Flugmeister", gap: "Lücke", current: "Position", kill: "Kämpfe",
};

function tgaToPng(file) {
  const b = readFileSync(file);
  const w = b.readUInt16LE(12), h = b.readUInt16LE(14);
  const rgba = Buffer.alloc(w * h * 4);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const s = 18 + ((h - 1 - y) * w + x) * 4;
      const d = (y * w + x) * 4;
      rgba[d] = b[s + 2];
      rgba[d + 1] = b[s + 1];
      rgba[d + 2] = b[s];
      rgba[d + 3] = b[s + 3];
    }
  }
  return `data:image/png;base64,${encodePng(w, h, rgba).toString("base64")}`;
}

function findBrowser() {
  return [
    process.env.CHROME_PATH,
    "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
    "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe",
    "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
    "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
    "/usr/bin/google-chrome",
    "/usr/bin/chromium",
  ]
    .filter(Boolean)
    .find((p) => existsSync(p));
}

/** Anzeigegroessen je Symbol aus dem Addon: { id: px } */
function gameSizes() {
  const vm = createVm({ setup: "" });
  vm.boot();
  const r = vm.lua(`local T, M = NS.Journal.Theme, NS.Journal.Map
    local s = T.MARKER_SIZE
    return { level = M.LEVEL_MARK_SIZE, milestone = M.MILESTONE_MARK_SIZE, death = s.death, rare = s.rare, elite = s.elite, boss = s.boss,
      photo = s.photo, hearth = s.hearth, flightpoint = s.flightpoint, gap = s.gap, current = M.ARROW_SIZE, kill = M.killBase(1) }`);
  return r;
}

export function main(argv) {
  if (argv.includes("--help") || argv.includes("-h")) {
    console.log("Vorschau der Kartensymbole auf Pergament -> tests/screens/map-icons.png\nAufruf: node scripts/preview-map-icons.mjs");
    return;
  }
  if (argv.length) throw new Error(`Unbekannte Option: ${argv[0]}\nHilfe: node scripts/preview-map-icons.mjs --help`);
  const browser = findBrowser();
  if (!browser) throw new Error("Kein Chrome/Edge gefunden. Pfad ueber die Umgebungsvariable CHROME_PATH angeben.");
  const sizes = gameSizes();
  const atlas = tgaToPng(path.join(MEDIA_DIR, "MapIcons.tga"));
  const current = tgaToPng(path.join(MEDIA_DIR, "MapCurrent.tga"));
  const kill = tgaToPng(path.join(MEDIA_DIR, "MapKill.tga"));
  const paper = tgaToPng(path.join(MEDIA_DIR, "Page_reise_R.tga"));
  const A = MAP_ICON_ATLAS;
  // Symbol id der Groesse px: Atlas-Kachel per Hintergrundausschnitt (Kachel 128 px auf px verkleinert)
  const icon = (id, px, extra = "") => {
    const i = MAP_ICON_IDS.indexOf(id);
    const col = i % A.cols, row = Math.floor(i / A.cols);
    const f = px / A.cell;
    return `<span style="display:inline-block;width:${px}px;height:${px}px;${extra};background:url(${atlas}) ${-col * A.cell * f}px ${-row * A.cell * f}px / ${A.w * f}px ${A.h * f}px no-repeat"></span>`;
  };
  const row = (scale) =>
    MAP_ICON_IDS.map(
      (id) =>
        `<div class="c"><div class="i" style="height:${Math.round(34 * scale)}px">${icon(id, Math.round(sizes[id] * scale))}</div><div class="l">${LABELS[id]}<br>${sizes[id]} px</div></div>`,
    ).join("");
  const turned = [0, 45, 135, 270]
    .map(
      (deg) =>
        `<div class="c"><div class="i" style="height:90px"><span style="display:inline-block;width:${sizes.current * 3}px;height:${sizes.current * 3}px;transform:rotate(${-deg}deg);background:url(${current}) 0 0 / 100% 100% no-repeat"></span></div><div class="l">Blickrichtung ${deg}°</div></div>`,
    )
    .join("");
  const W = 1180;
  const html = `<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0}body{width:${W}px;background:#e9dcb8 url(${paper}) 0 0 / ${W}px auto;font:12px 'Segoe UI',Arial,sans-serif;color:#2b2118}
.h{padding:14px 18px 2px;font:bold 13px 'Segoe UI',Arial,sans-serif;letter-spacing:.5px}
.r{display:flex;padding:6px 14px 10px}.c{width:${Math.floor((W - 28) / 12)}px;text-align:center}
.i{display:flex;align-items:center;justify-content:center}.l{margin-top:4px;font-size:11px;line-height:13px}
.k{display:flex;justify-content:center;align-items:center;gap:10px}
</style></head><body>
<div class="h">Spielgröße (Karte)</div><div class="r">${row(1)}</div>
<div class="h">3-fach</div><div class="r" style="align-items:flex-end">${row(3)}</div>
<div class="h">Spielerposition dreht mit der Blickrichtung (Quelle zeigt nach oben), 3-fach</div><div class="r" style="justify-content:center;gap:40px">${turned}</div>
<div class="h">Kill-Marke einzeln (MapKill.tga) und mit Schlagschatten wie auf der Karte, 16 px und 3-fach</div>
<div class="r" style="justify-content:center;gap:40px;align-items:center">
 <div class="c"><img src="${kill}" width="16" height="16"></div><div class="c"><img src="${kill}" width="48" height="48"></div>
</div>
</body></html>`;
  const tmp = mkdtempSync(path.join(os.tmpdir(), "even-mapicons-"));
  try {
    const file = path.join(tmp, "p.html");
    const png = path.join(tmp, "p.png");
    writeFileSync(file, html, "utf8");
    const H = 590;
    execFileSync(
      browser,
      ["--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1", `--user-data-dir=${path.join(tmp, "profile")}`,
        `--window-size=${W},${H}`, `--screenshot=${png}`, pathToFileURL(file).href],
      { stdio: "ignore", timeout: 60000 },
    );
    const img = decodePng(readFileSync(png));
    mkdirSync(path.dirname(OUT), { recursive: true });
    writeFileSync(OUT, encodePng(img.w, img.h, img.rgba));
    console.log(`Vorschau: ${path.relative(ROOT, OUT)} (${img.w} x ${img.h})`);
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
