#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 Xcode 的 CgBI PNG（actool --compress-pngs 产物）解回普通 PNG。

用法：python work/cgbi_decode.py <输入.png> <输出.png>

CgBI 是 Apple 的私有变体：IHDR 前多一个 CgBI chunk，像素是 **预乘 BGRA**、
字节序反了。图标是不透明的（alpha=255），所以预乘这一层可以不管，只需要
丢掉 CgBI、把 BGRA 换回 RGBA、按 PNG 规则反过滤再重新压一遍。
"""
from __future__ import annotations

import struct
import sys
import zlib

from PIL import Image


def chunks(data: bytes):
    pos = 8
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        yield tag, body
        pos += 12 + length


def paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def main() -> int:
    src, dst = sys.argv[1], sys.argv[2]
    raw = open(src, "rb").read()

    width = height = None
    idat = bytearray()
    for tag, body in chunks(raw):
        if tag == b"IHDR":
            width, height, depth, ctype = struct.unpack(">IIBB", body[:10])
            if (depth, ctype) != (8, 6):
                print(f"只处理 8bit RGBA，实际 depth={depth} ctype={ctype}")
                return 2
        elif tag == b"IDAT":
            idat += body

    # actool 的 CgBI 用 raw deflate（没有 zlib 头），普通 PNG 才带头
    try:
        data = zlib.decompress(bytes(idat))
    except zlib.error:
        data = zlib.decompressobj(-15).decompress(bytes(idat))
    stride = width * 4
    out = bytearray(stride * height)
    prev = bytearray(stride)

    for y in range(height):
        ft = data[y * (stride + 1)]
        line = bytearray(data[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for x in range(stride):
            a = line[x - 4] if x >= 4 else 0
            b = prev[x]
            c = prev[x - 4] if x >= 4 else 0
            if ft == 1:
                line[x] = (line[x] + a) & 0xFF
            elif ft == 2:
                line[x] = (line[x] + b) & 0xFF
            elif ft == 3:
                line[x] = (line[x] + (a + b) // 2) & 0xFF
            elif ft == 4:
                line[x] = (line[x] + paeth(a, b, c)) & 0xFF
        # BGRA → RGBA
        for x in range(0, stride, 4):
            line[x], line[x + 2] = line[x + 2], line[x]
        out[y * stride:(y + 1) * stride] = line
        prev = line

    img = Image.frombytes("RGBA", (width, height), bytes(out)).convert("RGB")
    img.save(dst, "PNG")
    print(f"{src} -> {dst}  {width}x{height}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
