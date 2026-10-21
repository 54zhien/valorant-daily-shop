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

    /// 网页里二维码的位置（CSS px，相对视口）。量到之后就把整页裁成一张二维码 ——
    /// 和微信登录那页长得一样：一张码 + 一行提示，没有网页的页头页脚。
    @State private var qrRect: CGRect?
    /// 看门狗重载次数（页面卡住时自救，最多一次）
    @State private var watchdogReloads = 0
    /// 网页是否已经加载完（didFinish）。没加载完的重载只会让它更慢。
    @State private var pageLoaded = false


    /// 二维码卡片：和微信那页共用同一组 token
    private static let qrSide = ZW.qrCardSide
    /// 网页用**固定视口**加载 —— 换机型二维码落点也一样，量一次就够
    private static let pageSize = CGSize(width: 390, height: 700)

    var body: some View {
        NavigationStack {
            // 只有一张码。提示条、状态条都去掉 —— 和微信那页长得一模一样。
            VStack {
                Spacer(minLength: 0)
                qrCard
                Spacer(minLength: 0)
            }
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
                        Label("换一张码", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { wire() }
        // ⚠️ 这里**只保留一个很长的兜底**。
        //    上一版曾经用「探针看到 #qr_invalid 就换码」—— 结果那个元素在 QQ 页面上
        //    一直是 display:block（它靠 opacity/visibility 藏），于是每次探针都判定"失效"，
        //    二维码被无限重建、页面不停刷新。**别再走那条路**。
        .task(id: reloadToken) {
            try? await Task.sleep(nanoseconds: 240_000_000_000)
            guard !Task.isCancelled else { return }
            if stage == .waiting || stage == .loading {
                reloadToken = UUID()
                stage = .loading
            }
        }
        // 看门狗：**页面自己都没加载完时不要碰它** —— 那是网络慢，
        // 重载只会让整条链从头再来一遍，看起来更慢（上一版就是 8 秒硬重载，反而添乱）。
        // 只有"页面明明加载完了、却没有二维码"才重载，而且最多一次。
        .task(id: reloadToken) {
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled else { return }
            if pageLoaded, qrRect == nil, watchdogReloads < 1 {
                watchdogReloads += 1
                reloadToken = UUID()
            }
        }
    }

    // MARK: - 二维码

    /// 一张白卡，里面只有二维码 —— 和微信登录那页同一套版式。
    /// 做法：网页照旧在底下整张加载（它自己会画码、自己轮询），
    /// 我们只把 WebView 按「二维码中心」偏移，再裁成 224×224。
    private var qrCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ZW.radiusCard, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)

            webLayer
                .clipShape(RoundedRectangle(cornerRadius: ZW.radiusCard, style: .continuous))

            // 还没量到二维码位置（或者入口页都还没回来）
            if qrRect == nil || url == nil {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.large)
                    Text("正在准备二维码…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: Self.qrSide, height: Self.qrSide)
        .contentShape(RoundedRectangle(cornerRadius: ZW.radiusCard, style: .continuous))
        .onTapGesture {
            // 码失效了：点一下就换一张（和微信页一致）
            if case .failed = stage {
                reloadToken = UUID()
                stage = .loading
            }
        }
    }

    /// 把二维码放大到正好装满卡片：按**量到的**尺寸算，不猜页面的码有多大
    private var webScale: CGFloat {
        guard let r = qrRect, r.width > 1 else { return 1 }
        // 卡片内四周各留 ZW.qrMargin —— 和微信那页的留白一模一样
        return min(1.8, (Self.qrSide - ZW.qrMargin * 2) / r.width)
    }

    /// WebView 本身：固定视口大小 → 按二维码中心缩放/偏移 → 外面再套 224 的裁切框。
    /// 量不到位置时透明，但**始终挂在视图树里** —— 否则一换布局 WebView 就被重建、页面重载。
    private var webLayer: some View {
        Group {
            if let url {
                QQWebView(url: url,
                          reloadToken: reloadToken,
                          onCallback: { callback in
                              login.complete(with: callback)
                          },
                          onLoaded: {
                              pageLoaded = true
                              if stage == .loading || stage == .idle {
                                  login.markWaiting()
                              }
                          },
                          onFailed: { msg in
                              stage = .failed(msg)
                          },
                          onQRRect: { rect in
                              // 只在真的变了的时候写，避免每帧都触发重绘
                              if qrRect != rect { withAnimation(.easeOut(duration: 0.2)) { qrRect = rect } }
                          })
                .frame(width: Self.pageSize.width, height: Self.pageSize.height)
                .scaleEffect(webScale, anchor: .topLeading)
                .offset(x: offset.x, y: offset.y)
            }
        }
        .opacity(qrRect == nil ? 0 : 1)
        .frame(width: Self.qrSide, height: Self.qrSide, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
    }

    /// 让二维码中心落在卡片中心
    private var offset: CGPoint {
        guard let r = qrRect else { return .zero }
        let s = webScale
        return CGPoint(x: Self.qrSide / 2 - r.midX * s,
                       y: Self.qrSide / 2 - r.midY * s)
    }

    // MARK: - 状态


    private var color: Color {
        switch stage {
        case .success: return .zwSignal
        case .failed:  return .zwRouge
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
    private func prepare(attempt: Int = 0) async {
        url = nil
        qrRect = nil
        pageLoaded = false
        watchdogReloads = 0
        stage = .loading
        do {
            // 有预取就用预取的（「我的」页出现时已经在后台抓好了），
            // 所以这里通常是 0 等待，WebView 立刻开始加载。
            let entry = try await login.entryURL(forceRefresh: attempt > 0)
            url = entry
        } catch {
            // 抓入口页失败多半是网络抖了一下：自动再试一次，
            // 不要一上来就让用户看错误（他除了关掉重开也没别的可做）。
            if attempt < 1 {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard !Task.isCancelled else { return }
                await prepare(attempt: attempt + 1)
                return
            }
            stage = .failed(error.localizedDescription)
        }
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
    /// 页面里二维码的位置（CSS px，相对视口）—— 上层据此把整页裁成一张二维码
    var onQRRect: ((CGRect) -> Void)?


    func makeCoordinator() -> Coordinator {
        Coordinator(onCallback: onCallback, onLoaded: onLoaded,
                    onFailed: onFailed, onNavigate: onNavigate, onProbe: onProbe,
                    onQRRect: onQRRect)
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

        // 位置是量出来的，页面自己别滚（滚了 rect 就对不上）
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false

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
        let onQRRect: ((CGRect) -> Void)?

        weak var web: WKWebView?
        var gate = ReloadGate()
        /// 探针重试次数（二维码晚一点才出现时用）
        var probeTries = 0

        init(onCallback: @escaping (URL) -> Void,
             onLoaded: @escaping () -> Void,
             onFailed: @escaping (String) -> Void,
             onNavigate: ((URL, Bool) -> Void)?,
             onProbe: ((String) -> Void)?,
             onQRRect: ((CGRect) -> Void)?) {
            self.onCallback = onCallback
            self.onLoaded = onLoaded
            self.onFailed = onFailed
            self.onNavigate = onNavigate
            self.onProbe = onProbe
            self.onQRRect = onQRRect
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
            probeTries = 0
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
            probeTries = 0
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
                var r = img ? img.getBoundingClientRect() : null;
                return JSON.stringify({
                  url: location.href,
                  hasImg: !!img,
                  imgSrc: img ? (img.src || '').slice(0, 200) : '',
                  imgW: img ? img.naturalWidth : 0,
                  // 二维码在页面里的位置（CSS px，相对视口）
                  rect: r ? { x: r.left, y: r.top, w: r.width, h: r.height } : null,
                  scrollY: window.scrollY || 0,
                  tips: tips ? tips.innerText.replace(/\\n/g, ' ') : '',
                  ua: navigator.userAgent.slice(0, 80),
                  cookieOK: document.cookie.length > 0
                });
              } catch (e) { return 'ERR:' + e; }
            })()
            """
            webView.evaluateJavaScript(js) { value, error in
                if let s = value as? String {
                    // 二维码有时是页面加载完之后才由脚本塞进来的：
                    // 没量到就隔 0.7 秒再量一次（有上限，不会一直轮询）
                    if !self.reportQRRect(from: s), self.probeTries < 12 {
                        self.probeTries += 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak webView] in
                            guard let webView else { return }
                            self.probePage(webView)
                        }
                    } else {
                        self.onProbe?(s)
                    }
                } else if let e = error {
                    self.onProbe?("probe 失败: \(e.localizedDescription)")
                }
            }
        }

        /// 从探针的 JSON 里抠出二维码矩形，交给上层做裁剪。
        /// 拿不到就什么都不做 —— 上层会继续显示"正在准备二维码…"。
        @discardableResult
        private func reportQRRect(from json: String) -> Bool {
            // ⚠️ 分两段 guard：`guard let` 的 else 分支里读不到前面刚绑定的名字，
            //    所以先单独把 JSON 解析出来（失效判定要先跑，位置拿不到也要判）。
            guard let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return false }



            guard let r = obj["rect"] as? [String: Any],
                  let x = (r["x"] as? NSNumber)?.doubleValue,
                  let y = (r["y"] as? NSNumber)?.doubleValue,
                  let w = (r["w"] as? NSNumber)?.doubleValue,
                  let h = (r["h"] as? NSNumber)?.doubleValue,
                  w > 20, h > 20
            else { return false }

            let scrollY = (obj["scrollY"] as? NSNumber)?.doubleValue ?? 0
            onQRRect?(CGRect(x: x, y: y + scrollY, width: w, height: h))
            return true
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
