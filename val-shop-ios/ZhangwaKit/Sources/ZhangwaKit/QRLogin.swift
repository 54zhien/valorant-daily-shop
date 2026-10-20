import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// ============================================================================
//  扫码登录
// ============================================================================
//
//  这是**官方渠道**：二维码由微信官方服务器为掌瓦的官方 AppID 生成，
//  授权码由微信下发，掌瓦的服务器拿它换登录态。我们只是把掌瓦客户端做的事
//  用 Swift 重做了一遍。
//
//  整条链路（全部实测验证过）：
//
//    ① POST https://app.mval.qq.com/go/auth/get_sdk_ticket     body {}
//         —— 匿名 Cookie 就行，不需要任何登录态
//         -> { "ticket": "qeuRRdz…" }（86 字符，会话级前缀 + 每请求 nonce）
//
//    ② signature = SHA1("appid={A}&noncestr={N}&sdk_ticket={T}&timestamp={TS}")
//         —— 参数名是 sdk_ticket 不是 ticket；scope 不参与；字母序
//         —— 不需要 AppSecret，全靠 ① 下发的 ticket
//
//    ③ GET https://open.weixin.qq.com/connect/sdk/qrconnect
//             ?appid=…&noncestr=…&timestamp=…&scope=snsapi_userinfo&signature=…
//         -> { uuid, qrcode: { qrcodebase64 } }   ← base64 是 JPEG（不是 PNG）
//
//    ④ GET https://long.open.weixin.qq.com/connect/l/qrconnect?f=json&uuid=…
//         长轮询，一次挂 ~15-30 秒。wx_errcode：
//             408 UUID_KEEP_CONNECT  等扫描    -> 继续
//             404 UUID_SCANED        已扫待确认 -> 继续
//             405 UUID_CONFIRM       已确认     -> 带 wx_code，往下走
//             402 UUID_EXPIRED       二维码过期 -> 换一张
//             403 UUID_CANCELED      用户取消   -> 停
//             500 UUID_ERROR         出错       -> 报错
//
//    ⑤ POST https://app.mval.qq.com/go/auth/login_by_wechat
//         { clienttype:9, mappid:10200, mcode:"", config_params:{lang_type:0},
//           login_info:{ appid:…, code:<wx_code>, wx_info_type:1, check_third_type:0 } }
//         -> 完整登录态（ct / wt），和抓包拿到的是同一个东西
//
//  之后 ct 照旧自动滚动续期 —— 所以扫一次就够长期用了。
// ============================================================================

/// 网络的抽象，方便离线测试
public typealias QRTransport = @Sendable (URLRequest, TimeInterval) async throws -> (Data, HTTPURLResponse)

@MainActor
public final class QRLogin {

    // MARK: 常量（全部来自逆向）

    nonisolated public static let appID = ZhangwaSession.appIDWX   // wxcbb49f1f39656c2a
    nonisolated public static let mappid = ZhangwaSession.mappid   // 10200
    nonisolated public static let scope = "snsapi_userinfo"
    nonisolated public static let clientType = 9
    nonisolated public static let wxInfoType = 1
    nonisolated public static let checkThirdType = 0

    static let hostAPI = "https://app.mval.qq.com"
    static let hostQR = "https://open.weixin.qq.com/connect/sdk/qrconnect"
    static let hostPoll = "https://long.open.weixin.qq.com/connect/l/qrconnect"

    /// 轮询一次最多挂多久。服务端自己会在 15-30 秒左右返回。
    static let pollTimeout: TimeInterval = 40

    /// 取票 / 取码单次超时。原来是 25 秒 —— 网络不通时用户就干等 25 秒，
    /// 现在 10 秒就放弃并立刻重试（重试会换一条新连接，很多"卡住"其实是坏连接）。
    static let stepTimeout: TimeInterval = 10

    /// 预取的码能用多久（二维码本身有效期约 5 分钟，2 分钟内复用没有风险）
    static let preloadTTL: TimeInterval = 120

    /// 预取到、还没人用的二维码
    private static var preloaded: (image: QRImage, at: Date)?

