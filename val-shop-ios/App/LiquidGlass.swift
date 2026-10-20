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
}
