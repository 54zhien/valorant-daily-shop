// 圆角矩形轮廓采样验算台
//
// 验的是 DesignSystem.swift 里 `ZWRingSweep.point(at:)` 的几何：
//   · 起点在上边中点，顺时针一圈
//   · t = 0 和 t = 1 必须重合（闭合）
//   · 相邻采样点间距 ≈ 周长 / 采样数（连续、不跳段、不切块）
//   · 折线总长 ≈ 2(w-2r) + 2(h-2r) + 2πr（弧长参数化正确）
//
// 跑法（val-shop-ios/probe 下）：
//   swiftc -O ring_probe.swift -o ring.exe; .\ring.exe

import Foundation

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

struct Pt: Equatable {
    let x: CGFloat, y: CGFloat
    func distance(to o: Pt) -> CGFloat { ((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y)).squareRoot() }
}

// ---- 从 DesignSystem.swift 原样搬过来 ----------------------------------

func ringPoint(at t: Double, in rect: Rect, cornerRadius: CGFloat, inset: CGFloat = 0) -> Pt {
    let r0x = rect.minX + inset, r0y = rect.minY + inset
    let r0w = max(0, rect.width - 2 * inset), r0h = max(0, rect.height - 2 * inset)
    let radius = max(0, min(cornerRadius, min(r0w, r0h) / 2))
    let minX = r0x, maxX = r0x + r0w
    let minY = r0y, maxY = r0y + r0h
    let midX = r0x + r0w / 2

    let straightH = max(0, r0w - 2 * radius)
    let straightV = max(0, r0h - 2 * radius)
    let arc = CGFloat(Double.pi) * radius / 2
    let halfTop = straightH / 2

    let lengths: [CGFloat] = [halfTop, arc, straightV, arc, straightH, arc, straightV, arc, halfTop]
    let total = lengths.reduce(0, +)
    guard total > 0 else { return Pt(x: midX, y: minY) }

    var dist = t.truncatingRemainder(dividingBy: 1)
    if dist < 0 { dist += 1 }
    var remain = CGFloat(dist) * total

    func lerp(_ a: CGFloat, _ b: CGFloat, _ f: CGFloat) -> CGFloat { a + (b - a) * f }
    func onArc(_ cx: CGFloat, _ cy: CGFloat, _ start: Double, _ f: Double) -> Pt {
        let ang = start + f * (.pi / 2)
        return Pt(x: cx + radius * CGFloat(cos(ang)), y: cy + radius * CGFloat(sin(ang)))
    }

    if remain <= lengths[0] {
        let f = remain / lengths[0]
        return Pt(x: lerp(midX, maxX - radius, f), y: minY)
    }
    remain -= lengths[0]
    if remain <= lengths[1] {
        return onArc(maxX - radius, minY + radius, -.pi / 2, Double(remain / lengths[1]))
    }
    remain -= lengths[1]
    if remain <= lengths[2] {
        let f = remain / lengths[2]
        return Pt(x: maxX, y: lerp(minY + radius, maxY - radius, f))
    }
    remain -= lengths[2]
    if remain <= lengths[3] {
        return onArc(maxX - radius, maxY - radius, 0, Double(remain / lengths[3]))
    }
    remain -= lengths[3]
    if remain <= lengths[4] {
        let f = remain / lengths[4]
        return Pt(x: lerp(maxX - radius, minX + radius, f), y: maxY)
    }
    remain -= lengths[4]
    if remain <= lengths[5] {
        return onArc(minX + radius, maxY - radius, .pi / 2, Double(remain / lengths[5]))
    }
    remain -= lengths[5]
    if remain <= lengths[6] {
        let f = remain / lengths[6]
        return Pt(x: minX, y: lerp(maxY - radius, minY + radius, f))
    }
    remain -= lengths[6]
    if remain <= lengths[7] {
        return onArc(minX + radius, minY + radius, .pi, Double(remain / lengths[7]))
    }
    remain -= lengths[7]
    let f = remain / lengths[8]
    return Pt(x: lerp(minX + radius, midX, f), y: minY)
}

