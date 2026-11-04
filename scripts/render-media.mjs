// Rendert die Texturen des Reisejournals (Buch, Reiter, Kartenzeichen, Koernung ...) aus dem Claude-Design im
// Headless-Browser und legt sie als TGA (32 bit, unkomprimiert, Kantenlaengen als Zweierpotenz, hoechstens 1024 px)
// unter addon/InkAndEmbers/Media/ ab. Die TGA-Dateien liegen im Repo; dieses Skript braucht man nur, wenn
// sich das Aussehen aendern soll.
//
// Aufruf:  node scripts/render-media.mjs [--only <Name>] [--check] [--keepout] [--fire-areas] [--help]
//   (ohne Flag)  alle Texturen neu rendern (braucht Chrome oder Edge; Pfad optional ueber CHROME_PATH)
//   --only Name  nur diese Textur (z. B. --only Markers)
//   --check      nichts rendern, nur pruefen: jede Textur vorhanden, TGA-Kopf und Groesse stimmen
//   --keepout    Sperrflaechen der gemalten Verzierungen je Reiter ermitteln -> journal/DecorKeepout.lua + tests/screens/b2-keepout-*.png
//   --fire-areas Textbereiche der Zettel am Feuer aus Media/FireNote<i>.tga -> journal/FireNoteAreas.lua + tests/screens/fire-notes.png
// Exit-Codes: 0 = ok, 1 = Fehler (kein Browser, Renderfehler, Pruefung fehlgeschlagen, unbekannte Option)
//
// Neue oder geaenderte Texturdateien erkennt der WoW-Client erst nach einem kompletten Spielneustart.

import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { deflateSync, inflateSync } from "node:zlib";
import { cutAtlas, cutSingle, MAP_ICON_ATLAS, MAP_ICONS_FILE, MAP_ICONS_SRC } from "./cut-icons.mjs";
import { cutEmblems, EMBLEM_ATLAS, EMBLEMS_FILE, EMBLEMS_SRC } from "./cut-emblems.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const MEDIA_DIR = path.join(ROOT, "addon", "InkAndEmbers", "Media");

// ---------------------------------------------------------------------------------------------------------------
// Gemeinsame Bausteine aus dem Design (Main.dc.html / Stilblatt.dc.html)

const FONT_LABEL = "'Segoe UI', Arial, sans-serif";
const BASE_CSS = "html,body{margin:0;padding:0;background:transparent;overflow:hidden}*{box-sizing:border-box}";
const FILTERS = `<svg width="0" height="0" style="position:absolute"><defs>
<filter id="paperNoise" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency="0.65" numOctaves="3" seed="31" stitchTiles="stitch"/><feColorMatrix values="0 0 0 0 0.45  0 0 0 0 0.32  0 0 0 0 0.16  0 0 0 0.5 0"/></filter>
<filter id="blotch" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency="0.010" numOctaves="3" seed="47"/><feColorMatrix values="0 0 0 0 0.5  0 0 0 0 0.33  0 0 0 0 0.12  0 0 -1.6 0 0.95"/></filter>
<filter id="softer"><feGaussianBlur stdDeviation="3"/></filter>
<filter id="leather" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency="1.1" numOctaves="2" seed="6"/><feColorMatrix values="0 0 0 0 0.1  0 0 0 0 0.05  0 0 0 0 0.02  0 0 0 0.55 0"/></filter>
</defs></svg>`;

const page = (w, h, body, css = "") =>
  `<!doctype html><html><head><meta charset="utf-8"><style>${BASE_CSS}${css}</style></head><body style="width:${w}px;height:${h}px">${FILTERS}${body}</body></html>`;

const MIME = { webp: "image/webp", jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png" };
// file ohne Ordner liegt in art/journal/, mit Ordner (z. B. "toast/toastBG.jpg") relativ zu art/
const artUrl = (file) =>
  `data:${MIME[path.extname(file).slice(1).toLowerCase()]};base64,${readFileSync(path.join(ROOT, "art", file.includes("/") ? "" : "journal", file)).toString("base64")}`;

// Bilder aus Gemini (art/journal/) zuschneiden und auf die Texturgroesse strecken. crop in Pixeln des Quellbilds.
const ART = (file, crop, w, h) => {
  const c = crop;
  const sx = w / c.w;
  const sy = h / c.h;
  const src = artUrl(file);
  return page(
    w,
    h,
    `<div style="position:absolute;inset:0;background:url(${src}) ${-c.x * sx}px ${-c.y * sy}px / ${c.srcW * sx}px ${c.srcH * sy}px no-repeat"></div>`,
  );
};

/**
 * Weissen Hintergrund der Gemini-Bilder transparent machen (weicher Uebergang, Farbe vom Weiss befreit). Nur Pixel, die
 * vom Bildrand aus ueber helle Pixel (Summe > from) zusammenhaengend erreichbar sind: helle Stellen im Papier selbst
 * bleiben deckend (sonst entstehen graue, halb durchsichtige Flecken nahe der Kante). seeds = zusaetzliche Startpunkte [x, y]
 * (Pixel), die nur zaehlen, wenn sie hell sind.
 */
export function keyWhite(rgba, w, h, { from = 700, to = 752, seeds = [], edges = true } = {}) {
  const bright = (i) => rgba[i * 4] + rgba[i * 4 + 1] + rgba[i * 4 + 2] > from;
  const seen = new Uint8Array(w * h);
  const stack = [];
  const push = (i) => {
    if (!seen[i] && bright(i)) {
      seen[i] = 1;
      stack.push(i);
    }
  };
  for (let x = 0; x < w && edges; x++) {
    push(x);
    push((h - 1) * w + x);
  }
  for (let y = 0; y < h && edges; y++) {
    push(y * w);
    push(y * w + w - 1);
  }
  // weitere Startpunkte (x, y), z. B. die freie Mitte eines Rahmens, die vom Rand aus nicht erreichbar ist
  for (const [sx, sy] of seeds) {
    const x = Math.round(sx);
    const y = Math.round(sy);
    if (x >= 0 && x < w && y >= 0 && y < h) push(y * w + x);
  }
  while (stack.length) {
    const i = stack.pop();
    const x = i % w;
    if (x > 0) push(i - 1);
    if (x < w - 1) push(i + 1);
    if (i >= w) push(i - w);
    if (i < (h - 1) * w) push(i + w);
  }
  for (let i = 0; i < w * h; i++) {
    if (!seen[i]) continue;
    const o = i * 4;
    const sum = rgba[o] + rgba[o + 1] + rgba[o + 2];
    const a = Math.max(0, Math.min(1, (to - sum) / (to - from)));
    for (let k = 0; k < 3; k++) rgba[o + k] = a > 0 ? Math.max(0, Math.min(255, Math.round((rgba[o + k] - 255 * (1 - a)) / a))) : 0;
    rgba[o + 3] = Math.round(rgba[o + 3] * a);
  }
  return rgba;
}

// Pergament (B1 "Buch natuerlich"): je Reiter ein Seitenpaar aus EINEM Gemini-Bild (art/journal/spread_<reiter>.jpg, 2752 x 1536,
// beide Seiten auf weissem Grund, Woelbung und Falzschatten ueber beide Haelften, unregelmaessige Aussenkanten). Das Bild wird
// einmal zugeschnitten und als Ganzes freigestellt (keyWhite vom Rand aus, Kante SPREAD_ERODE px eingezogen), dann genau an der
// Falzlinie in zwei Haelften geteilt -> Media/Page_<reiter>_L/_R.tga (je 512 x 512). Weil die Teilung in derselben Pixelzeile
// liegt, gibt es keinen doppelten Falz und keinen Saum zwischen den Seiten (an der Teilung wird nichts eingezogen).
// SPREAD_CROPS = die freigegebenen Seitenpaare (29.10.2026: alle sechs).
// Reise seit B1h aus spread_reise_v2.jpg (gleiches Bild ohne den schraegen Knick rechts Mitte; gemessen: gleiche Geometrie, Papier
// x 580..2170, y 188..1309, Falz 1374, Unterkante bis 1269); spread_reise.jpg bleibt im Repo, wird nicht mehr gerendert. Reiter ohne eigenes freigegebenes Bild nutzen das der Reise
// (SPREAD_FALLBACK). Neues Seitenpaar einbauen: Bild nach art/journal/, freigeben lassen, Zuschnitt messen
// (Falz = dunkelste Spalte im mittleren Band, x = Falz - w/2, also Falz genau in der Mitte des Zuschnitts) und hier eintragen,
// dann `node scripts/render-media.mjs --only Page_<reiter>_L` und `--only Page_<reiter>_R`, zuletzt `--check`.
// Gemessen je Bild (29.10.2026, PIL, Farbsumme < 690): alle sechs Bilder haben dieselbe Geometrie (gleicher Gemini-Chat,
// Abweichung hoechstens 3 px): Papier x 579..2172, y 185..1310 (unten mittig die Spitze des Falzes), 85 % der Zeilen Papier ab y 211..219
// bis 1238..1242, Falz (dunkelste Spalte, in sieben Hoehen von y 260 bis 1230 gemessen) in allen Bildern senkrecht bei 1374 -> Teilung
// genau durch ihre Mitte (1374,5; B1d), x = 574,5. Die Grundbild-Falz liegt ebenso bei 1374 (BOOK_SLICE_SRC spine), beide
// fallen im Spiel auf die Fenstermitte. Zuschnitt 1600 breit (je Haelfte 800, Papier
// links 797, rechts 795), y 185..1284 (B1g): die welligen Ober- und Unterkanten bleiben ganz drin, auch die Ecken unten
// (Papier reicht bis y 1269, z. B. die gerollte Ecke unten rechts; bei 1270 war sie abgeschnitten), nur die Spitze unten mittig
// wird gekappt. Seitenverhaeltnis 1,455; im Spiel liegt das Papier auf Frame.paperRect (1076 x 693 = 1,553), also senkrecht um
// 6 % gestaucht (auf Pergament unauffaellig).
// N1 (29.10.2026): Notizen aus spread_notizen.jpg (gleiche Geometrie, gemessen: Papier x 583..2170, y 189..1269, Falz 1373..1375).
export const PAGE_IDS = ["reise", "chronik", "kampf", "quests", "schaetze", "momente", "notizen"];
export const SPREAD_FALLBACK = "reise";
export const SPREAD_CROPS = {
  reise: { file: "spread_reise_v2.jpg", x: 574.5, y: 185, w: 1600, h: 1100, fold: 1374.5, srcW: 2752, srcH: 1536 },
  chronik: { file: "spread_chronik_v2.jpg", x: 574.5, y: 185, w: 1600, h: 1100, fold: 1374.5, srcW: 2752, srcH: 1536 },
  kampf: { file: "spread_kampf.jpg", x: 574.5, y: 185, w: 1600, h: 1100, fold: 1374.5, srcW: 2752, srcH: 1536 },
  quests: { file: "spread_quests.jpg", x: 574.5, y: 185, w: 1600, h: 1100, fold: 1374.5, srcW: 2752, srcH: 1536 },
  schaetze: { file: "spread_schaetze_v2.jpg", x: 574.5, y: 185, w: 1600, h: 1100, fold: 1374.5, srcW: 2752, srcH: 1536 },
  momente: { file: "spread_momente.jpg", x: 574.5, y: 185, w: 1600, h: 1100, fold: 1374.5, srcW: 2752, srcH: 1536 },
  notizen: { file: "spread_notizen.jpg", x: 574.5, y: 185, w: 1600, h: 1100, fold: 1374.5, srcW: 2752, srcH: 1536 },
};
export const SPREAD_TEX = { w: 1024, h: 512 }; // beide Haelften nebeneinander gerendert, Teilung bei Spalte 512
const SPREAD_ERODE = 1;
// Gemini malt das Pergament satter und dunkler als die bisherigen Seiten (Mittel L 0,60 statt 0,73): fuer Theme.ink (Kontrast
// >= 4,5 : 1, tests/journal-ink.test.mjs) wird es mit einer Gammakurve aufgehellt (Mitten heller, Tinte/Umriss bleiben dunkel)
export const SPREAD_GAMMA = 0.75;
export const SPREAD_KEY = { from: 705, to: 752 };
// Unterer Blattschnitt am Falz (B1d): Gemini malt unten mittig eine tiefe Spitze (bis y 1308), der Zuschnitt endet bei 1270 und
// schnitt sie bisher gerade ab (ein flaches Stueck ueber beiden Seiten). Jetzt wird die Unterkante zum Falz hin als V
// freigestellt: an der Falzlinie bis zur Zuschnittkante, je rise Quellpixel hoeher in width Quellpixel Abstand (sanft, steil
// am Falz), dort trifft sie die gemalte Unterkante (ca. 1240). Danach (bis width * (1 + fade)) taucht die Schnittlinie unter die
// Zuschnittkante ab: weiter aussen bleibt die gemalte Unterkante unberuehrt (B1g; vorher schnitt die Linie dort ueberall
// rise Pixel weg, auch die Ecken). Entlang der neuen Kante ein schmaler dunkler Saum wie Geminis
// Papierkante. So taucht jede Haelfte fuer sich zum Falz ab, und das V des Grundbilds darunter bleibt sichtbar.
export const SPREAD_V = { rise: 45, width: 150, fade: 0.3, rim: 3, rimDark: 0.7 };
/** V-Maske in Renderpixeln fuer einen Zuschnitt c (Rendergroesse SPREAD_TEX) */
export const spreadV = (c, V = SPREAD_V) => ({
  rise: (V.rise * SPREAD_TEX.h) / c.h, width: (V.width * SPREAD_TEX.w) / c.w, fade: V.fade, rim: V.rim, rimDark: V.rimDark,
});
/** Unterkante zum Falz (Bildmitte) als V freistellen: Hoehe ueber der Unterkante = rise * (1 - (1 - t)^2), t = Abstand / width;
 *  zwischen t = 1 und 1 + fade sinkt die Linie unter die Unterkante, weiter aussen wird nichts freigestellt */
export function vMask(rgba, w, h, v) {
  const mid = w / 2;
  for (let x = 0; x < w; x++) {
    const tt = Math.abs(x + 0.5 - mid) / v.width;
    const fade = v.fade ?? 0;
    if (tt >= 1 + fade && fade > 0) continue;
    const t = Math.min(1, tt);
    let line = h - v.rise * (1 - (1 - t) * (1 - t)); // y der neuen Kante (Pixel darunter frei)
    if (tt > 1 && fade > 0) line += ((tt - 1) / fade) * (v.rise + v.rim + 2); // aussen unter die Kante abtauchen
    for (let y = Math.max(0, Math.floor(line - v.rim - 2)); y < h; y++) {
      const o = (y * w + x) * 4;
      const d = line - (y + 0.5); // Abstand ueber der Kante
      const a = Math.max(0, Math.min(1, d + 0.5));
      rgba[o + 3] = Math.round(rgba[o + 3] * a);
      if (d > 0 && d < v.rim && t < 1) {
        const k = v.rimDark + (1 - v.rimDark) * (d / v.rim);
        for (let c = 0; c < 3; c++) rgba[o + c] = Math.round(rgba[o + c] * k);
      }
    }
  }
  return rgba;
}
/** Seitenpaar eines Reiters: freigegebenes eigenes Bild oder das der Reise */
export const spreadFor = (id) => SPREAD_CROPS[id] ?? SPREAD_CROPS[SPREAD_FALLBACK];

/** Doppelseite (w x h, RGBA) freistellen, unten am Falz als V freistellen (v), aufhellen (gamma) und an der Mitte teilen: { l, r } je (w/2) x h */
export function splitSpread(rgba, w, h, { erode = SPREAD_ERODE, gamma = SPREAD_GAMMA, v = null } = {}) {
  // Schwelle hoch (705): der Zuschnitt schneidet oben/unten durchs Papier (Farbsumme bis ca. 690), die Flutung darf nicht
  // ins Papier laufen; nur der weisse Grund (ab 705) wird frei
  erodeEdge(keyWhite(rgba, w, h, SPREAD_KEY), w, h, erode);
  if (v) vMask(rgba, w, h, v);
  if (gamma !== 1) {
    const lut = new Uint8Array(256);
    for (let v = 0; v < 256; v++) lut[v] = Math.round(255 * (v / 255) ** gamma);
    for (let i = 0; i < w * h * 4; i += 4) {
      rgba[i] = lut[rgba[i]];
      rgba[i + 1] = lut[rgba[i + 1]];
      rgba[i + 2] = lut[rgba[i + 2]];
    }
  }
  const half = w / 2;
  const l = new Uint8Array(half * h * 4);
  const r = new Uint8Array(half * h * 4);
  for (let y = 0; y < h; y++) {
    l.set(rgba.subarray(y * w * 4, (y * w + half) * 4), y * half * 4);
    r.set(rgba.subarray((y * w + half) * 4, (y + 1) * w * 4), y * half * 4);
  }
  return { l, r };
}
const pageTexture = (id, side) => {
  const c = spreadFor(id);
  return {
    name: `Page_${id}_${side === "l" ? "L" : "R"}`,
    w: SPREAD_TEX.w / 2,
    h: SPREAD_TEX.h,
    rw: SPREAD_TEX.w,
    rh: SPREAD_TEX.h,
    html: () => ART(c.file, c, SPREAD_TEX.w, SPREAD_TEX.h),
    post: (rgba, w, h) => splitSpread(rgba, w, h, { v: spreadV(c) })[side],
    spread: c.file,
  };
};

/**
 * Sichtbare Kante um r Pixel nach innen ziehen: Alpha = kleinstes Alpha im Umkreis (frisst den hellen Saum). Ausserhalb
 * des Bildes gilt als durchsichtig, ausser an der Kante keep ("left"/"right").
 */
export function erodeEdge(rgba, w, h, r, { keep = null } = {}) {
  const a0 = new Uint8Array(w * h);
  for (let i = 0; i < w * h; i++) a0[i] = rgba[i * 4 + 3];
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (a0[y * w + x] === 0) continue;
      let m = 255;
      for (let dy = -r; dy <= r && m > 0; dy++) {
        const yy = y + dy;
        for (let dx = -r; dx <= r; dx++) {
          const xx = x + dx;
          if (dx * dx + dy * dy > r * r) continue;
          if ((xx < 0 && keep === "left") || (xx >= w && keep === "right")) continue;
          m = Math.min(m, yy < 0 || yy >= h || xx < 0 || xx >= w ? 0 : a0[yy * w + xx]);
        }
      }
      rgba[(y * w + x) * 4 + 3] = Math.min(a0[y * w + x], m);
    }
  }
  return rgba;
}

// Toast: Pergamentstreifen aus Gemini (art/toast/toastBG.jpg, 3168 x 1344, gerissene Raender auf Weiss, innen
// feiner Sepia-Rahmen, links ein runder dunklerer Fleck fuer Medaille/Gebietszeichen, unten links ein Tinten-Schnoerkel).
// Zuschnitt einmal gemessen (27.10.2026): Bounding-Box aller Pixel mit Farbsumme < 690 ist x 58..3108, y 47..1306, dazu
// 6 bzw. 7 px Rand; der weisse Rest wird freigestellt. Seitenverhaeltnis des Zuschnitts 2,407 : 1 -> auf 512 x 256 gestreckt,
// im Spiel mit Toast.W/H (288 x 120 = 2,4 : 1) wieder zurueck, also unverzerrt. Der Fleck: Mitte bei x 11 %, y 47 % des
// Quellbilds (348 | 632 px), Durchmesser 301 px; Toast.ICON_X/ICON_Y/Toast.H in journal/Toast.lua rechnen daraus.
// Neues Bild einbauen: Datei ersetzen, Zuschnitt neu messen (TOAST_CROP), `node scripts/render-media.mjs --only Toast`.
export const TOAST_CROP = { file: "toast/toastBG.jpg", x: 52, y: 40, w: 3062, h: 1272, srcW: 3168, srcH: 1344 };
// kleinerer Einzug als bei den Pergamenten: das Bild wird 6-fach statt 3,3-fach verkleinert
const TOAST_ERODE = 2;
const TOAST_KEY = (rgba, w, h) => erodeEdge(keyWhite(rgba, w, h, { from: 600, to: 720 }), w, h, TOAST_ERODE);

// Willkommen-Karte (F1c, auch der Rast-Rueckblick F1g): art/toast/welcome_card.jpg (2752 x 1536, Gemini, weisser Grund, Pergament
// mit Falzlinie, links ein aufgedruckter Medaillon-Ring, oben links Wachssiegel, unten rechts ein Lesezeichenband, das ueber den
// Papierrand hinaus ragt). Gemessen 29.10.2026 (PIL, Farbsumme < 690): Papier x 223..2544, y 139..~1362 (Unterkante wellig),
// Band x ~2120..2326, y bis 1505; Falz senkrecht bei x 1372; Medaillon-Ring Mitte (682 | 765), aussen Durchmesser 607, innere
// freie Flaeche 490; Wachssiegel x 570..800, y 195..415. Zuschnitt x 205..2565, y 120..1525 (2360 x 1405 = 1,68 : 1, mit Band,
// Papier, Papierschatten) -> auf 1024 x 512 gestreckt, im Spiel mit Toast.CARD.w/h (640 x 381) wieder zurueck, also unverzerrt.
// Die Raster-Konstanten in journal/Toast.lua (Toast.CARD: iconX/iconY/iconSize, textX/textY/textW) rechnen daraus (Massstab 640 / 2360).
// Neues Bild einbauen: Datei ersetzen, Zuschnitt neu messen, `node scripts/render-media.mjs --only WelcomeCard`.
// Q64 (30.10.2026): Papier neu, art/toast/welcome_card_v2.jpg (freigegeben, ohne Knick). Gleiche Bildgroesse und Lage
// wie das alte Papier (Papier, Ring, Siegel, Band an denselben Stellen), daher derselbe Zuschnitt und dieselben Toast.CARD-Masse.
export const WELCOME_CARD_CROP = { file: "toast/welcome_card_v2.jpg", x: 205, y: 120, w: 2360, h: 1405, srcW: 2752, srcH: 1536 };
// Freistellung wie beim Buchrand (keyNeutralEdge, 29.10.2026, Befund "heller weiss-grauer Rand um Papier und Band"): vorher
// keyWhite 710/755 + erodeEdge 3, das liess Geminis grauen Papierschatten (Farbsumme ~500..700, kaum Farbe) deckend stehen. Das
// Papier ist cremefarben (Buntheit >= 40), der Grund und sein Schatten neutral: so trennt die Buntheit, nicht die Helligkeit, und
// das helle Papier wird nicht angefressen. Schatten wird weich und dunkel statt grau.
export const WELCOME_CARD_EDGE_KEY = { chroma: 20, min: 330, shadow: 0.7, fade: 6, rim: 0.75, grow: { chroma: 46, steps: 8, maxSum: 540 } };
const WELCOME_CARD_KEY = (rgba, w, h) => keyNeutralEdge(rgba, w, h, WELCOME_CARD_EDGE_KEY);

// Erzaehler der Willkommen-Karte (Q64): je Volk ein Portraet im runden Bildfeld (Gemini, art/toast/narrator_<volk>_v3.jpg bzw.
// Skyborne _v2, je 2048 x 2048, freigegeben; aussen Magenta, darin ein Kreis mit Szene, die Figur ragt teils heraus).
// Kreis je Bild gemessen 30.10.2026 (RANSAC auf der Grenze Magenta/Bild, Zwerg auf der Grenze weisser Aufkleber-Rand/Szene, von
// Hand geprueft): cx, cy, r in Pixeln des Quellbilds. Ziel: Media/Narrator_<volk>.tga (512 x 512), Kreis immer gleich gelegt
// (NARRATOR_TEX: Mitte x 256, y 250, Radius 176), daher zeigt das Spiel alle Voelker mit denselben Massen (Toast.CARD.portrait).
// Freistellung: im Kreis bleibt alles deckend (auch lila Szenen); ausserhalb Magenta-Key (keyMagenta, Mischfarbe rueckgerechnet,
// rosa Saum entsaettigt), beim Zwerg zusaetzlich der weisse Aufkleber-Rand und sein Schatten. Pop-out: die Figur darf oben und
// seitlich aus dem Kreis ragen, unterhalb von cy + 0,5 r blendet alles ausserhalb des Kreises weich aus (keine gerade Bildkante
// unten). Neues Bild einbauen: Datei ersetzen, Kreis neu messen, `node scripts/render-media.mjs --only Narrator_<volk>`.
export const NARRATOR_IDS = ["human", "dwarf", "nightelf", "gnome", "orc", "undead", "tauren", "troll", "skyborne"];
export const NARRATOR_SRC = {
  human: { file: "toast/narrator_human_v3.jpg", cx: 1023, cy: 1025, r: 1023 },
  dwarf: { file: "toast/narrator_dwarf_v3.jpg", cx: 1057, cy: 986, r: 725, white: true },
  nightelf: { file: "toast/narrator_nightelf_v3.jpg", cx: 1023, cy: 1024, r: 1024 },
  gnome: { file: "toast/narrator_gnome_v3.jpg", cx: 1020, cy: 1028, r: 1019 },
  orc: { file: "toast/narrator_orc_v3.jpg", cx: 1022, cy: 1024, r: 1023 },
  undead: { file: "toast/narrator_undead_v3.jpg", cx: 1024, cy: 1025, r: 937 },
  tauren: { file: "toast/narrator_tauren_v3.jpg", cx: 1023, cy: 1023, r: 873 },
  troll: { file: "toast/narrator_troll_v3.jpg", cx: 1022, cy: 1025, r: 1023 },
  skyborne: { file: "toast/narrator_skyborne_v2.jpg", cx: 1021, cy: 1024, r: 1023, edgeSpill: 0.6 },
};
export const NARRATOR_SRC_SIZE = 2048;
export const NARRATOR_TEX = { size: 512, cx: 256, cy: 250, r: 176, render: 2, fade: 0.5, fadeBand: 0.12, inset: 2, pure: 170, rimGrow: 2 };

const NARRATOR_HTML = (id) => () => {
  const s = NARRATOR_SRC[id];
  const T = NARRATOR_TEX;
  const k = (T.r * T.render) / s.r;
  const side = T.size * T.render;
  const url = pathToFileURL(path.join(ROOT, "art", s.file)).href;
  return page(side, side, `<img src="${url}" style="position:absolute;left:${T.cx * T.render - s.cx * k}px;top:${T.cy * T.render - s.cy * k}px;width:${NARRATOR_SRC_SIZE * k}px;height:${NARRATOR_SRC_SIZE * k}px">`);
};

