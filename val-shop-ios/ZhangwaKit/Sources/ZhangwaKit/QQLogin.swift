import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// ============================================================================
//  QQ 扫码登录
// ============================================================================
//
//  和微信那条最大的区别：**这是一条纯网页流程**。
//
//  要的只是一个 WKWebView —— 二维码渲染、状态刷新、"已扫描/已过期"的 UI，
//  全部由 QQ 官方页面自己做。我们只负责：
//      算 sign → 拼 URL → 加载 → 截回调 → 换登录态
//
//  ## sign 算法（从 com/tencent/open/utils/n.java:528 逐行还原）
//
//      public static String b(Context ctx, String time) {
//          String pkg = ctx.getPackageName();
//          Signature[] sigs = pm.getPackageInfo(pkg, 64).signatures;
//          MessageDigest md = MessageDigest.getInstance("MD5");
//          md.update(sigs[0].toByteArray());          // 证书 DER
//          String certMd5 = p.a(md.digest());         // hex
//          md.reset();
//          md.update(p.j(pkg + "_" + certMd5 + "_" + time));   // p.j = getBytes("UTF-8")
//          return p.a(md.digest());                   // hex
//      }
//
//  也就是一行：
//
//      sign = md5("{pkg}_{certMd5}_{time}")
//
//  用真机样本自检过（pkg=com.tencent.apps.valorant、time=1792326852
//  -> 1a7fe16b837e17fddc74ecc2232271bc），逐字节一致。
//
//  ## 回调
//
//  QQ 登录成功后页面会跳到 redirect_uri：
//
//      auth://tauth.qq.com/#access_token=XXX&expires_in=YYY&openid=ZZZ&...
//
//  注意是 **fragment（#）** 不是 query（?）。WKWebView 里用
//  decidePolicyFor 拦下来读就行，不用真的去处理这个 scheme。
//
//  ## 换登录态
//
//      POST /go/auth/login_by_qq
//      { clienttype:9, mappid:10200, mcode:"", config_params:{lang_type:0},
//        login_info:{ appid:102061775, openid:…, sig:<access_token>, qq_info_type:5 } }
//
//  `sig` 就是 `access_token` —— 依据 com/tencent/wglogin/sso/openqq/b.java:33，
//  那里把 (openid, accessToken) 塞进 SsoLicense，
//  再由 authsuite/d.java:208 的 loginByQC 填进 LoginInfo。
// ============================================================================

@MainActor
public final class QQLogin {

    // MARK: 常量

    nonisolated public static let qqAppID = "102061775"
    nonisolated public static let mappid = ZhangwaSession.mappid

    /// 掌瓦 APK 的签名证书 MD5。服务端拿它认调用方，所以必须用这个值。
    nonisolated public static let certMD5 = "304c3871ea696f1f96157840d33b413d"
    nonisolated public static let packageName = "com.tencent.apps.valorant"

    nonisolated public static let authorizeURL = "https://openmobile.qq.com/oauth2.0/m_authorize"
    /// 回调用的自定义 scheme。在 WKWebView 里拦下来就行，不用真去处理它。
    nonisolated public static let redirectURI = "auth://tauth.qq.com/"
    nonisolated public static let redirectScheme = "auth"

    /// qq_info_type 的固定值（authsuite/d.java:241）
    nonisolated public static let qqInfoType = 5

    static let hostAPI = "https://app.mval.qq.com"

    // MARK: 状态

    public enum Stage: Equatable, Sendable {
        case idle
        case loading            // 网页在加载
        case waiting            // 二维码出来了，等扫
        case authorizing        // 扫完在换登录态
        case success
        case cancelled
        case failed(String)

        public var text: String {
            switch self {
            case .idle:         return "正在准备…"
            case .loading:      return "正在加载 QQ 登录页…"
            case .waiting:      return "请用手机 QQ 扫一扫"
            case .authorizing:  return "正在登录…"
            case .success:      return "登录成功"
            case .cancelled:    return "已取消"
            case .failed(let m): return "失败：\(m)"
            }
        }

        public var isBusy: Bool {
            switch self {
            case .idle, .loading, .authorizing: return true
            default: return false
            }
        }
    }

    public private(set) var stage: Stage = .idle
    public private(set) var log: [String] = []

    public var onStageChange: (@MainActor (Stage) -> Void)?
    public var onSession: (@MainActor (ZhangwaSession) -> Void)?

    private let transport: QRTransport
    private var scopes: Set<String> = []

