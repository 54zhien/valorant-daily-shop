#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
爆破 qrconnect signature —— 第三轮，这次手上有 ticket。

## 为什么这轮不一样

前两轮（20 万+ 组合）全失败，是因为**缺了 ticket**：我当时以为它是服务端下发的
一次性凭证，没把它当签名材料。结果栈追踪指明计算点是：

    at com.tencent.mm.opensdk.diffdev.a.a.auth(Native Method)
    at com.tencent.wglogin.authsuite.c$1.a(A:78)
    at com.tencent.wglogin.authsuite.c$1.onSuccess(A:65)      <- get_sdk_ticket 的回调

而 `onSuccess` 的 arg0 就是 `GetWXServerTicketResult`，里面只有 `ticket` 一个字段。
也就是说：**c$1 手里唯一的额外材料就是 ticket，签名必然是它派生出来的。**

现在同一时刻的全套材料都抓到了：

    ticket    = qeuRRdzufZaOpdhfU2Q4gGbgoxq-NLbBLoPmh9nUqydeslyBQFiDXVdbrZRb18EWzY4VZ4OSxxjkW9qnzKAPBw
    appid     = wxcbb49f1f39656c2a
    scope     = snsapi_userinfo
    noncestr  = qFuXLe
    timestamp = 1792324698
    signature = 420740e0ae898dadb8e78f4515f1d39d662a1f0a

注意 ticket 的前缀 `qeuRRdzufZaOpdhfU2Q4gGbgoxq-NLbBLoPmh9nUqy` 是**会话级固定**的，
后半段每次请求都变 —— 典型的「key + nonce」结构，和签名的用法吻合。
"""
from __future__ import annotations

import hashlib
import itertools
import json
import pathlib
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

TICKET = ("qeuRRdzufZaOpdhfU2Q4gGbgoxq-NLbBLoPmh9nUqydeslyBQFiDXVdbrZRb18EWzY4VZ4OS"
          "xxjkW9qnzKAPBw")
APPID = "wxcbb49f1f39656c2a"
SCOPE = "snsapi_userinfo"
NONCE = "qFuXLe"
TS = "1792324698"
TARGET = "420740e0ae898dadb8e78f4515f1d39d662a1f0a"

# ticket 被下划线分成两段，可能是 key + nonce 的结构
TICKET_A, _, TICKET_B = TICKET.partition("_")
TICKET_HEAD = TICKET[:40]
TICKET_TAIL = TICKET[-40:]

OUT = pathlib.Path(__file__).parent / "_dump" / "sig_crack3.json"


def main():
    print(f"target = {TARGET}")
    print(f"ticket len = {len(TICKET)}  (前缀 {TICKET[:32]}…)")
    print()

    # 元素池：每个元素是一个 (标签, 值)
    pools = {
        "appid": APPID,
        "scope": SCOPE,
        "nonce": NONCE,
        "ts": TS,
        "ticket": TICKET,
        "ticketHead": TICKET_HEAD,
        "ticketTail": TICKET_TAIL,
        "ticketA": TICKET_A,
        "ticketB": TICKET_B,
    }

    SEPS = ["", "&", "|", ",", ":", "_", "-", "\n"]
    tried = 0
    hits = []

    def check(s):
        nonlocal tried
        tried += 1
        if hashlib.sha1(s.encode("utf-8")).hexdigest() == TARGET:
            hits.append(s)
            print(f"  ★★★ 命中！ {s!r}")
            return True
        return False

    # ---- 组合 A：ticket 的各种切法 + 4 个公开参数，全排列 --------------------
    print("[A] ticket 切法 × 参数排列 × 分隔符")
    for tname in ("ticket", "ticketHead", "ticketTail", "ticketA", "ticketB"):
        tval = pools[tname]
        for order in itertools.permutations(["appid", "scope", "nonce", "ts"]):
            for tpos in range(5):
                elems = [pools[k] for k in order]
                elems.insert(tpos, tval)
                for sep in SEPS:
                    if check(sep.join(elems)):
                        return report(hits, tried)
                # key=value 形式
                kv = [f"{k}={pools[k]}" for k in order]
                kv.insert(tpos, tval)
                for sep in ["&", "", "|"]:
                    if check(sep.join(kv)):
                        return report(hits, tried)
    print(f"    累计 {tried}")
    print()

    # ---- 组合 B：ticket 当 HMAC 密钥 ---------------------------------------
    print("[B] ticket 当 HMAC 密钥")
    import hmac
    for tname in ("ticket", "ticketA", "ticketB", "ticketHead", "ticketTail"):
        key = pools[tname].encode()
        for order in itertools.permutations(["appid", "scope", "nonce", "ts"]):
            for sep in SEPS:
                msg = sep.join(pools[k] for k in order).encode()
                for algo in ("sha1", "md5", "sha256"):
                    got = hmac.new(key, msg, getattr(hashlib, algo)).hexdigest()
                    tried += 1
                    if got == TARGET:
                        hits.append(f"hmac-{algo}({tname}, {sep.join(order)})")
                        print(f"  ★★★ 命中！ {hits[-1]}")
                        return report(hits, tried)
    print(f"    累计 {tried}")
    print()

    # ---- 组合 C：只有 ticket + 时间戳（微信历史上最常见的两种排法）--------
    print("[C] 常见固定排法")
    candidates = [
        TICKET + NONCE + TS,
        TICKET + TS + NONCE,
        NONCE + TS + TICKET,
        TS + NONCE + TICKET,
        APPID + TICKET + TS,
        TICKET + APPID + TS,
        APPID + NONCE + TS + TICKET,
        APPID + NONCE + TS + SCOPE + TICKET,
        APPID + SCOPE + NONCE + TS + TICKET,
        "appid=%s&noncestr=%s&timestamp=%s&scope=%s&ticket=%s"
            % (APPID, NONCE, TS, SCOPE, TICKET),
        "appid=%s&noncestr=%s&timestamp=%s&scope=%s&key=%s"
            % (APPID, NONCE, TS, SCOPE, TICKET),
    ]
    for c in candidates:
        if check(c):
            return report(hits, tried)
    print(f"    累计 {tried}")
    print()

    return report(hits, tried)


def report(hits, tried):
    print("=" * 72)
    if hits:
        print(f"🎉 爆破成功！{len(hits)} 个解")
        for h in hits[:5]:
            print(f"   {h!r}")
        print("   → signature 能自己算，扫码登录整条路打通")
        OUT.write_text(json.dumps({"target": TARGET, "tried": tried, "hits": hits},
                                  ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"\n已存 -> {OUT}")
        return 0
    print(f"❌ 累计 {tried} 种，全不中")
    print("   → signature 不是 ticket 直接派生，或者还有一层变换没猜中")
    OUT.write_text(json.dumps({"target": TARGET, "tried": tried, "hits": []},
                              ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n已存 -> {OUT}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
