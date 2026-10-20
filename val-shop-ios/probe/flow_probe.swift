// =============================================================================
//  翻牌光效验算台
// =============================================================================
//
//  验的是这一版的口径（都在 FlipCard.swift 里，参数一一对应）：
//
//  ① **时序**
//       · 细线 0.02→0.55 贴着卡边绕满一圈（900ms，慢→快→慢）
//       · **抬起动作在 0.46 结束 == 细线合拢那一刻**；翻转 0.48 才起步
//  ② **光晕三档**
//       · 转动时就已经有一层薄晕 0.35（"转的时候也得有点晕染"）
//       · 抬起 → 翻转这段加重到 1.0（"这一段光要再重一点"）
//       · 落地渐弱到 0.35，而且是**在整段落下里慢慢降**，不是一下子变暗
//  ③ **细线的减弱**：翻完之后（0.80）才开始降，落地那一刻正好停在 0.55 —— 不消失
//  ④ **速度**：smoothstep —— 头尾两段各 56°，中间两段各 124°（对称的慢→快→慢）
//
//  跑法（val-shop-ios/probe 下）：
//      swiftc -O flow_probe.swift -o flow.exe; .\flow.exe
// =============================================================================

import Foundation

// ---- 从 FlipCard.swift 原样搬过来 -------------------------------------------

let FLIP = 1.7            // ZW.flip
let FRAMES = 84           // 1.4s @ 60fps

let RING_FROM = 0.02, RING_TO = 0.55    // 细线绕一圈（900ms，慢→快→慢）
let LIFT_FROM = 0.35, LIFT_TO = 0.55    // 升起（到顶 == 合拢）
let LIFT_DOWN_FROM = 0.84               // 开始落下
let FLIP_FROM = 0.58, FLIP_TO = 0.84    // 翻转
let COMET_FROM = 0.49, COMET_TO = 0.56  // 光头收线

let LINE_PEAK = 1.0       // ZW.flipLineOpacity
let LINE_REST = 0.55      // ZW.flipLineRestOpacity
let GLOW_SWEEP = 0.35     // ZW.flipGlowDuringSweep
let GLOW_PEAK = 1.0       // ZW.flipGlowPeak
let GLOW_REST = 0.35      // ZW.flipRestGlow

func window(_ p: Double, _ from: Double, _ to: Double) -> Double {
    min(max((p - from) / max(to - from, 0.0001), 0), 1)
}

func smoothstep(_ t: Double) -> Double {
    let x = min(max(t, 0), 1)
    return x * x * (3 - 2 * x)
}

func ringProgress(_ p: Double) -> Double { smoothstep(window(p, RING_FROM, RING_TO)) }

func lineOpacity(_ p: Double) -> Double {
    guard p > 0 else { return 0 }
    let rise = window(p, 0.00, 0.04)
    let down = smoothstep(window(p, LIFT_DOWN_FROM, 1.00))
    return (LINE_PEAK * (1 - down) + LINE_REST * down) * rise
}

func glowOpacity(_ p: Double) -> Double {
    guard p > 0 else { return 0 }
    let thin = GLOW_SWEEP * window(p, 0.00, 0.10)
    let heavy = smoothstep(window(p, LIFT_FROM, LIFT_TO))
    let down = smoothstep(window(p, LIFT_DOWN_FROM, 1.00))
    let lit = thin + (GLOW_PEAK - thin) * heavy
    return lit * (1 - down) + GLOW_REST * down
}

func lift(_ p: Double) -> Double {
    smoothstep(window(p, LIFT_FROM, LIFT_TO)) * (1 - smoothstep(window(p, LIFT_DOWN_FROM, 1.0)))
}

func rotationAngle(_ p: Double) -> Double {
    let t = window(p, FLIP_FROM, FLIP_TO)
    let tail = min(max((t - 0.75) / 0.25, 0), 1)
    return t * 180 + 3.2 * sin(.pi * tail)
}

func cometOpacity(_ p: Double) -> Double { 1 - window(p, COMET_FROM, COMET_TO) }

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

print("== ① 时序：细线绕完 == 抬起到顶 → 停一拍 → 才翻 ==")

let ringDone = firstP { ringProgress($0) >= 1 - 1e-12 }
let liftPeak = firstP { lift($0) >= 1 - 1e-12 }
let flipStart = firstP { rotationAngle($0) > 1e-9 }

print(String(format: "  合拢 p=%.4f (%.0fms)   抬到顶 p=%.4f (%.0fms)   起翻 p=%.4f (%.0fms)",
             ringDone, ms(ringDone), liftPeak, ms(liftPeak), flipStart, ms(flipStart)))

check(abs(ringDone - RING_TO) < 0.001,
      "细线在 p = \(RING_TO) 绕满一圈", String(format: "%.0f ms", ms(ringDone)))
check(abs(liftPeak - ringDone) < 0.002,
      "**抬起动作结束 == 细线合拢**（同一刻）",
      String(format: "差 %.0f ms", ms(liftPeak - ringDone)))
check(flipStart - ringDone >= 0.01,
      "翻转晚于抬起（有一拍「准备要翻了」）",
      String(format: "晚 %.0f ms", ms(flipStart - ringDone)))
check(rotationAngle(ringDone) < 1e-9,
      "细线没走完之前，卡一点都不转", String(format: "rotation=%.4f°", rotationAngle(ringDone)))

