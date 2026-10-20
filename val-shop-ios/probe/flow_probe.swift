// =============================================================================
//  翻牌编排验算台
// =============================================================================
//
//  验两件事：
//
//  ① **时序**（这次改动的验收条件）：光环走完一圈 → 卡抬到最高 → 停一拍 → 才翻。
//     光还在跑就翻的话，看上去就是两件事撞在一起。
//       · 光环在 p = 0.46 扫满 360°，之后不再动
//       · 抬升在 p = 0.46 到最高（和扫满是同一刻）
//       · 翻转在 p = 0.50 才起步（中间那一拍是"定格"）
//
//  ② **速度曲线**：扫光窗口内（0.02→0.46）逐帧匀速，不能有静止帧、也不能忽快忽慢；
//     光头在合拢时淡出（否则扫完会留一颗亮头挂着，看着像"光卡住了"）。
//
//  对照：最早那版扫圈窗口是 0.02→0.45 的 `smoothstep`，翻转 0.45 就起步 ——
//  扫满和起翻撞在同一刻，同时曲线后半段彻底静止（84 帧里 47 帧速度为 0）。
//
//  跑法（val-shop-ios/probe 下）：
//      swiftc -O flow_probe.swift -o flow.exe; .\flow.exe
// =============================================================================

import Foundation

// ---- 从 FlipCard.swift 原样搬过来 -------------------------------------------

let RAMP = 0.08          // ZW.flipFlowRamp
let FLIP = 1.4           // ZW.flip
let FRAMES = 84          // 1.4s @ 60fps

let RING_FROM = 0.02, RING_TO = 0.46    // 光环扫一圈
let LIFT_FROM = 0.02, LIFT_TO = 0.46    // 抬升（和扫圈同一窗口）
let LIFT_DOWN = 0.92                    // 开始落下
let FLIP_FROM = 0.50, FLIP_TO = 0.92    // 翻转
let COMET_OUT_FROM = 0.39, COMET_OUT_TO = 0.46   // 光头淡出

func window(_ p: Double, _ from: Double, _ to: Double) -> Double {
    min(max((p - from) / max(to - from, 0.0001), 0), 1)
}

func smoothstep(_ t: Double) -> Double {
    let x = min(max(t, 0), 1)
    return x * x * (3 - 2 * x)
}

/// 起步加速 → 全程匀速（收尾不减速：圆环是周期图形，走满 360° 正好接回起点）
func flow(_ t: Double, ramp: Double = RAMP) -> Double {
    let x = min(max(t, 0), 1)
    let e = min(max(ramp, 0), 0.3)
    guard e > 0 else { return x }
    let v = 1 / (1 - e / 2)
    if x <= e { return v * x * x / (2 * e) }
    return v * (x - e / 2)
}

func ringProgress(_ p: Double) -> Double { flow(window(p, RING_FROM, RING_TO)) }

func lift(_ p: Double) -> Double {
    smoothstep(window(p, LIFT_FROM, LIFT_TO)) * (1 - window(p, LIFT_DOWN, 1.0))
}

func rotationAngle(_ p: Double) -> Double {
    let t = window(p, FLIP_FROM, FLIP_TO)
    let tail = min(max((t - 0.75) / 0.25, 0), 1)
    return t * 180 + 3.2 * sin(.pi * tail)
}

func cometOpacity(_ p: Double) -> Double { 1 - window(p, COMET_OUT_FROM, COMET_OUT_TO) }

// 最早那版（对照用）：0.02→0.45 扫完（smoothstep），翻转 0.45→0.95
func ringProgressOld(_ p: Double) -> Double { smoothstep(window(p, 0.02, 0.45)) }

// ---- 小工具 -----------------------------------------------------------------

func firstP(_ f: (Double) -> Bool) -> Double {
    var p = 0.0
    while p <= 1.0 {
        if f(p) { return p }
        p += 0.0001
    }
    return .nan
}

var failures: [String] = []
func check(_ ok: Bool, _ what: String, _ detail: String) {
    print("  \(ok ? "过" : "败")  \(what)   \(detail)")
    if !ok { failures.append(what) }
}
func ms(_ p: Double) -> Double { p * FLIP * 1000 }

// ---- ① 时序 ----------------------------------------------------------------

print("== ① 时序：光扫完 → 抬到顶 → 停一拍 → 才翻 ==")

let ringDone = firstP { ringProgress($0) >= 1 - 1e-12 }
let flipStart = firstP { rotationAngle($0) > 1e-9 }

// 抬到顶：lift 第一次到 1
let liftPeakAt = firstP { lift($0) >= 1 - 1e-12 }

print(String(format: "  光环扫满 p=%.4f (%.0fms)   抬到最高 p=%.4f (%.0fms)   起翻 p=%.4f (%.0fms)",
             ringDone, ms(ringDone), liftPeakAt, ms(liftPeakAt), flipStart, ms(flipStart)))

check(abs(ringDone - RING_TO) < 0.001,
      "光环在 p = \(RING_TO) 扫满一整圈",
      String(format: "%.0f ms", ms(ringDone)))
check(abs(liftPeakAt - ringDone) < 0.002,
      "抬到最高的那一刻 == 光环扫满的那一刻",
      String(format: "差 %.0f ms", abs(ms(liftPeakAt) - ms(ringDone))))
