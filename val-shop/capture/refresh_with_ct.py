#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
用正确的 ct 刷新票据。

## 之前错在哪

Frida 脚本 hook `AppContext.a(...)` 时参数映射错位了，把几个字段标串了。
对照抓包响应 `ct_info` 才确认：

    ct_info.ct        (464 字符)  <- 真 ct，我原来标成了 access_token
    ct_info.wt        (352 字符)  <- 就是 Cookie 里的 tid
    ct_info.openid    (32 字符)   <- 74193457a-b8d058817457ae26_10200
    bind_info[0].uin  (32 字符)   <- A44A6AA89A42ECA6909C2492C2193D14，这才是 Cookie 要的 openid

有效期（来自 ct_info）：

    refresh_ct_span = 604800   ct  7 天
    refresh_wt_span = 1800     wt  30 分钟   <- 所以 tid 掉得这么快
    expires         = 2592000  30 天

结论：**ct 管 7 天，wt 只活 30 分钟**。所以必须每次用 ct 现换 wt，
而不是想着存一份长期有效的 Cookie。
"""
from __future__ import annotations

import json
import pathlib
import sys
import urllib.error
import urllib.request

HERE = pathlib.Path(__file__).parent
OUT = HERE / "_dump" / "session_fresh.json"
HOSTS = ["https://app.mval.qq.com", "https://app.val.qq.com"]

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# 从抓包里提取的（正确的映射）
USER_ID = "JA-3095d6174193457a-b8d058817457ae26"
QQ_OPENID = "A44A6AA89A42ECA6909C2492C2193D14"   # Cookie 里的 openid
UIN = "2751275315"
CT = ("8418A93A9C7DCE05D6F877227275163173867551666557B0B48BEDE369A4A60CBE162AC0AD086EBE3490305"
      "DA46072AAC8AFBC0071DD37E54698B1578BCBD29E970802B124A9DFF4816568176D9E8E71F28FA3661AD"
      "B8E421553BA9682AC673D8B0DD6DA36CAA51ADC7E94A4E347C48B649E99D97DF3A88306C6074633353D4"
      "384D6A7BC5670BE88699895F8A88D08AC5C223645B49893FB8D1DBB6D776BCA937BC66806E80F50789"
      "BFD7E5BAF362EE48E47074E38CE514D705B6CA2EBB252941AECB7672B2F68207F8B1626BF6CAC3E6E3"
      "06AFF262BC9085B446EFAEAD18988905F1C2DA655A97D")


def post(host, path, body, cookie=None):
    headers = {"User-Agent": "okhttp/4.9.2",
               "Content-Type": "application/json; charset=utf-8"}
    if cookie:
        headers["Cookie"] = cookie
    req = urllib.request.Request(host + path, data=json.dumps(body).encode(),
                                 headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=25) as r:
        return json.loads(r.read().decode("utf-8", errors="replace"))


def build_cookie(tid: str) -> str:
    return ("clientType=9; "
            f"uin=o{UIN}; appid=102061775; acctype=qc; "
            f"openid={QQ_OPENID}; userId={USER_ID}; accountType=5; tid={tid};")


def main():
    print(f"ct 长度 = {len(CT)}")
    print()

    tid = None
    print("[1/3] POST /go/auth/get_web_ticket  用 ct 换新 wt")
    for host in HOSTS:
        try:
            r = post(host, "/go/auth/get_web_ticket",
                     {"ct": CT, "user_id": USER_ID,
                      "config_params": {"lang_type": 0}})
            print(f"      {host}  result={r.get('result')} msg={r.get('msg')!r}")
            if r.get("result") == 0:
                d = r.get("data") or {}
                tid = d.get("wt") or d.get("tid")
                if tid:
                    print(f"      ✅ 新 wt 长度 {len(tid)}")
                    break
            else:
                print(f"      {json.dumps(r, ensure_ascii=False)[:200]}")
        except urllib.error.HTTPError as e:
            print(f"      {host}  HTTP {e.code}")
        except Exception as e:
            print(f"      {host}  异常 {e}")

    if not tid:
        print()
        print("[2/3] 换 refresh_client_ticket 再试")
        for host in HOSTS:
            try:
                r = post(host, "/go/auth/refresh_client_ticket",
                         {"ct": CT, "user_id": USER_ID, "local_is_new_user": 0,
                          "config_params": {"lang_type": 0}})
                print(f"      {host}  result={r.get('result')} msg={r.get('msg')!r}")
                if r.get("result") == 0:
                    info = ((r.get("data") or {}).get("ct_info") or {})
                    tid = info.get("wt")
                    if info.get("ct"):
                        print(f"      ct 也刷新了（长度 {len(info['ct'])}），"
                              f"refresh_ct_span={info.get('refresh_ct_span')}")
                    if tid:
                        print(f"      ✅ 新 wt 长度 {len(tid)}")
                        break
            except Exception as e:
                print(f"      {host}  异常 {e}")

    if not tid:
        print()
        print("❌ 换不到 wt。ct 可能也过期了（7 天），只能重新抓包。")
        return 1

    print()
    print("[3/3] 用新票据调每日商店")
    cookie = build_cookie(tid)
    ok = False
    for host in HOSTS:
        try:
            r = post(host, "/go/mlol_store/agame/user_store", {}, cookie)
            print(f"      {host}  result={r.get('result')} msg={r.get('msg')!r}")
            if r.get("result") == 0:
                ok = True
                for p in (r.get("data") or []):
                    if p.get("key") == "dailystore":
                        print(f"      ✅ 每日商店 {len(p.get('list', []))} 件，"
                              f"剩余 {p.get('time')} 秒")
                        for g in p.get("list", []):
                            print(f"         · {g.get('goods_name')}  "
                                  f"{g.get('rmb_price')}  {g.get('quality')}")
                        break
                break
        except Exception as e:
            print(f"      {host}  异常 {e}")

    sess = {"user_id": USER_ID, "ct": CT, "auth_type": 4,
            "openid": QQ_OPENID, "uin": UIN, "access_token": "", "tid": tid}
    txt = json.dumps(sess, ensure_ascii=False, separators=(",", ":"))
    OUT.write_text(txt + "\n\n# Cookie（有效期约 30 分钟）\n" + cookie + "\n",
                   encoding="utf-8")

    print()
    print("=" * 78)
    print("  粘进 App 的「粘贴登录态」（这样带 ct，能在 App 里自动续 wt）")
    print("=" * 78)
    print(txt)
    print()
    print(f"已存 -> {OUT}")
    return 0 if ok else 2


if __name__ == "__main__":
    sys.exit(main())
