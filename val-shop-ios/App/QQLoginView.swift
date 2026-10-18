import SwiftUI
import WebKit
import ZhangwaKit

// ============================================================================
//  QQ 扫码登录界面
// ============================================================================
//
//  和微信那边最大的区别：**大部分活儿 QQ 自己干**。
//
//  QQ 的 m_authorize 页面自己会渲染二维码、自己做"已扫描/已过期"的 UI、
//  自己轮询状态。我们只要：
//
//      算 sign → 拼 URL → 塞进 WKWebView → 截 auth:// 回调 → 换登录态
//
//  所以这个文件主体就是一个 WKWebView 包装 + 一个回调拦截。
//
//  ⚠️ 回调是 `auth://tauth.qq.com/#access_token=…`，值在 **fragment** 里。
//     WKWebView 的 decidePolicyFor 能拿到完整 URL（含 fragment），
//     直接交给 Kit 的 parseCallback 就行。
// ============================================================================

struct QQLoginView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var login = QQLogin()
    @State private var stage: QQLogin.Stage = .idle
    @State private var url: URL?
    @State private var reloadToken = UUID()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let url {
                    QQWebView(url: url,
                              reloadToken: reloadToken,
                              onCallback: { callback in
                                  login.complete(with: callback)
                              },
                              onLoaded: {
                                  if stage == .loading || stage == .idle {
                                      login.markWaiting()
                                  }
                              },
                              onFailed: { msg in
                                  stage = .failed(msg)
                              })
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    ProgressView("正在准备…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                statusBar
            }
            .background(ZWBrandBackdrop())
            .navigationTitle("QQ 扫码登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        login.markCancelled()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        reloadToken = UUID()
                        stage = .loading
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .onAppear { wire() }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if stage.isBusy {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: icon)
                    .foregroundStyle(color)
            }
            Text(stage.text)
                .font(.callout)
                .foregroundStyle(color)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var icon: String {
        switch stage {
        case .success:   return "checkmark.circle.fill"
        case .failed:    return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle"
        case .waiting:   return "qrcode"
        default:         return "hourglass"
        }
    }

    private var color: Color {
        switch stage {
        case .success: return .green
        case .failed:  return .orange
        default:       return .secondary
        }
    }

    private func wire() {
        login.onStageChange = { s in
            withAnimation(.snappy) { stage = s }
        }
        login.onSession = { session in
            model.adopt(session)
            Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                dismiss()
            }
        }
        // 每次打开都重新算 time + sign —— 服务端会校验时效性
        url = login.authorizeURL(time: QQLogin.nowTimestamp())
        login.markLoading()
    }
}

// MARK: - WKWebView 包装

/// 只做两件事：加载 URL，拦截 auth:// 回调。
struct QQWebView: UIViewRepresentable {
    let url: URL
    /// 变了就重新加载（点"刷新"时）
    let reloadToken: UUID
    let onCallback: (URL) -> Void
    let onLoaded: () -> Void
    let onFailed: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCallback: onCallback, onLoaded: onLoaded, onFailed: onFailed)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // QQ 的登录页会开自己的小窗做校验，给它留个口子，否则可能白屏
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        // 用移动端 UA —— 服务端会据此决定渲染哪套页面
        config.applicationNameForUserAgent = "Version/4.0 Chrome/110.0 Mobile Safari/537.36"

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = false
        web.scrollView.bounces = false

        context.coordinator.web = web
        context.coordinator.load(url)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        // reloadToken 变了 = 用户点了刷新
        if context.coordinator.lastToken != reloadToken {
            context.coordinator.load(url)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onCallback: (URL) -> Void
        private let onLoaded: () -> Void
        private let onFailed: (String) -> Void

        weak var web: WKWebView?
        var lastToken: UUID?

        init(onCallback: @escaping (URL) -> Void,
             onLoaded: @escaping () -> Void,
             onFailed: @escaping (String) -> Void) {
            self.onCallback = onCallback
            self.onLoaded = onLoaded
            self.onFailed = onFailed
        }

        func load(_ url: URL) {
            lastToken = nil
            var req = URLRequest(url: url)
            req.setValue("Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 "
                         + "(KHTML, like Gecko) Version/4.0 Chrome/110.0 Mobile Safari/537.36",
                         forHTTPHeaderField: "User-Agent")
            web?.load(req)
        }

        /// ★ 关键：在这里把 auth:// 回调拦下来。
        ///   不拦的话 WebView 会尝试 "打开" 这个 scheme 然后报错，
        ///   而且我们也拿不到 fragment 里的 token。
        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let target = action.request.url else {
                decisionHandler(.allow)
                return
            }
            if QQLogin.isCallback(target) {
                decisionHandler(.cancel)
                onCallback(target)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoaded()
        }

        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!, withError error: Error) {
            onFailed(error.localizedDescription)
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            // auth:// 被 cancel 时也会走这儿，那是有意为之，别当失败报
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled { return }
            onFailed(error.localizedDescription)
        }
    }
}
