import SwiftUI

// ============================================================================
//  翻牌容器 —— 一个进度值驱动一整段编排
// ============================================================================
//
//  点击之后按顺序发生这些事（不是同时）：
//
//     p 0.00 ─ 0.04   品质细线亮起（很快，但不硬切）
//     p 0.02 ─ 0.55   细线**贴着卡边**绕一圈：慢 → 快 → 慢（smoothstep），
//                     0.55 正好合拢（约 900ms —— 这一版特意放慢了）。线细（0.6pt）、
//                     基本压在轮廓上（外扩 0.5pt）；转动时线外已经带着一层薄晕染光。
//     p 0.49 ─ 0.56   光头收线（合拢处不留亮点）
//     p 0.35 ─ 0.55   卡牌向上升起，**抬起动作正好在细线合拢那一刻结束**；
//                     同一段窗口里光晕从"薄晕"加重到峰值 —— 抬起 + 翻牌这一段光最重。
//     p 0.58 ─ 0.84   翻转（抬着翻），末尾 3.2° 过冲再回正
//     p 0.71          换面（翻转行程的中点 → 卡片侧对镜头，看不见）
//     p 0.84 ─ 1.00   **落下**（约 270ms）。
//                     翻完之后细线的不透明度开始下降、光晕也开始减弱，两者都在
//                     **落地那一刻**正好走完 —— 细线停在 `flipLineRestOpacity`（0.55），
//                     光晕停在 `flipRestGlow`（0.35）：减弱，但不是消失。
//
//  实现上仍然只有一个 `progress: 0→1`，上面每个效果都是它的一段窗口函数
//  （`window(p, from:to:)`）。这样就永远不会有"谁先谁后对不齐"的问题 ——
//  想改节奏只改窗口的边界数字。
//
//  顺序上的硬规矩（probe/flow_probe.swift 守着）：
//    ① **抬起动作结束 == 细线合拢**（两个窗口都是 0.55 收口），之后才翻
//    ② 细线 / 光晕的**减弱窗口 == 落下窗口**（0.84→1.00），不是一下子变暗
//    ③ 没翻开的卡一点光都没有（零长度 sweep 不画 + opacity 在 0 处硬归零）
//
//  ⚠️ `animatableData` 必须显式 `nonisolated`
//     本项目默认隔离是 MainActor，Animatable 的这个要求是 nonisolated 的。
//     验算台：probe/animatable_probe.swift（三种写法 + 一组会失败的对照）。
//
//  ⚠️ 光晕最多外扩 `flipGlowBand/2 + flipGlowBlur` ≈ 13pt，
//     所以 2×2 卡阵的间距用了 `ZW.cardGap = 20`：相邻两卡各留 10pt。
//     想再加粗光晕，先把 cardGap 一起放大。
//
//  ⚠️ 细线走的是**卡边**（`ZWRingSweep` 的 inset 传负值 = 往外扩）。
//     传正值就缩到卡里面去了 —— 那是更早一版的做法。
// ============================================================================

struct FlipCard<Back: View, Front: View>: View {

    var isFlipped: Bool
    var reduceMotion: Bool
    var cornerRadius: CGFloat = ZW.radiusCard
    /// 细线 / 光晕的颜色。传品质色 = 有点剧透；传 `.white` 就只有光、不透露档位
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

    /// 缓入缓出（smoothstep）：**先慢、中间快、再慢**
    private func smoothstep(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }

    // MARK: - 光效

    /// 细线扫过的角度（0…1 圈）：0.02 → 0.46，慢 → 快 → 慢
    private var ringProgress: Double {
        reduceMotion ? 1 : smoothstep(window(0.02, 0.55))
    }

    /// 光头：最后一小段更白一点；合拢时就收掉（0.44→0.50）
    private var cometOpacity: Double {
        reduceMotion ? 0 : 1 - window(0.49, 0.56)
    }

    /// 细线的不透明度。
    /// 翻到正面之后（0.84）开始降，**落地那一刻降到 0.55** —— 不是消失。
    private var lineOpacity: Double {
        guard progress > 0 else { return 0 }
        let rise = reduceMotion ? 1 : window(0.00, 0.04)
        let down = smoothstep(window(0.84, 1.00))
        return (ZW.flipLineOpacity * (1 - down) + ZW.flipLineRestOpacity * down) * rise
    }

    /// 线外面的晕染光。
    /// 转动时先有一层薄晕（0.35），抬起 → 翻转期间加重到峰值，落地时**渐弱**到常亮档。
    private var glowOpacity: Double {
        guard progress > 0 else { return 0 }
        if reduceMotion {
            return ZW.flipRestGlow * smoothstep(window(0.10, 0.60))
        }
        let thin = ZW.flipGlowDuringSweep * window(0.00, 0.10)   // 转动时的薄晕
        let heavy = smoothstep(window(0.35, 0.55))               // 抬起时加重
        let down = smoothstep(window(0.84, 1.00))                // 落下时减弱
        let lit = thin + (ZW.flipGlowPeak - thin) * heavy
        return lit * (1 - down) + ZW.flipRestGlow * down
    }

    // MARK: - 抬升 / 翻转

    /// 抬升量：0.35 → 0.55 升起（**0.55 正好到顶，也就是细线合拢那一刻**），
    /// 0.84 之后落回 —— 光也是在这一段里减弱的。
    private var lift: Double {
        guard !reduceMotion else { return 0 }
        let up = smoothstep(window(0.35, 0.55))
        let down = smoothstep(window(0.84, 1.00))
        return up * (1 - down)
    }

