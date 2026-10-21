#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
量出官方 V 标的几何顶点，供「当多边形重画」用

## 为什么不直接放大位图

第一版用「8 倍最近邻 + LANCZOS 降采样」，出来的斜边是**明显阶梯**——
因为源图只有 179px，二值遮罩的硬边放大后步进太粗，降采样抹不平。

正确的做法是把它当**几何图形**处理：量出顶点，用 ImageDraw.polygon
在 4 倍画布上画，再降采样 —— 边缘是数学上锐利的斜线，抗锯齿由降采样负责。

幸好官方 V 就是**两片平行四边形**，顶点没几个。
"""
from __future__ import annotations

import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "val-shop-ios/Icon/valorant-v-raw.png"

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def main() -> int:
    img = Image.open(SRC).convert("RGBA")
    a = img.getchannel("A")
    w, h = img.size
    ap = a.load()
    print(f"源图 {w}x{h}")

    # 按列/行扫出每个不透明像素，然后按「左上片 / 右上片」分组
    # 分界线：V 中间那道缝在 x 约 128 附近
    def spans(y: int) -> list[tuple[int, int]]:
        """返回这一行里所有连续不透明区间"""
        out, start = [], None
        for x in range(w):
            on = ap[x, y] >= 128
            if on and start is None:
                start = x
            elif not on and start is not None:
                out.append((start, x - 1))
                start = None
        if start is not None:
            out.append((start, w - 1))
        return out

    print("\n逐行采样（y: 区间…）")
    probe = [0, 1, 2, h // 4, h // 2, 3 * h // 4, h - 3, h - 2, h - 1]
    for y in probe:
        print(f"  y={y:3}: {spans(y)}")

    # 第一行 / 最后一行的区间就是顶边和底边
    top = spans(0)
    print(f"\n顶边 (y=0): {top}")

    # 找最底下的行里右片的底边在哪
    print("\n每行区间的边界（用来定位拐点）")
    prev = None
    for y in range(h):
        s = spans(y)
        if s != prev:
            print(f"  y={y:3}: {s}")
            prev = s
        if y > 200:
            break

    return 0


if __name__ == "__main__":
    sys.exit(main())
