"""Quest-Tracker-Griff + angepinnte Quest (Nachtrag "Quest anpinnen", Stilvorlage Gemini-Entwurf 2):
erzeugt den Textur-Atlas addon/InkAndEmbers/Media/QuestTracker/GripPin.tga (256 x 256, 32 bit unkomprimiert, Ursprung unten links)
und eine Vorschau docs/design/quest-tracker/grip-pin-vorschau.png.

Atlas (Pixel, y von oben; die Lua-Seite liest dieselben Zahlen aus QTR.GRIPTEX in journal/QuestTracker.lua):
  plaque  0..64   x 0..96    Pergament-Plakette fuer die Zaehlung (unregelmaessiger, leicht angesengter Rand, Alpha)
  orn     64..128 x 0..128   Bronze-Filigran UEBER der Plakette (zeigt nach oben, unten = an der Plakette); weiss, wird getoent;
                             unter der Plakette dieselbe Kachel senkrecht gespiegelt (Texturkoordinaten)
  corner  128..192 x 0..64   Ecken-Ornament des Pin-Panels (oben links; unten links gespiegelt); weiss, wird getoent
  smoke   0..128  x 128..256 Rauch-Schleier (hellgrau, weiche Raender, Alpha) ueber dem dunklen Grund von Griff und Panel
  soft    192..256 x 0..64   weicher Grund (weiss, abgerundet, Alpha laeuft im aeusseren Viertel weich aus) fuer 9-Slice
                             (QTR.softPlate): keine harten Aussenkanten, weiche Naht zwischen Griff und Pin-Panel
  (orn wird seit 17.11. nicht mehr benutzt: am 14 px schmalen Griff wirkte das Filigran deplatziert, dort steht nur noch je eine
  feine Haarlinie; die Kachel bleibt im Atlas, damit die Koordinaten stabil sind)

Filigran und Ecke werden aus dem freigegebenen Bild ausgeschnitten (Hochpass auf die warmen Bronze-Linien = Alpha), Plakette aus dem
Pergament von Media/Toast.tga, Rauch prozedural (feste Saat, reproduzierbar).
Aufruf: python scripts/cut-grip-pin.py"""
import os
import struct
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SRC = "docs/design/quest-tracker/griff-pin-konzept-2.jpg"
PARCH = "addon/InkAndEmbers/Media/Toast.tga"
OUT = "addon/InkAndEmbers/Media/QuestTracker/GripPin.tga"
PREVIEW = "docs/design/quest-tracker/grip-pin-vorschau.png"
W = H = 256

atlas = np.zeros((H, W, 4), np.float32)  # RGB 0..255, A 0..1


def blur(arr, r):
    u8 = np.clip(arr, 0, 255).astype(np.uint8)
    return np.asarray(Image.fromarray(u8).filter(ImageFilter.GaussianBlur(r))).astype(np.float32)


def resize(arr, w, h):
    return np.asarray(Image.fromarray(arr.astype(np.float32), mode="F").resize((w, h), Image.BOX))


def bronze_lines(a, box, thr=5.0, k=16.0):
    """Alpha der hellen, warmen Linien (Bronze-Gravur) im Ausschnitt box = (x0, y0, x1, y1)"""
    c = a[box[1]:box[3], box[0]:box[2]]
    lum = c.mean(2)
    hp = lum - blur(lum, 5)
    warm = np.clip((c[:, :, 0] - c[:, :, 2] - 2) / 12, 0, 1)
    return np.clip((hp - thr) / k, 0, 1) * warm


src = np.asarray(Image.open(SRC).convert("RGB")).astype(np.float32)

# ---- orn: Filigran ueber der Plakette (Bildachse x = 2300, symmetrisch)
al = bronze_lines(src, (2222, 395, 2378, 707))
al = resize(al, 64, 128)
al = np.clip(al * 1.6, 0, 1)
atlas[0:128, 64:128, :3] = 255
atlas[0:128, 64:128, 3] = al

# ---- corner: Ecken-Ornament oben links am Panel (ohne die aeussere Kante, ohne die Nadel rechts unten)
cw = 128
al = bronze_lines(src, (598, 556, 598 + cw, 556 + cw))
yy, xx = np.mgrid[0:cw, 0:cw]
al[(xx + yy) > 150] = 0
al[:8, :] = 0
al[:, :8] = 0
al = np.clip(resize(al, 64, 64) * 1.5, 0, 1)
atlas[0:64, 128:192, :3] = 255
atlas[0:64, 128:192, 3] = al

