#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""工程自检：YAML / plist / 工作流关键字段。不需要网络。"""
import pathlib
import plistlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]

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

import hashlib
import json
import struct

ICONSET = ROOT / "val-shop-ios" / "App" / "Assets.xcassets" / "AppIcon.appiconset"


def png_info(p):
    """读 IHDR：尺寸 / 位深 / 颜色类型。颜色类型 2 = 真彩无 alpha，6 = RGBA。"""
    data = p.read_bytes()
    w, h = struct.unpack(">II", data[16:24])
    depth, ctype = data[24], data[25]
    return w, h, depth, ctype, len(data)


# 图标三件套：App Store 只认方形、**不带 alpha** 的 1024
want = {
    "AppIcon-1024.png": "浅色",
    "AppIcon-1024-dark.png": "深色",
    "AppIcon-1024-tinted.png": "着色",
}
digests = {}
if not ICONSET.exists():
    fail("AppIcon.appiconset 不存在")
else:
    for name, label in want.items():
        p = ICONSET / name
        if not p.exists():
            fail(f"{name} 不存在（{label}）")
            continue
        w, h, depth, ctype, size = png_info(p)
        problem = []
        if (w, h) != (1024, 1024):
            problem.append(f"{w}x{h} ≠ 1024x1024")
        if ctype != 2:
            problem.append(f"颜色类型 {ctype}（2=RGB 无 alpha；带 alpha 的图标上架会被拒）")
        if depth != 8:
            problem.append(f"位深 {depth} ≠ 8")
        digests[name] = hashlib.sha256(p.read_bytes()).hexdigest()
        tag = "OK  " if not problem else "FAIL"
        print(f"  {tag} {name:26s} {w}x{h} depth={depth} type={ctype} {size} B"
              + (f"   ← {'; '.join(problem)}" if problem else ""))
        if problem:
            ok = False

    if len(set(digests.values())) < len(digests):
        fail("三张图标里有内容完全相同的 —— 深色/着色没换图？")
    else:
        print(f"  OK   三张互不相同: " + ", ".join(f"{k.split('-')[-1][:6]}={v[:8]}" for k, v in digests.items()))

    # Contents.json 里登记的必须就是磁盘上这三张，不能少也不能多
    try:
        manifest = json.loads((ICONSET / "Contents.json").read_text(encoding="utf-8"))
        listed = {}
        for img in manifest.get("images", []):
            appearance = (img.get("appearances") or [{}])[0].get("value", "light")
            listed[appearance] = img.get("filename")
        expect = {"light": "AppIcon-1024.png",
                  "dark": "AppIcon-1024-dark.png",
                  "tinted": "AppIcon-1024-tinted.png"}
        if listed == expect:
            print(f"  OK   Contents.json 登记 3 项: {sorted(listed)}")
        else:
            fail(f"Contents.json 登记项对不上：{listed} ≠ {expect}")
        extra = sorted(p.name for p in ICONSET.glob("*.png") if p.name not in expect.values())
        if extra:
            fail(f"appiconset 里有多余的图（不会被用到）: {extra}")
    except Exception as e:
        fail(f"Contents.json 解析失败  {e}")

print()
print("=== 4b) Icon Composer 包（ValPeek.icon） ===")
# iOS 26 的图标 = 分层素材 + 配置，玻璃/底色/投影由系统渲染。
# 所以这里卡两件事：① 层必须是「透明画布 + 形状」，不许把玻璃/投影/底色烤进去；
#               ② icon.json 必须把 fill / glass / translucency / shadow 交代清楚。
BUNDLE = ROOT / "val-shop-ios" / "Icon" / "ValPeek.icon"
if not BUNDLE.exists():
    print("  （没有 .icon 包，跳过）")
