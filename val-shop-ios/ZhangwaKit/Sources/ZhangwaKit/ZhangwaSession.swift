import Foundation

// MARK: - SSO 类型

/// 对应 `com.tencent.wglogin.datastruct.SsoAuthType`
/// （WT=0, WX=1, OPEN_QQ=4, TOURIST=255）
public enum SsoAuthType: Int, Codable, CaseIterable, Sendable {
    case wt = 0        // 掌瓦票据登录
    case wechat = 1    // 微信
    case qq = 4        // QQ 互联
    case tourist = 255 // 游客

    /// `AppContext.a(...)` 里 authType -> accountType 的映射：
    /// 0→1、1→2、4→5、其它→1
    public var accountType: Int {
        switch self {
        case .wt, .tourist: return 1
        case .wechat: return 2
        case .qq: return 5
        }
    }

    public var displayName: String {
        switch self {
        case .qq: return "QQ"
        case .wechat: return "微信"
        case .wt: return "掌瓦票据"
        case .tourist: return "游客"
        }
    }
}

// MARK: - 登录态

/// 掌瓦登录态。
///
/// 字段名与 `com.tencent.container.app.AppContext` 一一对应：
///
/// | 本结构        | AppContext          | Cookie            |
/// |--------------|---------------------|-------------------|
/// | `userID`     | `.b`                | `userId`          |
/// | `ct`         | `.c`                | —（不发送，仅用于换票） |
/// | `tid`        | `.e`（= wt）         | `tid`             |
/// | `authType`   | `.f`                | —                 |
/// | `openID`     | `.h`                | `openid`          |
/// | `uin`        | `.i`                | `uin`（带 `o` 前缀）|
/// | `accessToken`| `.j`                | `access_token`    |
/// | `accountType`| `.g`                | `accountType`     |
public struct ZhangwaSession: Codable, Equatable, Sendable {
    public var userID: String = ""
    /// Client Ticket，用于换 wt / ctt。不在 Cookie 里，但刷新票据必须有它。
    public var ct: String = ""
    /// Cookie 里的 `tid`。实测就是 AppContext 的 wt（web ticket）。
    public var tid: String = ""
    public var openID: String = ""
    public var uin: Int64 = 0
    public var accessToken: String = ""
    public var authType: SsoAuthType = .qq
    public var loginUUID: String = ""
    /// access_token 过期时间戳（秒）；0 = 未知
    public var expiresAt: TimeInterval = 0
    /// 这份 `ct` 是什么时候拿到的（unix 秒）。0 = 未知。
    ///
    /// 为什么要记这个：`ct` 的有效期是 7 天（抓包实测 `refresh_ct_span = 604800`），
    /// 但只要在过期前用旧 ct 换一张新的，就能**一直滚动续期** ——
    /// 也就是说抓一次包就够用一辈子，不用反复抓。
    public var ctUpdatedAt: TimeInterval = 0
    public var extraCookies: [String: String] = [:]
    /// 抓到原始 Cookie 时原样保存，保证零损耗回放
    public var rawCookieHeader: String = ""

    public init() {}

    // 常量，全部来自 AndroidManifest.xml
    public static let clientType = "9"
    public static let appIDQQ = "102061775"          // meta-data: openqq_appid
    public static let appIDWX = "wxcbb49f1f39656c2a" // meta-data: wx_appid
    public static let mappid = 10200                 // meta-data: login_mappid

    /// ct 有效期：7 天（`refresh_ct_span = 604800`）
    public static let ctLifetime: TimeInterval = 604_800
    /// wt 有效期：30 分钟（`refresh_wt_span = 1800`）—— 过期就 999999
    public static let wtLifetime: TimeInterval = 1_800

    /// 隔多久续一次 ct。
    ///
    /// **这个值直接决定了「多久必须打开一次 App」。**
    /// ct 本身活 7 天，但只要在过期前用旧的换一张新的，就能一直滚下去。
    /// 设成 1 天的话：每天开一次 App（哪怕只开一下就关）ct 就永远活着，
    /// 而且留了 6 天余量 —— 忘了开几天也不会死。
    ///
    /// 之前设的是「剩 1 天才续」（= 第 6 天），那样只要 7 天没开 App 就断了，
    /// 余量太小。宁可多调一次接口，也要把余量拉满。
    public static let ctRenewInterval: TimeInterval = 86_400

    public var accountType: Int { authType.accountType }

    public var isQQ: Bool { accountType == 5 }

    public var isValid: Bool {
        if !rawCookieHeader.isEmpty { return true }
        return !userID.isEmpty && (!ct.isEmpty || !tid.isEmpty)
    }

    // MARK: Cookie 拼装 —— 严格对齐 com.tencent.container.c.a.a#a(String)

