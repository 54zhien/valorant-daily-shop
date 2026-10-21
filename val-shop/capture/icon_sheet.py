#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把三个图标方案拼成一张对比图

为什么要放小尺寸：app 图标在桌面上只有 60pt 左右，
1024px 好看没用 —— 缩到 60pt 还认得出才算数。
"""
from __future__ import annotations

import pathlib
import sys

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parents[2]
PREV = ROOT / "val-shop-ios/Icon/preview"

NAMES = [
    ("icon-a-badge", "A  玻璃 V + 购物袋徽章"),
    ("icon-b-bag", "B  V 装在购物袋里"),
    ("icon-c-tag", "C  玻璃 V + 吊牌"),
]

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def rr(im: Image.Image, radius: int) -> Image.Image:
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, im.width - 1, im.height - 1],
                                        radius=radius, fill=255)
    out = im.convert("RGBA")
    out.putalpha(m)
    return out


def main() -> int:
    big = 340
    small = 96
    pad = 34
    label_h = 34

    W = pad + (big + pad) * 3
    H = pad + label_h + big + 28 + small + 28 + label_h + pad
    sheet = Image.new("RGBA", (W, H), (28, 30, 38, 255))
    d = ImageDraw.Draw(sheet)

    x = pad
    for name, label in NAMES:
        p = PREV / f"{name}.png"
        if not p.exists():
            print(f"  缺 {p}")
            continue
        src = Image.open(p).convert("RGB")

        # 标题
        d.text((x, pad), label, fill=(235, 236, 240, 255))

        # 大图
        b = rr(src.resize((big, big), Image.LANCZOS), int(big * 0.2237))
        sheet.alpha_composite(b, (x, pad + label_h))

        # 小图（桌面上大概这么大）
        s = rr(src.resize((small, small), Image.LANCZOS), int(small * 0.2237))
        sheet.alpha_composite(s, (x, pad + label_h + big + 28))
        d.text((x + small + 16, pad + label_h + big + 28 + small // 2 - 6),
               "60pt", fill=(150, 152, 162, 255))

        x += big + pad

    out = PREV / "contact-sheet.png"
    sheet.convert("RGB").save(out, "PNG")
    print(f"  ✅ {out}  {sheet.width}x{sheet.height}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
