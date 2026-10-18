#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
扫码登录 signature 破解验证 —— 从 PC 端到端跑通

## 破解结果（从 Frida 抓到的 SHA-1 原文直接读出来）

    signature = SHA1(
        "appid={APPID}&noncestr={nonce}&sdk_ticket={ticket}&timestamp={ts}"
    ).hexdigest()

要点（踩了三个坑才试出来）：

  1. 参数名是 **`sdk_ticket`**，不是 `ticket`
  2. **`scope` 不参与**签名（虽然它是请求 URL 上的参数）
  3. 顺序是**字母序**：appid < noncestr < sdk_ticket < timestamp
  4. **不需要 AppSecret** —— 全靠 `get_sdk_ticket` 下发的 ticket

## 这意味着什么

扫码登录整条路**可以在我们自己的 App 里实现**：
先拿 ticket、自己算签名、自己请求二维码、自己长轮询拿 authCode、
再拿去 `/go/auth/login_by_wechat` 换登录态。**不需要电脑，不需要模拟器。**

这个脚本先验证第 1-3 步（拿到二维码），成了就说明路通了。
"""
from __future__ import annotations

import hashlib
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
QR_URL = "https://open.weixin.qq.com/connect/sdk/qrconnect"
POLL_URL = "https://long.open.weixin.qq.com/connect/l/qrconnect"

OUT_DIR = pathlib.Path(__file__).parent / "_dump"
OUT = OUT_DIR / "qr_login_verify.json"
QR_PNG = OUT_DIR / "qr_login.png"

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# 冗余对照：破解出来的公式，拿真机抓到的样本自检
KNOWN = [
    # (appid, noncestr, ticket, timestamp) -> signature
    ("wxcbb49f1f39656c2a", "WM7gpb",
     "qeuRRdzufZaOpdhfU2Q4gGbgoxq-NLbBLoPmh9nUqydeslyBQFiDXVdbrZRb18EWzY4VZ4OSxxjkW9qnzKAPBw",
     "1792324928",
     "b7733c8ae0e0433f912123917bc9b5b1214a7ea6"),
]


def sign(appid: str, nonce: str, ticket: str, ts: str) -> str:
    """破解出来的公式"""
    pre = f"appid={appid}&noncestr={nonce}&sdk_ticket={ticket}&timestamp={ts}"
    return hashlib.sha1(pre.encode("utf-8")).hexdigest()


def selfcheck() -> bool:
    print("[0] 用真机抓到的样本自检公式")
    ok = True
    for appid, nonce, ticket, ts, want in KNOWN:
        got = sign(appid, nonce, ticket, ts)
        flag = "✅" if got == want else "❌"
        print(f"    {flag} nonce={nonce}  期望 {want[:16]}…  得到 {got[:16]}…")
        ok = ok and (got == want)
    print()
    return ok


def nonce(n=6) -> str:
    return "".join(random.choices(string.ascii_letters + string.digits, k=n))


def post_json(path: str, body: dict, cookie: str | None = None):
    h = {"User-Agent": "okhttp/4.9.2",
         "Content-Type": "application/json; charset=utf-8"}
    if cookie:
        h["Cookie"] = cookie
    req = urllib.request.Request(HOST + path, data=json.dumps(body).encode(),
                                 headers=h, method="POST")
    with urllib.request.urlopen(req, timeout=25) as r:
        return json.loads(r.read().decode("utf-8", errors="replace"))


def http_get(url: str):
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 "
                      "(KHTML, like Gecko) Version/4.0 Chrome/110.0 Mobile Safari/537.36",
        "Referer": "https://open.weixin.qq.com/"}, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, (e.read() if e.fp else b"")


def main():
    result = {"selfcheck": selfcheck()}

    print("[1] POST /go/auth/get_sdk_ticket  （匿名 Cookie 就能调）")
    try:
        r = post_json("/go/auth/get_sdk_ticket", {},
                      "clientType=9; openid=null; access_token=null;")
        ticket = ((r.get("data") or {}).get("ticket") or "")
        print(f"    result={r.get('result')}  ticket len={len(ticket)}")
        print(f"    {ticket[:60]}…")
    except Exception as e:
        print(f"    ❌ 失败：{e}")
        return 1
    if not ticket:
        print("    ❌ 没拿到 ticket")
        return 1
    print()

    nc = nonce()
    ts = str(int(time.time()))
    sig = sign(APPID, nc, ticket, ts)

    print("[2] 自己算签名（破解出来的公式）")
    print(f"    原文 = appid={APPID}&noncestr={nc}&sdk_ticket={ticket[:20]}…&timestamp={ts}")
    print(f"    signature = {sig}")
    print()

    params = {"appid": APPID, "noncestr": nc, "timestamp": ts,
              "scope": SCOPE, "signature": sig}
    url = QR_URL + "?" + urllib.parse.urlencode(params)

    print("[3] GET qrconnect  —— 关键一步")
    status, body = http_get(url)
    print(f"    HTTP {status}  ({len(body)} 字节)")
    text = body[:400].decode("utf-8", errors="replace")
    result["qr_request"] = {"status": status, "len": len(body), "head": text}

    if b"errcode" in body[:200] and b"signature" in body[:200]:
        print(f"    ❌ 还是被拒：{text}")
        print()
        print("=" * 70)
        print("  公式没对上，需要再回真机核对一次")
        print("=" * 70)
        OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
        return 1

    # 成功的话响应是 JSON，里面有 uuid 和 qrcode
    try:
        j = json.loads(body.decode("utf-8", errors="replace"))
    except Exception:
        j = {}

    uuid = j.get("uuid") or j.get("Uuid") or ""
    print(f"    uuid = {uuid}")
    print(f"    响应字段: {list(j.keys())}")

    if uuid:
        print()
        print("=" * 70)
        print("  🎉🎉 成功了！！signature 算法正确，二维码可以自己申请！")
        print("=" * 70)
        print()
        print(f"  长轮询地址（用户扫码后拿 authCode）：")
        print(f"    {POLL_URL}?f=json&uuid={uuid}")
        print()
        print("  → 扫码登录整条路可以在 iOS App 里实现了，不需要电脑。")
    else:
        print(f"    没拿到 uuid，原始响应：{text}")

    result["uuid"] = uuid
    result["payload"] = j
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n已存 -> {OUT}")
    return 0 if uuid else 2


if __name__ == "__main__":
    sys.exit(main())