    public var cookiePairs: [(String, String)] {
        if !rawCookieHeader.isEmpty {
            return rawCookieHeader
                .split(separator: ";")
                .compactMap { part -> (String, String)? in
                    guard let idx = part.firstIndex(of: "=") else { return nil }
                    let k = part[part.startIndex..<idx].trimmingCharacters(in: .whitespaces)
                    let v = part[part.index(after: idx)...].trimmingCharacters(in: .whitespaces)
                    return k.isEmpty ? nil : (k, v)
                }
        }

        var pairs: [(String, String)] = [("clientType", Self.clientType)]

        switch accountType {
        case 5:
            if uin != 0 { pairs.append(("uin", "o\(uin)")) }   // 注意 o 前缀
            pairs.append(("appid", Self.appIDQQ))
            pairs.append(("acctype", "qc"))
        case 2:
            pairs.append(("appid", Self.appIDWX))
            pairs.append(("acctype", "wx"))
        default:
            pairs.append(("appid", Self.appIDQQ))
            pairs.append(("acctype", "qc"))
        }

        if !openID.isEmpty { pairs.append(("openid", openID)) }
        if !accessToken.isEmpty { pairs.append(("access_token", accessToken)) }
        if !userID.isEmpty {
            pairs.append(("userId", userID))
            pairs.append(("accountType", String(accountType)))
        }
        if !tid.isEmpty { pairs.append(("tid", tid)) }
        for (k, v) in extraCookies { pairs.append((k, v)) }
        return pairs
    }

    public var cookieHeader: String {
        cookiePairs.map { "\($0.0)=\($0.1)" }.joined(separator: "; ")
    }

    // MARK: 从抓包数据构造

    /// 从 Cookie 头字符串解析（最省事的接入方式）。
    public static func from(cookieHeader: String) -> ZhangwaSession {
        var s = ZhangwaSession()
        s.rawCookieHeader = cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines)

        var kv: [String: String] = [:]
        for part in cookieHeader.split(separator: ";") {
            guard let idx = part.firstIndex(of: "=") else { continue }
            let k = part[part.startIndex..<idx].trimmingCharacters(in: .whitespaces).lowercased()
            let v = part[part.index(after: idx)...].trimmingCharacters(in: .whitespaces)
            kv[k] = v
        }

        s.userID = kv["userid"] ?? ""
        s.tid = kv["tid"] ?? ""
        s.openID = kv["openid"] ?? ""
        s.accessToken = kv["access_token"] ?? kv["accesstoken"] ?? ""

        var uinRaw = kv["uin"] ?? ""
        if uinRaw.hasPrefix("o") { uinRaw.removeFirst() }
        s.uin = Int64(uinRaw) ?? 0

        if let acct = kv["accounttype"], let n = Int(acct) {
            s.authType = SsoAuthType(rawValue: n == 5 ? 4 : (n == 2 ? 1 : 0)) ?? .qq
        }
        if let acc = kv["acctype"] {
            s.authType = (acc == "qc") ? .qq : .wechat
        }
        return s
    }

    /// 从 Frida 脚本产出的 `mval_session.json` 解析（**推荐**：里面带 ct，可以自刷新）。
    public static func from(sessionJSON data: Data) throws -> ZhangwaSession {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ZhangwaError.decoding("session json 不是对象")
        }
        var s = ZhangwaSession()
        s.userID = (obj["user_id"] as? String) ?? ""
        s.ct = (obj["ct"] as? String) ?? ""
        s.tid = (obj["tid"] as? String) ?? ""
        s.openID = (obj["openid"] as? String) ?? ""
        s.accessToken = (obj["access_token"] as? String) ?? ""
        if let u = obj["uin"] { s.uin = Int64("\(u)") ?? 0 }
        if let t = obj["auth_type"], let n = Int("\(t)") {
            s.authType = SsoAuthType(rawValue: n) ?? .qq
        }
        // 有 ct 时不用 rawCookieHeader，走实时拼装（tid 刷新后能立刻生效）
        if s.ct.isEmpty && s.tid.isEmpty {
            s.rawCookieHeader = (obj["cookie"] as? String) ?? ""
        }
        return s
    }
}

// MARK: - 错误

/// Swift 6 严格并发下 `Error` 要能跨隔离域传递，所以 payload 只放 Sendable 类型；
/// 原始 `data` 转成一段预览文本。
public enum ZhangwaError: Error, LocalizedError, Sendable {
    case api(code: Int, msg: String, dataPreview: String?)
    case transport(String)
    case decoding(String)
    case notConfigured(String)
    case capture(String)

    public var errorDescription: String? {
        switch self {
        case .api(let code, let msg, _):
            if code == 999999 {
                return "[999999] 票据异常（wt/tid 已过期）。重新抓包，或在设置里执行「刷新票据」。"
            }
            return "[\(code)] \(msg)"
        case .transport(let m): return "网络错误：\(m)"
        case .decoding(let m): return "解析失败：\(m)"
        case .notConfigured(let m): return m
        case .capture(let m): return "抓包解析失败：\(m)"
        }
    }

    public var apiCode: Int? {
        if case .api(let code, _, _) = self { return code }
        return nil
    }
}
