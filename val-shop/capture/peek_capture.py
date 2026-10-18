#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""快速看一眼模拟器上抓了多少东西（不落盘到仓库）。"""
import pathlib
import subprocess
import sys
import tempfile

ADB = r"D:\Program Files\Netease\MuMu\nx_main\adb.exe"
DEV = "127.0.0.1:16384"
LOG = "/data/data/com.tencent.apps.valorant/files/mval_capture.log"
SESSION = "/data/data/com.tencent.apps.valorant/files/mval_session.json"

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def adb(*args, **kw):
    p = subprocess.run([ADB, "-s", DEV, *args], capture_output=True, text=True,
                       encoding="utf-8", errors="replace", **kw)
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def su(cmd):
    return adb("shell", f"su -c '{cmd}'")


def read_remote(path):
    tmp = "/data/local/tmp/.zwpeek"
    rc, out = su(f"cat {path} > {tmp} && chmod 644 {tmp}")
    if rc != 0:
        return None
    local = pathlib.Path(tempfile.gettempdir()) / ".zwpeek"
    adb("pull", tmp, str(local))
    su(f"rm -f {tmp}")
    return local.read_text(encoding="utf-8", errors="replace") if local.exists() else None


def main():
    rc, out = su(f"ls -l {LOG} {SESSION}")
    print("[文件]")
    print("  " + out.strip().replace("\n", "\n  ") or "  (还没有)")
    print()

    log = read_remote(LOG)
    if not log:
        print("日志还不存在 —— 注入还没生效，或者 app 没发请求")
        return

    lines = log.splitlines()
    import json
    reqs, resps, sessions = [], [], []
    for ln in lines:
        if not ln.startswith("{"):
            continue
        try:
            d = json.loads(ln)
        except Exception:
            continue
        if d.get("kind") == "SESSION":
            sessions.append(d)
        elif d.get("dir") == "REQ":
            reqs.append(d)
        elif d.get("dir") == "RESP":
            resps.append(d)

    print(f"[统计] 日志 {len(lines)} 行 / 请求 {len(reqs)} 条 / 响应 {len(resps)} 条 / 会话 {len(sessions)} 条")
    print()

    # 唯一的 URL
    seen = []
    for r in reqs:
        u = r.get("url", "")
        base = u.split("?")[0]
        if base not in seen:
            seen.append(base)
    print(f"[出现过的接口] {len(seen)} 个")
    for u in seen:
        print("  " + u)
    print()

    # cookie 有没有登录态
    best = None
    for r in reqs:
        c = r.get("cookie") or ""
        if "userId=" in c or "tid=" in c:
            best = c
            break
    print("[Cookie]")
    if best:
        print("  已登录！")
        print("  " + best[:400])
    else:
        print("  还没登录（Cookie 里没有 userId / tid）")

    # 响应体读出来了吗
    print()
    print("[响应体抽样]")
    shown = 0
    for r in resps:
        b = r.get("body") or ""
        if b.startswith("<peek failed"):
            print("  " + r.get("url", "")[:70] + "  ->  " + b[:90])
            shown += 1
        elif b.startswith("{") or b.startswith("["):
            print("  OK  " + r.get("url", "")[:70] + "  ->  " + b[:110])
            shown += 1
        if shown >= 5:
            break

    print()
    if sessions:
        print("[会话] 已经拿到完整登录态！")
        s = sessions[-1]
        for k in ("user_id", "uin", "ct", "tid", "openid", "access_token"):
            v = s.get(k)
            print(f"  {k:14s} {'有' if v and v != 'null' else '无'}")


if __name__ == "__main__":
    main()
