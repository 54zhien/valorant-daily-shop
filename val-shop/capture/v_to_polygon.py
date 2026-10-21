#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把抠出来的 V 标位图变成**多边形顶点**，供矢量级重画

## 为什么

第一版直接用位图放大：8 倍最近邻 + LANCZOS 降采样。
结果斜边全是**明显阶梯** —— 源图只有 179px，二值遮罩放大后步进太粗。

看 4 倍放大图之后才明白这个 V 的真实结构：

  · 左臂是个**弯折的缎带**（六边形，不是平行四边形）——
    上段近乎垂直，中途拐一下，下段斜着到底
  · 右臂是四边形，从右上角斜下来

幸好每一行里**每个臂都恰好是一个连续区间**（到 y≈109 才合并），
所以可以「逐行取 min/max x」拼出轮廓，再 Douglas-Peucker 简化成十来个点。
这样画出来的边缘是数学直线，抗锯齿交给降采样 —— 干净利落。
"""
from __future__ import annotations

import json
import math
import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "val-shop-ios/Icon/valorant-v-raw.png"
OUT = ROOT / "val-shop-ios/Icon/v-polygon.json"

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def runs_at(ap, w: int, y: int) -> list[tuple[int, int]]:
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


def rdp(points: list[tuple[float, float]], eps: float) -> list[tuple[float, float]]:
    """Douglas-Peucker 折线简化"""
    if len(points) < 3:
        return points
    x1, y1 = points[0]
    x2, y2 = points[-1]
    dmax, idx = 0.0, 0
    for i in range(1, len(points) - 1):
        x0, y0 = points[i]
        # 点到线段的距离
        dx, dy = x2 - x1, y2 - y1
        den = math.hypot(dx, dy)
        if den < 1e-9:
            d = math.hypot(x0 - x1, y0 - y1)
        else:
            d = abs(dy * x0 - dx * y0 + x2 * y1 - y2 * x1) / den
        if d > dmax:
            dmax, idx = d, i
    if dmax > eps:
        left = rdp(points[:idx + 1], eps)
        right = rdp(points[idx:], eps)
        return left[:-1] + right
    return [points[0], points[-1]]


def main() -> int:
    img = Image.open(SRC).convert("RGBA")
    a = img.getchannel("A")
    w, h = img.size
    ap = a.load()
    print(f"源图 {w}x{h}")

    # 找两臂合并的那一行
    split_y = h
    for y in range(h):
        if len(runs_at(ap, w, y)) < 2:
            split_y = y
            break
    print(f"两臂在 y={split_y} 合并")

    # ---- 左臂：每行第一个区间 ----
    left_edge, right_edge = [], []
    for y in range(split_y):
        rs = runs_at(ap, w, y)
        if not rs:
            continue
        left_edge.append((rs[0][0], y))
        right_edge.append((rs[0][1], y))
    # 顺时针：沿左缘向下，再沿右缘向上
    left_poly = left_edge + right_edge[::-1]

    # ---- 右臂：每行最后一个区间 ----
    left_edge2, right_edge2 = [], []
    for y in range(split_y):
        rs = runs_at(ap, w, y)
        if len(rs) < 2:
            continue
        left_edge2.append((rs[-1][0], y))
        right_edge2.append((rs[-1][1], y))
    right_poly = left_edge2 + right_edge2[::-1]

    # ---- 下半截：合并之后的部分（一个区间，从 split_y 到底）----
    bottom_edge, bottom_right = [], []
    for y in range(split_y, h):
        rs = runs_at(ap, w, y)
        if not rs:
            continue
        bottom_edge.append((rs[0][0], y))
        bottom_right.append((rs[-1][1], y))
    bottom_poly = bottom_edge + bottom_right[::-1]

    def simplify(poly, eps=1.6):
        if not poly:
            return []
        closed = poly + [poly[0]]
        s = rdp(closed, eps)
        if len(s) > 1 and s[-1] == s[0]:
            s = s[:-1]
        return [(round(x, 2), round(y, 2)) for x, y in s]

    L = simplify(left_poly)
    R = simplify(right_poly)
    B = simplify(bottom_poly)

    print(f"\n左臂上段 {len(L)} 点: {L}")
    print(f"\n右臂     {len(R)} 点: {R}")
    print(f"\n下段     {len(B)} 点: {B}")

    # 合并成两个封闭多边形：
    #   左 = 左上缎带 + 下半截（它们本来就连着）
    #   右 = 单独的四边形
    # 为了简单，直接把三段都存下来，画的时候分别填充 —— 重叠区域同色看不出接缝
    data = {"width": w, "height": h, "parts": [L, R, B]}
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"\n已存 -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
