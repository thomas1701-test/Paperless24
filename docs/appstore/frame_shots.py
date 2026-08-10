#!/usr/bin/env python3
"""Baut aus den rohen Simulator-Screenshots die gerahmten App-Store-Bilder.

Hintergrund: Farbverlauf im Indigo der App, darüber eine kurze Schlagzeile,
darunter der Screenshot mit abgerundeten Ecken und weichem Schatten.
"""

import os
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SCRATCH = os.path.dirname(os.path.abspath(__file__))

# Reihenfolge und Texte der Bilder.
SLIDES = [
    ("01-uebersicht", ("Dein Papierkram.\nEndlich sortiert.",
                       "Alle Dokumente deines paperless-ngx-Servers, als Raster oder Liste."),
                      ("Your paperwork.\nFinally sorted.",
                       "Every document on your paperless-ngx server, as a grid or a list.")),
    ("06-suche",      ("Finde jedes Wort\nin jedem Scan.",
                       "Volltextsuche über den erkannten Text — auch offline."),
                      ("Find every word\nin every scan.",
                       "Full-text search across recognised text — offline too.")),
    ("02-dokument",   ("PDF, Text und Notizen\nin einer Ansicht.",
                       "Teilen, Freigabe-Links, Übersetzen — alles einen Tipp entfernt."),
                      ("PDF, text and notes\nin a single view.",
                       "Share, share links, translate — all one tap away.")),
    ("04-info",       ("Beträge, Fristen,\neigene Felder.",
                       "Custom Fields von paperless-ngx, direkt am Dokument."),
                      ("Amounts, due dates,\ncustom fields.",
                       "Your paperless-ngx custom fields, right on the document.")),
    ("03-text",       ("Erkannter Text,\nangenehm zu lesen.",
                       "Lesemodus mit warmem Papierton und einstellbarer Schriftgröße."),
                      ("Recognised text,\neasy on the eyes.",
                       "Reading mode with a warm paper tone and adjustable type size.")),
    ("11-tags",       ("Tags, Sender, Typen —\ndirekt in der App.",
                       "Anlegen, umbenennen, löschen. Verschachtelte Tags inklusive."),
                      ("Tags, correspondents,\ntypes — right here.",
                       "Create, rename, delete. Nested tags included.")),
    ("09-einstellungen", ("Alles offline dabei.\nAuch ohne Netz.",
                          "Dokumente herunterladen, Änderungen laufen in die Warteschlange."),
                         ("Take it all offline.\nEven with no signal.",
                          "Download documents; edits queue up until you are back online.")),
    ("10-darstellung", ("Sechs Farbthemen.\nOder deine eigene.",
                        "Hell, dunkel, OLED-Schwarz und fünf alternative App-Symbole."),
                       ("Six colour themes.\nOr one of your own.",
                        "Light, dark, OLED black and five alternative app icons.")),
]

# Farbverlauf oben → unten.
GRADIENT_TOP = (44, 54, 148)
GRADIENT_BOTTOM = (116, 74, 200)

FONT_PATH = "/System/Library/Fonts/SFNS.ttf"
FONT_FALLBACK = "/System/Library/Fonts/Avenir Next.ttc"


def load_font(size, weight="Bold"):
    try:
        font = ImageFont.truetype(FONT_PATH, size)
        try:
            font.set_variation_by_name(weight)
        except Exception:
            pass
        return font
    except Exception:
        return ImageFont.truetype(FONT_FALLBACK, size)


def gradient(width, height):
    base = Image.new("RGB", (1, height))
    px = base.load()
    for y in range(height):
        t = y / max(1, height - 1)
        px[0, y] = tuple(
            round(GRADIENT_TOP[i] + (GRADIENT_BOTTOM[i] - GRADIENT_TOP[i]) * t) for i in range(3)
        )
    canvas = base.resize((width, height), Image.BICUBIC)

    # Weicher heller Schein oben links, damit die Fläche nicht flach wirkt.
    glow = Image.new("L", (width, height), 0)
    ImageDraw.Draw(glow).ellipse(
        [-width * 0.35, -height * 0.22, width * 0.85, height * 0.42], fill=70
    )
    glow = glow.filter(ImageFilter.GaussianBlur(width * 0.12))
    canvas.paste(Image.new("RGB", (width, height), (255, 255, 255)), (0, 0), glow)
    return canvas


