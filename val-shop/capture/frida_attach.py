#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
无 REPL 的 frida 注入。

为什么不用 `frida -U -f ...` CLI：
  · frida 17 里没有 --no-pause 了
  · `-f` 默认会把进程挂起等你敲 %resume，而后台任务没有 stdin，REPL 直接退
所以直接走 Python API：spawn -> attach -> load -> resume，然后把进程挂住。

用法：
    python val-shop/capture/frida_attach.py          # 一直跑，Ctrl-C 结束
    python val-shop/capture/frida_attach.py 300      # 跑 300 秒后自动结束
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
JS = pathlib.Path(__file__).with_name("frida_okhttp_dump.js")

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


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
    seconds = float(sys.argv[1]) if len(sys.argv) > 1 else None

    if not JS.exists():
        print(f"找不到 {JS}", file=sys.stderr)
        return 1

    print("连接设备…", flush=True)
    device = frida.get_usb_device(timeout=15)
    print(f"  device = {device}", flush=True)

    print(f"启动 {PKG} …", flush=True)
    pid = device.spawn([PKG])
    print(f"  pid = {pid}", flush=True)

    session = device.attach(pid)
    script = session.create_script(JS.read_text(encoding="utf-8"))
    script.on("message", on_message)
    script.load()
    device.resume(pid)

    print()
    print("=" * 60)
    print("  注入已生效，脚本在跑了。")
    print("  现在去模拟器里：登录 -> 点开「每日商店」")
    print("  完成后 Ctrl-C 结束（或等自动超时）")
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
