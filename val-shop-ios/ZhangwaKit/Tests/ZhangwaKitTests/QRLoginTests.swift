import Foundation
import Testing

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@testable import ZhangwaKit

// ============================================================================
//  扫码登录的测试
// ============================================================================
//
//  重点不是覆盖率，是**回归**：
//  signature 那条公式是从二进制里抠出来的，腾讯随时可能改。
//  用真机抓到的样本钉死它 —— 哪天这条挂了，就说明协议变了，得重新挖。
// ============================================================================

@Suite("扫码登录")
@MainActor
struct QRLoginTests {

    // MARK: SHA-1 本身

    @Test("SHA-1 对标准向量（含 padding 边界）")
    func sha1KnownVectors() {
        // RFC 3174 的标准向量
        #expect(SHA1.hex("") == "da39a3ee5e6b4b0d3255bfef95601890afd80709")
        #expect(SHA1.hex("abc") == "a9993e364706816aba3e25717850c26c9cd0d89d")
        #expect(SHA1.hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
                == "84983e441c3bd26ebaae4aa1f95129e5e54670f1")

        // padding 边界：55（还能塞下长度）、56（必须新开一块）、64（刚好整块）、
        // 119/120（跨块）。这几个最容易写错，单独钉住。
        // 期望值用 Python hashlib 算的，逐字节核对过。
        #expect(SHA1.hex(String(repeating: "a", count: 55))
                == "c1c8bbdc22796e28c0e15163d20899b65621d65a")
        #expect(SHA1.hex(String(repeating: "a", count: 56))
                == "c2db330f6083854c99d4b5bfb6e8f29f201be699")
        #expect(SHA1.hex(String(repeating: "a", count: 57))
                == "f08f24908d682555111be7ff6f004e78283d989a")
        #expect(SHA1.hex(String(repeating: "a", count: 64))
                == "0098ba824b5c16427bd7a1122a5a442a25ec644d")
        #expect(SHA1.hex(String(repeating: "a", count: 119))
                == "ee971065aaa017e0632a8ca6c77bb3bf8b1dfc56")
        #expect(SHA1.hex(String(repeating: "a", count: 120))
                == "f34c1488385346a55709ba056ddd08280dd4c6d6")

        // 非 ASCII：签名原文全是 ASCII，但工具类得对任意 UTF-8 正确
        #expect(SHA1.hex("掌上无畏契约") == SHA1.hex(Array("掌上无畏契约".utf8)))
    }

    // MARK: ★ 公式回归（最重要的一条）

    @Test("signature 公式复现真机样本 —— 这条挂了说明腾讯改协议了")
    func signatureMatchesRealCapture() {
        // 样本来自 MuMu 真机：hook com.tencent.wglogin.authsuite.util.f 抓到的 SHA-1 原文
        //
        //   原文 = appid=wxcbb49f1f39656c2a&noncestr=WM7gpb
        //          &sdk_ticket=qeuRRdzufZaOpdhfU2Q4gGbgoxq-NLbBLoPmh9nUqy…
        //          &timestamp=1792324928
        //
        let ticket = "qeuRRdzufZaOpdhfU2Q4gGbgoxq-NLbBLoPmh9nUqydeslyBQFiDXVdbrZRb18EWz"
                   + "Y4VZ4OSxxjkW9qnzKAPBw"
        let sig = QRLogin.signature(nonce: "WM7gpb", ticket: ticket,
                                    timestamp: "1792324928")
        #expect(sig == "b7733c8ae0e0433f912123917bc9b5b1214a7ea6")

        // 把原文也钉住 —— 光对哈希不够，得保证拼接方式没被"优化"掉
        let preimage = "appid=\(QRLogin.appID)&noncestr=WM7gpb"
                     + "&sdk_ticket=\(ticket)&timestamp=1792324928"
        #expect(preimage.hasPrefix("appid=wxcbb49f1f39656c2a&noncestr="))
        #expect(preimage.contains("&sdk_ticket="))   // ★ 是 sdk_ticket，不是 ticket
        #expect(!preimage.contains("&scope="))       // ★ scope 不参与
        #expect(preimage.hasSuffix("&timestamp=1792324928"))
    }

    @Test("逆向出来的常量")
    func protocolConstants() {
        #expect(QRLogin.appID == "wxcbb49f1f39656c2a")
        #expect(QRLogin.mappid == 10200)
        #expect(QRLogin.scope == "snsapi_userinfo")
        #expect(QRLogin.clientType == 9)
        #expect(QRLogin.wxInfoType == 1)
        #expect(QRLogin.checkThirdType == 0)
    }

    @Test("noncestr 是 6 位（真机抓到的都是 6 位）")
    func nonceLength() {
        for _ in 0..<50 {
            let n = QRLogin.randomNonce()
            #expect(n.count == 6)
            #expect(n.allSatisfy { $0.isLetter || $0.isNumber })
        }
    }

    // MARK: 轮询状态机

    @Test("轮询：408 等待 → 404 已扫描 → 405 拿码")
    func pollStateMachine() async throws {
        let box = ScriptBox([
            #"{"wx_errcode":408}"#,
            #"{"wx_errcode":404}"#,
            #"{"wx_errcode":405,"wx_code":"071ku8ll2ylcDi4Q85ml2ktMNE2ku8l4"}"#,
        ])
        let q = QRLogin(transport: Self.transport(box))
        try await q.pollStageCheck(uuid: "U1")
        #expect(box.calls.count == 3)
    }

    @Test("轮询：402 过期 / 403 取消 要抛出来")
    func pollTerminalCodes() async {
        let expired = QRLogin(transport: Self.transport(ScriptBox([#"{"wx_errcode":402}"#])))
        await #expect(throws: (any Error).self) {
            _ = try await expired.poll(uuid: "U")
        }

        let cancelled = QRLogin(transport: Self.transport(ScriptBox([#"{"wx_errcode":403}"#])))
        await #expect(throws: (any Error).self) {
            _ = try await cancelled.poll(uuid: "U")
        }
    }

    @Test("轮询会把 last 带上（服务端据此判断是不是同一个码）")
    func pollSendsLast() async throws {
        let box = ScriptBox([
            #"{"wx_errcode":408}"#,
            #"{"wx_errcode":405,"wx_code":"CODE"}"#,
        ])
        let q = QRLogin(transport: Self.transport(box))
        _ = try? await q.poll(uuid: "U9")
        #expect(box.calls.count == 2)
        #expect(!box.calls[0].contains("last="))
        #expect(box.calls[1].contains("last=408"))
    }

    // MARK: 二维码

    @Test("申请二维码：解析 uuid + base64 图片（是 JPEG 不是 PNG）")
    func parseQRCode() async throws {
        // 1x1 的 JPEG
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46,
                         0x49, 0x46, 0x00, 0x01, 0xFF, 0xD9])
        let body = """
        {"errcode":0,"uuid":"021rgqqw1kZG1w3k","appname":"掌上无畏契约",
         "qrcode":{"qrcodebase64":"\(jpeg.base64EncodedString())","qrcodelength":\(jpeg.count)}}
        """
        let q = QRLogin(transport: Self.transport(ScriptBox([body])))
        let qr = try await q.requestQRCode(nonce: "n", timestamp: "t", signature: "s")
        #expect(qr.uuid == "021rgqqw1kZG1w3k")
        #expect(qr.data == jpeg)
        // 是 JPEG 的 SOI
        #expect(qr.data.prefix(2) == Data([0xFF, 0xD8]))
    }

    @Test("signature 被拒时要报清楚原因")
    func qrSignatureRejected() async {
        let body = #"{"errcode":-11,"errmsg":"signature mismatch"}"#
        let q = QRLogin(transport: Self.transport(ScriptBox([body])))
        do {
            _ = try await q.requestQRCode(nonce: "n", timestamp: "t", signature: "bad")
            Issue.record("应该抛错")
        } catch {
            #expect(error.localizedDescription.contains("signature mismatch"))
        }
    }

    // MARK: 换登录态

    @Test("登录：请求体形状要和 Android 一致")
    func loginBodyShape() async throws {
        let box = ScriptBox([Self.loginResponse])
        let q = QRLogin(transport: Self.transport(box))
        _ = try await q.login(code: "WXCODE")

        let sent = try #require(box.sentBodies.first)
        let json = try #require(try JSONSerialization.jsonObject(with: sent) as? [String: Any])

        #expect(json["clienttype"] as? Int == 9)
        #expect(json["mappid"] as? Int == 10200)
        #expect(json["mcode"] as? String == "")

        let info = try #require(json["login_info"] as? [String: Any])
        #expect(info["appid"] as? String == "wxcbb49f1f39656c2a")
        #expect(info["code"] as? String == "WXCODE")
        #expect(info["wx_info_type"] as? Int == 1)
        #expect(info["check_third_type"] as? Int == 0)
    }

    @Test("登录：返回值在 login_info 里，不是 ct_info（这个坑踩过）")
    func loginReadsLoginInfoNotCtInfo() async throws {
        // 真机上扫码扫成功、微信也提示"已登录"，但 App 报
        // 「登录响应里没有可用的登录态」—— 就是因为我照 refresh_client_ticket
        // 抄了 ct_info，而登录接口返回的是 login_info。
        let box = ScriptBox([Self.loginResponse])
        let q = QRLogin(transport: Self.transport(box))
        let s = try await q.login(code: "X")
        #expect(s.ct == "NEW_CT")        // 只有读对 key 才拿得到
        #expect(s.tid == "NEW_WT")
        #expect(s.userID == "JA-1")
        #expect(s.accessToken == "CTT_VALUE")
    }

    @Test("登录：万一哪天又改回 ct_info，也要能兜住")
    func loginFallsBackToCtInfo() async throws {
        // 兜底分支：login_info 不在、ct_info 在
        let resp = """
        {"result":0,"msg":"","data":{
          "bind_info":[{"openid":"A44A6AA89A42ECA6909C2492C2193D14","uuid":"JA-1"}],
          "ct_info":{"ct":"OLD_CT","wt":"OLD_WT","user_id":"JA-1"}
        }}
        """
        let box = ScriptBox([resp])
        let q = QRLogin(transport: Self.transport(box))
        let s = try await q.login(code: "X")
        #expect(s.ct == "OLD_CT")
        #expect(s.userID == "JA-1")
    }

    @Test("登录：解析不出来时，报错要带上实际结构")
    func loginErrorShowsShape() async {
        // 结构完全不对时，错误信息里得能看出收到了什么 key，
        // 不然下次还得靠猜
        let resp = #"{"result":0,"msg":"","data":{"unexpected":{"a":1}}}"#
        let box = ScriptBox([resp])
        let q = QRLogin(transport: Self.transport(box))
        do {
            _ = try await q.login(code: "X")
            Issue.record("应该抛错")
        } catch {
            let msg = error.localizedDescription
            #expect(msg.contains("unexpected"))     // 把真实 key 列出来了
        }
    }

    @Test("登录：Cookie 的 openid 必须取 bind_info，不能取 ct_info.openid")
    func loginOpenIDFromBindInfo() async throws {
        let box = ScriptBox([Self.loginResponse])
        let q = QRLogin(transport: Self.transport(box))
        let s = try await q.login(code: "X")

        #expect(s.userID == "JA-1")
        #expect(s.ct == "NEW_CT")
        #expect(s.tid == "NEW_WT")
        // ★ ct_info.openid 是掌瓦自己的（74193457a-…_10200），写进 Cookie 就废了
        #expect(s.openID == "A44A6AA89A42ECA6909C2492C2193D14")
        #expect(s.openID != "74193457a-b8d058817457ae26_10200")
        #expect(s.cookieHeader.contains("openid=A44A6AA89A42ECA6909C2492C2193D14"))
        #expect(s.authType == .wechat)
        #expect(s.ctUpdatedAt > 0)
    }

    // MARK: 端到端

    @Test("整条链：ticket → 签名 → 二维码 → 扫码 → 登录")
    func fullFlow() async throws {
        let ticket = "qeuRRdzufZaOpdhfU2Q4gGbgoxq-NLbBLoPmh9nUqyTICKETFAKE"
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0xFF, 0xD9])
        let qrBody = """
        {"errcode":0,"uuid":"U-E2E","qrcode":{"qrcodebase64":"\(jpeg.base64EncodedString())"}}
        """
        let box = ScriptBox([
            #"{"result":0,"msg":"","data":{"ticket":"\#(ticket)"}}"#,   // ① ticket
            qrBody,                                                      // ③ 二维码
            #"{"wx_errcode":408}"#,                                      // ④ 等扫描
            #"{"wx_errcode":405,"wx_code":"WXCODE-E2E"}"#,               // ④ 确认
            Self.loginResponse,                                          // ⑤ 登录
        ])

        let q = QRLogin(transport: Self.transport(box))
        var got: ZhangwaSession?
        q.onSession = { got = $0 }
        q.start()

        // 等流程跑完
        for _ in 0..<100 {
            if q.stage.isTerminal { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(q.stage == .success)
        #expect(got != nil)
        #expect(got?.userID == "JA-1")
        #expect(box.calls.count == 5)

        // ② 签名确实用了 ① 的 ticket
        let qrCall = box.calls[1]
        let expectSig = QRLogin.signature(
            nonce: qrCall.value(of: "noncestr") ?? "",
            ticket: ticket,
            timestamp: qrCall.value(of: "timestamp") ?? "")
        #expect(qrCall.contains("signature=\(expectSig)"))
    }

    // MARK: 测试脚手架

    /// **登录接口的真实返回结构** —— 别照 refresh_client_ticket 抄！
    ///
    /// 依据 com/tencent/wglogin/authsuite/protocol/LoginResult.java：
    ///   data.bind_info   在 data **顶层**
    ///   data.login_info  是 `login_info`，**不是** `ct_info`
    ///
    /// 这两个 key 名字很像、字段名几乎一样，但外层 key 不同。
    /// 我第一版抄错了，导致扫码扫码全成功、卡在最后一步解析不出来。
    static let loginResponse = """
    {"result":0,"msg":"","data":{
      "bind_info":[{"uin":"A44A6AA89A42ECA6909C2492C2193D14",
                    "openid":"A44A6AA89A42ECA6909C2492C2193D14","uuid":"JA-1"}],
      "login_info":{"ct":"NEW_CT","wt":"NEW_WT","user_id":"JA-1",
                    "uin":2751275315,"openid":"74193457a-b8d058817457ae26_10200",
                    "ctt":"CTT_VALUE","login_uuid":"JA-1","is_new_user":0,
                    "refresh_ct_span":604800,"refresh_wt_span":1800}
    }}
    """

    /// 按脚本依次返回响应，并记录每次请求
    final class ScriptBox: @unchecked Sendable {
        private let bodies: [String]
        private let lock = NSLock()
        private var _calls: [String] = []
        private var _bodies: [Data] = []

        init(_ bodies: [String]) { self.bodies = bodies }

        var calls: [String] { lock.withLock { _calls } }
        var sentBodies: [Data] { lock.withLock { _bodies } }

        func next(_ url: String, body: Data?) -> Data {
            lock.withLock {
                _calls.append(url + (url.contains("?") ? "" : ""))
                if let body { _bodies.append(body) }
                let i = min(_calls.count - 1, self.bodies.count - 1)
                return Data(self.bodies[i].utf8)
            }
        }
    }

    static func transport(_ box: ScriptBox) -> QRTransport {
        { req, _ in
            let url = req.url?.absoluteString ?? ""
            let data = box.next(url, body: req.httpBody)
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (data, resp)
        }
    }
}

// MARK: 小工具

private extension String {
    /// 从 URL 里抠一个 query 参数
    func value(of key: String) -> String? {
        guard let comps = URLComponents(string: self) else { return nil }
        return comps.queryItems?.first { $0.name == key }?.value
    }
}

private extension URL {
    func value(of key: String) -> String? { absoluteString.value(of: key) }
}

private extension QRLogin {
    /// 只为轮询状态机测试用的包装
    func pollStageCheck(uuid: String) async throws {
        _ = try await poll(uuid: uuid)
    }
}