def rounded(image, radius):
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, image.size[0] - 1, image.size[1] - 1],
                                           radius=radius, fill=255)
    out = Image.new("RGBA", image.size)
    out.paste(image, (0, 0), mask)
    return out


def draw_centered(draw, text, font, y, width, fill, line_spacing=1.14):
    lines = text.split("\n")
    ascent, descent = font.getmetrics()
    line_height = round((ascent + descent) * line_spacing)
    for i, line in enumerate(lines):
        w = draw.textlength(line, font=font)
        draw.text(((width - w) / 2, y + i * line_height), line, font=font, fill=fill)
    return y + len(lines) * line_height


def build(src_dir, out_dir, lang, tablet=False):
    os.makedirs(out_dir, exist_ok=True)
    made = []
    for index, (name, de, en) in enumerate(SLIDES, start=1):
        path = os.path.join(src_dir, name + ".png")
        if not os.path.exists(path):
            print("fehlt:", path)
            continue
        shot = Image.open(path).convert("RGB")
        W, H = shot.size
        canvas = gradient(W, H).convert("RGBA")
        draw = ImageDraw.Draw(canvas)

        headline, subline = (de if lang == "de" else en)

        title_size = round(W * (0.046 if tablet else 0.063))
        sub_size = round(W * (0.022 if tablet else 0.029))
        title_font = load_font(title_size, "Bold")
        sub_font = load_font(sub_size, "Regular")

        top = round(H * (0.052 if tablet else 0.055))
        y = draw_centered(draw, headline, title_font, top, W, (255, 255, 255, 255))
        y += round(H * 0.008)
        y = draw_centered(draw, subline, sub_font, y, W, (255, 255, 255, 205), line_spacing=1.2)

        # Screenshot skalieren und unter die Schlagzeile setzen; unten leicht anschneiden.
        target_w = round(W * (0.70 if tablet else 0.80))
        scale = target_w / W
        thumb = shot.resize((target_w, round(H * scale)), Image.LANCZOS)
        thumb = rounded(thumb, round(target_w * 0.058))

        x = (W - target_w) // 2
        top_y = round(y + H * (0.035 if tablet else 0.03))

        shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        shadow_layer = Image.new("RGBA", thumb.size, (0, 0, 0, 110))
        shadow.paste(shadow_layer, (x, top_y + round(H * 0.008)), thumb)
        shadow = shadow.filter(ImageFilter.GaussianBlur(W * 0.018))
        canvas = Image.alpha_composite(canvas, shadow)

        canvas.paste(thumb, (x, top_y), thumb)

        out = os.path.join(out_dir, f"{index:02d}-{name.split('-', 1)[1]}.png")
        canvas.convert("RGB").save(out, "PNG")
        made.append(os.path.basename(out))
    return made


if __name__ == "__main__":
    jobs = [
        ("shots_de", "store/de-DE/iphone-6.9", "de", False),
        ("shots_iphone_en", "store/en-US/iphone-6.9", "en", False),
        ("shots_ipad_de", "store/de-DE/ipad-13", "de", True),
        ("shots_ipad_en", "store/en-US/ipad-13", "en", True),
    ]
    for src, out, lang, tablet in jobs:
        src_dir = os.path.join(SCRATCH, src)
        out_dir = os.path.join(SCRATCH, out)
        if not os.path.isdir(src_dir):
            print("Quelle fehlt:", src_dir)
            continue
        names = build(src_dir, out_dir, lang, tablet)
        print(out, len(names), names)