    public init(transport: QRTransport? = nil) {
        self.transport = transport ?? QRLogin.defaultTransport
    }

    // MARK: ① 算 sign

    /// 真正算 sign 的地方。
    ///
    /// 从 `com/tencent/open/utils/n.b(Context,String)` 逐行还原：
    ///
    ///     sign = md5("{packageName}_{certMd5}_{time}")
    ///
    /// **是 MD5，不是 SHA1** —— 别和微信那条搞混了。
    ///
    /// 注意 certMD5 是**掌瓦** APK 的证书指纹。服务端靠它认调用方，
    /// 所以必须用掌瓦的值，不能用我们自己的（我们也没有那个证书）。
    nonisolated public static func makeSign(time: String) -> String {
        md5Hex("\(packageName)_\(certMD5)_\(time)")
    }

    /// 当前时间戳（秒）。服务端会校验 time 的时效性，所以每次都要现取。
    nonisolated public static func nowTimestamp() -> String {
        String(Int(Date().timeIntervalSince1970))
    }

    // MARK: ② 拼 URL

    /// 完整的 m_authorize URL。
    ///
    /// 参数顺序不影响校验（服务端只看 sign），但**转义要手动做**：
    /// URLComponents.queryItems 不会把值里的 `:` `/` 转义，
    /// 而 Android SDK 和我们在 PC 上验证通过的那个请求都是转义形态
    /// （`redirect_uri=auth%3A%2F%2Ftauth.qq.com%2F`）。
    /// 虽然按 RFC 3986 两种都合法，但既然验证过的是转义版，就保持一致。
    public func authorizeURL(time: String) -> URL {
        let pairs: [(String, String)] = [
            ("cancel_display", "1"),
            ("sdkp", "a"),
            ("display", "mobile"),
            ("format", "json"),
            ("sign", Self.makeSign(time: time)),
            ("sdkv", "3.5.17.lite"),
            ("response_type", "token"),
            ("status_os", "12"),
            ("client_id", Self.qqAppID),
            ("switch", "1"),
            ("status_version", "32"),
            ("show_download_ui", "true"),
            ("pf", "openmobile_android"),
            ("scope", "all"),
            ("compat_v", "1"),
            ("status_machine", "U00tUzkyMTA="),
            ("style", "qr"),
            ("time", time),
            ("redirect_uri", Self.redirectURI),
        ]
        var comps = URLComponents(string: Self.authorizeURL)!
        comps.percentEncodedQuery = pairs
            .map { "\($0.0)=\(Self.percentEncode($0.1))" }
            .joined(separator: "&")
        return comps.url!
    }

