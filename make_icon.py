#!/usr/bin/env python3
"""
Generates AppIcon.iconset + AppIcon.icns for RandomGif.
Design: purple-to-pink squircle, three fanned card-frames, corner sparkles.
"""
from PIL import Image, ImageDraw
import math, os, subprocess, sys

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def lerp(a, b, t):
    return a + (b - a) * t

def lerp_color(c1, c2, t):
    return tuple(int(lerp(c1[i], c2[i], t)) for i in range(3))

def gradient_image(size):
    """Top-to-bottom multi-stop gradient: deep indigo → violet → fuchsia → pink."""
    stops = [(30, 10, 100), (109, 40, 217), (192, 38, 211), (225, 29, 100)]
    n = len(stops) - 1
    img = Image.new('RGB', (size, size))
    draw = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        seg = min(int(t * n), n - 1)
        color = lerp_color(stops[seg], stops[seg + 1], (t * n) - seg)
        draw.line([(0, y), (size - 1, y)], fill=color)
    return img

def squircle_mask(size):
    mask = Image.new('L', (size, size), 0)
    r = int(size * 0.225)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=r, fill=255)
    return mask

def rotated_rect_pts(cx, cy, w, h, deg):
    a = math.radians(deg)
    cos_a, sin_a = math.cos(a), math.sin(a)
    hw, hh = w / 2, h / 2
    corners = [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)]
    return [(int(cx + cos_a * x - sin_a * y),
             int(cy + sin_a * x + cos_a * y)) for x, y in corners]

def draw_sparkle(draw, cx, cy, r, alpha=200):
    """4-pointed star (sparkle)."""
    inner = r * 0.28
    pts = []
    for i in range(8):
        angle = math.radians(i * 45 - 90)
        rad = r if i % 2 == 0 else inner
        pts.append((int(cx + rad * math.cos(angle)),
                    int(cy + rad * math.sin(angle))))
    draw.polygon(pts, fill=(255, 255, 255, alpha))

# ---------------------------------------------------------------------------
# Icon renderer
# ---------------------------------------------------------------------------

def make_icon(size):
    # ── background ──────────────────────────────────────────────────────────
    bg = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    bg.paste(gradient_image(size).convert('RGBA'), mask=squircle_mask(size))

    # Subtle inner vignette (darker at edges)
    vignette = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    for r_pct, alpha in [(0.50, 0), (0.70, 30), (0.85, 70), (1.00, 110)]:
        r = int(size * r_pct)
        offset = size // 2 - r
        ImageDraw.Draw(vignette).ellipse(
            [offset, offset, size - offset, size - offset],
            fill=(0, 0, 0, 0),
            outline=(0, 0, 0, alpha),
            width=int(size * 0.07)
        )
    bg = Image.alpha_composite(bg, vignette)

    # ── card frames ─────────────────────────────────────────────────────────
    cx   = size // 2
    cy   = int(size * 0.49)
    fw   = int(size * 0.50)
    fh   = int(size * 0.36)
    bw   = max(2, int(size * 0.017))
    cr   = max(2, int(size * 0.035))   # corner radius for frames

    # back-left, back-right, front — (rotation_deg, fill_alpha, stroke_alpha)
    cards = [(-15, 45, 140), (11, 55, 160), (0, 80, 255)]

    for deg, fill_a, stroke_a in cards:
        pts = rotated_rect_pts(cx, cy, fw, fh, deg)

        # fill layer
        layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        ImageDraw.Draw(layer).polygon(pts, fill=(255, 255, 255, fill_a))
        bg = Image.alpha_composite(bg, layer)

        # stroke layer
        layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(layer)
        draw.line(pts + [pts[0]], fill=(255, 255, 255, stroke_a), width=bw)
        # top accent stripe on the front card only
        if deg == 0:
            stripe_h = int(fh * 0.22)
            stripe_pts = rotated_rect_pts(cx, cy - fh // 2 + stripe_h // 2, fw, stripe_h, 0)
            draw.polygon(stripe_pts, fill=(255, 255, 255, 45))
            draw.line([stripe_pts[2], stripe_pts[3]], fill=(255, 255, 255, 100), width=bw)
        bg = Image.alpha_composite(bg, layer)

    # ── play triangle ────────────────────────────────────────────────────────
    tri_r  = int(size * 0.115)
    tri_cx = cx + int(size * 0.015)
    tri_cy = cy + int(size * 0.005)

    layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(layer).polygon([
        (tri_cx - int(tri_r * 0.65), tri_cy - int(tri_r * 0.82)),
        (tri_cx - int(tri_r * 0.65), tri_cy + int(tri_r * 0.82)),
        (tri_cx + int(tri_r * 0.95), tri_cy),
    ], fill=(255, 255, 255, 235))
    bg = Image.alpha_composite(bg, layer)

    # ── corner sparkles ──────────────────────────────────────────────────────
    layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw  = ImageDraw.Draw(layer)
    sparkles = [
        (0.20, 0.22, 0.045, 210),
        (0.78, 0.19, 0.033, 180),
        (0.81, 0.76, 0.050, 210),
        (0.18, 0.78, 0.028, 170),
    ]
    for sx, sy, sr, sa in sparkles:
        draw_sparkle(draw, int(sx * size), int(sy * size), int(sr * size), sa)
    bg = Image.alpha_composite(bg, layer)

    return bg

# ---------------------------------------------------------------------------
# Build iconset + icns
# ---------------------------------------------------------------------------

ICONSET = 'AppIcon.iconset'
ICNS    = 'AppIcon.icns'

os.makedirs(ICONSET, exist_ok=True)

sizes = [
    ('icon_16x16.png',      16),
    ('icon_16x16@2x.png',   32),
    ('icon_32x32.png',      32),
    ('icon_32x32@2x.png',   64),
    ('icon_128x128.png',   128),
    ('icon_128x128@2x.png',256),
    ('icon_256x256.png',   256),
    ('icon_256x256@2x.png',512),
    ('icon_512x512.png',   512),
    ('icon_512x512@2x.png',1024),
]

print('Rendering icon…')
master = make_icon(1024)

for filename, px in sizes:
    out = master.resize((px, px), Image.LANCZOS) if px < 1024 else master
    out.save(os.path.join(ICONSET, filename), 'PNG')
    print(f'  {filename}')

print('Converting to .icns…')
result = subprocess.run(['iconutil', '-c', 'icns', ICONSET, '-o', ICNS])
if result.returncode == 0:
    print(f'  ✓ {ICNS}')
else:
    print('  ✗ iconutil failed', file=sys.stderr)
    sys.exit(1)
