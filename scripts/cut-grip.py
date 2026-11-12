"""Quest-Tracker-Griff: Freistellung und Export der freigegebenen Griff-Grafik
docs/design/quest-tracker/griff-d3c.jpg (1536 x 2752, Griff auf reinem Schwarz, rechte Kante gerade, links gerundet, mittig
graviertes Ausrufezeichen, unten ein ovales Feld fuer die Fuellstand-Pille).

Ergebnis: addon/InkAndEmbers/Media/QuestTracker/Grip.tga (128 x 512, 32 bit unkomprimiert, Ursprung unten links wie die uebrigen
Texturen) und eine Vorschau docs/design/quest-tracker/griff-vorschau.png (Schachbrett + hell, 2x). Der Griff wird auf 78 x 512 skaliert
(volle Hoehe, Seitenverhaeltnis wie im Bild), RECHTS BUENDIG in die Textur gesetzt, links bleibt transparent. Die Lua-Konstanten
(QTR.GRIP in journal/QuestTracker.lua) werden mit ausgegeben: Texturbreite des Griffs, Rand links, Oval.

Freistellung: Hintergrund = zusammenhaengende Flaeche vom Bildrand aus mit Helligkeit <= BG_MAX (Flood-Fill). Das schwarze Oval im Griff ist
eingeschlossen und bleibt deckend. Kante: Alpha-Maske leicht weichgezeichnet, Skalierung mit vormultipliziertem Alpha (kein dunkler Saum).
Aufruf: python scripts/cut-grip.py"""
import struct
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SRC = "docs/design/quest-tracker/griff-d3c.jpg"
OUT = "addon/InkAndEmbers/Media/QuestTracker/Grip.tga"
PREVIEW = "docs/design/quest-tracker/griff-vorschau.png"
TEX_W, TEX_H = 128, 512
BG_MAX = 12  # Helligkeit (max. Kanal) bis hier = Hintergrund-Schwarz

im = Image.open(SRC).convert("RGB")
a = np.array(im)
m = a.max(2)
# Hintergrund per Flood-Fill vom Rand
bg = (m <= BG_MAX)
H, W = bg.shape
seen = np.zeros((H, W), bool)
flat_bg = bg.ravel().tolist()
seen_f = bytearray(H * W)
stack = []
for x in range(W):
    for y in (0, H - 1):
        stack.append(y * W + x)
for y in range(H):
    for x in (0, W - 1):
        stack.append(y * W + x)
while stack:  # Flood-Fill (4er-Nachbarschaft) vom Bildrand ueber das Hintergrund-Schwarz
    i = stack.pop()
    if seen_f[i] or not flat_bg[i]:
        continue
    seen_f[i] = 1
    y, x = divmod(i, W)
    if x > 0: stack.append(i - 1)
    if x < W - 1: stack.append(i + 1)
    if y > 0: stack.append(i - W)
    if y < H - 1: stack.append(i + W)
outside = np.frombuffer(bytes(seen_f), np.uint8).reshape(H, W) == 1
inside = ~outside
ys, xs = np.where(inside)
x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
x1 -= 1  # letzte Spalte ist die JPEG-Ausblutung der geraden Kante: nicht mitnehmen
print("Griff im Bild: x %d..%d, y %d..%d" % (x0, x1, y0, y1))

# Oval: eingeschlossenes Schwarz unterhalb der Bildmitte (Bereich unter dem Knopf)
dark_in = inside & (m <= BG_MAX)
oy, ox = np.where(dark_in[1500:, :])
oy = oy + 1500
ov = (ox.min(), ox.max(), oy.min(), oy.max())
print("Oval im Bild: x %d..%d, y %d..%d" % ov)

crop_rgb = a[y0:y1 + 1, x0:x1 + 1].astype(np.float32)
alpha = inside[y0:y1 + 1, x0:x1 + 1].astype(np.uint8) * 255
alpha[:, -1] = 255
# leichte Kantenweichheit (1,2 px im Quellbild); gerade rechte Kante bleibt hart, indem rechts aufgefuellt wird
pad = np.pad(alpha, ((0, 0), (0, 8)), mode="edge")
soft = np.array(Image.fromarray(pad).filter(ImageFilter.GaussianBlur(1.2)))[:, :-8]
alpha_f = soft.astype(np.float32) / 255.0
pm = crop_rgb * alpha_f[:, :, None]  # vormultipliziert
gw = int(round((x1 - x0 + 1) * TEX_H / (y1 - y0 + 1)))
def rs(arr):
    return np.array(Image.fromarray(arr, mode="F").resize((gw, TEX_H), Image.LANCZOS if False else Image.BOX))
