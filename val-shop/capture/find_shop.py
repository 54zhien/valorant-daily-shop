#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从抓包日志里挖「每日商店」的真实接口。

用法：
    python val-shop/capture/find_shop.py val-shop/capture/_dump/mval_capture.log
"""
from __future__ import annotations

import json
import pathlib
import re
import sys
from collections import OrderedDict

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SHOP_HINT = re.compile(
    r"shop|store|mall|commodity|goods|purchase|order|pay|skin|offer|bundle|"
    r"price|vip|coin|currency|card|item",
    re.I,
)


def load(path: pathlib.Path):
    reqs, resps, sessions = [], [], []
    seen_req = set()
    for ln in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not ln.startswith("{"):
            continue
        try:
            d = json.loads(ln)
        except Exception:
            continue
        if d.get("kind") == "SESSION":
            sessions.append(d)
        elif d.get("dir") == "REQ":
            # 同一个请求会被 build() 和 BridgeInterceptor 各记一次，去重
            key = (d.get("method"), d.get("url"), (d.get("body") or "")[:200])
            if key in seen_req:
                continue
            seen_req.add(key)
            reqs.append(d)
        elif d.get("dir") == "RESP":
            resps.append(d)
    return reqs, resps, sessions


def main():
    path = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else \
        pathlib.Path("val-shop/capture/_dump/mval_capture.log")
    reqs, resps, sessions = load(path)

    print(f"请求 {len(reqs)} / 响应 {len(resps)} / 会话 {len(sessions)}")
    print()

    # 按 path 归组
    by_path = OrderedDict()
    for r in reqs:
        url = r.get("url", "")
        p = url.split("?")[0].replace("https://app.mval.qq.com", "")
        by_path.setdefault(p, []).append(r)

    print("=" * 78)
    print("  全部接口（按路径去重）")
    print("=" * 78)
    for p, rs in by_path.items():
        m = rs[0].get("method", "?")
        q = rs[0].get("url", "").split("?", 1)[1] if "?" in rs[0].get("url", "") else ""
        flag = "  ★" if SHOP_HINT.search(p + q) else ""
        print(f"  {m:5s} {p}{('?' + q[:60]) if q else ''}{flag}")

    print()
    print("=" * 78)
    print("  带 shop/store/mall/zone=shop 的（重点）")
    print("=" * 78)
    hits = []
    for p, rs in by_path.items():
        blob = p + " " + " ".join(r.get("url", "") for r in rs) + " " + \
               " ".join(r.get("body") or "" for r in rs)
        if re.search(r"shop|store|mall|commodity|goods|offer", blob, re.I):
            hits.append((p, rs))
    if not hits:
        print("  （没有）")
    for p, rs in hits:
        print()
        print(f"  ### {rs[0].get('method')} {p}")
        for r in rs[:3]:
            print(f"      url  : {r.get('url')}")
            if r.get("body"):
                print(f"      body : {(r.get('body') or '')[:400]}")
        for resp in resps:
            if resp.get("url", "").split("?")[0].endswith(p):
                b = resp.get("body") or ""
                print(f"      resp({resp.get('code')}): {b[:600]}")
                break

    print()
    print("=" * 78)
    print("  /go/zone/v3/channel 的调用（商店/游戏区共用容器）")
    print("=" * 78)
    for r in reqs:
        if "/go/zone/v3/channel" in r.get("url", ""):
            print(f"  {r.get('method')} {r.get('url')}")
            if r.get("body"):
                print(f"    body: {r.get('body')[:500]}")
    for resp in resps:
        if "/go/zone/v3/channel" in resp.get("url", ""):
            b = resp.get("body") or ""
            print(f"  resp({resp.get('code')}) {resp.get('url','').split('?')[1][:60] if '?' in resp.get('url','') else ''}")
            print(f"    {b[:1500]}")

    print()
    print("=" * 78)
    print("  会话")
    print("=" * 78)
    for s in sessions:
        print(json.dumps(s, ensure_ascii=False, indent=2)[:1200])


if __name__ == "__main__":
    main()
