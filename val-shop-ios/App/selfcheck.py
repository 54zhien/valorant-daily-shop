#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""工程自检：YAML / plist / 工作流关键字段。不需要网络。"""
import pathlib
import plistlib
import sys

ROOT = pathlib.Path(r"D:\DSHDev\Reverse\Valorant App")

try:
    import yaml
except ImportError:
    import subprocess
    subprocess.run([sys.executable, "-m", "pip", "install", "-q", "pyyaml"], check=True)
    import yaml

ok = True


def fail(msg):
    global ok
    ok = False
    print(f"  FAIL {msg}")


print("=== 1) YAML ===")
for rel in [".github/workflows/ios.yml", "val-shop-ios/project.yml"]:
    p = ROOT / rel
    if not p.exists():
        fail(f"{rel} 不存在")
        continue
    try:
        doc = yaml.safe_load(p.read_text(encoding="utf-8"))
        # PyYAML 按 YAML 1.1 把裸 `on:` 解析成布尔 True；GitHub Actions 用 YAML 1.2，这里是字符串键。
        # 纯显示问题，顺手规范化一下免得看着吓人。
        keys = [("on" if k is True else k) for k in doc.keys()]
        print(f"  OK   {rel}   顶层键: {keys}")
    except Exception as e:
        fail(f"{rel}  {e}")

print()
print("=== 2) 工作流结构 ===")
wf = yaml.safe_load((ROOT / ".github/workflows/ios.yml").read_text(encoding="utf-8"))
for name, job in wf.get("jobs", {}).items():
    steps = job.get("steps", [])
    print(f"  job {name!r}: runs-on={job.get('runs-on')} needs={job.get('needs')} steps={len(steps)}")
    for s in steps:
        label = s.get("name") or s.get("uses")
        print(f"        - {label}")

# 关键断言
wf_text = (ROOT / ".github/workflows/ios.yml").read_text(encoding="utf-8")
for needle, why in [
    ("CODE_SIGNING_ALLOWED=NO", "未签名构建必须关掉签名"),
    ("_CodeSignature", "要清掉残留签名，否则自签工具可能报错"),
    ("embedded.mobileprovision", "要清掉描述文件"),
    ("zip -qry", "IPA 必须是 Payload/ 根的 zip"),
    ("upload-artifact", "要能把 IPA 拿出来"),
]:
    if needle in wf_text:
        print(f"  OK   {needle:26s} ({why})")
    else:
        fail(f"缺少 {needle} —— {why}")

print()
print("=== 3) plist ===")
for rel in ["Info.plist", "BundledConfig.plist"]:
    p = ROOT / "val-shop-ios" / "App" / rel
    try:
        d = plistlib.loads(p.read_bytes())
    except Exception as e:
        fail(f"{rel}  {e}")
        continue
    print(f"  OK   {rel}   keys={len(d)}")
    if rel == "Info.plist":
        for k, want in [("UIFileSharingEnabled", True),
                        ("LSSupportsOpeningDocumentsInPlace", True)]:
            got = d.get(k)
            print(f"         {k} = {got}   {'OK' if got is True else '✗ 应为 true'}")
            if got is not True:
                ok = False
        if "UIDesignRequiresCompatibility" in d:
            fail("Info.plist 里有 UIDesignRequiresCompatibility，iOS 27 会移除它，删掉")
        else:
            print("         UIDesignRequiresCompatibility: 无 ✓")
        ats = d.get("NSAppTransportSecurity", {}).get("NSExceptionDomains", {})
        print(f"         ATS 例外域名: {sorted(ats.keys())}")
    else:
        print(f"         {d}")

print()
print("=== 4) Assets ===")
for rel in ["Contents.json",
            "AppIcon.appiconset/Contents.json",
            "AccentColor.colorset/Contents.json"]:
    p = ROOT / "val-shop-ios" / "App" / "Assets.xcassets" / rel
    try:
        import json
        json.loads(p.read_text(encoding="utf-8"))
        print(f"  OK   Assets.xcassets/{rel}")
    except Exception as e:
        fail(f"Assets.xcassets/{rel}  {e}")

icon = ROOT / "val-shop-ios" / "App" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-1024.png"
if icon.exists():
    import struct
    data = icon.read_bytes()
    w, h = struct.unpack(">II", data[16:24])
    print(f"  OK   AppIcon-1024.png  {w}x{h}  {len(data)} bytes   {'✓' if (w, h) == (1024, 1024) else '✗ 必须是 1024x1024'}")
    if (w, h) != (1024, 1024):
        ok = False
else:
    fail("AppIcon-1024.png 不存在")

print()
print("=== 5) 自签 IPA 交付物清单 ===")
for rel in [".github/workflows/ios.yml",
            "val-shop-ios/project.yml",
            "val-shop-ios/App/BundledConfig.plist",
            ".gitignore",
            "val-shop-ios/.gitignore"]:
    p = ROOT / rel
    print(f"  {'OK  ' if p.exists() else 'MISS'} {rel}")

print()
print("RESULT:", "全部通过" if ok else "有失败项")
sys.exit(0 if ok else 1)
