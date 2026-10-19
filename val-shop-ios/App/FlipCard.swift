import SwiftUI

// ============================================================================
//  翻牌容器 —— 一个进度值驱动一整段编排
// ============================================================================
//
//  点击之后按顺序发生五件事（不是同时）：
//
//     p 0.00 ─ 0.30   品质光沿卡牌边缘跑一圈，把卡"包"起来
//     p 0.02 ─ 0.30   卡牌向顶部抬升，底部阴影拉开、变散
//     p 0.32 ─ 0.88   翻转（抬着翻），末尾 3.2° 过冲再回正
//     p 0.64          换面（正好是翻转行程的中点 → 卡片侧对镜头，看不见）
//     p 0.82 ─ 1.00   落下，阴影收拢，品质光淡出
//
//  实现上仍然只有一个 `progress: 0→1`，上面每个效果都是它的一段窗口函数
//  （`window(p, from:to:)`）。这样就永远不会有"谁先谁后对不齐"的问题 ——
//  想改节奏只改窗口的边界数字。
//
//  ⚠️ `animatableData` 必须显式 `nonisolated`
//     本项目默认隔离是 MainActor，Animatable 的这个要求是 nonisolated 的。
//     验算台：probe/animatable_probe.swift（三种写法 + 一组会失败的对照）。
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

    /// 品质光走完一圈的进度
    private var ringProgress: Double { easeOut(window(0.02, 0.30)) }

    /// 抬升量：0.02→0.30 起来，0.82→1.0 落下
    private var lift: Double {
        guard !reduceMotion else { return 0 }
        let up = easeOut(window(0.02, 0.30))
        let down = window(0.82, 1.0)
        return up * (1 - down)
    }

    /// 翻转角度：0.32→0.88 转完，最后 25% 加 3.2° 过冲
    private var rotationAngle: Double {
        guard !reduceMotion else { return 0 }
        let t = window(0.32, 0.88)
        let tail = min(max((t - 0.75) / 0.25, 0), 1)
        return t * 180 + 3.2 * sin(.pi * tail)
    }

    /// 光的存在感：跑圈时最强，落下时淡出
    private var ringOpacity: Double {
        if reduceMotion {
            // 减弱动态效果：不跑圈，改成整体淡入淡出（只有透明度变化）
            return sin(.pi * min(max(progress, 0), 1))
        }
        return 1 - window(0.82, 0.96)
    }

    /// 换面：翻转行程的中点。那一刻卡片侧对镜头，换面看不见
    private var showsFront: Bool {
        reduceMotion ? progress >= 0.5 : progress >= 0.60
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

    /// 周边品质光：一段亮光沿边缘跑一圈，走过的部分留下一圈包住卡牌的光晕
    private var ring: some View {
        ZStack {
            // 走过的轨迹 —— 把卡"包"起来的那层
            shape
                .trim(from: 0, to: ringProgress)
                .stroke(accent.opacity(0.55), lineWidth: 4)
                .blur(radius: 7)

            // 跑动的光头 —— 一段短亮线
            shape
                .trim(from: max(0, ringProgress - 0.22), to: ringProgress)
                .stroke(Color.white.opacity(0.95), lineWidth: 2)
                .blur(radius: 1.2)

            // 光头自己也带一层品质色的晕
            shape
                .trim(from: max(0, ringProgress - 0.22), to: ringProgress)
                .stroke(accent, lineWidth: 3.5)
                .blur(radius: 5)
        }
        .opacity(ringOpacity * ZW.flipGlow)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
