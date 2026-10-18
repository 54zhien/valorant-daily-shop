#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从 RN bundle 里挖出 /go/mlol_store/agame/daily_store 的调用上下文，然后真调一次。

bundle 是 Hermes 字节码，字符串表是连续的，所以直接看字符邻居就能还原出
接口名、参数名、字段名。
"""
from __future__ import annotations

import json
import pathlib
import re
import sys
import urllib.request

HERE = pathlib.Path(__file__).parent
D = HERE / "_dump"
SESSION_FILE = D / "mval_session.json"
HOST = "https://app.mval.qq.com"

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PATHS = [
    "/go/mlol_store/agame/daily_store",
    "/go/mlol_store/agame/flip_goods_card",
    "/go/mlol_store/agame/user_store",
    "/go/mlol_store/agame/kingdom_store",
    "/go/mlol_store/agame/get_vct_skin_list",
]


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


def call(path: str, cookie: str, body: dict):
    headers = {"Cookie": cookie, "User-Agent": "okhttp/4.9.2",
               "Content-Type": "application/json; charset=utf-8"}
    req = urllib.request.Request(f"{HOST}{path}", data=json.dumps(body).encode(),
                                 headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode("utf-8", errors="replace"))


def show_context():
    f = D / "rn" / "WelFareStrategyMain.jsbundle"
    if not f.exists():
        print("bundle 不在，跳过上下文")
        return
    text = f.read_text(encoding="utf-8", errors="replace")
    print("=" * 78)
    print("  字符串表里 daily_store 周围的邻居")
    print("=" * 78)
    for m in re.finditer(r"/go/mlol_store/agame/daily_store", text):
        seg = text[max(0, m.start() - 700):m.start() + 700]
        seg = re.sub(r"[^\x20-\x7e\u4e00-\u9fff]", " ", seg)
        seg = re.sub(r"\s+", " ", seg)
        print(f"\n  …{seg}…")
        break


def main():
    show_context()

    sessions = json.loads(SESSION_FILE.read_text(encoding="utf-8"))
    s = sessions[-1] if isinstance(sessions, list) else sessions
    cookie = build_cookie(s)

    print()
    print("=" * 78)
    print("  直接调这几个接口")
    print("=" * 78)

    bodies = [
        {},
        {"game_zone": "val", "source_game_zone": "val"},
        {"game_zone": "val", "source_game_zone": "val", "zone": "val"},
    ]

    hits = {}
    for p in PATHS:
        for body in bodies:
            q = f"{p}?source_game_zone=val&game_zone=val"
            try:
                r = call(q, cookie, body)
            except Exception as e:
                print(f"  {p:44s} body={body!r:52s} -> 异常 {e}")
                continue
            res = r.get("result")
            data = r.get("data")
            n = ""
            if isinstance(data, dict):
                n = f"keys={list(data.keys())[:8]}"
            elif isinstance(data, list):
                n = f"list[{len(data)}]"
            print(f"  {p:44s} body={len(body)}键 -> result={res} msg={r.get('msg')!r} {n}")
            if res == 0 and data not in (None, {}, []):
                hits[p] = (body, r)
                break

    if hits:
        out = D / "daily_store.json"
        out.write_text(json.dumps(hits, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"\n✅ 命中的接口 -> {out}")
        for p, (body, r) in hits.items():
            print()
            print(f"  ### {p}   body={json.dumps(body, ensure_ascii=False)}")
            print("  " + json.dumps(r, ensure_ascii=False)[:2000])
    else:
        print("\n都没返回有效数据（可能参数不对）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
