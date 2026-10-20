import SwiftUI

// ============================================================================
//  Liquid Glass —— 现在全部由系统提供，这里不再自己调玻璃 API
// ============================================================================
//
//  按 Apple 文档（HIG Materials / Adopting Liquid Glass）：
//  玻璃是「浮在内容之上的控件层」的材质。系统已经替我们做好了这些：
//
//    · TabBar        —— `TabView` + `Tab`（iOS 26 自带玻璃与 morph）
//    · NavigationBar —— `NavigationStack` + `.navigationTitle`
//    · sheet         —— `.sheet` / `.presentationDetents`
//    · 主要动作按钮   —— `ButtonStyle.glassProminent`（`.buttonStyle(.glassProminent)`）
//    · 次要动作按钮   —— `ButtonStyle.glass`
//    · 滚动边缘       —— `.scrollEdgeEffectStyle(_:for:)`
//    · TabBar 收纳    —— `.tabBarMinimizeBehavior(.onScrollDown)`
//
//  内容层（卡片、列表行、分组容器）**不用玻璃**，用系统语义背景色：
//    `Color(.systemBackground)` / `Color(.secondarySystemGroupedBackground)`
//  —— 这是这一版和上一版最大的不同，也是文档里明确划的那条线。
//
//  所以这个文件只剩一处薄封装。真要自己画玻璃时（比如做浮层）再往这里加，
//  别散到 View 里写 `.glassEffect(...)`。
// ============================================================================

extension View {

    /// 滚动容器顶部/底部的柔软渐隐边缘。
    /// 一个一个页面上手写 `.scrollEdgeEffectStyle(.soft, for:)` 容易漏，
    /// 统一从这里走。
    func zwScrollEdge(_ edges: Edge.Set = .all) -> some View {
        scrollEdgeEffectStyle(.soft, for: edges)
    }

    /// 内容层里**那一块**玻璃：身份条（账号信息）。
    ///
    /// 这是有意的例外 —— 它长得像控件、也确实可点（多角色时点开切换），
    /// 所以用系统原生的 `glassEffect`，而不是 `.zwContentBackground`：
    ///   · `.regular` 是 Apple 给"浮在内容之上的界面元素"的默认厚度
    ///   · `.interactive()` 让它在被按住时有系统的形变/高光反馈
    ///   · 圆角走 `ZW.radiusGlass`（比内容卡更大，玻璃块要更圆）
    ///
    /// 别的卡片、分组、列表行仍然保持不透明内容底 —— 见本文件开头那条线。
    func zwGlassCard(_ radius: CGFloat = ZW.radiusGlass) -> some View {
        glassEffect(.regular.interactive(),
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// 卡牌用的液态玻璃。
    ///
    /// ⚠️ **不用 `glassEffect`**，也不要用 `.ultraThinMaterial`：
    /// 卡牌整张会被 `rotation3DEffect` 翻过来，玻璃那种"折射 + backdrop 采样"的图层
    /// 在 3D 上下文里表现不可靠（翻到侧身时会被压平/闪/留在原地）。
    /// 所以这里用**纯图层**画玻璃：半透明底 + 左上镜面 + 一圈边缘高光。
    /// 它没有模糊，但随 3D 变换完全正常，而且便宜得多。
    ///
    /// - `fill`：先垫一层半透明深底（保证翻牌时不会看穿卡片看到背面），再压白渐变。
    /// - `overlay`：边缘镜面 —— 左上亮、右下收，是"这块是玻璃"最直接的信号。
    func zwCardGlass(_ radius: CGFloat, cornerStyle: RoundedCornerStyle = .circular) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: cornerStyle)
        return self
            .background {
                ZStack {
                    shape.fill(Color(.secondarySystemGroupedBackground).opacity(0.72))
                    shape.fill(
                        LinearGradient(colors: [.white.opacity(0.16),
                                                .white.opacity(0.055),
                                                .white.opacity(0.03)],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing))
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.32),
                                            .white.opacity(0.05),
                                            .white.opacity(0.14)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing),
                    lineWidth: 0.8)
            }
    }
}
