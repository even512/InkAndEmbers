// InkAndEmbers: Bilder der Willkommens-Einfuehrung (journal/Tutorial.lua) aus echten Ausschnitten des Addons.
//
// Aufruf:  node scripts/render-tutorial.mjs [--lang deDE|enUS] [--vorschau] [--roh-behalten] [--lua] [--help]
//
// Aufbau der Einfuehrung (nach der Vorlage des Autors): eine Willkommensseite und je Feature
// eine Seite (Sammlung, Reise-Karte, Stufenfluss, Medaillen, Weggefaehrten, Am Feuer, Kampf, Quests, Offene Quests, Schaetze,
// Notizen, To Do). Jede Seite zeigt links ein oder zwei Bilder ("Kacheln"): PAGE_TILES.
//
// Ablauf: Das Addon laeuft in der fengari-VM mit der Frame-Attrappe (wie scripts/preview-book.mjs) je Sprache; das ganze Buch
// wird in etlichen Ansichten im Headless-Browser gezeichnet (1,5-fach, damit die Ausschnitte scharf bleiben). Daraus schneidet dieses
// Skript je Kachel einen Ausschnitt (S: 512 x 256, L: 512 x 384), legt dezente Tinte (Kreise, Pfeile, Handschrift) darueber und packt
// alle Kacheln in Atlanten zu 1024 x 1024 (Regalpackung, layout()): Media/Tutorial_<sprache>_<n>.tga. Zwei Kacheln sind zusammengesetzt
// statt geschnitten: der Minimap-Knopf (Media/MinimapIcon.tga an einer gezeichneten Minimap, dazu eine Chatzeile "/chronik") und die
// Lagerfeuer-Zettel (Media/FireNote<i>.tga ueber Flammenschein). In der Reise-Karte steht das eigene Kartenbild des Autors
// (docs/tutorial-entwurf/bilder/02c-reise-karte-tim.png) in der Kartenflaeche. Keine Gemini-Bilder.
//
// --lua       die Kachel-Lage als Lua-Tabelle ausgeben (Tutorial.PAGES in journal/Tutorial.lua; ein Test gleicht beides ab)
// --vorschau  statt der Bilder die Einfuehrung selbst (alle Seiten, aus der VM gezeichnet) -> tests/screens/tutorial-<sprache>-<n>.png
//             und ein Uebersichtsbild tests/screens/tutorial-<sprache>.png.
// --roh-behalten  vorhandene Rohbilder tests/screens/tutorial-roh-<sprache>-<ansicht>.png weiterverwenden (nur die Kacheln neu setzen)
// Neue Texturdateien erkennt der WoW-Client erst nach einem kompletten Spielneustart.

import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { ROOT, ADDON_DIR } from "../tests/helpers/wow-vm.mjs";
import { decodePng, decodeTga, encodePng, encodeTga } from "./render-media.mjs";
import { bookHtml, bootVm, BOOK_PAD, findBrowser, OPEN_QUESTS_LUA, screenshot, SUBVIEWS } from "./preview-book.mjs";

export const LANGS = ["deDE", "enUS"];
export const SIZES = { S: { w: 512, h: 256 }, L: { w: 512, h: 384 } };
export const ATLAS = { size: 1024 };

// Seiten in der Reihenfolge der Einfuehrung; je Seite die Kacheln (Name, Groesse). Reihenfolge der zwoelf Features.
export const PAGE_TILES = [
  ["welcome", [["open", "S"]]],
  ["collection", [["profile", "S"], ["moments", "S"]]],
  ["travelmap", [["total", "S"], ["map", "S"]]],
  ["levelflow", [["flow", "L"]]],
  ["medals", [["seals", "L"]]],
  ["companions", [["list", "S"], ["detail", "S"]]],
  ["fire", [["list", "S"], ["notes", "S"]]],
  ["combat", [["hunting", "S"], ["deaths", "S"]]],
  ["quests", [["history", "S"], ["life", "S"]]],
  ["openquests", [["list", "L"]]],
  ["treasures", [["finds", "S"], ["gold", "S"]]],
  ["notes", [["read", "S"], ["edit", "S"]]],
  ["todo", [["list", "S"], ["goals", "S"]]],
  ["farewell", []], // Abschlussseite: links das Erzaehler-Portraet der Willkommen-Karte (Media/Narrator_<volk>.tga), keine Kachel
];
const PORTRAIT_PAGES = new Set(["farewell"]);
export const PAGES = PAGE_TILES.map(([id]) => id);
export const TILES = PAGE_TILES.flatMap(([page, tiles]) => tiles.map(([name, size]) => ({ id: `${page}.${name}`, page, name, size })));

