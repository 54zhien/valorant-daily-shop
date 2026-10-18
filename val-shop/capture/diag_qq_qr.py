#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
QQ 扫码「二维码失效」诊断 —— 往下追一层

## 已知

m_authorize 那一层是通的：自己算 sign 拼 URL → HTTP 200 → 返回 HTML，
HTML 里带着 xui.ptlogin2.qq.com/cgi-bin/xlogin?...&force_qr=1&autorefresh=1。

用户实测：二维码能画出来，但**扫了之后提示「二维码失效」**。

所以问题在下一层 —— 真正生成/校验二维码的是 ptlogin2。

## 这个脚本干嘛

1. 自己拼 m_authorize，拿到入口 HTML
2. 从 HTML 里把 xlogin 的 URL 抠出来
3. 带着 cookie 去请求 xlogin
4. 看它返回什么 —— 二维码图片？还是错误？

如果 xlogin 就报错，那问题在 sign/time 或 cookie；
如果 xlogin 正常出了二维码，那说明二维码有 TTL，得看刷新机制。
"""
from __future__ import annotations

import hashlib
import http.cookiejar
import json
import pathlib
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

PKG = "com.tencent.apps.valorant"
CERT_MD5 = "304c3871ea696f1f96157840d33b413d"
QQ_APPID = "102061775"
AUTHORIZE = "https://openmobile.qq.com/oauth2.0/m_authorize"

OUT = pathlib.Path(__file__).parent / "_dump" / "qq_qr_diag.json"

UA = ("Mozilla/5.0 (Linux; Android 12; SM-S9210) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Version/4.0 Chrome/110.0.5481.154 Mobile Safari/537.36")

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def qq_sign(ts: str) -> str:
    return hashlib.md5(f"{PKG}_{CERT_MD5}_{ts}".encode()).hexdigest()


def build_url(ts: str) -> str:
    params = {
        "cancel_display": "1", "sdkp": "a", "display": "mobile", "format": "json",
        "sign": qq_sign(ts), "sdkv": "3.5.17.lite", "response_type": "token",
        "status_os": "12", "client_id": QQ_APPID, "switch": "1",
        "status_version": "32", "show_download_ui": "true",
        "pf": "openmobile_android", "scope": "all", "compat_v": "1",
        "status_machine": "U00tUzkyMTA=", "style": "qr", "time": ts,
        "redirect_uri": "auth://tauth.qq.com/",
    }
    return AUTHORIZE + "?" + urllib.parse.urlencode(params)


def main():
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))

    def get(url, extra_headers=None, referer=None):
        h = {"User-Agent": UA, "Accept": "*/*",
             "Accept-Language": "zh-CN,zh;q=0.9"}
        if referer:
            h["Referer"] = referer
        if extra_headers:
            h.update(extra_headers)
        req = urllib.request.Request(url, headers=h)
        try:
            with opener.open(req, timeout=25) as r:
                return r.status, r.read(), dict(r.headers)
        except urllib.error.HTTPError as e:
            return e.code, (e.read() if e.fp else b""), dict(e.headers or {})

    ts = str(int(time.time()))
    url = build_url(ts)
    print(f"[1] m_authorize  time={ts}")
    status, body, _ = get(url)
    html = body.decode("utf-8", errors="replace")
    print(f"    HTTP {status}  {len(body)} 字节")

    # 从 HTML 里抠出 xlogin 的 URL（源码里是 \x2F \x3D \x26 这种转义的）
    text = html.replace("\\x2F", "/").replace("\\x3D", "=").replace("\\x26", "&")
    text = text.replace("\\x3A", ":").replace("\\x3F", "?").replace("\\x2f", "/")
    m = re.search(r'(https?://[^\s"\'<>]*(?:xlogin|ptlogin2)[^\s"\'<>]*)', text)
    if not m:
        # 兜底：找 iframe / src
        m = re.search(r'src\s*=\s*["\']([^"\']+)["\']', text)
    if not m:
        print("    ❌ HTML 里没找到 xlogin URL")
        print(f"    正文前 600 字：\n{html[:600]}")
        return 1

    xlogin = m.group(1)
    print(f"\n[2] 抠出 xlogin URL（{len(xlogin)} 字符）")
    print(f"    {xlogin[:200]}…")

    # 只看关键参数
    q = urllib.parse.urlparse(xlogin)
    for kv in (q.query or "").split("&"):
        if "=" in kv:
            k, v = kv.split("=", 1)
            print(f"      {k} = {v}")

    print(f"\n[3] 请求 xlogin（带上第一层的 cookie）")
    status2, body2, hdr2 = get(xlogin, referer=url)
    print(f"    HTTP {status2}  {len(body2)} 字节  Content-Type={hdr2.get('Content-Type','?')}")
    print(f"    Set-Cookie: {list(jar)}")

    text2 = body2.decode("utf-8", errors="replace")
    # 把完整 HTML 落盘，方便单独 grep 二维码请求
    (OUT.parent / "qq_xlogin.html").write_bytes(body2)
    print(f"    完整 HTML 已存 -> {OUT.parent / 'qq_xlogin.html'}")
    result = {"time": ts, "sign": qq_sign(ts), "authorize": url,
              "xlogin": xlogin, "status2": status2, "len2": len(body2),
              "head2": text2[:1500],
              "cookies": [c.name for c in jar]}

    print(f"\n    正文前 500 字：")
    print(f"      {text2[:500]}")

    # 二维码相关的线索
    for kw in ("ptqrshow", "qrcode", "QR", "showqr", "ptqrtoken", "qrsig",
               "二维码", "失效", "expired", "error"):
        i = text2.find(kw)
        if i >= 0:
            seg = text2[max(0, i - 80): i + 120].replace("\n", " ")
            print(f"    [{kw}] …{seg}…")

    OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n已存 -> {OUT}")

    print()
    print("=" * 72)
    if status2 == 200 and ("ptqrshow" in text2 or "qrsig" in text2 or "二维码" in text2):
        print("  xlogin 正常出了二维码 → 问题在二维码的 TTL / 刷新机制")
    elif status2 == 200:
        print("  xlogin 返回 200，但没有明显二维码痕迹 —— 看上面正文")
    else:
        print(f"  xlogin 返回 {status2} —— 问题在这一层")
    print("=" * 72)
    return 0


if __name__ == "__main__":
    sys.exit(main())