else:
    try:
        meta = json.loads((BUNDLE / "icon.json").read_text(encoding="utf-8"))
        groups = meta.get("groups", [])
        layers = [ly for g in groups for ly in g["layers"]]
        names = [ly["name"] for ly in layers]
        print(f"  OK   icon.json 解析通过，{len(groups)} 组 / {len(layers)} 层: {names}")

        if not meta.get("fill", {}).get("solid"):
            fail("icon.json 缺 fill.solid —— 底色要交给系统，不能画在层里")
        else:
            print(f"  OK   fill.solid = {meta['fill']['solid']}")
        if len(groups) != 1:
            fail(f"只该有 1 组（多了系统会分层渲染），实际 {len(groups)}")
        grp = groups[0]
        for key in ("shadow", "translucency"):
            if key in grp:
                print(f"  OK   group.{key} = {grp[key]}")
            else:
                fail(f"group 缺 {key}")
        glass = [ly["name"] for ly in layers if ly.get("glass")]
        print(f"  OK   glass 层: {glass or '（无，全是实色层）'}")

        referenced = {ly["image-name"] for ly in layers}
        assets = BUNDLE / "Assets"
        on_disk = {p.name for p in assets.iterdir() if p.is_file()} if assets.exists() else set()
        missing, orphan = referenced - on_disk, on_disk - referenced
        if missing:
            fail(f"icon.json 引用了不存在的层: {sorted(missing)}")
        else:
            print(f"  OK   {len(referenced)} 个层文件都在 Assets/ 里")
        if orphan:
            fail(f"Assets/ 里有没人引用的文件: {sorted(orphan)}")

        # 层里不该出现：整块画布底色、渐变、滤镜/投影（这些是系统干的活）
        banned = {
            "整块画布底色": f'width="{1024}" height="1024" fill="#'.encode(),
            "渐变": b"Gradient",
            "滤镜/投影": b"<filter",
            "模糊": b"feGaussianBlur",
        }
        for f in sorted(assets.glob("*.svg")):
            raw = f.read_bytes()
            hits = [label for label, needle in banned.items() if needle in raw]
            if hits:
                fail(f"{f.name} 里烤进了 {'/'.join(hits)} —— 层只该是透明画布 + 形状")
            else:
                print(f"  OK   {f.name} 是纯 alpha 层（{len(raw)} B，无底色/渐变/滤镜）")
    except Exception as e:
        fail(f"icon.json 解析失败  {e}")

print()
print("=== 4c) 图标管线 ===")
for rel, why in [("val-shop-ios/Icon/gen.mjs", "几何 → alpha 层 SVG + icon.json"),
                 ("val-shop-ios/Icon/render.mjs", "SVG → 1024 PNG（Chrome headless）"),
                 ("val-shop-ios/Icon/finalize.py", "压平 RGB + 装库 + 两张对照表"),
                 ("val-shop-ios/Icon/preview/contact-sheet.png", "终稿：三外观 × 四尺寸"),
                 ("val-shop-ios/Icon/preview/concepts.png", "候选方案对比（挑样式用）")]:
    p = ROOT / rel
    print(f"  {'OK  ' if p.exists() else 'MISS'} {rel}   ({why})")
    if not p.exists():
        ok = False

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
print("=== 6) Swift 语法体检 ===")
# 本机是 Windows，编译不了 SwiftUI（没有 Apple SDK），但 `-parse` 只查语法、
# 不需要模块，能把「括号不配对 / 引号被 shell 吃掉 / 少了逗号」这类错误挡在推之前。
import shutil
import subprocess

swiftc = shutil.which("swiftc")
app_dir = ROOT / "val-shop-ios" / "App"
sources = sorted(p.name for p in app_dir.glob("*.swift"))

if not swiftc:
    print("  跳过：本机没有 swiftc")
elif not sources:
    fail("App/ 下没有 .swift 文件")
else:
    r = subprocess.run([swiftc, "-parse"] + sources,
                       cwd=str(app_dir), capture_output=True, text=True)
    if r.returncode == 0:
        print(f"  OK   {len(sources)} 个文件 swiftc -parse 通过")
    else:
        fail("swiftc -parse 报错：")
        print((r.stderr or r.stdout)[:2000])

print()
print("=== 7) 设计系统一致性 ===")
# 视觉事实来源是 design/preview.html；这边只做最低限度的存在性检查，
# 免得改了 HTML 忘了它。
for rel, why in [("val-shop-ios/design/preview.html", "设计预览台（视觉事实来源）"),
                 ("val-shop-ios/design/shoot.ps1", "预览台截图脚本"),
                 ("val-shop-ios/App/DesignSystem.swift", "SwiftUI 侧 token 层"),
                 ("val-shop-ios/probe/isolation_probe.swift", "并发隔离实验台"),
    ("val-shop-ios/probe/animatable_probe.swift", "Animatable 隔离实验台"),
    ("val-shop-ios/probe/ring_probe.swift", "轮廓采样几何实验台")]:
    p = ROOT / rel
    print(f"  {'OK  ' if p.exists() else 'MISS'} {rel}   ({why})")
    if not p.exists():
        ok = False

print()
print("RESULT:", "全部通过" if ok else "有失败项")
sys.exit(0 if ok else 1)
