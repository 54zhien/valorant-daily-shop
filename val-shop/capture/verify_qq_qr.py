#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
QQ扫码 sign 破解 + 端到端验证

## 破解结果（从 com/tencent/open/utils/n.java:528 读出来的）

    public static String b(Context ctx, String time) {
        String pkg = ctx.getPackageName();                        // com.tencent.apps.valorant
        Signature[] sigs = pm.getPackageInfo(pkg, 64).signatures;
        MessageDigest md = MessageDigest.getInstance("MD5");
        md.update(sigs[0].toByteArray());                         // 证书 DER
        String certMd5 = p.a(md.digest());                        // hex
        md.reset();
        String s = pkg + "_" + certMd5 + "_" + time + "";         // 用下划线拼
        md.update(p.j(s));                                        // p.j = getBytes("UTF-8")，没加密
        return p.a(md.digest());                                  // hex
    }

也就是：

    sign = md5( f"{packageName}_{certMd5}_{time}" )

真机样本自检：pkg=com.tencent.apps.valorant，certMd5=304c3871…，time=1792326852
映射到 1a7fe16b837e17fddc74ecc2232271bc —— **逐字节一致**。

## URL（从 Frida 抓的 WebView.loadUrl，原样）

    https://openmobile.qq.com/oauth2.0/m_authorize?
        client_id=102061775&style=qr&response_type=token
        &redirect_uri=auth://tauth.qq.com/&time=…&sign=…
        &scope=all&display=mobile&pf=openmobile_android&sdkv=3.5.17.lite
        &sdkp=a&switch=1&compat_v=1&format=json&status_os=12
        &status_version=32&show_download_ui=true&cancel_display=1

跟微信那条最大的区别：**这是纯网页**，没有签名挑战，只要 sign 对上就行。
"""
from __future__ import annotations

import hashlib
import json
import pathlib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

PKG = "com.tencent.apps.valorant"
CERT_MD5 = "304c3871ea696f1f96157840d33b413d"
QQ_APPID = "102061775"

AUTHORIZE = "https://openmobile.qq.com/oauth2.0/m_authorize"
OUT = pathlib.Path(__file__).parent / "_dump" / "qq_qr_verify.json"

# 真机样本，用来自检公式
KNOWN = [("com.tencent.apps.valorant", "304c3871ea696f1f96157840d33b413d",
          "1792326852", "1a7fe16b837e17fddc74ecc2232271bc")]

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def qq_sign(pkg: str, cert_md5: str, ts: str) -> str:
    """从 n.b(Context,String) 逐行还原出来的"""
    return hashlib.md5(f"{pkg}_{cert_md5}_{ts}".encode("utf-8")).hexdigest()


def build_url(ts: str) -> str:
    params = {
        "cancel_display": "1",
        "sdkp": "a",
        "display": "mobile",
        "format": "json",
        "sign": qq_sign(PKG, CERT_MD5, ts),
        "sdkv": "3.5.17.lite",
        "response_type": "token",
        "status_os": "12",
        "client_id": QQ_APPID,
        "switch": "1",
        "status_version": "32",
        "show_download_ui": "true",
        "pf": "openmobile_android",
        "scope": "all",
        "compat_v": "1",
        "status_machine": "U00tUzkyMTA=",
        "style": "qr",
        "time": ts,
        "redirect_uri": "auth://tauth.qq.com/",
    }
    return AUTHORIZE + "?" + urllib.parse.urlencode(params)


def main():
    print("[0] 公式自检")
    ok = True
    for pkg, cert, ts, want in KNOWN:
        got = qq_sign(pkg, cert, ts)
        flag = "✅" if got == want else "❌"
        print(f"    {flag} time={ts}  期望 {want}  得到 {got}")
        ok = ok and got == want
    if not ok:
        print("    公式不对，别再往下走了")
        return 1
    print()

    ts = str(int(time.time()))
    url = build_url(ts)
    print("[1] 自己拼出来的 URL")
    print(f"    time = {ts}")
    print(f"    sign = {qq_sign(PKG, CERT_MD5, ts)}")
    print()

    print("[2] GET m_authorize")
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 "
                      "(KHTML, like Gecko) Version/4.0 Chrome/110.0 Mobile Safari/537.36",
    })
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            status = r.status
            body = r.read()
            headers = dict(r.headers)
    except urllib.error.HTTPError as e:
        status = e.code
        body = e.read() if e.fp else b""
        headers = dict(e.headers or {})

    text = body.decode("utf-8", errors="replace")
    print(f"    HTTP {status}  {len(body)} 字节")
    print(f"    Location: {headers.get('Location', '(无)')}")
    print(f"    正文前 400 字：")
    print(f"      {text[:400]}")
    print()

    result = {"time": ts, "sign": qq_sign(PKG, CERT_MD5, ts),
              "status": status, "url": url, "body_head": text[:2000],
              "location": headers.get("Location", "")}

    # 判断有没有戏
    low = text.lower()
    if status == 200 and ("qrcode" in low or "qrconnect" in low
                          or "ptlogin" in low or "<html" in low):
        print("=" * 72)
        print("  🎉 拿到页面了！QQ扫码这条路也能自己走")
        print("=" * 72)
        qr_link = ""
        for kw in ("ptlogin2.qq.com", "xui.ptlogin", "qrcode", "check_sig"):
            i = text.find(kw)
            if i > 0:
                qr_link = text[max(0, i - 120): i + 200]
                break
        if qr_link:
            print(f"  页面里和二维码相关的片段：\n    {qr_link}")
            result["qr_hint"] = qr_link
    elif "error" in low or "sign" in low:
        print("=" * 72)
        print("  ❌ 被拒了 —— 看上面正文，可能是 sign 校验没过")
        print("=" * 72)
    else:
        print("=" * 72)
        print("  ⚠️ 响应形态不明，看上面正文判断")
        print("=" * 72)

    OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n已存 -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