chan = [rs(pm[:, :, i].astype(np.float32)) for i in range(3)]
al = rs(alpha_f.astype(np.float32))
out = np.zeros((TEX_H, TEX_W, 4), np.float32)
x_off = TEX_W - gw
for i in range(3):
    c = np.where(al > 1e-4, chan[i] / np.maximum(al, 1e-4), 0)
    out[:, x_off:, i] = c
out[:, x_off:, 3] = al
rgba = np.clip(out * np.array([1, 1, 1, 255], np.float32)[None, None, :] + 0.5, 0, 255).astype(np.uint8) if False else None
rgba = np.zeros((TEX_H, TEX_W, 4), np.uint8)
rgba[:, :, :3] = np.clip(out[:, :, :3] + 0.5, 0, 255).astype(np.uint8)
rgba[:, :, 3] = np.clip(out[:, :, 3] * 255 + 0.5, 0, 255).astype(np.uint8)

# TGA: Typ 2, 32 bit, Deskriptor 8 (8 Alpha-Bits, Ursprung unten links), Zeilen von unten nach oben, BGRA
hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, TEX_W, TEX_H, 32, 8)
bgra = rgba[::-1, :, [2, 1, 0, 3]] if False else rgba[::-1][:, :, [2, 1, 0, 3]]
import os
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "wb") as f:
    f.write(hdr + bgra.tobytes())
print("TGA:", OUT, TEX_W, "x", TEX_H, os.path.getsize(OUT), "Bytes")

# Lua-Konstanten: Bruchteile der Texturhoehe/-breite (Texturkoordinaten, y von oben)
s = TEX_H / (y1 - y0 + 1)
def tx(x): return (x_off + (x - x0) * s) / TEX_W
def ty(y): return (y - y0) * s / TEX_H
print("GRIP_LEFT=%.4f (Texcoord links, Griff rechtsbuendig bis 1.0)" % (x_off / TEX_W))
print("Griff-Seitenverhaeltnis w/h = %.4f" % (gw / TEX_H))
gx = lambda x: (x - x0) / (x1 - x0 + 1)
print("OVAL relativ zum Griff (QTR.GRIP.oval): x0=%.4f x1=%.4f y0=%.4f y1=%.4f" % (gx(ov[0]), gx(ov[1] + 1), ty(ov[2]), ty(ov[3] + 1)))
print("OVAL: x %.4f..%.4f  y %.4f..%.4f (Texturbruchteile)" % (tx(ov[0]), tx(ov[1] + 1), ty(ov[2]), ty(ov[3] + 1)))

# Vorschau: Schachbrett | hell | dunkel, 2x
def comp(bg):
    base = Image.new("RGBA", (TEX_W, TEX_H), bg)
    return Image.alpha_composite(base, Image.fromarray(rgba, "RGBA"))
chk = Image.new("RGBA", (TEX_W, TEX_H))
d = ImageDraw.Draw(chk)
for yy in range(0, TEX_H, 8):
    for xx in range(0, TEX_W, 8):
        d.rectangle([xx, yy, xx + 7, yy + 7], fill=(200, 200, 200, 255) if (xx // 8 + yy // 8) % 2 else (150, 150, 150, 255))
sheet = Image.new("RGBA", (TEX_W * 3 + 40, TEX_H + 20), (60, 90, 60, 255))
for i, bgi in enumerate((Image.alpha_composite(chk, Image.fromarray(rgba, "RGBA")), comp((235, 228, 210, 255)), comp((40, 70, 110, 255)))):
    sheet.paste(bgi, (10 + i * (TEX_W + 10), 10))
sheet = sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST)
sheet.convert("RGB").save(PREVIEW)
print("Vorschau:", PREVIEW)
