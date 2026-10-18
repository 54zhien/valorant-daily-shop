#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
关键验证：refresh_client_ticket 会不会给一张**新的 ct**？

如果会 —— 那用户就**再也不需要重新抓包了**：
    每 6 天用旧 ct 换一张新 ct（新 ct 又是 7 天有效），滚动续期，无限延命。

这比「在 App 里实现 QQ/微信登录」实际得多：登录本身绕不过去（需要
掌瓦的 AppSecret / AppID 绑定），但只要 ct 能滚动续期，抓一次就够了。
"""
from __future__ import annotations

import json
import pathlib
import sys
import urllib.error
import urllib.request

HOSTS = ["https://app.mval.qq.com", "https://app.val.qq.com"]
S = pathlib.Path(__file__).parent / "_dump" / "session_fresh.json"

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def post(host, path, body, cookie=None):
    h = {"User-Agent": "okhttp/4.9.2", "Content-Type": "application/json; charset=utf-8"}
    if cookie:
        h["Cookie"] = cookie
    req = urllib.request.Request(host + path, data=json.dumps(body).encode(),
                                 headers=h, method="POST")
    with urllib.request.urlopen(req, timeout=25) as r:
        return json.loads(r.read().decode("utf-8", errors="replace"))


def main():
    sess = json.loads(S.read_text(encoding="utf-8").split("\n")[0])
    ct_old = sess["ct"]
    uid = sess["user_id"]
    print(f"旧 ct 长度 {len(ct_old)}  {ct_old[:24]}…")
    print()

    for host in HOSTS:
        try:
            r = post(host, "/go/auth/refresh_client_ticket",
                     {"ct": ct_old, "user_id": uid, "local_is_new_user": 0,
                      "config_params": {"lang_type": 0}})
            print(f"{host}")
            print(f"  result={r.get('result')} msg={r.get('msg')!r}")
            if r.get("result") != 0:
                print(f"  {json.dumps(r, ensure_ascii=False)[:300]}")
                continue

            info = ((r.get("data") or {}).get("ct_info") or {})
            ct_new = info.get("ct")
            wt_new = info.get("wt")
            print(f"  ct 长度 {len(ct_new or '')}   refresh_ct_span={info.get('refresh_ct_span')}")
            print(f"  wt 长度 {len(wt_new or '')}   refresh_wt_span={info.get('refresh_wt_span')}")
            if ct_new:
                same = (ct_new == ct_old)
                print(f"  ct 变了吗: {'没变' if same else '★ 变了（新的一张）'}")
            print()
            if ct_new and wt_new:
                print("🎉 refresh_client_ticket 同时给了新 ct + 新 wt")
                print("   → 滚动续期可行，抓一次就能长期用")
                # 存下来
                out = S.parent / "session_rolled.json"
                out.write_text(json.dumps({
                    "user_id": uid, "ct": ct_new, "auth_type": 4,
                    "openid": sess.get("openid"), "uin": sess.get("uin"),
                    "access_token": "", "tid": wt_new,
                }, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
                print(f"   已存 -> {out}")
                return 0
        except urllib.error.HTTPError as e:
            print(f"{host}  HTTP {e.code}")
        except Exception as e:
            print(f"{host}  异常 {e}")

    print("❌ 没拿到新 ct")
    return 1


if __name__ == "__main__":
    sys.exit(main())