/**
 * Regalpackung in Atlanten zu ATLAS.size: erst alle grossen (L), dann alle kleinen (S) Kacheln, je in Seitenreihenfolge; eine Kachel kommt in
 * das erste Regal (Zeile) mit genug Restbreite und Hoehe, sonst in ein neues Regal des ersten Atlas mit Platz, sonst in einen neuen Atlas.
 * Ergebnis: { atlases: Anzahl, rects: { <kachel-id>: { atlas (ab 1), x, y, w, h } } }
 */
export function layout() {
  const order = [...TILES.filter((t) => t.size === "L"), ...TILES.filter((t) => t.size === "S")];
  const atlases = [];
  const rects = {};
  for (const t of order) {
    const { w, h } = SIZES[t.size];
    let spot = null;
    for (const a of atlases) {
      const shelf = a.shelves.find((s) => s.x + w <= ATLAS.size && s.h >= h);
      if (shelf) {
        spot = { a, x: shelf.x, y: shelf.y };
        shelf.x += w;
        break;
      }
    }
    if (!spot) {
      let a = atlases.find((at) => at.y + h <= ATLAS.size);
      if (!a) {
        a = { n: atlases.length + 1, y: 0, shelves: [] };
        atlases.push(a);
      }
      const shelf = { y: a.y, h, x: w };
      a.shelves.push(shelf);
      a.y += h;
      spot = { a, x: 0, y: shelf.y };
    }
    rects[t.id] = { atlas: spot.a.n, x: spot.x, y: spot.y, w, h };
  }
  return { atlases: atlases.length, rects };
}

/** Kachel-Lage als Lua-Quelltext fuer Tutorial.PAGES (journal/Tutorial.lua) */
export function luaPages() {
  const { rects } = layout();
  const lines = ["Tutorial.PAGES = {"];
  for (const [page, tiles] of PAGE_TILES) {
    const parts = tiles.map(([name]) => {
      const r = rects[`${page}.${name}`];
      return `{ a = ${r.atlas}, x = ${r.x}, y = ${r.y}, w = ${r.w}, h = ${r.h} }`;
    });
    lines.push(`  { id = "${page}", ${PORTRAIT_PAGES.has(page) ? "portrait = true, " : ""}tiles = { ${parts.join(", ")} } },`);
  }
  lines.push("}");
  return lines.join("\n");
}

const MEDIA = path.join(ADDON_DIR, "Media");
const SCREENS = path.join(ROOT, "tests", "screens");
const TIM_MAP = path.join(ROOT, "docs", "tutorial-entwurf", "bilder", "02c-reise-karte-tim.png");
export const atlasFile = (lang, n) => path.join(MEDIA, `Tutorial_${lang}_${n}.tga`);
const RS = 1.5; // Rohbilder in 1,5-facher Aufloesung

// Beschriftungen in den Bildern (Handschrift)
const NOTE = {
  deDE: { quick: "Knopf an der Minimap", chat: "oder im Chat", say: "Sagen", fire: "Klick = sagen", fireR: "Rechtsklick = weg", goals: "Deine Ziele", lines: ["Was wollen wir hier am Feuer erzählen?", "Wer war schon einmal in der Tiefenbahn?", "Auf die nächste Etappe!"] },
  enUS: { quick: "Minimap button", chat: "or in chat", say: "Say", fire: "Click = say", fireR: "Right-click = discard", goals: "Your goals", lines: ["What tale shall we tell by the fire?", "Who has ridden the Deeprun Tram?", "To the next stretch of the road!"] },
};

const HELP = `Bilder der Willkommens-Einfuehrung (Tutorial) aus echten Ausschnitten des Addons

Aufruf:
  node scripts/render-tutorial.mjs [--lang deDE|enUS] [--vorschau] [--roh-behalten] [--lua] [--help]

  (ohne Flag) beide Sprachen: Media/Tutorial_<sprache>_<n>.tga (Atlanten 1024 x 1024, Kacheln 512 x 256 und 512 x 384)
  --lang          nur diese Sprache
  --vorschau      die Einfuehrung selbst aus der VM zeichnen: tests/screens/tutorial-<sprache>-<n>.png + Uebersicht
  --roh-behalten  vorhandene Rohbilder (tests/screens/tutorial-roh-*) weiterverwenden
  --lua           die Kachel-Lage als Lua-Tabelle ausgeben (Tutorial.PAGES)
  --help          diese Hilfe

Browser: Chrome oder Edge, Pfad optional ueber die Umgebungsvariable CHROME_PATH.`;

