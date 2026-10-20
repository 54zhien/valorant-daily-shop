// =============================================================================
//  光头速度曲线验算台
// =============================================================================
//
//  验的是 `App/FlipCard.swift` 里 `flow(_:)`（起步加速 → **全程匀速** → 收尾不减速）
//  取代旧 `smoothstep(0.02, 0.45)` 之后，光到底是不是"从头流到尾"：
//
//    · 归一化：u(0) = 0、u(1) = 1（一圈正好走满，不多不少）
//    · 单调：u 只增不减 —— 光不会倒转
//    · 逐帧角速度（1.4s @ 60fps = 84 帧）：
//        - 最大 / 平均 ≤ 1.15（看不出快慢起伏）
//        - **最后一帧仍是满速**（不滞留）
//        - 除了扫光前那 1 帧预铺，没有一帧速度为 0
//    · 扫光那一段切四份，每份走过 90° ± 12° —— 没有哪一段被"卡住"
//
//  对照：旧的 `smoothstep(0.02, 0.45)` 同一套指标下 84 帧里有 47 帧速度为 0，
//  后 1/4 时间走过 0.00° —— 那就是"最后四分之一在滞留"的来源。
//
//  跑法（val-shop-ios/probe 下）：
//      swiftc -O flow_probe.swift -o flow.exe; .\flow.exe
// =============================================================================

import Foundation

// ---- 从 FlipCard.swift 原样搬过来 -------------------------------------------

let RAMP = 0.08          // ZW.flipFlowRamp
let FLIP = 1.4           // ZW.flip
let FRAMES = 84          // 1.4s @ 60fps
let SWEEP_FROM = 0.02    // ringProgress 的窗口起点
let SWEEP_TO = 1.00

func window(_ p: Double, _ from: Double, _ to: Double) -> Double {
    min(max((p - from) / max(to - from, 0.0001), 0), 1)
}

func smoothstep(_ t: Double) -> Double {
    let x = min(max(t, 0), 1)
    return x * x * (3 - 2 * x)
}

/// 起步加速 → 全程匀速（收尾不减速）
func flow(_ t: Double, ramp: Double = RAMP) -> Double {
    let x = min(max(t, 0), 1)
    let e = min(max(ramp, 0), 0.3)
    guard e > 0 else { return x }
    let v = 1 / (1 - e / 2)
    if x <= e { return v * x * x / (2 * e) }
    return v * (x - e / 2)
}

/// 新：光走满整段
func ringProgressNew(_ p: Double) -> Double { flow(window(p, SWEEP_FROM, SWEEP_TO)) }
/// 旧：0.02 → 0.45 走完，之后彻底不动
func ringProgressOld(_ p: Double) -> Double { smoothstep(window(p, 0.02, 0.45)) }

// ---- 验算 -------------------------------------------------------------------

var failures: [String] = []
func check(_ ok: Bool, _ what: String, _ detail: String) {
    print("  \(ok ? "过" : "败")  \(what)   \(detail)")
    if !ok { failures.append(what) }
}

print("== 归一化 / 单调 ==")
check(abs(ringProgressNew(0)) < 1e-12, "u(0) = 0", String(format: "%.15f", ringProgressNew(0)))
check(abs(ringProgressNew(1) - 1) < 1e-12, "u(1) = 1", String(format: "%.15f", ringProgressNew(1)))

var mono = true
var p = 0.0
var last = ringProgressNew(0)
while p <= 1.0 {
    let u = ringProgressNew(p)
    if u < last - 1e-12 { mono = false }
    last = u
    p += 0.001
}
check(mono, "单调递增（不倒转）", "步长 0.001 全程扫过")

// ---- 逐帧角速度（整段动画的坐标系）------------------------------------------

func steps(_ f: (Double) -> Double) -> [Double] {
    var out: [Double] = []
    var prev = f(0)
    for i in 1...FRAMES {
        let u = f(Double(i) / Double(FRAMES))
        out.append((u - prev) * 360)      // 每帧走过多少度
        prev = u
    }
    return out
}

func report(_ name: String, _ s: [Double]) {
    let total = s.reduce(0, +)
    let idle = s.filter { $0 <= 1e-9 }.count
    let mean = total / Double(s.count)
    let mx = s.max() ?? 0
    print(String(format: "  %@：总 %6.2f°  平均 %5.2f°/帧  最大 %5.2f°/帧  最大/平均 %.3f  静的帧 %d/%d  末帧 %5.2f°",
                 name, total, mean, mx, mx / max(mean, 1e-9), idle, s.count, s.last ?? 0))
}

print("\n== 逐帧角速度（\(FRAMES) 帧 / \(FLIP)s，整段动画）==")
let newSteps = steps(ringProgressNew)
let oldSteps = steps(ringProgressOld)
report("新 flow", newSteps)
report("旧 smooth", oldSteps)

let meanNew = newSteps.reduce(0, +) / Double(newSteps.count)
let maxNew = newSteps.max() ?? 0
let idleNew = newSteps.filter { $0 <= 1e-9 }.count

check(abs(newSteps.reduce(0, +) - 360) < 1e-9, "一圈正好 360°",
      String(format: "%.12f°", newSteps.reduce(0, +)))
check(maxNew / meanNew <= 1.15, "最大/平均 ≤ 1.15",
      String(format: "%.3f", maxNew / meanNew))
check((newSteps.last ?? 0) > meanNew * 0.9, "末帧仍是满速（不滞留）",
      String(format: "%.2f°/帧（平均 %.2f）", newSteps.last ?? 0, meanNew))
check(idleNew == 1, "只有出发前 1 帧是静的（0.02 预铺，不是滞留）", "\(idleNew) 帧")

// ---- 扫光那一段切四份 -------------------------------------------------------

/// 在 [0,1] 的行程上均分采样，看每 1/4 行程对应多少帧的角度
func sweepQuarters() -> [Double] {
    var out: [Double] = []
    var prev = flow(0)
    for i in 1...FRAMES {
        let u = flow(Double(i) / Double(FRAMES))
        out.append((u - prev) * 360)
        prev = u
    }
    return out
}

print("\n== 扫光区间切四份（理想 90°×4）==")
let qSteps = sweepQuarters()
let q = qSteps.count / 4
for i in 0..<4 {
    let slice = qSteps[(i * q)..<min((i + 1) * q, qSteps.count)]
    let deg = slice.reduce(0, +)
    let ok = abs(deg - 90) <= 12
    print(String(format: "  %d/4 段：%6.2f°   %@", i + 1, deg, ok ? "过" : "败"))
    if !ok { failures.append("第 \(i + 1) 段角度 \(String(format: "%.2f", deg))") }
}

// ---- 和旧曲线正面对照 -------------------------------------------------------

print("\n== 对照：旧曲线为什么看着「滞留」 ==")
let half = FRAMES / 2
let threeQuarters = FRAMES * 3 / 4
print(String(format: "  后 1/2 时间：旧 %6.2f°  新 %6.2f°",
             oldSteps[half...].reduce(0, +), newSteps[half...].reduce(0, +)))
print(String(format: "  后 1/4 时间：旧 %6.2f°  新 %6.2f°",
             oldSteps[threeQuarters...].reduce(0, +), newSteps[threeQuarters...].reduce(0, +)))
check(oldSteps[threeQuarters...].reduce(0, +) < 1e-9, "旧曲线后 1/4 时间是静止的（病根）",
      "0°")

print("")
if failures.isEmpty {
    print("全部通过。")
    exit(0)
} else {
    print("失败 \(failures.count) 项：")
    for f in failures { print("  · \(f)") }
    exit(1)
}
