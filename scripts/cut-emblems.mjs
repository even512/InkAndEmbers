// EveN_ForeverChronicle: Kill-Embleme der Kampf-Seite (Gewoehnlich/Elite/Rar/Boss): Freistellung und Zuschnitt des Bogens
// art/journal/kill_emblems_v2.jpg (freigegebener Bogen, 2752 x 1536: vier Embleme nebeneinander auf Magenta #FF00FF;
// Bronze-Wolf, Gold-Drache, Silber-Drache, Eisen-Schaedel, jedes mit leerem Band/leerer Plakette unten fuer die Zahl).
//
// Ergebnis Media/KillEmblems.tga (512 x 512, 2 x 2 Kacheln zu 256 px, Reihenfolge = EMBLEM_IDS = Theme.EMBLEMS in journal/Theme.lua):
//   Kachel 1 normal (Bronze), 2 elite (Gold), 3 rare (Silber), 4 boss (Eisen). Je Kachel ist das Emblem so skaliert, dass seine
//   laengere Kante FILL der Kachel fuellt (zentriert); das Verhaeltnis Breite : Hoehe bleibt erhalten.
//
// Freistellung (Magenta-Key mit Toleranz, ohne rosa Saum):
//   Ein Pixel ist eine Mischung p = a * c + (1 - a) * (255, 0, 255). Der Magenta-Anteil ist m = min(R, B) - G; die Deckkraft ist
//   a = 1 - m / 255. Bis m <= KEY_LO ist das Pixel ein echtes Emblempixel (voll deckend, unveraendert: schwarze Umrisse, Metall,
//   rote Augen); darueber wird Magenta entmischt (c = (p - (1 - a) * bg) / a) und Blau gegen Gruen begrenzt (Saum). a < KEY_MIN: durchsichtig.
//   Zuschnitt je Emblem: zusammenhaengende Flaechen (Alpha > 0,5) -> die vier grossen Gebilde; kleine Reste (Funkeln, Splitter)
//   kommen zum naechsten grossen Gebilde; die Randpixel (AA) bekommen das Gebilde ihres Nachbarn. So bluten Nachbarn nicht in die
//   Kachel (der Wolf und der Drache liegen dicht beieinander).
// Reine Funktionen auf RGBA-Feldern (Uint8Array/Buffer, 4 Bytes je Pixel), ohne Browser testbar.

import { boxResample } from "./cut-icons.mjs";

export const EMBLEM_IDS = ["normal", "elite", "rare", "boss"];
export const EMBLEMS_FILE = "kill_emblems_v2.jpg";
export const EMBLEMS_SRC = { w: 2752, h: 1536 };
export const EMBLEM_ATLAS = { cols: 2, cell: 256, w: 512, h: 512 };
export const FILL = 0.94; // Anteil der Kachel, den die laengere Kante des Emblems fuellt
export const KEY_LO = 24; // bis hier: echtes Emblempixel
export const KEY_MIN = 0.1;  // Deckkraft darunter: durchsichtig

/** Ein Pixel (r, g, b 0..255) -> [r, g, b, a] (a 0..1), Magenta-Grund entfernt. */
export function keyEmblemPixel(r, g, b) {
  const m = Math.min(r, b) - g;
  if (m <= KEY_LO) return [r, g, b, 1];
  const a = 1 - m / 255;
  if (a < KEY_MIN) return [0, 0, 0, 0];
  const un = (c, bg) => Math.max(0, Math.min(255, Math.round((c - (1 - a) * bg) / a)));
  const ug = un(g, 0);
  return [un(r, 255), ug, Math.min(un(b, 255), ug + 14), a];
}

/** Ganzen Bogen freistellen -> Float32Array (Farbe 0..255, Alpha 0..1, je 4 Werte je Pixel). */
export function keyEmblems(rgba, w, h) {
  const out = new Float32Array(w * h * 4);
  for (let i = 0; i < w * h * 4; i += 4) {
    const [r, g, b, a] = keyEmblemPixel(rgba[i], rgba[i + 1], rgba[i + 2]);
    out[i] = r;
    out[i + 1] = g;
    out[i + 2] = b;
    out[i + 3] = a;
  }
  return out;
}

/**
 * Gebilde des Bogens: Beschriftung (Label) je Pixel (0 = Hintergrund) und die Rechtecke der `count` groessten Gebilde, von links
 * nach rechts sortiert. -> { label: Int32Array, boxes: [{ x0, y0, x1, y1 (exklusiv), n }] }
 */
