import Foundation
import Testing

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@testable import ZhangwaKit

// ============================================================================
//  QQ 扫码登录的测试
// ============================================================================
//
//  和微信那套一样，重点在**回归**：
//  sign 公式和回调格式都是从二进制里抠出来的，腾讯随时可能改。
//  用真机抓到的样本钉死，哪天挂了就说明协议变了。
// ============================================================================

@Suite("QQ 扫码登录")
@MainActor
struct QQLoginTests {

    // MARK: MD5

    @Test("MD5 对标准向量（含 padding 边界）")
    func md5KnownVectors() {
        #expect(md5Hex("") == "d41d8cd98f00b204e9800998ecf8427e")
        #expect(md5Hex("abc") == "900150983cd24fb0d6963f7d28e17f72")
        #expect(md5Hex("message digest") == "f96b697d7cb7938d525a2f31aaf161d0")
        #expect(md5Hex("abcdefghijklmnopqrstuvwxyz") == "c3fcd3d76192e4007dfb496cca67e13b")

        // padding 边界（期望值用 Python hashlib 核对过）
        #expect(md5Hex(String(repeating: "a", count: 55))
                == "ef1772b6dff9a122358552954ad0df65")
        #expect(md5Hex(String(repeating: "a", count: 56))
                == "3b0c8ac703f828b04c6c197006d17218")
        #expect(md5Hex(String(repeating: "a", count: 64))
                == "014842d480b571495a4a0363793f7367")
    }

    // MARK: ★ sign 公式回归（最重要）

    @Test("QQ sign 复现真机样本 —— 这条挂了说明腾讯改协议了")
    func signMatchesRealCapture() {
        // 样本来自 MuMu 真机：Frida hook WebView.loadUrl 抓到的 m_authorize URL
        //
        //   client_id=102061775&style=qr&time=1792326852
        //   &sign=1a7fe16b837e17fddc74ecc2232271bc
        //
        let sig = QQLogin.makeSign(time: "1792326852")
        #expect(sig == "1a7fe16b837e17fddc74ecc2232271bc")

        // 把原文也钉住，免得以后有人改了拼接方式
        #expect(QQLogin.packageName == "com.tencent.apps.valorant")
        #expect(QQLogin.certMD5 == "304c3871ea696f1f96157840d33b413d")
        let preimage = "\(QQLogin.packageName)_\(QQLogin.certMD5)_1792326852"
        #expect(preimage == "com.tencent.apps.valorant_304c3871ea696f1f96157840d33b413d_1792326852")
        // 分隔符必须是下划线
        #expect(preimage.split(separator: "_").count == 3)

        // 换一个时间戳结果必须不同（防止写成常量）
        #expect(QQLogin.makeSign(time: "1792326853") != sig)
    }

    @Test("逆向出来的常量")
    func protocolConstants() {
        #expect(QQLogin.qqAppID == "102061775")
        #expect(QQLogin.mappid == 10200)
        #expect(QQLogin.qqInfoType == 5)          // authsuite/d.java:241 的固定值
        #expect(QQLogin.redirectURI == "auth://tauth.qq.com/")
    }

    // MARK: URL

    @Test("authorize URL 的形状")
    func authorizeURLShape() {
        let q = QQLogin()
        let url = q.authorizeURL(time: "1792326852")
        let s = url.absoluteString

        #expect(s.hasPrefix("https://openmobile.qq.com/oauth2.0/m_authorize?"))
        #expect(s.contains("style=qr"))                       // ★ 没有它就不是扫码模式
        #expect(s.contains("client_id=102061775"))
        #expect(s.contains("sign=1a7fe16b837e17fddc74ecc2232271bc"))
        #expect(s.contains("time=1792326852"))
        #expect(s.contains("response_type=token"))
        #expect(s.contains("redirect_uri=auth%3A%2F%2Ftauth.qq.com%2F"))
    }

    // MARK: 回调

    @Test("回调解析：值在 fragment 里，不是在 query 里")
    func parseCallbackFromFragment() {
        // 这是真实格式 —— 注意是 # 不是 ?
        let url = URL(string: "auth://tauth.qq.com/#access_token=ABC123"
                      + "&expires_in=7776000&openid=DEADBEEF&pay_token=XXX")!
        let c = QQLogin.parseCallback(url)
        #expect(c != nil)
        #expect(c?.openID == "DEADBEEF")
        #expect(c?.accessToken == "ABC123")
        #expect(c?.expiresIn == "7776000")
        #expect(c?.isValid == true)
    }

    @Test("回调解析：各种异常输入不能崩")
    func parseCallbackEdgeCases() {
        // 取消登录时也会跳这个 scheme，但没带 token
        #expect(QQLogin.parseCallback(URL(string: "auth://tauth.qq.com/")!) == nil)
        #expect(QQLogin.parseCallback(URL(string: "auth://tauth.qq.com/#openid=X")!) == nil)
        #expect(QQLogin.parseCallback(URL(string: "auth://tauth.qq.com/#access_token=Y")!) == nil)
        // 别人的 scheme 不能认
        #expect(QQLogin.parseCallback(URL(string: "https://example.com/#openid=A&access_token=B")!) == nil)
    }

    @Test("isCallback 只认自己的 scheme")
    func isCallback() {
        #expect(QQLogin.isCallback(URL(string: "auth://tauth.qq.com/#a=b")!))
        #expect(QQLogin.isCallback(URL(string: "auth://anything")!))
        #expect(!QQLogin.isCallback(URL(string: "https://tauth.qq.com/")!))
        #expect(!QQLogin.isCallback(URL(string: "about:blank")!))
    }

    // MARK: 入口 URL 提取（这次的关键改动）

    @Test("还原 \\xNN 转义")
    func unescapeHexEscapes() {
        // m_authorize 页面里的 src 就是这种形态
        #expect(QQLogin.unescapeHex(#"https\x3A\x2F\x2Fxui"#) == "https://xui")
        #expect(QQLogin.unescapeHex(#"\x3F"#) == "?")
        #expect(QQLogin.unescapeHex(#"\x26"#) == "&")
        // 没有转义的照原样
        #expect(QQLogin.unescapeHex("plain text") == "plain text")
        #expect(QQLogin.unescapeHex("") == "")
        // 结尾半个转义不能崩
        #expect(QQLogin.unescapeHex(#"abc\x3"#) == #"abc\x3"#)
        #expect(QQLogin.unescapeHex(#"abc\"#) == #"abc\"#)
    }

    @Test("从入口页 HTML 里抠出登录页 URL —— 用真机抓到的原文")
    func extractEntryFromRealHTML() {
        // 这段是从 MuMu 真机上抓下来的 m_authorize 响应（原样，含 \xNN 转义）
        let html = #"""
        <script language="javascript">
        var src = "https:\x2F\x2Fxui.ptlogin2.qq.com\x2Fcgi-bin\x2Fxlogin\x3Fpt_enable_pwd\x3D1\x26appid\x3D716027609\x26pt_3rd_aid\x3D102061775\x26daid\x3D381\x26style\x3D35\x26force_qr\x3D1\x26autorefresh\x3D1\x26s_url\x3Dhttp\x253A\x252F\x252Fconnect.qq.com\x26sign\x3D1800a311d54700ffe0d5425cd100481d\x26time\x3D1792331444";
        if (isIos()) { document.write('<iframe src="', src, '"></iframe>'); }
        </script>
        """#
        let url = QQLogin.extractEntryURL(from: html)
        #expect(url != nil)
        let s = url?.absoluteString ?? ""
        #expect(s.hasPrefix("https://xui.ptlogin2.qq.com/cgi-bin/xlogin?"))
        #expect(s.contains("force_qr=1"))            // ★ 没有它就不是扫码模式
        #expect(s.contains("appid=716027609"))
        #expect(s.contains("pt_3rd_aid=102061775"))
        #expect(s.contains("style=35"))
        // \xNN 必须还原干净，不能留着反斜杠
        #expect(!s.contains("\\x"))
        #expect(!s.contains("%5Cx"))
    }

    @Test("提取失败时要返回 nil，不能乱猜")
    func extractEntryEdgeCases() {
        #expect(QQLogin.extractEntryURL(from: "") == nil)
        #expect(QQLogin.extractEntryURL(from: "<html>没有 src</html>") == nil)
        // 有 src 但不是 http 的，不算
        #expect(QQLogin.extractEntryURL(from: #"var src = "ftp://x""#) == nil)
    }

    @Test("伪装 UA 里不能有 iOS 标识 —— 否则 isIos() 会真")
    func androidUADoesNotLookIOS() {
        let ua = QQLogin.androidUA
        #expect(ua.contains("Android"))
        #expect(!ua.contains("iPhone"))
        #expect(!ua.contains("iPad"))
        #expect(!ua.contains("iPod"))
        // 也不能带 QQ/ —— 否则页面会走 window.open 分支（那是给真 QQ 客户端用的）
        #expect(!ua.contains("QQ/"))
    }

    // MARK: 重载闸门（二维码狂闪那个 bug 的回归）

    @Test("同一个 token 只加载一次 —— 重渲染不能触发重载")
    func reloadGateOnlyOncePerToken() {
        var gate = ReloadGate()
        let a = UUID()

        // 注意：#expect 会把表达式包进闭包，mutating 调用不能直接写在里面，
        // 所以先取出来再断言。
        let first = gate.shouldReload(token: a)
        #expect(first)                            // 第一次要加载

        // ★ 关键：反复问同一个 token，只能第一次为真。
        //   原版每次都为真 -> 每次重渲染都加载 -> 二维码狂闪。
        var anyTrue = false
        for _ in 0..<20 where gate.shouldReload(token: a) {
            anyTrue = true
        }
        #expect(!anyTrue, "同一个 token 不该再次加载")
        #expect(gate.current == a)
    }

    @Test("换 token 才重载（点刷新 / 自动换码）")
    func reloadGateNewTokenReloads() {
        var gate = ReloadGate()
        let a = UUID(), b = UUID(), c = UUID()

        let r1 = gate.shouldReload(token: a)
        let r2 = gate.shouldReload(token: b)
        let r3 = gate.shouldReload(token: b)      // 重复问 b
        let r4 = gate.shouldReload(token: c)
        let r5 = gate.shouldReload(token: a)      // 换回 a —— 相对 b/c 也是"新"的

        #expect(r1)
        #expect(r2)
        #expect(!r3)
        #expect(r4)
        #expect(r5)
    }

    // MARK: 换登录态

    @Test("登录：请求体形状要和 Android 一致（sig = access_token）")
    func loginBodyShape() async throws {
        let box = RecordBox([Self.loginResponse])
        let q = QQLogin(transport: Self.transport(box))
        _ = try await q.login(.init(openID: "QQ_OPENID", accessToken: "QQ_TOKEN",
                                    expiresIn: "7776000"))

        let sent = try #require(box.sentBodies.first)
        let json = try #require(try JSONSerialization.jsonObject(with: sent) as? [String: Any])
        #expect(json["clienttype"] as? Int == 9)
        #expect(json["mappid"] as? Int == 10200)

        let info = try #require(json["login_info"] as? [String: Any])
        #expect(info["appid"] as? Int == 102061775)
        #expect(info["openid"] as? String == "QQ_OPENID")
        #expect(info["sig"] as? String == "QQ_TOKEN")      // ★ sig 就是 access_token
        #expect(info["qq_info_type"] as? Int == 5)
        // Android 版没有这两个字段，多送了可能被服务端挑刺
        #expect(info["uin"] == nil)
    }

    @Test("登录：Cookie 的 openid 取 bind_info，authType 标成 QQ")
    func loginSession() async throws {
        let box = RecordBox([Self.loginResponse])
        let q = QQLogin(transport: Self.transport(box))
        let s = try await q.login(.init(openID: "QQ_OPENID", accessToken: "T", expiresIn: nil))

        #expect(s.userID == "JA-QQ")
        #expect(s.ct == "CT_QQ")
        #expect(s.authType == .qq)
        #expect(s.openID == "A44A6AA89A42ECA6909C2492C2193D14")
        #expect(s.ctUpdatedAt > 0)
    }

    @Test("登录：接口报错时要抛出来")
    func loginFailure() async {
        let box = RecordBox([#"{"result":2001,"msg":"登录失败,请重试"}"#])
        let q = QQLogin(transport: Self.transport(box))
        await #expect(throws: (any Error).self) {
            _ = try await q.login(.init(openID: "X", accessToken: "Y", expiresIn: nil))
        }
    }

    // MARK: 端到端

    @Test("整条链：拿到回调 → 换登录态 → 状态机走完")
    func fullFlow() async throws {
        let box = RecordBox([Self.loginResponse])
        let q = QQLogin(transport: Self.transport(box))

        var session: ZhangwaSession?
        var stages: [QQLogin.Stage] = []
        q.onSession = { session = $0 }
        q.onStageChange = { stages.append($0) }

        q.markWaiting()
        #expect(q.stage == .waiting)

        let url = URL(string: "auth://tauth.qq.com/#access_token=TK&openid=OID&expires_in=100")!
        q.complete(with: url)

        for _ in 0..<100 {
            if q.stage == .success || q.stage == .cancelled { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(q.stage == .success)
        #expect(session?.userID == "JA-QQ")
        #expect(stages.contains(.authorizing))
    }

    @Test("用户取消（回调里没 token）→ 状态是 cancelled，不是 failed")
    func cancelFlow() {
        let q = QQLogin()
        q.complete(with: URL(string: "auth://tauth.qq.com/?cancel=1")!)
        #expect(q.stage == .cancelled)
    }

    // MARK: 脚手架

    /// 同 QRLoginTests：登录接口返回的是 `login_info`，不是 `ct_info`
    static let loginResponse = """
    {"result":0,"msg":"","data":{
      "bind_info":[{"uin":"A44A6AA89A42ECA6909C2492C2193D14",
                    "openid":"A44A6AA89A42ECA6909C2492C2193D14","uuid":"JA-QQ"}],
      "login_info":{"ct":"CT_QQ","wt":"WT_QQ","user_id":"JA-QQ",
                    "uin":2751275315,"openid":"74193457a-b8d058817457ae26_10200",
                    "ctt":"CTT_QQ"}
    }}
    """

    final class RecordBox: @unchecked Sendable {
        private let responses: [String]
        private let lock = NSLock()
        private var _urls: [String] = []
        private var _bodies: [Data] = []

        init(_ responses: [String]) { self.responses = responses }

        var urls: [String] { lock.withLock { _urls } }
        var sentBodies: [Data] { lock.withLock { _bodies } }

        func next(_ url: String, body: Data?) -> Data {
            lock.withLock {
                _urls.append(url)
                if let body { _bodies.append(body) }
                let i = min(_urls.count - 1, responses.count - 1)
                return Data(responses[i].utf8)
            }
        }
    }

    static func transport(_ box: RecordBox) -> QRTransport {
        { req, _ in
            let data = box.next(req.url?.absoluteString ?? "", body: req.httpBody)
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (data, resp)
        }
    }
}
