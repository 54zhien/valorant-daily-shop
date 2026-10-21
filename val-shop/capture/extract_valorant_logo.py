#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从掌瓦 APK 里抠出无畏契约官方 V 标

## 来源

work/apk/res/drawable-xxhdpi-v4/img_valorant_1.png（1032x690）
左上那块橙色角形 V —— 这是官方标志，不是掌瓦自己画的。

## 做法

1. 按颜色挑：V 是纯橙（约 #F5A623~#FF7A45），背景是深藏青
   -> 只保留色相在橙区、且够亮的像素，其余全透明
2. 裁到实际边界（去掉四周空白）
3. 存成透明 PNG

用颜色挑而不是「按矩形裁」的理由：矩形裁会把背景一起带走，
而图标需要透明底才能贴到任何新背景上。
"""
from __future__ import annotations

import colorsys
import pathlib
import sys

try:
    from PIL import Image
except ImportError:
    print("  需要 Pillow：pip install pillow")
    sys.exit(1)

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "work/apk/res/drawable-xxhdpi-v4/img_valorant_1.png"
OUT_DIR = ROOT / "val-shop-ios/Icon"
OUT_DIR.mkdir(parents=True, exist_ok=True)

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def main() -> int:
    img = Image.open(SRC).convert("RGBA")
    w, h = img.size
    print(f"源图 {w}x{h}")

    # ⚠️ 必须先限定区域。
    #
    # 第一次没限定，纯按橙色挑 —— 结果把右侧英雄卡面里的橙色皮肤、
    # 火焰、枪械涂装全捞进来了，边界框大到 987x592（整张图）。
    #
    # V 标在左上角这块：（凭源图目测，后面再按命中范围微调）
    REGION = (120, 175, 380, 375)
    x0, y0, x1, y1 = REGION
    print(f"只看区域 {REGION}")

    px = img.load()
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    op = out.load()

    kept = 0
    minx, miny, maxx, maxy = w, h, -1, -1

    for y in range(y0, min(y1, h)):
        for x in range(x0, min(x1, w)):
            r, g, b, _ = px[x, y]
            hh, ll, ss = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
            hue = hh * 360
            # 官方 V 的橙：色相约 20~45，饱和度够、亮度中等偏上
            is_orange = 18 <= hue <= 48 and ss >= 0.45 and 0.30 <= ll <= 0.95
            if is_orange:
                op[x, y] = (r, g, b, 255)
                kept += 1
                if x < minx: minx = x
                if x > maxx: maxx = x
                if y < miny: miny = y
                if y > maxy: maxy = y

    print(f"命中橙色像素 {kept} 个")
    if kept < 500:
        print("  ❌ 太少，色相范围可能不对")
        return 1

    crop = out.crop((minx, miny, maxx + 1, maxy + 1))
    print(f"边界框 ({minx},{miny}) - ({maxx},{maxy})  尺寸 {crop.size[0]}x{crop.size[1]}")

    dst = OUT_DIR / "valorant-v-raw.png"
    crop.save(dst)
    print(f"已存 -> {dst}")

    # 顺带把颜色统计出来，做图标时用同一套色
    crop2 = crop.resize((64, 64), Image.LANCZOS)
    cpx = crop2.load()
    samples = []
    for y in range(64):
        for x in range(64):
            r, g, b, a = cpx[x, y]
            if a > 200:
                samples.append((r, g, b))
    if samples:
        samples.sort(key=lambda c: sum(c))
        mid = samples[len(samples) // 3]
        print(f"  主色（中位）: #{mid[0]:02X}{mid[1]:02X}{mid[2]:02X}")
        lo = samples[len(samples) // 6]
        hi = samples[-len(samples) // 6]
        print(f"  偏暗: #{lo[0]:02X}{lo[1]:02X}{lo[2]:02X}")
        print(f"  偏亮: #{hi[0]:02X}{hi[1]:02X}{hi[2]:02X}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
