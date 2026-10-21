#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""检查 CI 产出的未签名 IPA：自签工具能不能正常吃下去。"""
import pathlib
import plistlib
import struct
import sys
import zipfile

ipa = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\Azusa\AppData\Local\Temp\ipa-check\ZhangwaShop-unsigned.ipa")

print(f"IPA: {ipa.name}  {ipa.stat().st_size/1024/1024:.2f} MB")
print()

ok = True


def check(cond, msg_good, msg_bad):
    global ok
    print(f"  {'OK  ' if cond else 'FAIL'} {msg_good if cond else msg_bad}")
    if not cond:
        ok = False


def png_size(data: bytes):
    """取 PNG 尺寸。Xcode 会用 pngcrush 优化，前面多一个 CgBI chunk，
    所以 IHDR 不在固定偏移，得搜一下。"""
    i = data.find(b"IHDR")
    if i < 0 or i + 12 > len(data):
        return None
    return struct.unpack(">II", data[i + 4:i + 12])


with zipfile.ZipFile(ipa) as z:
    names = z.namelist()

    print("[结构]")
    app_dirs = {n.split("/")[1] for n in names
                if n.startswith("Payload/")
                and len(n.split("/")) > 2
                and not n.endswith("/")}
    check(len(app_dirs) == 1, f"Payload/ 下恰好一个 .app: {app_dirs}", f"Payload/ 内容异常: {app_dirs}")
    app = f"Payload/{sorted(app_dirs)[0]}"
    check(app.endswith(".app"), "扩展名是 .app", f"不是 .app: {app}")

    print()
    print("[自签前提]")
    sig = [n for n in names if "_CodeSignature" in n]
    check(not sig, "没有 _CodeSignature 残留", f"有 {len(sig)} 个 _CodeSignature 文件，自签工具可能报校验失败")
    prov = [n for n in names if "embedded.mobileprovision" in n]
    check(not prov, "没有 embedded.mobileprovision", "残留描述文件")

    print()
    print("[Info.plist]")
    info = plistlib.loads(z.read(f"{app}/Info.plist"))
    for k in ["CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion",
              "MinimumOSVersion", "CFBundleDisplayName", "CFBundleName",
              "CFBundleSupportedPlatforms"]:
        print(f"       {k:32s} = {info.get(k)}")

    check("UIDesignRequiresCompatibility" not in info,
          "没有 UIDesignRequiresCompatibility（走新设计 ✓）",
          "有 UIDesignRequiresCompatibility —— 会被 iOS 27 移除，删掉")
    check(info.get("UIFileSharingEnabled") is True, "UIFileSharingEnabled = true（文件 App 可见 ✓）", "UIFileSharingEnabled 缺失")
    check(info.get("LSSupportsOpeningDocumentsInPlace") is True, "LSSupportsOpeningDocumentsInPlace = true", "缺失")
    minos = info.get("MinimumOSVersion", "0")
    check(minos.startswith("26"), f"MinimumOSVersion = {minos}（iOS 26 部署目标 ✓）", f"MinimumOSVersion = {minos}，不是 26")
    ats = info.get("NSAppTransportSecurity", {}).get("NSExceptionDomains", {})
    print(f"       ATS 例外                    = {sorted(ats.keys())}")

    print()
    print("[构建期注入的配置]")
    bc = f"{app}/BundledConfig.plist"
    if bc in names:
        d = plistlib.loads(z.read(bc))
        print(f"       BundledConfig.plist -> {d}")
        check(True, "BundledConfig.plist 已打进 App", "")
    else:
        check(False, "", "BundledConfig.plist 没打进去 —— 检查 project.yml 的 sources")

    print()
    print("[图标 / 资源]")
    # 图标名不再写死 AppIcon：Icon Composer 的 .icon 编出来叫 <IconName>60x60@2x.png，
    # 以 Info.plist 里登记的为准（CFBundleIcons → CFBundleIconFiles）。
    primary = info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon", {})
    icon_files = primary.get("CFBundleIconFiles", [])
    icon_name = primary.get("CFBundleIconName")
    icons = [n for n in names
             if n.endswith(".png") and any(f in pathlib.Path(n).name for f in icon_files)] \
        if icon_files else [n for n in names if "AppIcon" in n and n.endswith(".png")]
    check(len(icons) > 0, f"图标已编译进包（{len(icons)} 个尺寸变体）", "没有图标")
    if icon_name:
        print(f"       CFBundleIconName = {icon_name}（图标来源）")
    if icons:
        biggest = max(icons, key=lambda n: len(z.read(n)))
        data = z.read(biggest)
        size = png_size(data)
        dims = f"{size[0]}x{size[1]}" if size else "?"
        print(f"       最大: {pathlib.Path(biggest).name}  {dims}  {len(data)//1024} KB")
    ac = [n for n in names if "Assets.car" in n]
    check(len(ac) > 0, "Assets.car 存在（图标层 + 品牌色都已编译）", "没有 Assets.car")
    if ac:
        print(f"       Assets.car {len(z.read(ac[0]))//1024} KB")

    print()
    print("[可执行文件]")
    exe_name = info.get("CFBundleExecutable", "ZhangwaShop")
    exe = f"{app}/{exe_name}"
    if exe in names:
        data = z.read(exe)
        magic = struct.unpack("<I", data[:4])[0]
        is_arm64 = magic in (0xFEEDFACF, 0xFEEDFACE, 0xCAFEBABE)
        check(is_arm64, f"{exe_name}  {len(data)/1024/1024:.1f} MB   Mach-O (magic 0x{magic:08X})", "可执行文件格式异常")
        # 架构：arm64 thin 的话 cputype 在 offset 4
        if magic == 0xFEEDFACF:
            cputype = struct.unpack("<I", data[4:8])[0]
            arch = {0x0100000C: "arm64", 0x01000007: "x86_64"}.get(cputype, hex(cputype))
            check(arch == "arm64", f"架构 = {arch}", f"架构 = {arch}，应为 arm64")
    else:
        check(False, "", f"找不到可执行文件 {exe}")

    print()
    print("[Liquid Glass 相关]")
    exe_data = z.read(exe) if exe in names else b""
    for sym in [b"glassEffect", b"GlassEffectContainer", b"tabBarMinimizeBehavior", b"scrollEdgeEffectStyle"]:
        print(f"       {'✓' if sym in exe_data else '·'} {sym.decode()}")

print()
print("RESULT:", "这个 IPA 可以直接丢给自签工具" if ok else "有问题，见上面 FAIL")
sys.exit(0 if ok else 1)
