// =============================================================================
//  翻牌光效验算台
// =============================================================================
//
//  验的是这一版的口径（都在 FlipCard.swift 里，参数一一对应）：
//
//  ① **顺序**
//       · 细线 0.02→0.48 绕满一圈（慢→快→慢）
//       · 转完才开始发光：光晕窗口 0.46→0.58，和线合拢（0.48）只差 28ms
//       · 抬起 0.46→0.58 到最高，**翻转 0.58 才起步**（抬起之后才翻）
//  ② **速度**：smoothstep —— 头尾两段各 56°，中间两段各 124°（对称的慢→快→慢）
//  ③ **光晕**：扫完之前是 0；峰值 0.90；落地后收到 0.40（比裸线亮一点点，不是灭掉）
//
//  跑法（val-shop-ios/probe 下）：
//      swiftc -O flow_probe.swift -o flow.exe; .\flow.exe
// =============================================================================

import Foundation

// ---- 从 FlipCard.swift 原样搬过来 -------------------------------------------

let FLIP = 1.4            // ZW.flip
let FRAMES = 84           // 1.4s @ 60fps

let RING_FROM = 0.02, RING_TO = 0.48    // 细线绕一圈
let GLOW_FROM = 0.46, GLOW_TO = 0.58    // 开始发光
let LIFT_FROM = 0.46, LIFT_TO = 0.58    // 抬起（和发光同一窗口）
let LIFT_DOWN = 0.92
let FLIP_FROM = 0.58, FLIP_TO = 0.92    // 翻转
let COMET_FROM = 0.44, COMET_TO = 0.50  // 光头收线
let GLOW_DOWN = 0.90                    // 落地时减弱

let GLOW_PEAK = 0.90      // ZW.flipGlowPeak
let REST_GLOW = 0.40      // ZW.flipRestGlow

func window(_ p: Double, _ from: Double, _ to: Double) -> Double {
    min(max((p - from) / max(to - from, 0.0001), 0), 1)
}

func smoothstep(_ t: Double) -> Double {
    let x = min(max(t, 0), 1)
    return x * x * (3 - 2 * x)
}

func ringProgress(_ p: Double) -> Double { smoothstep(window(p, RING_FROM, RING_TO)) }

func glowOpacity(_ p: Double) -> Double {
    guard p > 0 else { return 0 }
    let up = smoothstep(window(p, GLOW_FROM, GLOW_TO))
    let down = window(p, GLOW_DOWN, 1.00)
    return GLOW_PEAK * up * (1 - down) + REST_GLOW * up * down
}