// ---- 验算 --------------------------------------------------------------

let rect = Rect(x: 0, y: 0, w: 173, h: 202)     // 卡面实际尺寸量级
let radius: CGFloat = 20
let inset: CGFloat = 2

let w = rect.width - 2 * inset
let h = rect.height - 2 * inset
let expected = 2 * (w - 2 * radius) + 2 * (h - 2 * radius) + 2 * CGFloat(Double.pi) * radius

func fmt(_ v: CGFloat) -> String { String(format: "%.3f", Double(v)) }
var failures = 0
func check(_ ok: Bool, _ label: String, _ detail: String = "") {
    print("\(ok ? "✓" : "✗") \(label)\(detail.isEmpty ? "" : "  \(detail)")")
    if !ok { failures += 1 }
}

// ① 起点在上边中点
let p0 = ringPoint(at: 0, in: rect, cornerRadius: radius, inset: inset)
check(abs(p0.x - rect.midX) < 0.01 && abs(p0.y - (rect.minY + inset)) < 0.01,
      "t=0 起点在上边中点", "(\(fmt(p0.x)), \(fmt(p0.y)))")

// ② 闭合
let p1 = ringPoint(at: 1, in: rect, cornerRadius: radius, inset: inset)
check(p0.distance(to: p1) < 0.01, "t=1 与 t=0 重合（闭合）",
      "间距 \(fmt(p0.distance(to: p1)))")

// ③ 相邻采样点间距均匀 ≈ 周长/采样数（说明是按弧长走的，不会跳段）
let samples = 2000
var gaps: [CGFloat] = []
var prev = ringPoint(at: 0, in: rect, cornerRadius: radius, inset: inset)
for i in 1...samples {
    let pt = ringPoint(at: Double(i) / Double(samples), in: rect, cornerRadius: radius, inset: inset)
    gaps.append(prev.distance(to: pt))
    prev = pt
}
let ideal = expected / CGFloat(samples)
let maxGap = gaps.max() ?? 0
let minGap = gaps.min() ?? 0
check(maxGap < ideal * 1.6 && minGap > ideal * 0.4,
      "采样间距均匀（连续，不跳段）",
      "理想 \(fmt(ideal))，实际 \(fmt(minGap))…\(fmt(maxGap))")

// ④ 折线总长 ≈ 理论周长
let measured = gaps.reduce(0, +)
check(abs(measured - expected) / expected < 0.01,
      "折线总长 ≈ 2(w-2r)+2(h-2r)+2πr",
      "实测 \(fmt(measured)) / 理论 \(fmt(expected))")

// ⑤ 四个关键点：右中、下中、左中大致落在相应边上（不要求在 t=0.25/0.5/0.75，
//    因为弧长按边长分配；只要 y 在右边、x 在下边即可）
let onRight = ringPoint(at: 0.25, in: rect, cornerRadius: radius, inset: inset)
check(onRight.x > rect.midX, "t=0.25 在右半圈", "(\(fmt(onRight.x)), \(fmt(onRight.y)))")

// ⑥ 一小段（0.78→1.0，也就是用户说"像被切块"的那四分一圈）里，
//    采样点必须仍然连续 —— 逐点间距不超过理想的 2 倍
var segGaps: [CGFloat] = []
var segPrev = ringPoint(at: 0.78, in: rect, cornerRadius: radius, inset: inset)
for i in 1...200 {
    let t = 0.78 + 0.22 * Double(i) / 200
    let pt = ringPoint(at: t, in: rect, cornerRadius: radius, inset: inset)
    segGaps.append(segPrev.distance(to: pt))
    segPrev = pt
}
let segIdeal = expected * 0.22 / 200
check((segGaps.max() ?? 0) < segIdeal * 1.6,
      "最后 22% 一段内采样连续",
      "理想 \(fmt(segIdeal))，实际最大 \(fmt(segGaps.max() ?? 0))")

print("")
print(failures == 0 ? "全部通过" : "有 \(failures) 项不通过")
exit(failures == 0 ? 0 : 1)