# ---- plaque: Pergament (Toast.tga, ruhige Flaeche rechts oben), Rand angesengt, Umriss leicht unregelmaessig
pt = np.asarray(Image.open(PARCH).convert("RGBA")).astype(np.float32)
patch = pt[40:160, 300:380, :3]  # 80 x 120
patch = np.stack([resize(patch[:, :, i], 64, 96) for i in range(3)], 2)
mean = patch.reshape(-1, 3).mean(0)
patch = mean + (patch - mean) * 1.25  # etwas mehr Flecken
ph, pw = 96, 64
rng = np.random.default_rng(7)
mask = Image.new("L", (pw * 4, ph * 4), 0)
d = ImageDraw.Draw(mask)
d.rounded_rectangle([6, 6, pw * 4 - 7, ph * 4 - 7], radius=44, fill=255)
mask = mask.filter(ImageFilter.GaussianBlur(9))  # weicher Rand
m = np.asarray(mask.resize((pw, ph), Image.BOX)).astype(np.float32) / 255
# unregelmaessiger Rand: Rauschen nur im Randbereich
nz = blur(rng.random((ph, pw)) * 255, 1.2) / 255
edge = np.clip((1 - m) * 4, 0, 1) + np.clip((0.97 - m) * 3, 0, 1)
m = np.clip(m - (nz - 0.5) * 0.9 * np.clip(1 - m, 0, 1) * 2.2, 0, 1)
# angesengter Rand: Abstand zur Kante -> dunkler, braeunlich
inner = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(5))).astype(np.float32) / 255
inner = blur(inner * 255, 2.5) / 255
burn = np.clip(1 - inner, 0, 1)
col = patch * (1 - 0.55 * burn[:, :, None]) + np.array([92, 58, 28]) * (0.35 * burn[:, :, None])
atlas[0:96, 0:64, :3] = np.clip(col, 0, 255)
atlas[0:96, 0:64, 3] = m

# ---- soft: weiss, abgerundetes Rechteck, Alpha laeuft ueber die aeusseren 16 Texel (= 1 Viertel) weich aus
yy, xx = np.mgrid[0:64, 0:64].astype(np.float32)
dx = np.maximum(0, np.maximum(16 - (xx + 0.5), (xx + 0.5) - 48))
dy = np.maximum(0, np.maximum(16 - (yy + 0.5), (yy + 0.5) - 48))
d = np.sqrt(dx * dx + dy * dy) / 16  # 0 innen, 1 am Rand der Kachel
soft = np.clip(1 - d, 0, 1)
soft = soft * soft * (3 - 2 * soft)  # weicher Verlauf (smoothstep)
atlas[0:64, 192:256, :3] = 255
atlas[0:64, 192:256, 3] = soft

# ---- smoke: weiche Rauchschwaden (mehrere Oktaven, leicht senkrecht gestreckt), Rand blendet aus
s = np.zeros((128, 128), np.float32)
for octave, amp in ((4, 1.0), (8, 0.5), (16, 0.25), (32, 0.12)):
    g = rng.random((octave + 1, octave + 1)).astype(np.float32)
    s += amp * np.asarray(Image.fromarray(g, mode="F").resize((128, 128), Image.BICUBIC))
s = (s - s.min()) / (s.max() - s.min())
s = np.clip((s - 0.35) / 0.65, 0, 1) ** 1.4
yy, xx = np.mgrid[0:128, 0:128]
fade = np.minimum.reduce([xx, yy, 127 - xx, 127 - yy]).astype(np.float32)
fade = np.clip(fade / 18, 0, 1)
atlas[128:256, 0:128, :3] = 255
atlas[128:256, 0:128, 3] = s * fade

rgba = np.zeros((H, W, 4), np.uint8)
rgba[:, :, :3] = np.clip(atlas[:, :, :3] + 0.5, 0, 255).astype(np.uint8)
rgba[:, :, 3] = np.clip(atlas[:, :, 3] * 255 + 0.5, 0, 255).astype(np.uint8)

hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, W, H, 32, 8)
bgra = rgba[::-1][:, :, [2, 1, 0, 3]]
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "wb") as f:
    f.write(hdr + bgra.tobytes())
print("TGA:", OUT, W, "x", H, os.path.getsize(OUT), "Bytes")

# Vorschau: Atlas auf Dunkel (Bronze getoent wie im Spiel) und auf Hell, 2x
def comp(bg, tint):
    base = Image.new("RGBA", (W, H), bg)
    t = rgba.copy().astype(np.float32)
    for (x0, y0, x1, y1) in ((64, 0, 128, 128), (128, 0, 192, 64)):
        t[y0:y1, x0:x1, :3] *= np.array(tint, np.float32)[None, None, :]
    return Image.alpha_composite(base, Image.fromarray(np.clip(t, 0, 255).astype(np.uint8), "RGBA"))
sheet = Image.new("RGBA", (W * 2 + 30, H + 20), (60, 90, 60, 255))
sheet.paste(comp((21, 23, 29, 255), (0.80, 0.60, 0.40)), (10, 10))
sheet.paste(comp((235, 228, 210, 255), (0.55, 0.38, 0.22)), (W + 20, 10))
sheet = sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST)
sheet.convert("RGB").save(PREVIEW)
print("Vorschau:", PREVIEW)
