// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ZhangwaKit",
    // 协议层不依赖任何 UI 框架，最低版本保持宽松，
    // 这样 App 端升到 iOS 26 也不影响它被复用（以后做个 CLI / Widget 也能用）。
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "ZhangwaKit", targets: ["ZhangwaKit"]),
    ],
    targets: [
        .target(
            name: "ZhangwaKit",
            path: "Sources/ZhangwaKit",
            swiftSettings: [
                // Swift 6 语言模式：严格并发检查全开。
                // 作为 libray 不用 MainActor-by-default（那是 App target 的做法），
                // 需要隔离的地方显式标 @MainActor。
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "ZhangwaKitTests",
            dependencies: ["ZhangwaKit"],
            path: "Tests/ZhangwaKitTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
