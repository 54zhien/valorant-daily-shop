#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""量一下 actool 编出来的图标里，各处颜色到底被改了多少。

用途：判断「玻璃层」是压在 V 上面还是垫在下面 —— 如果 V 被压了，
颜色会比源图的 #FF4655 暗一截；雨棚的 #E8323F / #F4EFE6 同理。
"""
from __future__ import annotations

import sys
from collections import Counter

from PIL import Image

SRC_V = (0xFF, 0x46, 0x55)
SRC_AWN_RED = (0xE8, 0x32, 0x3F)
SRC_AWN_CREAM = (0xF4, 0xEF, 0xE6)


def pct(got, want):
    return [round(g / w * 100) for g, w in zip(got, want)]


def main() -> int:
    for name in sys.argv[1:]:
        im = Image.open(name).convert("RGB")
        w, h = im.size
        px = im.load()

        def at(fx, fy):
            return px[int(w * fx), int(h * fy)]

        print(f"\n{name}  {w}x{h}")
        for label, fx, fy in [("雨棚红条", 0.17, 0.13), ("雨棚米白", 0.29, 0.13),
                              ("V 左臂", 0.33, 0.45), ("V 右臂", 0.62, 0.44),
                              ("橱窗空白", 0.50, 0.80), ("图标底色", 0.06, 0.50)]:
            print(f"  {label:8} {at(fx, fy)}")

        print("  实测/源色 百分比：")
        print(f"    红条 {pct(at(0.17, 0.13), SRC_AWN_RED)}%   米白 {pct(at(0.29, 0.13), SRC_AWN_CREAM)}%")
        print(f"    V    {pct(at(0.33, 0.45), SRC_V)}%")
        print("  最常见 6 色:", Counter(im.getdata()).most_common(6))
    return 0


if __name__ == "__main__":
    sys.exit(main())
