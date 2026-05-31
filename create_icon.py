#!/usr/bin/env python3
"""Creates a new app icon for Paperless 24 (iOS client for Paperless-ngx)."""

from PIL import Image, ImageDraw, ImageFilter
import math

SIZE = 1024

def lerp(a, b, t):
    return a + (b - a) * t

def lerp_color(c1, c2, t):
    return tuple(int(lerp(a, b, t)) for a, b in zip(c1, c2))

def create_gradient_background(size):
    img = Image.new("RGBA", (size, size))
    pixels = img.load()
    # Dark navy -> teal gradient (diagonal)
    top_left = (10, 25, 55)       # deep navy
    bottom_right = (0, 120, 130)  # teal
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * size)
            t = max(0, min(1, t))
            c = lerp_color(top_left, bottom_right, t)
            pixels[x, y] = (*c, 255)
    return img

def draw_rounded_rect(draw, xy, radius, fill, outline=None, outline_width=0):
    x0, y0, x1, y1 = xy
    draw.rounded_rectangle([x0, y0, x1, y1], radius=radius, fill=fill,
                           outline=outline, width=outline_width)

def draw_document(draw, cx, cy, w, h, fold_size, fill, shadow_color=None):
    """Draw a document with folded top-right corner."""
    x0 = cx - w // 2
    y0 = cy - h // 2
    x1 = cx + w // 2
    y1 = cy + h // 2
    r = 18

    # Main document polygon (with cut top-right corner)
    pts = [
        (x0 + r, y0),
        (x1 - fold_size, y0),
        (x1, y0 + fold_size),
        (x1, y1 - r),
        (x1 - r, y1),
        (x0 + r, y1),
        (x0, y1 - r),
        (x0, y0 + r),
    ]
    draw.polygon(pts, fill=fill)
    # Fold triangle
    draw.polygon([
        (x1 - fold_size, y0),
        (x1, y0 + fold_size),
        (x1 - fold_size, y0 + fold_size),
    ], fill=(*[int(c * 0.82) for c in fill[:3]], fill[3] if len(fill) > 3 else 255))

def add_scan_line_effect(img, cx, cy, doc_w, doc_h, doc_y_offset=0):
    """Add a glowing green scan line across the document."""
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    x0 = cx - doc_w // 2 + 20
    x1 = cx + doc_w // 2 - 20
    scan_y = cy + doc_y_offset
    # Glow layers
    for thickness, alpha in [(24, 18), (14, 35), (6, 80), (3, 180)]:
        d.line([(x0, scan_y), (x1, scan_y)],
               fill=(0, 240, 180, alpha), width=thickness)
    img = Image.alpha_composite(img, overlay)
    return img

def draw_text_lines(draw, cx, cy, doc_w, doc_h, line_color):
    """Draw fake text lines on the document."""
    x0 = cx - doc_w // 2 + 52
    x1 = cx + doc_w // 2 - 45
    start_y = cy - doc_h // 2 + 80
    line_gap = 44
    widths = [1.0, 0.75, 1.0, 0.85, 0.60, 1.0, 0.70]
    for i, w_frac in enumerate(widths):
        lx1 = x0 + int((x1 - x0) * w_frac)
        ly = start_y + i * line_gap
        if ly > cy + doc_h // 2 - 60:
            break
        lw = 10 if i % 3 == 0 else 8
        draw.rounded_rectangle([x0, ly, lx1, ly + lw], radius=4, fill=line_color)