/** Halbieren mit vormultipliziertem Alpha (2 x 2 -> 1), Farbe der durchsichtigen Pixel blutet nicht ein */
export function halve(rgba, w, h) {
  const W2 = w >> 1, H2 = h >> 1;
  const out = new Uint8Array(W2 * H2 * 4);
  for (let y = 0; y < H2; y++) for (let x = 0; x < W2; x++) {
    let r = 0, g = 0, b = 0, a = 0;
    for (const [dx, dy] of [[0, 0], [1, 0], [0, 1], [1, 1]]) {
      const o = ((2 * y + dy) * w + 2 * x + dx) * 4;
      const al = rgba[o + 3];
      r += rgba[o] * al; g += rgba[o + 1] * al; b += rgba[o + 2] * al; a += al;
    }
    const d = (y * W2 + x) * 4;
    out[d + 3] = Math.round(a / 4);
    if (a > 0) { out[d] = Math.round(r / a); out[d + 1] = Math.round(g / a); out[d + 2] = Math.round(b / a); }
  }
  return out;
}

/** Erzaehler freistellen (Beschreibung oben). rgba in Rendergroesse (size * render), Ergebnis size x size. */
export function narratorKey(rgba, w, h, id) {
  const s = NARRATOR_SRC[id];
  const T = NARRATOR_TEX;
  const cx = T.cx * T.render, cy = T.cy * T.render, r = T.r * T.render;
  const inner = r - T.inset * T.render;
  const keep = new Uint8Array(w * h); // Alpha im Kreis (0..255), vor dem Key gemerkt
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const d = Math.hypot(x + 0.5 - cx, y + 0.5 - cy);
    keep[y * w + x] = Math.round(255 * Math.max(0, Math.min(1, inner - d + 0.5)));
  }
  // reines Magenta auch im Kreis freistellen (Skyborne: der gemalte Kreis ist rechts hinter dem Fluegel etwas kleiner)
  for (let i = 0; i < w * h; i++) {
    const o = i * 4;
    if (keep[i] && Math.min(rgba[o], rgba[o + 2]) - rgba[o + 1] > T.pure) keep[i] = 0;
  }
  const orig = Uint8Array.from(rgba);
  keyMagenta(rgba, w, h, { noise: 60 });
  if (s.white) {
    // weisser Aufkleber-Rand + grauer/lila Schatten: vom Durchsichtigen aus erreichbar, hell und kaum bunt bzw. halb durchsichtig
    const seen = new Uint8Array(w * h);
    const stack = [];
    for (let i = 0; i < w * h; i++) if (rgba[i * 4 + 3] < 40 && !keep[i]) { seen[i] = 1; stack.push(i); }
    // im Kreis laeuft der weisse Rand zwischen Figur und Szene weiter: dort wird er zur dunklen Kontur (Tinte), nicht durchsichtig
    const ink = new Uint8Array(w * h);
    const rim = (i) => {
      const o = i * 4, R = orig[o], G = orig[o + 1], B = orig[o + 2], A = rgba[o + 3];
      const chroma = Math.max(R, G, B) - Math.min(R, G, B);
      if (keep[i] === 255) return R + G + B > 660 && chroma < 30;
      return A < 235 || (R + G + B > 560 && chroma < 48);
    };
    while (stack.length) {
      const i = stack.pop();
      const x = i % w, y = (i - x) / w;
      for (const j of [x > 0 ? i - 1 : -1, x < w - 1 ? i + 1 : -1, y > 0 ? i - w : -1, y < h - 1 ? i + w : -1]) {
        if (j < 0 || seen[j] || !rim(j)) continue;
        seen[j] = 1;
        if (keep[j] === 255) ink[j] = 1;
        stack.push(j);
      }
    }
    // grauer Saum zwischen Rand und Schatten: noch T.rimGrow Pixel weiter (nur ausserhalb des Kreises)
    for (let step = 0; step < T.rimGrow * T.render; step++) {
      const add = [];
      for (let i = 0; i < w * h; i++) {
        if (seen[i] || keep[i]) continue;
        const x = i % w, y = (i - x) / w;
        if ((x > 0 && seen[i - 1] && !ink[i - 1]) || (x < w - 1 && seen[i + 1] && !ink[i + 1]) || (y > 0 && seen[i - w] && !ink[i - w]) || (y < h - 1 && seen[i + w] && !ink[i + w])) add.push(i);
      }
      for (const i of add) seen[i] = 1;
    }
    for (let i = 0; i < w * h; i++) {
      if (ink[i]) { const o = i * 4; orig[o] = 46; orig[o + 1] = 32; orig[o + 2] = 22; }
      else if (seen[i]) rgba[i * 4 + 3] = 0;
    }
  }
  const fadeTop = cy + T.fade * r, band = Math.max(1, T.fadeBand * r);
  for (let y = 0; y < h; y++) {
    const below = Math.max(0, Math.min(1, 1 - (y - fadeTop) / band));
    for (let x = 0; x < w; x++) {
      const i = y * w + x, o = i * 4;
      const out = Math.round(rgba[o + 3] * below);
      const a = keep[i] + ((255 - keep[i]) * out) / 255;
      // rosa Saum an der Kante (nur ausserhalb des Kreises): Rest-Magenta entfernen
      if (keep[i] < 255 && a > 0) {
        const m = Math.min(rgba[o], rgba[o + 2]) - rgba[o + 1];
        if (m > 0 && rgba[o + 3] < 250) { rgba[o] -= m; rgba[o + 2] -= m; }
      }
      let al = a;
      if (keep[i] > 0) {
        // Skyborne: der Himmel laeuft am Kreisrand rechts oben ins Magenta aus -> dort Farbe rueckgerechnet, reines Magenta durchsichtig
        const spill = s.edgeSpill && Math.hypot(x + 0.5 - cx, y + 0.5 - cy) > s.edgeSpill * r && rgba[o + 3] < 250;
        if (spill) al = Math.min(a, keep[i] * Math.min(1, (2 * rgba[o + 3]) / 255));
        else { rgba[o] = orig[o]; rgba[o + 1] = orig[o + 1]; rgba[o + 2] = orig[o + 2]; }
      }
      rgba[o + 3] = Math.round(al);
      if (rgba[o + 3] === 0) rgba[o] = rgba[o + 1] = rgba[o + 2] = 0;
    }
  }
  return halve(rgba, w, h);
}

const narratorTexture = (id) => ({
  name: "Narrator_" + id, w: NARRATOR_TEX.size, h: NARRATOR_TEX.size,
  rw: NARRATOR_TEX.size * NARRATOR_TEX.render, rh: NARRATOR_TEX.size * NARRATOR_TEX.render,
  html: NARRATOR_HTML(id), post: (rgba, w, h) => narratorKey(rgba, w, h, id), source: "art/" + NARRATOR_SRC[id].file,
});

// Siegel der Reise (Altbilder): ein Bildatlas Media/Seals.tga (1024 x 512, 8 x 4 Zellen zu 128 px, Zelle i = i-tes Altbild
// von SEAL_IDS = Theme.SEAL_LEGACY_IDS; die letzten 11 Zellen bleiben leer; die Medaillen verweisen per Katalogfeld art darauf). Quellen: art/seals/<id>.jpg (2048 x 2048, Gemini, weisser Grund).
// Ein Atlas statt 21 Dateien: eine Textur im Spiel, ein Eintrag in Theme.TEX, Zellen per SetTexCoord; Zuschnitt und
// Freistellung laufen je Zelle (keyWhite vom Zellenrand aus), also ohne Ausbluten zwischen den Nachbarn.
export const SEAL_IDS = [
  "first_bag", "first_blue", "first_death", "guild", "first_flight", "first_book", "first_fish", "hearth", "continent",
  "first_dungeon", "first_rare", "close_win", "profession", "reputation", "duel", "mount", "first_epic", "boss",
  "first_raid", "fortune", "level60",
];
export const SEAL_ATLAS = { cols: 8, rows: 4, cell: 128 };
// Medaillen mit Stufen (Spec change-medaillen, Weg A, Etappe 2): Motiv und Metallrahmen getrennt, im Spiel uebereinander
// (Theme.sealLayers: Motiv unten mit Theme.SEAL_MOTIF_SCALE, Rahmen der hoechsten Stufe darueber).
//   Media/Seals.tga      Motiv-Atlas 1024 x 1024, 8 x 8 Zellen zu 128 px, Zelle i = i-te Medaille von Chronik.SEALS
//                        (SEAL_MOTIF_IDS, ein Test haelt beide gleich). Jede Zelle ist die runde Emaille-Flaeche, kreisrund
//                        ausgeschnitten (CSS-Kreis, weiche Kante, ausserhalb durchsichtig: kein weisser Saum).
//   Media/SealFrames.tga Rahmen-Atlas 512 x 512, 2 x 2 Zellen zu 256 px: Bronze, Silber, Gold, Legendaer (SEAL_FRAME_IDS).
//                        Weisser Grund aussen und die helle Mitte werden freigestellt (keyWhite vom Rand bzw. von der Mitte).
// Quellen (freigegeben 30.10.2026): art/seals/v2/frame_<stufe>.jpg und 15 neue Motive art/seals/v2/motif_<name>.jpg
// (2048 x 2048, flacher weisser Grund, Kreis mittig); die 20 weiter genutzten Altbilder (art/seals/<id>.jpg) liefern ihr Motiv
// ueber das Mittelfeld innerhalb des Rings. art/seals/v2/_uebersicht.jpg ist nur der Uebersichtsbogen.
export const SEAL_MOTIF_IDS = [
  "explorer", "pathfinder", "continent", "flightmaster", "frequent_flyer", "hunter", "elite_hunter", "rare_hunter",
  "close_win", "duel", "quests", "reputation", "books", "profession", "fortune", "blue", "epic", "angler", "gatherer",
  "guild", "companions", "social", "regular", "campfire", "rested", "hearth", "tough", "flawless", "unscathed", "dungeon",
  "boss", "raid", "mount", "plans", "level60",
];
export const SEAL_MOTIF_ATLAS = { cols: 8, rows: 8, cell: 128 };
export const SEAL_FRAME_IDS = ["bronze", "silver", "gold", "legendary"];
export const SEAL_FRAME_ATLAS = { cols: 2, rows: 2, cell: 256 };
// Quelle je Medaille: neues Motiv (v2/motif_<name>.jpg) oder Altbild (Katalogfeld art = <id>.jpg). "Ohne Fehltritt" hat ein eigenes
// Motiv (v2/motif_flawless.jpg: Stiefel auf leuchtender Steintreppe, freigegeben 30.10.2026), "Lange unverwundet" nutzt "Ohne Narbe".
export const SEAL_MOTIF_SRC = {
  explorer: "v2/motif_globetrotter", pathfinder: "v2/motif_pathfinder", continent: "continent",
  flightmaster: "v2/motif_flightmaster", frequent_flyer: "first_flight", hunter: "v2/motif_hunter",
  elite_hunter: "v2/motif_elitehunter", rare_hunter: "first_rare", close_win: "close_win", duel: "duel",
  quests: "v2/motif_questbook", reputation: "reputation", books: "first_book", profession: "profession", fortune: "fortune",
  blue: "first_blue", epic: "first_epic", angler: "first_fish", gatherer: "v2/motif_gatherer", guild: "guild",
  companions: "v2/motif_companions", social: "v2/motif_sociable", regular: "v2/motif_regular", campfire: "v2/motif_campfire",
  rested: "v2/motif_rested", hearth: "hearth", tough: "v2/motif_unbreakable", flawless: "v2/motif_flawless",
  unscathed: "v2/motif_unscarred", dungeon: "first_dungeon", boss: "boss", raid: "first_raid", mount: "mount",
  plans: "v2/motif_ownways", level60: "level60",
};
// Kreis der neuen Motive, gemessen (30.10.2026, Quellpixel: Bounding-Box aller Pixel mit Farbsumme < 690, mindestens 7 je Zeile
// bzw. Spalte) [x0, y0, Breite, Hoehe]; geschnitten wird SEAL_MOTIF_INSET innerhalb des Kreises (die dunkle Kante bleibt draussen).
export const SEAL_V2_BOX = {
  campfire: [204, 203, 1640, 1641], companions: [204, 204, 1641, 1640], elitehunter: [205, 204, 1639, 1640],
  flightmaster: [204, 204, 1640, 1640], gatherer: [204, 204, 1641, 1640], globetrotter: [204, 204, 1640, 1640],
  flawless: [203, 202, 1643, 1642], hunter: [204, 204, 1640, 1640], ownways: [204, 204, 1640, 1640], pathfinder: [204, 204, 1640, 1640],
  questbook: [205, 204, 1639, 1640], regular: [204, 204, 1640, 1640], rested: [204, 204, 1640, 1640],
  sociable: [204, 204, 1640, 1640], unbreakable: [204, 204, 1640, 1640], unscarred: [205, 204, 1639, 1640],
};
export const SEAL_MOTIF_INSET = 0.015;
// Mittelfeld der Altbilder: Radius in Prozent des Medaillon-Radius (SEAL_BOX), gemessen als dunkelste Ringlinie (innere Kante des
// Metallrings, Mittel ueber 360 Strahlen), wo der Ring noch hineinragte von Hand enger gezogen; geschnitten wird 2 % weiter innen.
export const SEAL_LEGACY_INNER = { boss: 63, close_win: 55, continent: 71, duel: 62, first_blue: 66, first_book: 60, first_dungeon: 67, first_epic: 59, first_fish: 70, first_flight: 68, first_raid: 61, first_rare: 67, fortune: 57, guild: 69, hearth: 73, level60: 56, mount: 65, profession: 60, reputation: 57 };
// Rahmen: alle vier aus dem vollen Quellbild (gleicher Massstab; Legendaer hat Strahlen bis an den Rand). Gemessen: Ring aussen
// 1880 px, Oeffnung 1360 px von 2048 -> Oeffnung = 0,664 der Zelle; Theme.SEAL_MOTIF_SCALE legt das Motiv knapp darunter.
export const SEAL_FRAME_SRC = 2048;
export const SEAL_FRAME_OPENING = 1360 / 2048;

// Kreis-Ausschnitt eines Motivs in Quellpixeln -> { file, cx, cy, r, src }
export function sealMotifCrop(id) {
  const src = SEAL_MOTIF_SRC[id];
  if (!src) throw new Error(`Medaille ohne Motivquelle: ${id}`);
  if (src.startsWith("v2/")) {
    const [x, y, w, h] = SEAL_V2_BOX[src.slice(9)];
    const r = ((w + h) / 4) * (1 - SEAL_MOTIF_INSET);
    return { file: `${src}.jpg`, cx: x + w / 2, cy: y + h / 2, r, src: 2048 };
  }
  const [x, y, w, h] = SEAL_BOX[src];
  const r = ((w + h) / 4) * ((SEAL_LEGACY_INNER[src] - 2) / 100);
  return { file: `${src}.jpg`, cx: x + w / 2, cy: y + h / 2, r, src: 2048 };
}
const sealFileUrl = (file) => pathToFileURL(path.join(ROOT, "art", "seals", file)).href;
const SEAL_MOTIFS_HTML = () => {
  const c = SEAL_MOTIF_ATLAS.cell;
  const cells = SEAL_MOTIF_IDS.map((id, i) => {
    const k = sealMotifCrop(id);
    const z = c / (2 * k.r);
    return `<div style="position:absolute;left:${(i % SEAL_MOTIF_ATLAS.cols) * c}px;top:${Math.floor(i / SEAL_MOTIF_ATLAS.cols) * c}px;width:${c}px;height:${c}px;overflow:hidden;border-radius:50%"><img src="${sealFileUrl(k.file)}" style="position:absolute;left:${-(k.cx - k.r) * z}px;top:${-(k.cy - k.r) * z}px;width:${k.src * z}px;height:${k.src * z}px"></div>`;
  });
  return page(SEAL_MOTIF_ATLAS.cols * c, SEAL_MOTIF_ATLAS.rows * c, cells.join(""));
};
const SEAL_FRAMES_HTML = () => {
  const c = SEAL_FRAME_ATLAS.cell;
  const cells = SEAL_FRAME_IDS.map((id, i) =>
    `<div style="position:absolute;left:${(i % SEAL_FRAME_ATLAS.cols) * c}px;top:${Math.floor(i / SEAL_FRAME_ATLAS.cols) * c}px;width:${c}px;height:${c}px;overflow:hidden;background:#fff"><img src="${sealFileUrl(`v2/frame_${id}.jpg`)}" style="position:absolute;left:0;top:0;width:${c}px;height:${c}px"></div>`);
  return page(SEAL_FRAME_ATLAS.cols * c, SEAL_FRAME_ATLAS.rows * c, cells.join(""));
};
// Rahmen freistellen, Zelle fuer Zelle: aussen der weisse Grund (vom Zellenrand), innen die helle Mitte (Grau ~235, von der
// Zellenmitte aus, weicher Uebergang an der dunklen Innenkante), danach die Aussenkante 1 px eingezogen (kein heller Saum)
export const SEAL_FRAME_KEY = { outer: { from: 706, to: 748 }, inner: { from: 600, to: 700 } };
const SEAL_FRAMES_KEY = (rgba, w, h) => {
  const c = SEAL_FRAME_ATLAS.cell;
  for (let i = 0; i < SEAL_FRAME_IDS.length; i++) {
    const cx = (i % SEAL_FRAME_ATLAS.cols) * c;
    const cy = Math.floor(i / SEAL_FRAME_ATLAS.cols) * c;
    const cell = new Uint8Array(c * c * 4);
    for (let y = 0; y < c; y++) cell.set(rgba.subarray(((cy + y) * w + cx) * 4, ((cy + y) * w + cx + c) * 4), y * c * 4);
    keyWhite(cell, c, c, SEAL_FRAME_KEY.outer);
    erodeEdge(cell, c, c, 1);
    keyWhite(cell, c, c, { ...SEAL_FRAME_KEY.inner, edges: false, seeds: [[c / 2, c / 2]] });
    for (let y = 0; y < c; y++) rgba.set(cell.subarray(y * c * 4, (y + 1) * c * 4), ((cy + y) * w + cx) * 4);
  }
  return rgba;
};
const SEAL_PAD = 0.07; // Rand um das Medaillon (Anteil der Kantenlaenge), damit die Kante in der Zelle weich ausklingt
// Zuschnitt je Siegel, einmal gemessen (27.10.2026, Quellpixel, Suchlauf im Browser: Bounding-Box aller Pixel mit
// Farbsumme < 690, mindestens 7 solche Pixel je Zeile bzw. Spalte). [x0, y0, Breite, Hoehe] des Medaillons; der
// quadratische Zuschnitt sitzt mittig darauf und ist SEAL_PAD groesser.
export const SEAL_BOX = {
  first_bag: [168, 168, 1712, 1710],
  first_blue: [151, 153, 1747, 1743],
  first_death: [295, 296, 1458, 1456],
  guild: [215, 215, 1618, 1617],
  first_flight: [219, 210, 1610, 1614],
  first_book: [74, 75, 1904, 1904],
  first_fish: [99, 100, 1851, 1848],
  hearth: [106, 110, 1837, 1830],
  continent: [38, 39, 1973, 1972],
  first_dungeon: [97, 92, 1856, 1854],
  first_rare: [66, 65, 1917, 1918],
  close_win: [189, 185, 1670, 1669],
  profession: [154, 154, 1741, 1741],
  reputation: [81, 81, 1886, 1884],
  duel: [122, 131, 1804, 1799],
  mount: [127, 131, 1793, 1780],
  first_epic: [180, 179, 1688, 1687],
  boss: [82, 84, 1885, 1886],
  first_raid: [126, 122, 1797, 1800],
  fortune: [118, 120, 1812, 1810],
  level60: [108, 103, 1832, 1835],
};
export function sealCrop(id) {
  const [x, y, w, h] = SEAL_BOX[id];
  const side = Math.round(Math.max(w, h) * (1 + SEAL_PAD));
  return { x: Math.round(x + w / 2 - side / 2), y: Math.round(y + h / 2 - side / 2), side };
}
const SEAL_SRC = 2048; // Kantenlaenge der Quellbilder in art/seals/
const sealUrl = (id) => pathToFileURL(path.join(ROOT, "art", "seals", `${id}.jpg`)).href;
const SEALS_HTML = () => {
  const c = SEAL_ATLAS.cell;
  const cells = SEAL_IDS.map((id, i) => {
    const k = sealCrop(id);
    const z = c / k.side; // Quellpixel -> Zellenpixel
    return `<div style="position:absolute;left:${(i % SEAL_ATLAS.cols) * c}px;top:${Math.floor(i / SEAL_ATLAS.cols) * c}px;width:${c}px;height:${c}px;overflow:hidden;background:#fff"><img src="${sealUrl(id)}" style="position:absolute;left:${-k.x * z}px;top:${-k.y * z}px;width:${SEAL_SRC * z}px;height:${SEAL_SRC * z}px"></div>`;
  });
  return page(SEAL_ATLAS.cols * c, SEAL_ATLAS.rows * c, cells.join(""));
};
// Weiss freistellen, Zelle fuer Zelle (Flood-Fill vom Zellenrand aus)
const SEALS_KEY = (rgba, w, h) => {
  const c = SEAL_ATLAS.cell;
  for (let i = 0; i < SEAL_IDS.length; i++) {
    const cx = (i % SEAL_ATLAS.cols) * c;
    const cy = Math.floor(i / SEAL_ATLAS.cols) * c;
    const cell = new Uint8Array(c * c * 4);
    for (let y = 0; y < c; y++) cell.set(rgba.subarray(((cy + y) * w + cx) * 4, ((cy + y) * w + cx + c) * 4), y * c * 4);
    keyWhite(cell, c, c, { from: 706, to: 748 });
    for (let y = 0; y < c; y++) rgba.set(cell.subarray(y * c * 4, (y + 1) * c * 4), ((cy + y) * w + cx) * 4);
  }
  return rgba;
};

// Gebietszeichen des Toasts "Neues Gebiet": Media/ZoneSeal.tga (128 x 128), rundes Bronze-Medaillon mit Landschaft und
// Wegweiser (Gemini, art/toast/new_zone.jpg, 2048 x 2048, weisser Grund, gleicher Stil wie art/seals/*.jpg). Zuschnitt wie bei
// den Siegeln (Quadrat mittig auf dem Medaillon, SEAL_PAD Rand), einmal gemessen (28.10.2026, Farbsumme < 690 bzw. < 600,
// mindestens 7 bzw. 20 Pixel je Zeile/Spalte): Medaillon x 38, y 39, 1973 x 1972. Fehlt die Quelldatei und auch die TGA,
// wird die Textur uebersprungen (`--check` bleibt gruen, der Toast faellt auf das sepiafarbene Marker-Zeichen zurueck).
export const ZONE_SEAL = { file: "toast/new_zone.jpg", src: 2048, box: [38, 39, 1973, 1972] };
export function zoneSealCrop() {
  const [x, y, w, h] = ZONE_SEAL.box;
  const side = Math.round(Math.max(w, h) * (1 + SEAL_PAD));
  return { x: Math.round(x + w / 2 - side / 2), y: Math.round(y + h / 2 - side / 2), side };
}
const ZONE_SEAL_HTML = () => {
  const k = zoneSealCrop();
  const z = 128 / k.side;
  const url = pathToFileURL(path.join(ROOT, "art", ZONE_SEAL.file)).href;
  return page(128, 128, `<div style="position:absolute;inset:0;overflow:hidden;background:#fff"><img src="${url}" style="position:absolute;left:${-k.x * z}px;top:${-k.y * z}px;width:${ZONE_SEAL.src * z}px;height:${ZONE_SEAL.src * z}px"></div>`);
};
const ZONE_SEAL_KEY = (rgba, w, h) => erodeEdge(keyWhite(rgba, w, h, { from: 706, to: 748 }), w, h, 1);

