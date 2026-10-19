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
    @State private var copied = false

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
                                  // 打**完整 URL**，不只 host ——
                                  // QQ 成功后会经过 s_url 之类的中转，只看 host 看不出走到了哪
                                  diag.insert("\u{2192} \(isMain ? "主" : "子") \(target.absoluteString.prefix(120))", at: 0)
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

    /// 诊断文本（可复制，出问题时整段发过来）
    private var diagLines: String {
        (["QQ扫码诊断", "UA = Android（伪装）", "---"] + diag.reversed())
            .joined(separator: "\n")
    }

    /// 诊断面板 —— 出问题时让用户整块截图 / 复制发过来就够了
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
        Task { await prepare() }
    }

    /// 两步走：先从入口页把真正的登录页 URL 抠出来，再让 WebView 直接加载它。
    ///
    /// 为什么不把 m_authorize 直接丢给 WebView：
    ///   那个页面最后有一段 iOS 特判，会把它塞进 `<iframe>`：
    ///
    ///       if (isIos()) {
    ///           if (inMQQ()) { window.open(src, '_self') }
    ///           else { document.write('<iframe ... src="', src, '"></iframe>') }
    ///       } else { location.replace(src) }
    ///
    ///   iframe 里 xui.ptlogin2.qq.com 就是**第三方域**，iOS 的 ITP 会拦它的
    ///   Cookie，ptlogin2 会话建不起来 —— 二维码画不出来或者扫了说过期。
    ///   我们自己抠 URL、自己导航，就永远是**顶层导航**，不给它走 iframe 的机会。
    @MainActor
    private func prepare() async {
        diag.removeAll()
        url = nil
        stage = .loading
        let ts = QQLogin.nowTimestamp()
        diag.insert("① 请求入口页（time=\(ts)，签名本地算）", at: 0)
        do {
            let entry = try await login.fetchEntryURL(time: ts)
            diag.insert("② 抠到登录页 → \(entry.host ?? "?")", at: 0)
            diag.insert("③ 顶层导航（绕开页面的 isIos/iframe 分支）", at: 0)
            if diag.count > 16 { diag.removeLast() }
            url = entry
        } catch {
            stage = .failed(error.localizedDescription)
            diag.insert("✗ 抓入口页失败：\(error.localizedDescription)", at: 0)
            diag.insert("   （如果这行出现，多半是网络或 sign/time 被拒）", at: 0)
        }
    }

    /// 重来：重新算 time + sign + 重抓入口页
    private func restart() {
        Task { await prepare() }
    }
}

// MARK: - WKWebView 包装

/// 只做两件事：加载 URL，拦截 auth:// 回调。
struct QQWebView: UIViewRepresentable {
    /// 伪装成 Android（转发到 Kit 里的定义，避免两处不一致）
    static let androidUA = QQLogin.androidUA

    /// 页面加载前注入：把 window.open / location.assign / replace 挂上钩子，
    /// 一旦发现 auth:// 回调就通过 messageHandler **直接报给原生端**。
    ///
    /// 为什么要这个：
    ///   WKWebView 对**未知 scheme**（auth:// 就是）的处理路径不止一条 ——
    ///   有时候走 navigationDelegate 的 decidePolicyFor，
    ///   有时候被当成「尝试打开外部 App」直接吞掉，delegate 一次都不回调。
    ///   多这一层，不管它用哪种方式跳，我们都能拿到那个 URL。
    static let hookScript = """
    (function () {
      if (window.__qqcbHooked) { return; }
      window.__qqcbHooked = true;

      function report(u) {
        try {
          if (u && String(u).indexOf('auth://') === 0) {
            window.webkit.messageHandlers.qqcb.postMessage(String(u));
          }
        } catch (e) {}
      }

      try {
        var _open = window.open;
        window.open = function (u) { report(u); return _open.apply(this, arguments); };
      } catch (e) {}

      try {
        var _assign = window.location.assign;
        window.location.assign = function (u) {
          report(u); return _assign.call(window.location, u);
        };
      } catch (e) {}

      try {
        var _replace = window.location.replace;
        window.location.replace = function (u) {
          report(u); return _replace.call(window.location, u);
        };
      } catch (e) {}

      // href 直接赋值拦不住（location 不可配置），所以退一步兜 hashchange
      try {
        window.addEventListener('hashchange', function () {
          report(window.location.href);
        }, true);
      } catch (e) {}
    })();
    """

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
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        // ★ 注入一个脚本，在页面加载前把 window.open 挂上钩子。
        //    QQ 的成功回调有可能是 window.open('auth://tauth.qq.com/#...')，
        //    WKWebView 对未知 scheme 的处理路径不止一条，多一层保险。
        config.userContentController.add(context.coordinator, name: "qqcb")
        config.userContentController.addUserScript(
            WKUserScript(source: QQWebView.hookScript,
                         injectionTime: .atDocumentStart,
                         forMainFrameOnly: false))

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        // ★★★ 之前漏了这行！只设 javaScriptCanOpenWindowsAutomatically
        //     而不实现 WKUIDelegate，window.open 会被**静默忽略** ——
        //     表现就是「QQ 那边提示已确认，App 这边毫无反应」。
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = false
        web.scrollView.bounces = false
        web.customUserAgent = QQLogin.androidUA

        context.coordinator.web = web
        context.coordinator.load(url, token: reloadToken)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        // reloadToken 变了 = 用户点了刷新，或者自动换码到点了。
        //
        // ⚠️ 这里必须用 ReloadGate，不能自己比 —— 之前写成
        //     if coordinator.lastToken != reloadToken { load() }
        //   而 load() 里把 lastToken 设成了 nil，于是条件**永远为真**：
        //   每次重渲染都重载页面，导航回调又写诊断、诊断又触发重渲染……
        //   死循环，表现就是二维码疯狂闪烁扫不了。
        if context.coordinator.gate.shouldReload(token: reloadToken) {
            context.coordinator.load(url, token: reloadToken)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let onCallback: (URL) -> Void
        private let onLoaded: () -> Void
        private let onFailed: (String) -> Void
        let onNavigate: ((URL, Bool) -> Void)?
        let onProbe: ((String) -> Void)?

        weak var web: WKWebView?
        var gate = ReloadGate()

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

        // MARK: 回调捕获（三层保险）

        /// ① navigationDelegate：常规跳转
        /// ② uiDelegate：window.open
        /// ③ JS 注入：直接报给原生
        private func handleIfCallback(_ url: URL) -> Bool {
            guard QQLogin.isCallback(url) else { return false }
            onCallback(url)
            return true
        }

        // MARK: WKScriptMessageHandler —— JS 注入那条路

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "qqcb",
                  let s = message.body as? String,
                  let url = URL(string: s) else { return }
            onProbe?("JS 上报 \(url.absoluteString.prefix(120))")
            _ = handleIfCallback(url)
        }

        // MARK: WKUIDelegate —— 没有它 window.open 会被静默忽略

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                onProbe?("window.open \(url.absoluteString.prefix(120))")
                if handleIfCallback(url) { return nil }
            }
            // 不是回调就**在当前 WebView 里打开**（不要另开窗口），
            // 否则 QQ 的中转页会在一个我们看不到的窗口里跑
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        func load(_ url: URL, token: UUID) {
            // 记下当前 token。不记的话下次 updateUIView 会再加载一次，
            // 然后导航回调写诊断、诊断触发重渲染、又加载 —— 死循环，二维码狂闪。
            _ = gate.shouldReload(token: token)
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
            if handleIfCallback(target) {
                decisionHandler(.cancel)
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
