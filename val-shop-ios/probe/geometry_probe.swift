// 几何验算台 —— 把 DesignSystem.swift 里自己画的形状路径点真的算出来，
// 逐点核对。本机没有 SwiftUI，所以 Path/CGRect 用极简桩替代。
//
// 跑法（val-shop-ios/probe 下）：
//   swiftc -O geometry_probe.swift -o geo.exe && ./geo.exe
//
// 这不是单元测试，是「肉眼对账」：输出里每个点都要和注释里的期望值一致。
//
// 大改后还剩两个自绘形状（切角那套已经跟着玻璃方向撤掉了）：
//   ZWDiamond      品质钻（掌瓦 ic_val_goods_quality 的形状语言）
//   ZWHatchTexture 卡背的磨砂斜纹

import Foundation

// ---- 桩：只保留 Shape 用得到的那部分 -------------------------------

struct Rect {
    let x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat
    var minX: CGFloat { x }
    var maxX: CGFloat { x + w }
    var minY: CGFloat { y }
    var maxY: CGFloat { y + h }
    var midX: CGFloat { x + w / 2 }
    var midY: CGFloat { y + h / 2 }
    var width: CGFloat { w }
    var height: CGFloat { h }
}

struct PathStub {
    var commands: [String] = []

    mutating func move(to p: (CGFloat, CGFloat)) {
        commands.append("M \(fmt(p.0)),\(fmt(p.1))")
    }
    mutating func addLine(to p: (CGFloat, CGFloat)) {
        commands.append("L \(fmt(p.0)),\(fmt(p.1))")
    }
    mutating func closeSubpath() {
        commands.append("Z")
    }

    /// 每条线 = move + addLine
    var lineCount: Int { commands.count / 2 }
}

func fmt(_ v: CGFloat) -> String {
    let s = String(format: "%.2f", Double(v))
    return s.hasSuffix(".00") ? String(s.dropLast(3)) : s
}

// ---- 被测对象：与 DesignSystem.swift 逐行对齐 -----------------------

struct ZWDiamond {
    let inset: CGFloat

    func path(in rect: Rect) -> PathStub {
        let r = min(rect.width, rect.height) / 2 * (1 - inset)
        let cx = rect.midX
        let cy = rect.midY
        var p = PathStub()
        p.move(to: (cx, cy - r))
        p.addLine(to: (cx + r, cy))
        p.addLine(to: (cx, cy + r))
        p.addLine(to: (cx - r, cy))
        p.closeSubpath()
        return p
    }
}

struct ZWHatchTexture {
    let pitch: CGFloat

    func path(in rect: Rect) -> PathStub {
        var p = PathStub()
        guard pitch > 0 else { return p }
        var x = rect.minX - rect.height
        while x < rect.maxX {
            p.move(to: (x, rect.maxY))
            p.addLine(to: (x + rect.height, rect.minY))
            x += pitch
        }
        return p
    }
}

// ---- 对账 ---------------------------------------------------------

func dump(_ title: String, _ p: PathStub, expect: String) {
    let ok = p.commands.joined(separator: " ") == expect
        || p.commands.joined(separator: " ").replacingOccurrences(of: ",-0", with: ",0") == expect
    print("── \(title)   \(ok ? "✓ 对上" : "✗ 不一致")")
    print("   实际: \(p.commands.joined(separator: " "))")
    print("   期望: \(expect)")
    print("")
}

dump("品质钻 · 全实心（inset 0），边长 30",
     ZWDiamond(inset: 0).path(in: Rect(x: 0, y: 0, w: 30, h: 30)),
     expect: "M 15,0 L 30,15 L 15,30 L 0,15 Z")

dump("品质钻 · 方框（inset 0.30）：r = 15 × 0.7 = 10.5",
     ZWDiamond(inset: 0.30).path(in: Rect(x: 0, y: 0, w: 30, h: 30)),
     expect: "M 15,4.50 L 25.50,15 L 15,25.50 L 4.50,15 Z")

dump("品质钻 · 非正方形时取短边（60×30 → r = 15）",
     ZWDiamond(inset: 0).path(in: Rect(x: 0, y: 0, w: 60, h: 30)),
     expect: "M 30,0 L 45,15 L 30,30 L 15,15 Z")

let hatch = ZWHatchTexture(pitch: 100).path(in: Rect(x: 0, y: 0, w: 200, h: 100))
print("── 卡背斜纹（pitch 100，200×100）")
print("   实际条数: \(hatch.lineCount)   首条: \(hatch.commands.prefix(2).joined(separator: " "))")
print("   期望条数: 3（起点 x = -100 / 0 / 100；x=200 时 x<maxX 不成立，停）")