// Notizzettel (Z3): leichter Notizzettel (Gemini, art/journal/todo_pad_leicht_v1.jpg, freigegeben 30.10.2026; 1792 x 2400,
// Magenta-Grund, Klebeband oben, gerissene Kanten, KEINE gedruckten Linien, keine Lasche, keine eingerollte Ecke). Gemessen (PIL,
// Nicht-Magenta, mindestens 20 Pixel je Zeile/Spalte): Blatt x 148..1646, y ~200..2195, Klebeband x 740..1051, y 145..264.
// Zuschnitt x 115..1675, y 120..2240 (1560 x 2120, rundum ~30 px Magenta-Rand). Die senkrechte 3-Teilung im Spiel
// (Theme.TODO_PAD_SLICE) haengt an diesen Zahlen: oben bis unter das Klebeband (v 0 .. 0,12), Mitte gedehnt, unten die gerissene
// Unterkante (v 0,88 .. 1). Die Seitenkanten wellen ueber die ganze Hoehe um nur +-8 px, die Dehnung der Mitte faellt nicht auf.
// Das Klebeband hat durch den Magenta-Grund einen Rosastich: TODO_PAD_KEY macht es vor der Freistellung neutral-beige und halb
// durchsichtig (todoPadTape). Linien zieht das Spiel selbst je Zeile (journal/TodoTracker.lua); unruleSheet bleibt als Werkzeug
// fuer Bilder mit gedruckten Linien erhalten, wird fuer dieses Bild aber nicht mehr aufgerufen.
export const TODO_PAD = { file: "todo_pad_leicht_v1.jpg", x: 115, y: 120, w: 1560, h: 2120, srcW: 1792, srcH: 2400 };
// Klebeband im Zuschnitt (Anteile von Breite/Hoehe: u 0,401 .. 0,600, v 0,012 .. 0,068), mit etwas Spiel; Alpha 0,8 = Papier schimmert durch
export const TODO_PAD_TAPE = { u0: 0.396, u1: 0.605, v0: 0, v1: 0.069, alpha: 0.8 };
// Rosa entfernen: Pixel, bei denen (R + B) / 2 deutlich ueber G liegt, bekommen G = Mittel von R und B (neutral) und B unter G
// gedrueckt (warm-beige wie das gelbliche Band unten). Gilt nur im Klebeband-Rechteck (Papier hat dort kein Rosa).
export function todoPadTape(rgba, w, h, { when = "pre", box = TODO_PAD_TAPE } = {}) {
  const x0 = Math.floor(box.u0 * w), x1 = Math.ceil(box.u1 * w), y0 = Math.floor(box.v0 * h), y1 = Math.ceil(box.v1 * h);
  let n = 0;
  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      const o = (y * w + x) * 4;
      if (when === "post" && rgba[o + 3] === 0) continue;
      const r = rgba[o], g = rgba[o + 1], b = rgba[o + 2];
      if (when === "pre" && g < 140) continue; // Magenta-Grund und Mischpixel am Rand lassen: die Freistellung rechnet sie zurueck
      const pink = (r + b) / 2 - g;
      if (pink < 4) continue;
      const k = Math.min(1, pink / 14); // sanft einblenden, damit keine Kante im Band entsteht
      const gn = g + ((r + b) / 2 - g) * k;
      rgba[o + 1] = Math.round(gn);
      rgba[o + 2] = Math.round(Math.min(b, gn - 28 * k + (1 - k) * (b - gn)));
      n++;
    }
  }
  return n;
}
// Schattensaum: halbdurchsichtige Pixel (Schlagschatten auf Magenta) auf dunkles Braun setzen, sonst bleibt ein violetter Rand
// Gedruckte Querlinien entfernen: Zeilen, die im Linienbereich (x 0,23..0,82) deutlich dunkler sind als ihre Nachbarn (+-4), sind
// Linie; jede Linie wird spaltenweise aus den Zeilen knapp darueber/darunter ueberblendet (nur Pixel, die dunkler sind als die
// Ueberblendung, also die Tinte; Flecken und Pergament bleiben). Rand (x < 0,06 / > 0,94) und Alpha bleiben unberuehrt.
export function unruleSheet(rgba, w, h, { minDark = 15 } = {}) {
  const lum = (x, y) => { const o = (y * w + x) * 4; return (rgba[o] + rgba[o + 1] + rgba[o + 2]) / 3; };
  const x0 = Math.round(w * 0.23), x1 = Math.round(w * 0.82);
  const prof = new Float64Array(h);
  for (let y = 0; y < h; y++) {
    let sum = 0;
    for (let x = x0; x < x1; x++) sum += lum(x, y);
    prof[y] = sum / (x1 - x0);
  }
  const isLine = new Uint8Array(h);
  for (let y = 4; y < h - 4; y++) {
    if ((prof[y - 4] + prof[y + 4]) / 2 - prof[y] > minDark && prof[y] > 90) isLine[y] = 1;
  }
  const bands = [];
  for (let y = 0; y < h; y++) {
    if (!isLine[y]) continue;
    let e = y;
    while (e + 1 < h && isLine[e + 1]) e++;
    bands.push([Math.max(0, y - 1), Math.min(h - 1, e + 1)]);
    y = e;
  }
  const xa = Math.round(w * 0.06), xb = Math.round(w * 0.94);
  for (const [a, b] of bands) {
    const above = Math.max(0, a - 2), below = Math.min(h - 1, b + 2);
    for (let x = xa; x < xb; x++) {
      const oa = (above * w + x) * 4, ob = (below * w + x) * 4;
      if (rgba[oa + 3] < 250 || rgba[ob + 3] < 250) continue;
      for (let y = a; y <= b; y++) {
        const t = (y - above) / (below - above);
        const o = (y * w + x) * 4;
        const r = rgba[oa] + (rgba[ob] - rgba[oa]) * t, g = rgba[oa + 1] + (rgba[ob + 1] - rgba[oa + 1]) * t, bl = rgba[oa + 2] + (rgba[ob + 2] - rgba[oa + 2]) * t;
        if ((rgba[o] + rgba[o + 1] + rgba[o + 2]) / 3 < (r + g + bl) / 3 - 4) {
          rgba[o] = Math.round(r); rgba[o + 1] = Math.round(g); rgba[o + 2] = Math.round(bl);
        }
      }
    }
  }
  return bands.length;
}
const TODO_PAD_KEY = (rgba, w, h) => {
  todoPadTape(rgba, w, h, { when: "pre" });
  keyMagenta(rgba, w, h);
  todoPadTape(rgba, w, h, { when: "post" });
  for (let i = 0; i < w * h; i++) {
    const o = i * 4;
    if (rgba[o + 3] > 0 && rgba[o + 3] < 200) { rgba[o] = 38; rgba[o + 1] = 26; rgba[o + 2] = 16; }
    // rosa Saum: Randpixel mit weniger als ~16 % Magenta-Anteil lassen die Freistellung deckend stehen (Papier hat sonst keinen Rosastich)
    else if (rgba[o + 3] > 0 && (rgba[o] + rgba[o + 2]) / 2 - rgba[o + 1] > 8) { rgba[o] = 92; rgba[o + 1] = 68; rgba[o + 2] = 48; }
  }
  // Klebeband halbdurchsichtig, aber nur dort, wo es ueber dem Nichts steht (oberhalb der Papier-Oberkante, linear zwischen den
  // Papierkanten links und rechts vom Band); auf dem Papier bliebe ein sichtbares Rechteck. Erst nach dem Schattensaum, sonst faerbte
  // dessen Schwelle die Bandkante dunkel.
  const T = TODO_PAD_TAPE;
  const bx0 = Math.floor(T.u0 * w), bx1 = Math.ceil(T.u1 * w);
  const topOf = (x) => { let y = 0; while (y < h - 1 && rgba[(y * w + x) * 4 + 3] < 128) y++; return y; };
  const eL = topOf(Math.max(0, bx0 - 4)), eR = topOf(Math.min(w - 1, bx1 + 4));
  for (let x = bx0; x < bx1; x++) {
    const edge = eL + ((eR - eL) * (x - bx0)) / Math.max(1, bx1 - bx0);
    for (let y = 0; y < Math.min(h, Math.floor(edge) - 1); y++) {
      const o = (y * w + x) * 4;
      rgba[o + 3] = Math.round(rgba[o + 3] * T.alpha);
    }
  }
  return rgba;
};
// Zettel am Feuer (Lagerfeuer E3, journal/FireNotes.lua): fuenf Formen angesengter Papierfetzen (Gemini, art/journal/fire_note_v1..v5.jpg,
// freigegeben 30.10.2026; je 2752 x 1536, Magenta-Grund, Glut-Schimmer an den Brandkanten). Alle fuenf haben dieselbe Lage
// (Papier etwa x 193..2594, y 152..1394 im Quellbild): ein gemeinsamer Zuschnitt 2600 x 1300 (genau 2 : 1) -> Media/FireNote<i>.tga
// 512 x 256. Freistellung keyMagenta: die orange Glut ist kein Magenta (min(R, B) - G <= 0) und bleibt deckend, ihr Schimmer auf dem
// Grund wird halbdurchsichtig mit zurueckgerechneter Farbe; Asche-Kruemel bleiben stehen.
// Textbereich je Form: `node scripts/render-media.mjs --fire-areas` liest die fertigen TGAs und sucht das groesste Rechteck auf heilem,
// hellem Papier (deckend, nicht verkohlt, FIRE_AREA.margin px Abstand zu Rand, Loch und Brandfleck) -> journal/FireNoteAreas.lua
// (Anteile 0..1 der Textur, von links oben) und die Vorschau tests/screens/fire-notes.png (jede Form normal und gespiegelt, Bereich
// rot umrandet). Das Spiel spiegelt den Bereich mit der Textur (x' = 1 - x - w). Test: tests/lagerfeuer-zettel.test.mjs.
export const FIRE_NOTE_CROP = { x: 76, y: 108, w: 2600, h: 1300, srcW: 2752, srcH: 1536 };
export const FIRE_NOTE_IDS = [1, 2, 3, 4, 5];
export const FIRE_NOTE_SIZE = { w: 512, h: 256 };
// alpha: Mindestdeckung; paper: Mindest-Helligkeit (Summe R+G+B, Mittel ueber blur px) = kein Russ/Brand; margin: Abstand in px
export const FIRE_AREA = { alpha: 250, paper: 560, blur: 3, margin: 12 };
// Freistellen; der Glutschimmer auf dem Grund bleibt nach der Rueckrechnung leicht rosa (JPEG-Mischung): halbdurchsichtige Pixel mit
// Blau ueber Gruen werden warm-orange (Blau unter Gruen gedrueckt), damit der Schimmer auf hellem wie dunklem Grund nach Glut aussieht.
export function fireNoteKey(rgba, w, h) {
  keyMagenta(rgba, w, h);
  for (let i = 0; i < w * h; i++) {
    const o = i * 4;
    if (rgba[o + 3] === 0 || rgba[o + 3] >= 240) continue;
    if (rgba[o + 2] > rgba[o + 1]) rgba[o + 2] = Math.round(rgba[o + 1] * 0.55);
  }
  // 2 px Rand ganz durchsichtig (Asche-Kruemel am Zuschnitt, JPEG-Reste): sonst zieht die Textur-Klemmung Streifen
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (x < 2 || y < 2 || x >= w - 2 || y >= h - 2) rgba[(y * w + x) * 4 + 3] = 0;
    }
  }
  return rgba;
}
const fireNoteTexture = (i) => ({
  name: `FireNote${i}`, w: FIRE_NOTE_SIZE.w, h: FIRE_NOTE_SIZE.h,
  html: () => ART(`fire_note_v${i}.jpg`, FIRE_NOTE_CROP, FIRE_NOTE_SIZE.w, FIRE_NOTE_SIZE.h),
  post: fireNoteKey,
  source: `art/journal/fire_note_v${i}.jpg`,
});

/** TGA Typ 2, 32 bit lesen (Ursprung unten oder oben links) -> { w, h, rgba } von oben links */
export function decodeTga(buf) {
  const r = inspectTga(buf);
  if (!r.ok) throw new Error(`TGA: ${r.reason}`);
  const { w, h } = r;
  const top = (buf[17] & 0x20) !== 0;
  const off = 18 + buf[0];
  const rgba = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) {
    const sy = top ? y : h - 1 - y;
    for (let x = 0; x < w; x++) {
      const s = off + (sy * w + x) * 4;
      const d = (y * w + x) * 4;
      rgba[d] = buf[s + 2];
      rgba[d + 1] = buf[s + 1];
      rgba[d + 2] = buf[s];
      rgba[d + 3] = buf[s + 3];
    }
  }
  return { w, h, rgba };
}

/** Pixelzeilen spiegeln (links <-> rechts) */
export function mirrorX(rgba, w, h) {
  const out = new Uint8Array(rgba.length);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const s = (y * w + x) * 4;
      const d = (y * w + (w - 1 - x)) * 4;
      for (let k = 0; k < 4; k++) out[d + k] = rgba[s + k];
    }
  }
  return out;
}

/** Papiermaske: deckend und hell (Summe R+G+B ueber ein Fenster von blur px gemittelt, durchsichtige Pixel zaehlen 0) */
export function fireNoteMask(rgba, w, h, A = FIRE_AREA) {
  const ok = new Uint8Array(w * h);
  const sum = new Float64Array(w * h);
  for (let i = 0; i < w * h; i++) sum[i] = rgba[i * 4 + 3] >= A.alpha ? rgba[i * 4] + rgba[i * 4 + 1] + rgba[i * 4 + 2] : 0;
  const r = A.blur;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (rgba[(y * w + x) * 4 + 3] < A.alpha) continue;
      let s = 0;
      let n = 0;
      for (let dy = -r; dy <= r; dy++) {
        const yy = y + dy;
        if (yy < 0 || yy >= h) continue;
        for (let dx = -r; dx <= r; dx++) {
          const xx = x + dx;
          if (xx < 0 || xx >= w) continue;
          s += sum[yy * w + xx];
          n++;
        }
      }
      if (s / n >= A.paper) ok[y * w + x] = 1;
    }
  }
  return ok;
}

/** Maske um m px einziehen (ein Pixel bleibt, wenn waagerecht und senkrecht je m px Papier daneben liegen; zweistufig = Quadrat) */
export function erodeMask(mask, w, h, m) {
  const rowOk = new Uint8Array(w * h);
  for (let y = 0; y < h; y++) {
    let run = 0;
    const left = new Int32Array(w);
    for (let x = 0; x < w; x++) { run = mask[y * w + x] ? run + 1 : 0; left[x] = run; }
    run = 0;
    for (let x = w - 1; x >= 0; x--) {
      run = mask[y * w + x] ? run + 1 : 0;
      if (left[x] > m && run > m) rowOk[y * w + x] = 1;
    }
  }
  const out = new Uint8Array(w * h);
  for (let x = 0; x < w; x++) {
    let run = 0;
    const up = new Int32Array(h);
    for (let y = 0; y < h; y++) { run = rowOk[y * w + x] ? run + 1 : 0; up[y] = run; }
    run = 0;
    for (let y = h - 1; y >= 0; y--) {
      run = rowOk[y * w + x] ? run + 1 : 0;
      if (up[y] > m && run > m) out[y * w + x] = 1;
    }
  }
  return out;
}

/** Groesstes achsenparalleles Rechteck aus lauter 1 (Histogramm-Verfahren) -> { x, y, w, h } in Pixeln */
export function largestRect(mask, w, h) {
  const height = new Int32Array(w);
  let best = { x: 0, y: 0, w: 0, h: 0, area: 0 };
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) height[x] = mask[y * w + x] ? height[x] + 1 : 0;
    const stack = [];
    for (let x = 0; x <= w; x++) {
      const cur = x < w ? height[x] : 0;
      let start = x;
      while (stack.length && stack[stack.length - 1][1] >= cur) {
        const [sx, sh] = stack.pop();
        const area = sh * (x - sx);
        if (area > best.area) best = { x: sx, y: y - sh + 1, w: x - sx, h: sh, area };
        start = sx;
      }
      stack.push([start, cur]);
    }
  }
  return { x: best.x, y: best.y, w: best.w, h: best.h };
}

/** Textbereich einer Zettel-Textur -> { x, y, w, h } als Anteile 0..1 (4 Stellen, nach innen gerundet) */
export function fireNoteArea(rgba, w, h, A = FIRE_AREA) {
  const r = largestRect(erodeMask(fireNoteMask(rgba, w, h, A), w, h, A.margin), w, h);
  const ceil4 = (v) => Math.ceil(v * 10000) / 10000;
  const floor4 = (v) => Math.floor(v * 10000) / 10000;
  const x = ceil4(r.x / w);
  const y = ceil4(r.y / h);
  return { x, y, w: Number((floor4((r.x + r.w) / w) - x).toFixed(4)), h: Number((floor4((r.y + r.h) / h) - y).toFixed(4)) };
}

export const FIRE_AREAS_LUA = path.join(ROOT, "addon", "InkAndEmbers", "journal", "FireNoteAreas.lua");

export function fireAreasLua(areas) {
  const f = (v) => Number(v.toFixed(4)).toString();
  const rows = areas.map((a, i) => `  { x = ${f(a.x)}, y = ${f(a.y)}, w = ${f(a.w)}, h = ${f(a.h)} }, -- FireNote${i + 1}`).join("\n");
  return `-- GENERATED by scripts/render-media.mjs --fire-areas, do not edit by hand.
-- Text area per note shape (Media/FireNote<i>.tga, ${FIRE_NOTE_SIZE.w} x ${FIRE_NOTE_SIZE.h}) as 0..1 shares of the texture, x/y from the top left;
-- mirrored notes mirror the area too (x' = 1 - x - w). Test: tests/lagerfeuer-zettel.test.mjs.
local _, ns = ...
ns.Journal = ns.Journal or {}
ns.Journal.FIRE_NOTE_AREAS = {
${rows}
}
`;
}

/** Vorschau: jede Form normal und gespiegelt auf dunklem und hellem Grund, Textbereich rot umrandet */
export function fireNotesPreview(textures) {
  const tw = FIRE_NOTE_SIZE.w;
  const th = FIRE_NOTE_SIZE.h;
  const gap = 8;
  const W = 4 * tw + 5 * gap;
  const H = textures.length * (th + gap) + gap;
  const out = new Uint8Array(W * H * 4);
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const o = (y * W + x) * 4;
      const light = x >= 2 * tw + 2 * gap + gap / 2;
      out[o] = light ? 236 : 22;
      out[o + 1] = light ? 230 : 24;
      out[o + 2] = light ? 222 : 30;
      out[o + 3] = 255;
    }
  }
  textures.forEach((t, row) => {
    const variants = [[t.rgba, t.area], [mirrorX(t.rgba, tw, th), { ...t.area, x: 1 - t.area.x - t.area.w }]];
    for (let col = 0; col < 4; col++) {
      const [px, a] = variants[col % 2];
      const ox = gap + col * (tw + gap);
      const oy = gap + row * (th + gap);
      for (let y = 0; y < th; y++) {
        for (let x = 0; x < tw; x++) {
          const s = (y * tw + x) * 4;
          const d = ((oy + y) * W + ox + x) * 4;
          const al = px[s + 3] / 255;
          for (let k = 0; k < 3; k++) out[d + k] = Math.round(px[s + k] * al + out[d + k] * (1 - al));
        }
      }
      const rx0 = Math.round(a.x * tw);
      const ry0 = Math.round(a.y * th);
      const rx1 = Math.round((a.x + a.w) * tw) - 1;
      const ry1 = Math.round((a.y + a.h) * th) - 1;
      const red = (x, y) => {
        const d = ((oy + y) * W + ox + x) * 4;
        out[d] = 220;
        out[d + 1] = 20;
        out[d + 2] = 20;
      };
      for (let x = rx0; x <= rx1; x++) { red(x, ry0); red(x, ry1); }
      for (let y = ry0; y <= ry1; y++) { red(rx0, y); red(rx1, y); }
    }
  });
  return encodePng(W, H, out);
}

/** Textbereiche aus den fertigen TGAs: schreibt journal/FireNoteAreas.lua und tests/screens/fire-notes.png */
export function runFireAreas({ dir = MEDIA_DIR, luaFile = FIRE_AREAS_LUA, screens = path.join(ROOT, "tests", "screens") } = {}) {
  const textures = FIRE_NOTE_IDS.map((i) => {
    const img = decodeTga(readFileSync(path.join(dir, `FireNote${i}.tga`)));
    return { ...img, area: fireNoteArea(img.rgba, img.w, img.h) };
  });
  mkdirSync(screens, { recursive: true });
  writeFileSync(path.join(screens, "fire-notes.png"), fireNotesPreview(textures));
  writeFileSync(luaFile, fireAreasLua(textures.map((t) => t.area)), "utf8");
  textures.forEach((t, i) => console.log(`  FireNote${i + 1}: x ${t.area.x} y ${t.area.y} w ${t.area.w} h ${t.area.h}`));
  console.log(`  -> ${path.relative(ROOT, luaFile)} und tests/screens/fire-notes.png geschrieben`);
  return textures.map((t) => t.area);
}

export const BTN_TOTAL = { file: "btn_gesamtreise.jpg", x: 75, y: 105, w: 2600, h: 1300, srcW: 2752, srcH: 1536 };
// Zuschnitt (28.10.2026, nach Augenmass gemessen): Schwert x 313..1744, y 281..1696 -> quadratisch 1600 um die Mitte (1028, 989)
export const SWORD_ICON = { file: "icon_sword.jpg", x: 228, y: 189, w: 1600, h: 1600, srcW: 2048, srcH: 2048 };
const SWORD_ICON_KEY = (rgba, w, h) => erodeEdge(keyWhite(rgba, w, h, { from: 690, to: 745 }), w, h, 1);
// Ereignis-Symbole der Reise-Karte (Symbolbogen art/journal/map_icons_v2.jpg, 2400 x 1792, 4 x 3 Zellen auf Magenta): Atlas MapIcons
// (Kartenzeichen), MapKill (Kill-Marke) und MapCurrent (Spielerposition, eigene Datei: der Pfeil dreht sich per SetRotation).
// Freistellung und Zuschnitt in scripts/cut-icons.mjs; gerendert wird in voller Quellgroesse.
export const MAP_ICONS = { file: MAP_ICONS_FILE, x: 0, y: 0, w: MAP_ICONS_SRC.w, h: MAP_ICONS_SRC.h, srcW: MAP_ICONS_SRC.w, srcH: MAP_ICONS_SRC.h };
const MAP_ICONS_HTML = () => ART(MAP_ICONS.file, MAP_ICONS, MAP_ICONS.srcW, MAP_ICONS.srcH);
// Kill-Embleme der Kampf-Seite (art/journal/kill_emblems_v2.jpg, 2752 x 1536, vier Embleme auf Magenta): Atlas KillEmblems
// (512 x 512, 2 x 2 Kacheln zu 256 px: Gewoehnlich Bronze-Wolf, Elite Gold-Drache, Rar Silber-Drache, Boss Eisen-Schaedel). Freistellung
// und Zuschnitt in scripts/cut-emblems.mjs; gerendert wird in voller Quellgroesse.
export const KILL_EMBLEMS = { file: EMBLEMS_FILE, x: 0, y: 0, w: EMBLEMS_SRC.w, h: EMBLEMS_SRC.h, srcW: EMBLEMS_SRC.w, srcH: EMBLEMS_SRC.h };
const KILL_EMBLEMS_HTML = () => ART(KILL_EMBLEMS.file, KILL_EMBLEMS, KILL_EMBLEMS.srcW, KILL_EMBLEMS.srcH);
const BTN_TOTAL_KEY = (rgba, w, h) => erodeEdge(keyWhite(rgba, w, h, { from: 690, to: 745 }), w, h, 1);

// Ledereinband (art/journal/leather_open2.jpg, 2528 x 1696, weisser Grund): der aufgeschlagene Einband von innen, zwei
// Buch aus einem Guss (B1c/B1f): Grundbild ist art/journal/book_master_v4.jpg (2752 x 1536, freigegeben): dasselbe Buch
// wie die Stilvorlage book_master_v3, von Gemini neu gemalt mit glatten, leeren Seiten (ohne Eselsohren, Knick, Kritzel; die
// B1e-Retusche entfaellt). Ganzes aufgeschlagenes Buch mit Ledereinband, Metallkappen, Buchblock mit echten Blattkanten
// links/rechts/unten und Falz. Darauf legt das Spiel je Reiter das Seitenpaar (Page_<reiter>_L/_R, SPREAD_CROPS), so dass die
// Blattkanten des Grundbilds rundum zu sehen bleiben. Geminis Bodenschatten liegt ausserhalb der Lederkante (Fenster) und faellt weg.
// Zuschnitt einmal gemessen (29.10.2026, PIL, Helligkeitsprofile): Lederkante links 479, oben 168, rechts 2270, unten 1346;
// linker Blattstapel 524..590, rechter 2164..2222, unterer 1252..1306; Seiten oben 210..214, unten 1250..1254; Falz (dunkelste
// Spalte, in acht Hoehen) senkrecht bei 1375. Lederkante x 479..2270, y 168..1346 (1792 x 1179, Mitte 1375), Zuschnitt seit dem
// Buchrand-Fix BOOK_MARGIN groesser (s. u.). Auf 1024 x 1024 gestaucht (0,542 bzw. 0,803 Texturpixel je Quellpixel; im Spiel liegen
// Rand und Ecken bei 0,42, also immer mindestens ein Texturpixel je Spielpixel).
// Im Spiel in 15 Teile gespannt (Frame.bookPieces, Masse BOOK_SLICE in journal/Theme.lua; Test journal-book.test.mjs):
//   RING   = 72 Quellpixel werden Frame.RIM (30 px) breit -> Massstab s = 0,417 fuer den ganzen Aussenring (Ecken, Kappen):
//            Leder 18..20 px, sichtbare Blattkanten links ca. 11 px, rechts ca. 10 px, unten ca. 13 px
//   CORNER = 160: Ecke samt Metallkappe, unverzerrt (67 px)
//   SPINE  = Falz 836..957 (121 breit, genau um die Falzlinie 1375 = Zuschnittspalte 896,5), fest auf der Buchmitte (Kerbe oben,
//            Spitze unten): so liegt die Falz des Grundbilds genau unter der Teilung des Pergaments
// Die Mitte (leere Seiten des Grundbilds) wird gestreckt, liegt aber fast ganz unter dem Pergament.
// Buchrand (29.10.2026, Befund "hart abgeschnitten, grau/weisse Raender"): der Zuschnitt endete genau an der gemessenen
// Lederkante und schnitt so die abgerundeten Ecken, die ueberstehenden Metallkappen (bis x 473, y 1360) und die Unterkante
// (Leder bis y 1353) gerade ab; keyWhite (ab Farbsumme 700) liess Geminis grauen Bodenschatten (Summe 369..700) deckend als
// hellen Saum stehen. Jetzt: Zuschnitt BOOK_MARGIN Quellpixel ausserhalb der Lederkante auf allen Seiten (Falz bleibt mittig),
// Freistellung mit keyNeutralEdge: alles vom Rand aus erreichbare Neutrale (Grau/Weiss, kaum Farbe) ist Hintergrund und wird zu
// reinem Schwarz mit Alpha = Dunkelheit (Geminis Schatten auf Weiss = schwarzer Schatten, ganz weich, ohne hellen Saum).
// Leder und Kappen haben eine dunkle, farbige Aussenlinie, an der die Flutung stoppt. Im Spiel ragt der Rand (BOOK_MARGIN * s =
// 20 px) ueber das Fenster hinaus (Frame.bookPieces), Fenster und Inhaltskoordinaten bleiben gleich.
export const BOOK_FILE = "book_master_v4.jpg";
export const BOOK_MARGIN = 48;
export const BOOK_CROP = { x: 479 - BOOK_MARGIN, y: 168 - BOOK_MARGIN, w: 1792 + 2 * BOOK_MARGIN, h: 1179 + 2 * BOOK_MARGIN, srcW: 2752, srcH: 1536 };
// ring/corner zaehlen ab der Lederkante, spine0/spine1 in Spalten des Zuschnitts (mit Rand)
export const BOOK_SLICE_SRC = { ring: 72, corner: 160, spine0: 836 + BOOK_MARGIN, spine1: 957 + BOOK_MARGIN, margin: BOOK_MARGIN };
// neutral: Buntheit (max - min) hoechstens chroma und Farbsumme ueber min; shadow = Staerke des Schattens; fade = Pixel am
// Texturrand, auf denen der Schatten sicher auf 0 auslaeuft; rim = Helligkeit des Buchpixel-Rings an der Kontur
export const BOOK_EDGE_KEY = { chroma: 16, min: 330, shadow: 0.85, fade: 6, rim: 0.6 };
/**
 * Hintergrund mit Schatten freistellen: vom Bildrand aus zusammenhaengend erreichbare neutrale Pixel (grau/weiss) werden
 * reines Schwarz mit Alpha = shadow * (1 - Helligkeit); so wird weisser Grund durchsichtig und grauer Schatten ein weicher
 * dunkler Schatten, ohne hellen Saum. Farbiges oder Dunkles (Leder, Kappen-Umriss) stoppt die Flutung und bleibt deckend.
 */