    /// 把所有非 unreserved 字符都转义掉（和 Android 的 UrlEncoder 行为一致）。
    nonisolated static func percentEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }


    // MARK: ③ 截回调

    public struct Credentials: Equatable, Sendable {
        public let openID: String
        public let accessToken: String
        public let expiresIn: String?

        public var isValid: Bool { !openID.isEmpty && !accessToken.isEmpty }
    }

    /// 解析 `auth://tauth.qq.com/#access_token=…&openid=…&expires_in=…`
    ///
    /// ⚠️ 这些值在 **fragment（#）** 里，不是 query（?）。
    /// 用 URLComponents 的 queryItems 会拿到空 —— 这是最容易踩的坑。
    nonisolated public static func parseCallback(_ url: URL) -> Credentials? {
        let s = url.absoluteString
        guard s.hasPrefix(redirectScheme + "://") else { return nil }

        var pairs: [String: String] = [:]
        // fragment 优先，兜底也看一眼 query（不同版本 SDK 有差异）
        for part in [url.fragment, url.query].compactMap({ $0 }) {
            for kv in part.split(separator: "&") {
                let seg = kv.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard seg.count == 2 else { continue }
                let k = String(seg[0])
                let v = String(seg[1]).removingPercentEncoding ?? String(seg[1])
                if pairs[k] == nil { pairs[k] = v }
            }
        }

        guard let openID = pairs["openid"], !openID.isEmpty,
              let token = pairs["access_token"], !token.isEmpty else { return nil }
        return Credentials(openID: openID, accessToken: token,
                           expiresIn: pairs["expires_in"])
    }

    /// 是不是我们要拦的那个回调
    nonisolated public static func isCallback(_ url: URL) -> Bool {
        url.absoluteString.hasPrefix(redirectScheme + "://")
    }

    // MARK: ④ 换登录态

    public func login(_ creds: Credentials) async throws -> ZhangwaSession {
        let payload: [String: Any] = [
            "clienttype": QRLogin.clientType,
            "mappid": Self.mappid,
            "mcode": "",
            "config_params": ["lang_type": 0],
            "login_info": [
                "appid": Int(Self.qqAppID) ?? 0,
                "openid": creds.openID,
                "sig": creds.accessToken,     // ★ sig 就是 access_token
                "qq_info_type": Self.qqInfoType,
            ],
        ]
        var req = URLRequest(url: URL(string: Self.hostAPI + "/go/auth/login_by_qq")!)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue(QRLogin.anonymousCookie, forHTTPHeaderField: "Cookie")
        req.setValue("okhttp/4.9.2", forHTTPHeaderField: "User-Agent")

        let (data, http) = try await transport(req, 25)
        guard (200..<300).contains(http.statusCode) else {
            throw ZhangwaError.transport("HTTP \(http.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ZhangwaError.transport("登录响应不是 JSON")
        }
        let result = ZhangwaClient.intValue(json["result"]) ?? -1
        guard result == 0 else {
            throw ZhangwaError.api(code: result,
                                   msg: ZhangwaClient.stringValue(json["msg"]) ?? "",
                                   dataPreview: nil)
        }

        var session = ZhangwaSession()
        session.authType = .qq
        let root = (json["data"] as? [String: Any]) ?? json
        if let info = root["ct_info"] as? [String: Any] {
            session.ct = ZhangwaClient.stringValue(info["ct"]) ?? ""
            session.tid = ZhangwaClient.stringValue(info["wt"]) ?? ""
            session.userID = ZhangwaClient.stringValue(info["user_id"]) ?? ""
            if let u = ZhangwaClient.intValue(info["uin"]) { session.uin = Int64(u) }
        }
        // Cookie 的 openid 用 bind_info 的（QQ openid），不是 ct_info.openid
        if let binds = root["bind_info"] as? [[String: Any]],
           let mine = binds.first(where: { ZhangwaClient.stringValue($0["uuid"]) == session.userID })
                       ?? binds.first,
           let oid = ZhangwaClient.stringValue(mine["openid"]) {
            session.openID = oid
        }
        // 兜底：万一没 bind_info，就用回调里的 openid（对 QQ 来说通常是对的）
        if session.openID.isEmpty { session.openID = creds.openID }
        session.ctUpdatedAt = Date().timeIntervalSince1970

        guard session.isValid else {
            throw ZhangwaError.transport("登录响应里没有可用的登录态")
        }
        return session
    }

    // MARK: 状态管理（给 UI 用）

    public func markLoading() { set(.loading) }
    public func markWaiting() { set(.waiting) }
    public func markCancelled() { set(.cancelled) }

    /// 收到回调后一条龙：换登录态 + 通知
    public func complete(with url: URL) {
        guard let creds = Self.parseCallback(url) else {
            // 取消登录时 QQ 也会跳这个 scheme，但没带 token
            set(.cancelled)
            log("回调没有 token（多半是用户取消了）")
            return
        }
        set(.authorizing)
        log("拿到 openid=\(creds.openID.prefix(8))… access_token=\(creds.accessToken.prefix(8))…")
        Task { [weak self] in
            guard let self else { return }
            do {
                let s = try await login(creds)
                set(.success)
                log("登录成功，userID=\(s.userID)")
                onSession?(s)
            } catch {
                set(.failed(error.localizedDescription))
                log("✗ \(error.localizedDescription)")
            }
        }
    }

    private func set(_ s: Stage) {
        stage = s
        onStageChange?(s)
    }

    private func log(_ line: String) {
        log.append(line)
        if log.count > 40 { log.removeFirst() }
    }
}

// MARK: - MD5

/// 就为算 QQ 的 sign。QQ 那边用的是 MD5（60 位以内的短输入，够用）。
/// 不用 CryptoKit 的原因和 SHA1.swift 一样：包要在 Windows 上跑测试。
func md5Hex(_ string: String) -> String {
    md5(Array(string.utf8)).map { String(format: "%02x", $0) }.joined()
}

