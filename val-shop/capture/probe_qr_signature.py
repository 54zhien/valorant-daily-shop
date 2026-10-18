#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
最后一轮：qrconnect 的 signature 到底怎么算。

已知：
  · 证书指纹（v1 == v2）试过了 → signature mismatch
  · /go/auth/get_sdk_ticket 不带登录态就能拿到 ticket

假设：signature 由 ticket 派生（掌瓦服务端下发 ticket，客户端用它签名）。

试这些组合：
  ticket 本身
  md5/sha1( appid + noncestr + timestamp + scope [+ ticket] )
  md5/sha1( 按参数名排序拼接 + ticket )
  hmac-sha1(ticket, 参数串)
"""
from __future__ import annotations

import hashlib
import hmac
import json
import pathlib
import random
import string
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

APPID = "wxcbb49f1f39656c2a"
SCOPE = "snsapi_userinfo"
HOST = "https://app.mval.qq.com"
OUT = pathlib.Path(__file__).parent / "_dump" / "qr_sig_probe.json"

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def nonce(n=16):
    return "".join(random.choices(string.ascii_letters + string.digits, k=n))


def post(path, body, cookie=None):
    h = {"User-Agent": "okhttp/4.9.2", "Content-Type": "application/json; charset=utf-8"}
    if cookie:
        h["Cookie"] = cookie
    req = urllib.request.Request(HOST + path, data=json.dumps(body).encode(),
                                 headers=h, method="POST")
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.read().decode("utf-8", errors="replace")


def get(url):
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (Linux; Android 12) Mobile Safari/537.36",
        "Referer": "https://open.weixin.qq.com/"}, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status, r.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, (e.read().decode("utf-8", errors="replace") if e.fp else "")


def main():
    raw = post("/go/auth/get_sdk_ticket", {},
               "clientType=9; openid=null; access_token=null;")
    ticket = (json.loads(raw).get("data") or {}).get("ticket", "")
    print(f"ticket = {ticket}")
    print(f"长度   = {len(ticket)}")
    print()

    nc = nonce()
    ts = str(int(time.time()))
    base_pairs = [("appid", APPID), ("noncestr", nc), ("timestamp", ts), ("scope", SCOPE)]

    def concat(pairs, sep=""):
        return sep.join(f"{k}={v}" for k, v in pairs)

    def sorted_concat(pairs):
        return "&".join(f"{k}={v}" for k, v in sorted(pairs))

    candidates = {}
    candidates["ticket_literal"] = ticket
    for name, s in (
        ("concat", concat(base_pairs)),
        ("concat_sorted", sorted_concat(base_pairs)),
        ("concat_nosep", concat(base_pairs, "")),
    ):
        for algo in ("md5", "sha1", "sha256"):
            for keyname, key in (("ticket", ticket), ("appid", APPID), ("empty", "")):
                h = getattr(hashlib, algo)((s + key).encode()).hexdigest()
                candidates[f"{algo}({name}+{keyname})"] = h
                candidates[f"{algo}({name}+{keyname})_UP"] = h.upper()
                hm = hmac.new(key.encode(), s.encode(), getattr(hashlib, algo)).hexdigest()
                candidates[f"hmac-{algo}({keyname},{name})"] = hm
        # 参数名排序 + key（微信网站应用的标准算法）
        h = hashlib.sha1((sorted_concat(base_pairs) + ticket).encode()).hexdigest()
        candidates[f"sha1(sorted+ticket)"] = h

    print(f"共 {len(candidates)} 个候选")
    print()

    hits = []
    for i, (name, sig) in enumerate(candidates.items(), 1):
        params = dict(base_pairs) | {"signature": sig}
        url = "https://open.weixin.qq.com/connect/sdk/qrconnect?" + urllib.parse.urlencode(params)
        code, body = get(url)
        if '"errcode":-11' not in body and "signature mismatch" not in body:
            print(f"  ★★★ {name}  ->  {body[:300]}")
            hits.append({"name": name, "sig": sig, "body": body[:500]})
        elif i % 20 == 0:
            print(f"  … 试了 {i} 个，还是 mismatch")

    print()
    if hits:
        print(f"🎯 {len(hits)} 个候选没被拒！")
        for h in hits[:10]:
            print(f"   {h['name']}: {h['body'][:200]}")
    else:
        print("❌ 全部 signature mismatch —— signature 需要掌瓦的微信 AppSecret，")
        print("   那个不在 APK 里（服务端持有）。这条路到头了。")

    OUT.write_text(json.dumps({"ticket": ticket, "tried": len(candidates),
                               "hits": hits}, ensure_ascii=False, indent=2),
                   encoding="utf-8")
    print(f"\n已存 -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