export function findEmblems(keyed, w, h, count = EMBLEM_IDS.length) {
  const label = new Int32Array(w * h);
  const comps = [];
  const stack = new Int32Array(w * h);
  for (let start = 0; start < w * h; start++) {
    if (label[start] !== 0 || keyed[start * 4 + 3] <= 0.5) continue;
    const id = comps.length + 1;
    const c = { id, x0: w, y0: h, x1: -1, y1: -1, n: 0 };
    let sp = 0;
    stack[sp++] = start;
    label[start] = id;
    while (sp > 0) {
      const p = stack[--sp];
      const x = p % w, y = (p - x) / w;
      c.n++;
      if (x < c.x0) c.x0 = x;
      if (x > c.x1) c.x1 = x;
      if (y < c.y0) c.y0 = y;
      if (y > c.y1) c.y1 = y;
      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          const nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          const q = ny * w + nx;
          if (label[q] === 0 && keyed[q * 4 + 3] > 0.5) {
            label[q] = id;
            stack[sp++] = q;
          }
        }
      }
    }
    comps.push(c);
  }
  const big = comps.slice().sort((a, b) => b.n - a.n).slice(0, count);
  if (big.length < count) throw new Error(`Emblembogen: nur ${big.length} von ${count} Emblemen gefunden`);
  big.sort((a, b) => (a.x0 + a.x1) - (b.x0 + b.x1));
  // kleine Reste: zum Emblem, dessen Rechteck (mit Rand) sie enthaelt bzw. das ihnen am naechsten liegt
  const remap = new Map(big.map((c, i) => [c.id, i + 1]));
  for (const c of comps) {
    if (remap.has(c.id)) continue;
    const cx = (c.x0 + c.x1) / 2, cy = (c.y0 + c.y1) / 2;
    let best = 0, bd = Infinity;
    big.forEach((b, i) => {
      const dx = Math.max(b.x0 - cx, 0, cx - b.x1), dy = Math.max(b.y0 - cy, 0, cy - b.y1);
      const d = dx * dx + dy * dy;
      if (d < bd) { bd = d; best = i + 1; }
    });
    remap.set(c.id, best);
  }
  for (let i = 0; i < label.length; i++) if (label[i] !== 0) label[i] = remap.get(label[i]);
  // Randpixel (Alpha 0..0,5): Gebilde des Nachbarn, drei Durchgaenge
  for (let pass = 0; pass < 3; pass++) {
    const next = label.slice();
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const p = y * w + x;
        if (label[p] !== 0 || keyed[p * 4 + 3] <= 0) continue;
        for (let dy = -1; dy <= 1 && next[p] === 0; dy++) {
          for (let dx = -1; dx <= 1; dx++) {
            const nx = x + dx, ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            const l = label[ny * w + nx];
            if (l !== 0) { next[p] = l; break; }
          }
        }
      }
    }
    label.set(next);
  }
  // Rechtecke aus den endgueltigen Beschriftungen
  const boxes = big.map(() => ({ x0: w, y0: h, x1: -1, y1: -1, n: 0 }));
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const l = label[y * w + x];
      if (l === 0) continue;
      const b = boxes[l - 1];
      b.n++;
      if (x < b.x0) b.x0 = x;
      if (x > b.x1) b.x1 = x;
      if (y < b.y0) b.y0 = y;
      if (y > b.y1) b.y1 = y;
    }
  }
  return { label, boxes: boxes.map((b) => ({ x0: b.x0, y0: b.y0, x1: b.x1 + 1, y1: b.y1 + 1, n: b.n })) };
}

/** Geometrie der Kachel eines Emblems: Quellmitte und Kantenlaenge (Quellpixel) des quadratischen Ausschnitts. */
export function tileFrame(box, fill = FILL) {
  return { cx: (box.x0 + box.x1) / 2, cy: (box.y0 + box.y1) / 2, side: Math.max(box.x1 - box.x0, box.y1 - box.y0) / fill };
}

/** Atlas (EMBLEM_ATLAS) aus den vier Emblemen -> Uint8Array RGBA. */
export function cutEmblems(rgba, w, h, A = EMBLEM_ATLAS) {
  const keyed = keyEmblems(rgba, w, h);
  const { label, boxes } = findEmblems(keyed, w, h);
  const out = new Uint8Array(A.w * A.h * 4);
  boxes.forEach((box, i) => {
    // nur die Pixel dieses Emblems (Nachbarn ausblenden): Ausschnitt des Rechtecks mit Rand
    const pad = 4;
    const x0 = Math.max(0, box.x0 - pad), y0 = Math.max(0, box.y0 - pad);
    const x1 = Math.min(w, box.x1 + pad), y1 = Math.min(h, box.y1 + pad);
    const sw = x1 - x0, sh = y1 - y0;
    const sub = new Float32Array(sw * sh * 4);
    for (let y = 0; y < sh; y++) {
      for (let x = 0; x < sw; x++) {
        const p = (y0 + y) * w + (x0 + x);
        if (label[p] !== i + 1) continue;
        const s = p * 4, d = (y * sw + x) * 4;
        sub[d] = keyed[s];
        sub[d + 1] = keyed[s + 1];
        sub[d + 2] = keyed[s + 2];
        sub[d + 3] = keyed[s + 3];
      }
    }
    const f = tileFrame(box);
    const ox = (i % A.cols) * A.cell, oy = Math.floor(i / A.cols) * A.cell;
    boxResample(sub, sw, sh, f.cx - x0, f.cy - y0, f.side, A.cell, out, A.w, ox, oy);
  });
  return out;
}