const pngUrl = (file) => "data:image/png;base64," + readFileSync(file).toString("base64");
const tgaUrl = (name) => {
  const t = decodeTga(readFileSync(path.join(MEDIA, `${name}.tga`)));
  return "data:image/png;base64," + encodePng(t.w, t.h, t.rgba).toString("base64");
};
const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

// ---------------------------------------------------------------------------------------------------------------
// Rohbilder: das ganze Buch in einer Ansicht (wie preview-book --buch), 1,5-fach

function bookGeometry(vm) {
  const [W, H, TOUT, SOUT, RIM] = vm.lua("local F = NS.Journal.Frame return { F.W, F.H, F.TABS_OUT, F.SUBTABS_OUT, F.RIM }");
  return { W, H, TOUT, SOUT, RIM, w: W + TOUT + 2 * BOOK_PAD, h: H + SOUT + 2 * BOOK_PAD };
}

const SUB = (tab, name) => SUBVIEWS.find((s) => s[0] === tab && s[1] === name);
// Ansichten: Name -> [Reiter, Lua zum Oeffnen, Lua zum Schliessen, mit eigener Karte]
const VIEWS = {
  chronik: ["chronik", "", ""],
  momente: ["momente", "", ""],
  gesamt: ["reise", SUB("reise", "gesamt")[2], SUB("reise", "gesamt")[3]],
  reise: ["reise", "", "", true],
  weggef: ["chronik", SUB("chronik", "weggefaehrten")[2], SUB("chronik", "weggefaehrten")[3]],
  feuer: ["chronik", SUB("chronik", "feuer")[2], SUB("chronik", "feuer")[3]],
  kampf: ["kampf", "", ""],
  tode: ["kampf", SUB("kampf", "tode")[2], SUB("kampf", "tode")[3]],
  quests: ["quests", "", ""],
  offen: ["plaene", OPEN_QUESTS_LUA(1420), 'NS.Journal.PlaenePage:ShowSub("vorhaben")'], // I12: Offene Quests unter Plaene
  funde: ["schaetze", SUB("schaetze", "funde")[2], SUB("schaetze", "funde")[3]],
  quellen: ["schaetze", SUB("schaetze", "quellen")[2], SUB("schaetze", "quellen")[3]],
  notizen: ["notizen", "", ""],
  notizenedit: ["notizen", SUB("notizen", "edit")[2], SUB("notizen", "edit")[3]],
  todo: ["plaene", SUB("plaene", "todo")[2], SUB("plaene", "todo")[3]], // I12: To Do unter Plaene
};

const pngSize = (file) => {
  const b = readFileSync(file);
  return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) };
};
const rohFile = (lang, name) => path.join(SCREENS, `tutorial-roh-${lang}-${name}.png`);

