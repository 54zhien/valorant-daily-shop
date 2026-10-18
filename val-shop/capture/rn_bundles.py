#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从抓包日志里取出 RN bundle 清单，找出「商店」那个，下载并 grep 出 /go/ 接口。

思路：每日商店是服务端下发的 React Native 页面，x86_64 模拟器上打开会原生崩溃，
但**它的 JS bundle 是明文放在 CDN 上的**，直接从 /go/app_update/rn_package
的响应里拿到地址下载即可，完全不需要运行那个页面。

用法：
    python val-shop/capture/rn_bundles.py list        # 列清单
    python val-shop/capture/rn_bundles.py fetch mall  # 下载名字含 mall/shop/store 的
    python val-shop/capture/rn_bundles.py grep mall   # 在里面搜 /go/ 路径
"""
from __future__ import annotations

import io
import json
import pathlib
import re
import sys
import urllib.request
import zipfile

LOG = pathlib.Path("val-shop/capture/_dump/mval_capture.log")
OUT = pathlib.Path("val-shop/capture/_dump/rn")

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SHOP_WORDS = re.compile(r"shop|store|mall|commodity|goods|offer|bundle|purchase|pay", re.I)


def load_manifest() -> dict | None:
    """从抓包日志里抠出 rn_package 的响应。

    响应体很大（清单里有几百个 bundle），会被 frida 脚本的 MAX_BODY 截断，
    所以这里**不解析整段 JSON**，而是用正则直接抠 (url, name, size) 三元组。
    """
    if not LOG.exists():
        print(f"找不到 {LOG}")
        return None
    for ln in LOG.read_text(encoding="utf-8", errors="replace").splitlines():
        if "/go/app_update/rn_package" not in ln or '"dir":"RESP"' not in ln:
            continue
        try:
            body = json.loads(ln)["body"]
        except Exception:
            continue

        base = re.search(r'"url"\s*:\s*"(https://[^"]+\.zip)"', body)
        bundles = []
        # 每个 bundle 是一个对象，bussinessURL 和 bussinessName 成对出现
        for m in re.finditer(
                r'"bussinessURL"\s*:\s*"(https://[^"]*?)"\s*,\s*"baseId".*?'
                r'"bussinessName"\s*:\s*"([^"]+)".*?'
                r'"bundle_size"\s*:\s*"([^"]*)"',
                body, re.S):
            bundles.append({"bussinessURL": m.group(1),
                            "bussinessName": m.group(2),
                            "bundle_size": m.group(3)})
        if not bundles:
            # 退一步：只要 name + url，不管顺序
            urls = re.findall(r'"bussinessURL"\s*:\s*"(https://[^"]*?\.zip)"', body)
            names = re.findall(r'"bussinessName"\s*:\s*"([^"]+)"', body)
            bundles = [{"bussinessURL": u, "bussinessName": n, "bundle_size": ""}
                       for u, n in zip(urls, names)]
        return {"baseId": "2", "url": base.group(1) if base else "", "Bussiness": bundles}
    return None


def all_bundles(data: dict):
    out = [("(base)", data.get("url", ""), None)]
    for b in data.get("Bussiness", []) or []:
        out.append((
            b.get("bussinessName", "?"),
            b.get("bussinessURL", ""),
            b.get("bundle_size"),
        ))
    return out


def cmd_list():
    data = load_manifest()
    if not data:
        print("没在日志里找到 rn_package 的响应")
        return 1
    bundles = all_bundles(data)
    print(f"base = {data.get('baseId')}  url = {data.get('url')}")
    print(f"共 {len(bundles)} 个 bundle")
    print()
    for name, url, size in sorted(bundles):
        mark = "  ★" if SHOP_WORDS.search(name or "") else ""
        sz = f"{int(size)/1024:.0f}KB" if size else ""
        print(f"  {name:42s} {sz:>8s}{mark}")
        if mark:
            print(f"      {url}")
    print()
    print("★ = 名字里带 shop/store/mall/…")
    return 0


def cmd_fetch(pattern: str):
    data = load_manifest()
    if not data:
        return 1
    rx = re.compile(pattern, re.I)
    bundles = [b for b in all_bundles(data) if rx.search(b[0] or "")]
    if not bundles:
        print(f"没有名字匹配 /{pattern}/ 的 bundle")
        return 1

    OUT.mkdir(parents=True, exist_ok=True)
    for name, url, size in bundles:
        if not url:
            continue
        print(f"[下载] {name}")
        print(f"       {url}")
        try:
            raw = urllib.request.urlopen(url, timeout=60).read()
        except Exception as e:
            print(f"       失败: {e}")
            continue
        dest_zip = OUT / f"{name}.zip"
        dest_zip.write_bytes(raw)
        print(f"       -> {dest_zip}  ({len(raw)/1024:.0f} KB)")

        # 解开，拿到 .jsbundle / .js
        try:
            with zipfile.ZipFile(io.BytesIO(raw)) as z:
                for info in z.namelist():
                    print(f"       包内: {info}  ({info and z.getinfo(info).file_size/1024:.0f} KB)")
                    if info.endswith((".jsbundle", ".js", ".bundle", ".hbc")):
                        dst = OUT / f"{name}__{pathlib.Path(info).name}"
                        dst.write_bytes(z.read(info))
                        print(f"       -> {dst}")
        except Exception as e:
            print(f"       不是 zip / 解不开: {e}")
    return 0


def cmd_grep(pattern: str):
    rx = re.compile(pattern, re.I)
    files = [p for p in OUT.glob("*") if rx.search(p.name) and
             p.suffix in (".jsbundle", ".js", ".bundle", ".json")]
    if not files:
        print(f"{OUT} 里没有匹配的 jsbundle，先跑 fetch")
        return 1

    for f in files:
        data = f.read_bytes()
        # 有些是 Hermes 字节码（魔法数 0x1F1903C1），里面是压缩字符串表，还能捞
        hermes = data[:8].startswith(bytes.fromhex("c10319075f"))
        print()
        print("=" * 74)
        print(f"  {f.name}   {len(data)/1024:.0f} KB   {'Hermes 字节码' if hermes else '明文 JS'}")
        print("=" * 74)

        text = data.decode("utf-8", errors="replace")

        found = {}
        for m in re.finditer(r"/go/[a-z0-9_]+(?:/[a-z0-9_]+)*", text, re.I):
            found[m.group(0)] = found.get(m.group(0), 0) + 1
        if found:
            print(f"\n  /go/ 路径 ({len(found)} 个):")
            for p, c in sorted(found.items()):
                print(f"    {p}   x{c}")
        else:
            print("\n  （没搜到 /go/ 路径）")

        for kw in ("shop", "store", "mall", "commodity", "每日商店", "商店", "offer"):
            hits = [m.start() for m in re.finditer(re.escape(kw), text, re.I)]
            if hits:
                print(f"\n  '{kw}' x{len(hits)}，上下文:")
                shown = 0
                for h in hits:
                    seg = text[max(0, h - 120):h + 160].replace("\n", " ")
                    print(f"    …{seg}…")
                    shown += 1
                    if shown >= 4:
                        break
    return 0


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    a = sys.argv[1]
    if a == "list":
        return cmd_list()
    if a == "fetch":
        return cmd_fetch(sys.argv[2] if len(sys.argv) > 2 else ".")
    if a == "grep":
        return cmd_grep(sys.argv[2] if len(sys.argv) > 2 else ".")
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