// ---- ② 光晕三档 ------------------------------------------------------------

print("\n== ② 光晕：转动薄晕 → 抬起翻转最重 → 落地渐弱 ==")

check(abs(glowOpacity(0.20) - GLOW_SWEEP) < 1e-9,
      "转动时就有薄晕（不是 0）", String(format: "p=0.20 → %.2f", glowOpacity(0.20)))
check(abs(glowOpacity(0.60) - GLOW_PEAK) < 1e-9,
      "抬起 / 翻转这一段最重", String(format: "p=0.60 → %.2f", glowOpacity(0.60)))
check(abs(glowOpacity(1.00) - GLOW_REST) < 1e-9,
      "落地停常亮档", String(format: "p=1.00 → %.2f", glowOpacity(1.00)))
check(glowOpacity(0.60) > glowOpacity(0.20) * 2,
      "翻转那一下明显比转动时重", String(format: "%.2f vs %.2f",
                                          glowOpacity(0.60), glowOpacity(0.20)))

// 渐弱要看"是不是一路降"，不是"最后一下掉下来"：
// 采样落下窗口内的 6 个点，必须严格单调下降，且中段既不在峰值也不是终值。
var glowDown: [Double] = []
for i in 0...6 {
    let p = LIFT_DOWN_FROM + (1.0 - LIFT_DOWN_FROM) * Double(i) / 6
    glowDown.append(glowOpacity(p))
}
var monotone = true
for i in 1..<glowDown.count where glowDown[i] > glowDown[i - 1] + 1e-12 { monotone = false }
let midGlow = glowDown[3]
print("  落下窗口内 7 个点：" + glowDown.map { String(format: "%.2f", $0) }.joined(separator: " → "))
check(monotone, "落下期间光晕单调渐弱", "")
check(midGlow < GLOW_PEAK - 0.1 && midGlow > GLOW_REST + 0.1,
      "中段落在一半左右（不是一下子掉到底）", String(format: "%.2f", midGlow))

// ---- ③ 细线：翻完之后才开始降，落到 0.55 不消失 -----------------------------

print("\n== ③ 细线 ==")
check(abs(lineOpacity(0.70) - LINE_PEAK) < 1e-9,
      "翻之前 / 翻的过程中是满亮", String(format: "p=0.70 → %.2f", lineOpacity(0.70)))
check(abs(lineOpacity(0.90)) > LINE_REST && lineOpacity(0.90) < LINE_PEAK,
      "落下途中正在降", String(format: "p=0.90 → %.2f", lineOpacity(0.90)))
check(abs(lineOpacity(1.00) - LINE_REST) < 1e-9,
      "落地正好停在 \(LINE_REST)（不消失）", String(format: "p=1.00 → %.2f", lineOpacity(1.00)))
check(lineOpacity(0.83) > lineOpacity(0.85), "是翻完之后才开始降（0.84 起）",
      String(format: "%.3f → %.3f", lineOpacity(0.83), lineOpacity(0.85)))

// ---- ④ 速度 ----------------------------------------------------------------

print("\n== ④ 速度曲线（smoothstep，\(Int(ms(RING_TO - RING_FROM)))ms 扫完）==")

var steps: [Double] = []
var prev = ringProgress(0)
for i in 1...FRAMES {
    let u = ringProgress(Double(i) / Double(FRAMES))
    steps.append((u - prev) * 360)
    prev = u
}
let total = steps.reduce(0, +)
let moving = steps.filter { $0 > 1e-9 }
let meanMoving = moving.reduce(0, +) / Double(max(moving.count, 1))
let peakStep = moving.max() ?? 0
let peakDegPerSec = (360 / ((RING_TO - RING_FROM) * FLIP)) * 1.5

print(String(format: "  总 %.2f°   动帧 %d/%d   峰值 %.0f°/s", total, moving.count, steps.count, peakDegPerSec))
check(abs(total - 360) < 1e-9, "正好 360°", String(format: "%.12f°", total))

var quarters: [Double] = []
for k in 0..<4 {
    let x0 = Double(k) / 4, x1 = Double(k + 1) / 4
    quarters.append((smoothstep(x1) - smoothstep(x0)) * 360)
}
print(String(format: "  四段：%.1f° / %.1f° / %.1f° / %.1f°",
             quarters[0], quarters[1], quarters[2], quarters[3]))
check(quarters[0] < 70 && quarters[1] > 110 && quarters[2] > 110 && quarters[3] < 70,
      "慢 → 快 → 慢", "")
check(abs(quarters[0] - quarters[3]) < 1e-9 && abs(quarters[1] - quarters[2]) < 1e-9,
      "左右对称", "")
check(peakStep / max(meanMoving, 1e-9) > 1.25, "真的有一段「快」",
      String(format: "%.2f× 平均", peakStep / max(meanMoving, 1e-9)))

print("\n== ⑤ 光头收线 ==")
check(cometOpacity(0.52) > 0.5, "合拢前还亮着", String(format: "p=0.52 → %.2f", cometOpacity(0.52)))
check(cometOpacity(COMET_TO) <= 1e-9, "合拢后收掉（不留亮点）",
      String(format: "p=%.2f → %.2f", COMET_TO, cometOpacity(COMET_TO)))

print("")
if failures.isEmpty {
    print("全部通过。")
    exit(0)
} else {
    print("失败 \(failures.count) 项：")
    for f in failures { print("  · \(f)") }
    exit(1)
}
