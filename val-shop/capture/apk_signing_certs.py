#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从 APK Signing Block 里挖 v2 / v3 签名的证书指纹。

为什么要这个：`META-INF/CERT.RSA` 是 **v1（JAR）签名**的证书。
现代 APK 会同时带 v2 / v3 签名，而那两个的证书在 **APK Signing Block** 里
（文件末尾的 zip 中央目录之前）。微信开放平台校验 Android 调用方用的
「应用签名」取的可能是 v2/v3 那份，拿 v1 的去比就会 mismatch。

APK Signing Block 结构（官方文档）：
    size of block (8 bytes, 不含这 8 字节)
    sequence of ID-value pairs:
        uint64 length
        uint32 ID
        value (length - 4 bytes)
    size of block (8 bytes, 和开头一样)
    magic "APK Sig Block 42" (16 bytes)

v2 签名 ID = 0x7109871a, v3 = 0xf05368c0
证书是 DER 编码的 X.509，直接算 MD5 / SHA1 即可。
"""
from __future__ import annotations

import hashlib
import pathlib
import re
import struct
import sys

APK = pathlib.Path(__file__).resolve().parents[2] / "com.tencent.apps.valorant.apk"

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def find_signing_block(data: bytes):
    """
    布局（官方文档）：

        uint64  size_of_block      <- S，不含这 8 字节
        ...ID-value pairs...       <- 长度 S-24
        uint64  size_of_block      <- 也是 S
        "APK Sig Block 42"         <- 16 字节 magic
        [ZIP 中央目录从这里开始]

    所以 S = size2，块起点 = magic_start - S + 8（推导：magic 在块内偏移 8+S-16 处）。
    """
    magic = b"APK Sig Block 42"
    idx = data.rfind(magic)
    if idx < 0:
        return None, None
    if idx < 8 + 24:
        return None, None
    (size2,) = struct.unpack_from("<Q", data, idx - 8)
    if size2 <= 0 or size2 > len(data):
        return None, None
    block_start = idx - size2 + 8
    if block_start < 0:
        return None, None
    (size1,) = struct.unpack_from("<Q", data, block_start)
    if size1 != size2:
        print(f"  ⚠️ 两端的 size 不一致：{size1} vs {size2}（可能不是标准布局）")
    return block_start, idx + len(magic)


def parse_pairs(data: bytes, start: int, end: int):
    """id -> raw value"""
    out = {}
    p = start + 8
    while p < end - 24:
        (length,) = struct.unpack_from("<Q", data, p)
        if length < 4 or p + 8 + length > end:
            break
        (ident,) = struct.unpack_from("<I", data, p + 8)
        value = data[p + 12: p + 8 + length]
        out[ident] = value
        p += 8 + length
    return out


def certs_in_len_prefixed(value: bytes):
    """
    v2/v3 的 value 里是嵌套的 length-prefixed 结构，证书是其中的 DER 序列。
    这里不严格按 schema 走，直接扫 X.509 的 SEQUENCE 头（0x30 0x82 xx xx），
    再用「能被 hashlib 算出且长度自洽」来筛 —— 够用了。
    """
    found = []
    i = 0
    n = len(value)
    while i < n - 4:
        if value[i] == 0x30 and value[i + 1] == 0x82:
            ln = struct.unpack_from(">H", value, i + 2)[0] + 4
            if 400 < ln < 4000 and i + ln <= n:
                cand = value[i:i + ln]
                if cand[-1] == 0x00 or True:
                    found.append(cand)
                    i += ln
                    continue
        i += 1
    # 去重
    uniq = []
    for c in found:
        if c not in uniq:
            uniq.append(c)
    return uniq


def main():
    if not APK.exists():
        print(f"找不到 {APK}")
        return 1
    data = APK.read_bytes()
    print(f"APK: {APK.name}  {len(data)/1024/1024:.0f} MB")

    start, end = find_signing_block(data)
    if start is None:
        print("没有 APK Signing Block（只有 v1 签名）")
        return 1
    print(f"Signing Block: {start} .. {end}  ({end-start} 字节)")
    print()

    pairs = parse_pairs(data, start, end)
    names = {0x7109871a: "v2", 0xf05368c0: "v3", 0x42726577: "verity padding",
             0x1b93ad61: "v3.1", 0x2b09189e: "v4?"}
    for ident, value in pairs.items():
        print(f"  ID 0x{ident:08x}  {names.get(ident, '?'):16s} {len(value)} 字节")

    print()
    for ident, label in ((0x7109871a, "v2"), (0xf05368c0, "v3"), (0x1b93ad61, "v3.1")):
        if ident not in pairs:
            continue
        print(f"=== {label} 里的证书 ===")
        for c in certs_in_len_prefixed(pairs[ident]):
            print(f"  长度 {len(c)}")
            print(f"    MD5(lower) = {hashlib.md5(c).hexdigest()}")
            print(f"    MD5(upper) = {hashlib.md5(c).hexdigest().upper()}")
            print(f"    SHA1       = {hashlib.sha1(c).hexdigest()}")
            print(f"    SHA256     = {hashlib.sha256(c).hexdigest()}")
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
