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

    /// 抬升 / 投影 / 透光共用的那条曲线：两端 0，中点 1。
    ///
    /// 用 `sin(π·p)^0.7` 而不是裸 `sin`：指数 < 1 会把中段托住，
    /// 峰值持续得更久 —— 肉眼才看得见"抬起来"这一下。
    private var curve: Double {
        pow(sin(.pi * min(max(progress, 0), 1)), 0.7)
    }

    /// 位移类（抬升、投影）：减弱动态效果时一律关掉
    private var lift: Double { reduceMotion ? 0 : curve }

    /// 亮度类（边缘透光）：只改透明度，不算"动效"，所以减弱动态效果时**保留** ——
    /// 不然那个设置一开，翻牌就变成毫无反馈的硬切（HIG 允许淡入淡出）。
    private var glow: Double { curve }

    private var showsFront: Bool { progress >= 0.5 }

    /// 减弱动态效果时不做 3D，改成纯交叉淡入（进度本身就是 0→1，正好当透明度用）
    private var backOpacity: Double {
        reduceMotion ? 1 - progress : (showsFront ? 0 : 1)
    }

    private var frontOpacity: Double {
        reduceMotion ? progress : (showsFront ? 1 : 0)
    }

    /// 旋转角度。
    /// 末尾有一段 **3.2° 的过冲**：越过 180° 再回正，落定时有"啪"一下的实体感。
    /// （tail 在 p=0.72 起算，p=1 时正好回到 0）
    private var rotationAngle: Double {
        guard !reduceMotion else { return 0 }
        let tail = min(max((progress - 0.72) / 0.28, 0), 1)
        return progress * 180 + 3.2 * sin(.pi * tail)
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

        // 效果 3：边缘透光（中性白 —— 翻之前不透露品质）。
        // 两层：贴边的亮线 + 外侧一圈晕，单靠 1pt 细线在 3D 旋转里根本看不见。
        .overlay {
            ZStack {
                shape
                    .strokeBorder(Color.white.opacity(ZW.flipGlow), lineWidth: 2)
                    .blur(radius: 2.5)
                shape
                    .stroke(Color.white.opacity(ZW.flipGlow * 0.55), lineWidth: 6)
                    .blur(radius: 9)
            }
            .opacity(glow)
            .allowsHitTesting(false)
        }
        .compositingGroup()

        // 效果 1：抬升 + 投影（像把卡从桌面上捏起来）
        .scaleEffect(reduceMotion ? 1 : 1 + ZW.flipLift * lift)
        .shadow(color: Color.black.opacity(0.60 * lift),
                radius: 28 * lift, y: 14 * lift)

        // 整卡绕 Y 轴转 —— 唯一带透视的一层
        .rotation3DEffect(.degrees(rotationAngle),
                          axis: (x: 0, y: 1, z: 0),
                          perspective: reduceMotion ? 0 : 0.35)
    }
}