    /// 翻转角度：0.58→0.84（抬起结束、停一拍再翻），末尾 25% 加 3.2° 过冲再回正
    private var rotationAngle: Double {
        guard !reduceMotion else { return 0 }
        let t = window(0.58, 0.84)
        let tail = min(max((t - 0.75) / 0.25, 0), 1)
        return t * 180 + 3.2 * sin(.pi * tail)
    }

    /// 换面：翻转行程的中点（0.58 与 0.84 之间）= 0.71
    private var showsFront: Bool {
        reduceMotion ? progress >= 0.5 : progress >= 0.71
    }

    private var backOpacity: Double {
        reduceMotion ? 1 - progress : (showsFront ? 0 : 1)
    }

    private var frontOpacity: Double {
        reduceMotion ? progress : (showsFront ? 1 : 0)
    }

    /// ⚠️ 必须是 `.circular`：`ZWRingSweep` 画的是**圆弧**圆角，
    /// 卡牌用 `.continuous`（squircle）的话，圆弧在 45° 处会切进卡片里 ——
    /// 表现就是"边线没贴住卡、四角圆角看着小了"。两个形状必须是同一种。
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
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
        // 卡面：Apple 液态玻璃（取代原来的不透明分组底），见 LiquidGlass.zwCardGlass
        .zwCardGlass(cornerRadius, cornerStyle: .circular)
        // 晕染光画在玻璃**后面**：玻璃是半透的，所以边缘会透进一点点光 ——
        // 这正是玻璃该有的样子；要高对比就把 edgeGlow 的不透明度调回去。
        .background { edgeGlow }
        // 细线画在卡边（overlay 不受 clipShape 影响，负 inset 会往外扩）
        .overlay { edgeLine }
        .compositingGroup()

        // 抬升：向上位移 + 轻微放大（"从桌面上被捏起来"）
        .offset(y: -ZW.flipLiftOffset * lift)
        .scaleEffect(1 + ZW.flipLiftScale * lift)

        // 底部阴影：抬起来时拉开变散，落下时收拢
        .shadow(color: Color.black.opacity(0.55 * lift),
                radius: 26 * lift, y: 16 * lift)
        // 品质色的那层光会把阴影也染上一点（发光时）
        .shadow(color: accent.opacity(0.35 * lift * glowOpacity),
                radius: 18 * lift, y: 4 * lift)

        // 整卡绕 Y 轴转 —— 唯一带透视的一层
        .rotation3DEffect(.degrees(rotationAngle),
                          axis: (x: 0, y: 1, z: 0),
                          perspective: reduceMotion ? 0 : 0.35)
    }

    /// 贴着卡边的那根品质细线（+ 一小段更白的光头）。
    ///
    /// `inset` 传负值 = 往外扩 `ZW.flipLineInset`（0.5pt，基本压在轮廓上）。
    /// 圆角跟着 +同样的值，外圈和卡边的圆角才对得上。
    private var edgeLine: some View {
        let radius = cornerRadius + ZW.flipLineInset
        let inset = -ZW.flipLineInset
        let line = ZWRingSweep(cornerRadius: radius, inset: inset,
                               from: 0, to: ringProgress)
        let head = ZWRingSweep(cornerRadius: radius, inset: inset,
                               from: max(0, ringProgress - 0.07), to: ringProgress)

        return ZStack {
            line.stroke(accent,
                        style: StrokeStyle(lineWidth: ZW.flipLineWidth,
                                           lineCap: .round, lineJoin: .round))

            head.stroke(Color.white.opacity(0.9),
                        style: StrokeStyle(lineWidth: ZW.flipLineWidth + 0.5,
                                           lineCap: .round, lineJoin: .round))
                .blur(radius: 0.5)
                .opacity(cometOpacity)
        }
        .opacity(lineOpacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 线外面那层晕染光。
    ///
    /// **跟着细线走**（0 → ringProgress），不是一上来就整圈亮：
    /// 转动时是线后面拖着的一段柔光，合拢之后才是一整圈。
    /// 画在卡底后面 → 只在卡外露出来。
    private var edgeGlow: some View {
        let radius = cornerRadius + ZW.flipLineInset
        let inset = -ZW.flipLineInset
        let trail = ZWRingSweep(cornerRadius: radius, inset: inset,
                                from: 0, to: ringProgress)
        let head = ZWRingSweep(cornerRadius: radius, inset: inset,
                               from: max(0, ringProgress - 0.06), to: ringProgress)

        return ZStack {
            // 宽柔层：铺开的那片光
            trail.stroke(accent,
                         style: StrokeStyle(lineWidth: ZW.flipGlowBand,
                                            lineCap: .round, lineJoin: .round))
                .blur(radius: ZW.flipGlowBlur)

            // 紧光层：贴着细线再压一层，翻转那一下的"重"主要来自它
            trail.stroke(accent,
                         style: StrokeStyle(lineWidth: ZW.flipGlowCoreBand,
                                            lineCap: .round, lineJoin: .round))
                .blur(radius: ZW.flipGlowCoreBlur)

            // 光头自己那点光，转起来才有"火头"的感觉
            head.stroke(Color.white,
                        style: StrokeStyle(lineWidth: ZW.flipGlowBand * 0.6,
                                           lineCap: .round, lineJoin: .round))
                .blur(radius: 3)
                .opacity(cometOpacity * 0.85)
        }
        .opacity(glowOpacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
