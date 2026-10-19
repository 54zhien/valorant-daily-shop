// 隔离语义实验台 —— 目标：找出在 App target 那套设置下能编译通过的自定义 Shape 写法。
// 设置复刻：-default-isolation MainActor + -swift-version 6 + strict-concurrency=complete
//           （对应 Xcode 的 SWIFT_DEFAULT_ACTOR_ISOLATION / SWIFT_APPROACHABLE_CONCURRENCY）
//
// 跑法（在 App/_probe 下）：
//   swiftc -typecheck -swift-version 6 -default-isolation MainActor \
//          -strict-concurrency=complete isolation_probe.swift

import Foundation

struct PathStub: Sendable {}
struct RectStub: Sendable, Hashable {}
struct ColorStub: Sendable {}

protocol ShapeStub: Sendable {
    nonisolated func path(in rect: RectStub) -> PathStub
}

// ============================================================================
// ① 切角：**不用 OptionSet**，用纯 struct + Bool 字段
//    path(in:) 里只读**实例**属性 —— 实例属性不报隔离错，静态/协议成员才报。
// ============================================================================

struct ZWCorners: Sendable {
    var topLeading = false
    var topTrailing = false
    var bottomLeading = false
    var bottomTrailing = false

    static let all = ZWCorners(topLeading: true, topTrailing: true,
                               bottomLeading: true, bottomTrailing: true)
    static let diagonal = ZWCorners(topLeading: true, bottomTrailing: true)
}

struct ChamferPlain: ShapeStub {
    let cut: CGFloat
    let corners: ZWCorners

    nonisolated func path(in rect: RectStub) -> PathStub {
        _ = corners.topLeading
        _ = corners.bottomTrailing
        _ = cut
        _ = rect
        return PathStub()
    }
}

// ============================================================================
// ② 对照：非要用 OptionSet，就得把类型本身标成 nonisolated（Swift 6.2 的写法）
// ============================================================================

nonisolated struct ZWCornersSet: OptionSet, Sendable {
    let rawValue: Int
    static let topLeading = ZWCornersSet(rawValue: 1)
    static let all: ZWCornersSet = [.topLeading]
}

struct ChamferOptionSet: ShapeStub {
    let cut: CGFloat
    let corners: ZWCornersSet

    nonisolated func path(in rect: RectStub) -> PathStub {
        _ = corners.contains(.topLeading)
        _ = cut
        return PathStub()
    }
}

// ============================================================================
// ③ token：默认隔离下是 MainActor 静态；加 nonisolated 后到处能用
// ============================================================================

enum Tok {
    // MainActor 隔离（默认）
    static let isolatedNumber: CGFloat = 16
    static let isolatedColor = ColorStub()

    // 显式 nonisolated —— 纯值，没理由挂在 actor 上
    nonisolated static let cut: CGFloat = 16
    nonisolated static let pad: CGFloat = 16
    nonisolated static let board = ColorStub()
}

extension ColorStub {
    nonisolated static let ink = ColorStub()
    static let boardHi = ColorStub()
}

/// 默认参数引用 token —— 这是最容易炸的地方（视图里到处是 `tint: Color = .zwRouge`）
struct Widget {
    var cut: CGFloat = Tok.cut
    var corners: ZWCorners = .all
    var tint: ColorStub = .ink

    // 计算属性 + 可选默认值（ZWActionRow.label 那种用法）
    var label: PathStub {
        _ = cut
        _ = corners
        _ = tint
        return PathStub()
    }
}

struct ActionRowish {
    let title: String
    var tint: ColorStub = .ink
    var action: () -> Void = {}

    var body: PathStub {
        action()
        return PathStub()
    }
}

/// 无参构造 + trailing closure（ZWActionRow(title:) { ... } 的写法）
@MainActor
func useWidgets() {
    _ = Widget()
    _ = Widget(cut: 8, corners: .diagonal, tint: .boardHi)
    _ = Widget().label
    _ = ActionRowish(title: "x") { }
    _ = ActionRowish(title: "x", tint: .boardHi) { }
    _ = Tok.isolatedNumber
    _ = Tok.isolatedColor
}

// 非隔离上下文里用 nonisolated 的 token —— 这就是 Shape 里要的效果
nonisolated func useTokensOffMain() -> CGFloat {
    Tok.cut + Tok.pad
}
