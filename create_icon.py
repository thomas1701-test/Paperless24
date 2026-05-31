#!/usr/bin/env python3
"""Modern minimal app icon for Paperless 24 (iOS client for Paperless-ngx)."""

from PIL import Image, ImageDraw, ImageFilter
import math

SIZE = 1024

def make_radial_gradient(size, cx, cy, r, color_inner, color_outer):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pixels = img.load()
    for y in range(size):
        for x in range(size):
            dist = math.sqrt((x - cx) ** 2 + (y - cy) ** 2)
            t = min(dist / r, 1.0)
            t = t * t  # ease
            c = tuple(int(a + (b - a) * t) for a, b in zip(color_inner, color_outer))
            pixels[x, y] = c
    return img

def make_linear_gradient(size, c1, c2, angle_deg=135):
    img = Image.new("RGBA", (size, size))
    pixels = img.load()
    rad = math.radians(angle_deg)
    dx, dy = math.cos(rad), math.sin(rad)
    for y in range(size):
        for x in range(size):
            t = ((x / size) * dx + (y / size) * dy)
            t = max(0.0, min(1.0, t))
            c = tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))
            pixels[x, y] = (*c, 255)
    return img

def draw_doc(draw, cx, cy, w, h, fold, fill, fold_fill):
    x0, y0 = cx - w // 2, cy - h // 2
    x1, y1 = cx + w // 2, cy + h // 2
    r = 22
    body = [
        (x0 + r, y0), (x1 - fold, y0),
        (x1, y0 + fold),
        (x1, y1 - r), (x1 - r, y1),
        (x0 + r, y1), (x0, y1 - r),
        (x0, y0 + r),
    ]
    draw.polygon(body, fill=fill)
    draw.polygon([(x1 - fold, y0), (x1, y0 + fold), (x1 - fold, y0 + fold)], fill=fold_fill)

def add_glow(base, cx, cy, radius, color, alpha_peak=90):
    glow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    pixels = glow.load()
    for y in range(base.size[1]):
        for x in range(base.size[0]):
            d = math.sqrt((x - cx) ** 2 + (y - cy) ** 2)
            t = max(0.0, 1.0 - d / radius)
            t = t ** 2
            a = int(alpha_peak * t)
            pixels[x, y] = (*color, a)
    return Image.alpha_composite(base, glow)

def main():
    # ── Background: deep navy → rich teal (diagonal) ──────────────────────────
    bg = make_linear_gradient(SIZE, (8, 16, 40), (5, 90, 110), angle_deg=145)

    # ── Subtle radial glow (teal, bottom-center) ───────────────────────────────
    bg = add_glow(bg, SIZE // 2 + 60, SIZE // 2 + 180, 620,
                  (0, 160, 180), alpha_peak=80)

    # ── Noise/grain overlay for premium feel ──────────────────────────────────
    import random, os
    rng = random.Random(42)
    grain = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    gp = grain.load()
    for y in range(SIZE):
        for x in range(SIZE):
            v = rng.randint(200, 255)
            a = rng.randint(0, 6)
            gp[x, y] = (v, v, v, a)
    bg = Image.alpha_composite(bg, grain)

    draw = ImageDraw.Draw(bg)

    # ── Document geometry ──────────────────────────────────────────────────────
    cx, cy = SIZE // 2, SIZE // 2 - 10
    dw, dh, fold = 420, 520, 90

    # Drop shadow
    shadow_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow_layer)
    for offset, alpha in [(24, 15), (16, 25), (8, 40)]:
        draw_doc(sd, cx + offset // 2, cy + offset,
                 dw, dh, fold, (0, 0, 0, alpha), (0, 0, 0, 0))
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(32))
    bg = Image.alpha_composite(bg, shadow_layer)
    draw = ImageDraw.Draw(bg)

    # Document body – clean white with very slight warmth
    draw_doc(draw, cx, cy, dw, dh, fold,
             fill=(248, 250, 253, 255),
             fold_fill=(210, 220, 232, 255))

    # ── Minimal content lines ──────────────────────────────────────────────────
    lx0 = cx - dw // 2 + 56
    lx1 = cx + dw // 2 - 56
    ly_start = cy - dh // 2 + 80
    line_defs = [
        (1.00, 12, (180, 195, 210, 180)),
        (0.60, 10, (195, 208, 220, 140)),
        (0.80, 10, (195, 208, 220, 140)),
        (0.45, 10, (195, 208, 220, 140)),
    ]
    gap = 46
    for i, (frac, lh, col) in enumerate(line_defs):
        ly = ly_start + i * gap
        draw.rounded_rectangle([lx0, ly, lx0 + int((lx1 - lx0) * frac), ly + lh],
                                radius=5, fill=col)

    # ── Teal accent bar (scan line) ────────────────────────────────────────────
    scan_y = cy + 30
    bar_overlay = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bar_overlay)
    bx0, bx1 = cx - dw // 2 + 20, cx + dw // 2 - 20

    # Glow halo
    for thickness, alpha in [(40, 10), (22, 25), (10, 55)]:
        bd.rounded_rectangle([bx0, scan_y - thickness // 2,
                               bx1, scan_y + thickness // 2],
                              radius=thickness // 2,
                              fill=(0, 210, 185, alpha))
    # Core line
    bd.rounded_rectangle([bx0, scan_y - 4, bx1, scan_y + 4],
                          radius=4, fill=(0, 230, 200, 200))
    bg = Image.alpha_composite(bg, bar_overlay)
    draw = ImageDraw.Draw(bg)

    # ── More content lines below scan ─────────────────────────────────────────
    ly_start2 = scan_y + 30
    line_defs2 = [
        (0.90, 10, (195, 208, 220, 130)),
        (0.55, 10, (195, 208, 220, 100)),
    ]
    for i, (frac, lh, col) in enumerate(line_defs2):
        ly = ly_start2 + i * gap
        if ly + lh > cy + dh // 2 - 48:
            break
        draw.rounded_rectangle([lx0, ly, lx0 + int((lx1 - lx0) * frac), ly + lh],
                                radius=5, fill=col)

    # ── Checkmark badge ────────────────────────────────────────────────────────
    badge_cx = cx + dw // 2 - 10
    badge_cy = cy + dh // 2 - 8
    br = 82

    badge_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    bdraw = ImageDraw.Draw(badge_layer)

    # Outer ring (white)
    bdraw.ellipse([badge_cx - br, badge_cy - br, badge_cx + br, badge_cy + br],
                  fill=(255, 255, 255, 255))
    # Inner fill: vibrant teal
    ir = int(br * 0.86)
    bdraw.ellipse([badge_cx - ir, badge_cy - ir, badge_cx + ir, badge_cy + ir],
                  fill=(0, 185, 155, 255))

    # Checkmark
    lw = max(9, int(br * 0.19))
    p1 = (badge_cx - int(br * 0.36), badge_cy + int(br * 0.04))
    p2 = (badge_cx - int(br * 0.04), badge_cy + int(br * 0.36))
    p3 = (badge_cx + int(br * 0.40), badge_cy - int(br * 0.28))
    bdraw.line([p1, p2], fill=(255, 255, 255, 255), width=lw)
    bdraw.line([p2, p3], fill=(255, 255, 255, 255), width=lw)

    bg = Image.alpha_composite(bg, badge_layer)

    # ── Save ───────────────────────────────────────────────────────────────────
    out = bg.convert("RGB")
    path = "Paperless24/Assets.xcassets/AppIcon.appiconset/AppIcon_new.png"
    out.save(path, "PNG", optimize=True)
    print(f"Saved: {path}  {out.size}")

if __name__ == "__main__":
    main()
