#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
决定性实验：能不能用「掌瓦的微信 AppID + APK 签名证书 MD5」拿到扫码登录的二维码？

## 为什么这条路可能通

掌瓦的登录页有「扫码登录」，它走的是微信 SDK 的 diffdev 模块（不是拉起微信 App）：

    POST /go/auth/get_sdk_ticket              {}  -> {ticket}
    GET  https://open.weixin.qq.com/connect/sdk/qrconnect
             ?appid=%s&noncestr=%s&timestamp=%s&scope=%s&signature=%s
    GET  https://long.open.weixin.qq.com/connect/l/qrconnect?uuid=...   （长轮询）
    POST /go/auth/login_by_wechat  {appid, code}  -> 登录态

URL 模板来自 `com/tencent/mm/opensdk/diffdev/a/d.java`，是**微信 SDK 自带的**。

关键点：**它不拉起微信 App**，所以不需要 URL scheme / Universal Link，
也就不受「bundle ID 必须匹配」的约束。唯一的门是 `signature` 参数。

微信开放平台对 Android 的调用方校验用的是**签名证书**。掌瓦的 APK 就在手上，
证书能直接提出来 —— 所以这个 signature 有希望算出来。

## 这个脚本干嘛

1. 调 /go/auth/get_sdk_ticket，看要不要登录态
2. 用 appid + 证书指纹 请求二维码
3. 打印原始响应，判断 signature 到底是不是证书指纹

不管成不成，结果都写进报告 —— 成了就能做真正的「App 内扫码登录」。
"""
from __future__ import annotations

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
CERT_MD5 = "304c3871ea696f1f96157840d33b413d"
CERT_MD5_UP = CERT_MD5.upper()
CERT_SHA1 = "98a8e786c6310f273b3d3379ddc4fe19db6fe7b6"

HOST = "https://app.mval.qq.com"
QR_HOSTS = [
    "https://open.weixin.qq.com",
    "https://open.weixin.qq.com/connect/sdk/qrconnect",
]

OUT = pathlib.Path(__file__).parent / "_dump" / "qr_login_probe.json"

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def nonce(n=16):
    return "".join(random.choices(string.ascii_letters + string.digits, k=n))


def post(path, body, cookie=None):
    h = {"User-Agent": "okhttp/4.9.2",
         "Content-Type": "application/json; charset=utf-8"}
    if cookie:
        h["Cookie"] = cookie
    req = urllib.request.Request(HOST + path, data=json.dumps(body).encode(),
                                 headers=h, method="POST")
    with urllib.request.urlopen(req, timeout=25) as r:
        return r.status, r.read().decode("utf-8", errors="replace")


def get(url):
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 "
                      "(KHTML, like Gecko) Version/4.0 Chrome/110.0 Mobile Safari/537.36",
        "Referer": "https://open.weixin.qq.com/",
    }, method="GET")
    with urllib.request.urlopen(req, timeout=25) as r:
        return r.status, r.read().decode("utf-8", errors="replace")


results = {}


def probe(label, fn):
    print(f"  [{label}]")
    try:
        status, body = fn()
        print(f"    HTTP {status}")
        print(f"    {body[:500]}")
        results[label] = {"status": status, "body": body[:4000]}
    except urllib.error.HTTPError as e:
        raw = ""
        try:
            raw = e.read().decode("utf-8", errors="replace")[:500]
        except Exception:
            pass
        print(f"    HTTP {e.code}  {raw}")
        results[label] = {"status": e.code, "body": raw}
    except Exception as e:
        print(f"    异常 {e}")
        results[label] = {"error": str(e)}
    print()
    return results.get(label, {})


def main():
    print("=" * 78)
    print("  ① POST /go/auth/get_sdk_ticket  （不带任何登录态）")
    print("=" * 78)
    ticket = None
    r = probe("sdk_ticket_anon", lambda: post(
        "/go/auth/get_sdk_ticket", {}, "clientType=9; openid=null; access_token=null;"))
    if r.get("status") == 200:
        try:
            j = json.loads(r["body"]) if r["body"].startswith("{") else {}
        except Exception:
            j = {}
    # 完整响应可能在前 4000 字符里，重新解析一次
    try:
        full = json.loads(results["sdk_ticket_anon"]["body"])
        ticket = ((full.get("data") or {}).get("ticket"))
        print(f"  result={full.get('result')} msg={full.get('msg')!r} ticket={(ticket or '')[:40]}…")
        print()
    except Exception:
        pass

    print("=" * 78)
    print("  ② GET open.weixin.qq.com/connect/sdk/qrconnect  —— 试各种 signature 写法")
    print("=" * 78)
    ts = int(time.time())
    nc = nonce()

    variants = [
        ("cert_md5_lower", CERT_MD5),
        ("cert_md5_upper", CERT_MD5_UP),
        ("cert_sha1", CERT_SHA1),
        ("empty", ""),
        ("appid", APPID),
    ]

    for name, sig in variants:
        params = {
            "appid": APPID,
            "noncestr": nc,
            "timestamp": str(ts),
            "scope": "snsapi_userinfo",
            "signature": sig,
        }
        url = "https://open.weixin.qq.com/connect/sdk/qrconnect?" + urllib.parse.urlencode(params)
        res = probe(f"qrconnect_{name}", lambda u=url: get(u))
        body = res.get("body", "")
        if "uuid" in body or "wx_errcode" in body:
            print(f"    ★★★ {name} 有戏！ ===\\n")

    print("=" * 78)
    print("  ③ 带上 ticket 再试一次（有的实现会把 ticket 一起传）")
    print("=" * 78)
    if ticket:
        params = {
            "appid": APPID, "noncestr": nc, "timestamp": str(ts),
            "scope": "snsapi_userinfo", "signature": CERT_MD5,
            "ticket": ticket,
        }
        url = "https://open.weixin.qq.com/connect/sdk/qrconnect?" + urllib.parse.urlencode(params)
        probe("qrconnect_with_ticket", lambda: get(url))
    else:
        print("  没拿到 ticket，跳过\n")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"appid": APPID, "cert_md5": CERT_MD5,
                               "ticket": ticket, "results": results},
                              ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"全部原始响应已存 -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
