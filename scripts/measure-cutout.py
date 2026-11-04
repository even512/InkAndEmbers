"""Misst eine Erzaehler-Figur (art/toast/narrator_cutout_<volk>_v2.jpg, Magenta-Grund) und gibt die fertigen Eintraege fuer
scripts/render-media.mjs (NARRATOR_CUTOUTS) und journal/Begleiter.lua (CUTOUTS) aus.
Aufruf: python scripts/measure-cutout.py <volk> [kopfY [untenY]] [--dx=N]   (--dx = Figur N px nach rechts, z. B. Skyborne 17, damit Hand/Umhang hinter dem Ring liegen)   (kopfY = Oberkante des Schaedels, wenn Haar/Kamm hoeher ragt;
untenY = Zuschnittboden, wenn das Bild unten einen runden Rand hat, Mensch 1840)
Aufbau (Figur HINTER dem Ring, Oberkoerper davor): Zuschnitt = ganze Figur von Kopf bis untenY. Die Figur wird so skaliert, dass ihre
Unterkante bei y = 178 liegt (im Ringkreis unterhalb des Kreises, hinter dem Ring, nie als gerade Kante sichtbar), Kopf bei y = -20,5.
Linke Figurkante bei x = -7; ist die Figur dafuer zu breit (rechte Kante > 212, Text ab 214), rutscht sie nach links und inset
(Abstand des Zettels vom Bildschirmrand) waechst mit, damit nichts links abgeschnitten wird."""
import sys
from PIL import Image
import numpy as np
args = [a for a in sys.argv[1:] if not a.startswith('--dx=')]
DX = next((float(a[5:]) for a in sys.argv[1:] if a.startswith('--dx=')), 0.0)
sys.argv = [sys.argv[0]] + args
v = sys.argv[1]
im = Image.open(f"art/toast/narrator_cutout_{v}_v2.jpg").convert("RGB"); a = np.array(im).astype(int)
m = (np.minimum(a[:, :, 0], a[:, :, 2]) - a[:, :, 1]) < 120
cx = np.where(m.sum(0) > 3)[0]; cy = np.where(m.sum(1) > 3)[0]
l, r, top = int(cx.min()), int(cx.max()), int(cy.min())
bbox_top = top
if len(sys.argv) > 2: top = int(sys.argv[2])
BOT = int(sys.argv[3]) if len(sys.argv) > 3 else 2048
S = (178 + 20.5) / (BOT - top)
X = max(0, l - 10); W = min(2048, r + 11) - X
Y = max(0, bbox_top - 12)
H = BOT - Y
fw = (r - l + 1) * S
fx = -7.0 + DX
if fx + fw > 212: fx = 212 - fw
gx = fx - (l - X) * S; gy = -20.5 - (top - Y) * S
inset = max(12, round(-fx + 5))
g = f"x: {gx:.1f}, y: {gy:.1f}, w: {W*S:.1f}, h: {H*S:.1f}"
print(f'  {v}: {{ file: "toast/narrator_cutout_{v}_v2.jpg", x: {X}, y: {Y}, w: {W}, h: {H}, srcW: 2048, srcH: 2048, game: {{ {g} }} }},')
print(f'  {v} = {{ x = {gx:.1f}, y = {gy:.1f}, w = {W*S:.1f}, h = {H*S:.1f}, inset = {inset}, dim = 1 }},')