    /// 提前把二维码取好 —— 在「我的」页出现时调一次。
    /// 这样用户点「微信扫码登录」时，码已经是现成的了。
    public static func preload() async {
        if let p = preloaded, Date().timeIntervalSince(p.at) < preloadTTL { return }
        let probe = QRLogin()
        do {
            let qr = try await probe.prepareQRCode()
            preloaded = (qr, Date())
        } catch {
            // 预取失败没关系：用户点开时还会重试
        }
    }

    // MARK: 状态

    public enum Stage: Equatable, Sendable {
        case idle
        case preparing          // 拿 ticket + 申请二维码
        case waiting            // 二维码已显示，等扫描        (408)
        case scanned            // 已扫描，等用户点确认         (404)
        case authorizing        // 已确认，正在换登录态         (405)
        case success            // 拿到登录态
        case expired            // 二维码过期                  (402)
        case cancelled          // 用户取消                    (403)
        case failed(String)

        public var text: String {
            switch self {
            case .idle:         return "点下面的按钮开始"
            case .preparing:    return "正在申请二维码…"
            case .waiting:      return "请用微信扫一扫"
            case .scanned:      return "已扫描，请在手机上点「确认登录」"
            case .authorizing:  return "正在登录…"
            case .success:      return "登录成功"
            case .expired:      return "二维码已过期，点一下换一张"
            case .cancelled:    return "已取消"
            case .failed(let m): return "失败：\(m)"
            }
        }

        /// 还在进行中（UI 要转圈 / 要继续轮询）
        public var isBusy: Bool {
            switch self {
            case .preparing, .authorizing: return true
            default: return false
            }
        }

        public var isTerminal: Bool {
            switch self {
            case .success, .cancelled, .failed: return true
            default: return false
            }
        }
    }

    public struct QRImage: Equatable, Sendable {
        public let uuid: String
        /// 原始图片字节。**是 JPEG**，字段名却叫 qrcodebase64 —— 别按 PNG 解。
        public let data: Data
    }

    // MARK: 属性

    public private(set) var stage: Stage = .idle
    public private(set) var image: QRImage?
    public private(set) var log: [String] = []

    /// 状态变化回调（UI 订阅用）
    public var onStageChange: (@MainActor (Stage) -> Void)?
    /// 二维码到手就立刻回调 —— 视图不用再自己轮询 `image` 了。
    /// （以前那套「每 50ms 轮询、最多 100 次」= 5 秒上限：网慢一点码回来了界面也不显示。）
    public var onImage: (@MainActor (QRImage) -> Void)?
    /// 成功拿到登录态
    public var onSession: (@MainActor (ZhangwaSession) -> Void)?

    private let transport: QRTransport
    private var task: Task<Void, Never>?

    public init(transport: QRTransport? = nil) {
        self.transport = transport ?? QRLogin.defaultTransport
    }

    // MARK: 默认网络实现

