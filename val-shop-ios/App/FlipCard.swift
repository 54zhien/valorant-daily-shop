import SwiftUI

// ============================================================================
//  翻牌容器 —— 一个进度值驱动一整段编排
// ============================================================================
//
//  点击之后按顺序发生这些事（不是同时）：
//
//     p 0.00 ─ 0.06   品质光起头（很快亮起来，但不硬切）
//     p 0.02 ─ 1.00   **品质光沿卡牌边缘跑满一圈** —— 起步一小段加速，之后全程
//                     匀速，收尾不减速。旧版窗口只到 0.45 就用 smoothstep 刹死，
//                     整整后半段光一动不动，看着就是"最后四分之一在滞留"。
//     p 0.02 ─ 0.45   卡牌向顶部抬升，底部阴影拉开、变散
//     p 0.45 ─ 0.95   翻转（抬着翻），末尾 3.2° 过冲再回正
//     p 0.70          换面（正好是翻转行程的中点 → 卡片侧对镜头，看不见）
//     p 0.85 ─ 1.00   落下，阴影收拢
//     p 0.90 ─ 1.00   整圈光从"扫过的亮度"收到 `flipGlowResting` 常亮
//     p 0.62 ─ 1.00   **卡外那圈淡光**从卡边渗出来（`outerHalo`）——
//                     翻过来之后卡内卡外都有光，卡内亮、卡外淡
//
//  实现上仍然只有一个 `progress: 0→1`，上面每个效果都是它的一段窗口函数
//  （`window(p, from:to:)`）。这样就永远不会有"谁先谁后对不齐"的问题 ——
//  想改节奏只改窗口的边界数字。
//
//  ⚠️ `animatableData` 必须显式 `nonisolated`
//     本项目默认隔离是 MainActor，Animatable 的这个要求是 nonisolated 的。
//     验算台：probe/animatable_probe.swift（三种写法 + 一组会失败的对照）。
//     速度曲线：probe/flow_probe.swift（梯形 vs 旧 smoothstep 的逐帧角速度对照）。
//
//  ⚠️ 卡外那圈光最多外扩 `ZW.flipHaloInset + blur` ≈ 10pt，
//     所以 2×2 卡阵的间距用了 `ZW.cardGap = 20`：相邻两卡各留 10pt，
//     光不会糊到隔壁卡上。想再加强外晕，先把 cardGap 一起放大。
//
//  ⚠️ 没翻开的卡必须**一点光都没有**：
//     `ZWRingSweep` 在 `from == to` 时返回空路径（否则圆帽会在起点、也就是
//     卡顶中点戳出一个光点），`ringOpacity` 在 `progress == 0` 时也硬返回 0。
//     这两条缺一条，卡顶就会挂一颗"光效起点"。
// ============================================================================

struct FlipCard<Back: View, Front: View>: View {

    var isFlipped: Bool
    var reduceMotion: Bool
    var cornerRadius: CGFloat = ZW.radiusCard
    /// 卡牌周边那道光的颜色。传品质色 = 有点剧透；传 `.white` 就只有光、不透露档位
    var accent: Color = .white
    @ViewBuilder var back: Back
    @ViewBuilder var front: Front

    var body: some View {
        Flipper(progress: isFlipped ? 1 : 0,
                reduceMotion: reduceMotion,
                cornerRadius: cornerRadius,
                accent: accent,
                back: back,
                front: front)
    }
}

private struct Flipper<Back: View, Front: View>: View, Animatable {

    var progress: Double
    let reduceMotion: Bool
    let cornerRadius: CGFloat
    let accent: Color
    let back: Back
    let front: Front

    /// 默认隔离是 MainActor，而 Animatable 的这条要求是 nonisolated —— 必须显式标
    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    // MARK: - 时间窗口

    /// 把 0→1 的进度切成一段段，每段内部再 0→1
    private func window(_ from: Double, _ to: Double) -> Double {
        min(max((progress - from) / max(to - from, 0.0001), 0), 1)
    }

    /// 缓出：光跑起来时头快尾慢，更像"扫过去"
    private func easeOut(_ t: Double) -> Double { 1 - pow(1 - t, 3) }

