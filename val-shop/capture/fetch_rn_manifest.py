#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""试出 /go/app_update/rn_package 的正确 version 参数，拿全量 RN bundle 清单。"""
from __future__ import annotations

import json
import pathlib
import re
import sys
import urllib.request

HOST = "https://app.mval.qq.com"
SESSION_FILE = pathlib.Path(__file__).with_name("_dump") / "mval_session.json"
OUT = pathlib.Path(__file__).with_name("_dump") / "rn_manifest.json"

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


def post(path: str, cookie: str, body: dict | None):
    headers = {
        "Cookie": cookie,
        "User-Agent": "okhttp/4.9.2",
        "Content-Type": "application/json; charset=utf-8",
    }
    data = json.dumps(body or {}).encode()
    req = urllib.request.Request(f"{HOST}{path}", data=data, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode("utf-8", errors="replace"))


def main():
    sessions = json.loads(SESSION_FILE.read_text(encoding="utf-8"))
    s = sessions[-1] if isinstance(sessions, list) else sessions
    cookie = build_cookie(s)

    trials = [
        ("2.10.1",  "val",   "/go/app_update/rn_package?plat=android&version=2.10.1&source_game_zone=val&game_zone=val"),
        ("10076",   "val",   "/go/app_update/rn_package?plat=android&version=10076&source_game_zone=val&game_zone=val"),
        ("2.10.1",  "agame", "/go/app_update/rn_package?plat=android&version=2.10.1&source_game_zone=agame&game_zone=agame"),
        ("10076",   "agame", "/go/app_update/rn_package?plat=android&version=10076&source_game_zone=agame&game_zone=agame"),
        ("10076.10076", "val", "/go/app_update/rn_package?plat=android&version=10076.10076&source_game_zone=val&game_zone=val"),
    ]

    best = None
    for ver, zone, path in trials:
        try:
            r = post(path, cookie, {"game_zone": zone, "source_game_zone": zone})
        except Exception as e:
            print(f"  version={ver:14s} zone={zone:6s} -> 异常 {e}")
            continue
        n = len((r.get("data") or {}).get("Bussiness", []) or [])
        print(f"  version={ver:14s} zone={zone:6s} -> result={r.get('result')} "
              f"msg={r.get('msg')!r} bundles={n}")
        if r.get("result") == 0 and n > 0:
            best = (ver, zone, r)
            break

    if not best:
        print("\n都没成功。")
        return 1

    ver, zone, r = best
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(r, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n✅ 用 version={ver} zone={zone} 拿到了全量清单 -> {OUT}")

    bundles = r["data"].get("Bussiness", [])
    print(f"\n共 {len(bundles)} 个 bundle")
    print("=" * 78)

    shopish = re.compile(r"shop|store|mall|commodity|goods|offer|purchase|pay|order|skin|good", re.I)
    print("\n【名字里带 shop/store/order/skin/pay 的】")
    for b in bundles:
        n = b.get("bussinessName", "")
        if shopish.search(n):
            sz = b.get("bundle_size") or "?"
            print(f"  {n:44s} {sz:>10s}")
            print(f"      {b.get('bussinessURL')}")

    print("\n【全部】")
    for b in sorted(bundles, key=lambda x: x.get("bussinessName", "")):
        print(f"  {b.get('bussinessName','')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
