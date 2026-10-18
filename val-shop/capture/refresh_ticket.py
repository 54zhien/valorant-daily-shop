#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
用 ct 刷新票据 —— 不需要重新抓包。

掌瓦的 wt（= Cookie 里的 tid）有效期很短（一小时量级），过期后所有业务接口
都返回 999999「票据异常」。但只要手里有 ct，就能自己换一张新的：

    POST /go/auth/refresh_client_ticket  {ct, user_id, ...}   -> 新 ct / wt
    POST /go/auth/get_web_ticket         {ct, user_id, ...}   -> 新 wt

这个脚本把整条链跑一遍并打印结果，同时输出可以直接粘贴的新 Cookie。
"""
from __future__ import annotations

import json
import pathlib
import sys
import urllib.error
import urllib.request

HERE = pathlib.Path(__file__).parent
S = HERE / "_dump" / "mval_session.json"
OUT = HERE / "_dump" / "refreshed.txt"
HOST = "https://app.mval.qq.com"
HOST_VAL = "https://app.val.qq.com"

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def post(host: str, path: str, cookie: str, body: dict):
    headers = {
        "Cookie": cookie,
        "User-Agent": "okhttp/4.9.2",
        "Content-Type": "application/json; charset=utf-8",
    }
    req = urllib.request.Request(host + path, data=json.dumps(body).encode(),
                                 headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=25) as r:
        return json.loads(r.read().decode("utf-8", errors="replace"))


def cookie_for(s: dict, tid: str | None = None) -> str:
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
                 ("tid", tid or s.get("tid"))):
        if v not in (None, ""):
            parts.append(f"{k}={v}")
    return "; ".join(parts) + ";"


def main():
    raw = json.loads(S.read_text(encoding="utf-8"))
    s = raw[-1] if isinstance(raw, list) else raw
    # 取最新的 ct
    if isinstance(raw, list):
        for r in reversed(raw):
            if r.get("ct") and r["ct"] != "*":
                s = r
                break

    ct = s.get("ct", "")
    uid = s.get("user_id", "")
    print(f"user_id = {uid}")
    print(f"ct      = {ct[:22]}…  (长度 {len(ct)})")
    print(f"tid     = {s.get('tid','')[:24]}…  (长度 {len(s.get('tid',''))})")
    print()

    new_ct, new_tid = None, None

    print("[1/3] POST /go/auth/refresh_client_ticket")
    for host in (HOST, HOST_VAL):
        try:
            r = post(host, "/go/auth/refresh_client_ticket", cookie_for(s),
                     {"ct": ct, "user_id": uid,
                      "local_is_new_user": 0,
                      "config_params": {"lang_type": 0}})
            res = r.get("result")
            print(f"      {host}  result={res} msg={r.get('msg')!r}")
            if res == 0:
                info = ((r.get("data") or {}).get("ct_info") or {})
                new_ct = info.get("ct") or ct
                new_tid = info.get("wt")
                print(f"      新 ct  = {str(new_ct)[:30]}…")
                print(f"      新 wt  = {str(new_tid)[:30] if new_tid else '（无）'}")
                break
            else:
                print(f"      {json.dumps(r, ensure_ascii=False)[:220]}")
        except urllib.error.HTTPError as e:
            print(f"      {host}  HTTP {e.code}")
        except Exception as e:
            print(f"      {host}  异常 {e}")

    if not new_tid:
        print()
        print("[2/3] POST /go/auth/get_web_ticket")
        for host in (HOST, HOST_VAL):
            try:
                r = post(host, "/go/auth/get_web_ticket", cookie_for(s, new_ct or ct),
                         {"ct": new_ct or ct, "user_id": uid,
                          "config_params": {"lang_type": 0}})
                res = r.get("result")
                print(f"      {host}  result={res} msg={r.get('msg')!r}")
                if res == 0:
                    d = r.get("data") or {}
                    new_tid = d.get("wt") or d.get("tid")
                    if new_tid:
                        print(f"      新 wt = {new_tid[:30]}…")
                        break
                else:
                    print(f"      {json.dumps(r, ensure_ascii=False)[:220]}")
            except urllib.error.HTTPError as e:
                print(f"      {host}  HTTP {e.code}")
            except Exception as e:
                print(f"      {host}  异常 {e}")

    print()
    if not new_tid:
        print("❌ 没换到新票据。ct 可能也过期了，只能重新抓一次包。")
        return 1

    print("✅ 换到新票据了")

    # 用新票据验证一下
    print()
    print("[3/3] 用新票据调一次每日商店验证")
    new_cookie = cookie_for(s, new_tid)
    for host in (HOST, HOST_VAL):
        try:
            r = post(host, "/go/mlol_store/agame/user_store", new_cookie, {})
            print(f"      {host}  result={r.get('result')} msg={r.get('msg')!r}")
            if r.get("result") == 0:
                panels = r.get("data") or []
                for p in panels:
                    if p.get("key") == "dailystore":
                        print(f"      ✅ 每日商店 {len(p.get('list',[]))} 件，"
                              f"剩余 {p.get('time')} 秒")
                        for g in p.get("list", []):
                            print(f"         · {g.get('goods_name')}  "
                                  f"{g.get('rmb_price')}  {g.get('quality')}")
                        break
                break
        except Exception as e:
            print(f"      {host}  异常 {e}")

    txt = json.dumps({
        "user_id": uid, "ct": new_ct or ct, "auth_type": s.get("auth_type", 4),
        "openid": s.get("openid"), "uin": s.get("uin"),
        "access_token": s.get("access_token"), "tid": new_tid,
    }, ensure_ascii=False, separators=(",", ":"))

    OUT.write_text(txt + "\n\n" + new_cookie + "\n", encoding="utf-8")
    print()
    print("=" * 78)
    print("  新的 session JSON（粘进 App 的「粘贴登录态」）")
    print("=" * 78)
    print(txt)
    print()
    print(f"已存 -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
