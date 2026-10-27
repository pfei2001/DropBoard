# -*- coding: utf-8 -*-
"""
DropBoard 图标生成器
正式图标为方案 B（三色横条）：输出根目录 DropBoard.ico（16/32/48/64/128/256）
+ icons/DropBoard.png（README 用）+ icons/preview.png（三套方案拼版，仅供比对）。
方案 A / C 的绘制函数保留作设计参考，不再产出文件。
纯 Pillow 绘制，1024 画布超采样后缩到各尺寸。用 py -3 运行。
"""
import os
from PIL import Image, ImageDraw, ImageFont

BASE = 1024
OUT = os.path.dirname(os.path.abspath(__file__))
FONT_BOLD = "C:/Windows/Fonts/segoeuib.ttf"

# 三页主色（与 DropBoard.ahk 的 TABS 一致）
C_FOLDER = (0x5B, 0x6C, 0xF0)
C_FILE = (0x19, 0xB3, 0x9E)
C_URL = (0xE0, 0x71, 0x3F)
DARK = (0x15, 0x17, 0x1C)
BORDER = (0x2E, 0x33, 0x45)
WHITE = (0xFF, 0xFF, 0xFF)
RADIUS = 224                 # 256px 下约 56，接近 squircle
ICO_SIZES = [256, 128, 64, 48, 32, 16]


def vgrad(size, c1, c2):
    w, h = size
    strip = Image.new("RGB", (1, h))
    px = strip.load()
    for y in range(h):
        t = y / (h - 1)
        px[0, y] = tuple(round(a + (b - a) * t) for a, b in zip(c1, c2))
    return strip.resize((w, h), Image.BICUBIC)


def canvas(top, bot, border=None):
    """圆角方形底，四角透明"""
    bg = vgrad((BASE, BASE), top, bot).convert("RGBA")
    mask = Image.new("L", (BASE, BASE), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, BASE - 1, BASE - 1], radius=RADIUS, fill=255)
    out = Image.new("RGBA", (BASE, BASE), (0, 0, 0, 0))
    out.paste(bg, (0, 0), mask)
    if border:
        ImageDraw.Draw(out).rounded_rectangle(
            [0, 0, BASE - 1, BASE - 1], radius=RADIUS, outline=border, width=10)
    return out


def polyline(d, pts, w, fill):
    """带圆头的折线"""
    d.line(pts, fill=fill, width=w, joint="curve")
    r = w / 2
    for x, y in (pts[0], pts[-1]):
        d.ellipse([x - r, y - r, x + r, y + r], fill=fill)


# ---------------------------------------------------------------- 方案 A
def scheme_a():
    """Tray：上宽下窄的敞口托盘 + 正落下的方块。靛蓝渐变底"""
    bg = canvas((0x71, 0x82, 0xF8), (0x3A, 0x49, 0xD0))
    d = ImageDraw.Draw(bg)

    w = 88
    pts = [(258, 386), (300, 764), (724, 764), (766, 386)]
    polyline(d, pts, w, WHITE)

    s = 144
    d.rounded_rectangle([512 - s // 2, 386 - 10 - s, 512 + s // 2, 386 - 10],
                        radius=40, fill=WHITE)
    return bg


# ---------------------------------------------------------------- 方案 B
def scheme_b():
    """Tri-Slot：三色横条，对应三个标签页"""
    img = canvas(DARK, DARK, border=BORDER)
    d = ImageDraw.Draw(img)

    bw, bh, gap = 620, 148, 84
    total = bh * 3 + gap * 2
    x0 = (BASE - bw) // 2
    y = (BASE - total) // 2
    for col in (C_FOLDER, C_FILE, C_URL):
        d.rounded_rectangle([x0, y, x0 + bw, y + bh], radius=bh // 2, fill=col)
        y += bh + gap
    return img


# ---------------------------------------------------------------- 方案 C
def scheme_c():
    """Monogram D：字母 D 立在一条橙色底座上，底座宽度按字形实测宽度推算"""
    img = canvas(DARK, DARK, border=BORDER)
    d = ImageDraw.Draw(img)

    font = ImageFont.truetype(FONT_BOLD, 480)
    bbox = d.textbbox((0, 0), "D", font=font)
    gw, gh = bbox[2] - bbox[0], bbox[3] - bbox[1]

    cx = 512
    top = 232                                       # D 的顶边
    d.text((cx - gw / 2 - bbox[0], top - bbox[1]), "D", font=font, fill=WHITE)

    bar_w = round(gw * 0.95)
    bar_h = 88
    bar_top = top + gh + 96                         # 与字形底部留 96 的呼吸
    d.rounded_rectangle([cx - bar_w // 2, bar_top, cx + bar_w // 2, bar_top + bar_h],
                        radius=bar_h // 2, fill=C_URL)
    return img


SCHEMES = [("A-box", "A  Box + drop", scheme_a),
           ("B-slots", "B  Three slots", scheme_b),
           ("C-monogram", "C  Monogram D", scheme_c)]
FINAL = scheme_b          # 定稿方案


def main():
    os.makedirs(OUT, exist_ok=True)
    root = os.path.dirname(OUT)

    img = FINAL()
    img.save(os.path.join(root, "DropBoard.ico"),
             format="ICO", sizes=[(s, s) for s in ICO_SIZES])
    img.resize((256, 256), Image.LANCZOS).save(
        os.path.join(OUT, "DropBoard.png"))
    print("[ok] DropBoard.ico + icons/DropBoard.png")

    # 拼版：三套都画一遍留档，只存 preview.png
    tiles = [(label, fn()) for _, label, fn in SCHEMES]
    pad, tile = 48, 256
    row2 = 96 + 40
    W = pad + (tile + pad) * 3
    H = pad + tile + 46 + row2 + pad
    sheet = Image.new("RGBA", (W, H), (0x0B, 0x0C, 0x0F, 255))
    sd = ImageDraw.Draw(sheet)
    lab = ImageFont.truetype(FONT_BOLD, 30)
    tiny = ImageFont.truetype(FONT_BOLD, 18)

    for i, (label, im) in enumerate(tiles):
        x = pad + i * (tile + pad)
        sheet.alpha_composite(im.resize((tile, tile), Image.LANCZOS), (x, pad))
        sd.text((x, pad + tile + 14), label, font=lab, fill=(0xD6, 0xDC, 0xEA))
        sx = x + 2
        sy = pad + tile + 54
        for size in (48, 32, 16):
            sheet.alpha_composite(im.resize((size, size), Image.LANCZOS), (sx, sy))
            sd.text((sx, sy + size + 8), str(size), font=tiny, fill=(0x6C, 0x74, 0x8A))
            sx += size + 32
    sheet.convert("RGB").save(os.path.join(OUT, "preview.png"))
    print("[ok] icons/preview.png")


if __name__ == "__main__":
    main()