function rawShots(lang, { keep }, browser, tmp) {
  const shots = {};
  if (keep && Object.keys(VIEWS).every((n) => existsSync(rohFile(lang, n)))) {
    for (const n of Object.keys(VIEWS)) shots[n] = { file: rohFile(lang, n), ...pngSize(rohFile(lang, n)) };
    return shots;
  }
  const vm = bootVm({ lang: lang === "enUS" ? "en" : "de" });
  const g = bookGeometry(vm);
  const timMap = pngUrl(TIM_MAP);
  for (const [name, [tab, open, close, withMap]] of Object.entries(VIEWS)) {
    vm.lua(`return NS.Journal.Frame.showPage(${JSON.stringify(tab)})`);
    if (open) vm.exec(open);
    let items = vm.lua("return KO_PREVIEW(NS.Journal.Frame.state.frame, 0, 0, 1e12)");
    items = Array.isArray(items) ? items : [];
    let extra = "";
    if (withMap) {
      // Kartenflaeche der Reise: die Kartenkunst kommt im Spiel aus dem Client; hier steht das eigene Kartenbild des Autors (Hochformat) darin
      const [mx, my, mw, mh] = vm.lua("local M = NS.Journal.Frame.MAP return { M.x, M.y, M.w, M.h }").map((v, i) => v + (i < 2 ? g.RIM : 0));
      const inMap = (i) => i.x >= mx && i.y >= my && i.x + i.w <= mx + mw && i.y + i.h <= my + mh;
      items = items.filter((i) => !inMap(i));
      extra = `<div style="position:absolute;left:${mx + BOOK_PAD}px;top:${my + BOOK_PAD}px;width:${mw}px;height:${mh}px;overflow:hidden;box-shadow:0 0 0 1px rgba(70,45,20,0.55),0 0 0 3px rgba(240,226,190,0.8)">` +
        `<div style="position:absolute;left:-30px;top:-30px;right:-30px;bottom:-30px;background:url('${timMap}') center/cover;filter:blur(14px) saturate(0.9)"></div>` +
        `<div style="position:absolute;left:0;top:0;width:100%;height:100%;background:url('${timMap}') center/contain no-repeat"></div></div>`;
    }
    const html = bookHtml(items, g.w, g.h)
      .replace("</style>", `body{height:${Math.round(g.h * RS)}px}</style>`)
      .replace("#s{position:relative;", `#s{transform:scale(${RS});transform-origin:0 0;position:relative;`)
      .replace("</div></body>", `${extra}</div></body>`);
    const file = rohFile(lang, name);
    screenshot(browser, tmp, html, Math.round(g.w * RS), Math.round(g.h * RS), file);
    shots[name] = { file, ...pngSize(file) };
    if (close) vm.exec(close);
  }
  const errs = vm.errors();
  if (errs.length) console.log(`  Lua-Fehler in der Attrappe (${lang}):\n    ${errs.join("\n    ")}`);
  return shots;
}

// ---------------------------------------------------------------------------------------------------------------
// Tinte: Kreis, Pfeil, Notiz (SVG/HTML ueber dem Ausschnitt, Zellpixel 512 x 256 bzw. 384)

const INK = "rgba(155,44,31,0.9)";
const caveatCss = () => `@font-face{font-family:'Caveat';src:url('${pathToFileURL(path.join(MEDIA, "Fonts", "Caveat-Bold.ttf")).href}');font-weight:700}`;

/** handgezogener Kreis (zwei leicht versetzte Ellipsenbahnen) um cx, cy mit Radien rx, ry */
function circle(cx, cy, rx, ry, rot = -4) {
  const pts = [];
  for (let i = 0; i <= 64; i++) {
    const a = (i / 64) * Math.PI * 2.12 - 0.3;
    const k = 1 + 0.04 * Math.sin(a * 3) + (i > 58 ? 0.06 : 0);
    pts.push(`${(cx + Math.cos(a) * rx * k).toFixed(1)},${(cy + Math.sin(a) * ry * k).toFixed(1)}`);
  }
  return `<polyline points="${pts.join(" ")}" fill="none" stroke="${INK}" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" transform="rotate(${rot} ${cx} ${cy})"/>`;
}

/** geschwungener Pfeil von (x1, y1) nach (x2, y2) mit Bogen bend */
function arrow(x1, y1, x2, y2, bend = 30) {
  const mx = (x1 + x2) / 2, my = (y1 + y2) / 2;
  const dx = x2 - x1, dy = y2 - y1, len = Math.hypot(dx, dy) || 1;
  const cx = mx - (dy / len) * bend, cy = my + (dx / len) * bend;
  const ang = Math.atan2(y2 - cy, x2 - cx);
  const h = 11;
  const a1 = ang + Math.PI - 0.45, a2 = ang + Math.PI + 0.45;
  return `<path d="M${x1},${y1} Q${cx},${cy} ${x2},${y2}" fill="none" stroke="${INK}" stroke-width="2.6" stroke-linecap="round"/>` +
    `<path d="M${(x2 + Math.cos(a1) * h).toFixed(1)},${(y2 + Math.sin(a1) * h).toFixed(1)} L${x2},${y2} L${(x2 + Math.cos(a2) * h).toFixed(1)},${(y2 + Math.sin(a2) * h).toFixed(1)}" fill="none" stroke="${INK}" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>`;
}

