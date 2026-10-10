"""Render the KAGO mark (assets/branding/kago-mark.svg) into every app icon.

Usage: python kago_icons.py <repo root>
The SVG holds a rounded square and one M/C/Z path filled with the even-odd rule.
"""
import os
import re
import sys

from PIL import Image, ImageChops, ImageDraw

ROOT = sys.argv[1]
SVG = os.path.join(ROOT, 'assets', 'branding', 'kago-mark.svg')
svg = open(SVG, encoding='utf-8').read()

VB = [float(x) for x in re.search(r'viewBox="([^"]+)"', svg).group(1).split()]
_rect = re.search(r'<rect[^>]*rx="([\d.]+)"[^>]*fill="(#[0-9A-Fa-f]{6})"', svg)
RX, BG = float(_rect.group(1)), _rect.group(2)
_path = re.search(
    r'<path[^>]*transform="translate\(([-\d.]+),([-\d.]+)\) scale\(([-\d.]+)\)"'
    r'[^>]*d="([^"]+)"[^>]*fill="(#[0-9A-Fa-f]{6})"', svg)
TX, TY, SC, D, FG = (float(_path.group(1)), float(_path.group(2)),
                     float(_path.group(3)), _path.group(4), _path.group(5))
NUM = re.compile(r'[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?')


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def bezier(p0, p1, p2, p3, steps=24):
    out = []
    for i in range(1, steps + 1):
        t, u = i / steps, 1 - i / steps
        out.append((u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0],
                    u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1]))
    return out


def contours(d):
    out, cur, start, pos = [], [], (0.0, 0.0), (0.0, 0.0)
    for cmd, args in re.findall(r'([MCZmcz])([^MCZmcz]*)', d):
        n = [float(v) for v in NUM.findall(args)]
        if cmd in 'Mm':
            if cur:
                out.append(cur)
            pos = (n[0], n[1]) if cmd == 'M' else (pos[0] + n[0], pos[1] + n[1])
            start, cur = pos, [pos]
        elif cmd in 'Cc':
            for i in range(0, len(n), 6):
                p = n[i:i + 6]
                if cmd == 'c':
                    p = [v + (pos[0] if j % 2 == 0 else pos[1]) for j, v in enumerate(p)]
                cur += bezier(pos, (p[0], p[1]), (p[2], p[3]), (p[4], p[5]))
                pos = (p[4], p[5])
        else:
            if cur:
                out.append(cur)
            cur, pos = [], start
    if cur:
        out.append(cur)
    return out


POLYS = contours(D)
# The glyph's own bounds, so it can be centred inside an Android safe zone.
_xs = [x * SC + TX for c in POLYS for x, _ in c]
_ys = [y * SC + TY for c in POLYS for _, y in c]
GLYPH_BOX = (min(_xs), min(_ys), max(_xs), max(_ys))


def glyph_mask(size, box, ss=4):
    """Even-odd mask of the glyph fitted into `box` (l, t, r, b) of `size`."""
    w = size * ss
    gl, gt, gr, gb = GLYPH_BOX
    k = min((box[2] - box[0]) / (gr - gl), (box[3] - box[1]) / (gb - gt)) * ss
    ox = (box[0] + box[2]) / 2 * ss - (gl + gr) / 2 * k
    oy = (box[1] + box[3]) / 2 * ss - (gt + gb) / 2 * k
    mask = Image.new('1', (w, w), 0)
    for poly in POLYS:
        if len(poly) < 3:
            continue
        one = Image.new('1', (w, w), 0)
        ImageDraw.Draw(one).polygon(
            [((x * SC + TX) * k + ox, (y * SC + TY) * k + oy) for x, y in poly], fill=1)
        mask = ImageChops.logical_xor(mask, one)
    return mask.convert('L').resize((size, size), Image.LANCZOS)


def square(size, pad=None, radius=None, bg=BG):
    """The full mark: rounded square plus the white glyph."""
    pad = (VB[2] - (GLYPH_BOX[2] - GLYPH_BOX[0])) / 2 if pad is None else pad
    ss = 4
    img = Image.new('RGBA', (size * ss, size * ss), (0, 0, 0, 0))
    if bg:
        r = (RX if radius is None else radius) / VB[2] * size * ss
        ImageDraw.Draw(img).rounded_rectangle(
            [0, 0, size * ss - 1, size * ss - 1], radius=r, fill=rgb(bg) + (255,))
    img = img.resize((size, size), Image.LANCZOS)
    m = GLYPH_BOX
    box = (m[0] / VB[2] * size, m[1] / VB[3] * size, m[2] / VB[2] * size, m[3] / VB[3] * size)
    img.paste(Image.new('RGBA', (size, size), rgb(FG) + (255,)), (0, 0), glyph_mask(size, box))
    return img


def foreground(size, safe=0.62):
    """Android adaptive foreground: glyph centred in the safe zone, no background."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    s = size * safe
    box = ((size - s) / 2, (size - s) / 2, (size + s) / 2, (size + s) / 2)
    img.paste(Image.new('RGBA', (size, size), (255, 255, 255, 255)), (0, 0),
              glyph_mask(size, box))
    return img


def save(img, *parts):
    path = os.path.join(ROOT, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print(os.path.join(*parts), img.size)


# In-app logo and the generic branding asset.
save(square(512), 'assets', 'branding', 'kago_icon.png')

# Android launcher icons.
for folder, legacy, fg in (('mipmap-mdpi', 48, 108), ('mipmap-hdpi', 72, 162),
                           ('mipmap-xhdpi', 96, 216), ('mipmap-xxhdpi', 144, 324),
                           ('mipmap-xxxhdpi', 192, 432)):
    base = ('android', 'app', 'src', 'main', 'res', folder)
    save(square(legacy), *base, 'ic_launcher.png')
    save(foreground(fg), *base, 'ic_launcher_foreground.png')

# Windows .ico (the runner embeds every size).
ico = square(256)
ico.save(os.path.join(ROOT, 'windows', 'runner', 'resources', 'app_icon.ico'),
         sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])
print('windows/runner/resources/app_icon.ico')

# macOS app icon set.
for s in (16, 32, 64, 128, 256, 512, 1024):
    save(square(s), 'macos', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset',
         'app_icon_%d.png' % s)