func lift(_ p: Double) -> Double {
    smoothstep(window(p, LIFT_FROM, LIFT_TO)) * (1 - window(p, LIFT_DOWN, 1.0))
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

// ---- ① 顺序 ----------------------------------------------------------------

print("== ① 顺序：细线绕完 → 开始发光 → 抬起 → 才翻 ==")

let ringDone = firstP { ringProgress($0) >= 1 - 1e-12 }
let glowStart = firstP { glowOpacity($0) > 1e-9 }
let liftPeak = firstP { lift($0) >= 1 - 1e-12 }
let flipStart = firstP { rotationAngle($0) > 1e-9 }

print(String(format: "  合拢 p=%.4f (%.0fms)   起光 p=%.4f (%.0fms)   抬到顶 p=%.4f (%.0fms)   起翻 p=%.4f (%.0fms)",
             ringDone, ms(ringDone), glowStart, ms(glowStart),
             liftPeak, ms(liftPeak), flipStart, ms(flipStart)))

check(abs(ringDone - RING_TO) < 0.001,
      "细线在 p = \(RING_TO) 绕满一圈", String(format: "%.0f ms", ms(ringDone)))
check(abs(glowStart - ringDone) <= 0.03,
      "「转完一圈才开始发光」（起光和合拢几乎同刻）",
      String(format: "差 %.0f ms", ms(glowStart - ringDone)))
check(abs(liftPeak - flipStart) < 0.002,
      "抬到最高的那一刻 == 开始翻的那一刻", String(format: "差 %.0f ms", ms(liftPeak - flipStart)))
check(rotationAngle(ringDone) < 1e-9,
      "细线没走完之前，卡一点都不转", String(format: "rotation=%.4f°", rotationAngle(ringDone)))
check(glowOpacity(0.44) < 1e-9,
      "细线还在跑的时候没有光晕", String(format: "p=0.44 → %.3f", glowOpacity(0.44)))
check(glowOpacity(ringDone) < 0.10,
      "合拢那一刻光晕才刚起来", String(format: "p=%.2f → %.3f", RING_TO, glowOpacity(ringDone)))

var ringStable = true
var q = ringDone
while q <= 1.0 {
    if abs(ringProgress(q) - 1) > 1e-12 { ringStable = false }
    q += 0.005
}
check(ringStable, "合拢之后不再绕第二圈", "0.48 → 1.00 全程 = 1")

// ---- ② 速度：慢 → 快 → 慢 --------------------------------------------------

print("\n== ② 速度曲线（smoothstep，0.02→0.48 共 \(Int(ms(RING_TO - RING_FROM)))ms）==")

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
let peak = moving.max() ?? 0
let peakSec = (360 / ((RING_TO - RING_FROM) * FLIP)) * 1.5   // smoothstep 峰值 = 1.5×平均

print(String(format: "  总 %.2f°   动帧 %d/%d   动帧平均 %.2f°/帧   峰值 %.2f°/帧（≈ %.0f°/s）",
             total, moving.count, steps.count, meanMoving, peak, peakSec))
check(abs(total - 360) < 1e-9, "正好 360°", String(format: "%.12f°", total))
check(peak / max(meanMoving, 1e-9) > 1.25 && peak / max(meanMoving, 1e-9) < 1.75,
      "峰值 ≈ 1.5× 平均（真的有一段「快」）",
      String(format: "%.3f×", peak / max(meanMoving, 1e-9)))

// 四段的角度分布：慢 → 快 → 快 → 慢，而且左右对称
// 注意要按**扫光那一段自己的行程**切（0.02→0.48），不是按整条动画的时间轴切 ——
// 按时间轴切的话前两段会吃掉几乎全部 360°（后半段本来就是静止的）。
var quarters: [Double] = []
for k in 0..<4 {
    let x0 = Double(k) / 4
    let x1 = Double(k + 1) / 4
    quarters.append((smoothstep(x1) - smoothstep(x0)) * 360)
}
print(String(format: "  四段：%.1f° / %.1f° / %.1f° / %.1f°", quarters[0], quarters[1], quarters[2], quarters[3]))
check(quarters[0] < 70 && quarters[1] > 110 && quarters[2] > 110 && quarters[3] < 70,
      "慢 → 快 → 慢（头尾两段明显小于中间两段）", "")
check(abs(quarters[0] - quarters[3]) < 1e-9 && abs(quarters[1] - quarters[2]) < 1e-9,
      "左右对称", "")

// ---- ③ 光晕：扫完才亮，落地收到"比裸线亮一点点" -----------------------------

print("\n== ③ 光晕 ==")
check(glowOpacity(0.30) < 1e-9, "扫的过程中一点光晕都没有",
      String(format: "p=0.30 → %.3f", glowOpacity(0.30)))
check(abs(glowOpacity(0.75) - GLOW_PEAK) < 1e-9, "翻牌阶段是峰值",
      String(format: "p=0.75 → %.2f", glowOpacity(0.75)))
check(abs(glowOpacity(1.0) - REST_GLOW) < 1e-9, "落定后收到 \(REST_GLOW)",
      String(format: "p=1.00 → %.2f", glowOpacity(1.0)))
check(glowOpacity(1.0) > 0.2, "落定不是灭掉 —— 比裸线亮一点点",
      String(format: "%.2f > 0", REST_GLOW))

print("\n== ④ 光头收线 ==")
check(cometOpacity(0.42) > 0.5, "合拢前还亮着", String(format: "p=0.42 → %.2f", cometOpacity(0.42)))
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
