import SwiftUI

// ============================================================================
//  翻牌容器 —— 一个进度值驱动一整段编排
// ============================================================================
//
//  点击之后按顺序发生这些事（不是同时）：
//
//     p 0.00 ─ 0.04   品质细线亮起（很快，但不硬切）
//     p 0.02 ─ 0.48   细线沿卡牌**外面**绕一圈：**慢 → 快 → 慢**（smoothstep），
//                     走到 0.48 正好合拢。线细（1.5pt）、走在卡外 2.5pt 处。
//     p 0.44 ─ 0.50   光头收线 —— 合拢处不留一颗亮点
//     p 0.46 ─ 0.58   细线开始发光（光晕 0 → 峰值）**同时**卡牌抬到最高
//     p 0.58 ─ 0.92   翻转（抬着翻），末尾 3.2° 过冲再回正
//     p 0.75          换面（翻转行程的中点 → 卡片侧对镜头，看不见）
//     p 0.92 ─ 1.00   落下；光晕从峰值收到 `flipRestGlow = 0.40`
//                     —— **比裸线亮一点点**，不是回到"只有一根线"那种状态
//
//  实现上仍然只有一个 `progress: 0→1`，上面每个效果都是它的一段窗口函数
//  （`window(p, from:to:)`）。这样就永远不会有"谁先谁后对不齐"的问题 ——
//  想改节奏只改窗口的边界数字。
//
//  顺序上的硬规矩：
//    ① **细线走完一圈，才开始发光**（光晕窗口从 0.46 起，线在 0.48 才合拢）
//    ② **卡牌抬起之后才翻**（抬升 0.46→0.58，翻转 0.58 才起步）
//    ③ **没翻开的卡一点光都没有**（细线零长度不画 + 两个 opacity 在 0 处硬归零）
//    窗口的先后关系由 probe/flow_probe.swift 逐条守着。
//
//  ⚠️ `animatableData` 必须显式 `nonisolated`
//     本项目默认隔离是 MainActor，Animatable 的这个要求是 nonisolated 的。
//     验算台：probe/animatable_probe.swift（三种写法 + 一组会失败的对照）。
//
//  ⚠️ 光晕最多外扩 `flipLineInset + flipGlowBand/2 + flipGlowBlur` ≈ 12pt，
//     所以 2×2 卡阵的间距用了 `ZW.cardGap = 20`：相邻两卡各留 10pt，
//     光不会糊到隔壁卡上。想加粗光晕，先把 cardGap 一起放大。
//
//  ⚠️ 细线走的是**卡外**（`ZWRingSweep` 的 inset 传负值 = 往外扩）。
//     传正值就缩到卡里面去了 —— 那是上一版的做法，和"包在外面"是两回事。
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

    /// 缓入缓出（smoothstep）：**先慢、中间快、再慢** —— 细线绕圈就是这个节奏
    private func smoothstep(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }

    // MARK: - 光效

    /// 细线扫过的角度（0…1 圈）：0.02 → 0.48，慢 → 快 → 慢
    private var ringProgress: Double {
        reduceMotion ? 1 : smoothstep(window(0.02, 0.48))
    }

    /// 光头：最后一小段比线更亮一点，让"在跑"这件事看得出来；
    /// 合拢时就收掉（0.44→0.50），免得圈闭上了还挂一颗亮点
    private var cometOpacity: Double {
        reduceMotion ? 0 : 1 - window(0.44, 0.50)
    }

    /// 细线本身的透明度：点下去就亮起来，之后一直留着
    private var lineOpacity: Double {
        guard progress > 0 else { return 0 }
        return ZW.flipLineOpacity * (reduceMotion ? 1 : window(0.00, 0.04))
    }

    /// 线外面那圈光晕：**转完一圈才开始发光**（0.46 起），落地时收到常亮档。
    private var glowOpacity: Double {
        guard progress > 0 else { return 0 }
        if reduceMotion {
            return ZW.flipRestGlow * smoothstep(window(0.10, 0.60))
        }
        let up = smoothstep(window(0.46, 0.58))     // 合拢 → 抬起：这一段里亮起来
        let down = window(0.90, 1.00)               // 落下去的时候减弱
        return ZW.flipGlowPeak * up * (1 - down) + ZW.flipRestGlow * up * down
    }

    // MARK: - 抬升 / 翻转

    /// 抬升量：0.46 → 0.58 抬到最高（细线刚发光、卡被捏起来），0.92 之后落回
    private var lift: Double {
        guard !reduceMotion else { return 0 }
        let up = smoothstep(window(0.46, 0.58))
        let down = window(0.92, 1.0)
        return up * (1 - down)
    }

    /// 翻转角度：0.58→0.92（抬到最高之后才翻），末尾 25% 加 3.2° 过冲再回正
    private var rotationAngle: Double {
        guard !reduceMotion else { return 0 }
        let t = window(0.58, 0.92)
        let tail = min(max((t - 0.75) / 0.25, 0), 1)
        return t * 180 + 3.2 * sin(.pi * tail)
    }

    /// 换面：翻转行程的中点（0.58 与 0.92 之间）。那一刻卡片侧对镜头，换面看不见
    private var showsFront: Bool {
        reduceMotion ? progress >= 0.5 : progress >= 0.75
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
        // 光晕画在不透明卡底**后面** → 只露在卡外，卡里一点不被冲淡
        .background { edgeGlow }
        // 细线画在卡外（overlay 不受 clipShape 影响，负 inset 会往外扩）
        .overlay { edgeLine }
        .compositingGroup()

        // 抬升：向上位移 + 轻微放大（"从桌面上被捏起来"）
        .offset(y: -ZW.flipLiftOffset * lift)
        .scaleEffect(1 + ZW.flipLiftScale * lift)

        // 底部阴影：抬起来时拉开变散，落下时收拢
        .shadow(color: Color.black.opacity(0.55 * lift),
                radius: 26 * lift, y: 16 * lift)
        // 品质色的那层光会把阴影也染上一点（只在发光时）
        .shadow(color: accent.opacity(0.30 * lift * glowOpacity),
                radius: 18 * lift, y: 4 * lift)

        // 整卡绕 Y 轴转 —— 唯一带透视的一层
        .rotation3DEffect(.degrees(rotationAngle),
                          axis: (x: 0, y: 1, z: 0),
                          perspective: reduceMotion ? 0 : 0.35)
    }

    /// 卡牌**外面**那一圈品质细线（+ 一小段光头）。
    ///
    /// `inset` 传负值 = 往外扩：线走在卡轮廓外 `ZW.flipLineInset` 处，
    /// 圆角也跟着 +同样的值，外圈和卡边的圆角才对得上（不然四个角会尖出来）。
    private var edgeLine: some View {
        let radius = cornerRadius + ZW.flipLineInset
        let inset = -ZW.flipLineInset
        let line = ZWRingSweep(cornerRadius: radius, inset: inset,
                               from: 0, to: ringProgress)
        let head = ZWRingSweep(cornerRadius: radius, inset: inset,
                               from: max(0, ringProgress - 0.08), to: ringProgress)

        return ZStack {
            line.stroke(accent,
                        style: StrokeStyle(lineWidth: ZW.flipLineWidth,
                                           lineCap: .round, lineJoin: .round))

            head.stroke(Color.white.opacity(0.9),
                        style: StrokeStyle(lineWidth: ZW.flipLineWidth + 0.6,
                                           lineCap: .round, lineJoin: .round))
                .blur(radius: 0.8)
                .opacity(cometOpacity)
        }
        .opacity(lineOpacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 线外面那圈光晕：转完一圈才亮起来，落地后收到 `flipRestGlow`。
    /// 画在卡底后面 → 只在卡外露出来，所以"包在外面"这件事是几何保证的，不靠调透明度。
    private var edgeGlow: some View {
        ZWRingSweep(cornerRadius: cornerRadius + ZW.flipLineInset,
                    inset: -ZW.flipLineInset,
                    from: 0, to: 1)
            .stroke(accent,
                    style: StrokeStyle(lineWidth: ZW.flipGlowBand,
                                       lineCap: .round, lineJoin: .round))
            .blur(radius: ZW.flipGlowBlur)
            .opacity(glowOpacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
