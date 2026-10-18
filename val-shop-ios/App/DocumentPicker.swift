import SwiftUI
import UIKit
import UniformTypeIdentifiers

// ============================================================================
//  文件选择器
// ============================================================================
//
//  为什么不用 SwiftUI 的 `.fileImporter`：
//    它有已知问题 —— 选择器弹出来但选完之后回调不触发 / 拿到空 URL。
//
//  为什么也不是简单地包一层 UIViewControllerRepresentable 丢进 .sheet：
//    设置页自己就是从商店页弹出来的 sheet，再往里弹 .sheet 就成了**嵌套 sheet**，
//    iOS 上这种呈现本来就不稳（第二个 sheet 可能根本不出现，或者出现但回调丢失）。
//
//  所以这里直接从**最上层的 UIViewController** 上 present，
//  绕开所有 SwiftUI 呈现逻辑，也不管外层套了几层 sheet。
//
//  `asCopy: true` 让系统把文件复制到 App 沙盒里再给我们，
//  不需要自己处理 security-scoped resource，也绕开跨 App 沙盒的坑。
// ============================================================================

enum DocumentPicker {

    /// 强引用住 delegate —— UIDocumentPickerViewController 的 delegate 是 weak，
    /// 不持有的话会被立刻释放，表现为「选完没反应」。
    @MainActor private static var activeCoordinator: Coordinator?

    /// 弹出文件选择器。
    /// - Parameters:
    ///   - contentTypes: 默认 `.item`（任意文件）。**不要用白名单** ——
    ///     类型对不上时「文件」App 会把文件置灰，用户根本点不动。
    ///   - onPick: 选完回调。URL 已落在 App 沙盒内，可直接读。
    ///   - onCancel: 用户取消时回调。
    @MainActor
    static func present(contentTypes: [UTType] = [.item],
                        onPick: @escaping (URL) -> Void,
                        onCancel: (() -> Void)? = nil) {
        guard let host = topViewController() else {
            onCancel?()
            return
        }

        let coordinator = Coordinator(
            onPick: { url in
                activeCoordinator = nil
                onPick(url)
            },
            onCancel: {
                activeCoordinator = nil
                onCancel?()
            })
        activeCoordinator = coordinator

        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: contentTypes,
            asCopy: true)
        picker.delegate = coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true

        host.present(picker, animated: true)
    }

    /// 找到当前最上层的 view controller（穿透已经 present 出来的那些）
    @MainActor
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let window = scenes
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? scenes.first?.windows.first

        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        // 如果最上层是导航/标签容器，继续往里找
        while true {
            if let nav = top as? UINavigationController, let v = nav.visibleViewController {
                top = v
            } else if let tab = top as? UITabBarController, let v = tab.selectedViewController {
                top = v
            } else {
                break
            }
        }
        return top
    }

    // MARK: - delegate

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (URL) -> Void
        private let onCancel: (() -> Void)?

        init(onPick: @escaping (URL) -> Void, onCancel: (() -> Void)?) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        /// iOS 14+ 的正确回调。
        /// 不要再实现已废弃的 `didPickDocumentAt` —— 两个都写会被调用两次。
        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onCancel?()
                return
            }
            onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel?()
        }
    }
}
