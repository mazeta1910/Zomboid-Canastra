"""Generates the mod's UI textures (suits, card faces/backs, court emblems, icons, poster).

Suits, emblems and card backgrounds are drawn as vector shapes and exported at several pixel
sizes so the game never has to shrink a texture much (small downscales stay crisp).
Suits and emblems are white and tinted at draw time (allows the optional four-colour deck).

Usage: python tools/generate_textures.py   (requires Pillow and the Windows fonts)
"""
import math
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD = os.path.join(ROOT, "Contents", "mods", "Canastra", "42")
UI = os.path.join(MOD, "media", "ui", "Canastra")
FONTS = "C:/Windows/Fonts/"

SYMBOL = FONTS + "seguisym.ttf"
ICONS = FONTS + "segmdl2.ttf"
BOLD = FONTS + "seguibl.ttf"
RANK_FONT = FONTS + "segoeuib.ttf"

WHITE = (255, 255, 255, 255)
# Keep in sync with CanastraDraw.SUIT_COLORS.
COLORS = {
    "spade": (22, 22, 28), "heart": (200, 24, 36), "club": (22, 22, 28), "diamond": (200, 24, 36),
}
COLORS4 = {
    "spade": (22, 22, 28), "heart": (200, 24, 36), "club": (18, 125, 55), "diamond": (25, 90, 200),
}
FACE_BG = (252, 250, 244)
FACE_BORDER = (120, 115, 105)
GOLD = (200, 160, 60)

SUIT_SIZES = [12, 14, 16, 20, 24, 28, 32, 40, 48, 64, 96, 128]
EMBLEM_SIZES = [16, 24, 32, 48, 64, 96]
CARD_WIDTHS = [32, 48, 64, 96]
SS = 1024  # supersampled canvas for vector shapes


def save(img, name):
    os.makedirs(UI, exist_ok=True)
    img.save(os.path.join(UI, name))


# ----------------------------------------------------------------- suit shapes (unit square)

def heart_points(n=240, flip=False, box=(0.06, 0.08, 0.94, 0.92)):
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        x = 16 * math.sin(t) ** 3
        y = -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t))
        pts.append((x, y))
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    bx0, by0, bx1, by1 = box
    out = []
    for x, y in pts:
        u = bx0 + (x - x0) / (x1 - x0) * (bx1 - bx0)
        v = (y - y0) / (y1 - y0)
        if flip:
            v = 1 - v
        out.append((u, by0 + v * (by1 - by0)))
    return out


def stem_points(top=0.56, bottom=0.97, neck=0.035, foot=0.2, n=40):
    left, right = [], []
    for i in range(n + 1):
        f = i / n
        y = top + (bottom - top) * f
        half = neck + (foot - neck) * f ** 2.4
        left.append((0.5 - half, y))
        right.append((0.5 + half, y))
    return left + right[::-1]


def diamond_points(n=60, bow=0.07):
    corners = [(0.5, 0.02), (0.9, 0.5), (0.5, 0.98), (0.1, 0.5)]
    pts = []
    for k in range(4):
        (ax, ay), (bx, by) = corners[k], corners[(k + 1) % 4]
        mx, my = (ax + bx) / 2, (ay + by) / 2
        # bow the edge towards the centre
        cx, cy = mx + (0.5 - mx) * bow * 2.2, my + (0.5 - my) * bow * 2.2
        for i in range(n):
            t = i / n
            x = (1 - t) ** 2 * ax + 2 * (1 - t) * t * cx + t ** 2 * bx
            y = (1 - t) ** 2 * ay + 2 * (1 - t) * t * cy + t ** 2 * by
            pts.append((x, y))
    return pts


def scaled(pts):
    return [(x * SS, y * SS) for x, y in pts]