    /// 缓入缓出（smoothstep）：**先慢、中间快、再慢** —— 抬升、外晕淡入用这个
    private func smoothstep(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }

    /// 光头行进曲线 —— **起步一小段加速，之后全程匀速，收尾不减速**。
    ///
    ///     v(t)  0 ─↑(0…ramp)─── 匀速 ─────────────── 匀速 ─→ 1
    ///
    /// 为什么不是 `smoothstep`：smoothstep 头尾导数都是 0，再配上一个只到 0.45
    /// 的窗口，整段的后半光就彻底停住了 —— 眼睛看到的就是"最后一段在滞留"。
    /// 为什么收尾也**不减速**：圆环是周期图形，走到 360° 正好接回起点，
    /// 视觉上没有"停下来"这回事；反而一减速就成了新的滞留（验算台第一版就栽在这）。
    /// 停车感交给 `cometOpacity` 的淡出（最后 7%），不是交给速度。
    ///
    /// 归一化：u(0) = 0、u(1) = 1，处处单调递增；匀速段 = 1/(1 - ramp/2) ≈ 1.04 倍平均。
    private func flow(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        let e = min(max(ZW.flipFlowRamp, 0), 0.3)
        guard e > 0 else { return x }
        let v = 1 / (1 - e / 2)                   // 匀速段速度，让总行程正好 1
        if x <= e { return v * x * x / (2 * e) }  // 起步斜边
        return v * (x - e / 2)                    // 之后一路匀速到底
    }

    /// 品质光扫完整圈的进度：0.02 → 1.00 —— **走满整段动画**，一直在流
    private var ringProgress: Double { flow(window(0.02, 1.0)) }

    /// 抬升量。
    /// 和光起跑同一个窗口（0.02→0.45）—— 光绕到一半时卡抬到最高。
    private var lift: Double {
        guard !reduceMotion else { return 0 }
        let up = smoothstep(window(0.02, 0.45))
        let down = window(0.85, 1.0)
        return up * (1 - down)
    }

    /// 翻转角度：0.45→0.95（抬到最高之后才翻），最后 25% 加 3.2° 过冲
    private var rotationAngle: Double {
        guard !reduceMotion else { return 0 }
        let t = window(0.45, 0.95)
        let tail = min(max((t - 0.75) / 0.25, 0), 1)
        return t * 180 + 3.2 * sin(.pi * tail)
    }

    /// 划过的那道"光头"：光扫完就收掉（留下的整圈不消失）
    private var cometOpacity: Double {
        reduceMotion ? 0 : 1 - window(0.93, 1.0)
    }

    /// 整圈光的亮度。
    /// **翻过来之后不消失**：扫的时候最亮，翻到正面后收在 `flipGlowResting` 常亮。
    private var ringOpacity: Double {
        // 没翻开 = 一点光都没有。这里必须是硬 0：光带在 progress 0 时长度为零，
        // 只要透明度不是 0，圆帽就会在卡顶中间留下一个光点。
        guard progress > 0 else { return 0 }
        if reduceMotion {
            // 减弱动态效果：不跑圈，只做整体淡入 → 停在常亮档
            return ZW.flipGlowResting * smoothstep(window(0.10, 0.55))
        }
        let rise = window(0.00, 0.06)         // 起头就亮起来
        let settle = window(0.90, 1.00)       // 收尾才从"扫过最亮"落到常亮
        return ZW.flipGlow * rise * (1 - settle) + ZW.flipGlowResting * settle
    }

    /// 卡外那圈光晕的透明度：跟着翻转升起来，落在 `flipHaloResting` 常亮。
    /// 它比卡内那圈淡得多 —— 卡外是"透出来的一点"，不是第二道光。
    private var haloOpacity: Double {
        let rise = reduceMotion ? window(0.30, 1.00) : window(0.62, 1.00)
        return ZW.flipHaloResting * smoothstep(rise)
    }

    /// 换面：翻转行程的中点（0.45 与 0.95 之间）。那一刻卡片侧对镜头，换面看不见
    private var showsFront: Bool {
        reduceMotion ? progress >= 0.5 : progress >= 0.70
    }

    private var backOpacity: Double {
        reduceMotion ? 1 - progress : (showsFront ? 0 : 1)
    }

