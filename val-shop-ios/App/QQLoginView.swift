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
    /// 诊断信息（导航 + 页面探针）。二维码失效到底是服务端判的还是我们这边的问题，
    /// 看这个就能分辨 —— 别再靠猜。
    @State private var diag: [String] = []

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
                              },
                              onNavigate: { target, isMain in
                                  // 换过一次 UA 之后，这里应该看到
                                  // xui.ptlogin2.qq.com 是**主框架**。
                                  // 如果它出现在子框架里，说明 iOS 分支还是走了 iframe。
                                  diag.insert("\u{2192} \(isMain ? "主" : "子") \(target.host ?? "?")", at: 0)
                                  if diag.count > 12 { diag.removeLast() }
                              },
                              onProbe: { info in
                                  diag.insert("QR \(info)", at: 0)
                                  if diag.count > 12 { diag.removeLast() }
                              })
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    ProgressView("正在准备…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                statusBar
                if !diag.isEmpty { diagPanel }
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
        // QQ 的二维码有 TTL（约两三分钟）。页面自带 autorefresh=1，
        // 但不保证生效，所以自己也兜一层：还在等扫码就定期换一张。
        .task(id: reloadToken) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 90_000_000_000)   // 90 秒
                if Task.isCancelled { break }
                if stage == .waiting || stage == .loading {
                    diag.insert("⟳ 自动换码（90 秒到）", at: 0)
                    reloadToken = UUID()
                    stage = .loading
                } else {
                    break
                }
            }
        }
    }

    /// 诊断面板 —— 出问题时让用户整块截图发过来就够了
    private var diagPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(diag.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(12)
        }
        .frame(maxHeight: 132)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
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
    /// 伪装成 Android。理由见 makeUIView 里那段注释 ——
    /// 不这么做的话 QQ 会把登录页塞进 iframe，然后 Cookie 被 iOS 拦掉。
    static let androidUA = "Mozilla/5.0 (Linux; Android 12; SM-S9210) AppleWebKit/537.36 "
                         + "(KHTML, like Gecko) Version/4.0 Chrome/110.0.5481.154 "
                         + "Mobile Safari/537.36"

    let url: URL
    /// 变了就重新加载（点"刷新"时）
    let reloadToken: UUID
    let onCallback: (URL) -> Void
    let onLoaded: () -> Void
    let onFailed: (String) -> Void
    /// 每次导航（URL + 是不是主框架），用来诊断
    var onNavigate: ((URL, Bool) -> Void)?
    /// 页面加载完注入 JS 探到的信息
    var onProbe: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onCallback: onCallback, onLoaded: onLoaded,
                    onFailed: onFailed, onNavigate: onNavigate, onProbe: onProbe)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // QQ 的登录页会开自己的小窗做校验，给它留个口子，否则可能白屏
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = false
        web.scrollView.bounces = false

        // ★★★ 必须伪装成 Android UA —— 这不是为了骗服务端，是为了绕开
        //     QQ 登录页里的这一段 iOS 特判：
        //
        //         if (isIos()) {
        //             if (inMQQ()) { window.open(src, '_self') }
        //             else { document.write('<iframe src="', src, '"></iframe>') }
        //         } else {
        //             location.replace(src)
        //         }
        //
        //     iOS + 不在 QQ 里 -> 登录页被塞进 <iframe>，
        //     xui.ptlogin2.qq.com 就成了**第三方域**，
        //     而 iOS 的 ITP 会拦掉它的 Cookie -> ptlogin2 会话建不起来
        //     -> 二维码画得出来但一扫码就"失效"。
        //
        //     掌瓦在 Android 上走 location.replace，顶层导航没这问题，
        //     所以这个坑只有 iOS 版会踩。
        //
        //     设 customUserAgent（而不是只设 URLRequest 的 header）——
        //     后者只作用于首个请求，页面里 navigator.userAgent 读到的还是 iOS。
        web.customUserAgent = QQWebView.androidUA

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
        let onNavigate: ((URL, Bool) -> Void)?
        let onProbe: ((String) -> Void)?

        weak var web: WKWebView?
        var lastToken: UUID?

        init(onCallback: @escaping (URL) -> Void,
             onLoaded: @escaping () -> Void,
             onFailed: @escaping (String) -> Void,
             onNavigate: ((URL, Bool) -> Void)?,
             onProbe: ((String) -> Void)?) {
            self.onCallback = onCallback
            self.onLoaded = onLoaded
            self.onFailed = onFailed
            self.onNavigate = onNavigate
            self.onProbe = onProbe
        }

        func load(_ url: URL) {
            lastToken = nil
            // customUserAgent 已经设过了，这里不用再改 header。
            // 两处都设反而容易不一致，留一处就好。
            web?.load(URLRequest(url: url))
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
            onNavigate?(target, action.targetFrame?.isMainFrame ?? false)
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoaded()
            probePage(webView)
        }

        /// 页面加载完，注入 JS 看看二维码到底出没出来。
        ///
        /// 为什么要这个：光看截图没法判断「二维码失效」是**服务端给的**还是
        /// **我们这边渲染/会话出的问题**。把 qrimg.src 和提示文字读出来就能分辨：
        ///   · qrimg.src 为空      -> 二维码根本没拉到
        ///   · src 有但带着旧时间  -> 缓存问题
        ///   · tips 里有"失效"     -> 服务端确实判定过期了
        func probePage(_ webView: WKWebView) {
            let js = """
            (function () {
              try {
                var img = document.getElementById('qrimg');
                var tips = document.getElementById('qrtips');
                var inv = document.getElementById('qr_invalid');
                return JSON.stringify({
                  url: location.href,
                  hasImg: !!img,
                  imgSrc: img ? (img.src || '').slice(0, 200) : '',
                  imgW: img ? img.naturalWidth : 0,
                  tips: tips ? tips.innerText.replace(/\\n/g, ' ') : '',
                  invalidShown: inv ? (getComputedStyle(inv).display !== 'none') : null,
                  ua: navigator.userAgent.slice(0, 80),
                  cookieOK: document.cookie.length > 0
                });
              } catch (e) { return 'ERR:' + e; }
            })()
            """
            webView.evaluateJavaScript(js) { value, error in
                if let s = value as? String {
                    self.onProbe?(s)
                } else if let e = error {
                    self.onProbe?("probe 失败: \(e.localizedDescription)")
                }
            }
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
