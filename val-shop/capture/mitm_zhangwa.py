#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
掌瓦 mitmproxy 抓包插件
=======================

目的：抓出「每日商店」的真实接口路径 / 参数 / Cookie（备选方案，Frida 优先）。

用法：
    # 1) 启动（监听 8080，并写一份 jsonl 到 ./mval-*.jsonl）
    mitmdump -s mitm_zhangwa.py -p 8080 --set outdir=.

    # 2) 手机 WiFi 代理指向本机:8080，装 mitmproxy CA 到「系统证书」
    #    （Android 7+ 需要 root 把 CA 放到 /system/etc/security/cacerts 或用 Magisk 模块）
    #    App 内若有证书固定（TL S / okhttp CertificatePinner），用 frida 脚本
    #    capture/frida_okhttp_dump.js 或 frida-unpinning 先解掉。

    # 3) 在 App 里打开「每日商店」

产出：
    ./mval-<时间戳>.jsonl   每条一行：请求 + 响应
    终端里高亮打印 /go/ 接口，并把 Cookie 头单独拆出来
"""

import json
import os
import re
import time
from datetime import datetime

from mitmproxy import ctx, http

TARGET_HOSTS = ("app.mval.qq.com", "apptest.mval.qq.com", "mlol.qt.qq.com", "val.qq.com")
INTEREST = re.compile(r"/go/|store|shop|commodity|goods|daily", re.I)

# 想全部抓就把这个改成 False
ONLY_INTEREST = True

_started = time.time()
_file = None
_count = 0


def _out_path(outdir: str) -> str:
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    return os.path.join(outdir, f"mval-{ts}.jsonl")


def load(loader):
    ctx.log.info("[zhangwa] plugin loaded, waiting for traffic ...")


def running():
    global _file
    outdir = ctx.options.outdir if hasattr(ctx.options, "outdir") else "."
    try:
        _file = open(_out_path(outdir), "a", encoding="utf-8")
    except Exception as exc:  # noqa: BLE001
        ctx.log.warn(f"[zhangwa] cannot open output file: {exc}")


def done():
    if _file:
        _file.flush()
        _file.close()


def _wanted(flow: http.HTTPFlow) -> bool:
    host = flow.request.pretty_host
    if not any(host.endswith(h) for h in TARGET_HOSTS):
        return False
    if not ONLY_INTEREST:
        return True
    return bool(INTEREST.search(flow.request.path))


def _cookies(flow: http.HTTPFlow) -> dict:
    try:
        return dict(flow.request.cookies)
    except Exception:  # noqa: BLE001
        raw = flow.request.headers.get("cookie", "")
        out = {}
        for part in raw.split(";"):
            if "=" in part:
                k, v = part.split("=", 1)
                out[k.strip()] = v.strip()
        return out


def request(flow: http.HTTPFlow) -> None:
    if not _wanted(flow):
        return
    ctx.log.alert(f"→ {flow.request.method} {flow.request.pretty_url}")

    body = None
    try:
        if flow.request.content:
            body = flow.request.get_text(strict=False)
    except Exception:  # noqa: BLE001
        body = "<binary>"

    rec = {
        "t": datetime.now().isoformat(),
        "dir": "REQ",
        "method": flow.request.method,
        "url": flow.request.pretty_url,
        "headers": dict(flow.request.headers),
        "cookies": _cookies(flow),
        "body": body,
    }
    _dump(rec)

    ck = _cookies(flow)
    if ck:
        ctx.log.info("   Cookie: " + "; ".join(f"{k}={v}" for k, v in ck.items()))


def response(flow: http.HTTPFlow) -> None:
    if not _wanted(flow):
        return

    text = None
    try:
        text = flow.response.get_text(strict=False)
    except Exception:  # noqa: BLE001
        text = "<binary>"

    rec = {
        "t": datetime.now().isoformat(),
        "dir": "RESP",
        "method": flow.request.method,
        "url": flow.request.pretty_url,
        "code": flow.response.status_code,
        "body": text,
    }
    _dump(rec)

    # 顺手把 result 字段提出来，方便一眼看出票据是否过期
    if text and text.lstrip().startswith("{"):
        try:
            j = json.loads(text)
            r = j.get("result")
            if r == 999999:
                ctx.log.warn("   !! result=999999  wt 票据异常，需要刷新票据")
            elif r not in (0, None):
                ctx.log.warn(f"   result={r} msg={j.get('msg')}")
        except Exception:  # noqa: BLE001
            pass


def _dump(rec: dict) -> None:
    global _count
    _count += 1
    line = json.dumps(rec, ensure_ascii=False)
    if _file:
        _file.write(line + "\n")
        _file.flush()
