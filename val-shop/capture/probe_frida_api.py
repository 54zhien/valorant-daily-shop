#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""探一下当前 frida 版本在目标进程里到底提供了哪些全局对象。

frida 17 把 Java / ObjC bridge 从核心拆出去了，脚本里不能再直接写 Java.use。
这个探针把真实情况打出来，省得靠猜。
"""
from __future__ import annotations

import pathlib
import sys
import time

import frida

PKG = "com.tencent.apps.valorant"

PROBE = r"""
const names = Object.getOwnPropertyNames(globalThis).sort();
send({ kind: 'globals', names: names });

for (const n of ['Java', 'ObjC', 'Swift', 'Module', 'Process', 'Interceptor', 'require']) {
    let info = 'MISSING';
    try {
        const v = globalThis[n];
        if (v !== undefined) {
            info = typeof v;
            if (n === 'require') {
                try { info += ' (frida-java-bridge -> ' + (typeof require('frida-java-bridge')) + ')'; }
                catch (e) { info += ' (frida-java-bridge -> ' + e.message + ')'; }
            }
        }
    } catch (e) {
        info = 'ERR ' + e.message;
    }
    send({ kind: 'global', name: n, info: info });
}
"""

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def main():
    device = frida.get_usb_device(timeout=15)
    print(f"device = {device}")
    print(f"frida  = {frida.__version__}")
    print()
    pid = device.spawn([PKG])
    session = device.attach(pid)
    script = session.create_script(PROBE)
    script.on("message", lambda m, d: handle(m))
    script.load()
    device.resume(pid)
    time.sleep(4)
    try:
        script.unload()
        session.detach()
    except Exception:
        pass
    device.kill(pid)


def handle(message):
    if message.get("type") != "send":
        print("  [non-send]", message)
        return
    p = message["payload"]
    if p.get("kind") == "globals":
        print("全局对象:")
        print("  " + ", ".join(p["names"]))
    elif p.get("kind") == "global":
        print(f"  {p['name']:14s} -> {p['info']}")


if __name__ == "__main__":
    main()
