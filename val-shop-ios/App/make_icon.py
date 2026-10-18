#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 App 图标（1024x1024 PNG），零依赖：手写 PNG 编码。

设计：深色底 (#0F1923) + 品牌红 (#FF4655) 的 V 形。
颜色与掌瓦动态 UI 里用的是同一套。

用法：
    python make_icon.py <输出路径>
"""
import math
import struct
import sys
import zlib

SIZE = 1024

BG_IN = (0x16, 0x21, 0x2C)   # 中心略亮
BG_OUT = (0x0B, 0x13, 0x19)  # 边缘更暗
ACCENT = (0xFF, 0x46, 0x55)
ACCENT_HI = (0xFF, 0x7A, 0x84)  # 高光


def lerp(a, b, t):
    return a + (b - a) * t


def smoothstep(edge0, edge1, x):
    t = (x - edge0) / (edge1 - edge0)
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def dist_to_segment(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    denom = vx * vx + vy * vy
    t = 0.0 if denom == 0 else max(0.0, min(1.0, (wx * vx + wy * vy) / denom))
    cx, cy = ax + t * vx, ay + t * vy
    return math.hypot(px - cx, py - cy), t


def render():
    s = SIZE
    # V 的两条笔画（归一化坐标）
    ax, ay = 0.285, 0.285
    bx, by = 0.500, 0.750
    cx, cy = 0.715, 0.285
    stroke = 0.098          # 半宽
    rows = []

    for y in range(s):
        row = bytearray()
        py = (y + 0.5) / s
        for x in range(s):
            px = (x + 0.5) / s

            # --- 背景：径向渐变 ---
            d = math.hypot(px - 0.5, py - 0.36) / 0.78
            t = smoothstep(0.0, 1.0, d)
            r = lerp(BG_IN[0], BG_OUT[0], t)
            g = lerp(BG_IN[1], BG_OUT[1], t)
            b = lerp(BG_IN[2], BG_OUT[2], t)

            # --- V 形 ---
            d1, t1 = dist_to_segment(px, py, ax, ay, bx, by)
            d2, t2 = dist_to_segment(px, py, cx, cy, bx, by)
            dmin = min(d1, d2)

            # 抗锯齿 + 沿笔画的高光
            cover = 1.0 - smoothstep(stroke - 0.008, stroke + 0.008, dmin)
            if cover > 0.0:
                tt = min(t1, t2)
                hi = smoothstep(0.0, 0.85, tt) * 0.55
                ar = lerp(ACCENT[0], ACCENT_HI[0], hi)
                ag = lerp(ACCENT[1], ACCENT_HI[1], hi)
                ab = lerp(ACCENT[2], ACCENT_HI[2], hi)
                r = lerp(r, ar, cover)
                g = lerp(g, ag, cover)
                b = lerp(b, ab, cover)

            # --- V 外圈的一层柔光 ---
            glow = (1.0 - smoothstep(stroke, stroke + 0.20, dmin)) * 0.16
            if glow > 0.0:
                r = lerp(r, ACCENT[0], glow)
                g = lerp(g, ACCENT[1], glow)
                b = lerp(b, ACCENT[2], glow)

            row += bytes((int(round(r)), int(round(g)), int(round(b))))

        rows.append(bytes(row))
    return rows


def write_png(path, rows):
    h = len(rows)
    w = len(rows[0]) // 3

    def chunk(tag, data):
        out = struct.pack(">I", len(data)) + tag + data
        return out + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + r for r in rows)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")

    with open(path, "wb") as f:
        f.write(png)
    return len(png)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "AppIcon-1024.png"
    n = write_png(out, render())
    print(f"wrote {out} ({n} bytes)")
