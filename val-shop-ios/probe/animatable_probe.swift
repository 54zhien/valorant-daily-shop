// 验证：本项目默认隔离 = MainActor 时，Animatable 这类 nonisolated 要求怎么写
//
// 场景：翻牌容器要 conform 到 Animatable（SwiftUI），它的 animatableData
// 是 nonisolated 要求，而 body / 其它成员在 MainActor 上。
//
// 跑法（Windows 就能跑，不需要 SwiftUI）：
//   swiftc -typecheck -swift-version 6 -default-isolation MainActor `
//          -strict-concurrency=complete isolation_probe.swift

import Foundation

// 用一个自家协议模拟 SwiftUI.Animatable：同样是 nonisolated 要求
protocol FakeAnimatable {
    nonisolated var animatableData: Double { get set }
}

// ① 只把成员标 nonisolated
struct VariantA: FakeAnimatable {
    var progress: Double
    let label: String

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    @MainActor
    func describe() -> String { "\(label) \(progress)" }
}

// ② 整个类型标 nonisolated，需要隔离的成员再显式标回 MainActor
nonisolated struct VariantB: FakeAnimatable {
    var progress: Double
    let label: String

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    @MainActor
    func describe() -> String { "\(label) \(progress)" }
}

// ③ 对照：完全不标，应该报错（证明这个坑是真的）
#if PROBE_EXPECT_FAILURE
struct VariantBad: FakeAnimatable {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
}
#endif

@MainActor
func check() {
    var a = VariantA(progress: 0, label: "A")
    a.animatableData = 0.5
    var b = VariantB(progress: 0, label: "B")
    b.animatableData = 0.5
    print("A=\(a.describe())  B=\(b.describe())")
}

check()
print("✓ 编译通过")
