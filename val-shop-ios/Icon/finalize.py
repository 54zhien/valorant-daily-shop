#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
图标收尾：压平 → 装库 → 出对照表

    python val-shop-ios/Icon/finalize.py

 1. 把 Icon/out/png/ 里 Chrome 截的图压成 RGB（App Store 不收带 alpha 的图标）
 2. 主方案的 flat-<theme> 装进 App/Assets.xcassets/AppIcon.appiconset/
    —— 这是**兜底**：不画玻璃、不画投影，只底色 + 层轮廓；真玻璃由系统的 .icon 渲染
 3. 出两张表：
    preview/concepts.png      三个候选方案并排（挑样式用）
    preview/contact-sheet.png 主方案三外观 × 四尺寸 + 浅色壁纸（验收用）

前置：node Icon/gen.mjs && node Icon/render.mjs
"""
from __future__ import annotations

import hashlib
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = pathlib.Path(__file__).resolve().parent
PNG = HERE / "out" / "png"
PREVIEW = HERE / "preview"
ASSETS = HERE.parent / "App" / "Assets.xcassets" / "AppIcon.appiconset"

THEMES = [
    ("light", "浅色", "AppIcon-1024.png"),
    ("dark", "深色", "AppIcon-1024-dark.png"),
    ("tinted", "着色", "AppIcon-1024-tinted.png"),
]
CONCEPT_LABELS = {
    "a": "A 斜卡 + V",
    "b": "B 取景环 + V",
    "c": "C 单 V",
}

FONTS = [
    "C:/Windows/Fonts/msyh.ttc",
    "C:/Windows/Fonts/msyhl.ttc",
    "/System/Library/Fonts/PingFang.ttc",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
]

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def font(size: int) -> ImageFont.ImageFont:
    for f in FONTS:
        if pathlib.Path(f).exists():
            try:
                return ImageFont.truetype(f, size)
            except OSError:
                pass
    return ImageFont.load_default()


def flatten(src: pathlib.Path, dst: pathlib.Path | None = None) -> Image.Image:
    im = Image.open(src)
    if im.mode != "RGB":
        im = im.convert("RGBA")
        bg = Image.new("RGB", im.size, (0, 0, 0))
        bg.paste(im, mask=im.getchannel("A"))
        im = bg
    if dst is not None:
        dst.parent.mkdir(parents=True, exist_ok=True)
        im.save(dst, "PNG")
    return im


def squircle(im: Image.Image, size: int) -> Image.Image:
    """按 iOS 图标圆角比例（半径 ≈ 22.37% 边长）裁一张预览用的圆角图。"""
    out = im.convert("RGBA").resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=int(round(size * 0.2237)), fill=255
    )
    out.putalpha(mask)
    return out


def sha(p: pathlib.Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()[:16]


def concepts_sheet() -> pathlib.Path:
    """三个方案并排：大图 + 60pt 实尺寸。"""
    big, pad = 320, 40
    col_w = big + pad
    ids = [i for i in CONCEPT_LABELS if (PNG / f"concept-{i}.png").exists()]
    W = pad + col_w * len(ids) + pad
    H = pad + 34 + big + 34 + 96 + 34 + pad

    sheet = Image.new("RGBA", (W, H), (24, 26, 32, 255))
    d = ImageDraw.Draw(sheet)
    f_title, f_mid, f_small = font(28), font(22), font(18)

    d.text((pad, pad - 6), "候选方案（模拟系统玻璃，最终由 iOS 渲染）", font=f_title, fill=(236, 238, 242, 255))
    y = pad + 40
    for i in ids:
        x = pad + col_w * ids.index(i)
        d.text((x, y), CONCEPT_LABELS[i], font=f_mid, fill=(226, 229, 235, 255))
        im = flatten(PNG / f"concept-{i}.png")
        sheet.alpha_composite(squircle(im, big), (x, y + 34))
        d.text((x, y + 34 + big + 12), "60pt 实尺寸", font=f_small, fill=(120, 126, 138, 255))
        sheet.alpha_composite(squircle(im, 96), (x, y + 34 + big + 34))

    out = PREVIEW / "concepts.png"
    sheet.convert("RGB").save(out, "PNG")
    return out


def main() -> int:
    missing = [str(p) for p in [PNG / f"flat-{t}.png" for t, _, _ in THEMES] if not p.exists()]
    if missing:
        print("缺源图，先跑 node Icon/gen.mjs && node Icon/render.mjs：")
        for m in missing:
            print("  " + m)
        return 1

    print("① 压平成 RGB + 装进 xcassets（兜底稿：不画玻璃）")
    for theme, _, name in THEMES:
        src = PNG / f"flat-{theme}.png"
        im = flatten(src, src)
        assert im.size == (1024, 1024), f"{src.name} 不是 1024×1024：{im.size}"
        dst = ASSETS / name
        im.save(dst, "PNG")
        print(f"  {name:24} {im.mode} {im.size[0]}×{im.size[1]}  sha256:{sha(dst)}")

    print("② 圆角预览稿 → Icon/preview/")
    PREVIEW.mkdir(parents=True, exist_ok=True)
    for theme, _, _ in THEMES:
        dst = PREVIEW / f"appicon-preview-{theme}.png"
        flatten(PNG / f"preview-{theme}.png", dst)
        print(f"  {dst.name:32} sha256:{sha(dst)}")

    print("③ 对照表")
    out = concepts_sheet()
    print(f"  {out.relative_to(HERE.parent.parent)}  sha256:{sha(out)}")

    big, smalls, pad = 300, (96, 64, 40, 29), 40
    col_w = big + pad
    W = pad + col_w * len(THEMES) + pad

    y_title = pad
    y_sub = y_title + 40
    y_row1_label = y_sub + 34
    y_row1 = y_row1_label + 30
    y_row2_label = y_row1 + big + 34
    y_row2 = y_row2_label + 30
    y_row3 = y_row2 + 96 + 34
    panel_h = 160
    H = y_row3 + panel_h + pad

    sheet = Image.new("RGBA", (W, H), (24, 26, 32, 255))
    d = ImageDraw.Draw(sheet)
    f_title, f_mid, f_small = font(30), font(22), font(18)

    d.text((pad, y_title), "ValPeek · 图标终稿", font=f_title, fill=(236, 238, 242, 255))
    d.text((pad, y_sub), "分层素材 + icon.json，玻璃/底色/投影由系统渲染；下面是对系统的模拟",
           font=f_small, fill=(140, 146, 158, 255))

    x = pad
    for theme, label, _ in THEMES:
        im = flatten(PNG / f"preview-{theme}.png")
        d.text((x, y_row1_label), label, font=f_mid, fill=(226, 229, 235, 255))
        sheet.alpha_composite(squircle(im, big), (x, y_row1))
        x += col_w

    d.text((pad, y_row2_label), "桌面尺寸（iOS 自己蒙圆角，这里先看小尺寸认不认得出）",
           font=f_small, fill=(140, 146, 158, 255))
    x = pad
    for theme, _, _ in THEMES:
        im = flatten(PNG / f"preview-{theme}.png")
        cx = x
        for s in smalls:
            sheet.alpha_composite(squircle(im, s), (cx, y_row2 + (96 - s)))
            d.text((cx, y_row2 + 100), f"{s}px", font=f_small, fill=(120, 126, 138, 255))
            cx += s + 18
        x += col_w

    d.rounded_rectangle([pad - 10, y_row3, W - pad + 10, y_row3 + panel_h - 10], radius=16,
                        fill=(242, 243, 246, 255))
    d.text((pad, y_row3 + 8), "浅色壁纸 96px", font=f_small, fill=(110, 114, 122, 255))
    x = pad
    for theme, _, _ in THEMES:
        im = flatten(PNG / f"preview-{theme}.png")
        sheet.alpha_composite(squircle(im, 96), (x, y_row3 + 34))
        x += col_w

    out = PREVIEW / "contact-sheet.png"
    sheet.convert("RGB").save(out, "PNG")
    print(f"  {out.relative_to(HERE.parent.parent)}  {sheet.width}×{sheet.height}  sha256:{sha(out)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