/** Handschrift-Notiz (Caveat) bei x, y (oben links), leicht gedreht */
const note = (x, y, text, { size = 26, rot = -3, color = INK, align = "left" } = {}) =>
  `<div style="position:absolute;left:${x}px;top:${y}px;font-family:'Caveat';font-weight:700;font-size:${size}px;color:${color};transform:rotate(${rot}deg);transform-origin:left top;white-space:nowrap;text-align:${align};text-shadow:0 0 3px rgba(248,241,224,0.9),0 0 6px rgba(248,241,224,0.7)">${esc(text)}</div>`;

/** Zelle: Ausschnitt (x, y, w im Rohbild; Hoehe aus der Kachelgroesse) eines Rohbilds + Tinte */
function cropCell(shot, crop, size, svg = "", html = "") {
  const { w: cw, h: ch } = SIZES[size];
  const k = cw / crop.w;
  const src = pngUrl(shot.file);
  return `<!doctype html><html><head><meta charset="utf-8"><style>${caveatCss()}html,body{margin:0;padding:0;overflow:hidden;background:#2a231d}
#c{position:relative;width:${cw}px;height:${ch}px;overflow:hidden;background:url('${src}') ${-crop.x * k}px ${-crop.y * k}px / ${shot.w * k}px ${shot.h * k}px no-repeat}
svg{position:absolute;left:0;top:0}</style></head><body><div id="c"><svg width="${cw}" height="${ch}" viewBox="0 0 ${cw} ${ch}">${svg}</svg>${html}</div></body></html>`;
}

// Ausschnitte (x, y, Breite im Rohbild, 1884 x 1200; Hoehe = Breite / 2 bei S, Breite x 0,75 bei L)
const SPREAD = { x: 110, y: 120, w: 1600 }; // ganze Doppelseite (Uebersicht)
const LEFT = 205, RIGHT = 935; // linke / rechte Seite (Textspalte)

