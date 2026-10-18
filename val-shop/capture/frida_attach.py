#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
无 REPL 的 frida 注入。

为什么不用 `frida -U -f ...` CLI：
  · frida 17 里没有 --no-pause 了
  · `-f` 默认会把进程挂起等你敲 %resume，而后台任务没有 stdin，REPL 直接退
所以直接走 Python API：spawn -> attach -> load -> resume，然后把进程挂住。

用法：
    python val-shop/capture/frida_attach.py                    # 默认抓包脚本，spawn 模式
    python val-shop/capture/frida_attach.py 300                # 跑 300 秒后自动结束
    python val-shop/capture/frida_attach.py 600 frida_qr_login.js   # 换脚本
    python val-shop/capture/frida_attach.py attach frida_qr_login.js  # ★ 附着到已在跑的进程

为什么要 attach 模式：
    spawn 会**重启** App。一旦 App 因为别的原因（比如 am start / monkey）重启，
    注入就没了 —— 你会看到 hook 明明装好了却什么都抓不到，因为那是上一个进程里的 hook。
    attach 不动现有进程，只往里面插 hook。抓「点某个按钮之后发生的事」必须用 attach。
"""
from __future__ import annotations

import pathlib
import sys
import time

try:
    import frida
except ImportError:
    print("缺 frida，先跑： pip install frida-tools", file=sys.stderr)
    sys.exit(1)

PKG = "com.tencent.apps.valorant"
HERE = pathlib.Path(__file__).parent

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def pick_js(argv: list[str]) -> pathlib.Path:
    """参数里任何一个 .js 都当脚本名"""
    for a in argv[1:]:
        if a.endswith(".js"):
            p = pathlib.Path(a)
            return p if p.exists() else HERE / a
    return HERE / "frida_okhttp_dump.js"


JS = pick_js(sys.argv)
ATTACH = "attach" in sys.argv[1:]

# --pid=NNNN：直接按 PID 附着。
# 为什么必须要这个：掌瓦有进程自保，frida spawn 之后它会立刻重启成新进程，
# 注入的 hook 全丢 —— 表现就是「hook 明明装好了却一个字都抓不到」，
# 而且 frida 的 device.attach(包名) 在 MuMu 上找不到进程（进程名对不上）。
# 只有「查到当前 PID → 按 PID 附着」这一条路稳。
PID = None
for a in sys.argv[1:]:
    if a.startswith("--pid="):
        try:
            PID = int(a.split("=", 1)[1])
        except ValueError:
            pass


def on_message(message, data):
    t = message.get("type")
    if t == "send":
        print(f"[script] {message.get('payload')}", flush=True)
    elif t == "error":
        print(f"[error ] {message.get('description')}", flush=True)
        if message.get("stack"):
            print(message["stack"], flush=True)
    else:
        print(f"[{t}] {message}", flush=True)


def main() -> int:
    # 参数里第一个能转成数字的才是超时秒数（attach / 脚本名都要跳过）
    seconds = None
    for a in sys.argv[1:]:
        try:
            seconds = float(a)
            break
        except ValueError:
            continue

    if not JS.exists():
        print(f"找不到 {JS}", file=sys.stderr)
        return 1

    print("连接设备…", flush=True)
    device = frida.get_usb_device(timeout=15)
    print(f"  device = {device}", flush=True)

    pid = None
    if ATTACH:
        # 附着到已经在跑的进程 —— 不重启 App，hook 不会被 spawn 冲掉
        target = PID if PID is not None else PKG
        try:
            session = device.attach(target)
            print(f"  ✅ attach 到 {target}", flush=True)
        except Exception as e:
            print(f"  attach({target}) 失败：{e}", flush=True)
            if PID is not None:
                print("  PID 附着都失败就没别的办法了（spawn 会被进程自保冲掉）",
                      flush=True)
                return 1
            print("  退回 spawn", flush=True)
            pid = device.spawn([PKG])
            session = device.attach(pid)
    else:
        print(f"启动 {PKG} …", flush=True)
        pid = device.spawn([PKG])
        session = device.attach(pid)

    print(f"  pid = {pid if pid is not None else '（attach 模式）'}", flush=True)

    script = session.create_script(JS.read_text(encoding="utf-8"))
    script.on("message", on_message)
    script.load()
    if pid is not None:
        device.resume(pid)

    print()
    print("=" * 60)
    print(f"  脚本已注入：{JS.name}")
    if ATTACH:
        print("  附着模式 —— App 不会被重启，放心操作。")
    print("=" * 60)
    print(flush=True)

    started = time.time()
    try:
        while True:
            time.sleep(1)
            if seconds and time.time() - started > seconds:
                print(f"\n到 {seconds:.0f} 秒了，自动结束。", flush=True)
                break
    except KeyboardInterrupt:
        print("\n收到 Ctrl-C，结束。", flush=True)
    finally:
        try:
            script.unload()
            session.detach()
        except Exception:
            pass

    return 0


if __name__ == "__main__":
    sys.exit(main())
