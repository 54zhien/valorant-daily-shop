#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
扫一遍 Swift 源码，找出「被 shell 吃掉引号/美元符」的痕迹

## 为什么需要这个

这次踩了个坑：用 PowerShell 里的 python -c "..." heredoc 改 Swift 代码，
结果 `$showRolePicker` 的 `$` 和 `"chevron.up.chevron.down"` 的引号被
shell 先一步吃掉了，写进文件变成：

    .sheet(isPresented: ) {                       // $ 没了
    Image(systemName: chevron.up.chevron.down)    // 引号没了

本地 `swiftc -parse` 只查语法不查类型（`chevron.up.chevron.down` 那行
语法上"看起来"是成员访问），所以本地过了、CI 才炸。

**结论：改 Swift 代码一律用编辑工具，不要走 shell heredoc。**
这个脚本是用来兜底的体检。
"""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2] / "val-shop-ios"

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# (正则, 说明)
#
# 只留**真会被吃掉**的模式。第一版把 `= ""`（合法初始化）和
# `Image(systemName: 变量)`（合法传参）也报出来了，噪音太大反而会掩盖真问题。
PATTERNS = [
    # 绑定变量被吃掉：.sheet(isPresented: ) / .sheet(item: )
    (r"isPresented:\s*\)", "sheet 的绑定变量被吃掉"),
    (r"isPresented:\s*,", "同上（逗号版）"),
    (r"\.sheet\(item:\s*\)", "sheet(item:) 的绑定被吃掉"),
    (r"\.sheet\(isPresented:\s*\{", "绑定被吃掉后紧跟着 {"),

    # SF Symbol 少了引号：systemName: chevron.up.chevron.down
    # 注意 `systemName: icon`（传变量）是合法的，只有**带点**才可疑
    (r"systemName:\s*[a-zA-Z_][a-zA-Z0-9_]*\.[a-zA-Z]", "SF Symbol 少了引号"),

    # 别的参数被吃掉
    (r"forKey:\s*\)", "UserDefaults key 被吃掉"),
    (r"action:\s*\)", "action 被吃掉"),
    (r"label:\s*\)", "label 被吃掉"),
    (r"await\s+\)", "await 后面空了"),
    (r"\bawait\s*$", "await 后面没东西了"),

    # 属性包装器的初始值被吃掉：@State private var x =
    (r"@(State|Binding|Environment|FocusState)\b[^=]*=\s*$", "属性包装器初始值被吃掉"),
]

# 注意：不要加「= 对象.属性」这类模式。
# 试过，`renewError = client.lastError`、`userRole = roles.preferred` 这种
# 正常赋值全被报出来，140 行噪音里淹掉真问题 —— 体检脚本自己也得体检。


def main() -> int:
    bad = 0
    files = sorted(ROOT.rglob("*.swift"))
    print(f"扫描 {len(files)} 个 Swift 文件\n")

    for f in files:
        # 跳过 .build
        if ".build" in f.parts:
            continue
        try:
            lines = f.read_text(encoding="utf-8").splitlines()
        except Exception as e:
            print(f"  读不了 {f}: {e}")
            continue

        for n, line in enumerate(lines, 1):
            stripped = line.rstrip()
            # 注释行跳过 —— 注释里出现这些字样是正常的
            if stripped.lstrip().startswith("//"):
                continue
            for pat, why in PATTERNS:
                if re.search(pat, stripped):
                    rel = f.relative_to(ROOT)
                    print(f"  {rel}:{n}")
                    print(f"      {stripped.strip()}")
                    print(f"      ↑ {why}")
                    bad += 1

    print()
    if bad:
        print(f"  ❌ 发现 {bad} 处可疑")
    else:
        print("  ✅ 没发现被 shell 吃掉的痕迹")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
