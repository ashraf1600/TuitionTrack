"""Draws the TuitionTrack mark (same geometry as lib/widgets/tt_logo.dart) into the Android resources.

Needs: pip install pillow numpy
Usage (from mobile/): python3 tool/make_icons.py android/app/src/main/res
"""
import math, os, sys
import numpy as np
from PIL import Image, ImageDraw

SS = 4  # supersampling

def mark(px, tile=True, mono=False):
    S = px * SS
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    if tile:
        y, x = np.mgrid[0:S, 0:S].astype(float)
        t = (x + y) / (2 * (S - 1))
        top, bottom = np.array([0x5C, 0x95, 0xCB]), np.array([0x2B, 0x56, 0x80])
        rgb = (top[None, None, :] * (1 - t[..., None]) + bottom[None, None, :] * t[..., None]).astype(np.uint8)
        grad = Image.fromarray(rgb, 'RGB').convert('RGBA')
        mask = Image.new('L', (S, S), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=int(0.28 * S), fill=255)
        img.paste(grad, (0, 0), mask)
    cx = cy = S / 2
    r, w = 0.27 * S, 0.075 * S
    white = (255, 255, 255, 255)
    # PIL draws a stroke inward from the box, so grow the box by half the width to centre it on the ring.
    ro = r + w / 2
    bbox = [cx - ro, cy - ro, cx + ro, cy + ro]
    track = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(track).ellipse(bbox, outline=(255, 255, 255, 72), width=int(w))
    img = Image.alpha_composite(img, track)
    d = ImageDraw.Draw(img)
    start, sweep = -90.0, 0.82 * 360
    d.arc(bbox, start, start + sweep, fill=white, width=int(w))
    for ang in (start, start + sweep):  # round caps
        a = math.radians(ang)
        px_, py_ = cx + r * math.cos(a), cy + r * math.sin(a)
        d.ellipse([px_ - w / 2, py_ - w / 2, px_ + w / 2, py_ + w / 2], fill=white)
    # the next-class dot
    a = math.radians(start + sweep)
    hx, hy, hr = cx + r * math.cos(a), cy + r * math.sin(a), 0.045 * S
    d.ellipse([hx - hr, hy - hr, hx + hr, hy + hr], fill=white if mono else (0xF2, 0xB8, 0x4B, 255))
    # check mark
    pts = [(0.385 * S, 0.51 * S), (0.47 * S, 0.595 * S), (0.625 * S, 0.415 * S)]
    cw = 0.085 * S
    d.line(pts, fill=white, width=int(cw), joint='curve')
    for (x, y) in (pts[0], pts[2]):
        d.ellipse([x - cw / 2, y - cw / 2, x + cw / 2, y + cw / 2], fill=white)
    return img.resize((px, px), Image.LANCZOS)

res = sys.argv[1]
for folder, px in (('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)):
    mark(px).save(os.path.join(res, f'mipmap-{folder}', 'ic_launcher.png'))
for folder, px in (('mdpi', 24), ('hdpi', 36), ('xhdpi', 48), ('xxhdpi', 72), ('xxxhdpi', 96)):
    d = os.path.join(res, f'drawable-{folder}')
    os.makedirs(d, exist_ok=True)
    mark(px, tile=False, mono=True).save(os.path.join(d, 'ic_stat_tt.png'))
os.makedirs(os.path.join(res, 'drawable-nodpi'), exist_ok=True)
mark(288).save(os.path.join(res, 'drawable-nodpi', 'splash_logo.png'))
print('done')