check(flipStart - ringDone >= 0.02,
      "翻转晚于光环扫完（中间有定格）",
      String(format: "晚 %.0f ms", ms(flipStart - ringDone)))
check(lift(flipStart) >= 0.99,
      "开始翻的时候卡在最高点",
      String(format: "lift=%.3f", lift(flipStart)))
check(ringProgress(flipStart) >= 1 - 1e-12,
      "开始翻的时候光环已经合拢",
      String(format: "ringProgress=%.6f", ringProgress(flipStart)))
check(rotationAngle(ringDone) < 1e-9,
      "光环走完之前，卡一点都不转",
      String(format: "rotation=%.4f°", rotationAngle(ringDone)))

// 扫完之后整圈光不再变（合拢就是合拢，不会接着绕第二圈）
var ringStable = true
var q = ringDone
while q <= 1.0 {
    if abs(ringProgress(q) - 1) > 1e-12 { ringStable = false }
    q += 0.005
}
check(ringStable, "扫满之后不再绕第二圈", "0.46 → 1.00 全程 = 1")

// ---- ② 扫光窗口内的逐帧角速度 -----------------------------------------------

print("\n== ② 扫光那 0.44 段里的逐帧角速度（84 帧坐标系）==")

var steps: [Double] = []
var prev = ringProgress(0)
for i in 1...FRAMES {
    let u = ringProgress(Double(i) / Double(FRAMES))
    steps.append((u - prev) * 360)
    prev = u
}

let moving = steps.filter { $0 > 1e-9 }
let total = steps.reduce(0, +)
let meanMoving = moving.reduce(0, +) / Double(max(moving.count, 1))
let maxStep = moving.max() ?? 0
let peakDegPerSec = 360 / ((RING_TO - RING_FROM) * FLIP)

print(String(format: "  总 %6.2f°   动帧 %d/%d   动帧平均 %4.2f°/帧   最大 %4.2f°/帧   最大/平均 %.3f   峰值 %.0f°/s",
             total, moving.count, steps.count, meanMoving, maxStep,
             maxStep / max(meanMoving, 1e-9), peakDegPerSec))
print(String(format: "  扫一圈用 %.0f ms（%.0f → %.0f ms）", ms(RING_TO - RING_FROM), ms(RING_FROM), ms(RING_TO)))

check(abs(total - 360) < 1e-9, "正好 360°", String(format: "%.12f°", total))

// 静止帧必须全部落在扫完之后（扫之前静止是预铺，扫之后静止是设计）
var movingOutside = 0
for (i, s) in steps.enumerated() where s > 1e-9 {
    let p = Double(i + 1) / Double(FRAMES)
    if p < RING_FROM - 1e-9 || p > RING_TO + 1.0 / Double(FRAMES) { movingOutside += 1 }
}
check(movingOutside == 0, "只有 0.02→0.46 这段在动（允许跨越边界的那一帧）",
      "段外动帧 \(movingOutside) 帧")
check(maxStep / max(meanMoving, 1e-9) <= 1.35,
      "扫的过程匀速（最大/平均 ≤ 1.35）",
      String(format: "%.3f", maxStep / max(meanMoving, 1e-9)))

// ---- ③ 光头在合拢时收掉 -----------------------------------------------------

print("\n== ③ 光头 · 合拢即收 ==")
check(cometOpacity(0.42) > 0.5, "合拢前还亮着",
      String(format: "p=0.42 → %.2f", cometOpacity(0.42)))
check(cometOpacity(RING_TO) <= 1e-9, "合拢那一刻已淡出（不留亮头挂着）",
      String(format: "p=%.2f → %.2f", RING_TO, cometOpacity(RING_TO)))

// ---- ④ 对照最早那版 ---------------------------------------------------------

print("\n== ④ 对照：最早那版为什么「光没走完就翻」 ==")
let oldRingDone = 0.45, oldFlipFrom = 0.45
print(String(format: "  旧：光环 p=%.2f 扫满，翻转 p=%.2f 起步 → 间隔 %.0f ms（等于撞在一起）",
             oldRingDone, oldFlipFrom, ms(oldFlipFrom - oldRingDone)))
var oldSteps: [Double] = []
var prevOld = ringProgressOld(0)
for i in 1...FRAMES {
    let u = ringProgressOld(Double(i) / Double(FRAMES))
    oldSteps.append((u - prevOld) * 360)
    prevOld = u
}
let oldIdle = oldSteps.filter { $0 <= 1e-9 }.count
print(String(format: "  旧曲线：84 帧里 %d 帧速度为 0，后 1/4 时间走过 %.2f°",
             oldIdle, oldSteps[(FRAMES * 3 / 4)...].reduce(0, +)))
check(oldFlipFrom <= oldRingDone + 1e-9,
      "旧版扫满与起翻是同一刻（所以看着像光没走完就翻）",
      String(format: "p=%.2f / p=%.2f", oldRingDone, oldFlipFrom))
check(oldSteps[(FRAMES * 3 / 4)...].reduce(0, +) < 1e-9,
      "旧曲线后 1/4 时间是静止的（另一条病根）", "0°")

print("")
if failures.isEmpty {
    print("全部通过。")
    exit(0)
} else {
    print("失败 \(failures.count) 项：")
    for f in failures { print("  · \(f)") }
    exit(1)
}