export function keyNeutralEdge(rgba, w, h, { chroma, min, shadow, fade, rim, grow = null } = BOOK_EDGE_KEY) {
  const bg = (i) => {
    const o = i * 4;
    const r = rgba[o], g = rgba[o + 1], b = rgba[o + 2];
    return r + g + b > min && Math.max(r, g, b) - Math.min(r, g, b) <= chroma;
  };
  const seen = new Uint8Array(w * h);
  const stack = [];
  const push = (i) => {
    if (!seen[i] && bg(i)) {
      seen[i] = 1;
      stack.push(i);
    }
  };
  for (let x = 0; x < w; x++) {
    push(x);
    push((h - 1) * w + x);
  }
  for (let y = 0; y < h; y++) {
    push(y * w);
    push(y * w + w - 1);
  }
  while (stack.length) {
    const i = stack.pop();
    const x = i % w;
    if (x > 0) push(i - 1);
    if (x < w - 1) push(i + 1);
    if (i >= w) push(i - w);
    if (i < (h - 1) * w) push(i + w);
  }
  // grow: danach noch steps Ringe weit in angrenzende, etwas buntere Pixel (Buntheit <= grow.chroma) wachsen: warmer Schatten
  // direkt an der Kante (Mischung aus Grund und farbiger Kante), ohne die buntere Flaeche selbst anzufressen; nur Pixel dunkler
  // als grow.maxSum (Schatten unter Papierkante/Band), so bleiben blasse helle Papierecken stehen
  for (let step = 0; grow && step < grow.steps; step++) {
    const add = [];
    for (let i = 0; i < w * h; i++) {
      if (seen[i]) continue;
      const x = i % w;
      if (!((x > 0 && seen[i - 1]) || (x < w - 1 && seen[i + 1]) || (i >= w && seen[i - w]) || (i < (h - 1) * w && seen[i + w]))) continue;
      const o = i * 4;
      const r = rgba[o], g = rgba[o + 1], b = rgba[o + 2];
      if (r + g + b > min && r + g + b < (grow.maxSum ?? 766) && Math.max(r, g, b) - Math.min(r, g, b) <= grow.chroma) add.push(i);
    }
    for (const i of add) seen[i] = 1;
  }
  // Randpixel des Buchs sind Mischpixel aus Kante und hellem Grund: der aeusserste Ring wird wie Hintergrund behandelt (Schwarz
  // mit Alpha = Dunkelheit, also eine dunkle weiche Kontur), der naechste abgedunkelt (rim) -> kein heller Saum auf dunklem Grund
  const nextTo = (i, m) => {
    const x = i % w;
    return (x > 0 && seen[i - 1] === m) || (x < w - 1 && seen[i + 1] === m) || (i >= w && seen[i - w] === m) || (i < (h - 1) * w && seen[i + w] === m);
  };
  for (let i = 0; i < w * h; i++) if (!seen[i] && nextTo(i, 1)) seen[i] = 2;
  for (let i = 0; i < w * h; i++) {
    if (seen[i] || !nextTo(i, 2)) continue;
    for (let k = 0; k < 3; k++) rgba[i * 4 + k] = Math.round(rgba[i * 4 + k] * rim);
  }
  for (let i = 0; i < w * h; i++) {
    if (!seen[i]) continue;
    const o = i * 4;
    const x = i % w;
    const y = (i - x) / w;
    const edge = Math.min(1, Math.min(x, y, w - 1 - x, h - 1 - y) / fade);
    const dark = 1 - (rgba[o] + rgba[o + 1] + rgba[o + 2]) / 765;
    rgba[o] = rgba[o + 1] = rgba[o + 2] = 0;
    rgba[o + 3] = Math.round(255 * Math.max(0, Math.min(1, dark * shadow * edge)));
  }
  return rgba;
}
const BOOK_KEY = (rgba, w, h) => keyNeutralEdge(rgba, w, h);

// Lesezeichen (art/journal/bookmarks.jpg, 2752 x 1536, Gemini, weisser Grund): sechs kurze Stoffbaender untereinander, links
// gerade abgeschnitten, rechts Schwalbenschwanz, das Wort in Gold eingestickt. Atlas Media/Bookmarks.tga (512 x 1024): sechs
// Zellen zu 512 x 96 untereinander (Zelle i = i-ter Reiter von Theme.TABS, Rest leer). Zuschnitt je Band einmal gemessen
// (28.10.2026, Suchlauf im Browser: Farbsumme < 690, mindestens 7 Pixel je Zeile): Baender x 873..1881, Hoehe 196..202,
// Mitten y 192,5 / 427,5 / 664,5 / 902,5 / 1137 / 1371; Abstand der Baender 35 px; Wort beginnt fruehestens bei x 1101 (Momente).
// Im Spiel steckt das linke Ende unter der Pergamentkante der rechten Seite und das Band laeuft ueber den Lederrand (30 px) nach
// aussen: das Band ist also links laenger als die Vorlage (R4: das Wort darf schon auf dem Leder beginnen, Frame.TAB.under = RIM + 44). Die Zelle (1256 x 235,5 Quellpixel,
// Zellenverhaeltnis 512 : 96) zeigt deshalb: links (Zellenspalte 0..410) einen glatten Bandabschnitt aus Quellspalte 940..1040,
// mehrfach nebeneinander gesetzt (verdeckt unter Seite und Leder, die Naht der Stichreihe faellt kaum auf), ab Zellenspalte 410
// das Original ab Quellspalte 1040 (Zellenspalte = Quellspalte - 630), also Wort ab Zellenspalte 471 und Schwalbenschwanz bis 1255.
// Freistellung vom Zellenrand aus (keyWhite, auch die Kerbe des Schwalbenschwanzes), danach Kante 1 Texturpixel eingezogen (links nicht).
// N1: Zelle 7 "Notizen" gibt es im Gemini-Bild nicht. Sie wird aus dem Reise-Band gebaut (BOOKMARK_SYNTH): der glatte Abschnitt
// (tile) bis vor das Bandende, dann das Original ab Quellspalte tail (hinter dem Wort, mit Schwalbenschwanz); darauf das Wort in
// Gold (Blackletter "Old English Text MT", Verlauf und Praegeschatten wie die Stickerei). Danach faerbt BOOKMARKS_KEY die Zelle um:
// alles ausser dem Gold (Farbton 30..65 Grad, gesaettigt) bekommt den Farbton hue (Petrol), Helligkeit und Saettigung skaliert.
export const BOOKMARK_IDS = ["reise", "chronik", "kampf", "quests", "schaetze", "momente", "notizen"];
export const BOOKMARK_MID_Y = [192.5, 427.5, 664.5, 902.5, 1137, 1371];
export const BOOKMARK_SYNTH = {
  notizen: { from: 0, word: "Notizen", tail: 1560, tile: [925, 1215], center: 300, size: 58, hue: 190, sat: 0.78, val: 0.56,
    font: "'Old English Text MT', 'UnifrakturMaguntia', 'Times New Roman', serif" },
};
/** Farbton (Grad) einer RGB-Farbe 0..255 -> [h, s, v] */
export function rgbToHsv(r, g, b) {
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn;
  let h = 0;
  if (d > 0) {
    if (mx === r) h = 60 * (((g - b) / d) % 6);
    else if (mx === g) h = 60 * ((b - r) / d + 2);
    else h = 60 * ((r - g) / d + 4);
  }
  if (h < 0) h += 360;
  return [h, mx === 0 ? 0 : d / mx, mx / 255];
}
export function hsvToRgb(h, s, v) {
  const c = v * s, x = c * (1 - Math.abs(((h / 60) % 2) - 1)), m = v - c;
  const [r, g, b] = h < 60 ? [c, x, 0] : h < 120 ? [x, c, 0] : h < 180 ? [0, c, x] : h < 240 ? [0, x, c] : h < 300 ? [x, 0, c] : [c, 0, x];
  return [Math.round((r + m) * 255), Math.round((g + m) * 255), Math.round((b + m) * 255)];
}
/** Gold der Stickerei (bleibt beim Umfaerben) */
export const isBookmarkGold = (h, s, v) => h >= 30 && h <= 65 && s >= 0.3 && v >= 0.35;
/** Zelle cell (RGBA, w Pixel breit) umfaerben: alles ausser Gold auf den Farbton syn.hue */
export function recolorBookmark(rgba, w, h, syn) {
  for (let i = 0; i < w * h * 4; i += 4) {
    if (rgba[i + 3] === 0) continue;
    const [hh, ss, vv] = rgbToHsv(rgba[i], rgba[i + 1], rgba[i + 2]);
    if (isBookmarkGold(hh, ss, vv)) continue;
    const [r, g, b] = hsvToRgb(syn.hue, Math.min(1, ss * syn.sat), Math.min(1, vv * syn.val));
    rgba[i] = r; rgba[i + 1] = g; rgba[i + 2] = b;
  }
  return rgba;
}
export const BOOKMARK_ATLAS = { w: 512, h: 1024, cellW: 512, cellH: 96 };
export const BOOKMARK_CROP = { file: "bookmarks.jpg", w: 1256, h: (1256 * 96) / 512, offset: 630, tile: [940, 1040], srcW: 2752, srcH: 1536 };
const BOOKMARKS_HTML = () => {
  const a = BOOKMARK_ATLAS;
  const c = BOOKMARK_CROP;
  const z = a.cellW / c.w;
  const src = artUrl(c.file);
  const bg = (srcX, y0) => `background:#fff url(${src}) ${-srcX * z}px ${-y0 * z}px / ${c.srcW * z}px ${c.srcH * z}px no-repeat`;
  const cells = BOOKMARK_IDS.map((id, i) => {
    const syn = BOOKMARK_SYNTH[id];
    if (syn) return synthCell(i, syn, z, bg);
    const y0 = Math.round(BOOKMARK_MID_Y[i] - c.h / 2);
    const [t0, t1] = c.tile;
    const edge = t1 - c.offset; // Zellenspalte, ab der das Original steht
    const tiles = [];
    for (let k = 1; edge - k * (t1 - t0) + (t1 - t0) > 0; k++) {
      tiles.push(`<div style="position:absolute;left:${(edge - k * (t1 - t0)) * z}px;top:0;width:${(t1 - t0) * z}px;height:${a.cellH}px;${bg(t0, y0)}"></div>`);
    }
    const orig = `<div style="position:absolute;left:${edge * z}px;top:0;width:${(c.w - edge) * z}px;height:${a.cellH}px;${bg(t1, y0)}"></div>`;
    return `<div style="position:absolute;left:0;top:${i * a.cellH}px;width:${a.cellW}px;height:${a.cellH}px;overflow:hidden;background:#fff">${tiles.join("")}${orig}</div>`;
  });
  return page(a.w, a.h, `<div style="position:absolute;inset:0;background:#fff"></div>` + cells.join(""));
};
// Zelle i aus dem Band syn.from: glatter Abschnitt bis zur Quellspalte syn.tail, ab dort das Original (ohne Wort), darauf syn.word
function synthCell(i, syn, z, bg) {
  const a = BOOKMARK_ATLAS;
  const c = BOOKMARK_CROP;
  const y0 = Math.round(BOOKMARK_MID_Y[syn.from] - c.h / 2);
  const [t0, t1] = syn.tile || c.tile;
  const edge = syn.tail - c.offset;
  const tiles = [];
  for (let k = 1; edge - k * (t1 - t0) + (t1 - t0) > 0; k++) {
    tiles.push(`<div style="position:absolute;left:${(edge - k * (t1 - t0)) * z}px;top:0;width:${(t1 - t0) * z}px;height:${a.cellH}px;${bg(t0, y0)}"></div>`);
  }
  const tail = `<div style="position:absolute;left:${edge * z}px;top:0;width:${(c.w - edge) * z}px;height:${a.cellH}px;${bg(syn.tail, y0)}"></div>`;
  const word = `<div style="position:absolute;left:${syn.center - 160}px;top:0;width:320px;height:${a.cellH}px;display:flex;align-items:center;justify-content:center"><span style="font-family:${syn.font};font-size:${syn.size}px;line-height:1;background:linear-gradient(180deg,#f6dc8c 0%,#d9a849 45%,#a8761f 100%);-webkit-background-clip:text;background-clip:text;color:transparent;filter:drop-shadow(1px 2px 0 rgba(40,20,5,0.75)) drop-shadow(0 0 1px rgba(60,35,10,0.6));padding-top:4px">${syn.word}</span></div>`;
  return `<div style="position:absolute;left:0;top:${i * a.cellH}px;width:${a.cellW}px;height:${a.cellH}px;overflow:hidden;background:#fff">${tiles.join("")}${tail}${word}</div>`;
}
// Weiss freistellen, Zelle fuer Zelle (Flood-Fill vom Zellenrand aus), dann die Kante einziehen; unter den sechs Zellen bleibt alles leer
const BOOKMARKS_KEY = (rgba, w, h) => {
  const a = BOOKMARK_ATLAS;
  for (let i = 0; i < BOOKMARK_IDS.length; i++) {
    const cell = new Uint8Array(a.cellW * a.cellH * 4);
    for (let y = 0; y < a.cellH; y++) cell.set(rgba.subarray(((i * a.cellH + y) * w) * 4, ((i * a.cellH + y) * w + a.cellW) * 4), y * a.cellW * 4);
    keyWhite(cell, a.cellW, a.cellH, { from: 706, to: 748 });
    const syn = BOOKMARK_SYNTH[BOOKMARK_IDS[i]];
    if (syn) recolorBookmark(cell, a.cellW, a.cellH, syn);
    for (let y = 0; y < a.cellH; y++) rgba.set(cell.subarray(y * a.cellW * 4, (y + 1) * a.cellW * 4), ((i * a.cellH + y) * w) * 4);
  }
  for (let y = BOOKMARK_IDS.length * a.cellH; y < h; y++) for (let x = 0; x < w; x++) rgba[(y * w + x) * 4 + 3] = 0;
  return erodeEdge(rgba, w, h, 1, { keep: "left" });
};

// Lesezeichen V4c "Forever-Bronze" (Hauptreiter rechts am Buch; die Unter-Lesezeichen unten bleiben auf Media/Bookmarks.tga):
// art/journal/bookmarks_bronze.jpg (2400 x 1792, Gemini, Magenta-Grund): sieben schlanke dunkle Lederlaschen untereinander, je mit
// farbiger Naht und rechts einer Bronzekappe mit Muenze und Symbol, ohne Schrift (die Beschriftung setzt journal/Frame.lua in Friz).
// Gemessen 29.10.2026 (PIL, Zeilen/Spalten mit Nicht-Magenta, min(R, B) - G < 120): Laschen y 34..261 / 285..511 / 535..761 /
// 783..1009 / 1030..1255 / 1280..1507 / 1530..1757 (Hoehe 226..228 inkl. Kappe, Lederband 205), links ab x 114, rechte Kappenkante
// x 2235 / 2235 / 2234 / 2234 / 2232 / 2225 / 2221; Kappe (linke Plattenkante bis rechts) 257..269 breit.
// Zuschnitt je Lasche: Hoehe 236 um die Mitte der Lasche, rechts 4 px hinter der Kappe, Breite = 236 * cellW / cellH (= 1110,6, also
// nur das rechte Ende; die linke Kante ist gerade und liegt im Spiel unter der Seite). Atlas Media/BookmarksBronze.tga 512 x 1024:
// Zellen 480 x 102 untereinander (Zelle i = BOOKMARK_IDS[i], Seitenverhaeltnis 80 : 17 = Frame.TAB.w : h = 120 : 25,5; rund 4fach
// ueberabgetastet bei Skalierung 1), Rest durchsichtig. Magenta per keyMagenta freigestellt.
export const TAB_BAND_ATLAS = { w: 512, h: 1024, cellW: 480, cellH: 102 };
export const TAB_BAND_CROP = {
  file: "bookmarks_bronze.jpg", srcW: 2400, srcH: 1792, h: 236, margin: 4, cap: 272,
  rows: [[34, 261, 2235], [285, 511, 2235], [535, 761, 2234], [783, 1009, 2234], [1030, 1255, 2232], [1280, 1507, 2225], [1530, 1757, 2221]],
};
/** Zuschnitt (Quellpixel) der Lasche i -> { x, y, w, h } */
export function tabBandCrop(i) {
  const c = TAB_BAND_CROP, a = TAB_BAND_ATLAS;
  const [y0, y1, right] = c.rows[i];
  const w = (c.h * a.cellW) / a.cellH;
  return { x: right + c.margin - w, y: (y0 + y1) / 2 - c.h / 2, w, h: c.h };
}
/** linke Kante der Kappe als Anteil der Zellenbreite (0..1), fuer die Beschriftung links davon (Frame.TAB.capU) */
export const tabBandCapU = () => 1 - (TAB_BAND_CROP.cap + TAB_BAND_CROP.margin) / tabBandCrop(0).w;
const TAB_BAND_HTML = () => {
  const a = TAB_BAND_ATLAS, c = TAB_BAND_CROP;
  const src = artUrl(c.file);
  const cells = BOOKMARK_IDS.map((id, i) => {
    const r = tabBandCrop(i);
    const z = a.cellH / r.h;
    return `<div style="position:absolute;left:0;top:${i * a.cellH}px;width:${a.cellW}px;height:${a.cellH}px;overflow:hidden;background:#f0f url(${src}) ${-r.x * z}px ${-r.y * z}px / ${c.srcW * z}px ${c.srcH * z}px no-repeat"></div>`;
  });
  return page(a.w, a.h, `<div style="position:absolute;inset:0;background:#f0f"></div>` + cells.join(""));
};
const TAB_BAND_KEY = (rgba, w, h) => {
  const a = TAB_BAND_ATLAS;
  keyMagenta(rgba, w, h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    if (x < a.cellW && y < BOOKMARK_IDS.length * a.cellH) continue;
    rgba[(y * w + x) * 4 + 3] = 0;
  }
  return rgba;
};

// Kartenzeichen: 4 x 4 Zellen zu 64 px, Reihenfolge = Theme.ATLAS (journal/Theme.lua)
const INK = "#2b2118";
const cell = (i, inner, vb = 30) => {
  const x = (i % 4) * 64;
  const y = Math.floor(i / 4) * 64;
  return `<svg x="${x}" y="${y}" width="64" height="64" viewBox="${-vb / 2} ${-vb / 2} ${vb} ${vb}">${inner}</svg>`;
};
const STAR = "M0,-10 L3,-3 L10,-3 L4,2 L6,10 L0,5 L-6,10 L-4,2 L-10,-3 L-3,-3 Z";
const SKULL = `<path d="M-8,-2 a8,8 0 1 1 16,0 v4 h-3 v4 h-10 v-4 h-3 z" fill="#f4ebd6" stroke="${INK}" stroke-width="1.3"/><circle cx="-3" cy="-1" r="2" fill="${INK}"/><circle cx="3" cy="-1" r="2" fill="${INK}"/>`;
const MARKERS_HTML = () =>
  page(
    256,
    256,
    `<svg width="256" height="256" style="position:absolute;left:0;top:0">
${cell(0, `<circle r="13" fill="#f4ebd6" stroke="${INK}" stroke-width="1.6"/>`)}
${cell(1, `<circle r="13.5" fill="#c9a14a" stroke="${INK}" stroke-width="1.8"/><circle r="10.5" fill="none" stroke="rgba(43,33,24,0.35)" stroke-width="0.8"/>`)}
${cell(2, `<g transform="translate(0 1) scale(1.2)">${SKULL}</g>`)}
${cell(3, `<path d="${STAR}" transform="scale(1.25)" fill="#7a4a9a" stroke="${INK}" stroke-width="0.9"/>`)}
${cell(4, `<path d="${STAR}" transform="scale(1.25)" fill="#a0702c" stroke="${INK}" stroke-width="0.9"/>`)}
${cell(5, `<circle r="13" fill="#9b2c1f" stroke="${INK}" stroke-width="1.4"/><g transform="translate(0 1) scale(0.95)">${SKULL}</g>`)}
${cell(6, `<g transform="scale(1.3)"><rect x="-8" y="-5" width="16" height="11" rx="2" fill="#f4ebd6" stroke="${INK}" stroke-width="1.1"/><rect x="-3" y="-7.5" width="6" height="3" rx="1" fill="${INK}"/><circle r="3" fill="${INK}"/></g>`)}
${cell(7, `<ellipse rx="10" ry="12.5" fill="#2f4e7a" stroke="${INK}" stroke-width="1.4"/><path d="M-4 -5 L0 -8 L4 -5 M0 -8 V7 M-4 3 L0 7 L4 3" fill="none" stroke="#f4ebd6" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>`)}
${cell(8, `<circle r="12.5" fill="#f4ebd6" stroke="#2f4e7a" stroke-width="1.8"/><path d="M-8 -1 C-4 -6 -1 -3 0 1 C1 -3 4 -6 8 -1 C4 -2 2 1 0 5 C-2 1 -4 -2 -8 -1 Z" fill="#2f4e7a"/>`)}
${cell(9, `<path d="M-9 11 V-2 A9 9 0 0 1 9 -2 V11 Z" fill="#e8dcc0" stroke="#6b5034" stroke-width="1.5" stroke-dasharray="3 2"/><path d="M-4 11 V1 A4 4 0 0 1 4 1 V11 Z" fill="#6b5034"/>`)}
${cell(10, `<circle r="13" fill="#9b2c1f" opacity="0.18"/><circle r="6.5" fill="#f4ebd6" stroke="#9b2c1f" stroke-width="2.6"/>`)}
${cell(11, `<circle r="12" fill="none" stroke="#c9a14a" stroke-width="2.2"/>`)}
${cell(12, `<path d="M-5 -8 L9 0 L-5 8 Z" fill="#ffffff"/>`, 32)}
${cell(13, `<rect x="-7" y="-8" width="5" height="16" rx="1" fill="#ffffff"/><rect x="2" y="-8" width="5" height="16" rx="1" fill="#ffffff"/>`, 32)}
${cell(14, `<circle r="14.5" fill="#ffffff"/>`)}
${cell(15, `<path d="M-6 -6 L6 6 M6 -6 L-6 6" stroke="#ffffff" stroke-width="2.6" stroke-linecap="round"/>`)}
</svg>`,
  );

const NOTE_PIN_HTML = () =>
  page(
    64,
    64,
    `<svg width="64" height="64" viewBox="0 0 64 64" style="position:absolute;left:0;top:0">
<defs><radialGradient id="pinHead" cx="0.38" cy="0.32" r="0.75"><stop offset="0" stop-color="#ff8a74"/><stop offset="0.35" stop-color="#c8321f"/><stop offset="1" stop-color="#5e1209"/></radialGradient>
<linearGradient id="pinNeedle" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#e9e6df"/><stop offset="1" stop-color="#7b7770"/></linearGradient>
<filter id="pinShadow" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="1.6"/></filter></defs>
<ellipse cx="9" cy="58" rx="5" ry="2.2" fill="rgba(30,18,8,0.45)" filter="url(#pinShadow)"/>
<path d="M36 28 L7 57" stroke="rgba(30,18,8,0.35)" stroke-width="3" stroke-linecap="round" filter="url(#pinShadow)" transform="translate(3 3)"/>
<path d="M36 28 L7 57" stroke="url(#pinNeedle)" stroke-width="2.4" stroke-linecap="round"/>
<circle cx="42" cy="22" r="15" fill="rgba(30,18,8,0.4)" filter="url(#pinShadow)" transform="translate(2 3)"/>
<circle cx="42" cy="22" r="14" fill="url(#pinHead)" stroke="#3a0c06" stroke-width="1.4"/>
<ellipse cx="37" cy="16" rx="5" ry="3.4" fill="rgba(255,255,255,0.75)" transform="rotate(-30 37 16)"/>
</svg>`,
  );

const QUEST_MARK_HTML = () =>
  page(
    64,
    64,
    `<svg width="64" height="64" viewBox="0 0 64 64" style="position:absolute;left:0;top:0">
<defs><linearGradient id="qmGold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff2a0"/><stop offset="0.45" stop-color="#ffd23a"/><stop offset="1" stop-color="#d98a0c"/></linearGradient>
<filter id="qmShadow" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="1.8"/></filter></defs>
<g transform="translate(2 3)" fill="rgba(30,18,8,0.45)" filter="url(#qmShadow)"><path d="M24 6 H40 L36 40 H28 Z"/><circle cx="32" cy="52" r="7"/></g>
<g fill="url(#qmGold)" stroke="#3a2208" stroke-width="3" stroke-linejoin="round"><path d="M24 6 H40 L36 40 H28 Z"/><circle cx="32" cy="52" r="7"/></g>
<path d="M27.5 9.5 H31 L30 30" stroke="rgba(255,255,255,0.7)" stroke-width="2.2" stroke-linecap="round" fill="none"/>
</svg>`,
  );

// Minimap-Knopf: freistehendes Buch mit Lesezeichen (Befund Nr. 5 aus art/minimap_icons.jpg, 2752 x 1536, 3 x 2 Motive auf Magenta;
// untere Reihe Mitte). Gemessen 29.10.2026 (PIL): Motiv x 1101..1639, y 880..1385 -> quadratischer Zuschnitt 560 x 560 (x 1090, y 852),
// auf 128 x 128. Der Magenta-Grund wird ueber die "Magentaanteil" m = min(R, B) - G gekeyt (braun/gold/rot/gruen/blau/schwarz: m <= 0,
// Magenta: 255): Alpha = 1 - m/255 (oberhalb einer Rauschschwelle), Farbe vom Magenta befreit (Mischung mit dem Grund rueckgerechnet);
// der schwarze Umriss des Motivs bleibt als Kontur. Kein runder Rahmen (journal/Access.lua zeigt es freistehend).
// 29.10.2026: Wunsch "eingepraegtes W" -> art/minimap_icon_w.jpg (Gemini-Ueberarbeitung von Nr. 5, 2048 x 2048, Motiv fuellt das Bild).
// 31.10.2026: Das goldene "W" erinnert zu stark an die Warcraft-Marke -> zurueck zum Buch OHNE W (Nr. 5, gleiches Motiv wie das CurseForge-Logo):
// art/minimap_nr5_ref.png, 560 x 560, bereits quadratisch auf Magenta zugeschnitten (Zuschnitt = ganzes Bild).
export const MINIMAP_CROP = { file: "./minimap_nr5_ref.png", x: 0, y: 0, w: 560, h: 560, srcW: 560, srcH: 560 };
export function keyMagenta(rgba, w, h, { noise = 40 } = {}) {
  for (let i = 0; i < w * h; i++) {
    const o = i * 4;
    const r = rgba[o];
    const g = rgba[o + 1];
    const b = rgba[o + 2];
    const m = Math.min(r, b) - g;
    if (m <= noise) continue;
    let a = Math.max(0, Math.min(1, 1 - (m - noise) / (255 - noise)));
    if (a < 0.04) a = 0; // JPEG-Rauschen im Grund
    rgba[o + 3] = Math.round(rgba[o + 3] * a);
    if (a > 0.02) {
      // Mischung mit Magenta (255, 0, 255) rueckrechnen: beobachtet = a * C + (1 - a) * M
      rgba[o] = Math.max(0, Math.min(255, Math.round((r - 255 * (1 - a)) / a)));
      rgba[o + 1] = Math.max(0, Math.min(255, Math.round(g / a)));
      rgba[o + 2] = Math.max(0, Math.min(255, Math.round((b - 255 * (1 - a)) / a)));
    } else {
      rgba[o] = rgba[o + 1] = rgba[o + 2] = 0;
    }
  }
  return rgba;
}
const MINIMAP_KEY = (rgba, w, h) => keyMagenta(rgba, w, h);