private func md5(_ message: [UInt8]) -> [UInt8] {
    // RFC 1321
    let s: [UInt32] = [7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
                       5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
                       4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
                       6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21]

    // ⚠️ K 表**必须硬编码**，不能现算。
    //
    // K[i] = floor(abs(sin(i+1)) * 2^32)，但这个值非常接近整数，
    // 双精度浮点在乘完之后可能落在整数下面一丁点（比如 3614090359.9999），
    // 截断就得到 3614090359 —— 整个哈希全错。我第一版就是这么挂的（连 "abc" 都不对）。
    // 硬编码是所有人最终都会采取的做法。
    let k: [UInt32] = [
        0xD76AA478, 0xE8C7B756, 0x242070DB, 0xC1BDCEEE,
        0xF57C0FAF, 0x4787C62A, 0xA8304613, 0xFD469501,
        0x698098D8, 0x8B44F7AF, 0xFFFF5BB1, 0x895CD7BE,
        0x6B901122, 0xFD987193, 0xA679438E, 0x49B40821,
        0xF61E2562, 0xC040B340, 0x265E5A51, 0xE9B6C7AA,
        0xD62F105D, 0x02441453, 0xD8A1E681, 0xE7D3FBC8,
        0x21E1CDE6, 0xC33707D6, 0xF4D50D87, 0x455A14ED,
        0xA9E3E905, 0xFCEFA3F8, 0x676F02D9, 0x8D2A4C8A,
        0xFFFA3942, 0x8771F681, 0x6D9D6122, 0xFDE5380C,
        0xA4BEEA44, 0x4BDECFA9, 0xF6BB4B60, 0xBEBFBC70,
        0x289B7EC6, 0xEAA127FA, 0xD4EF3085, 0x04881D05,
        0xD9D4D039, 0xE6DB99E5, 0x1FA27CF8, 0xC4AC5665,
        0xF4292244, 0x432AFF97, 0xAB9423A7, 0xFC93A039,
        0x655B59C3, 0x8F0CCC92, 0xFFEFF47D, 0x85845DD1,
        0x6FA87E4F, 0xFE2CE6E0, 0xA3014314, 0x4E0811A1,
        0xF7537E82, 0xBD3AF235, 0x2AD7D2BB, 0xEB86D391,
    ]

    var a0: UInt32 = 0x6745_2301
    var b0: UInt32 = 0xEFCD_AB89
    var c0: UInt32 = 0x98BA_DCFE
    var d0: UInt32 = 0x1032_5476

    var data = message
    let bitLength = UInt64(message.count) * 8
    data.append(0x80)
    while data.count % 64 != 56 { data.append(0) }
    // ⚠️ 长度字段是**小端**（先低字节）。
    // 写成大端的话，空字符串照样对（长度为 0，8 个字节全是 00，看不出端序），
    // 但任何非空输入都会算错 —— 这个 bug 特别能骗过"空串自测"。
    for shift in stride(from: 0, through: 56, by: 8) {
        data.append(UInt8((bitLength >> UInt64(shift)) & 0xFF))
    }

    for chunk in stride(from: 0, to: data.count, by: 64) {
        var m = [UInt32](repeating: 0, count: 16)
        for i in 0..<16 {
            let j = chunk + i * 4
            m[i] = (UInt32(data[j]) | (UInt32(data[j + 1]) << 8)
                    | (UInt32(data[j + 2]) << 16) | (UInt32(data[j + 3]) << 24))
        }
        var a = a0, b = b0, c = c0, d = d0
        for i in 0..<64 {
            var f: UInt32
            var g: Int
            switch i {
            case 0..<16:  f = (b & c) | (~b & d);        g = i
            case 16..<32: f = (d & b) | (~d & c);        g = (5 * i + 1) % 16
            case 32..<48: f = b ^ c ^ d;                 g = (3 * i + 5) % 16
            default:      f = c ^ (b | ~d);              g = (7 * i) % 16
            }
            f = f &+ a &+ k[i] &+ m[g]
            a = d; d = c; c = b
            b = b &+ rotl(f, s[i])
        }
        a0 = a0 &+ a; b0 = b0 &+ b; c0 = c0 &+ c; d0 = d0 &+ d
    }

    var out = [UInt8]()
    for v in [a0, b0, c0, d0] {
        out.append(UInt8(v & 0xFF))
        out.append(UInt8((v >> 8) & 0xFF))
        out.append(UInt8((v >> 16) & 0xFF))
        out.append(UInt8((v >> 24) & 0xFF))
    }
    return out
}

private func rotl(_ v: UInt32, _ n: UInt32) -> UInt32 {
    (v << n) | (v >> (32 - n))
}
