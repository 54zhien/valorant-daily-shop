#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
「皮肤商店」app 图标 —— v2

## 和 v1 的差别

v1 三个问题：
  1. V 的边缘是阶梯状（位图放大没做对）
  2. 背景糊成一团棕（径向光过强过宽）
  3. 价签太黑太重，"%" 像两个圈加一根棍

v2：
  · V 改成**多边形重画**（顶点由 v_to_polygon.py 量出来），
    在 4 倍画布上画再降采样 —— 斜边是数学直线，抗锯齿交给降采样
  · 背景压暗，暖光只留在 V 后面一小圈
  · 商店信号换成更好认的三个方案，见下

## 三个方案

A  玻璃 V + 购物袋徽章     右下角一个玻璃圆章，里面一个袋子剪影
B  V 装在购物袋里          袋子本身是玻璃罩，V 印在袋面
C  玻璃 V + 吊牌           右下角挂一个真正的吊牌（带孔和绳）

小尺寸下最耐看的是 A：V 够大，徽章是个熟悉的形状。
"""
from __future__ import annotations

import json
import math
import pathlib
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parents[2]
ICON = ROOT / "val-shop-ios/Icon"
POLY = ICON / "v-polygon.json"
OUT = ICON / "preview"
OUT.mkdir(parents=True, exist_ok=True)

SIZE = 1024
SS = 4                      # 超采样倍数
BIG = SIZE * SS

V_MAIN = (255, 172, 91)
V_LIGHT = (255, 221, 176)
V_DEEP = (255, 84, 52)

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


# ----------------------------------------------------------------------------
#  V 的多边形
# ----------------------------------------------------------------------------

def load_polys() -> tuple[list[list[tuple[float, float]]], tuple[int, int]]:
    d = json.loads(POLY.read_text(encoding="utf-8"))
    return [list(map(tuple, part)) for part in d["parts"]], (d["width"], d["height"])


def v_mask(target_w: int) -> Image.Image:
    """
    在 target_w 宽的透明画布上画出 V 的遮罩。

    先在 SS 倍大小的画布上画多边形（这时边缘是**像素级硬边**），
    再 LANCZOS 降回目标尺寸 —— 降采样本身就是最好的抗锯齿。
    """
    parts, (sw, sh) = load_polys()
    scale = target_w / sw
    target_h = int(round(sh * scale))

    big_w, big_h = target_w * SS, target_h * SS
    k = big_w / sw

    m = Image.new("L", (big_w, big_h), 0)
    d = ImageDraw.Draw(m)
    for part in parts:
        d.polygon([(x * k, y * k) for x, y in part], fill=255)

    return m.resize((target_w, target_h), Image.LANCZOS)


def v_layer(target_w: int, top=V_LIGHT, bottom=V_DEEP) -> Image.Image:
    """带渐变 + 边缘高光的 V"""
    m = v_mask(target_w)
    w, h = m.size

    # 竖直渐变
    grad = Image.new("RGB", (1, h))
    gp = grad.load()
    for y in range(h):
        gp[0, y] = mix(top, bottom, y / max(1, h - 1))
    grad = grad.resize((w, h), Image.BILINEAR).convert("RGBA")

    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(grad, (0, 0), m)

    # 边缘折射：上缘一条更亮的细线（玻璃侧面反光）
    eroded = m.filter(ImageFilter.MinFilter(5))
    edge = ImageChops.subtract(m, eroded)
    top_only = ImageChops.multiply(edge, ImageChops.offset(edge, 0, -SS))
    tint = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    tint.putalpha(top_only.point(lambda v: int(v * 0.55)))
    out.alpha_composite(tint)

    return out


def add_shadow(base: Image.Image, layer: Image.Image, cx: int, cy: int,
               blur: float, dy: int = 0, alpha: float = 0.55) -> None:
    """在 layer 下面垫一层模糊阴影"""
    sh = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    sh.paste(Image.new("RGBA", layer.size, (0, 0, 0, int(255 * alpha))),
             (0, 0), layer.getchannel("A"))
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    base.alpha_composite(sh, (int(cx - layer.width / 2), int(cy - layer.height / 2) + dy))


def paste_c(base: Image.Image, layer: Image.Image, cx: int, cy: int) -> None:
    base.alpha_composite(layer, (int(cx - layer.width / 2), int(cy - layer.height / 2)))


# ----------------------------------------------------------------------------
#  背景 / 玻璃
# ----------------------------------------------------------------------------

def backdrop(glow_r: float = 0.22, glow_a: float = 0.34) -> Image.Image:
    """
    深色底 + **只在中心一小圈**的暖光。

    v1 的径向光半径开到 0.62、强度 0.55，结果整个画面糊成一片棕 ——
    玻璃感全没了。这次压到刚好托住 V 就停。
    """
    bg = Image.new("RGBA", (SIZE, SIZE), (8, 9, 14, 255))
    # 极轻的竖向渐变，别用纯黑（纯黑在深色桌面上会"陷进去"）
    grad = Image.new("RGB", (1, SIZE))
    gp = grad.load()
    for y in range(SIZE):
        gp[0, y] = mix((22, 24, 34), (7, 8, 12), y / (SIZE - 1))
    bg.alpha_composite(grad.resize((SIZE, SIZE), Image.BILINEAR).convert("RGBA"))

    # 小而柔的暖光
    r = int(SIZE * glow_r)
    glow = Image.new("RGBA", (r * 2, r * 2), (0, 0, 0, 0))
    gp2 = glow.load()
    for y in range(r * 2):
        for x in range(r * 2):
            d = math.hypot(x - r, y - r) / r
            if d >= 1:
                continue
            a = int(255 * glow_a * (1 - d) ** 2.6)
            gp2[x, y] = (255, 130, 70, a)
    glow = glow.filter(ImageFilter.GaussianBlur(r * 0.10))
    bg.alpha_composite(glow, (SIZE // 2 - r, int(SIZE * 0.42) - r))
    return bg


def sheen(size: int) -> Image.Image:
    """斜向高光带 —— 让画面是"玻璃做的"而不是色块"""
    s = size * 2
    layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(layer).polygon(
        [(-s * 0.1, s * 0.06), (s, -s * 0.28), (s, -s * 0.10), (-s * 0.1, s * 0.22)],
        fill=(255, 255, 255, 9))
    layer = layer.filter(ImageFilter.GaussianBlur(s * 0.05))
    return layer.resize((size, size), Image.LANCZOS)


def rr_mask(size, radius) -> Image.Image:
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1],
                                        radius=radius, fill=255)
    return m


# ----------------------------------------------------------------------------
#  购物袋剪影（徽章用）
# ----------------------------------------------------------------------------

def bag_glyph(w: int, h: int, color) -> Image.Image:
    """
    购物袋剪影：宽而扁的袋身 + 大提手。

    第一版画出来像个**挂锁** —— 袋身太方、提手太短，两者挤在一起。
    购物袋的辨识特征是「**袋身明显比提手宽**」，所以：
      · 袋身横向占满 0.86，纵向只占 0.44（扁）
      · 提手半径给到 0.21w，起点抬到袋身之上留出空隙
    """
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    lw = max(3, int(w * 0.095))

    body_top = int(h * 0.46)

    # 提手：半圆，两端正好落在袋身顶边上
    hr = int(w * 0.21)
    hcx = w // 2
    d.arc([hcx - hr, body_top - hr, hcx + hr, body_top + hr],
          start=185, end=355, fill=color, width=lw)

    # 袋身：宽扁
    d.rounded_rectangle([int(w * 0.07), body_top, int(w * 0.93), int(h * 0.94)],
                        radius=int(w * 0.10), outline=color, width=lw)
    return img


# ----------------------------------------------------------------------------
#  方案 A：V + 玻璃购物袋徽章
# ----------------------------------------------------------------------------

def build_a() -> Image.Image:
    img = backdrop()

    vw = 660
    v = v_layer(vw)
    cx, cy = SIZE // 2, int(SIZE * 0.455)

    # 外发光（**贴着 V 的边缘**，不是铺满画布）
    #
    # 第一版 alpha=120、blur=vw*0.07，光晕半径约 660px —— 整个画布被染成棕色，
    # 取色能测出左侧 #7F4028 这种泥巴色。液态玻璃的光应该贴着物体走。
    halo = Image.new("RGBA", (v.width * 2, v.height * 2), (0, 0, 0, 0))
    hm = v.getchannel("A").resize((v.width * 2, v.height * 2), Image.LANCZOS)
    halo.paste(Image.new("RGBA", hm.size, (255, 120, 60, 58)), (0, 0), hm)
    halo = halo.filter(ImageFilter.GaussianBlur(vw * 0.035))
    paste_c(img, halo, cx, cy)

    add_shadow(img, v, cx, cy, blur=vw * 0.045, dy=14, alpha=0.6)
    paste_c(img, v, cx, cy)

    # 玻璃圆章
    d0 = 300
    badge = Image.new("RGBA", (d0, d0), (0, 0, 0, 0))
    bm = Image.new("L", (d0, d0), 0)
    ImageDraw.Draw(bm).ellipse([0, 0, d0 - 1, d0 - 1], fill=255)

    # 深色玻璃底
    badge.paste(Image.new("RGBA", (d0, d0), (16, 18, 26, 238)), (0, 0), bm)
    # 上半提亮（玻璃厚度）
    lit = Image.new("RGBA", (d0, d0), (255, 255, 255, 0))
    lp = lit.load()
    for y in range(d0):
        t = max(0.0, 1 - y / (d0 * 0.75))
        a = int(26 * t)
        for x in range(d0):
            lp[x, y] = (255, 255, 255, a)
    lit.putalpha(ImageChops.multiply(lit.getchannel("A"), bm))
    badge.alpha_composite(lit)
    # 描边
    ImageDraw.Draw(badge).ellipse([3, 3, d0 - 4, d0 - 4],
                                  outline=V_MAIN + (225,), width=7)
    # 袋子剪影
    g = bag_glyph(int(d0 * 0.52), int(d0 * 0.52), V_LIGHT + (255,))
    paste_c(badge, g, d0 // 2, d0 // 2 + 4)

    bcx, bcy = int(SIZE * 0.715), int(SIZE * 0.735)
    add_shadow(img, badge, bcx, bcy, blur=26, dy=12, alpha=0.5)
    paste_c(img, badge, bcx, bcy)

    img.alpha_composite(sheen(SIZE))
    return img


# ----------------------------------------------------------------------------
#  方案 B：V 装在购物袋里
# ----------------------------------------------------------------------------

def build_b() -> Image.Image:
    img = backdrop(glow_r=0.50, glow_a=0.32)

    bw, bh = int(SIZE * 0.60), int(SIZE * 0.545)
    body = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    bm = rr_mask((bw, bh), int(bw * 0.14))
    body.paste(Image.new("RGBA", (bw, bh), (255, 255, 255, 26)), (0, 0), bm)

    # 袋身玻璃质感：顶部亮、底部透
    lit = Image.new("RGBA", (bw, bh), (255, 255, 255, 0))
    lp = lit.load()
    for y in range(bh):
        a = int(34 * max(0.0, 1 - y / (bh * 0.8)))
        for x in range(bw):
            lp[x, y] = (255, 255, 255, a)
    lit.putalpha(ImageChops.multiply(lit.getchannel("A"), bm))
    body.alpha_composite(lit)

    # 描边：一圈很淡的白
    ImageDraw.Draw(body).rounded_rectangle([2, 2, bw - 3, bh - 3],
                                           radius=int(bw * 0.14),
                                           outline=(255, 255, 255, 70), width=3)

    bx, by = (SIZE - bw) // 2, int(SIZE * 0.375)
    add_shadow(img, body.crop((bx, by, bx + bw, by + bh)), SIZE // 2, by + bh // 2,
               blur=40, dy=18, alpha=0.45)
    img.alpha_composite(body, (bx, by))

    # 提手
    handle = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    hr = int(SIZE * 0.145)
    hcx, hcy = SIZE // 2, by + 6
    ImageDraw.Draw(handle).arc([hcx - hr, hcy - hr, hcx + hr, hcy + hr],
                               start=198, end=342, fill=V_MAIN + (255,), width=26)
    handle = handle.filter(ImageFilter.GaussianBlur(1.0))
    img.alpha_composite(handle)

    # 袋面上的 V
    vw = int(SIZE * 0.40)
    v = v_layer(vw)
    add_shadow(img, v, SIZE // 2, by + bh // 2 + 6, blur=18, dy=8, alpha=0.45)
    paste_c(img, v, SIZE // 2, by + bh // 2 + 6)

    img.alpha_composite(sheen(SIZE))
    return img


# ----------------------------------------------------------------------------
#  方案 C：V + 吊牌
# ----------------------------------------------------------------------------

def build_c() -> Image.Image:
    img = backdrop()

    vw = 680
    v = v_layer(vw)
    cx, cy = SIZE // 2, int(SIZE * 0.44)
    add_shadow(img, v, cx, cy, blur=vw * 0.045, dy=14, alpha=0.6)
    paste_c(img, v, cx, cy)

    # 吊牌：竖着的圆角矩形，上方一个小孔
    tw, th = 250, 330
    tag = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    tm = rr_mask((tw, th), 34)
    tag.paste(Image.new("RGBA", (tw, th), (16, 18, 26, 240)), (0, 0), tm)
    d = ImageDraw.Draw(tag)
    d.rounded_rectangle([3, 3, tw - 4, th - 4], radius=32,
                        outline=V_MAIN + (215,), width=6)
    # 孔
    hx, hy = tw // 2, 52
    d.ellipse([hx - 17, hy - 17, hx + 17, hy + 17], outline=V_LIGHT + (255,), width=6)

    # 三根横线（"条形码"的感觉，暗示商品/价格）
    for i, wfrac in enumerate((0.52, 0.66, 0.42)):
        y = 130 + i * 46
        x0 = int(tw * (1 - wfrac) / 2)
        d.rounded_rectangle([x0, y, tw - x0, y + 16], radius=8,
                            fill=V_LIGHT + (235,))

    tag = tag.rotate(-13, resample=Image.BICUBIC, expand=True)
    tx, ty = int(SIZE * 0.725), int(SIZE * 0.72)
    add_shadow(img, tag, tx, ty, blur=26, dy=14, alpha=0.55)
    paste_c(img, tag, tx, ty)

    img.alpha_composite(sheen(SIZE))
    return img


# ----------------------------------------------------------------------------

def save(img: Image.Image, name: str) -> None:
    flat = Image.new("RGB", img.size, (8, 9, 14))
    flat.paste(img, (0, 0), img)
    flat.save(OUT / f"{name}.png", "PNG")

    prev = flat.convert("RGBA")
    prev.putalpha(rr_mask((SIZE, SIZE), int(SIZE * 0.2237)))
    prev.save(OUT / f"{name}-rounded.png", "PNG")

    small = flat.resize((120, 120), Image.LANCZOS)
    sm = small.convert("RGBA")
    sm.putalpha(rr_mask((120, 120), 27))
    sm.save(OUT / f"{name}-120.png", "PNG")
    print(f"  ✅ {name}")


def main() -> int:
    for fn, name in ((build_a, "icon-a-badge"),
                     (build_b, "icon-b-bag"),
                     (build_c, "icon-c-tag")):
        save(fn(), name)
    print(f"\n输出: {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