    private var frontOpacity: Double {
        reduceMotion ? progress : (showsFront ? 1 : 0)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    // MARK: - 视图

    var body: some View {
        ZStack {
            back.opacity(backOpacity)

            front
                // 卡面先把自己镜像 180°（正投影，不参与透视），外层再转 180° 正好是正的
                .rotation3DEffect(.degrees(reduceMotion ? 0 : 180),
                                  axis: (x: 0, y: 1, z: 0),
                                  perspective: 0)
                .compositingGroup()
                .opacity(frontOpacity)
        }
        .clipShape(shape)
        .background(Color(.secondarySystemGroupedBackground), in: shape)
        // 卡外那圈淡光：画在不透明卡底**后面** → 只在卡片轮廓外面露出来，
        // 卡里一点也不会被冲淡（卡片自己的底和卡面把内侧盖住了）。
        .background { outerHalo }
        .overlay { ring }
        .compositingGroup()

        // 抬升：向上位移 + 轻微放大（"从桌面上被捏起来"）
        .offset(y: -ZW.flipLiftOffset * lift)
        .scaleEffect(1 + ZW.flipLiftScale * lift)

        // 底部阴影：抬起来时拉开变散，落下时收拢
        .shadow(color: Color.black.opacity(0.55 * lift),
                radius: 26 * lift, y: 16 * lift)
        // 品质色的那层光会把阴影也染上一点（只在抬起来时）
        .shadow(color: accent.opacity(0.35 * lift * ringOpacity),
                radius: 18 * lift, y: 4 * lift)

        // 整卡绕 Y 轴转 —— 唯一带透视的一层
        .rotation3DEffect(.degrees(rotationAngle),
                          axis: (x: 0, y: 1, z: 0),
                          perspective: reduceMotion ? 0 : 0.35)
    }

    /// 卡外光晕：一圈外扩的圆角描边 + 模糊。
    ///
    /// 外扩 `ZW.flipHaloInset`（4pt）+ 同量模糊 ≈ 卡外 10pt 的柔光；
    /// 圆角要跟着一起加，不然外圈和卡边的圆角对不上（会出现四个小尖角）。
    private var outerHalo: some View {
        let inset = ZW.flipHaloInset
        return ZWRingSweep(cornerRadius: cornerRadius + inset,
                           inset: -inset,
                           from: 0, to: 1)
            .stroke(accent,
                    style: StrokeStyle(lineWidth: inset * 2, lineCap: .round, lineJoin: .round))
            .blur(radius: inset * 2)
            .opacity(haloOpacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// 周边品质光（卡内那圈）。
    ///
    /// 用 `ZWRing`（**单条连续子路径**）而不是 `RoundedRectangle` ——
    /// 后者 trim 起来会按子路径分段裁，光会断成四块。
    ///
    /// 四层：
    ///   ① 走过的轨迹：把卡"包"起来的光晕（翻完之后这一层常亮）
    ///   ② 拖尾：轨迹末端偏长偏淡的一段
    ///   ③ 中段：品质色，实一点
    ///   ④ 光头：最短最白的一点
    /// ②③④ 长度递减、亮度递增 → 看上去是一条"流过去"的光，不是一坨硬边。
    private var ring: some View {
        let trail = ZWRingSweep(cornerRadius: cornerRadius, inset: 2,
                                from: 0, to: ringProgress)
        let tail = ZWRingSweep(cornerRadius: cornerRadius, inset: 2,
                               from: max(0, ringProgress - 0.26), to: ringProgress)
        let mid = ZWRingSweep(cornerRadius: cornerRadius, inset: 2,
                              from: max(0, ringProgress - 0.15), to: ringProgress)
        let head = ZWRingSweep(cornerRadius: cornerRadius, inset: 2,
                               from: max(0, ringProgress - 0.06), to: ringProgress)

        return ZStack {
            trail
                .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .blur(radius: 6)

            tail
                .stroke(accent.opacity(0.55),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .blur(radius: 5)
                .opacity(cometOpacity)

            mid
                .stroke(accent,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .blur(radius: 3)
                .opacity(cometOpacity)

            head
                .stroke(Color.white.opacity(0.95),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .blur(radius: 1.2)
                .opacity(cometOpacity)
        }
        .opacity(ringOpacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
