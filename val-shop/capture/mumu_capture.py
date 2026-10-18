#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MuMu 模拟器一键抓包 —— 拿到 mval_session.json + mval_capture.log

用法（在仓库根目录或任意位置跑都行）：

    python val-shop/capture/mumu_capture.py check      # 只体检，不动任何东西
    python val-shop/capture/mumu_capture.py setup      # 起模拟器 + adb + 推 frida-server + 装 app
    python val-shop/capture/mumu_capture.py run        # 注入 frida 脚本（这一步要你手动操作）
    python val-shop/capture/mumu_capture.py pull       # 把两个产物拉回本地
    python val-shop/capture/mumu_capture.py all        # setup -> run -> pull 一条龙

为什么必须抓这一次：openid 是按 AppID 维度生成的，掌瓦服务端认的是它自己 AppID
下的那个 openid。用自己的 AppID 登录拿到的 openid 对不上，服务端认不出你是谁。
详见 val-shop/analysis/掌瓦数据链路分析.md §2.2。
"""
from __future__ import annotations

import argparse
import json
import lzma
import os
import pathlib
import shutil
import subprocess
import sys
import sysconfig
import time
import urllib.request

# ---------------------------------------------------------------- 基本配置

PKG = "com.tencent.apps.valorant"
CAPTURE_JS = pathlib.Path(__file__).with_name("frida_okhttp_dump.js")
REMOTE_DIR = "/data/local/tmp"
REMOTE_SERVER = f"{REMOTE_DIR}/frida-server"

# ⚠️ 产物不在 /data/local/tmp。
# frida 脚本跑在 app 进程里（uid u0_a47），而 /data/local/tmp 是 drwxrwx--x shell shell，
# app 只有执行位没有写位，写进去会 EACCES。所以落在 app 自己的 files 目录，
# 拉的时候先 su cp 到 /data/local/tmp 再 adb pull。
APP_FILES = f"/data/data/{PKG}/files"
OUT_SESSION = f"{APP_FILES}/mval_session.json"
OUT_LOG = f"{APP_FILES}/mval_capture.log"

MUMU_CANDIDATES = [
    pathlib.Path(r"D:\Program Files\Netease\MuMu"),
    pathlib.Path(r"C:\Program Files\Netease\MuMuPlayer-12.0"),
    pathlib.Path(r"C:\Program Files\Netease\MuMu"),
    pathlib.Path(r"D:\MuMuPlayer-12.0"),
]

ADB_CANDIDATES = [
    pathlib.Path(r"D:\Program Files\Netease\MuMu\nx_main\adb.exe"),
    pathlib.Path(r"C:\Program Files\Netease\MuMu\nx_main\adb.exe"),
    pathlib.Path(os.path.expandvars(r"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe")),
]

# MuMu 12 的 adb 端口按实例号推：16384 + index*32
ADB_PORTS = [16384, 16416, 16448]

APK_CANDIDATES = [
    pathlib.Path("com.tencent.apps.valorant.apk"),
    pathlib.Path("work/com.tencent.apps.valorant.apk"),
]

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def say(msg: str = "") -> None:
    print(msg, flush=True)


def head(msg: str) -> None:
    say()
    say("=" * 68)
    say(f"  {msg}")
    say("=" * 68)


# ---------------------------------------------------------------- 工具

def run(cmd, **kw):
    """跑一条命令，返回 (returncode, stdout+stderr)。"""
    kw.setdefault("capture_output", True)
    kw.setdefault("text", True)
    kw.setdefault("encoding", "utf-8")
    kw.setdefault("errors", "replace")
    try:
        p = subprocess.run(cmd, **kw)
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except FileNotFoundError:
        return 127, f"找不到可执行文件: {cmd[0]}"


def frida_cli() -> str | None:
    """frida 控制台脚本的位置。别用 `python -m frida`——frida 包不能这么执行。"""
    exe = "frida.exe" if os.name == "nt" else "frida"
    cand = pathlib.Path(sysconfig.get_path("scripts")) / exe
    if cand.exists():
        return str(cand)
    return shutil.which("frida")


def frida_version() -> str | None:
    """核心库版本。frida-server 必须和它一致。"""
    rc, out = run([sys.executable, "-c", "import frida;print(frida.__version__)"])
    if rc == 0 and out.strip():
        return out.strip().splitlines()[-1].strip()
    cli = frida_cli()
    if cli:
        rc, out = run([cli, "--version"])
        if rc == 0:
            return out.strip().splitlines()[-1].strip()
    return None


def sh(adb: str, device: str, cmd: str, **kw):
    """在设备上跑一条 shell 命令。"""
    return run([adb, "-s", device, "shell", cmd], **kw)


def su(adb: str, device: str, cmd: str, **kw):
    """
    以 root 跑一条命令。

    ⚠️ 必须把 `su -c '<cmd>'` 拼成**一个**参数交给 adb。
    如果拆成 ["su", "-c", cmd]，adb 会用空格把它们重新拼起来，
    远端 sh 就会把 cmd 里的空格当成参数分隔 —— 变成
    `su -c chmod 755 /data/local/tmp/frida-server`，
    su 只收到 "chmod"，后面全被丢掉，命令静默失败。
    """
    return run([adb, "-s", device, "shell", f"su -c '{cmd}'"], **kw)


def find_mumu() -> pathlib.Path | None:
    for p in MUMU_CANDIDATES:
        if (p / "nx_main" / "MuMuManager.exe").exists():
            return p
    return None


def find_adb() -> str | None:
    for p in ADB_CANDIDATES:
        if p.exists():
            return str(p)
    w = shutil.which("adb")
    if w:
        return w
    # 兜底：扫一遍常见安装目录
    for root in ("C:\\Program Files", "C:\\Program Files (x86)", "D:\\", "E:\\"):
        if not os.path.isdir(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            if dirpath.count(os.sep) > 6:
                dirnames[:] = []
                continue
            if "MuMuManager.exe" in filenames and "adb.exe" in filenames:
                return os.path.join(dirpath, "adb.exe")
    return None


# ---------------------------------------------------------------- 单步

def step_check() -> int:
    head("环境体检")

    say("[MuMu]")
    mumu = find_mumu()
    if mumu:
        say(f"  OK   {mumu}")
    else:
        say("  FAIL 找不到 MuMu，改一下脚本顶部的 MUMU_CANDIDATES")

    say()
    say("[adb]")
    adb = find_adb()
    if adb:
        say(f"  OK   {adb}")
    else:
        say("  FAIL 找不到 adb.exe")

    say()
    say("[frida 工具链（PC 端）]")
    ver = frida_version()
    cli = frida_cli()
    if ver:
        say(f"  OK   frida {ver}   ← frida-server 必须同版本")
    else:
        say("  未安装 —— setup 会自动 pip install frida-tools")
    if cli:
        say(f"  OK   CLI: {cli}")
    else:
        say("  找不到 frida 控制台脚本（pip 装的 Scripts 目录不在 PATH）")

    say()
    say("[抓包脚本]")
    if CAPTURE_JS.exists():
        say(f"  OK   {CAPTURE_JS}  ({CAPTURE_JS.stat().st_size} 字节)")
    else:
        say(f"  FAIL 缺 {CAPTURE_JS}")

    say()
    say("[样本 APK]")
    apk = next((p for p in APK_CANDIDATES if p.exists()), None)
    if apk:
        say(f"  OK   {apk.resolve()}  ({apk.stat().st_size/1024/1024:.0f} MB)")
    else:
        say("  没找到（如果模拟器里已经装过掌瓦，可以忽略）")

    say()
    say("[模拟器实例]")
    if mumu:
        rc, out = run([str(mumu / "nx_main" / "MuMuManager.exe"), "info", "-v", "all"])
        try:
            for inst in _parse_instances(out):
                state = "运行中" if inst.get("is_android_started") else "未启动"
                say(f"  #{inst.get('index')}  {inst.get('name')}  [{state}]")
        except Exception:
            say(f"  {out.strip()[:300]}")

    return 0 if (mumu and adb and CAPTURE_JS.exists()) else 1


def _parse_instances(text: str):
    """MuMuManager 会输出一个或多个 JSON 对象（不是数组）。"""
    text = text.strip()
    if not text:
        return []
    # 尝试整体解析
    try:
        d = json.loads(text)
        return d if isinstance(d, list) else [d]
    except json.JSONDecodeError:
        pass
    # 逐个 { ... } 抠
    out, depth, start = [], 0, None
    for i, ch in enumerate(text):
        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start is not None:
                try:
                    out.append(json.loads(text[start:i + 1]))
                except json.JSONDecodeError:
                    pass
    return out


def step_setup() -> int:
    head("① 启动模拟器 + adb + frida-server")

    mumu = find_mumu()
    adb = find_adb()
    if not mumu or not adb:
        say("先跑 check 看看缺什么")
        return 1

    mgr = str(mumu / "nx_main" / "MuMuManager.exe")

    say("[1/6] 启动模拟器实例 0")
    rc, out = run([mgr, "info", "-v", "0"])
    started = '"is_android_started": true' in out.replace(" ", "").lower() or \
              '"is_android_started":true' in out.replace(" ", "").lower()
    if not started:
        say("      实例没在跑，尝试拉起…")
        for args in (["api", "-v", "0", "launch_player"], ["control", "-v", "0", "launch"]):
            run([mgr] + args)
            time.sleep(5)
            rc, out = run([mgr, "info", "-v", "0"])
            if '"is_android_started": true' in out:
                break
        else:
            say("      自动拉起没成功 —— 手动打开 MuMu 也行，脚本会等。")
    else:
        say("      已经在跑")

    say("[2/6] 等 adb 连上")
    device = None
    for attempt in range(60):
        for port in ADB_PORTS:
            run([adb, "connect", f"127.0.0.1:{port}"])
        rc, out = run([adb, "devices"])
        for line in out.splitlines():
            if "\tdevice" in line:
                device = line.split("\t")[0].strip()
                break
        if device:
            say(f"      连上了: {device}")
            break
        time.sleep(3)
    if not device:
        say("      连不上。检查 MuMu 是否真的启动到桌面了。")
        return 1

    say("[3/6] 检查 root 和架构")
    rc, out = su(adb, device, "id")
    if "uid=0" not in out:
        say("      没有 root。到 MuMu 设置 → 其他 → ROOT权限 → 开启，然后重启实例。")
        say(f"      (su -c id 返回: {out.strip()[:120]})")
        return 1
    say("      root OK")

    rc, out = run([adb, "-s", device, "shell", "getprop", "ro.product.cpu.abi"])
    abi = out.strip()
    say(f"      ABI = {abi}")
    arch = {"x86_64": "x86_64", "arm64-v8a": "arm64", "armeabi-v7a": "arm"}.get(abi)
    if not arch:
        say(f"      认不出 {abi}，默认按 x86_64 走")
        arch = "x86_64"

    say("[4/6] 准备 frida-server")
    ver = frida_version()
    if not ver:
        say("      装 frida-tools…")
        rc, out = run([sys.executable, "-m", "pip", "install", "-q", "-U", "frida-tools"],
                      timeout=600)
        ver = frida_version()
    if not ver:
        say("      装不上，手动执行： pip install frida-tools")
        return 1
    frida_ver = ver
    say(f"      frida {frida_ver}")

    # frida 17 把 Java bridge 从运行时里拆出去了 —— 脚本里写 Java.use 会
    # ReferenceError: 'Java' is not defined，而且连 require 都没有，
    # 没法自己加载 frida-java-bridge。所以抓 Android 必须用 16.x。
    major = int(frida_ver.split(".")[0])
    if major >= 17:
        say()
        say(f"      ⚠️ frida {frida_ver} 的 Java bridge 已从运行时移除，脚本会报")
        say("         ReferenceError: 'Java' is not defined（而且没有 require 可用）。")
        say("         降到 16.x：")
        say('             pip install "frida==16.7.19" "frida-tools<14"')
        say("         然后重跑 setup。")
        return 1

    local_xz = pathlib.Path(__file__).with_name(f"frida-server-{frida_ver}-android-{arch}.xz")
    local_bin = local_xz.with_suffix("")
    if not local_bin.exists():
        if not local_xz.exists():
            url = (f"https://github.com/frida/frida/releases/download/"
                   f"{frida_ver}/frida-server-{frida_ver}-android-{arch}.xz")
            say(f"      下载 {url}")
            try:
                urllib.request.urlretrieve(url, local_xz)
            except Exception as e:
                say(f"      下载失败: {e}")
                say("      GitHub 在国内可能不通，手动下这个文件放到同目录也行：")
                say(f"        {url}")
                return 1
        say("      解压…")
        with lzma.open(local_xz, "rb") as f, open(local_bin, "wb") as o:
            shutil.copyfileobj(f, o)
    say(f"      本地: {local_bin}  ({local_bin.stat().st_size/1024/1024:.1f} MB)")

    say("[5/6] 推到模拟器并启动")
    su(adb, device, "pkill -f frida-server")
    rc, out = run([adb, "-s", device, "push", str(local_bin), REMOTE_SERVER])
    if rc != 0:
        say(f"      push 失败: {out.strip()[:200]}")
        return 1
    su(adb, device, f"chmod 755 {REMOTE_SERVER}")

    # 先确认真的能执行（chmod 失败过的话这里会立刻暴露，而不是等到 frida 连不上）
    rc, out = su(adb, device, f"{REMOTE_SERVER} --version")
    if rc != 0 or not out.strip():
        say(f"      frida-server 起不来: {out.strip()[:160]}")
        return 1
    say(f"      frida-server {out.strip().splitlines()[-1]}")

    su(adb, device, f"nohup {REMOTE_SERVER} >{REMOTE_DIR}/frida.log 2>&1 &")
    time.sleep(3)
    rc, out = su(adb, device, "ps -A | grep frida-server")
    if "frida-server" in out:
        say("      已在后台运行")
    else:
        rc, log = su(adb, device, f"cat {REMOTE_DIR}/frida.log")
        say(f"      没起来。日志: {log.strip()[:200]}")
        return 1

    say("[6/6] 检查掌瓦是否已安装")
    rc, out = run([adb, "-s", device, "shell", "pm", "list", "packages", PKG])
    if PKG in out:
        say(f"      已安装 {PKG}")
    else:
        apk = next((p for p in APK_CANDIDATES if p.exists()), None)
        if not apk:
            say(f"      没装，也没找到 APK 文件。手动装一下 {PKG}")
        else:
            say(f"      安装 {apk} （可能要一分钟）")
            rc, out = run([adb, "-s", device, "install", "-r", str(apk)], timeout=600)
            say(f"      {out.strip()[:200]}")

    say()
    say("✅ setup 完成。下一步：")
    say("     python val-shop/capture/mumu_capture.py run")
    _write_state(device, adb)
    return 0


def _write_state(device: str, adb: str) -> None:
    state = pathlib.Path(__file__).with_name(".capture_state.json")
    state.write_text(json.dumps({"device": device, "adb": adb}), encoding="utf-8")


def _read_state():
    state = pathlib.Path(__file__).with_name(".capture_state.json")
    if not state.exists():
        return None, None
    d = json.loads(state.read_text(encoding="utf-8"))
    return d.get("device"), d.get("adb")


def step_run() -> int:
    head("② 注入 frida 脚本（这一步要你动手）")

    device, adb = _read_state()
    if not adb:
        adb = find_adb()
        device = "127.0.0.1:16384"

    # 清掉上次的产物，免得把新旧数据混在一起
    su(adb, device, f"rm -f {OUT_SESSION} {OUT_LOG}")

    say("接下来会启动掌瓦，然后：")
    say("  1. 在模拟器里用你的 QQ 或微信登录")
    say("  2. 点开一次「每日商店」页面")
    say("  3. 回到这个终端按 Ctrl-C 结束")
    say()
    say(f"要拿到的东西会写在模拟器的 {OUT_SESSION} 和 {OUT_LOG}")
    say()
    input("准备好了按回车开始…")

    cli = frida_cli() or "frida"
    cmd = [cli, "-U", "-f", PKG, "-l", str(CAPTURE_JS), "--no-pause"]
    say()
    say("$ " + " ".join(cmd))
    say("（Ctrl-C 结束注入）")
    say()
    try:
        subprocess.run(cmd)
    except KeyboardInterrupt:
        pass

    say()
    say("注入结束。下一步：")
    say("     python val-shop/capture/mumu_capture.py pull")
    return 0


def step_pull() -> int:
    head("③ 拉回产物")

    device, adb = _read_state()
    if not adb:
        adb = find_adb()
        device = "127.0.0.1:16384"

    outdir = pathlib.Path.cwd()
    got = 0

    # app 的私有目录只有它自己和 root 能读，先 su 拷到 /data/local/tmp 放开权限
    staged = []
    for remote in (OUT_SESSION, OUT_LOG):
        name = os.path.basename(remote)
        rc, out = su(adb, device, f"cat {remote} > {REMOTE_DIR}/{name} && chmod 644 {REMOTE_DIR}/{name}")
        if rc == 0:
            staged.append((f"{REMOTE_DIR}/{name}", name))
        else:
            say(f"  MISS {name}  —— {out.strip()[:150]}")
            say("       （还没登录 / 还没点开商店的话，产物就不存在）")

    for remote, name in staged:
        local = outdir / name
        rc, out = run([adb, "-s", device, "pull", remote, str(local)])
        if rc == 0 and local.exists():
            say(f"  OK   {local}  ({local.stat().st_size} 字节)")
            got += 1
        else:
            say(f"  FAIL {name}  —— {out.strip()[:150]}")

    if got == 0:
        say()
        say("什么都没拉到。多半是 frida 注入没成功，或者没登录/没点开商店。")
        return 1

    # 顺手校验 session 文件是不是真的能用
    sess = outdir / "mval_session.json"
    if sess.exists():
        say()
        try:
            d = json.loads(sess.read_text(encoding="utf-8"))
            if isinstance(d, list):
                d = next((x for x in d if x.get("kind") == "SESSION"), d[0] if d else {})
            say("  [session 内容检查]")
            for k in ("user_id", "uin", "ct", "tid", "openid", "access_token"):
                v = d.get(k)
                state = "有" if v else "无"
                if k == "ct":
                    state += "  ← 有它才能自动续票" if v else "  ← 没有的话 tid 过期就得重抓"
                say(f"    {k:14s} {state}")
        except Exception as e:
            say(f"  session 解析失败: {e}")

    say()
    say("下一步：把这两个文件传到 iPhone")
    say("  · AirDrop 到手机 → 在「文件」里移到「我的 iPhone → 每日商店」")
    say("  · App → 设置 → 「扫描 App 文件夹」")
    return 0


# ---------------------------------------------------------------- main

def main() -> int:
    p = argparse.ArgumentParser(description="MuMu 模拟器一键抓包")
    p.add_argument("action", choices=["check", "setup", "run", "pull", "all"])
    a = p.parse_args()

    if a.action == "check":
        return step_check()
    if a.action == "setup":
        return step_setup()
    if a.action == "run":
        return step_run()
    if a.action == "pull":
        return step_pull()
    if a.action == "all":
        rc = step_setup()
        if rc != 0:
            return rc
        rc = step_run()
        if rc != 0:
            return rc
        return step_pull()
    return 2


if __name__ == "__main__":
    sys.exit(main())