// Rechtecke/Kanten fuer 3- und 9-Teilung (weiss, wird per SetVertexColor eingefaerbt)
const ROUNDRECT_HTML = () => page(64, 64, `<div style="position:absolute;inset:0;border-radius:16px;background:#ffffff"></div>`);
const RING_HTML = () => page(64, 64, `<div style="position:absolute;inset:1px;border-radius:15px;border:2px solid #ffffff"></div>`);

// ---------------------------------------------------------------------------------------------------------------
// Baukasten "Tagebuch mit Stickern" (Nachtrag R11, journal/widgets/Diary.lua). Vorlage: Claude-Design Reiter E (zurueckhaltend).
// Alles im Browser gezeichnet (SVG/CSS, kantengeglaettet). Weisse Teile werden im Spiel per SetVertexColor eingefaerbt
// (Kringel, Tintenstrich, Kaestchen, Haken, Pfeile); Sticker, Klebeband und Abzeichen sind farbig und bleiben ungetoent.
// Masse stehen auch in journal/Theme.lua (Theme.DIARY_STICKER, Theme.DIARY_ATLAS); ein Test haelt beide gleich.

// Sticker-Grund: helles Etikett mit weissem Stanzrand und weichem Schatten, 128 x 64. Waagerecht 3-teilig dehnbar (auch
// 9-teilig: alle Raender gleich): die Kappen links/rechts (cap px) enthalten die ganze Rundung, die Mitte ist gleichfoermig.
export const DIARY_STICKER = { w: 128, h: 64, cap: 32, body: { x: 11, y: 10, w: 106, h: 40, r: 20, rim: 5 } };
const DIARY_STICKER_HTML = () => {
  const b = DIARY_STICKER.body;
  return page(
    DIARY_STICKER.w,
    DIARY_STICKER.h,
    `<div style="position:absolute;left:${b.x - b.rim}px;top:${b.y - b.rim}px;width:${b.w + 2 * b.rim}px;height:${b.h + 2 * b.rim}px;border-radius:3px;background:linear-gradient(#f3e6c8,#e8d6ae);box-shadow:0 2px 4px rgba(40,25,10,0.25)"></div>`,
  );
};

// Papierstreifen (B2b, ersetzt das blaue Washi-Tape): schmaler Pergament-Zettel mit gerissenen Enden, gerade, 128 x 32, waagerecht
// dehnbar (Grund der Unteransichts-Etiketten Diary.NewOpenLink)
export const DIARY_TAPE = { w: 128, h: 32 };
const DIARY_TAPE_HTML = () =>
  page(
    DIARY_TAPE.w,
    DIARY_TAPE.h,
    `<svg width="128" height="32" viewBox="0 0 128 32" style="position:absolute;left:0;top:0"><path d="M5 7 L123 6 L121 10 L124 14 L121 18 L124 22 L122 26 L5 26 L7 22 L4 18 L7 14 L4 10 Z" fill="#efe0bf" stroke="rgba(120,85,40,0.35)" stroke-width="1"/></svg>`,
  );

// Hand-Kringel: Ellipsenring wie mit der Feder gezogen (Anfang und Ende ueberlappen), weiss, 128 x 64, dehnbar
function diaryCirclePath() {
  const pts = [];
  const n = 90;
  const a0 = -0.55;
  const a1 = Math.PI * 2 + 0.35;
  for (let i = 0; i <= n; i++) {
    const t = a0 + ((a1 - a0) * i) / n;
    const grow = 1 + 0.05 * Math.sin(1.7 * t + 0.6) + 0.03 * (i / n);
    const x = 64 + 55 * grow * Math.cos(t);
    const y = 32 + 24 * grow * Math.sin(t) - 2.2 * (i / n);
    pts.push(`${x.toFixed(2)} ${y.toFixed(2)}`);
  }
  return "M" + pts.join(" L");
}
const DIARY_CIRCLE_HTML = () =>
  page(
    128,
    64,
    `<svg width="128" height="64" viewBox="0 0 128 64" style="position:absolute;left:0;top:0"><g transform="rotate(-3 64 32)"><path d="${diaryCirclePath()}" fill="none" stroke="#ffffff" stroke-width="3.6" stroke-linecap="round" stroke-linejoin="round"/></g></svg>`,
  );

// Tintenstrich (Unterstrich): Feder setzt links an, wird in der Mitte voll und laeuft rechts duenn aus, leicht wellig; weiss,
// 256 x 16, waagerecht dehnbar
function diaryStrokePath() {
  const top = [];
  const bot = [];
  const n = 64;
  for (let i = 0; i <= n; i++) {
    const u = i / n;
    const x = 4 + 248 * u;
    const mid = 8 + 1.1 * Math.sin(u * 7.3 + 0.4) + 0.6 * Math.sin(u * 17 + 1.2);
    const half = 0.6 + 2.6 * Math.min(1, u / 0.08) * (1 - 0.65 * Math.max(0, (u - 0.6) / 0.4));
    top.push(`${x.toFixed(2)} ${(mid - half).toFixed(2)}`);
    bot.push(`${x.toFixed(2)} ${(mid + half).toFixed(2)}`);
  }
  return "M" + top.join(" L") + " L" + bot.reverse().join(" L") + " Z";
}
const DIARY_STROKE_HTML = () =>
  page(256, 16, `<svg width="256" height="16" viewBox="0 0 256 16" style="position:absolute;left:0;top:0"><path d="${diaryStrokePath()}" fill="#ffffff"/></svg>`);

// Zeichen-Atlas 256 x 256, 4 x 4 Zellen zu 64 px (Reihenfolge = Theme.DIARY_ATLAS): Hand-Kaestchen, Feder-Haken, Abzeichen gold
// und rot (farbig, weisser Stanzrand + Schatten), Pfeil "➜", Zurueck "↩", Blaettern "‹" / "›", Dropdown "⌄". Die Pfeile sind
// Zeichnungen statt Schriftzeichen: Friz, Arial Narrow und Caveat haben ➜ ↩ ✓ ⌄ nicht.
export const DIARY_ATLAS = { size: 256, cell: 64, ids: ["box", "tick", "badgeGold", "badgeRed", "arrow", "back", "prev", "next", "down"] };
const DIARY_MARKS_HTML = () => {
  const W = "#ffffff";
  const sw = (d, w = 6) => `<path d="${d}" fill="none" stroke="${W}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/>`;
  const badge = (bg) =>
    `<div style="position:absolute;left:7px;top:5px;width:50px;height:50px;border-radius:50%;background:radial-gradient(circle at 38% 32%,rgba(255,255,255,0.22),rgba(255,255,255,0) 60%),${bg};box-shadow:0 2px 3px rgba(40,25,10,0.25)"></div>`;
  const cells = {
    box: `<svg width="64" height="64" viewBox="0 0 64 64"><g transform="rotate(-4 32 32)">${sw("M15 14.5 Q32 12.6 49.5 13.8 Q51.6 31 50.4 50.2 Q31 51.8 14 50.6 Q12.4 32 15 14.5 Z", 4.2)}</g></svg>`,
    tick: `<svg width="64" height="64" viewBox="0 0 64 64"><path d="M8 33 C14 34 20 39 25 47 C33 30 44 18 59 6 C46 20 36 34 28 55 C26.5 57 25 57 24 55 C20 46 15 39 8 35 Z" fill="${W}"/></svg>`,
    badgeGold: badge("#d9a656"),
    badgeRed: badge("#c46a6e"),
    arrow: `<svg width="64" height="64" viewBox="0 0 64 64"><path d="M7 25.5 H35 V14 L59 32 L35 50 V38.5 H7 Z" fill="${W}" stroke="${W}" stroke-width="2.5" stroke-linejoin="round"/></svg>`,
    back: `<svg width="64" height="64" viewBox="0 0 64 64">${sw("M50 12 V28 Q50 42 36 42 H15")}${sw("M26 31 L14 42 L26 53")}</svg>`,
    prev: `<svg width="64" height="64" viewBox="0 0 64 64">${sw("M40 12 L21 32 L40 52", 7)}</svg>`,
    next: `<svg width="64" height="64" viewBox="0 0 64 64">${sw("M24 12 L43 32 L24 52", 7)}</svg>`,
    down: `<svg width="64" height="64" viewBox="0 0 64 64">${sw("M13 23 L32 42 L51 23", 7)}</svg>`,
  };
  const n = DIARY_ATLAS.size / DIARY_ATLAS.cell;
  const body = DIARY_ATLAS.ids
    .map((id, i) => `<div style="position:absolute;left:${(i % n) * DIARY_ATLAS.cell}px;top:${Math.floor(i / n) * DIARY_ATLAS.cell}px;width:64px;height:64px;overflow:hidden">${cells[id]}</div>`)
    .join("");
  return page(DIARY_ATLAS.size, DIARY_ATLAS.size, body, "svg{position:absolute;left:0;top:0}");
};

// Gezeichnete Diary-Texturen (Rueckfall ohne gemalten Bogen, siehe DIARY_SHEET)
const DIARY_DRAWN = [
  { name: "DiarySticker", w: DIARY_STICKER.w, h: DIARY_STICKER.h, html: DIARY_STICKER_HTML },
  { name: "DiaryTape", w: DIARY_TAPE.w, h: DIARY_TAPE.h, html: DIARY_TAPE_HTML },
  { name: "DiaryCircle", w: 128, h: 64, html: DIARY_CIRCLE_HTML },
  { name: "DiaryStroke", w: 256, h: 16, html: DIARY_STROKE_HTML },
  { name: "DiaryMarks", w: DIARY_ATLAS.size, h: DIARY_ATLAS.size, html: DIARY_MARKS_HTML },
];

// B2b: Papier-Etiketten. Bevorzugt wird der Etiketten-Bogen art/journal/label_sheet.(png|jpg) (freigegeben: Pergament-
// Zettel mit gerissenen Raendern, runde Etiketten gold/rot, schmaler Papierstreifen, Feder-Zeichen; gleiche Zellbelegung, Magenta-Grund
// mit duennen lila Gitterlinien, siehe isLine). Nur wenn er fehlt, gilt der alte Tagebuch-Bogen (weisse Sticker, blaues Tape).
// Gemalter Tagebuch-Bogen (Nachtrag R11c, Prompt docs/gemini-diary-sheet.md): art/journal/diary_sheet.(png|jpg), 4 x 3 Zellen auf
// Magenta, feste Reihenfolge (DIARY_SHEET.order). Liegt der Bogen vor, entstehen die fuenf Diary-Texturen daraus statt aus den
// Zeichnungen oben: gleiche Namen, Groessen und Atlas-Lage (Diary.lua und Theme.lua bleiben unveraendert). Fehlt er, bleiben die
// gezeichneten Texturen (Schalter = Vorhandensein der Quelle, wie bei den uebrigen Gemini-Texturen).
// Ablauf (diarySheet): Raster aus den satten Magenta-Linien erkennen (sonst aus den Luecken zwischen den Elementen, sonst
// gleichmaessig), je Zelle den Hintergrund messen und wegschluesseln: Schluessel k = Blau - Gruen (Magenta ~170-255, Tinte/
// Papier/Gold < 40; Karminrot hat kaum Blau und bleibt), Deckkraft linear zwischen Hintergrund und dem k des Elements
// (95-%-Quantil der sicheren Vordergrundpixel), danach die Farbe vom Magenta befreit (Mischung zurueckgerechnet). Farbige Elemente
// (Sticker, Abzeichen) behalten ihren weichen Schatten halbtransparent; Tinten-Elemente werden weiss (Einfaerbung im Spiel).
// Danach je Element auf den Inhalt zugeschnitten und in die Zieltextur gesetzt (DIARY_SHEET.place).
export const DIARY_SHEET = {
  files: ["label_sheet.png", "label_sheet.jpg", "diary_sheet.png", "diary_sheet.jpg"],
  // Reihenfolge der zwoelf Zellen (zeilenweise, wie im Prompt)
  order: ["sticker", "badgeGold", "badgeRed", "tape", "circle", "box", "tick", "arrow", "stroke", "prev", "back", "down"],
  colored: ["sticker", "badgeGold", "badgeRed", "tape"], // Farbe behalten; alle anderen weiss (SetVertexColor im Spiel)
  shadow: ["sticker", "badgeGold", "badgeRed"],          // weicher Schatten bleibt halbtransparent
  tapeAlpha: 1,                                          // B2b: Papierstreifen deckend (frueher Washi-Tape 0,85)
  tapeTilt: 0,                                           // B2b: gerade (der Streifen ist Grund eines Etiketts, waagerecht gedehnt)
  inset: 6,                                              // Pixel Abstand zu Rasterlinie/Bildrand beim Zellenzuschnitt
  // Zielflaechen [x, y, w, h] in der Textur bzw. Atlaszelle; fit "contain" = Seitenverhaeltnis halten, "fill" = strecken
  marks: { box: 52, tick: 56, badgeGold: 52, badgeRed: 52, arrow: 54, back: 50, prev: 46, next: 46, down: 40 },
};

export function diarySheetSource(root = ROOT) {
  const f = DIARY_SHEET.files.find((n) => existsSync(path.join(root, "art", "journal", n)));
  return f ? "art/journal/" + f : null;
}

/** Breite und Hoehe eines PNG aus dem IHDR-Kopf ({ w, h } | null) */
export function pngSize(buf) {
  if (buf.length < 24 || buf.readUInt32BE(0) !== 0x89504e47 || buf.toString("ascii", 12, 16) !== "IHDR") return null;
  return { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) };
}

// Rasterlinien: sattes Magenta (Tagebuch-Bogen, ~ 255/0/255) oder dunkleres Lila (Etiketten-Bogen B2b, ~ 200/0/190). Der Grund
// beider Boegen hat Gruen ~ 40-90 (Etiketten-Bogen ~ 253/45/253!), die Linien Gruen < 25: dadurch trennbar (Toleranz fuer die
// lila Gitterlinien des Etiketten-Bogens, ohne den Grund mitzunehmen).
const isLine = (r, g, b) => g < 25 && r > 150 && b > 150 && Math.min(r, b) - g > 130;
const keyK = (r, g, b) => b - g;

// Laeufe (a, b exklusiv) der Indizes, fuer die test(i) gilt
function runs(n, test) {
  const out = [];
  let s = -1;
  for (let i = 0; i <= n; i++) {
    const on = i < n && test(i);
    if (on && s < 0) s = i;
    if (!on && s >= 0) {
      out.push([s, i]);
      s = -1;
    }
  }
  return out;
}

// Zellgrenzen aus k Trennern (je [a, b]): Zellen dazwischen, aussen bis zum Bildrand
const cellsFrom = (seps, n) => {
  const out = [];
  let a = 0;
  for (const [s0, s1] of seps) {
    out.push([a, s0]);
    a = s1;
  }
  out.push([a, n]);
  return out;
};

// Inhalts-Laeufe auf count bringen (schmalste Luecken zuerst zusammenlegen) -> Trenner = Luecken dazwischen | null
function gapsToSeps(content, count) {
  const big = content.slice();
  if (big.length < count) return null;
  while (big.length > count) {
    let best = 1;
    for (let k = 2; k < big.length; k++) if (big[k][0] - big[k - 1][1] < big[best][0] - big[best - 1][1]) best = k;
    big.splice(best - 1, 2, [big[best - 1][0], big[best][1]]);
  }
  const seps = [];
  for (let k = 1; k < big.length; k++) {
    const m = Math.round((big[k - 1][1] + big[k][0]) / 2);
    seps.push([m, m]);
  }
  return seps;
}

/**
 * Raster eines 4 x 3-Bogens auf Magenta: { x: [[a, b] x 4], y: [[a, b] x 3], how }. Zuerst die satten Magenta-Linien (Spalten
 * bzw. Zeilen, die zu >= 80 % aus Linienfarbe bestehen, schmaler als 4 % der Kante); passt deren Zahl nicht, die Luecken
 * zwischen den Elementen (Spalten/Zeilen ganz ohne Vordergrund); sonst gleichmaessig.
 */
export function diaryGrid(rgba, w, h, cols = 4, rows = 3) {
  const px = (x, y) => (y * w + x) * 4;
  const lineAt = (o) => isLine(rgba[o], rgba[o + 1], rgba[o + 2]);
  const fgAt = (o) => keyK(rgba[o], rgba[o + 1], rgba[o + 2]) < 110;
  const count = (n, m, at, f) => (i) => {
    let c = 0;
    for (let j = 0; j < m; j += 2) if (f(at(i, j))) c++;
    return c;
  };
  const colLine = count(w, h, (i, j) => px(i, j), lineAt);
  const rowLine = count(h, w, (i, j) => px(j, i), lineAt);
  const vx = runs(w, (i) => colLine(i) >= 0.8 * (h / 2)).filter(([a, b]) => b - a < 0.04 * w && a > 0 && b < w);
  const vy = runs(h, (i) => rowLine(i) >= 0.8 * (w / 2)).filter(([a, b]) => b - a < 0.04 * h && a > 0 && b < h);
  if (vx.length === cols - 1 && vy.length === rows - 1) return { x: cellsFrom(vx, w), y: cellsFrom(vy, h), how: "Linien" };
  const colFg = count(w, h, (i, j) => px(i, j), fgAt);
  const rowFg = count(h, w, (i, j) => px(j, i), fgAt);
  const sx = gapsToSeps(runs(w, (i) => colFg(i) > 1), cols);
  const sy = gapsToSeps(runs(h, (i) => rowFg(i) > 1), rows);
  if (sx && sy) return { x: cellsFrom(sx, w), y: cellsFrom(sy, h), how: "Luecken" };
  const even = (n, k) => Array.from({ length: k }, (_, i) => [Math.round((i * n) / k), Math.round(((i + 1) * n) / k)]);
  return { x: even(w, cols), y: even(h, rows), how: "gleichmaessig" };
}

const quantile = (arr, q = 0.5) => {
  if (!arr.length) return null;
  const s = Float64Array.from(arr).sort();
  return s[Math.min(s.length - 1, Math.floor(s.length * q))];
};
const median = (arr) => quantile(arr, 0.5);

/**
 * Eine Zelle freistellen und auf den Inhalt zuschneiden. -> { w, h, rgba } (RGBA, nicht vormultipliziert) | null (leer)
 */
export function keyDiaryCell(rgba, w, x0, y0, x1, y1, { white = false, shadow = false, alphaScale = 1 } = {}) {
  const cw = x1 - x0, ch = y1 - y0;
  if (cw <= 0 || ch <= 0) return null;
  // Hintergrund und Vordergrund-Schluessel der Zelle messen (jede 3. Zeile/Spalte genuegt)
  const bgR = [], bgG = [], bgB = [], fgK = [];
  for (let y = y0; y < y1; y += 3) {
    for (let x = x0; x < x1; x += 3) {
      const o = (y * w + x) * 4;
      const r = rgba[o], g = rgba[o + 1], b = rgba[o + 2];
      if (isLine(r, g, b)) continue;
      const k = keyK(r, g, b);
      if (k > 120 && r > 180 && b > 180) {
        bgR.push(r);
        bgG.push(g);
        bgB.push(b);
      } else if (k < 40) fgK.push(k);
    }
  }
  const B = [median(bgR) ?? 255, median(bgG) ?? 84, median(bgB) ?? 255];
  const kBg = B[2] - B[1];
  const kFg = Math.min(quantile(fgK, 0.95) ?? 0, kBg - 60); // fast alle sicheren Vordergrundpixel voll deckend
  const NOISE = 12; // JPEG-Rauschen im Hintergrund bleibt durchsichtig
  const bgSum = B[0] + B[1] + B[2];
  const out = Buffer.alloc(cw * ch * 4);
  let bx0 = cw, by0 = ch, bx1 = -1, by1 = -1;
  for (let y = 0; y < ch; y++) {
    for (let x = 0; x < cw; x++) {
      const o = ((y0 + y) * w + x0 + x) * 4;
      const r = rgba[o], g = rgba[o + 1], b = rgba[o + 2];
      const d = (y * cw + x) * 4;
      let a = clamp01((kBg - keyK(r, g, b) - NOISE) / (kBg - kFg - NOISE));
      if (isLine(r, g, b)) a = 0;
      if (a > 0) {
        const c = [r, g, b].map((v, i) => Math.max(0, Math.min(255, Math.round((v - (1 - a) * B[i]) / a))));
        if (white) c[0] = c[1] = c[2] = 255;
        out[d] = c[0];
        out[d + 1] = c[1];
        out[d + 2] = c[2];
        out[d + 3] = Math.round(255 * a * alphaScale);
        if (a > 0.2) {
          if (x < bx0) bx0 = x;
          if (x > bx1) bx1 = x;
          if (y < by0) by0 = y;
          if (y > by1) by1 = y;
        }
      } else if (shadow) {
        // Schatten: Hintergrund abgedunkelt -> dunkles Braun mit der Abdunklung als Deckkraft (hoechstens 0,5)
        const s = Math.min(0.5, Math.max(0, (1 - (r + g + b) / bgSum - 0.02) * 2.5));
        if (s > 0) {
          out[d] = 40;
          out[d + 1] = 25;
          out[d + 2] = 10;
          out[d + 3] = Math.round(255 * s);
        }
      }
    }
  }
  if (bx1 < 0) return null;
  // Zuschnitt auf den Inhalt plus Rand (2 % der groesseren Seite, Schatten passt hinein)
  const pad = Math.max(2, Math.round(0.04 * Math.max(bx1 - bx0, by1 - by0)));
  const ax = Math.max(0, bx0 - pad), ay = Math.max(0, by0 - pad);
  const ex = Math.min(cw, bx1 + 1 + pad), ey = Math.min(ch, by1 + 1 + pad);
  const tw = ex - ax, th = ey - ay;
  const crop = Buffer.alloc(tw * th * 4);
  for (let y = 0; y < th; y++) out.copy(crop, y * tw * 4, ((ay + y) * cw + ax) * 4, ((ay + y) * cw + ex) * 4);
  // Inhaltskasten relativ zum Zuschnitt (ohne Rand): fuer genaue Einpassung
  return { w: tw, h: th, rgba: crop, box: [bx0 - ax, by0 - ay, bx1 + 1 - ax, by1 + 1 - ay] };
}

/**
 * Quelle (Element) in einen Zielbereich zeichnen, vormultipliziert ueber Teilpixel gemittelt. src: { w, h, rgba };
 * sr = [x, y, w, h] Ausschnitt der Quelle; dr = [x, y, w, h] Zielbereich; flipX spiegelt, rot (Grad, wie CSS rotate) dreht um
 * die Mitte des Zielbereichs. Schreibt ueber vorhandene Pixel (source-over).
 */
export function drawInto(dst, dw, dh, src, sr, dr, { flipX = false, rot = 0 } = {}) {
  const [sx, sy, sw, sh] = sr;
  const [dx, dy, dwid, dhei] = dr;
  if (sw <= 0 || sh <= 0 || dwid <= 0 || dhei <= 0) return dst;
  const n = Math.max(2, Math.min(8, Math.ceil(Math.max(sw / dwid, sh / dhei))));
  const cx = dx + dwid / 2, cy = dy + dhei / 2;
  const t = (-rot * Math.PI) / 180;
  const cos = Math.cos(t), sin = Math.sin(t);
  // gedrehter Bereich: Bounding-Box der Ecken
  const ex = Math.abs(dwid / 2 * Math.cos(t)) + Math.abs(dhei / 2 * Math.sin(t));
  const ey = Math.abs(dwid / 2 * Math.sin(t)) + Math.abs(dhei / 2 * Math.cos(t));
  const X0 = Math.max(0, Math.floor(cx - ex)), X1 = Math.min(dw, Math.ceil(cx + ex));
  const Y0 = Math.max(0, Math.floor(cy - ey)), Y1 = Math.min(dh, Math.ceil(cy + ey));
  for (let y = Y0; y < Y1; y++) {
    for (let x = X0; x < X1; x++) {
      let r = 0, g = 0, b = 0, a = 0;
      for (let j = 0; j < n; j++) {
        for (let i = 0; i < n; i++) {
          const px = x + (i + 0.5) / n - cx, py = y + (j + 0.5) / n - cy;
          // zurueckdrehen in den ungedrehten Zielbereich
          const ux = px * cos + py * sin + dwid / 2, uy = -px * sin + py * cos + dhei / 2;
          if (ux < 0 || uy < 0 || ux >= dwid || uy >= dhei) continue;
          let qx = (ux / dwid) * sw;
          if (flipX) qx = sw - qx;
          const qy = (uy / dhei) * sh;
          const X = Math.min(src.w - 1, Math.max(0, Math.floor(sx + qx)));
          const Y = Math.min(src.h - 1, Math.max(0, Math.floor(sy + qy)));
          const o = (Y * src.w + X) * 4;
          const al = src.rgba[o + 3] / 255;
          r += src.rgba[o] * al;
          g += src.rgba[o + 1] * al;
          b += src.rgba[o + 2] * al;
          a += al;
        }
      }
      if (a <= 0) continue;
      const nn = n * n;
      const sa = a / nn;
      const d = (y * dw + x) * 4;
      const da = dst[d + 3] / 255;
      const oa = sa + da * (1 - sa);
      for (let k = 0; k < 3; k++) {
        const sc = [r, g, b][k] / a; // Farbe des Quellanteils (nicht vormultipliziert)
        dst[d + k] = Math.round((sc * sa + dst[d + k] * da * (1 - sa)) / oa);
      }
      dst[d + 3] = Math.round(oa * 255);
    }
  }
  return dst;
}

// Inhaltskasten mit Rand m (Anteil) als Quellausschnitt
const boxRect = (el, m = 0) => {
  const [a, b, c, d] = el.box;
  const pw = Math.round((c - a) * m), ph = Math.round((d - b) * m);
  return [a - pw, b - ph, c - a + 2 * pw, d - b + 2 * ph];
};

// Seitenverhaeltnis haltend mittig in ein Quadrat side (Atlaszelle) bzw. Rechteck einpassen
const containRect = (sr, cx, cy, maxW, maxH) => {
  const s = Math.min(maxW / sr[2], maxH / sr[3]);
  const w = sr[2] * s, h = sr[3] * s;
  return [cx - w / 2, cy - h / 2, w, h];
};

/** Bogen (rgba w x h) -> { elements: { id: Element }, grid } (wirft, wenn eine Zelle leer ist) */
export function diarySheet(rgba, w, h) {
  const grid = diaryGrid(rgba, w, h);
  const S = DIARY_SHEET;
  const elements = {};
  S.order.forEach((id, i) => {
    const [x0, x1] = grid.x[i % 4];
    const [y0, y1] = grid.y[Math.floor(i / 4)];
    const el = keyDiaryCell(rgba, w, x0 + S.inset, y0 + S.inset, x1 - S.inset, y1 - S.inset, {
      white: !S.colored.includes(id),
      shadow: S.shadow.includes(id),
      alphaScale: id === "tape" ? S.tapeAlpha : 1,
    });
    if (!el) throw new Error(`Tagebuch-Bogen: Zelle ${i + 1} (${id}) ist leer`);
    elements[id] = el;
  });
  return { elements, grid };
}