    public static let defaultTransport: QRTransport = { request, timeout in
        var req = request
        req.timeoutInterval = timeout
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw ZhangwaError.transport("响应不是 HTTP")
        }
        return (data, http)
    }

    // MARK: 对外

    /// 跑完整条链：拿二维码 → 等扫码 → 换登录态。
    public func start() {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            // 码过期就自动再来一张（最多 2 次）。
            // 以前是直接停在「已过期，点一下换一张」—— 用户扫到一半码过期是常事，
            // 让他自己点一次纯属把我们的问题丢给他。
            var autoRefreshed = 0
            while !Task.isCancelled {
                let expired = await self.run()
                guard expired, autoRefreshed < 2, !Task.isCancelled else { break }
                autoRefreshed += 1
                self.log("二维码过期，自动换一张（第 \(autoRefreshed) 次）")
            }
        }
    }

    /// 二维码过期时换一张
    public func refresh() { start() }

    public func cancel() {
        task?.cancel()
        task = nil
        setStage(.cancelled)
    }

    // MARK: 流程

    /// 跑一轮。返回 `true` 表示**二维码过期**（外层会自动换一张）。
    private func run() async -> Bool {
        do {
            setStage(.preparing)

            // ① ticket + ② 签名 + ③ 申请二维码 —— 一起重试：
            //    这三步里任何一步网络抖一下，以前都是直接报错让用户重扫，
            //    现在自动重试 3 次（0.6s、1.2s 退避），绝大多数抖动都能自己过去。
            let qr = try await prepareQRCode()
            image = qr
            onImage?(qr)
            setStage(.waiting)
            log("③ 拿到二维码 uuid=\(qr.uuid)，图片 \(qr.data.count) 字节")

            // ④ 长轮询
            let code = try await poll(uuid: qr.uuid)

            // ⑤ 换登录态
            setStage(.authorizing)
            let session = try await login(code: code)
            setStage(.success)
            log("⑤ 登录成功，userID=\(session.userID)")
            onSession?(session)
            return false

        } catch is CancellationError {
            setStage(.cancelled)
            return false
        } catch let ZhangwaError.api(code, _, _) where code == 402 {
            log("二维码过期（402）")
            return true
        } catch let ZhangwaError.api(code, _, _) where code == 403 {
            setStage(.cancelled)
            log("用户取消（403）")
            return false
        } catch {
            setStage(.failed(error.localizedDescription))
            log("✗ \(error.localizedDescription)")
            return false
        }
    }

    /// ① ticket → ② 签名 → ③ 申请二维码，带重试。
    ///
    /// 有预取好的码就直接用（`preload()` 在「我的」页出现时就跑过了），
    /// 用户点开扫码页看到的是一张现成的码，0 等待。
    private func prepareQRCode(attempts: Int = 2) async throws -> QRImage {
        if let p = Self.preloaded, Date().timeIntervalSince(p.at) < Self.preloadTTL {
            Self.preloaded = nil
            log("⚡️ 用预取的二维码（\(Int(Date().timeIntervalSince(p.at))) 秒前取的）")
            return p.image
        }
        var lastError: Error?
        for attempt in 0..<attempts {
            try Task.checkCancellation()
            do {
                let ticket = try await requestTicket()
                log("① ticket 长度 \(ticket.count)（第 \(attempt + 1) 次）")

                let nonce = Self.randomNonce()
                let ts = String(Int(Date().timeIntervalSince1970))
                let signature = Self.signature(nonce: nonce, ticket: ticket, timestamp: ts)

                return try await requestQRCode(nonce: nonce, timestamp: ts, signature: signature)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                log("⟳ 第 \(attempt + 1) 次取码失败：\(error.localizedDescription)")
                if attempt + 1 < attempts {
                    try? await Task.sleep(nanoseconds: UInt64(600_000_000) * UInt64(attempt + 1))
                }
            }
        }
        throw lastError ?? ZhangwaError.transport("取码失败")
    }

    // MARK: 各步骤

    /// ① `POST /go/auth/get_sdk_ticket`，body 是空对象，匿名 Cookie 就够
    public func requestTicket() async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: [String: Any]())
        var req = URLRequest(url: URL(string: Self.hostAPI + "/go/auth/get_sdk_ticket")!)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.anonymousCookie, forHTTPHeaderField: "Cookie")
        req.setValue("okhttp/4.9.2", forHTTPHeaderField: "User-Agent")

        let (data, http) = try await transport(req, Self.stepTimeout)
        let json = try Self.decode(data, http)
        let code = ZhangwaClient.intValue(json["result"]) ?? -1
        guard code == 0 else {
            throw ZhangwaError.api(code: code, msg: ZhangwaClient.stringValue(json["msg"]) ?? "", dataPreview: nil)
        }
        guard let root = json["data"] as? [String: Any],
              let ticket = ZhangwaClient.stringValue(root["ticket"]), !ticket.isEmpty else {
            throw ZhangwaError.notConfigured("get_sdk_ticket 没返回 ticket")
        }
        return ticket
    }

    /// 制签。踩过的三个坑都写在这儿了：
    ///   · 参数名是 `sdk_ticket`，不是 `ticket`
    ///   · `scope` **不参与**签名（虽然它出现在请求 URL 上）
    ///   · 顺序是**字母序**
    nonisolated public static func signature(nonce: String, ticket: String, timestamp: String) -> String {
        let preimage = "appid=\(appID)&noncestr=\(nonce)&sdk_ticket=\(ticket)&timestamp=\(timestamp)"
        return SHA1.hex(preimage)
    }

    /// ③ 申请二维码
    public func requestQRCode(nonce: String, timestamp: String, signature: String) async throws -> QRImage {
        var comps = URLComponents(string: Self.hostQR)!
        comps.queryItems = [
            .init(name: "appid", value: Self.appID),
            .init(name: "noncestr", value: nonce),
            .init(name: "timestamp", value: timestamp),
            .init(name: "scope", value: Self.scope),
            .init(name: "signature", value: signature),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) "
                     + "AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
                     forHTTPHeaderField: "User-Agent")
        req.setValue("https://open.weixin.qq.com/", forHTTPHeaderField: "Referer")

        let (data, _) = try await transport(req, Self.stepTimeout)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ZhangwaError.transport("二维码响应不是 JSON")
        }
        let errcode = ZhangwaClient.intValue(json["errcode"]) ?? -1
        guard errcode == 0 else {
            // 最常见的失败：signature mismatch
            let msg = ZhangwaClient.stringValue(json["errmsg"]) ?? ""
            throw ZhangwaError.transport("申请二维码被拒（errcode=\(errcode) \(msg)）")
        }
        guard let uuid = ZhangwaClient.stringValue(json["uuid"]), !uuid.isEmpty,
              let qr = json["qrcode"] as? [String: Any],
              let b64 = ZhangwaClient.stringValue(qr["qrcodebase64"]),
              let bytes = Data(base64Encoded: b64) else {
            throw ZhangwaError.transport("二维码响应结构不对：\(json.keys.sorted())")
        }
        return QRImage(uuid: uuid, data: bytes)
    }

    /// ④ 长轮询，直到拿到 wx_code
    public func poll(uuid: String) async throws -> String {
        var last: Int? = nil
        /// 连续失败次数：长轮询抖一下不该让整个会话结束
        var hiccups = 0
        // 二维码大约 5 分钟有效，轮询按 30 秒一次算，给足余量
        for _ in 0..<60 {
            try Task.checkCancellation()

            var comps = URLComponents(string: Self.hostPoll)!
            var items = [URLQueryItem(name: "f", value: "json"),
                         URLQueryItem(name: "uuid", value: uuid)]
            if let last { items.append(.init(name: "last", value: String(last))) }
            comps.queryItems = items

            var req = URLRequest(url: comps.url!)
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) "
                         + "AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
                         forHTTPHeaderField: "User-Agent")

            var data = Data()
            do {
                let result = try await transport(req, Self.pollTimeout)
                data = result.0
                hiccups = 0
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                hiccups += 1
                // 连续 4 次都失败才认输；中间任何一次成功就重新计数
                if hiccups > 4 { throw error }
                try? await Task.sleep(nanoseconds: 400_000_000)
                continue
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let errcode = ZhangwaClient.intValue(json["wx_errcode"]) ?? 500
            last = errcode

            switch errcode {
            case 405:                                  // UUID_CONFIRM
                guard let code = ZhangwaClient.stringValue(json["wx_code"]), !code.isEmpty else {
                    throw ZhangwaError.transport("已确认但没带 wx_code")
                }
                return code
            case 404:                                  // UUID_SCANED
                if stage != .scanned { setStage(.scanned) }
            case 408:                                  // UUID_KEEP_CONNECT
                if stage != .waiting { setStage(.waiting) }
            case 402:                                  // UUID_EXPIRED
                throw ZhangwaError.api(code: 402, msg: "二维码已过期", dataPreview: nil)
            case 403:                                  // UUID_CANCELED
                throw ZhangwaError.api(code: 403, msg: "用户取消", dataPreview: nil)
            default:                                   // 500 及其它
                throw ZhangwaError.transport("轮询出错 wx_errcode=\(errcode)")
            }
        }
        throw ZhangwaError.api(code: 402, msg: "二维码超时", dataPreview: nil)
    }

    /// ⑤ 用 wx_code 换登录态
    public func login(code: String) async throws -> ZhangwaSession {
        let payload: [String: Any] = [
            "clienttype": Self.clientType,
            "mappid": Self.mappid,
            "mcode": "",
            "config_params": ["lang_type": 0],
            "login_info": [
                "appid": Self.appID,
                "code": code,
                "wx_info_type": Self.wxInfoType,
                "check_third_type": Self.checkThirdType,
            ],
        ]
        var req = URLRequest(url: URL(string: Self.hostAPI + "/go/auth/login_by_wechat")!)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.anonymousCookie, forHTTPHeaderField: "Cookie")
        req.setValue("okhttp/4.9.2", forHTTPHeaderField: "User-Agent")

        let (data, http) = try await transport(req, Self.stepTimeout)
        let json = try Self.decode(data, http)
        let result = ZhangwaClient.intValue(json["result"]) ?? -1
        guard result == 0 else {
            throw ZhangwaError.api(code: result,
                                   msg: ZhangwaClient.stringValue(json["msg"]) ?? "",
                                   dataPreview: nil)
        }

        // ⚠️ 这里是 `login_info`，**不是** `ct_info`。
        //
        // refresh_client_ticket 返回的是 data.ct_info，
        // 但 login_by_wechat 返回的是 data.login_info，两者字段名一样但外层 key 不同。
        // 而且 bind_info 在 **data 顶层**，不在 login_info 里面。
        // （依据 com/tencent/wglogin/authsuite/protocol/LoginResult.java）
        //
        // 第一版我照 refresh 抄了 ct_info，结果扫码扫码全成功、卡在最后一步
        // 报「登录响应里没有可用的登录态」—— 就是这儿。
        var session = ZhangwaSession()
        session.authType = .wechat
        let root = (json["data"] as? [String: Any]) ?? json
        let info = (root["login_info"] as? [String: Any])
            ?? (root["ct_info"] as? [String: Any])     // 兜底：万一哪天又改回去
            ?? root
        session.ct = ZhangwaClient.stringValue(info["ct"]) ?? ""
        session.tid = ZhangwaClient.stringValue(info["wt"]) ?? ""
        session.userID = ZhangwaClient.stringValue(info["user_id"]) ?? ""
        if let u = ZhangwaClient.intValue(info["uin"]) { session.uin = Int64(u) }

        // Cookie 的 openid 必须来自 bind_info（那里是 QQ/微信 的 openid），
        // 不能用 login_info.openid（那是掌瓦自己的）—— 详见 ZhangwaClient 里的注释
        if let binds = (root["bind_info"] as? [[String: Any]])
                        ?? (root["accounts"] as? [[String: Any]]),
           let mine = binds.first(where: { ZhangwaClient.stringValue($0["uuid"]) == session.userID })
                       ?? binds.first,
           let oid = ZhangwaClient.stringValue(mine["openid"]) {
            session.openID = oid
        }
        // 再兜底一次：login_info.third_openid 有时是公众号侧的 openid
        if session.openID.isEmpty {
            session.openID = ZhangwaClient.stringValue(info["third_openid"]) ?? ""
        }
        session.accessToken = ZhangwaClient.stringValue(info["ctt"]) ?? ""
        session.ctUpdatedAt = Date().timeIntervalSince1970

        guard session.isValid else {
            // 把实际拿到的结构吐出来 —— 下次再对不上就不用瞎猜了
            let keys = root.keys.sorted().joined(separator: ",")
            let infoKeys = info.keys.sorted().joined(separator: ",")
            throw ZhangwaError.transport(
                "登录响应里没有可用的登录态。data=[\(keys)] info=[\(infoKeys)]")
        }
        return session
    }

    // MARK: 杂项

    static let anonymousCookie = "clientType=9; openid=null; access_token=null;"

    /// 6 位随机串。真机抓到的就是 6 位（mnfKFk / CZeFon / ad32XH / nkIDJi / WM7gpb / qFuXLe）
    nonisolated public static func randomNonce(length: Int = 6) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    private static func decode(_ data: Data, _ http: HTTPURLResponse) throws -> [String: Any] {
        guard (200..<300).contains(http.statusCode) else {
            throw ZhangwaError.transport("HTTP \(http.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ZhangwaError.transport("响应不是 JSON")
        }
        return json
    }

    private func setStage(_ s: Stage) {
        stage = s
        onStageChange?(s)
    }

    private func log(_ line: String) {
        log.append(line)
        if log.count > 40 { log.removeFirst() }
    }
}
