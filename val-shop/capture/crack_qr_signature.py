#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
爆破 qrconnect 的 signature 算法。

## 实测样本（从 logcat 里抓到的真实值）

    appid     = wxcbb49f1f39656c2a
    noncestr  = mnfKFk                    ← 只有 6 个字符
    timestamp = 1792317402
    scope     = snsapi_userinfo
    signature = a08f2d92c84f6ec4599969474b3edf36a6738b44   ← 40 hex = SHA1

## 思路

signature 是 SHA1（40 hex）就说明一定是「某串文本的 SHA1」。
那段文本由上面 4 个公开参数 + 可能的一个 secret 拼成。

先把「不需要 secret」的所有拼法穷举一遍 —— 只要有一种能对上，
这个签名我们就能自己算，整套扫码登录就能自己做。

拼法空间：
  · 4 个参数的全排列（24 种）
  · 元素格式：k=v / 只用 value / 大写键 / 带引号
  · 分隔符："" / "&" / "|" / "," / ":" / 换行
  · 是否排序
  · 前置/后置固定串（"appid="、"qrconnect" 之类）
如果不中，再挂上几个常见 secret 候选扫一遍。
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
NONCE = "mnfKFk"
TS = "1792317402"
SCOPE = "snsapi_userinfo"
TARGET = "a08f2d92c84f6ec4599969474b3edf36a6738b44"

OUT = pathlib.Path(__file__).parent / "_dump" / "sig_crack.json"

params = {
    "appid": APPID,
    "noncestr": NONCE,
    "timestamp": TS,
    "scope": SCOPE,
}

SEPS = ["", "&", "|", ",", ":", ";", "-", "_", "\n"]
FORMATS = [
    lambda k, v: f"{k}={v}",      # key=value
    lambda k, v: f"{k}{v}",       # keyvalue
    lambda k, v: v,               # 只用 value
    lambda k, v: f"{k.upper()}={v}",
    lambda k, v: f"'{k}':'{v}'",
]
PREFIXES = ["", "qrconnect", "sdk/qrconnect", "/connect/sdk/qrconnect",
            "appid=", "appid", "wxcbb49f1f39656c2a", "掌上无畏契约"]
SUFFIXES = ["", "&", "appid", "qrconnect", "wxcbb49f1f39656c2a"]

SECRETS = [
    "",  # 先试没有 secret 的
    # 几个可能的候选（掌瓦 / 微信开放平台常见位置）
    "wxcbb49f1f39656c2a",
    "102061775",
    "wxcbb49f1f39656c2a102061775",
    "mval",
    "mlol",
    "valorant",
    "zhangshangwuweiqiyue",
]


def sha1(s: str) -> str:
    return hashlib.sha1(s.encode("utf-8")).hexdigest()


def sha1_bytes(b: bytes) -> str:
    return hashlib.sha1(b).hexdigest()


def main():
    print(f"target = {TARGET}")
    print(f"输入   : appid={APPID} noncestr={NONCE} timestamp={TS} scope={SCOPE}")
    print()

    keys = list(params.keys())
    values = [params[k] for k in keys]
    tried = 0
    hits = []

    # ---- 阶段 1：不含 secret 的全排列 -------------------------------------
    print("[阶段 1] 4 个参数全排列 x 各种拼法（不含 secret）")
    for perm in itertools.permutations(range(4)):
        ks = [keys[i] for i in perm]
        vs = [values[i] for i in perm]
        for fmt in FORMATS:
            parts = [fmt(k, v) for k, v in zip(ks, vs)]
            for sep in SEPS:
                s = sep.join(parts)
                for pre in PREFIXES:
                    for suf in SUFFIXES:
                        cand = pre + s + suf
                        tried += 1
                        if sha1(cand) == TARGET:
                            hits.append({"stage": 1, "text": cand})
                            print(f"  ★★★ 命中！ text = {cand!r}")
    # 排序版
    for reverse in (False, True):
        for fmt in FORMATS:
            parts = [fmt(k, params[k]) for k in sorted(keys, reverse=reverse)]
            for sep in SEPS:
                s = sep.join(parts)
                for pre in PREFIXES:
                    for suf in SUFFIXES:
                        cand = pre + s + suf
                        tried += 1
                        if sha1(cand) == TARGET:
                            hits.append({"stage": 1, "text": cand})
                            print(f"  ★★★ 命中！ text = {cand!r}")
    print(f"  试了 {tried} 种，命中 {len(hits)}")
    print()

    # ---- 阶段 2：挂 secret -------------------------------------------------
    if not hits:
        print("[阶段 2] 加上 secret 候选")
        base_forms = []
        for perm in itertools.permutations(range(4)):
            parts = [f"{keys[i]}={values[i]}" for i in perm]
            for sep in ["", "&", "|"]:
                base_forms.append(sep.join(parts))
        for k in sorted(keys):
            base_forms.append(f"{k}={params[k]}")
        base_forms.append("".join(values))
        base_forms.append(APPID + NONCE + TS + SCOPE)
        base_forms = list(dict.fromkeys(base_forms))
        print(f"  底串 {len(base_forms)} 个 x secret {len(SECRETS)} 个")
        for b in base_forms:
            for sec in SECRETS:
                for cand in (b + sec, sec + b, b + "&key=" + sec,
                             b + "key=" + sec, f"{b}{sec}"):
                    tried += 1
                    if sha1(cand) == TARGET:
                        hits.append({"stage": 2, "text": cand, "secret": sec})
                        print(f"  ★★★ 命中！ secret={sec!r} text={cand!r}")
        print(f"  累计试了 {tried} 种")
        print()

    # ---- 阶段 3：非文本输入（二进制拼接 / MD5 再 SHA1 等）------------------
    if not hits:
        print("[阶段 3] 二进制拼接 / 二次哈希")
        raw = [APPID.encode(), NONCE.encode(), TS.encode(), SCOPE.encode()]
        for perm in itertools.permutations(range(4)):
            b = b"".join(raw[i] for i in perm)
            tried += 1
            if sha1_bytes(b) == TARGET:
                hits.append({"stage": 3, "note": "bytes concat", "order": perm})
                print(f"  ★★★ 命中！ bytes 顺序 {perm}")
            for sep in (b"&", b"", b"|"):
                b2 = sep.join(raw[i] for i in perm)
                tried += 1
                if sha1_bytes(b2) == TARGET:
                    hits.append({"stage": 3, "note": "bytes sep join", "order": perm})
                    print(f"  ★★★ 命中！ bytes 分隔拼接 顺序 {perm}")
        print(f"  累计试了 {tried} 种")
        print()

    print("=" * 70)
    if hits:
        print(f"🎉 爆破成功！{len(hits)} 个解")
        for h in hits[:5]:
            print(f"   {json.dumps(h, ensure_ascii=False)}")
        print()
        print("   → signature 可以自己算，扫码登录整条路打通！")
    else:
        print(f"❌ {tried} 种都没命中")
        print("   signature 里掺了一个我们不知道的 secret")
        print("   （大概率是掌瓦的微信开放平台 AppSecret，服务端才有）")
    print("=" * 70)

    OUT.write_text(json.dumps({"target": TARGET, "tried": tried, "hits": hits},
                              ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n已存 -> {OUT}")
    return 0 if hits else 1


if __name__ == "__main__":
    sys.exit(main())
