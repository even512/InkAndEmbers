// Ereignis-Symbole der Reise-Karte (Kartenzeichen, Kill-Marke, Spielerposition): Zuschnitt und Freistellung des Symbolbogens
// art/journal/map_icons_v2.jpg (freigegebener Bogen, 4 x 3 Zellen auf Magenta #FF00FF).
//
// Reihenfolge der Zellen (zeilenweise): 1 Stufenaufstieg, 2 Meilenstein, 3 Tod, 4 Seltener, 5 Elite, 6 Boss, 7 Foto/Moment,
// 8 Ruhestein, 9 Flugmeister, 10 Luecke, 11 eigene Position, 12 Kaempfe (= Theme.MAP_ICONS in journal/Theme.lua).
//
// Freistellung (rechnet jedes Pixel einzeln, keine globale Farbtoleranz):
//   - Purpur-Familie (Rot = Blau, Gruen fast 0): reines Magenta (hell) oder dunkles Magenta (der Schlagschatten der Vorlage und
//     schwarze Umrisslinien auf Magenta). Das ist "Schwarz mit Deckkraft s" ueber Magenta: Ergebnis Schwarz mit Alpha s = 1 - Rot/255.
//   - Zelle "Luecke" (Fussspuren) ist selbst dunkelpurpur (Rot = Blau ca. 70, Gruen 0): dort wuerde Schwarz-mit-Alpha sie zu halb
//     durchsichtigem Grau machen. Diese Zelle bekommt eine feste Tintenfarbe (INK_GAP) und Alpha aus der Dunkelheit (voll deckend
//     bei Rot <= GAP_SOLID).
//   - Alles andere (Gold, Gruen, Grau ...) ist ein Mischpixel mit dem Hintergrund (255, 0, 255): Alpha aus dem Magenta-Anteil
//     k = min(Rot, Blau) - Gruen, Farbe durch Entmischen (Glow des Positionspfeils, Randpixel).
// Danach je Zelle: Kernflaeche (Alpha > 0,5) -> quadratische Kachel, zentriert auf die Mitte des Kerns, Kern auf FILL der Kachel,
// der Rest ist Rand fuer Schatten und Glow. Verkleinert wird mit Flaechenmittel (Alpha-gewichtet, ohne dunklen Saum).
// Reine Funktionen auf RGBA-Feldern (Uint8Array/Buffer, 4 Bytes je Pixel), ohne Browser testbar.

export const MAP_ICON_IDS = ["level", "milestone", "death", "rare", "elite", "boss", "photo", "hearth", "flightpoint", "gap", "current", "kill"];
export const MAP_ICON_GRID = { cols: 4, rows: 3 };
export const MAP_ICONS_FILE = "map_icons_v2.jpg";
export const MAP_ICONS_SRC = { w: 2400, h: 1792 };
export const MAP_ICON_ATLAS = { cols: 4, cell: 128, w: 512, h: 512 }; // 12 Kacheln belegt, letzte Reihe leer (Zweierpotenz)
export const FILL = 0.84; // Anteil der Kachel, den der Kern des Symbols (ohne Schatten/Glow) fuellt
export const INK_GAP = [66, 38, 72]; // Fussspuren: dunkles Purpur-Braun, auf Pergament gut lesbar
const GAP_SOLID = 95; // Rot/Blau bis hier: voll deckend (die Spuren der Vorlage liegen bei 60 bis 80)
const GAP_INDEX = MAP_ICON_IDS.indexOf("gap");
const SHADOW_GAIN = 0.9; // Schlagschatten der Vorlage etwas abschwaechen

/** Ein Pixel (r, g, b 0..255) -> [r, g, b, a] (a 0..1), Magenta-Grund entfernt. gap = Zelle der Fussspuren. */
export function keyMagentaPixel(r, g, b, gap = false) {
  const purple = Math.abs(r - b) < 16 && g < 22;
  if (purple) {
    const v = (r + b) / 2;
    if (gap) {
      const a = Math.max(0, Math.min(1, (255 - v) / (255 - GAP_SOLID)));
      return a < 0.03 ? [0, 0, 0, 0] : [INK_GAP[0], INK_GAP[1], INK_GAP[2], a];
    }
    const s = (1 - v / 255) * SHADOW_GAIN;
    if (s < 0.03) return [0, 0, 0, 0];
    return [0, 0, 0, Math.min(1, s)];
  }
  const k = Math.min(r, b) - g;
  const a = Math.max(0, Math.min(1, 1 - k / 255));
  if (a < 0.03) return [0, 0, 0, 0];
  if (a > 0.995) return [r, g, b, 1];
  const un = (c, bg) => Math.max(0, Math.min(255, Math.round((c - (1 - a) * bg) / a)));
  // Mischpixel liegen nur am Glow (Gold): Blau darf Gruen nicht uebersteigen, sonst bleibt ein rosa Saum vom Magenta-Grund
  const ug = un(g, 0);
  return [un(r, 255), ug, Math.min(un(b, 255), ug), a];
}

