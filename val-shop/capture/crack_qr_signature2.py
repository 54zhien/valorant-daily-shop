#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
爆破 qrconnect signature —— 第二轮，三个真实样本交叉验证。

## 三个样本（全部从真机抓的，appid 恒为 wxcbb49f1f39656c2a）

  #  noncestr   timestamp     signature
  1  mnfKFk     1792317402    a08f2d92c84f6ec4599969474b3edf36a6738b44
  2  CZeFon     1792318159    6ad81c45b26868406af889af6e49400203479148
  3  ad32XH     1792318964    a09baef9cd50ad3898de15755d57966673678208

## 这一轮新增的密钥候选

上一轮把 4 个公开参数的 5 万种拼法穷举干净了，全不中 —— 说明**一定掺了个外部量**。
微信开放平台校验 Android 调用方用的是**应用签名**，所以把 APK 的证书指纹
和包名都当候选塞进去：

    证书 MD5  = 304c3871ea696f1f96157840d33b413d
    证书 SHA1 = 98a8e786c6310f273b3d3379ddc4fe19db6fe7b6
    包名      = com.tencent.apps.valorant

**三个样本必须同时命中**，所以基本不会有巧合误判。
"""
from __future__ import annotations

import hashlib
import itertools
import json
import pathlib
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

APPID = "wxcbb49f1f39656c2a"
SAMPLES = [
    ("mnfKFk", "1792317402", "a08f2d92c84f6ec4599969474b3edf36a6738b44"),
    ("CZeFon", "1792318159", "6ad81c45b26868406af889af6e49400203479148"),
    ("ad32XH", "1792318964", "a09baef9cd50ad3898de15755d57966673678208"),
]

CERT_MD5 = "304c3871ea696f1f96157840d33b413d"
CERT_MD5_UP = CERT_MD5.upper()
CERT_SHA1 = "98a8e786c6310f273b3d3379ddc4fe19db6fe7b6"
PKG = "com.tencent.apps.valorant"
SCOPE = "snsapi_userinfo"

SECRETS = [CERT_MD5, CERT_MD5_UP, CERT_SHA1, PKG, APPID, "102061775",
           CERT_MD5 + SCOPE, PKG + CERT_MD5]

OUT = pathlib.Path(__file__).parent / "_dump" / "sig_crack2.json"


def sha1(s: str) -> str:
    return hashlib.sha1(s.encode("utf-8")).hexdigest()


def build(sep: str, fmt, order: list[str], nonce: str, ts: str) -> str:
    vals = {"appid": APPID, "scope": SCOPE, "noncestr": nonce, "timestamp": ts}
    return sep.join(fmt(k, vals[k]) for k in order)


def main():
    print(f"样本数 = {len(SAMPLES)}")
    for i, (n, t, s) in enumerate(SAMPLES, 1):
        print(f"  #{i}  noncestr={n:8s} ts={t}  sig={s}")
    print()

    keys = ["appid", "scope", "noncestr", "timestamp"]
    SEPS = ["", "&", "|", ",", ":", ";", "_", "-"]
    FMTS = [
        lambda k, v: f"{k}={v}",
        lambda k, v: v,
        lambda k, v: f"{k}{v}",
        lambda k, v: f"{k.upper()}={v}",
    ]
    FIXED = ["", "qrconnect", "sdk", "/connect/sdk/qrconnect", APPID]

    tried = 0
    hits = []

    # 阶段 A：参数串 + secret（前后缀 / 中间插入）
    print("[A] 参数串 x secret（前缀/后缀/中间）")
    base_forms = set()
    for order in itertools.permutations(keys):
        for sep in SEPS:
            for fmt in FMTS:
                base_forms.add((order, sep, fmt))
    print(f"    底串模板 {len(base_forms)} 个 x secret {len(SECRETS)} x 8 种位置")

    for (order, sep, fmt) in base_forms:
        for pre in FIXED:
            for nonce, ts, target in SAMPLES:
                pass  # 下面统一按样本算
            for sec in SECRETS:
                for pos in range(5):
                    ok = True
                    for nonce, ts, target in SAMPLES:
                        parts = [fmt(k, {"appid": APPID, "scope": SCOPE,
                                         "noncestr": nonce, "timestamp": ts}[k])
                                 for k in order]
                        parts.insert(min(pos, len(parts)), sec)
                        cand = pre + sep.join(parts)
                        tried += 1
                        if sha1(cand) != target:
                            ok = False
                            break
                    if ok:
                        hits.append({"stage": "A", "order": order, "sep": sep,
                                     "secret": sec, "pos": pos, "pre": pre})
                        print(f"  ★★★ 命中！ {hits[-1]}")
    print(f"    累计 {tried}")
    print()

    # 阶段 B：把 appid 固定在最前/最后 + secret（更贴近微信文档的写法）
    if not hits:
        print("[B] appid 固定两端 + secret，key=value 用 & 连接")
        for order in itertools.permutations(["scope", "noncestr", "timestamp"]):
            for appid_pos in ("first", "last"):
                for sec_pos in ("first", "last", "none"):
                    for sep in ["", "&", "|"]:
                        ok = True
                        for nonce, ts, target in SAMPLES:
                            vals = {"appid": APPID, "scope": SCOPE,
                                    "noncestr": nonce, "timestamp": ts}
                            parts = [f"{k}={vals[k]}" for k in order]
                            if appid_pos == "first":
                                parts.insert(0, f"appid={APPID}")
                            else:
                                parts.append(f"appid={APPID}")
                            if sec_pos == "first":
                                parts.insert(0, SECRETS[0])
                            elif sec_pos == "last":
                                parts.append(SECRETS[0])
                            cand = sep.join(parts)
                            tried += 1
                            if sha1(cand) != target:
                                ok = False
                                break
                        if ok:
                            hits.append({"stage": "B", "order": order,
                                         "appid_pos": appid_pos, "sec_pos": sec_pos})
                            print(f"  ★★★ 命中！ {hits[-1]}")
        print(f"    累计 {tried}")
        print()

    # 阶段 C：把 noncestr 换成「服务端可能下发的东西」再试
    if not hits:
        print("[C] noncestr 可能不是随机的 —— 试试它是别的东西的截断")
        print("    （先跳过，需要更多样本才能判断）")
        print()

    print("=" * 72)
    if hits:
        print(f"🎉 爆破成功！{len(hits)} 个解")
        print("   → signature 能自己算，扫码登录整条路打通")
    else:
        print(f"❌ 累计 {tried} 种，三个样本无一同时命中")
        print("   → signature 里掺的量我们手上没有")
        print("   → 最可能是掌瓦在微信开放平台的 AppSecret（只有服务器有）")
    print("=" * 72)

    OUT.write_text(json.dumps({"samples": SAMPLES, "tried": tried, "hits": hits},
                              ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n已存 -> {OUT}")
    return 0 if hits else 1


if __name__ == "__main__":
    sys.exit(main())