function cellHtml(tile, lang, shots) {
  const N = NOTE[lang];
  const crop = (view, x, y, w) => cropCell(shots[view], { x, y, w }, tile.size);
  switch (tile.id) {
    case "welcome.open": {
      // gezeichnete Minimap mit dem Knopf der Chronik + Chatzeile "/chronik"
      const icon = tgaUrl("MinimapIcon");
      return `<!doctype html><html><head><meta charset="utf-8"><style>${caveatCss()}html,body{margin:0;padding:0;overflow:hidden}
#c{position:relative;width:512px;height:256px;overflow:hidden;background:radial-gradient(ellipse at 30% 40%,#3b4a35 0%,#26301f 55%,#1b2017 100%)}
.map{position:absolute;left:52px;top:34px;width:170px;height:170px;border-radius:50%;background:radial-gradient(circle at 45% 40%,#6f8f5a 0%,#55724a 45%,#3d5636 100%);box-shadow:0 0 0 6px #2b2118,0 0 0 9px #8a6a3a,0 6px 14px rgba(0,0,0,0.6)}
.road{position:absolute;left:60px;top:110px;width:160px;height:6px;background:#a58a5a;transform:rotate(-18deg);border-radius:3px;opacity:0.7}
.dot{position:absolute;left:128px;top:112px;width:14px;height:14px;background:#f1d97a;clip-path:polygon(50% 0,100% 100%,50% 75%,0 100%)}
.icon{position:absolute;left:180px;top:150px;width:58px;height:58px;background:url('${icon}') center/contain no-repeat;filter:drop-shadow(0 2px 3px rgba(0,0,0,0.7))}
.chat{position:absolute;left:286px;top:150px;width:200px;height:34px;border-radius:4px;background:rgba(0,0,0,0.55);border:1px solid rgba(255,255,255,0.18);font:600 17px Arial,sans-serif;color:#fff;line-height:34px;padding-left:10px;box-sizing:border-box}
.chat b{color:#ffd100;font-weight:600}
svg{position:absolute;left:0;top:0}</style></head><body><div id="c">
<div class="map"></div><div class="road"></div><div class="dot"></div><div class="icon"></div>
<div class="chat"><b>${esc(N.say)}:</b> /chronik</div>
<svg width="512" height="256" viewBox="0 0 512 256">${circle(209, 179, 40, 38)}${arrow(300, 60, 236, 140, -26)}</svg>
${note(290, 26, N.quick, { size: 26, rot: -3, color: "#f2c46b" })}${note(300, 196, N.chat, { size: 24, rot: -2, color: "#f2c46b" })}
</div></body></html>`;
    }
    case "collection.profile":
      return cropCell(shots.chronik, SPREAD, "S");
    case "collection.moments":
      return cropCell(shots.momente, SPREAD, "S");
    case "travelmap.total":
      return crop("gesamt", LEFT, 175, 640);
    case "travelmap.map":
      return crop("reise", 950, 450, 612);
    case "levelflow.flow":
      return crop("chronik", RIGHT + 5, 160, 620);
    case "medals.seals":
      return crop("chronik", LEFT + 5, 588, 600);
    case "companions.list":
      return crop("weggef", LEFT, 165, 640);
    case "companions.detail":
      return crop("weggef", 925, 185, 680);
    case "fire.list":
      return crop("feuer", LEFT, 165, 640);
    case "fire.notes": {
      const n1 = tgaUrl("FireNote1"), n2 = tgaUrl("FireNote3"), n3 = tgaUrl("FireNote5");
      const L = N.lines;
      const paper = (x, y, w, url, rot, text) => `<div style="position:absolute;left:${x}px;top:${y}px;width:${w}px;height:${w / 2}px;transform:rotate(${rot}deg);background:url('${url}') center/100% 100% no-repeat;filter:drop-shadow(0 4px 6px rgba(0,0,0,0.55))">
<div style="position:absolute;left:14%;top:26%;width:72%;height:50%;display:flex;align-items:center;justify-content:center;text-align:center;font:600 13px Georgia,serif;color:#2b2118;line-height:1.15">${esc(text)}</div></div>`;
      return `<!doctype html><html><head><meta charset="utf-8"><style>${caveatCss()}html,body{margin:0;padding:0;overflow:hidden}
#c{position:relative;width:512px;height:256px;overflow:hidden;background:radial-gradient(ellipse at 50% 112%,#ffb347 0%,#d9631e 18%,#6b2a12 40%,#22140d 70%,#120b08 100%)}
svg{position:absolute;left:0;top:0}</style></head><body><div id="c">
${paper(12, 22, 180, n1, -5, L[0])}${paper(172, 8, 176, n2, 3, L[1])}${paper(330, 30, 172, n3, -2, L[2])}
${note(40, 196, N.fire, { size: 24, rot: -2, color: "#f2c46b" })}${note(300, 200, N.fireR, { size: 24, rot: -2, color: "#f2c46b" })}
</div></body></html>`;
    }
    case "combat.hunting":
      return crop("kampf", 925, 170, 680);
    case "combat.deaths":
      return crop("tode", 925, 630, 700);
    case "quests.history":
      return crop("quests", LEFT, 185, 640);
    case "quests.life":
      return crop("quests", 930, 190, 640);
    case "openquests.list":
      return crop("offen", LEFT + 5, 175, 620);
    case "treasures.finds":
      return crop("funde", 930, 215, 600);
    case "treasures.gold":
      return crop("quellen", 925, 170, 680);
    case "notes.read":
      return crop("notizen", 925, 185, 680);
    case "notes.edit":
      return crop("notizenedit", 925, 185, 680);
    case "todo.list":
      return crop("todo", LEFT, 175, 640);
    case "todo.goals": {
      return cropCell(shots.todo, { x: 930, y: 175, w: 640 }, "S", arrow(400, 62, 340, 112, -16), note(300, 6, N.goals, { size: 34, rot: -3 }));
    }
    default:
      throw new Error(`Unbekannte Kachel: ${tile.id}`);
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Atlas

function renderAtlas(browser, tmp, lang, keep) {
  const shots = rawShots(lang, { keep }, browser, tmp);
  const { atlases, rects } = layout();
  const pixels = Array.from({ length: atlases }, () => new Uint8Array(ATLAS.size * ATLAS.size * 4));
  for (const tile of TILES) {
    const r = rects[tile.id];
    const file = path.join(tmp, `cell-${lang}-${tile.id}.png`);
    screenshot(browser, tmp, cellHtml(tile, lang, shots), r.w, r.h, file);
    const img = decodePng(readFileSync(file));
    if (img.w !== r.w || img.h !== r.h) throw new Error(`${tile.id}: Screenshot ${img.w}x${img.h}`);
    for (let y = 0; y < r.h; y++) {
      const src = y * r.w * 4;
      const dst = ((r.y + y) * ATLAS.size + r.x) * 4;
      pixels[r.atlas - 1].set(img.rgba.subarray(src, src + r.w * 4), dst);
    }
  }
  mkdirSync(SCREENS, { recursive: true });
  pixels.forEach((atlas, i) => {
    for (let p = 3; p < atlas.length; p += 4) atlas[p] = 255; // deckend
    writeFileSync(atlasFile(lang, i + 1), encodeTga(ATLAS.size, ATLAS.size, atlas));
    const check = path.join(SCREENS, `tutorial-bilder-${lang}-${i + 1}.png`);
    writeFileSync(check, encodePng(ATLAS.size, ATLAS.size, atlas));
    console.log(`  ${path.relative(ROOT, atlasFile(lang, i + 1))}  ${ATLAS.size}x${ATLAS.size}  (Pruefbild ${path.relative(ROOT, check)})`);
  });
}

// ---------------------------------------------------------------------------------------------------------------
// Vorschau der Einfuehrung selbst

function renderPreview(browser, tmp, lang) {
  const vm = bootVm({ lang: lang === "enUS" ? "en" : "de", profil: "frisch" });
  vm.exec("NS.Journal.Tutorial.open(1)");
  const [W, H, n] = vm.lua("local T = NS.Journal.Tutorial return { T.W, T.H, #T.PAGES }");
  const w = W + 2 * BOOK_PAD, h = H + 2 * BOOK_PAD;
  const files = [];
  for (let i = 1; i <= n; i++) {
    vm.exec(`NS.Journal.Tutorial.go(${i})`);
    let items = vm.lua("return KO_PREVIEW(NS.Journal.Tutorial.state.frame, 0, 0, 1e12)");
    items = Array.isArray(items) ? items : [];
    const file = path.join(SCREENS, `tutorial-${lang}-${i}.png`);
    screenshot(browser, tmp, bookHtml(items, w, h), w, h, file);
    files.push(file);
    console.log(`  ${path.relative(ROOT, file)}  (${items.length} Elemente)`);
  }
  const errs = vm.errors();
  if (errs.length) console.log(`  Lua-Fehler in der Attrappe (${lang}):\n    ${errs.join("\n    ")}`);
  const s = 0.5, cw = Math.round(w * s), ch = Math.round(h * s), gap = 10;
  const cells = files.map((f, i) => `<img src="${pathToFileURL(f).href}" style="position:absolute;left:${gap + (i % 2) * (cw + gap)}px;top:${gap + Math.floor(i / 2) * (ch + gap)}px;width:${cw}px;height:${ch}px">`).join("");
  const rows = Math.ceil(files.length / 2);
  const OW = 2 * cw + 3 * gap, OH = rows * ch + (rows + 1) * gap;
  const all = path.join(SCREENS, `tutorial-${lang}.png`);
  screenshot(browser, tmp, `<!doctype html><html><body style="margin:0;background:#2a231d;overflow:hidden"><div style="position:relative;width:${OW}px;height:${OH}px">${cells}</div></body></html>`, OW, OH, all);
  console.log(`  ${path.relative(ROOT, all)}  (Uebersicht)`);
}

export function main(argv) {
  const known = new Set(["--lang", "--vorschau", "--roh-behalten", "--lua", "--help", "-h"]);
  for (let i = 0; i < argv.length; i++) {
    if (!known.has(argv[i])) throw new Error(`Unbekannte Option: ${argv[i]}\nHilfe: node scripts/render-tutorial.mjs --help`);
    if (argv[i] === "--lang") i++;
  }
  if (argv.includes("--help") || argv.includes("-h")) return console.log(HELP);
  if (argv.includes("--lua")) return console.log(luaPages());
  const li = argv.indexOf("--lang");
  const langs = li >= 0 ? [String(argv[li + 1] || "")] : LANGS;
  for (const l of langs) if (!LANGS.includes(l)) throw new Error(`--lang: ${LANGS.join(" oder ")}`);
  const browser = findBrowser();
  if (!browser) throw new Error("Kein Chrome/Edge gefunden. Pfad ueber die Umgebungsvariable CHROME_PATH angeben.");
  mkdirSync(SCREENS, { recursive: true });
  const tmp = mkdtempSync(path.join(os.tmpdir(), "even-tutorial-"));
  try {
    for (const lang of langs) {
      if (argv.includes("--vorschau")) renderPreview(browser, tmp, lang);
      else renderAtlas(browser, tmp, lang, argv.includes("--roh-behalten"));
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
