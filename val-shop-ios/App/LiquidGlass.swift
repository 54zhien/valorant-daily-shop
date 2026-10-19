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
}