def draw_checkmark(img, cx, cy, radius):
    """Draw a bold green checkmark in a white circle."""
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    # White circle
    d.ellipse([cx - radius, cy - radius, cx + radius, cy + radius],
              fill=(255, 255, 255, 255))
    # Green filled circle inside
    inner = int(radius * 0.88)
    d.ellipse([cx - inner, cy - inner, cx + inner, cy + inner],
              fill=(0, 190, 140, 255))
    # Checkmark path
    lw = max(8, int(radius * 0.18))
    p1 = (cx - int(radius * 0.38), cy + int(radius * 0.02))
    p2 = (cx - int(radius * 0.05), cy + int(radius * 0.35))
    p3 = (cx + int(radius * 0.42), cy - int(radius * 0.30))
    d.line([p1, p2], fill=(255, 255, 255, 255), width=lw)
    d.line([p2, p3], fill=(255, 255, 255, 255), width=lw)
    img = Image.alpha_composite(img, overlay)
    return img

def draw_sparkles(draw, positions, color, size):
    """Draw small 4-pointed star sparkles."""
    for (sx, sy) in positions:
        s = size
        draw.polygon([
            (sx, sy - s), (sx + s//4, sy - s//4),
            (sx + s, sy), (sx + s//4, sy + s//4),
            (sx, sy + s), (sx - s//4, sy + s//4),
            (sx - s, sy), (sx - s//4, sy - s//4),
        ], fill=color)

def main():
    # --- Background ---
    img = create_gradient_background(SIZE)
    draw = ImageDraw.Draw(img)

    # --- Document shadow ---
    shadow_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow_layer)
    doc_w, doc_h = 480, 580
    cx, cy = SIZE // 2, SIZE // 2 - 30
    fold = 80
    doc_pts = [
        (cx - doc_w//2 + 18, cy - doc_h//2 + 12),
        (cx + doc_w//2 - fold + 12, cy - doc_h//2 + 12),
        (cx + doc_w//2 + 12, cy - doc_h//2 + fold + 12),
        (cx + doc_w//2 + 12, cy + doc_h//2 - 18 + 12),
        (cx + doc_w//2 - 18 + 12, cy + doc_h//2 + 12),
        (cx - doc_w//2 + 18 + 12, cy + doc_h//2 + 12),
        (cx - doc_w//2 + 12, cy + doc_h//2 - 18 + 12),
        (cx - doc_w//2 + 12, cy - doc_h//2 + 18 + 12),
    ]
    sd.polygon(doc_pts, fill=(0, 0, 0, 70))
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(28))
    img = Image.alpha_composite(img, shadow_layer)

    draw = ImageDraw.Draw(img)

    # --- Main document ---
    draw_document(draw, cx, cy, doc_w, doc_h, fold,
                  fill=(245, 250, 255, 255))

    # --- Text lines (dark teal) ---
    draw_text_lines(draw, cx, cy, doc_w, doc_h,
                    line_color=(180, 200, 215, 200))

    # --- Scan line effect ---
    img = add_scan_line_effect(img, cx, cy, doc_w - 40, doc_h, doc_y_offset=60)

    # --- Checkmark badge (bottom-right of document) ---
    badge_cx = cx + doc_w // 2 - 18
    badge_cy = cy + doc_h // 2 - 10
    img = draw_checkmark(img, badge_cx, badge_cy, radius=88)

    # --- Sparkles (top-left area) ---
    draw = ImageDraw.Draw(img)
    draw_sparkles(draw, [
        (cx - doc_w//2 - 60, cy - doc_h//2 - 20),
        (cx - doc_w//2 - 20, cy - doc_h//2 + 60),
        (cx - doc_w//2 + 30, cy - doc_h//2 - 70),
    ], color=(255, 255, 255, 200), size=14)
    draw_sparkles(draw, [
        (cx + doc_w//2 + 55, cy - doc_h//2 + 30),
    ], color=(255, 255, 255, 160), size=10)

    # --- Final output ---
    out = img.convert("RGB")
    out_path = "/home/user/Paperless24/Paperless24/Assets.xcassets/AppIcon.appiconset/AppIcon_new.png"
    out.save(out_path, "PNG", optimize=True)
    print(f"Icon saved to: {out_path}")
    print(f"Size: {out.size}")

if __name__ == "__main__":
    main()