/** Die fuenf Diary-Texturen aus den Elementen: { DiarySticker, DiaryTape, DiaryCircle, DiaryStroke, DiaryMarks } (RGBA) */
export function diarySheetTextures(elements) {
  const E = elements;
  const out = {};
  // Sticker 128 x 64, dreiteilig wie das gezeichnete: Etikett (mit Stanzrand) fuellt die Flaeche innerhalb von Theme-pad
  // (l 6, r 6, t 5, b 9; der Schatten liegt im Rand); die Kappen (cap) behalten das Seitenverhaeltnis, die Mitte wird gestaucht.
  {
    const T = DIARY_STICKER, W = T.w, H = T.h;
    const pad = { l: 6, r: 6, t: 5, b: 9 };
    const buf = Buffer.alloc(W * H * 4);
    const el = E.sticker;
    const [bx, by, bw, bh] = boxRect(el);
    const ih = H - pad.t - pad.b;
    const s = ih / bh; // Ziel-px je Quell-px
    const capT = T.cap - pad.l; // Kappe innerhalb des Etiketts (Ziel)
    const capS = Math.min(Math.floor(bw / 2), Math.round(capT / s));
    const marginS = Math.round(pad.t / s); // Rand (Schatten) ober-/unterhalb in Quellpixeln
    const sy0 = Math.max(0, by - marginS), sy1 = Math.min(el.h, by + bh + Math.round(pad.b / s));
    const dy0 = pad.t - (by - sy0) * s, dh = (sy1 - sy0) * s;
    const lx = Math.max(0, bx - Math.round(pad.l / s)), rx = Math.min(el.w, bx + bw + Math.round(pad.r / s));
    // links: Rand + Kappe, Mitte, rechts: Kappe + Rand
    drawInto(buf, W, H, el, [lx, sy0, bx + capS - lx, sy1 - sy0], [pad.l - (bx - lx) * s, dy0, (bx + capS - lx) * s, dh]);
    drawInto(buf, W, H, el, [bx + capS, sy0, bw - 2 * capS, sy1 - sy0], [T.cap, dy0, W - 2 * T.cap, dh]);
    drawInto(buf, W, H, el, [bx + bw - capS, sy0, rx - (bx + bw - capS), sy1 - sy0], [W - T.cap, dy0, (rx - (bx + bw - capS)) * s, dh]);
    out.DiarySticker = buf;
  }
  // Papierstreifen 128 x 32 (B2b): gestreckt auf die Flaeche mit 3 px Rand (Schatten), um tapeTilt gedreht
  {
    const T = DIARY_TAPE;
    const buf = Buffer.alloc(T.w * T.h * 4);
    drawInto(buf, T.w, T.h, E.tape, boxRect(E.tape), [3, 3, T.w - 6, T.h - 7], { rot: DIARY_SHEET.tapeTilt });
    out.DiaryTape = buf;
  }
  // Kringel 128 x 64 und Tintenstrich 256 x 16: gestreckt (beide werden im Spiel ohnehin gedehnt)
  {
    const buf = Buffer.alloc(128 * 64 * 4);
    drawInto(buf, 128, 64, E.circle, boxRect(E.circle), [3, 3, 122, 58]);
    out.DiaryCircle = buf;
    const st = Buffer.alloc(256 * 16 * 4);
    drawInto(st, 256, 16, E.stroke, boxRect(E.stroke), [3, 2, 250, 12]);
    out.DiaryStroke = st;
  }
  // Zeichen-Atlas: je Zelle mittig, Seitenverhaeltnis gehalten, groesste Kante DIARY_SHEET.marks[id]; "next" = "prev" gespiegelt
  {
    const A = DIARY_ATLAS, n = A.size / A.cell;
    const buf = Buffer.alloc(A.size * A.size * 4);
    A.ids.forEach((id, i) => {
      const el = E[id === "next" ? "prev" : id];
      const sr = boxRect(el);
      const side = DIARY_SHEET.marks[id] ?? 48;
      const cx = (i % n) * A.cell + A.cell / 2, cy = Math.floor(i / n) * A.cell + A.cell / 2;
      drawInto(buf, A.size, A.size, el, sr, containRect(sr, cx, cy, side, side), { flipX: id === "next" });
    });
    out.DiaryMarks = buf;
  }
  return out;
}

// Ein Lauf berechnet den Bogen einmal und teilt ihn auf die fuenf Texturen auf
let sheetCache = null;
function diaryFromSheet(name, rgba, w, h) {
  if (!sheetCache || sheetCache.w !== w || sheetCache.h !== h) {
    const s = diarySheet(rgba, w, h);
    sheetCache = { w, h, tex: diarySheetTextures(s.elements) };
    console.log(`  Tagebuch-Bogen: Raster ${s.grid.how} (x ${JSON.stringify(s.grid.x)}, y ${JSON.stringify(s.grid.y)})`);
  }
  return sheetCache.tex[name];
}

/** Diary-Texturen: aus dem Bogen (source vorhanden) oder gezeichnet (Rueckfall) */
export function diaryTextures(source = diarySheetSource()) {
  if (!source) return DIARY_DRAWN;
  const size = () => {
    const buf = readFileSync(path.join(ROOT, source));
    const s = /\.png$/i.test(source) ? pngSize(buf) : jpegSize(buf);
    if (!s) throw new Error(`${source}: Groesse nicht lesbar`);
    return s;
  };
  const file = path.basename(source);
  return DIARY_DRAWN.map((t) => ({
    name: t.name,
    w: t.w,
    h: t.h,
    get rw() {
      return size().w;
    },
    get rh() {
      return size().h;
    },
    html: () => {
      const s = size();
      return ART(file, { x: 0, y: 0, w: s.w, h: s.h, srcW: s.w, srcH: s.h }, s.w, s.h);
    },
    post: (rgba, w, h) => diaryFromSheet(t.name, rgba, w, h),
    sheet: source,
  }));
}
const DIARY_TEXTURES = diaryTextures();

// Willkommen-zurueck-Zettel (B08, journal/Begleiter.lua): art/toast/welcome_back_v2.jpg (2752 x 1536, Gemini, freigegeben
// 03.11.2026; Magenta-Grund, links runder Holz-Bronze-Rahmen mit Laterne und Feder, der innere Kreis ist Magenta, rechts Pergament mit
// rotem Lesezeichen). Gemessen 03.11.2026 (Flutfuellung des Magenta im Kreis, Schwelle min(R,B)-G > 120): Kreis x 325..1066,
// y 344..1110 (742 x 767, Mitte 695,5 | 727, flaechengleicher Radius 378); Motiv x 72..2617, y 86..1479 (mit Laternenschimmer).
// Zuschnitt x 56..2640, y 70..1500 (2584 x 1430, 1,807 : 1) -> auf 1024 x 512 gestreckt, im Spiel mit 420 x 232 wieder zurueck.
// Die Konstanten in journal/Begleiter.lua (SLIP: circleX/circleY/circleR, Papierflaeche) rechnen daraus (Massstab 420 / 2584).
// Das Erzaehler-Portraet liegt UNTER dieser Textur im durchsichtigen Kreis. Neues Bild: Zuschnitt neu messen,
// `node scripts/render-media.mjs --only WelcomeBack`.
export const WELCOME_BACK_CROP = { file: "toast/welcome_back_v2.jpg", x: 56, y: 70, w: 2584, h: 1430, srcW: 2752, srcH: 1536 };
export const WELCOME_BACK_CIRCLE = { cx: 695.5, cy: 727, r: 378 }; // Pixel des Quellbilds

// Freigestellte Erzaehler-Figur des Willkommen-Zettels: art/toast/narrator_cutout_<volk>_v2.jpg (2048 x 2048, Magenta-Grund,
// Oberkoerper). Die Figur steht HINTER dem Ring im Kreis, nur der obere Teil schaut davor heraus. Ebenen von unten nach oben:
// (1) NarratorBG_<volk> (Hintergrund im Kreis), (2) NarratorFigIn_<volk> = Figur auf das Kreisinnere maskiert (Radius CUTOUT_GEO.rIn),
// (3) der Rahmen WelcomeBack, (4) NarratorFigOut_<volk> = dieselbe Figur oberhalb der Schnittlinie CUTOUT_GEO.cut (9 px weich) UND
// alles, was ausserhalb der Rahmen-Silhouette liegt (Media/WelcomeBack.tga durchsichtig, ohne Hoehengrenze: Aermel, Robe bleiben immer
// sichtbar; WelcomeBack muss vorher gerendert sein).
// Zuschnitt = ganze Figur (Bounding-Box des Nicht-Magenta, ab Kopf bis zum Bildunterrand bzw. untenY) -> 512 x 512 (gestreckt);
// `game` = Lage/Groesse im Zettel in px (identisch zu Begleiter.CUTOUTS). Die Unterkante liegt bei y 178, also hinter dem Ring bzw. im
// Kreis unter der Schnittlinie; ausserhalb des Rings blendet nur der unterste Streifen (fade) weich aus.
// Overrides je Volk (Zettelpixel; e = Ellipse [cx, cy, rx, ry], r = Rechteck [x0, y0, x1, y1]): frontKeep = immer vor dem Ring (ganze Hand), frontDrop =
// nie vor dem Ring (bleibt hinter dem Ring bzw. faellt weg). Grundregel: ein Koerperteil liegt ganz vor oder ganz hinter dem Ring.
// Zuschnitt und Zeilen liefert `python scripts/measure-cutout.py <volk>` (Troll: Schaedel 340, Mensch: untenY 1840 wegen rundem Rand);
// Zwerg: despill gegen rosa Dampf. Kreis: Mitte 104|107 (Zettel), Loch-Radius 61.
export const CUTOUT_GEO = { cx: 104, cy: 107, rIn: 64, cut: 134, soft: 9, fade: 6 };
export const NARRATOR_CUTOUTS = {
  undead: { file: "toast/narrator_cutout_undead_v2.jpg", x: 350, y: 160, w: 1576, h: 1888, srcW: 2048, srcH: 2048, game: { x: 25.9, y: -21.8, w: 166.8, h: 199.8 } },
  human: { file: "toast/narrator_cutout_human_v2.jpg", x: 190, y: 133, w: 1732, h: 1707, srcW: 2048, srcH: 2048, game: { x: -8.2, y: -21.9, w: 202.8, h: 199.9 } },
  dwarf: { file: "toast/narrator_cutout_dwarf_v2.jpg", x: 31, y: 109, w: 2010, h: 1939, srcW: 2048, srcH: 2048, despill: { x0: 400, y0: 90, x1: 512, y1: 215 }, frontKeep: [{ e: [34, 132, 18, 20] }], game: { x: -8.0, y: -21.7, w: 207.0, h: 199.7 } },
  nightelf: { file: "toast/narrator_cutout_nightelf_v2.jpg", x: 191, y: 184, w: 1726, h: 1864, srcW: 2048, srcH: 2048, frontDrop: [{ r: [-20, 134, 45, 190] }, { e: [39, 127, 11, 8] }, { e: [31, 132, 5, 4] }, { r: [150, 68, 185, 190] }], frontKeep: [{ e: [152, 50, 24, 14] }], game: { x: -8.1, y: -21.8, w: 185.0, h: 199.8 } },
  gnome: { file: "toast/narrator_cutout_gnome_v2.jpg", x: 409, y: 18, w: 1626, h: 2030, srcW: 2048, srcH: 2048, game: { x: 28.0, y: -21.7, w: 159.9, h: 199.7 } },
  orc: { file: "toast/narrator_cutout_orc_v2.jpg", x: 386, y: 59, w: 1606, h: 1989, srcW: 2048, srcH: 2048, game: { x: 21.0, y: -21.7, w: 161.2, h: 199.7 } },
  tauren: { file: "toast/narrator_cutout_tauren_v2.jpg", x: 163, y: 123, w: 1849, h: 1925, srcW: 2048, srcH: 2048, game: { x: -8.0, y: -21.7, w: 191.9, h: 199.7 } },
  troll: { file: "toast/narrator_cutout_troll_v2.jpg", x: 264, y: 0, w: 1708, h: 2048, srcW: 2048, srcH: 2048, game: { x: -8.2, y: -60.0, w: 198.5, h: 238.0 } },
  skyborne: { file: "toast/narrator_cutout_skyborne_v2.jpg", x: 137, y: 178, w: 1789, h: 1870, srcW: 2048, srcH: 2048, frontDrop: [{ r: [-20, 134, 22, 190] }, { r: [-20, 118, 38, 140] }], game: { x: 8.9, y: -21.8, w: 191.1, h: 199.8 } },
};
export const NARRATOR_CUTOUTS_PENDING = [];
// Fig_out: ausserhalb des Rings bleibt nur, was ueber sichtbare Pixel mit dem Teil OBERHALB der Schnittlinie zusammenhaengt (8er-Nachbarschaft,
// Deckkraft >= MIN_A). Lose Stuecke (Aermel-/Umhangzipfel, Haende, Buchecken, deren Verbindung hinter dem Ring liegt) und kleine Inseln
// (< MIN_AREA Texturpixel) fallen weg; schwache Randpixel bleiben nur neben einer behaltenen Flaeche.
const inShapes = (list, x, y) => {
  let m = 0;
  for (const sh of list || []) {
    let v;
    if (sh.e) { const rho = Math.hypot((x - sh.e[0]) / sh.e[2], (y - sh.e[1]) / sh.e[3]); v = Math.max(0, Math.min(1, (1 - rho) / 0.12)); }
    else v = x >= sh.r[0] && x <= sh.r[2] && y >= sh.r[1] && y <= sh.r[3] ? 1 : 0;
    m = Math.max(m, v);
  }
  return m;
};
const CUTOUT_MIN_A = 24;
const CUTOUT_MIN_AREA = 30;
function keepConnectedToTop(rgba, w, h, g, G, c) {
  const A = (i) => rgba[i * 4 + 3];
  const label = new Int32Array(w * h).fill(-1);
  const keep = new Uint8Array(w * h);
  const stack = new Int32Array(w * h);
  let n = 0;
  for (let s0 = 0; s0 < w * h; s0++) {
    if (label[s0] !== -1 || A(s0) < CUTOUT_MIN_A) continue;
    let sp = 0, area = 0, top = false;
    const members = [];
    stack[sp++] = s0; label[s0] = n;
    while (sp) {
      const p = stack[--sp];
      members.push(p);
      area++;
      const py = Math.floor(p / w), px = p - py * w;
      if (g.y + ((py + 0.5) / h) * g.h < G.cut || inShapes(c.frontKeep, g.x + ((px + 0.5) / w) * g.w, g.y + ((py + 0.5) / h) * g.h) > 0.5) top = true;
      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          const qx = px + dx, qy = py + dy;
          if (qx < 0 || qy < 0 || qx >= w || qy >= h) continue;
          const q = qy * w + qx;
          if (label[q] === -1 && A(q) >= CUTOUT_MIN_A) { label[q] = n; stack[sp++] = q; }
        }
      }
    }
    if (top && area >= CUTOUT_MIN_AREA) for (const p of members) keep[p] = 1;
    n++;
  }
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const p = y * w + x;
      if (keep[p]) continue;
      let near = false;
      if (A(p) > 0 && A(p) < CUTOUT_MIN_A) {
        for (let dy = -1; dy <= 1 && !near; dy++) for (let dx = -1; dx <= 1; dx++) {
          const qx = x + dx, qy = y + dy;
          if (qx >= 0 && qy >= 0 && qx < w && qy < h && keep[qy * w + qx]) { near = true; break; }
        }
      }
      if (!near) rgba[p * 4 + 3] = 0;
    }
  }
}

// despill = {x0, y0, x1, y1} (Texturpixel 512 x 512): rosa Reste (halbtransparenter Dampf, Magenta-Spill) in diesem Bereich zu hellem
// Grau entfaerben; die Deckkraft bleibt. Zwerg: Dampf ueber dem Krug.
// mode "in" = Figur im Kreis (hinter dem Ring), "out" = Figur vor dem Ring (siehe CUTOUT_GEO). Texturpixel -> Zettelpixel ueber c.game.
export function cutoutKey(rgba, w, h, c, mode) {
  keyMagenta(rgba, w, h, { noise: 60 });
  const despill = c && c.despill;
  if (despill) {
    for (let y = despill.y0; y < Math.min(h, despill.y1); y++) {
      for (let x = despill.x0; x < Math.min(w, despill.x1); x++) {
        const i = (y * w + x) * 4;
        const r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
        if (Math.min(r, b) - g > 25) {
          const l = Math.round((r + g + b * 0.5) / 2.5 * 0.35 + 205 * 0.65);
          rgba[i] = l; rgba[i + 1] = Math.max(0, l - 3); rgba[i + 2] = Math.max(0, l - 8);
        }
      }
    }
  }
  if (c && c.game && mode) {
    const G = CUTOUT_GEO, g = c.game, clamp = (v) => Math.max(0, Math.min(1, v));
    const frame = mode === "out" ? decodeTga(readFileSync(path.join(MEDIA_DIR, "WelcomeBack.tga"))) : null;
    for (let y = 0; y < h; y++) {
      const gy = g.y + ((y + 0.5) / h) * g.h;
      const fade = clamp((g.y + g.h - gy) / G.fade); // unterster Streifen weich (nur dort sichtbar, wo die Kante nicht hinter dem Ring liegt)
      for (let x = 0; x < w; x++) {
        const gx = g.x + ((x + 0.5) / w) * g.w;
        const d = Math.hypot(gx - G.cx, gy - G.cy);
        let k;
        if (mode === "in") k = clamp(G.rIn - d + 0.5);
        else {
          const fx = Math.floor((gx / 420) * frame.w), fy = Math.floor((gy / 232) * frame.h);
          const fa = fx >= 0 && fy >= 0 && fx < frame.w && fy < frame.h ? frame.rgba[(fy * frame.w + fx) * 4 + 3] : 0;
          k = Math.max(clamp((G.cut - gy) / G.soft + 0.5), clamp(1 - fa / 200));
          k = Math.max(k * (1 - inShapes(c.frontDrop, gx, gy)), inShapes(c.frontKeep, gx, gy));
        }
        const i = (y * w + x) * 4 + 3;
        rgba[i] = Math.round(rgba[i] * k * fade);
      }
    }
    if (mode === "out") keepConnectedToTop(rgba, w, h, g, G, c);
  }
  return rgba;
}

// Kreis-Hintergruende des Willkommen-Gruesses (art/toast/narrator_bg_<volk>_v1.jpg, 2048 x 2048, Landschaft ohne Figur, freigegeben
// 04.11.2026): ersetzen im Kreis hinter der Pop-out-Figur das Erzaehler-Portraet. Ziel Media/NarratorBG_<volk>.tga (512 x 512, Kreis
// wie Narrator_<volk>: Mitte 256 | 250, sichtbarer Radius 176, 4 px Ueberstand unter dem Rahmen), rund maskiert, Vignette zum Rand
// (je Volk `vignette` = Staerke am Rand, `dim` = leichte Abdunklung ueber alles; helle Szenen Zwerg/Gnom und der einfarbige Ork-Boden
// dunkler, damit sich die Figur abhebt).
export const NARRATOR_BG = {
  human: { vignette: 0.45 }, dwarf: { vignette: 0.6, dim: 0.2 }, nightelf: { vignette: 0.45 }, gnome: { vignette: 0.6, dim: 0.2 },
  orc: { vignette: 0.55, dim: 0.12 }, undead: { vignette: 0.45 }, tauren: { vignette: 0.45 }, troll: { vignette: 0.45 },
  skyborne: { vignette: 0.45 },
};
const narratorBgTexture = (id) => ({
  name: `NarratorBG_${id}`, w: 512, h: 512, source: `art/toast/narrator_bg_${id}_v1.jpg`,
  html: () => {
    const b = NARRATOR_BG[id];
    return page(512, 512,
      `<div style="position:absolute;left:${256 - 180}px;top:${250 - 180}px;width:360px;height:360px;border-radius:50%;overflow:hidden;background:url(${artUrl(`toast/narrator_bg_${id}_v1.jpg`)}) center / cover no-repeat">` +
      `<div style="position:absolute;inset:0;background:radial-gradient(circle at 50% 50%, rgba(0,0,0,${b.dim || 0}) 0%, rgba(0,0,0,${b.dim || 0}) 55%, rgba(0,0,0,${b.vignette}) 100%)"></div></div>`);
  },
});