def suit_shape(name):
    img = Image.new("L", (SS, SS), 0)
    d = ImageDraw.Draw(img)
    if name == "heart":
        d.polygon(scaled(heart_points(box=(0.04, 0.1, 0.96, 0.92))), fill=255)
    elif name == "diamond":
        d.polygon(scaled(diamond_points()), fill=255)
    elif name == "spade":
        d.polygon(scaled(heart_points(flip=True, box=(0.05, 0.02, 0.95, 0.76))), fill=255)
        d.polygon(scaled(stem_points()), fill=255)
    elif name == "club":
        r = 0.215
        for cx, cy in ((0.5, 0.23), (0.235, 0.57), (0.765, 0.57)):
            d.ellipse(((cx - r) * SS, (cy - r) * SS, (cx + r) * SS, (cy + r) * SS), fill=255)
        d.polygon(scaled([(0.5, 0.36), (0.36, 0.6), (0.64, 0.6)]), fill=255)
        d.polygon(scaled(stem_points(top=0.5, neck=0.045)), fill=255)
    return img


def export_mask(mask, size, color=WHITE, pad=0):
    inner = size - pad * 2
    small = mask.resize((inner, inner), Image.LANCZOS)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    layer = Image.new("RGBA", (inner, inner), color)
    layer.putalpha(small)
    img.alpha_composite(layer, (pad, pad))
    return img


def suits():
    for name in ("spade", "heart", "club", "diamond"):
        mask = suit_shape(name)
        for px in SUIT_SIZES:
            save(export_mask(mask, px), "suit_%s_%d.png" % (name, px))


# ----------------------------------------------------------------- court emblems and joker

