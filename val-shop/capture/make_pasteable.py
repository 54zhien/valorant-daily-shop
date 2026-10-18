#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把抓到的 session 拼成可以直接粘贴的文本。

为什么要这个：iOS 上把文件弄进 App 有几个前提（UIFileSharingEnabled、
App 至少启动过一次、Files 缓存……），任何一环不对就传不进去。
而「直接粘贴」这条路没有任何依赖 —— 复制文本，粘进 App 就行。

输出三种格式：
  1) mval_session.json 的完整内容（粘贴后 App 会自动识别，含 ct，可自刷新）
  2) 纯 Cookie 头（老版本 App 的「直接粘贴 Cookie」用）
  3) 一段简短的一行式（方便微信/AirDrop 传）

用法：
    python val-shop/capture/make_pasteable.py
"""
from __future__ import annotations

import json
import pathlib
import sys

HERE = pathlib.Path(__file__).parent
SESSION_FILE = HERE / "_dump" / "mval_session.json"

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


def main():
    if not SESSION_FILE.exists():
        print(f"找不到 {SESSION_FILE}")
        return 1

    raw = json.loads(SESSION_FILE.read_text(encoding="utf-8"))
    s = raw[-1] if isinstance(raw, list) else raw
    s = {k: v for k, v in s.items() if k not in ("kind", "t")}

    compact = json.dumps(s, ensure_ascii=False, separators=(",", ":"))
    cookie = build_cookie(s)

    out = HERE / "_dump" / "pasteable.txt"
    out.write_text(
        "=== 1) 完整 session（推荐，含 ct，可自刷新）===\n"
        + compact
        + "\n\n=== 2) 纯 Cookie ===\n"
        + cookie
        + "\n",
        encoding="utf-8")

    print("=" * 78)
    print("  ① 完整 session JSON —— 推荐（含 ct，能自动续票）")
    print("=" * 78)
    print(compact)
    print()
    print("=" * 78)
    print("  ② 纯 Cookie —— 老版本 App 的「直接粘贴 Cookie」用")
    print("     （没有 ct，tid 过期就得重来）")
    print("=" * 78)
    print(cookie)
    print()
    print(f"已存 -> {out}  ({out.stat().st_size} 字节)")
    print(f"长度：session {len(compact)} 字符 / cookie {len(cookie)} 字符")
    return 0


if __name__ == "__main__":
    sys.exit(main())
