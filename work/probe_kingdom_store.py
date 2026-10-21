#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
只读探针：看一看「王国商店」在接口层到底给了哪些字段。

1) 用存档里的 ct 换一张新的 wt（Cookie 里的 tid，只有 30 分钟）
2) POST /go/mlol_store/agame/user_store   -> 两个面板（dailystore / kingdomstore）
3) POST /go/mlol_store/agame/kingdom_store -> 王国商店单独调用，看字段是否更全

不写任何 App 代码，只落一份 JSON 到 capture/_dump/kingdom_probe.json。
"""
from __future__ import annotations

import json
import pathlib
import sys
import urllib.error
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
DUMP = ROOT / "val-shop" / "capture" / "_dump"
OUT = DUMP / "kingdom_probe.json"

HOSTS = ["https://app.mval.qq.com", "https://app.val.qq.com"]

USER_ID = "JA-3095d6174193457a-b8d058817457ae26"
QQ_OPENID = "A44A6AA89A42ECA6909C2492C2193D14"
UIN = "2751275315"
CT = ("8418A93A9C7DCE05D6F877227275163173867551666557B0B48BEDE369A4A60CBE162AC0AD086EBE3490305"
      "DA46072AAC8AFBC0071DD37E54698B1578BCBD29E970802B124A9DFF4816568176D9E8E71F28FA3661AD"
      "B8E421553BA9682AC673D8B0DD6DA36CAA51ADC7E94A4E347C48B649E99D97DF3A88306C6074633353D4"
      "384D6A7BC5670BE88699895F8A88D08AC5C223645B49893FB8D1DBB6D776BCA937BC66806E80F50789"
      "BFD7E5BAF362EE48E47074E38CE514D705B6CA2EBB252941AECB7672B2F68207F8B1626BF6CAC3E6E3"
      "06AFF262BC9085B446EFAEAD18988905F1C2DA655A97D")

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def post(host: str, path: str, body: dict, cookie: str | None = None) -> dict:
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


def get_tid() -> str | None:
    for host in HOSTS:
        try:
            r = post(host, "/go/auth/get_web_ticket",
                     {"ct": CT, "user_id": USER_ID,
                      "config_params": {"lang_type": 0}})
            d = r.get("data") or {}
            tid = d.get("wt") or d.get("tid")
            print(f"  get_web_ticket {host} result={r.get('result')} tid={'ok' if tid else 'none'}")
            if tid:
                return tid
        except Exception as e:  # noqa: BLE001
            print(f"  get_web_ticket {host} 异常 {e}")
    for host in HOSTS:
        try:
            r = post(host, "/go/auth/refresh_client_ticket",
                     {"ct": CT, "user_id": USER_ID, "local_is_new_user": 0,
                      "config_params": {"lang_type": 0}})
            info = ((r.get("data") or {}).get("ct_info") or {})
            tid = info.get("wt")
            print(f"  refresh_client_ticket {host} result={r.get('result')} tid={'ok' if tid else 'none'}")
            if tid:
                return tid
        except Exception as e:  # noqa: BLE001
            print(f"  refresh_client_ticket {host} 异常 {e}")
    return None


def call(host: str, path: str, cookie: str) -> dict:
    for body in ({}, {"game_zone": "val", "source_game_zone": "val"}):
        try:
            r = post(host, path, body, cookie)
        except urllib.error.HTTPError as e:
            return {"_http": e.code, "_path": path}
        except Exception as e:  # noqa: BLE001
            return {"_err": str(e), "_path": path}
        if r.get("result") == 0:
            return r
        last = r
    return last


def summarize(panel: dict) -> None:
    print(f"    面板 key={panel.get('key')!r} title={panel.get('title')!r} "
          f"time={panel.get('time')} end_ts={panel.get('end_ts')} cur_ts={panel.get('cur_ts')}")
    for g in panel.get("list") or []:
        keys = ",".join(sorted(g.keys()))
        print(f"      · {g.get('goods_name')!r:24} price={g.get('rmb_price')!r:8} "
              f"quality={g.get('quality')!r:8} bg={str(g.get('bg_image')).split('/')[-1]!r} "
              f"pic={str(g.get('goods_pic')).split('/')[-2:]!r}")
    print(f"      字段全集：{keys}")


def main() -> int:
    print("[1/3] 用 ct 换新 wt")
    tid = get_tid()
    if not tid:
        print("换不到 wt（ct 可能已过期）。")
        return 1
    cookie = build_cookie(tid)

    result: dict = {}
    print("\n[2/3] POST /go/mlol_store/agame/user_store")
    for host in HOSTS:
        r = call(host, "/go/mlol_store/agame/user_store", cookie)
        if r.get("result") == 0:
            print(f"  host={host} result=0，面板 {len(r.get('data') or [])} 个")
            for p in r.get("data") or []:
                summarize(p)
            result["user_store"] = r
            break
        print(f"  host={host} -> {json.dumps(r, ensure_ascii=False)[:160]}")

    print("\n[3/3] POST /go/mlol_store/agame/kingdom_store")
    for host in HOSTS:
        r = call(host, "/go/mlol_store/agame/kingdom_store", cookie)
        print(f"  host={host} result={r.get('result')} msg={r.get('msg')!r}")
        if r.get("result") == 0:
            data = r.get("data")
            panels = data if isinstance(data, list) else [data] if isinstance(data, dict) else []
            for p in panels:
                if isinstance(p, dict) and p.get("list") is not None:
                    summarize(p)
                else:
                    print(f"    非面板数据：{json.dumps(p, ensure_ascii=False)[:400]}")
            result["kingdom_store"] = r
            break
        print(f"     {json.dumps(r, ensure_ascii=False)[:200]}")

    DUMP.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n已落盘 -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