def glyph_mask(ch, font_path, fill=0.86, offset=(0, 0)):
    img = Image.new("L", (SS, SS), 0)
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(font_path, int(SS * fill))
    box = d.textbbox((0, 0), ch, font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    scale = min(SS * fill / w, SS * fill / h)
    font = ImageFont.truetype(font_path, int(SS * fill * scale))
    box = d.textbbox((0, 0), ch, font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    d.text(((SS - w) / 2 - box[0] + offset[0] * SS, (SS - h) / 2 - box[1] + offset[1] * SS), ch, font=font, fill=255)
    return img


def emblems():
    for name, ch in (("king", "\u265A"), ("queen", "\u265B"), ("jack", "\u265E")):
        # thicken the glyph strokes so the figures survive small sizes
        mask = glyph_mask(ch, SYMBOL, fill=0.84).filter(ImageFilter.MaxFilter(17))
        for px in EMBLEM_SIZES:
            save(export_mask(mask, px), "emblem_%s_%d.png" % (name, px))


def star_points(cx, cy, r_out, r_in, n=5, rot=-90):
    pts = []
    for i in range(n * 2):
        r = r_out if i % 2 == 0 else r_in
        a = math.radians(rot + i * 180 / n)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def joker_image(size):
    s = SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # jester hat: three drooping points in red, purple and green with gold bells
    tips = [((0.1, 0.48), (190, 30, 45)), ((0.5, 0.06), (110, 50, 160)), ((0.9, 0.48), (25, 130, 70))]
    base_l, base_r = (0.2 * s, 0.86 * s), (0.8 * s, 0.86 * s)
    for (tx, ty), col in tips:
        d.polygon([base_l, (0.5 * s, 0.62 * s), base_r, (tx * s, ty * s)], fill=col + (255,))
    for (tx, ty), col in tips:
        d.polygon([(0.5 * s, 0.62 * s), (tx * s, ty * s), ((0.5 + (tx - 0.5) * 0.35) * s, 0.86 * s)],
                  fill=tuple(int(c * 0.75) for c in col) + (255,))
    d.rounded_rectangle((0.16 * s, 0.8 * s, 0.84 * s, 0.95 * s), radius=0.04 * s, fill=GOLD + (255,))
    for (tx, ty), _ in tips:
        r = 0.075 * s
        d.ellipse((tx * s - r, ty * s - r, tx * s + r, ty * s + r), fill=(240, 200, 70, 255), outline=(150, 110, 30, 255), width=int(0.015 * s))
    return img.resize((size, size), Image.LANCZOS)


def joker():
    for px in EMBLEM_SIZES:
        save(joker_image(px), "joker_%d.png" % px)


# ----------------------------------------------------------------- card backgrounds

def card_size(w):
    return w, int(round(w * 1.4))


def rounded_mask(w, h, radius, scale=8):
    m = Image.new("L", (w * scale, h * scale), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w * scale - 1, h * scale - 1), radius=radius * scale, fill=255)
    return m.resize((w, h), Image.LANCZOS)


def card_face_image(w):
    w, h = card_size(w)
    sc = 8
    big = Image.new("RGBA", (w * sc, h * sc), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    radius = max(3, w * 0.09) * sc
    border = max(1, w / 48) * sc
    d.rounded_rectangle((0, 0, w * sc - 1, h * sc - 1), radius=radius, fill=FACE_BORDER + (255,))
    d.rounded_rectangle((border, border, w * sc - 1 - border, h * sc - 1 - border), radius=radius - border, fill=FACE_BG + (255,))
    # faint warm gradient towards the bottom
    grad = Image.new("RGBA", big.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    for y in range(0, h * sc, sc):
        a = int(18 * (y / (h * sc)))
        gd.line((0, y, w * sc, y), fill=(120, 100, 60, a), width=sc)
    mask = Image.new("L", big.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((border, border, w * sc - 1 - border, h * sc - 1 - border), radius=radius - border, fill=255)
    big = Image.composite(Image.alpha_composite(big, grad), big, mask)
    return big.resize((w, h), Image.LANCZOS)


def card_back_image(w):
    w, h = card_size(w)
    sc = 8
    W, H = w * sc, h * sc
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    radius = max(3, w * 0.09) * sc
    d.rounded_rectangle((0, 0, W - 1, H - 1), radius=radius, fill=(250, 248, 240, 255))
    m = max(2, w * 0.07) * sc
    inner = (m, m, W - m, H - m)
    pattern = Image.new("RGBA", (W, H), (120, 20, 30, 255))
    pd = ImageDraw.Draw(pattern)
    step = max(6, w * 0.16) * sc
    lw = max(1, int(w / 40 * sc))
    i = -H
    while i < W + H:
        pd.line((i, 0, i + H, H), fill=(160, 40, 50, 255), width=lw)
        pd.line((i, H, i + H, 0), fill=(160, 40, 50, 255), width=lw)
        i += step
    # central medallion with a spade
    cx, cy, r = W / 2, H / 2, W * 0.26
    pd.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(120, 20, 30, 255), outline=GOLD + (255,), width=max(sc, int(w / 28 * sc)))
    spade = suit_shape("spade").resize((int(r * 1.15), int(r * 1.15)), Image.LANCZOS)
    gold = Image.new("RGBA", spade.size, GOLD + (255,))
    gold.putalpha(spade)
    pattern.alpha_composite(gold, (int(cx - spade.width / 2), int(cy - spade.height / 2)))
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle(inner, radius=radius * 0.6, fill=255)
    img.paste(pattern, (0, 0), mask)
    d.rounded_rectangle(inner, radius=radius * 0.6, outline=GOLD + (255,), width=max(sc, int(w / 40 * sc)))
    d.rounded_rectangle((0, 0, W - 1, H - 1), radius=radius, outline=FACE_BORDER + (255,), width=max(sc, int(w / 48 * sc)))
    return img.resize((w, h), Image.LANCZOS)


def card_backgrounds():
    for w in CARD_WIDTHS:
        save(card_face_image(w), "card_face_%d.png" % w)
        save(card_back_image(w), "card_back_%d.png" % w)


# ----------------------------------------------------------------- icons

ICON_GLYPHS = {
    "meld": "\uE710", "discard": "\uE896", "sortrank": "\uE8CB", "clear": "\uE711",
    "info": "\uE946", "leave": "\uF3B1", "bot": "\uE99A", "sit": "\uE77B",
    "start": "\uE768", "prev": "\uE76B", "next": "\uE76C", "refresh": "\uE72C",
    "rules": "\uE713", "confirm": "\uE73E", "remove": "\uE74D", "nextround": "\uE893",
    "back": "\uE72B", "swap": "\uE8AB",
}


def glyph(ch, font_path, size, color, canvas, scale=4, offset=(0, 0)):
    big = Image.new("RGBA", (canvas[0] * scale, canvas[1] * scale), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    font = ImageFont.truetype(font_path, size * scale)
    box = d.textbbox((0, 0), ch, font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    x = (big.width - w) / 2 - box[0] + offset[0] * scale
    y = (big.height - h) / 2 - box[1] + offset[1] * scale
    d.text((x, y), ch, font=font, fill=color)
    return big.resize(canvas, Image.LANCZOS)


def icons():
    for name, ch in ICON_GLYPHS.items():
        save(glyph(ch, ICONS, 22, WHITE, (32, 32)), "icon_%s.png" % name)
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    img.alpha_composite(export_mask(suit_shape("spade"), 15), (4, 3))
    img.alpha_composite(export_mask(suit_shape("heart"), 15), (13, 14))
    save(img, "icon_sortsuit.png")
    # four-colour deck toggle: one suit per quadrant
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    for i, name in enumerate(("spade", "heart", "club", "diamond")):
        img.alpha_composite(export_mask(suit_shape(name), 13), (3 + (i % 2) * 14, 3 + (i // 2) * 14))
    save(img, "icon_colors.png")


# ----------------------------------------------------------------- composed cards (poster / preview)
# Mirrors CanastraDraw.drawCard so the poster and the preview sheet match the game.

RANKS = {1: "A", 11: "J", 12: "Q", 13: "K"}
EMBLEM = {11: "jack", 12: "queen", 13: "king"}


def tinted(name, size, color):
    src = Image.open(os.path.join(UI, name)).convert("RGBA").resize((size, size), Image.LANCZOS)
    layer = Image.new("RGBA", src.size, color + (255,))
    layer.putalpha(src.split()[3])
    return layer


def pick(sizes, px):
    for s in sizes:
        if s >= px:
            return s
    return sizes[-1]


def compose_card(rank, suit, w, mini=False, four=False, font_px=None):
    """rank 0 = joker."""
    _, h = card_size(w)
    face = Image.open(os.path.join(UI, "card_face_%d.png" % pick(CARD_WIDTHS, w))).resize((w, h), Image.LANCZOS)
    card = face.copy()
    d = ImageDraw.Draw(card)
    color = (COLORS4 if four else COLORS)[suit] if suit else (110, 50, 160)
    pad = max(2, int(w * 0.08))
    font_px = font_px or (int(w * 0.36) if not mini else int(w * 0.42))
    font = ImageFont.truetype(RANK_FONT, font_px)
    label = "JK" if rank == 0 else RANKS.get(rank, str(rank))
    box = d.textbbox((0, 0), label, font=font)
    d.text((pad - box[0] + (1 if label == "10" else 0), pad // 2 - box[1] + 1), label, font=font, fill=color + (255,))
    iy = pad // 2 + (box[3] - box[1]) + max(2, int(w * 0.06))
    isz = int(w * (0.42 if mini else 0.3))
    if rank == 0:
        card.alpha_composite(joker_image(isz), (pad, iy))
    else:
        card.alpha_composite(tinted("suit_%s_%d.png" % (suit, pick(SUIT_SIZES, isz)), isz, color), (pad, iy))
    if mini:
        return card
    if rank == 0:
        s = int(w * 0.62)
        card.alpha_composite(joker_image(s), (w - s - pad, h - s - pad))
    elif rank in EMBLEM:
        s = int(w * 0.6)
        card.alpha_composite(tinted("emblem_%s_%d.png" % (EMBLEM[rank], pick(EMBLEM_SIZES, s)), s, color),
                             (w - s - pad + 1, h - s - pad + 1))
    else:
        s = int(w * (0.62 if rank == 1 else 0.5))
        card.alpha_composite(tinted("suit_%s_%d.png" % (suit, pick(SUIT_SIZES, s)), s, color), (w - s - pad, h - s - pad))
    return card


def poster():
    size = 512
    img = Image.new("RGBA", (size, size), (18, 70, 40, 255))
    d = ImageDraw.Draw(img)
    for r in range(size // 2, 0, -4):
        c = int(40 + 30 * (r / (size / 2)))
        d.ellipse((size / 2 - r * 1.3, size / 2 - r, size / 2 + r * 1.3, size / 2 + r), fill=(18, c + 30, 40, 255))
    back = card_back_image(150)
    cards = [compose_card(r, s, 150) for r, s in ((1, "spade"), (13, "heart"), (12, "diamond"), (11, "club"))]
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    layer.alpha_composite(back.rotate(28, expand=True, resample=Image.BICUBIC), (30, 110))
    angles = [-21, -7, 7, 21]
    for i, card in enumerate(cards):
        rot = card.rotate(-angles[i], expand=True, resample=Image.BICUBIC)
        layer.alpha_composite(rot, (70 + i * 72, 100 + abs(angles[i]) * 2))
    shadow = layer.split()[3].filter(ImageFilter.GaussianBlur(8))
    sh = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sh.putalpha(shadow.point(lambda a: int(a * 0.5)))
    img.alpha_composite(sh, (6, 8))
    img.alpha_composite(layer)
    d = ImageDraw.Draw(img)
    title = ImageFont.truetype(BOLD, 64)
    text = "BURACO"
    bw = d.textbbox((0, 0), text, font=title)
    d.text(((size - bw[2]) / 2 + 3, 393), text, font=title, fill=(0, 0, 0, 160))
    d.text(((size - bw[2]) / 2, 390), text, font=title, fill=(250, 235, 180, 255))
    sub = ImageFont.truetype(BOLD, 30)
    text = "& CANASTRA"
    bw = d.textbbox((0, 0), text, font=sub)
    d.text(((size - bw[2]) / 2, 462), text, font=sub, fill=(230, 230, 230, 255))
    img.convert("RGB").save(os.path.join(MOD, "poster.png"))
    img.resize((256, 256), Image.LANCZOS).convert("RGB").save(os.path.join(ROOT, "preview.png"))
    ic = Image.new("RGBA", (64, 64), (18, 90, 50, 255))
    ic.alpha_composite(compose_card(1, "spade", 44), (10, 1))
    ic.save(os.path.join(MOD, "icon.png"))


def preview_sheet(path):
    """Cards at in-game sizes (hand 40 px, meld 28 px) on the table colour, 3x zoom."""
    hand = [(1, "spade"), (7, "club"), (10, "heart"), (11, "diamond"), (12, "club"), (13, "spade"), (0, None)]
    minis = [(3, "spade"), (4, "spade"), (5, "spade"), (6, "club"), (7, "club"), (8, "club"), (9, "club")]
    rows = []
    for four in (False, True):
        row = Image.new("RGBA", (520, 150), (22, 75, 45, 255))
        x = 8
        for r, s in hand:
            row.alpha_composite(compose_card(r, s, 40, four=four), (x, 8))
            x += 44
        x = 8
        for i, (r, s) in enumerate(minis):
            row.alpha_composite(compose_card(r, s, 28, mini=True, four=four), (x + i * 20, 80))
        bx = 8 + 7 * 44 + 10
        row.alpha_composite(card_back_image(40), (bx, 8))
        rows.append(row)
    sheet = Image.new("RGBA", (520, 300))
    sheet.alpha_composite(rows[0], (0, 0))
    sheet.alpha_composite(rows[1], (0, 150))
    sheet = sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST)
    big = Image.new("RGBA", (1040, 330), (22, 75, 45, 255))
    for i, (r, s) in enumerate([(1, "spade"), (13, "heart"), (12, "club"), (11, "diamond"), (0, None)]):
        big.alpha_composite(compose_card(r, s, 160), (10 + i * 172, 10))
    big.alpha_composite(card_back_image(160), (10 + 5 * 172, 10))
    out = Image.new("RGBA", (1040, 930), (22, 75, 45, 255))
    out.alpha_composite(big, (0, 0))
    out.alpha_composite(sheet, (0, 330))
    out.convert("RGB").save(path)


if __name__ == "__main__":
    import sys
    suits()
    emblems()
    joker()
    card_backgrounds()
    icons()
    poster()
    if len(sys.argv) > 1:
        preview_sheet(sys.argv[1])
    print("textures written to", UI)
