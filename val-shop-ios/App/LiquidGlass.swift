import SwiftUI

// ============================================================================
//  Liquid Glass 适配层 —— 全项目唯一直接调用 iOS 26 玻璃 API 的文件
// ============================================================================
//
//  ⚠️ 如果 Xcode 报某条 API 找不到 / 签名不对，只改这个文件，不要动 View。
//     下面每个封装都注明了对应的系统能力，方便对照 Apple 文档修。
//
//  用到的 iOS 26 Liquid Glass 能力：
//    · Glass.regular / .clear / .tint(_:) / .interactive(_:)
//    · View.glassEffect(_:in:)
//    · GlassEffectContainer(spacing:)
//    · View.glassEffectID(_:in:) / .glassEffectUnion(id:namespace:)
//    · ButtonStyle.glass / .glassProminent
//    · ToolbarSpacer
//    · View.tabBarMinimizeBehavior(_:)
//    · View.scrollEdgeEffectStyle(_:for:)
//    · Color.mix(with:by:in:)
// ============================================================================

enum ZWGlass {

    /// 统一圆角。想换成 iOS 26 的同心圆角，
    /// 把各处的 `RoundedRectangle(cornerRadius:style:)` 换成 `ConcentricRectangle()` 即可。
    static let panelRadius: CGFloat = 22
    static let cardRadius: CGFloat = 20

    /// 玻璃之间的最小间距：太近会产生光学干扰，Apple 建议 ≥ 20pt
    static let containerSpacing: CGFloat = 22

    /// 给 `.clear` 玻璃用的压暗层透明度（放在内容与玻璃之间）
    /// —— 本项目背景是柔和渐变，走 `.regular` 就够，用不到这个值。
    static let clearDimOpacity: Double = 0.18
}

// MARK: - 面板

extension View {

    /// 给一块内容套上系统玻璃背景。
    /// - Parameters:
    ///   - cornerRadius: 圆角
    ///   - tint: 染色（nil = 系统 `.regular`）
    ///   - interactive: 是否让玻璃对触摸有反应（按钮、可点区域用）
    func zwGlassPanel(cornerRadius: CGFloat = ZWGlass.panelRadius,
                      tint: Color? = nil,
                      interactive: Bool = false) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius,
                                    tint: tint,
                                    interactive: interactive))
    }

    /// 卡片玻璃（比面板多一层品质色染色）
    func zwGlassCard(cornerRadius: CGFloat = ZWGlass.cardRadius,
                     tint: Color? = nil,
                     interactive: Bool = false) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius,
                                    tint: tint,
                                    interactive: interactive))
    }

    /// 小胶囊（账号状态、品质标签之类）
    func zwGlassChip(tint: Color? = nil) -> some View {
        modifier(GlassPanelModifier(cornerRadius: 0,
                                    tint: tint,
                                    interactive: false,
                                    capsule: true))
    }

    /// 让玻璃参与"变形"动画（配合 GlassEffectContainer 使用）
    func zwMorphID(_ id: some Hashable, in namespace: Namespace.ID) -> some View {
        glassEffectID(id, in: namespace)
    }

    /// 滚动容器顶部/底部的柔软渐隐边缘
    func zwScrollEdge(_ edges: Edge.Set = .all) -> some View {
        scrollEdgeEffectStyle(.soft, for: edges)
    }
}

private struct GlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool
    var clear: Bool = false
    var capsule: Bool = false

    func body(content: Content) -> some View {
        if capsule {
            content.glassEffect(glass, in: Capsule())
        } else {
            content.glassEffect(glass,
                                in: RoundedRectangle(cornerRadius: cornerRadius,
                                                     style: .continuous))
        }
    }

    private var glass: Glass {
        var g: Glass = clear ? .clear : .regular
        if let tint { g = g.tint(tint) }
        if interactive { g = g.interactive() }
        return g
    }
}

// MARK: - 按钮

extension View {

    /// 主行动按钮（Liquid Glass 高亮样式）
    func zwProminentButton(tint: Color = .accentColor) -> some View {
        buttonStyle(.glassProminent).tint(tint)
    }

    /// 次要按钮
    func zwGlassButton() -> some View {
        buttonStyle(.glass)
    }

    /// 圆形图标按钮
    func zwCircleIconButton() -> some View {
        buttonStyle(.glass).buttonBorderShape(.circle)
    }
}

// MARK: - 容器

/// 玻璃容器。放进来的多个玻璃元素靠近时会互相融合、并支持 morph 过渡。
struct ZWGlassGroup<Content: View>: View {
    var spacing: CGFloat = ZWGlass.containerSpacing
    @ViewBuilder var content: Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content
        }
    }
}

// MARK: - 背景

/// 品牌背景。玻璃需要底下有内容才看得出来，纯色背景上 Liquid Glass 几乎不可见，
/// 所以铺一层低饱和的 MeshGradient（iOS 18+）。
struct ZWBrandBackdrop: View {
    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0],
            ],
            colors: [
                .zwInk,                  .zwInk,                  .zwInk,
                .zwInk,                  .zwAccent.opacity(0.18), .zwInk,
                .zwInk,                  .zwMint.opacity(0.14),   .zwInk,
            ]
        )
        .ignoresSafeArea()
    }
}

// MARK: - 色板
//
// 直接用系统语义色 / 材质，深浅色自动适配。
// 品牌色只做小面积强调，不做大面积背景。

extension Color {
    /// 掌瓦动态 UI 里的品牌色（#0F1923 / #FF4655 / 青绿点缀）
    static let zwInk = Color(red: 0.059, green: 0.098, blue: 0.137)
    static let zwAccent = Color(red: 1.0, green: 0.275, blue: 0.333)
    static let zwMint = Color(red: 0.0, green: 0.878, blue: 0.776)

    /// 两色混合（系统 API，iOS 18+）
    static func blend(_ a: Color, _ b: Color, by amount: Double) -> Color {
        a.mix(with: b, by: amount)
    }
}