/** Ganzen Bogen freistellen -> Float32Array (Farbe 0..255, Alpha 0..1, je 4 Werte je Pixel). */
export function keyMagenta(rgba, w, h, grid = MAP_ICON_GRID) {
  const out = new Float32Array(w * h * 4);
  for (let y = 0; y < h; y++) {
    const row = Math.min(grid.rows - 1, Math.floor((y * grid.rows) / h));
    for (let x = 0; x < w; x++) {
      const col = Math.min(grid.cols - 1, Math.floor((x * grid.cols) / w));
      const i = (y * w + x) * 4;
      const [r, g, b, a] = keyMagentaPixel(rgba[i], rgba[i + 1], rgba[i + 2], row * grid.cols + col === GAP_INDEX);
      out[i] = r;
      out[i + 1] = g;
      out[i + 2] = b;
      out[i + 3] = a;
    }
  }
  return out;
}

/** Kern (Alpha > 0,5) einer Zelle: { x0, y0, x1, y1 } (x1/y1 exklusiv) oder null. */
export function coreBox(keyed, w, cx0, cy0, cx1, cy1) {
  let x0 = Infinity, y0 = Infinity, x1 = -1, y1 = -1;
  for (let y = cy0; y < cy1; y++) {
    for (let x = cx0; x < cx1; x++) {
      if (keyed[(y * w + x) * 4 + 3] > 0.5) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  return x1 < 0 ? null : { x0, y0, x1: x1 + 1, y1: y1 + 1 };
}

/** Quadrat (Mitte cx, cy, Kante side Quellpixel) per Flaechenmittel auf size x size verkleinern, in dst (RGBA, Breite dw) bei ox, oy. */
export function boxResample(keyed, w, h, cx, cy, side, size, dst, dw, ox, oy) {
  const sx0 = cx - side / 2;
  const sy0 = cy - side / 2;
  const f = side / size;
  for (let dy = 0; dy < size; dy++) {
    for (let dx = 0; dx < size; dx++) {
      const ax0 = sx0 + dx * f, ax1 = ax0 + f, ay0 = sy0 + dy * f, ay1 = ay0 + f;
      let sr = 0, sg = 0, sb = 0, sa = 0, wsum = 0;
      for (let y = Math.floor(ay0); y < Math.ceil(ay1); y++) {
        const wy = Math.min(y + 1, ay1) - Math.max(y, ay0);
        for (let x = Math.floor(ax0); x < Math.ceil(ax1); x++) {
          const wt = wy * (Math.min(x + 1, ax1) - Math.max(x, ax0));
          wsum += wt;
          if (x < 0 || y < 0 || x >= w || y >= h) continue; // ausserhalb des Bogens: durchsichtig
          const i = (y * w + x) * 4;
          const a = keyed[i + 3] * wt;
          sr += keyed[i] * a;
          sg += keyed[i + 1] * a;
          sb += keyed[i + 2] * a;
          sa += a;
        }
      }
      const o = ((oy + dy) * dw + ox + dx) * 4;
      if (sa <= 1e-6 || wsum <= 0) {
        dst[o] = dst[o + 1] = dst[o + 2] = dst[o + 3] = 0;
      } else {
        dst[o] = Math.round(sr / sa);
        dst[o + 1] = Math.round(sg / sa);
        dst[o + 2] = Math.round(sb / sa);
        dst[o + 3] = Math.round(255 * Math.min(1, sa / wsum));
      }
    }
  }
}

/** Zelle index (0-basiert, zeilenweise) auf eine size x size Kachel -> Uint8Array RGBA. Wirft bei leerer Zelle. */
export function cutIcon(keyed, w, h, index, size, { grid = MAP_ICON_GRID, fill = FILL } = {}) {
  const col = index % grid.cols;
  const row = Math.floor(index / grid.cols);
  const cx0 = Math.round((col * w) / grid.cols), cx1 = Math.round(((col + 1) * w) / grid.cols);
  const cy0 = Math.round((row * h) / grid.rows), cy1 = Math.round(((row + 1) * h) / grid.rows);
  const box = coreBox(keyed, w, cx0, cy0, cx1, cy1);
  if (!box) throw new Error(`Symbolbogen: Zelle ${index + 1} ist leer (kein Symbol gefunden)`);
  const side = Math.max(box.x1 - box.x0, box.y1 - box.y0) / fill;
  const out = new Uint8Array(size * size * 4);
  boxResample(keyed, w, h, (box.x0 + box.x1) / 2, (box.y0 + box.y1) / 2, side, size, out, size, 0, 0);
  return out;
}

/** Atlas aus den zwoelf Kacheln (MAP_ICON_ATLAS, 4 Spalten), unbenutzte Kacheln durchsichtig. */
export function cutAtlas(rgba, w, h, A = MAP_ICON_ATLAS) {
  const keyed = keyMagenta(rgba, w, h);
  const out = new Uint8Array(A.w * A.h * 4);
  for (let i = 0; i < MAP_ICON_IDS.length; i++) {
    const tile = cutIcon(keyed, w, h, i, A.cell);
    const ox = (i % A.cols) * A.cell;
    const oy = Math.floor(i / A.cols) * A.cell;
    for (let y = 0; y < A.cell; y++) out.set(tile.subarray(y * A.cell * 4, (y + 1) * A.cell * 4), ((oy + y) * A.w + ox) * 4);
  }
  return out;
}

/** Einzelnes Symbol (id aus MAP_ICON_IDS) als size x size Textur. */
export function cutSingle(rgba, w, h, id, size) {
  const index = MAP_ICON_IDS.indexOf(id);
  if (index < 0) throw new Error(`Unbekanntes Kartensymbol: ${id}`);
  return cutIcon(keyMagenta(rgba, w, h), w, h, index, size);
}
