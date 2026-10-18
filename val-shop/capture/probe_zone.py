#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
直接调 /go/zone/v3/channel 拿商店页结构 —— 不需要在模拟器里打开那个会崩的 RN 页面。

依据：抓包里 /go/zone/v3/channel?zone=plat 返回的是**完整的页面结构 JSON**
（每个 tab 的 url、data、subChannel 都在里面）。那 zone=shop 同理。

用法：
    python val-shop/capture/probe_zone.py
"""
from __future__ import annotations

import json
import pathlib
import re
import sys
import urllib.parse
import urllib.request

HOST = "https://app.mval.qq.com"
SESSION_FILE = pathlib.Path(__file__).with_name("_dump") / "mval_session.json"
OUT = pathlib.Path(__file__).with_name("_dump") / "zone_probe.json"

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def build_cookie(s: dict) -> str:
    parts = ["clientType=9"]
    uin = s.get("uin")
    if s.get("auth_type") in (4, 0) and uin:
        parts += [f"uin=o{uin}", "appid=102061775", "acctype=qc"]
    else:
        parts += ["appid=wxcbb49f1f39656c2a", "acctype=wx"]
    for k, v in (("openid", s.get("openid")),
                 ("access_token", s.get("access_token")),
                 ("userId", s.get("user_id")),
                 ("accountType", 5 if s.get("auth_type") in (4, 0) else 2),
                 ("tid", s.get("tid"))):
        if v not in (None, ""):
            parts.append(f"{k}={v}")
    return "; ".join(parts) + ";"


def get(path: str, cookie: str):
    headers = {"Cookie": cookie, "User-Agent": "okhttp/4.9.2", "Accept": "application/json"}
    req = urllib.request.Request(f"{HOST}{path}", headers=headers, method="GET")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode("utf-8", errors="replace"))


def main():
    sessions = json.loads(SESSION_FILE.read_text(encoding="utf-8"))
    s = sessions[-1] if isinstance(sessions, list) else sessions
    cookie = build_cookie(s)

    zones = ["shop", "val", "game_zone", "mall", "store"]
    results = {}

    for zone in zones:
        path = (f"/go/zone/v3/channel?zone={zone}&disableAlgo=0"
                f"&source_game_zone=val&game_zone=val")
        try:
            r = get(path, cookie)
        except Exception as e:
            print(f"  zone={zone:10s} -> 异常 {e}")
            continue
        data = r.get("data")
        n = len(data) if isinstance(data, list) else "?"
        print(f"  zone={zone:10s} -> result={r.get('result')} msg={r.get('msg')!r} tabs={n}")
        if r.get("result") == 0:
            results[zone] = r

    if not results:
        print("\n都没成功")
        return 1

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n已存 -> {OUT}")

    # 把里面所有 URL 挖出来
    print()
    print("=" * 78)
    print("  页面结构里嵌的 URL")
    print("=" * 78)
    blob = json.dumps(results, ensure_ascii=False)
    urls = set()
    for m in re.finditer(r"https?://[^\s\"'\\]+", blob):
        urls.add(urllib.parse.unquote(m.group(0)))
    # 也挖 valpage:// 路由
    routes = set(re.findall(r"valpage://[a-zA-Z0-9_/?=&%.\-]+", blob))

    interesting = [u for u in urls if re.search(r"shop|store|mall|goods|commodity|offer|order", u, re.I)]
    print(f"\n  含 shop/store/mall 的 URL ({len(interesting)}):")
    for u in sorted(interesting):
        print(f"    {u[:200]}")

    print(f"\n  全部 valpage 路由 ({len(routes)}):")
    for r in sorted(routes):
        print(f"    {r[:200]}")

    print(f"\n  全部 /go/ 路径:")
    gos = set()
    for u in urls:
        m = re.search(r"(/go/[a-z0-9_/]+)", u)
        if m:
            gos.add(m.group(1))
    for g in sorted(gos):
        print(f"    {g}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