export const TEXTURES = [
  { name: "Book", w: 1024, h: 1024, html: () => ART(BOOK_FILE, BOOK_CROP, 1024, 1024), post: BOOK_KEY },
  ...PAGE_IDS.flatMap((id) => [pageTexture(id, "l"), pageTexture(id, "r")]),
  // Medaillen (Etappe 2): Motiv-Atlas und Rahmen-Atlas; der fruehere Altbild-Atlas (SEALS_HTML, SEAL_ATLAS) wird nicht mehr gerendert
  { name: "Seals", w: SEAL_MOTIF_ATLAS.cols * SEAL_MOTIF_ATLAS.cell, h: SEAL_MOTIF_ATLAS.rows * SEAL_MOTIF_ATLAS.cell, html: SEAL_MOTIFS_HTML },
  { name: "SealFrames", w: SEAL_FRAME_ATLAS.cols * SEAL_FRAME_ATLAS.cell, h: SEAL_FRAME_ATLAS.rows * SEAL_FRAME_ATLAS.cell, html: SEAL_FRAMES_HTML, post: SEAL_FRAMES_KEY, source: "art/seals/v2/frame_bronze.jpg" },
  { name: "Toast", w: 512, h: 256, html: () => ART(TOAST_CROP.file, TOAST_CROP, 512, 256), post: TOAST_KEY },
  { name: "WelcomeCard", w: 1024, h: 512, html: () => ART(WELCOME_CARD_CROP.file, WELCOME_CARD_CROP, 1024, 512), post: WELCOME_CARD_KEY, source: "art/" + WELCOME_CARD_CROP.file },
  { name: "WelcomeBack", w: 1024, h: 512, html: () => ART(WELCOME_BACK_CROP.file, WELCOME_BACK_CROP, 1024, 512), post: fireNoteKey, source: "art/" + WELCOME_BACK_CROP.file },
  ...Object.entries(NARRATOR_CUTOUTS).flatMap(([id, c]) => ["In", "Out"].map((m) => ({ name: `NarratorFig${m}_${id}`, w: 512, h: 512, html: () => ART(c.file, c, 512, 512), post: (rgba, w, h) => cutoutKey(rgba, w, h, c, m.toLowerCase()), source: "art/" + c.file }))),
  ...NARRATOR_IDS.map(narratorTexture),
  ...Object.keys(NARRATOR_BG).map(narratorBgTexture),
  { name: "ZoneSeal", w: 128, h: 128, html: ZONE_SEAL_HTML, post: ZONE_SEAL_KEY, source: "art/" + ZONE_SEAL.file },
  // Knopf "Gesamtreise": Plakette mit goldenem Lorbeer (Gemini, art/journal/btn_gesamtreise.jpg, 2752 x 1536, weisser Grund),
  // Zuschnitt 2600 x 1300 (Plakette x 85..2665, y 150..1400 plus Rand), 2 : 1 -> 256 x 128. Fehlt die Quelldatei und auch die
  // TGA, wird die Textur uebersprungen (`--check` bleibt gruen); die Oberflaeche braucht dann Playback.PIN_ART = false.
  ...FIRE_NOTE_IDS.map(fireNoteTexture),
  { name: "TodoPad", w: 512, h: 1024, html: () => ART(TODO_PAD.file, TODO_PAD, 512, 1024), post: TODO_PAD_KEY, source: "art/journal/" + TODO_PAD.file },
  {
    // Zeichen des Notizzettels (journal/TodoTracker.lua, Theme.TODO_MARKS): vier Zellen 32 x 32, weiss, im Spiel getoent (Sepia-Tinte
    // bzw. hell im Stil "Schlicht"). 0 = Schloss zu, 1 = Schloss offen (Buegel gehoben, links offen), 2 = Griff (drei Schraegstriche
    // wie eine Federzeichnung), 3 frei. Gezeichnet wie mit der Feder: Buegel als Bogen, Koerper mit Schluesselloch.
    name: "TodoMarks",
    w: 128,
    h: 32,
    html: () => {
      const ink = 'stroke="#fff" fill="none" stroke-linecap="round" stroke-linejoin="round"';
      const body = (dx) => `<path d="M${dx + 8.5} 15.5 h15 a1.5 1.5 0 0 1 1.5 1.5 v9 a2 2 0 0 1 -2 2 h-14 a2 2 0 0 1 -2 -2 v-9 a1.5 1.5 0 0 1 1.5 -1.5 z" fill="#fff"/>
<path d="M${dx + 16} 19.2 a1.9 1.9 0 1 1 -0.01 0 z M${dx + 15.2} 21.6 h1.6 l0.5 3.6 h-2.6 z" fill="#000"/>`;
      const closed = `${body(0)}<path d="M10.5 15.5 v-4 a5.5 5.5 0 0 1 11 0 v4" ${ink} stroke-width="2.6"/>`;
      const open = `${body(32)}<path d="M53.5 15.5 v-8 a5.5 5.5 0 0 0 -11 0 v1.5" ${ink} stroke-width="2.6"/>`;
      const grip = [[78, 28, 92, 14, 2.4], [83, 28, 92, 19, 2.2], [88, 28, 92, 24, 2]]
        .map(([a, b, c, d, wd]) => `<path d="M${a} ${b} L${c} ${d}" ${ink} stroke-width="${wd}"/>`).join("");
      return page(128, 32, `<svg width="128" height="32" viewBox="0 0 128 32" style="position:absolute;left:0;top:0">
<g>${closed}${open}${grip}</g></svg>`);
    },
    post: (rgba, w, h) => {
      // Schluesselloch (schwarz gezeichnet) wird durchsichtig, alles Uebrige weiss mit Deckkraft = Helligkeit
      for (let i = 0; i < w * h; i++) {
        const o = i * 4;
        const v = Math.round((rgba[o] + rgba[o + 1] + rgba[o + 2]) / 3);
        rgba[o + 3] = Math.round((rgba[o + 3] * v) / 255);
        rgba[o] = rgba[o + 1] = rgba[o + 2] = 255;
      }
      return rgba;
    },
  },
  { name: "BtnTotal", w: 256, h: 128, html: () => ART(BTN_TOTAL.file, BTN_TOTAL, 256, 128), post: BTN_TOTAL_KEY, source: "art/journal/" + BTN_TOTAL.file },
  {
    // Dropdown-Pfeil (Kampf-Seite, Meistgejagt-Knopf): weisses Dreieck nach unten, per SetVertexColor eingefaerbt; offen = gespiegelt
    name: "Arrow",
    w: 32,
    h: 32,
    html: () => page(32, 32, `<svg width="32" height="32" viewBox="0 0 32 32" style="position:absolute;left:0;top:0"><path d="M4.5 9.5 H27.5 L16 24.5 Z" fill="#fff" stroke="#fff" stroke-width="1.5" stroke-linejoin="round"/></svg>`),
  },
  {
    // Schraffur (Stufenfluss-Saeulen der Chronik): weisse Diagonalstriche mit leicht wechselnder Staerke, nahtlos kachelbar (die Linien
    // laufen ueber den Rand und kehren gegenueber wieder ein); wird im Spiel gekachelt (Toast/Columns: Kachel 24 px) und per SetVertexColor getoent
    name: "Hatch",
    w: 64,
    h: 64,
    html: () => {
      const strokes = [[16, 2.4], [48, 1.8], [80, 2.2], [112, 1.6]]
        .map(([c, wd]) => `<path d="M-8 ${c + 8} L${72} ${c - 72}" stroke="#fff" stroke-width="${wd}" stroke-linecap="round" fill="none"/>`)
        .join("");
      return page(64, 64, `<svg width="64" height="64" viewBox="0 0 64 64" style="position:absolute;left:0;top:0">${strokes}</svg>`);
    },
  },
  // Glow/Disc: weisse Hilfstexturen (weiche Raender; Faerbung per SetVertexColor), genutzt von Wiedergabe-Knoepfen und Kampf-Seite
  {
    name: "Glow",
    w: 128,
    h: 128,
    html: () =>
      page(128, 128, `<div style="position:absolute;inset:0;border-radius:50%;background:radial-gradient(circle closest-side, rgba(255,255,255,1) 0%, rgba(255,255,255,0.62) 22%, rgba(255,255,255,0.26) 50%, rgba(255,255,255,0.07) 78%, rgba(255,255,255,0) 100%)"></div>`),
  },
  {
    // Maske (nur Alpha zaehlt): Kreis mit sehr weichem Rand, deckt das Medaillon (SEAL_PAD-Rand bleibt aussen)
    name: "Disc",
    w: 64,
    h: 64,
    html: () => page(64, 64, `<div style="position:absolute;inset:3px;border-radius:50%;background:#ffffff;filter:blur(1px)"></div>`),
  },
  {
    // Kill-Symbol der Reise-Karte (Rueckfall, bis das gemalte SwordIcon da ist): Schwert, Spitze oben rechts, dunkle Tinte,
    // voll deckend, mit hellem Pergament-Rand (Lesbarkeit auf Karte und Route). Farbig gerendert und im Spiel ungetoent
    // (Vertexfarbe weiss); die linke Klingenhaelfte ist etwas heller (Grat), das gibt Tiefe
    name: "Sword",
    w: 64,
    h: 64,
    html: () => {
      const parts = `<path d="M32 2 L36.2 12 V40 H32 Z"/><path d="M32 2 L27.8 12 V40 H32 Z"/><rect x="18.5" y="39.5" width="27" height="5" rx="2.2"/><rect x="29.6" y="44" width="4.8" height="10.5" rx="1.2"/><circle cx="32" cy="57.2" r="3.6"/>`;
      return page(
        64,
        64,
        `<svg width="64" height="64" viewBox="0 0 64 64" style="position:absolute;left:0;top:0"><g transform="translate(32 32) rotate(45) scale(1.2) translate(-32 -32)"><g fill="#f4ebd6" stroke="#f4ebd6" stroke-width="6.5" stroke-linejoin="round">${parts}</g><g fill="#2b2118" stroke="#2b2118" stroke-width="0.8" stroke-linejoin="round">${parts}</g><path d="M32 2 L27.8 12 V40 H32 Z" fill="#6a5238"/></g></svg>`,
      );
    },
  },
  {
    // Gemalte Schwert-Ikone (Gemini, art/journal/icon_sword.jpg, weisser Grund): kraeftiges kleines Schwert fuer die Reise-Karte,
    // im Spiel ungetoent und voll deckend. Zuschnitt quadratisch um das Schwert (SWORD_ICON), 2048 -> 64 px. Der weisse
    // Grund wird nur vom Rand aus freigestellt (keyWhite), die helle Klinge innen bleibt deckend (dunkler Umriss schliesst sie ein).
    // Fehlt die Quelldatei und auch die TGA, wird die Textur uebersprungen (`--check` bleibt gruen); die Karte nimmt dann
    // Sword.tga (Theme.HAS_SWORD_ICON = false).
    name: "SwordIcon",
    w: 64,
    h: 64,
    html: () => ART(SWORD_ICON.file, SWORD_ICON, 64, 64),
    post: SWORD_ICON_KEY,
    source: "art/journal/" + SWORD_ICON.file,
  },
  {
    // Kill-Marke der Karte: Zelle 12 (gekreuzte Schwerter) des Symbolbogens, 128 x 128, im Spiel ungetoent und voll deckend (mit dem
    // Schatten der Vorlage). Fehlt die Quelldatei und auch die TGA, wird die Textur uebersprungen (`--check` bleibt gruen); die Karte
    // nimmt dann SwordIcon/Sword (Theme.HAS_MAP_KILL = false).
    name: "MapKill",
    w: 128,
    h: 128,
    rw: MAP_ICONS.srcW,
    rh: MAP_ICONS.srcH,
    html: MAP_ICONS_HTML,
    post: (rgba, w, h) => cutSingle(rgba, w, h, "kill", 128),
    source: "art/journal/" + MAP_ICONS.file,
  },
  {
    // Kartenzeichen der Reise-Karte: Atlas 512 x 512, 4 x 4 Kacheln zu 128 px (12 belegt, Reihenfolge = Theme.MAP_ICONS). Fehlt die
    // Quelldatei und auch die TGA, wird die Textur uebersprungen; die Karte nimmt dann den alten Atlas Markers (Theme.HAS_MAP_ICONS = false).
    name: "MapIcons",
    w: MAP_ICON_ATLAS.w,
    h: MAP_ICON_ATLAS.h,
    rw: MAP_ICONS.srcW,
    rh: MAP_ICONS.srcH,
    html: MAP_ICONS_HTML,
    post: (rgba, w, h) => cutAtlas(rgba, w, h),
    source: "art/journal/" + MAP_ICONS.file,
  },
  {
    // Spielerposition (Zelle 11, Pfeil nach oben): eigene Datei, damit SetRotation (Blickrichtung) die ganze Textur dreht.
    name: "MapCurrent",
    w: 128,
    h: 128,
    rw: MAP_ICONS.srcW,
    rh: MAP_ICONS.srcH,
    html: MAP_ICONS_HTML,
    post: (rgba, w, h) => cutSingle(rgba, w, h, "current", 128),
    source: "art/journal/" + MAP_ICONS.file,
  },
  {
    // Kill-Embleme (Kampf-Seite, Kaesten Gewoehnl./Elite/Rar/Boss): Atlas 512 x 512 aus 4 Kacheln zu 256 px (Reihenfolge = Theme.EMBLEMS).
    // Fehlt die Quelldatei und auch die TGA, wird die Textur uebersprungen (`--check` bleibt gruen); die Seite zeigt dann die Ringe
    // (Theme.HAS_KILL_EMBLEMS = false).
    name: "KillEmblems",
    w: EMBLEM_ATLAS.w,
    h: EMBLEM_ATLAS.h,
    rw: KILL_EMBLEMS.srcW,
    rh: KILL_EMBLEMS.srcH,
    html: KILL_EMBLEMS_HTML,
    post: (rgba, w, h) => cutEmblems(rgba, w, h),
    source: "art/journal/" + KILL_EMBLEMS.file,
  },
  { name: "Bookmarks", w: 512, h: 1024, html: BOOKMARKS_HTML, post: BOOKMARKS_KEY, source: "art/journal/" + BOOKMARK_CROP.file },
  { name: "BookmarksBronze", w: TAB_BAND_ATLAS.w, h: TAB_BAND_ATLAS.h, html: TAB_BAND_HTML, post: TAB_BAND_KEY, source: "art/journal/" + TAB_BAND_CROP.file },
  { name: "Markers", w: 256, h: 256, html: MARKERS_HTML },
  // N1: Pinnadel einer Notiz (Reise-Karte, Notizliste): roter Glaskopf mit Glanz, Stahlnadel schraeg nach unten links, die Spitze
  // sitzt in der unteren linken Ecke (Anker im Spiel: Theme.NOTE_PIN.tipX/tipY), weicher Schatten. Ungetoent, voll deckend.
  { name: "NotePin", w: 64, h: 64, html: NOTE_PIN_HTML },
  // Offene Quests (Rubrik "Offen" unter Quests): Questgeber-Zeichen "!" wie im Spiel, aber gemalt im Stil der Kartensymbole: goldenes
  // Ausrufezeichen mit Verlauf, dunkler Tuscheumriss, weicher Schatten. Ungetoent; grau (gesperrt) per SetDesaturated + Alpha im Spiel.
  { name: "QuestMark", w: 64, h: 64, html: QUEST_MARK_HTML },
  {
    name: "Grain",
    w: 256,
    h: 256,
    html: () => page(256, 256, `<svg width="256" height="256" style="position:absolute;left:0;top:0"><rect width="256" height="256" filter="url(#paperNoise)"/></svg>`),
  },
  {
    name: "Tape",
    w: 128,
    h: 64,
    html: () =>
      page(128, 64, `<div style="position:absolute;left:10px;top:14px;width:108px;height:34px;background:rgba(226,214,176,0.82);transform:rotate(2deg);box-shadow:0 1px 3px rgba(0,0,0,0.18)"></div>`),
  },
  {
    // Zettel "leicht gedreht" (Design): Papier und Schatten sind gedreht, der Text im Fenster bleibt gerade.
    // Feste Breite/Hoehe statt right/bottom: der Headless-Viewport ist breiter als das Fenster, right: 16px ging verloren.
    name: "Card",
    w: 256,
    h: 512,
    html: () =>
      page(256, 512, `<div style="position:absolute;left:16px;top:12px;width:224px;height:476px;background:#f8f1e0;border-radius:2px;transform:rotate(-1.3deg);transform-origin:50% 50%;box-shadow:0 8px 18px rgba(60,35,15,0.30), 0 1px 2px rgba(60,35,15,0.25)"></div>`),
  },
  { name: "MinimapIcon", w: 128, h: 128, html: () => ART(MINIMAP_CROP.file, MINIMAP_CROP, 128, 128), post: MINIMAP_KEY, source: "art/minimap_nr5_ref.png" },
  { name: "RoundRect", w: 64, h: 64, html: ROUNDRECT_HTML },
  { name: "RoundRing", w: 64, h: 64, html: RING_HTML },
  {
    // Maske der Karte (nur Alpha zaehlt): weisse Flaeche, deren Rand weich und leicht unregelmaessig ins Transparente
    // auslaeuft. Ueber die Kartenansicht und ueber die Kartenkunst gespannt -> kein hartes Rechteck auf dem Pergament.
    name: "MapFade",
    w: 256,
    h: 256,
    html: () =>
      page(256, 256, `<svg width="256" height="256" style="position:absolute;left:0;top:0"><defs><filter id="fade" x="-20%" y="-20%" width="140%" height="140%"><feTurbulence type="fractalNoise" baseFrequency="0.035" numOctaves="2" seed="9" result="n"/><feDisplacementMap in="SourceGraphic" in2="n" scale="16" xChannelSelector="R" yChannelSelector="G"/><feGaussianBlur stdDeviation="9"/></filter></defs><rect x="30" y="30" width="196" height="196" rx="22" fill="#ffffff" filter="url(#fade)"/></svg>`),
  },
  {
    // Maske der Karte (nur Alpha zaehlt): ganz weiss, an allen vier Raendern weich (Smoothstep) ins Transparente
    // auslaufend. Wird ueber die feste Kartenflaeche gespannt: die Karte laeuft an den Seitenraendern ins Papier aus, ohne
    // Rahmen und ohne Linie. Aus Rechnung erzeugt (kein Browser noetig).
    name: "PageFade",
    w: 256,
    h: 256,
    pixels: () => fadePixels(256, 256, PAGE_FADE),
  },
  {
    name: "Dash",
    w: 16,
    h: 4,
    html: () => page(16, 4, `<div style="position:absolute;left:0;top:0;width:9px;height:4px;background:#ffffff"></div>`),
  },
  // Kampf-Seite (Nachtrag K1): Tintenstrich der Strichliste (laengs = u, fuer Line-Objekte; Feder setzt links breit auf
  // und hebt rechts duenn ab) und Grabstein des Graeberfelds. Weiss auf durchsichtig, im Spiel per SetVertexColor in Tinte.
  { name: "Stroke", w: 64, h: 16, pixels: () => strokePixels(64, 16) },
  { name: "Grave", w: 32, h: 32, pixels: () => gravePixels(32, 32) },
  // Momente-Seite (Nachtrag M1): Zeichen je Momentart (Gemini-Bild art/journal/moment_icons.jpg, freigestellt) und Balken der
  // Spielzeit-Uhr (aus Rechnung). Die Zettel selbst nutzen den Notizzettel (TodoPad).
  { name: "MomentIcons", w: 512, h: 256, html: () => MOMENT_ICONS_HTML(), post: (rgba, w, h) => MOMENT_ICONS_KEY(rgba, w, h) },
  { name: "ClockBar", w: 32, h: 128, pixels: () => barPixels(32, 128) },
  ...DIARY_TEXTURES,
];

// ---------------------------------------------------------------------------------------------------------------
// Momente-Seite (Nachtrag M1). Zuschnitte einmal gemessen (28.10.2026, Suchlauf im Browser: Bounding-Box aller Pixel mit
// Farbsumme < 700, bei den Zeichen < 690), jeweils mit etwas Rand.

// Zeichen je Momentart (art/journal/moment_icons.jpg, 2528 x 1696, 3 x 2 Raster). Atlas Media/MomentIcons.tga 512 x 256,
// Zellen zu 128 px, 3 Spalten genutzt (4. Spalte leer, Zweierpotenz). Reihenfolge = Theme.MOMENT_ICONS (ein Test haelt
// beide gleich). Je Zeichen die Mitte seiner Bounding-Box [cx, cy]; Zuschnitt ein Quadrat MOMENT_ICON_SIDE darum (gleicher
// Massstab fuer alle sechs; das breiteste Zeichen, das Buch mit 549 px, passt mit Rand hinein).
export const MOMENT_ICON_IDS = ["level", "fight", "death", "find", "place", "memory"];
export const MOMENT_ICON_CENTER = {
  level: [460, 435], // Banner mit Stern: x 261..660, y 179..692
  fight: [1265, 452], // gekreuzte Schwerter: x 1027..1504, y 207..698
  death: [2117, 441], // Schaedel auf Schild: x 1937..2298, y 201..681
  find: [424, 1275], // Truhe: x 199..649, y 1043..1508
  place: [1281, 1249], // Kompass und Karte: x 1071..1492, y 1011..1488
  memory: [2119, 1262], // Buch mit Feder: x 1845..2393, y 1027..1497
};
export const MOMENT_ICON_SIDE = 600;
export const MOMENT_ICON_ATLAS = { cols: 3, cell: 128, w: 512, h: 256 };
function MOMENT_ICONS_HTML() {
  const a = MOMENT_ICON_ATLAS;
  const z = a.cell / MOMENT_ICON_SIDE;
  const src = artUrl("moment_icons.jpg");
  const cells = MOMENT_ICON_IDS.map((id, i) => {
    const [cx, cy] = MOMENT_ICON_CENTER[id];
    const x0 = cx - MOMENT_ICON_SIDE / 2;
    const y0 = cy - MOMENT_ICON_SIDE / 2;
    return `<div style="position:absolute;left:${(i % a.cols) * a.cell}px;top:${Math.floor(i / a.cols) * a.cell}px;width:${a.cell}px;height:${a.cell}px;overflow:hidden;background:#fff url(${src}) ${-x0 * z}px ${-y0 * z}px / ${2528 * z}px ${1696 * z}px no-repeat"></div>`;
  });
  return page(a.w, a.h, cells.join(""));
}
// Freistellung je Zelle (Flood-Fill vom Zellenrand aus) wie beim Siegel-Atlas; die leere 4. Spalte bleibt durchsichtig
function MOMENT_ICONS_KEY(rgba, w, h) {
  const c = MOMENT_ICON_ATLAS.cell;
  for (let i = 0; i < MOMENT_ICON_IDS.length; i++) {
    const cx = (i % MOMENT_ICON_ATLAS.cols) * c;
    const cy = Math.floor(i / MOMENT_ICON_ATLAS.cols) * c;
    const cell = new Uint8Array(c * c * 4);
    for (let y = 0; y < c; y++) cell.set(rgba.subarray(((cy + y) * w + cx) * 4, ((cy + y) * w + cx + c) * 4), y * c * 4);
    keyWhite(cell, c, c, { from: 706, to: 748 });
    for (let y = 0; y < c; y++) rgba.set(cell.subarray(y * c * 4, (y + 1) * c * 4), ((cy + y) * w + cx) * 4);
  }
  for (let y = 0; y < h; y++) for (let x = MOMENT_ICON_ATLAS.cols * c; x < w; x++) rgba[(y * w + x) * 4 + 3] = 0;
  return rgba;
}

// Balken der Spielzeit-Uhr: weiss, mit weichem Rand (gut 1 Texturpixel) und durchsichtigem Saum ringsum (BAR_PAD). Gedreht
// mischt der Client die Randpixel bilinear: glatte Kanten statt der Treppen einer gedrehten Farbflaeche. Die Uhr rechnet
// den Saum zurueck (Widgets.NewRing opts.tex / opts.texPad = Saum-Anteil je Seite, hier 8/32 bzw. 8/128).
export const BAR_PAD = { x: 8, y: 8 }; // Texturpixel Saum je Seite (32 x 128 -> Balken 16 x 112)
export function barPixels(w, h) {
  const rgba = Buffer.alloc(w * h * 4, 255);
  const half = (w - 2 * BAR_PAD.x) / 2;
  const y0 = BAR_PAD.y;
  const y1 = h - BAR_PAD.y;
  const r = 3; // leicht gerundete Enden
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const dx = half - Math.abs(x + 0.5 - w / 2); // Abstand zur Kante, positiv = innen
      const dy = Math.min(y + 0.5 - y0, y1 - (y + 0.5));
      let d = Math.min(dx, dy);
      if (dx < r && dy < r) d = r - Math.hypot(r - dx, r - dy);
      rgba[(y * w + x) * 4 + 3] = Math.round(255 * Math.max(0, Math.min(1, (d + 0.6) / 1.6)));
    }
  }
  return rgba;
}

const clamp01 = (v) => Math.max(0, Math.min(1, v));

/** Breite und Hoehe eines JPEG aus dem SOF-Kopf ({ w, h } | null) */
export function jpegSize(buf) {
  if (buf.length < 4 || buf[0] !== 0xff || buf[1] !== 0xd8) return null;
  let pos = 2;
  while (pos + 9 < buf.length) {
    if (buf[pos] !== 0xff) {
      pos++;
      continue;
    }
    const m = buf[pos + 1];
    if (m === 0xd8 || m === 0x01 || (m >= 0xd0 && m <= 0xd7) || m === 0xff) {
      pos += m === 0xff ? 1 : 2;
      continue;
    }
    const len = buf.readUInt16BE(pos + 2);
    if (m >= 0xc0 && m <= 0xcf && m !== 0xc4 && m !== 0xc8 && m !== 0xcc) {
      return { h: buf.readUInt16BE(pos + 5), w: buf.readUInt16BE(pos + 7) };
    }
    pos += 2 + len;
  }
  return null;
}

/** Tintenstrich: Breite laengs veraenderlich (Aufsetzen, leichtes Schwellen, duenner Abstrich), weiche Kanten */
export function strokePixels(w, h) {
  const rgba = Buffer.alloc(w * h * 4, 255);
  for (let x = 0; x < w; x++) {
    const u = (x + 0.5) / w;
    const head = u < 0.12 ? 0.75 + 0.25 * Math.sin((u / 0.12) * Math.PI * 0.5) : 1;
    const tail = u > 0.7 ? 1 - 0.7 * ((u - 0.7) / 0.3) ** 1.4 : 1;
    const half = 0.34 * head * tail * (1 + 0.06 * Math.sin(u * 17));
    const ink = 0.88 + 0.12 * Math.sin(u * 9 + 1);
    const ends = clamp01(u / 0.03) * clamp01((1 - u) / 0.05);
    for (let y = 0; y < h; y++) {
      const d = Math.abs((y + 0.5) / h - 0.5);
      const a = clamp01((half - d) * h * 0.9) * ink * ends;
      rgba[(y * w + x) * 4 + 3] = Math.round(255 * a);
    }
  }
  return rgba;
}

/** Grabstein: runder Kopf, Sockel, eingeritztes Kreuz; Flaeche halb deckend, Umriss und Kreuz voll */
export function gravePixels(w, h) {
  const rgba = Buffer.alloc(w * h * 4, 255);
  const sx = w / 32;
  const sy = h / 32;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const px = (x + 0.5) / sx;
      const py = (y + 0.5) / sy;
      // Abstand zur Kante (positiv = innen) von Stein (Rechteck + Halbkreis) und Sockel
      const body = py < 13 ? 8 - Math.hypot(px - 16, py - 13) : Math.min(px - 8, 24 - px, 27 - py);
      const base = Math.min(px - 5, 27 - px, py - 26, 29.5 - py);
      const inside = Math.max(body, base);
      const cover = clamp01(inside + 0.5);
      const rim = clamp01(1.9 - Math.abs(inside - 0.9));
      const cross = Math.max(
        Math.min(clamp01(0.9 - Math.abs(px - 16) + 0.5), clamp01(Math.min(py - 9.5, 20.5 - py) + 0.5)),
        Math.min(clamp01(0.85 - Math.abs(py - 13.6) + 0.5), clamp01(Math.min(px - 12.3, 19.7 - px) + 0.5)),
      );
      const a = cover * Math.max(0.42, rim, py < 26 ? cross : 0);
      rgba[(y * w + x) * 4 + 3] = Math.round(255 * clamp01(a));
    }
  }
  return rgba;
}

/** Blendenbreite (Anteil der Kantenlaenge) der festen Kartenrand-Maske PageFade */
export const PAGE_FADE = 0.075;

/** weisse Flaeche, Alpha = Smoothstep des Randabstands (Anteil fade der Kantenlaenge) in x und y */
export function fadePixels(w, h, fade) {
  const rgba = Buffer.alloc(w * h * 4, 255);
  const edge = (i, n) => {
    const u = Math.min((i + 0.5) / n, 1 - (i + 0.5) / n) / fade;
    const c = Math.max(0, Math.min(1, u));
    return c * c * (3 - 2 * c);
  };
  for (let y = 0; y < h; y++) {
    const ay = edge(y, h);
    for (let x = 0; x < w; x++) rgba[(y * w + x) * 4 + 3] = Math.round(255 * edge(x, w) * ay);
  }
  return rgba;
}

// ---------------------------------------------------------------------------------------------------------------
// Sperrflaechen der gemalten Verzierungen (B2a): `node scripts/render-media.mjs --keepout` -> journal/DecorKeepout.lua
// (Theme.DECOR_KEEPOUT[reiter] = { L = {{x, y, w, h} ...}, R = {...} }, Pixel der Seite wie die Seiten-Layouts: x von der linken
// Kante der jeweiligen Seite (538 breit), y von der Oberkante der Doppelseite (666 hoch)) und Vorschaubilder tests/screens/
// b2-keepout-<reiter>.png. Das Seitenpaar wird dafuer in Spielgroesse (Frame.paperRect: 1076 x 693, Oberkante 21 px ueber der
// Doppelseite) gerendert, also ohne Gammakurve und ohne V-Schnitt. Erkennung (detectDecor):
//   1. Papierflaeche = alles, was vom Rand aus nicht weiss ist (keyWhite), um `edge` px seitlich bzw. `edgeY` px oben/unten eingezogen: Papierrand, Randschatten und
//      der Rand der Blattschnitte zaehlen nie als Verzierung; ebenso das Falzband (`foldBand` px beiderseits der Falzlinie).
//   2. Helligkeit durch ein getrenntes Modell a(x) * b(y) teilen (je Spalte/Zeile ein hohes Quantil des Papiers): nimmt den
//      Falzschatten und die Woelbung der Blatthaelften (Verlauf ueber die ganze Hoehe/Breite) heraus.
//   3. Rest-Hintergrund = Weichzeichnung des Papiers ohne bereits erkannte Pixel (mehrere Durchgaenge); Abweichung dunkler als
//      `dark` bzw. heller als `bright` (relativ), dazu Farbabstand (Siegelrot, Flecken) = Verzierung.
//   4. Kleine Reste weg (Mindestflaeche), um `dilate` px dilatiert (Nachbarn verschmelzen), Zusammenhangskomponenten; grosse,
//      duenne (diagonale) Gebilde werden per Halbierung in Bloecke zerlegt (Fuellgrad < `fill`), damit die Sperrflaeche nicht das
//      ganze Umfeld einer Ranke sperrt. Ergebnis je Block: das enge Rechteck um die dilatierten Pixel.
export const KEEPOUT = {
  w: 1076, h: 693, top: 21, half: 538, pageH: 666,
  edge: 12, edgeY: 24, foldBand: 46, dilate: 6, minArea: 30, dark: 0.09, bright: 0.10, chroma: 0.09, fill: 0.5, minSide: 28, blur: 28,
};

/** Mittelwert der Werte (nur wo mask) im Fenster (2r+1)^2, ueber Integralbilder; NaN, wo das Fenster keine Maskenpixel hat */
function boxMean(vals, mask, w, h, r) {
  const W = w + 1;
  const sv = new Float64Array(W * (h + 1));
  const sm = new Float64Array(W * (h + 1));
  for (let y = 0; y < h; y++) {
    let rv = 0;
    let rm = 0;
    for (let x = 0; x < w; x++) {
      const i = y * w + x;
      if (mask[i]) {
        rv += vals[i];
        rm += 1;
      }
      sv[(y + 1) * W + x + 1] = sv[y * W + x + 1] + rv;
      sm[(y + 1) * W + x + 1] = sm[y * W + x + 1] + rm;
    }
  }
  const out = new Float32Array(w * h);
  for (let y = 0; y < h; y++) {
    const y0 = Math.max(0, y - r);
    const y1 = Math.min(h, y + r + 1);
    for (let x = 0; x < w; x++) {
      const x0 = Math.max(0, x - r);
      const x1 = Math.min(w, x + r + 1);
      const n = sm[y1 * W + x1] - sm[y0 * W + x1] - sm[y1 * W + x0] + sm[y0 * W + x0];
      const s = sv[y1 * W + x1] - sv[y0 * W + x1] - sv[y1 * W + x0] + sv[y0 * W + x0];
      out[y * w + x] = n > 0 ? s / n : NaN;
    }
  }
  return out;
}

