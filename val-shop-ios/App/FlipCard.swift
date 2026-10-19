import SwiftUI

// ============================================================================
//  翻牌容器 —— **一个进度值驱动全部效果**
// ============================================================================
//
//  之前是"旋转一段 + 延迟换面一段"拼起来的：换面时刻靠 `delay(0.25)` 猜，
//  曲线一换就错位（表现就是内容"啪"地跳出来）。现在只有一个 `progress: 0→1`，
//  其余全是它的函数：
//
//     rotationY   = progress × 180°              （减弱动态效果时恒为 0）
//     换面         = progress ≥ 0.5                ← 0.5 时卡片必然侧对镜头，数学上不会错
//     抬升 scale   = 1 + 0.06 × sin(π·p)          ← 效果 1
//     投影          = sin(π·p)                    ← 效果 1
//     边缘透光      = 0.55 × sin(π·p)              ← 效果 3（**中性白，不剧透品质**）
//
//  `sin(π·p)` 这条曲线两端为 0、中点为 1，所以三个效果天生同步：
//  抬起来的同时边缘亮、投影变散，翻到正面时全部归零 —— 不需要各自对时间。
//
//  可逆：翻到一半再点，`animatableData` 从当前值往回走，不会跳。
//
//  ⚠️ `animatableData` 必须显式 `nonisolated`
//     本项目默认隔离是 MainActor，Animatable 的这个要求是 nonisolated 的；
//     不标会报 "conformance … crosses into main actor-isolated code"。
//     验算台：probe/animatable_probe.swift（三种写法 + 对照组，Windows 上就能跑）。
// ============================================================================

struct FlipCard<Back: View, Front: View>: View {

    var isFlipped: Bool
    var reduceMotion: Bool
    var cornerRadius: CGFloat = ZW.radiusCard
    @ViewBuilder var back: Back
    @ViewBuilder var front: Front

    var body: some View {
        Flipper(progress: isFlipped ? 1 : 0,
                reduceMotion: reduceMotion,
                cornerRadius: cornerRadius,
                back: back,
                front: front)
    }
}

private struct Flipper<Back: View, Front: View>: View, Animatable {

    var progress: Double
    let reduceMotion: Bool
    let cornerRadius: CGFloat
    let back: Back
    let front: Front

    /// 默认隔离是 MainActor，而 Animatable 的这条要求是 nonisolated —— 必须显式标
    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    /// 抬升 / 投影 / 透光共用的那条曲线：两端 0，中点 1
    private var swell: Double {
        reduceMotion ? 0 : sin(.pi * min(max(progress, 0), 1))
    }

    private var showsFront: Bool { progress >= 0.5 }

    /// 减弱动态效果时不做 3D，改成纯交叉淡入（进度本身就是 0→1，正好当透明度用）
    private var backOpacity: Double {
        reduceMotion ? 1 - progress : (showsFront ? 0 : 1)
    }

    private var frontOpacity: Double {
        reduceMotion ? progress : (showsFront ? 1 : 0)
    }

    var body: some View {
        ZStack {
            back
                .opacity(backOpacity)

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

        // 效果 3：边缘透光。中性白 —— 翻之前不透露品质（不剧透）
        .overlay {
            shape
                .strokeBorder(Color.white.opacity(ZW.flipGlow), lineWidth: 1.5)
                .blur(radius: 3)
                .opacity(swell)
                .allowsHitTesting(false)
        }
        .compositingGroup()

        // 效果 1：抬升 + 投影（像把卡从桌面上捏起来）
        .scaleEffect(reduceMotion ? 1 : 1 + ZW.flipLift * swell)
        .shadow(color: Color.black.opacity(0.45 * swell),
                radius: 18 * swell, y: 10 * swell)

        // 整卡绕 Y 轴转 —— 唯一带透视的一层
        .rotation3DEffect(.degrees(reduceMotion ? 0 : progress * 180),
                          axis: (x: 0, y: 1, z: 0),
                          perspective: reduceMotion ? 0 : 0.35)
    }
}