/** Rechteck-Dilatation (Maske 0/1) um rx x ry Pixel, getrennt in x und y (Abstand zum naechsten gesetzten Pixel links/rechts bzw. oben/unten) */
function dilateBox(mask, w, h, rx, ry = rx) {
  const tmp = new Uint8Array(w * h);
  const out = new Uint8Array(w * h);
  const left = new Int32Array(Math.max(w, h));
  for (let y = 0; y < h; y++) {
    const row = y * w;
    let l = -1e9;
    for (let x = 0; x < w; x++) {
      if (mask[row + x]) l = x;
      left[x] = l;
    }
    let rr = 1e9;
    for (let x = w - 1; x >= 0; x--) {
      if (mask[row + x]) rr = x;
      if (x - left[x] <= rx || rr - x <= rx) tmp[row + x] = 1;
    }
  }
  for (let x = 0; x < w; x++) {
    let u = -1e9;
    for (let y = 0; y < h; y++) {
      if (tmp[y * w + x]) u = y;
      left[y] = u;
    }
    let d = 1e9;
    for (let y = h - 1; y >= 0; y--) {
      if (tmp[y * w + x]) d = y;
      if (y - left[y] <= ry || d - y <= ry) out[y * w + x] = 1;
    }
  }
  return out;
}

/** Rechteck-Erosion (Maske 0/1) um rx x ry Pixel; ausserhalb des Bildes gilt als leer */
function erodeBox(mask, w, h, rx, ry = rx) {
  const inv = new Uint8Array(w * h);
  for (let i = 0; i < w * h; i++) inv[i] = mask[i] ? 0 : 1;
  const d = dilateBox(inv, w, h, rx, ry);
  const out = new Uint8Array(w * h);
  for (let y = ry; y < h - ry; y++) for (let x = rx; x < w - rx; x++) out[y * w + x] = d[y * w + x] ? 0 : 1;
  return out;
}

const decorQuantile = (arr, q) => {
  if (arr.length === 0) return NaN;
  const a = Float32Array.from(arr).sort();
  return a[Math.min(a.length - 1, Math.floor(q * a.length))];
};

/** NaN-Luecken eines Profils mit dem naechsten gueltigen Nachbarn fuellen */
function fillGaps(v) {
  let last = NaN;
  for (let i = 0; i < v.length; i++) if (Number.isNaN(v[i])) v[i] = last; else last = v[i];
  last = NaN;
  for (let i = v.length - 1; i >= 0; i--) if (Number.isNaN(v[i])) v[i] = last; else last = v[i];
}

/**
 * Verzierungen auf einer Doppelseite erkennen. rgba = Bild (w x h) der Doppelseite auf weissem Grund. Liefert
 * { rects: [{ x, y, w, h }] in Bildpixeln, paper: Papierflaeche (um edge eingezogen), flag: erkannte Pixel }.
 */
export function detectDecor(rgba, w, h, opt = {}) {
  const o = { ...KEEPOUT, ...opt };
  const n = w * h;
  // 1. Papierflaeche
  const key = Uint8Array.from(rgba);
  keyWhite(key, w, h, SPREAD_KEY);
  const raw = new Uint8Array(n);
  for (let i = 0; i < n; i++) raw[i] = key[i * 4 + 3] > 200 ? 1 : 0;
  const paper = erodeBox(raw, w, h, o.edge, o.edgeY);
  // Falzband: der Schatten am Falz hat steile, von der Hoehe abhaengige Verlaeufe, die kein Modell sauber trifft; der Satzspiegel haelt 40 px Abstand
  for (let y = 0; y < h; y++) for (let x = Math.max(0, o.half - o.foldBand); x < Math.min(w, o.half + o.foldBand); x++) paper[y * w + x] = 0;
  // 2. Helligkeit und Farbe, getrenntes Modell
  const L = new Float32Array(n);
  const CR = new Float32Array(n); // Rot - Gruen relativ zur Helligkeit (Siegelrot)
  const CB = new Float32Array(n); // Gruen - Blau relativ zur Helligkeit (Flecken, Gelb)
  for (let i = 0; i < n; i++) {
    const r = rgba[i * 4];
    const g = rgba[i * 4 + 1];
    const b = rgba[i * 4 + 2];
    L[i] = 0.299 * r + 0.587 * g + 0.114 * b;
    CR[i] = (r - g) / Math.max(40, L[i]);
    CB[i] = (g - b) / Math.max(40, L[i]);
  }
  const ax = new Float32Array(w).fill(1);
  const by = new Float32Array(h).fill(1);
  const col = [];
  for (let it = 0; it < 3; it++) {
    for (let x = 0; x < w; x++) {
      col.length = 0;
      for (let y = 0; y < h; y++) if (paper[y * w + x]) col.push(L[y * w + x] / by[y]);
      ax[x] = col.length >= 40 ? decorQuantile(col, 0.7) : NaN;
    }
    fillGaps(ax);
    for (let y = 0; y < h; y++) {
      col.length = 0;
      for (let x = 0; x < w; x++) if (paper[y * w + x]) col.push(L[y * w + x] / ax[x]);
      by[y] = col.length >= 40 ? decorQuantile(col, 0.7) : NaN;
    }
    fillGaps(by);
    const m = by.reduce((s, v) => s + v, 0) / h;
    for (let y = 0; y < h; y++) by[y] /= m;
  }
  const N = new Float32Array(n); // normalisierte Helligkeit
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) N[y * w + x] = L[y * w + x] / (ax[x] * by[y]);
  // 3. Rest-Hintergrund ohne bereits erkannte Pixel
  const flag = new Uint8Array(n);
  const use = new Uint8Array(n);
  for (let pass = 0; pass < 3; pass++) {
    for (let i = 0; i < n; i++) use[i] = paper[i] && !flag[i] ? 1 : 0;
    const bgN = boxMean(N, use, w, h, o.blur);
    const bgR = boxMean(CR, use, w, h, o.blur);
    const bgB = boxMean(CB, use, w, h, o.blur);
    for (let i = 0; i < n; i++) {
      if (!paper[i] || Number.isNaN(bgN[i])) {
        flag[i] = 0;
        continue;
      }
      const dev = (N[i] - bgN[i]) / bgN[i];
      const dc = Math.hypot(CR[i] - bgR[i], CB[i] - bgB[i]);
      flag[i] = dev < -o.dark || dev > o.bright || dc > o.chroma ? 1 : 0;
    }
  }
  // 4. dilatieren, Zusammenhangskomponenten, kleine Reste weg, grosse duenne Gebilde in Bloecke zerlegen
  const dil = dilateBox(flag, w, h, o.dilate);
  const label = new Int32Array(n);
  const comps = [];
  const stack = [];
  for (let s = 0; s < n; s++) {
    if (!dil[s] || label[s]) continue;
    const id = comps.length + 1;
    let core = 0;
    let x0 = w;
    let y0 = h;
    let x1 = -1;
    let y1 = -1;
    stack.push(s);
    label[s] = id;
    while (stack.length) {
      const i = stack.pop();
      const x = i % w;
      const y = (i - x) / w;
      if (flag[i]) core++;
      if (x < x0) x0 = x;
      if (x > x1) x1 = x;
      if (y < y0) y0 = y;
      if (y > y1) y1 = y;
      const nb = [x > 0 ? i - 1 : -1, x < w - 1 ? i + 1 : -1, y > 0 ? i - w : -1, y < h - 1 ? i + w : -1];
      for (const j of nb) {
        if (j >= 0 && dil[j] && !label[j]) {
          label[j] = id;
          stack.push(j);
        }
      }
    }
    comps.push({ id, core, x0, y0, x1: x1 + 1, y1: y1 + 1 });
  }
  const rects = [];
  const split = (id, x0, y0, x1, y1) => {
    let a = 0;
    let bx0 = w;
    let by0 = h;
    let bx1 = -1;
    let by1 = -1;
    for (let y = y0; y < y1; y++) {
      for (let x = x0; x < x1; x++) {
        if (label[y * w + x] !== id) continue;
        a++;
        if (x < bx0) bx0 = x;
        if (x > bx1) bx1 = x;
        if (y < by0) by0 = y;
        if (y > by1) by1 = y;
      }
    }
    if (a === 0) return;
    const rw = bx1 + 1 - bx0;
    const rh = by1 + 1 - by0;
    if (a / (rw * rh) >= o.fill || Math.max(rw, rh) < o.minSide * 2) {
      rects.push({ x: bx0, y: by0, w: rw, h: rh });
    } else if (rw >= rh) {
      const mx = bx0 + Math.floor(rw / 2);
      split(id, bx0, by0, mx, by1 + 1);
      split(id, mx, by0, bx1 + 1, by1 + 1);
    } else {
      const my = by0 + Math.floor(rh / 2);
      split(id, bx0, by0, bx1 + 1, my);
      split(id, bx0, my, bx1 + 1, by1 + 1);
    }
  };
  for (const c of comps) if (c.core >= o.minArea) split(c.id, c.x0, c.y0, c.x1, c.y1);
  return { rects, paper, flag };
}

/** Rechtecke der Doppelseite (Bildpixel) in Seitenkoordinaten: { L: [[x, y, w, h]], R: [...] }, am Falz geteilt, auf 0..pageH gekappt */
export function toPageRects(rects, o = KEEPOUT) {
  const out = { L: [], R: [] };
  for (const r of rects) {
    const y0 = Math.max(0, r.y - o.top);
    const y1 = Math.min(o.pageH, r.y + r.h - o.top);
    if (y1 <= y0) continue;
    if (r.x < o.half) {
      const x1 = Math.min(r.x + r.w, o.half);
      if (x1 > r.x) out.L.push([r.x, y0, x1 - r.x, y1 - y0]);
    }
    if (r.x + r.w > o.half) {
      const x0 = Math.max(r.x, o.half);
      out.R.push([x0 - o.half, y0, r.x + r.w - x0, y1 - y0]);
    }
  }
  const order = (a, b) => a[1] - b[1] || a[0] - b[0];
  out.L.sort(order);
  out.R.sort(order);
  return out;
}

/** Lua-Quelltext der generierten Datei journal/DecorKeepout.lua */
export function keepoutLua(map) {
  const side = (list) => (list.length ? "{\n" + list.map((r) => `      {${r.join(", ")}},`).join("\n") + "\n    }" : "{}");
  const body = PAGE_IDS.map((id) => `  ${id} = {\n    L = ${side(map[id].L)},\n    R = ${side(map[id].R)},\n  },`).join("\n");
  return `-- GENERATED by scripts/render-media.mjs --keepout, do not edit by hand.
-- Keep-out rectangles {x, y, w, h} of the painted decorations per tab and page (L/R, each ${KEEPOUT.half} wide, x from the page's
-- left edge, y from the top of the double page, ${KEEPOUT.pageH} high). No content may cross them; test helper: tests/helpers/keepout.mjs.
local _, NS = ...
local Theme = NS.Journal.Theme

Theme.DECOR_KEEPOUT = {
${body}
}
`;
}

/** Doppelseite eines Reiters in Spielgroesse rendern (Papier auf Frame.paperRect, weisser Grund, keine Gammakurve): { w, h, rgba } */
export function renderSpreadRaw(browser, tmp, id) {
  const c = spreadFor(id);
  const name = `keepout_${id}`;
  const html = path.join(tmp, `${name}.html`);
  const png = path.join(tmp, `${name}.png`);
  const body = ART(c.file, c, KEEPOUT.w, KEEPOUT.h).replace("background:transparent", "background:#fff");
  writeFileSync(html, body.replace("</style>", "body{background:#fff !important}</style>"), "utf8");
  execFileSync(
    browser,
    [
      "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
      "--default-background-color=FFFFFFFF", `--user-data-dir=${path.join(tmp, "profile")}`,
      `--window-size=${KEEPOUT.w},${KEEPOUT.h}`, `--screenshot=${png}`, pathToFileURL(html).href,
    ],
    { stdio: "ignore", timeout: 60000 },
  );
  const img = decodePng(readFileSync(png));
  if (img.w !== KEEPOUT.w || img.h !== KEEPOUT.h) throw new Error(`${name}: Screenshot ${img.w}x${img.h} statt ${KEEPOUT.w}x${KEEPOUT.h}`);
  return img;
}

/** PNG schreiben (8 bit RGBA, ein Filter 0 je Zeile) */
export function encodePng(w, h, rgba) {
  const crcTable = Array.from({ length: 256 }, (_, n) => {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    return c >>> 0;
  });
  const crc = (buf) => {
    let c = 0xffffffff;
    for (const b of buf) c = crcTable[(c ^ b) & 255] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  };
  const chunk = (type, data) => {
    const head = Buffer.alloc(8);
    head.writeUInt32BE(data.length, 0);
    head.write(type, 4, "ascii");
    const tail = Buffer.alloc(4);
    tail.writeUInt32BE(crc(Buffer.concat([head.subarray(4), data])), 0);
    return Buffer.concat([head, data, tail]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  const raw = Buffer.alloc(h * (w * 4 + 1));
  for (let y = 0; y < h; y++) Buffer.from(rgba.buffer, rgba.byteOffset + y * w * 4, w * 4).copy(raw, y * (w * 4 + 1) + 1);
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk("IHDR", ihdr),
    chunk("IDAT", deflateSync(raw)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

/** Vorschau: Seitenpaar mit den Sperrflaechen (rot, halbtransparent, mit Rand) und der Falzlinie */
function previewImage(img, rects) {
  const { w, h } = img;
  const out = Uint8Array.from(img.rgba);
  const blend = (x, y, r, g, b, a) => {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    const o = (y * w + x) * 4;
    out[o] = Math.round(out[o] * (1 - a) + r * a);
    out[o + 1] = Math.round(out[o + 1] * (1 - a) + g * a);
    out[o + 2] = Math.round(out[o + 2] * (1 - a) + b * a);
    out[o + 3] = 255;
  };
  for (const r of rects) {
    for (let y = r.y; y < r.y + r.h; y++) for (let x = r.x; x < r.x + r.w; x++) blend(x, y, 255, 30, 30, 0.28);
    for (let x = r.x; x < r.x + r.w; x++) {
      blend(x, r.y, 220, 0, 0, 0.95);
      blend(x, r.y + r.h - 1, 220, 0, 0, 0.95);
    }
    for (let y = r.y; y < r.y + r.h; y++) {
      blend(r.x, y, 220, 0, 0, 0.95);
      blend(r.x + r.w - 1, y, 220, 0, 0, 0.95);
    }
  }
  for (let y = 0; y < h; y += 4) blend(KEEPOUT.half, y, 0, 90, 220, 0.9);
  return encodePng(w, h, out);
}

/** Sperrflaechen aller Reiter erzeugen: schreibt journal/DecorKeepout.lua und tests/screens/b2-keepout-<reiter>.png */
export function runKeepout(browser, tmp, { luaFile = KEEPOUT_LUA, screens = KEEPOUT_SCREENS } = {}) {
  const map = {};
  mkdirSync(screens, { recursive: true });
  for (const id of PAGE_IDS) {
    const img = renderSpreadRaw(browser, tmp, id);
    const { rects } = detectDecor(img.rgba, img.w, img.h);
    map[id] = toPageRects(rects);
    writeFileSync(path.join(screens, `b2-keepout-${id}.png`), previewImage(img, rects));
    console.log(`  ${id}: ${map[id].L.length} Sperrflaechen links, ${map[id].R.length} rechts`);
  }
  writeFileSync(luaFile, keepoutLua(map), "utf8");
  console.log(`  -> ${path.relative(ROOT, luaFile)} und ${path.relative(ROOT, screens)}/b2-keepout-<reiter>.png geschrieben`);
  return map;
}

export const KEEPOUT_LUA = path.join(ROOT, "addon", "InkAndEmbers", "journal", "DecorKeepout.lua");
export const KEEPOUT_SCREENS = path.join(ROOT, "tests", "screens");

// ---------------------------------------------------------------------------------------------------------------
// PNG lesen (Chrome-Screenshot: 8 bit, RGB oder RGBA, ohne Interlace) und TGA schreiben

export function decodePng(buf) {
  const SIG = [137, 80, 78, 71, 13, 10, 26, 10];
  for (let i = 0; i < 8; i++) if (buf[i] !== SIG[i]) throw new Error("keine PNG-Datei");
  let pos = 8;
  let w = 0;
  let h = 0;
  let type = 0;
  const idat = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos);
    const name = buf.toString("ascii", pos + 4, pos + 8);
    const data = buf.subarray(pos + 8, pos + 8 + len);
    if (name === "IHDR") {
      w = data.readUInt32BE(0);
      h = data.readUInt32BE(4);
      const depth = data[8];
      type = data[9];
      if (depth !== 8 || (type !== 6 && type !== 2) || data[12] !== 0) throw new Error(`PNG-Format nicht unterstuetzt (Tiefe ${depth}, Typ ${type})`);
    } else if (name === "IDAT") idat.push(data);
    else if (name === "IEND") break;
    pos += 12 + len;
  }
  const bpp = type === 6 ? 4 : 3;
  const raw = inflateSync(Buffer.concat(idat));
  const stride = w * bpp;
  const out = Buffer.alloc(w * h * 4);
  let prev = Buffer.alloc(stride);
  for (let y = 0; y < h; y++) {
    const f = raw[y * (stride + 1)];
    const line = Buffer.from(raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1)));
    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? line[x - bpp] : 0;
      const b = prev[x];
      const c = x >= bpp ? prev[x - bpp] : 0;
      let v = line[x];
      if (f === 1) v += a;
      else if (f === 2) v += b;
      else if (f === 3) v += (a + b) >> 1;
      else if (f === 4) {
        const p = a + b - c;
        const pa = Math.abs(p - a);
        const pb = Math.abs(p - b);
        const pc = Math.abs(p - c);
        v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
      }
      line[x] = v & 255;
    }
    for (let x = 0; x < w; x++) {
      const o = (y * w + x) * 4;
      out[o] = line[x * bpp];
      out[o + 1] = line[x * bpp + 1];
      out[o + 2] = line[x * bpp + 2];
      out[o + 3] = bpp === 4 ? line[x * bpp + 3] : 255;
    }
    prev = line;
  }
  return { w, h, rgba: out };
}

/** TGA Typ 2, 32 bit BGRA, Ursprung unten links (Standard, den der Client sicher liest) */
export function encodeTga(w, h, rgba) {
  const head = Buffer.alloc(18);
  head[2] = 2;
  head.writeUInt16LE(w, 12);
  head.writeUInt16LE(h, 14);
  head[16] = 32;
  head[17] = 8; // 8 Alpha-Bits, Ursprung unten links
  const body = Buffer.alloc(w * h * 4);
  for (let y = 0; y < h; y++) {
    const src = (h - 1 - y) * w * 4;
    for (let x = 0; x < w; x++) {
      const s = src + x * 4;
      const d = (y * w + x) * 4;
      body[d] = rgba[s + 2];
      body[d + 1] = rgba[s + 1];
      body[d + 2] = rgba[s];
      body[d + 3] = rgba[s + 3];
    }
  }
  return Buffer.concat([head, body]);
}

/** TGA-Kopf pruefen: { ok, w, h, reason } */
export function inspectTga(buf) {
  if (buf.length < 18) return { ok: false, reason: "zu kurz" };
  const type = buf[2];
  const w = buf.readUInt16LE(12);
  const h = buf.readUInt16LE(14);
  const bits = buf[16];
  const pow2 = (n) => n > 0 && (n & (n - 1)) === 0;
  if (type !== 2) return { ok: false, w, h, reason: `Typ ${type} statt 2 (unkomprimiert)` };
  if (bits !== 32) return { ok: false, w, h, reason: `${bits} bit statt 32` };
  if (!pow2(w) || !pow2(h)) return { ok: false, w, h, reason: "Kanten keine Zweierpotenz" };
  if (w > 1024 || h > 1024) return { ok: false, w, h, reason: "groesser als 1024 px" };
  if (buf.length < 18 + buf[0] + w * h * 4) return { ok: false, w, h, reason: "Pixeldaten unvollstaendig" };
  return { ok: true, w, h };
}

// ---------------------------------------------------------------------------------------------------------------
// Browser

function findBrowser() {
  const env = process.env.CHROME_PATH;
  const list = [
    env,
    "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
    "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe",
    "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
    "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
    "/usr/bin/google-chrome",
    "/usr/bin/chromium",
  ].filter(Boolean);
  return list.find((p) => existsSync(p));
}

function render(browser, tmp, tex) {
  if (tex.pixels) return encodeTga(tex.w, tex.h, tex.pixels());
  const html = path.join(tmp, `${tex.name}.html`);
  const png = path.join(tmp, `${tex.name}.png`);
  const rw = tex.rw ?? tex.w; // Rendergroesse; bei rw/rh verkleinert post selbst auf w x h
  const rh = tex.rh ?? tex.h;
  writeFileSync(html, tex.html(), "utf8");
  execFileSync(
    browser,
    [
      "--headless=new",
      "--disable-gpu",
      "--hide-scrollbars",
      "--force-device-scale-factor=1",
      "--default-background-color=00000000",
      `--user-data-dir=${path.join(tmp, "profile")}`,
      `--window-size=${rw},${rh}`,
      `--screenshot=${png}`,
      pathToFileURL(html).href,
    ],
    { stdio: "ignore", timeout: 60000 },
  );
  const img = decodePng(readFileSync(png));
  if (img.w !== rw || img.h !== rh) throw new Error(`${tex.name}: Screenshot ${img.w}x${img.h} statt ${rw}x${rh}`);
  if (tex.rw) return encodeTga(tex.w, tex.h, tex.post(img.rgba, img.w, img.h));
  if (tex.post) tex.post(img.rgba, img.w, img.h);
  return encodeTga(img.w, img.h, img.rgba);
}

// Optionale Texturen (Eintrag "source"): fehlt die Quelldatei, wird nichts gerendert; fehlt auch die TGA, nichts geprueft
export const sourceMissing = (t) => Boolean(t.source) && !existsSync(path.join(ROOT, t.source));

export function checkMedia(dir = MEDIA_DIR) {
  const problems = [];
  for (const t of TEXTURES) {
    const file = path.join(dir, `${t.name}.tga`);
    if (!existsSync(file) && sourceMissing(t)) continue;
    if (!existsSync(file)) {
      problems.push(`${t.name}.tga fehlt`);
      continue;
    }
    const r = inspectTga(readFileSync(file));
    if (!r.ok) problems.push(`${t.name}.tga: ${r.reason}`);
    else if (r.w !== t.w || r.h !== t.h) problems.push(`${t.name}.tga: ${r.w}x${r.h} statt ${t.w}x${t.h}`);
  }
  return problems;
}

const HELP = `Texturen des Reisejournals aus dem Design rendern (Headless-Browser -> TGA)

Aufruf:
  node scripts/render-media.mjs [--only <Name>] [--check] [--keepout] [--fire-areas] [--help]

  --only Name  nur eine Textur (${TEXTURES.map((t) => t.name).join(", ")})
  --check      nur pruefen (vorhanden, 32 bit, Zweierpotenz, <= 1024 px)
  --keepout    Sperrflaechen der Verzierungen je Reiter neu ermitteln (journal/DecorKeepout.lua, Vorschau tests/screens/b2-keepout-*.png)
  --fire-areas Textbereiche der Zettel am Feuer neu ermitteln (journal/FireNoteAreas.lua, Vorschau tests/screens/fire-notes.png)
  --help       diese Hilfe

Browser: Chrome oder Edge, Pfad optional ueber die Umgebungsvariable CHROME_PATH.
Ziel: addon/InkAndEmbers/Media/<Name>.tga. Neue Texturen erkennt WoW erst nach einem Spielneustart.`;

export function main(argv) {
  const known = new Set(["--only", "--check", "--keepout", "--fire-areas", "--help", "-h"]);
  for (let i = 0; i < argv.length; i++) {
    if (!known.has(argv[i])) throw new Error(`Unbekannte Option: ${argv[i]}\nHilfe: node scripts/render-media.mjs --help`);
    if (argv[i] === "--only") i++;
  }
  if (argv.includes("--help") || argv.includes("-h")) {
    console.log(HELP);
    return;
  }
  if (argv.includes("--check")) {
    const problems = checkMedia();
    if (problems.length) throw new Error("Texturen fehlerhaft:\n  " + problems.join("\n  "));
    console.log(`Texturen ok (${TEXTURES.length}).`);
    return;
  }
  if (argv.includes("--fire-areas")) {
    runFireAreas();
    return;
  }
  if (argv.includes("--keepout")) {
    const browser = findBrowser();
    if (!browser) throw new Error("Kein Chrome/Edge gefunden. Pfad ueber die Umgebungsvariable CHROME_PATH angeben.");
    const tmp = mkdtempSync(path.join(os.tmpdir(), "even-keepout-"));
    try {
      runKeepout(browser, tmp);
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
    return;
  }
  const oi = argv.indexOf("--only");
  let list = TEXTURES;
  if (oi >= 0) {
    const name = argv[oi + 1];
    list = TEXTURES.filter((t) => t.name === name);
    if (!name || list.length === 0) throw new Error(`--only braucht einen Texturnamen (${TEXTURES.map((t) => t.name).join(", ")})`);
  }
  const skipped = list.filter(sourceMissing);
  if (skipped.length && oi >= 0) throw new Error(`Quelldatei fehlt: ${skipped[0].source}`);
  for (const t of skipped) console.log(`  ${t.name}.tga uebersprungen (Quelle ${t.source} fehlt)`);
  list = list.filter((t) => !sourceMissing(t));
  const browser = list.every((t) => t.pixels) ? null : findBrowser();
  if (!browser && !list.every((t) => t.pixels)) throw new Error("Kein Chrome/Edge gefunden. Pfad ueber die Umgebungsvariable CHROME_PATH angeben.");
  mkdirSync(MEDIA_DIR, { recursive: true });
  const tmp = mkdtempSync(path.join(os.tmpdir(), "even-media-"));
  try {
    for (const t of list) {
      const tga = render(browser, tmp, t);
      writeFileSync(path.join(MEDIA_DIR, `${t.name}.tga`), tga);
      console.log(`  ${t.name}.tga  ${t.w}x${t.h}  ${tga.length} Bytes`);
    }
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
  console.log("Fertig. Neue Texturen erkennt der Client erst nach einem kompletten Spielneustart.");
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    main(process.argv.slice(2));
  } catch (err) {
    console.error(`FEHLER: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  }
}
