import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 掌瓦协议层（Swift 版）。
///
/// 与 Android 端 1:1 对齐的四件事：
/// 1. 域名重写 `mlol.qt.qq.com → app.mval.qq.com`
///    （`com/tencent/qt/qtl/activity/ValUrlTransformer`）
/// 2. 响应信封 `{"result":0,"msg":"","data":{}}`，`999999` = 票据异常
///    （`com/tencent/container/protocol/a/a.java`）
/// 3. val 域请求注入 `game_zone=val` / `source_game_zone`
///    （`com/tencent/container/app/AppEnvironment` + `ValZoneBodyWrapper`）
/// 4. Cookie 固定拼装
///    （`com/tencent/container/c/a/a.java` CookieHelper）
@MainActor
public final class ZhangwaClient {

    // MARK: 常量（全部来自 AndroidManifest.xml）

    public static let hostProd = "app.mval.qq.com"
    public static let hostTest = "apptest.mval.qq.com"
    public static let hostOld = "mlol.qt.qq.com"
    public static let hostOldPre = "mlolpre.qt.qq.com"

    /// `com/tencent/qt/module_information/data/c.java:47` 里的另一台正式域名：
    /// `https://app.val.qq.com/go/zone/v3/channel?zone=$ZONE$&disableAlgo=$DISABLEALGO$`
    /// 页面容器（zone channel）走这台，探测时要一起试。
    public static let hostVal = "app.val.qq.com"

    public static let zoneVAL = "val"       // 无畏契约端游
    public static let zoneCODEV = "codev"   // 无畏契约手游 / 共创

    public static let resultOK = 0
    public static let resultTicketInvalid = 999999

    public static let defaultUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    // MARK: 状态

    public private(set) var session: ZhangwaSession
    public var host: String
    public var userAgent: String
    public var gameZone: String

    /// 每日商店的**真实接口**（2026-10 抓包实测确认）。
    ///
    /// `POST /go/mlol_store/agame/user_store`，body 就是 `{}`。
    /// 响应里 `data[]` 的每个面板有 `key`（`dailystore` / `kingdomstore`）、
    /// `title`（"每日商店"）、`time`（剩余秒）、`end_ts`、`list[]`（商品）。
    ///
    /// 这个路径是从 RN bundle `WelFareStrategyMain.jsbundle` 的字符串表里挖出来的，
    /// 该文件里同时还有 `/go/mlol_store/agame/flip_goods_card`（翻牌）、
    /// `/go/mlol_store/agame/kingdom_store`、`/go/mlol_store/agame/get_vct_skin_list`。
    public static let dailyStorePath = "/go/mlol_store/agame/user_store"

    /// 商店接口路径。默认就是实测出来的那个。
    public var shopPath: String? = ZhangwaClient.dailyStorePath
    public var shopBody: [String: Any]? = [:]
    public var shopMethod: String = "POST"

    /// 探测用的候选（第一个是实测确认的）
    public var shopCandidates: [String] = [
        ZhangwaClient.dailyStorePath,
        "/go/mlol_store/agame/kingdom_store",
        "/go/mlol_store/agame/flip_goods_card",
        "/go/zone/v3/channel?zone=shop&disableAlgo=0",
        "/go/agame/store/storefront",
    ]

    /// 探测时依次尝试的域名
    public var probeHosts: [String] = [ZhangwaClient.hostProd, ZhangwaClient.hostVal]

    public var onSessionChanged: (@MainActor (ZhangwaSession) -> Void)?

    /// 测试 / 自定义传输用的缝。默认 nil，走 URLSession。
    /// 测试里塞一个闭包就能完全离线验证信封解析、game_zone 注入、999999 重试。
    public var transportOverride: ((URLRequest) async throws -> (Data, HTTPURLResponse))?

    private let urlSession: URLSession

    // MARK: init

    public init(session: ZhangwaSession,
                host: String = ZhangwaClient.hostProd,
                userAgent: String = ZhangwaClient.defaultUserAgent,
                gameZone: String = ZhangwaClient.zoneVAL) {
        self.session = session
        self.host = host
        self.userAgent = userAgent
        self.gameZone = gameZone

        let cfg = URLSessionConfiguration.ephemeral
        // Cookie 完全自己管，不让 URLSession 插手（否则会被 HTTPCookieStorage 覆盖）
        cfg.httpCookieStorage = nil
        cfg.httpShouldSetCookies = false
        cfg.httpCookieAcceptPolicy = .never
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 30
        self.urlSession = URLSession(configuration: cfg)
    }

    public func updateSession(_ new: ZhangwaSession) {
        session = new
        onSessionChanged?(new)
    }

    // MARK: URL 处理

    public func rewriteHost(_ url: String) -> String {
        var s = url
        if s.contains(Self.hostOld) { s = s.replacingOccurrences(of: Self.hostOld, with: Self.hostProd) }
        if s.contains(Self.hostOldPre) { s = s.replacingOccurrences(of: Self.hostOldPre, with: Self.hostTest) }
        if s.hasPrefix("/") { s = "https://\(host)\(s)" }
        return s
    }

    private func makeURL(_ path: String, query: [String: String]? = nil) throws -> URL {
        let full = rewriteHost(path)
        guard var comps = URLComponents(string: full) else {
            throw ZhangwaError.transport("非法 URL: \(full)")
        }
        if let query, !query.isEmpty {
            var items = comps.queryItems ?? []
            for (k, v) in query {
                items.removeAll { $0.name == k }
                items.append(URLQueryItem(name: k, value: v))
            }
            comps.queryItems = items
        }
        guard let url = comps.url else {
            throw ZhangwaError.transport("非法 URL: \(full)")
        }
        return url
    }

    /// 等价 `AppEnvironment.a(String, Map)` / `b(String, Map)`
    private func injectZone(into body: [String: Any]) -> [String: Any] {
        var b = body
        if b["source_game_zone"] == nil { b["source_game_zone"] = "" }
        if b["game_zone"] == nil { b["game_zone"] = gameZone }
        return b
    }

    // MARK: 核心请求

    @discardableResult
    public func request(_ path: String,
                        body: [String: Any]? = nil,
                        method: String = "auto",
                        gameZone explicitZone: String? = nil,
                        retryOnTicketError: Bool = true) async throws -> Any {

        let zone = explicitZone ?? gameZone
        let usePost: Bool
        switch method.uppercased() {
        case "POST": usePost = true
        case "GET": usePost = false
        default: usePost = (body != nil)
        }

        var query: [String: String]? = nil
        var payload: [String: Any]? = nil
        if usePost {
            payload = injectZone(into: body ?? [:])
        } else {
            var q: [String: String] = ["source_game_zone": "", "game_zone": zone]
            if let body { for (k, v) in body { q[k] = "\(v)" } }
            query = q
        }

        var req = URLRequest(url: try makeURL(path, query: query))
        req.httpMethod = usePost ? "POST" : "GET"
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(session.cookieHeader, forHTTPHeaderField: "Cookie")
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        req.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.setValue("https://\(host)/", forHTTPHeaderField: "Referer")

        if usePost {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: payload ?? [:], options: [])
        }

        let data: Data
        let httpResponse: HTTPURLResponse?
        do {
            if let override = transportOverride {
                let pair = try await override(req)
                data = pair.0
                httpResponse = pair.1
            } else {
                let pair = try await urlSession.data(for: req)
                data = pair.0
                httpResponse = pair.1 as? HTTPURLResponse
            }
        } catch {
            throw ZhangwaError.transport(error.localizedDescription)
        }

        if let http = httpResponse, !(200...299).contains(http.statusCode) {
            let snippet = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw ZhangwaError.transport("HTTP \(http.statusCode) \(snippet)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let snippet = String(data: data.prefix(300), encoding: .utf8) ?? "<binary>"
            throw ZhangwaError.decoding("响应不是 JSON：\(snippet)")
        }

        let code = Self.intValue(json["result"]) ?? -1
        let msg = (json["msg"] as? String) ?? ""

        if code == Self.resultTicketInvalid && retryOnTicketError {
            if await refreshWebTicket() {
                return try await request(path, body: body, method: method,
                                         gameZone: explicitZone, retryOnTicketError: false)
            }
        }
        if code != Self.resultOK {
            throw ZhangwaError.api(code: code, msg: msg, dataPreview: Self.preview(json["data"]))
        }
        return json["data"] ?? NSNull()
    }

    nonisolated public static func intValue(_ any: Any?) -> Int? {
        switch any {
        case let i as Int: return i
        case let n as NSNumber: return n.intValue
        case let d as Double: return Int(d)
        case let s as String: return Int(s)
        default: return nil
        }
    }

    nonisolated public static func doubleValue(_ any: Any?) -> Double? {
        switch any {
        case let d as Double: return d
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    nonisolated public static func stringValue(_ any: Any?) -> String? {
        switch any {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    nonisolated public static func dictValue(_ any: Any?) -> [String: Any]? {
        any as? [String: Any]
    }

    nonisolated public static func arrayValue(_ any: Any?) -> [Any]? {
        any as? [Any]
    }

    // MARK: /go/auth/* —— 票据链

    /// `POST /go/auth/refresh_client_ticket` → 拿到新的 ct / wt
    @discardableResult
    public func refreshClientTicket() async throws -> Bool {
        guard !session.ct.isEmpty, !session.userID.isEmpty else {
            throw ZhangwaError.notConfigured("缺少 ct / userId，无法刷新。请重新导入抓包会话。")
        }
        let data = try await request("/go/auth/refresh_client_ticket", body: [
            "ct": session.ct,
            "user_id": session.userID,
            "local_is_new_user": 0,
            "config_params": ["lang_type": 0],
        ], retryOnTicketError: false)

        guard let root = data as? [String: Any],
              let info = root["ct_info"] as? [String: Any] else { return false }

        var s = session
        if let v = info["ct"] as? String, !v.isEmpty { s.ct = v }
        if let v = info["wt"] as? String, !v.isEmpty { s.tid = v }
        if let v = info["user_id"] as? String, !v.isEmpty { s.userID = v }
        if let u = Self.intValue(info["uin"]) { s.uin = Int64(u) }
        // 记下这次续期的时间 —— ct 有效期 7 天，靠这个滚动续期
        s.ctUpdatedAt = Date().timeIntervalSince1970

        // ⚠️ 千万别把 ct_info.openid 写进 Cookie 的 openid！
        //
        // ct_info.openid 是**掌瓦自己的 openid**（形如 `74193457a-…_10200`，
        // 尾巴是 login_mappid），而 Cookie 要的是 **QQ 的 openid**
        // （形如 `A44A6AA89A42ECA6909C2492C2193D14`）。两个完全不同。
        // 写错了这一行，Cookie 立刻失效 —— 而且报的是 999999，
        // 看起来像「票据过期」，极难查。
        //
        // 正确的来源是 ct_info 同一层的 `bind_info`：
        //   [{"uin":"A44A6AA8…","openid":"A44A6AA8…","uuid":"JA-3095d6…"}]
        // 取 uuid == userID 的那条。
        let bindList = (root["bind_info"] as? [Any])
            ?? (((root["data"] as? [String: Any])?["bind_info"]) as? [Any])
        if let binds = bindList?.compactMap({ $0 as? [String: Any] }) {
            if let mine = binds.first(where: { ($0["uuid"] as? String) == s.userID })
                ?? binds.first,
               let oid = Self.stringValue(mine["openid"]), !oid.isEmpty {
                s.openID = oid
            }
        }

        updateSession(s)
        return true
    }

    /// 要不要续 ct。
    ///
    /// ct 有效期 7 天（实测 `refresh_ct_span = 604800`），
    /// 但在过期前用旧 ct 换一张新的就能一直滚下去 —— **抓一次包够用一辈子**。
    ///
    /// 续期条件设成「超过 1 天」，所以只要每天打开一次 App 就永远活着，
    /// 而且留了 6 天余量（忘了开几天也不会断）。
    public var needsClientTicketRenewal: Bool {
        guard !session.ct.isEmpty, !session.userID.isEmpty else { return false }
        // 不知道是什么时候拿的，就先续一次
        guard session.ctUpdatedAt > 0 else { return true }
        let age = Date().timeIntervalSince1970 - session.ctUpdatedAt
        return age > ZhangwaSession.ctRenewInterval
    }

    /// ct 还剩多久过期（秒）。负数 = 已经过期。nil = 没 ct。
    public var clientTicketSecondsLeft: TimeInterval? {
        guard !session.ct.isEmpty else { return nil }
        guard session.ctUpdatedAt > 0 else { return nil }
        return session.ctUpdatedAt + ZhangwaSession.ctLifetime
            - Date().timeIntervalSince1970
    }

    /// 该续就续，不该续就什么都不做。失败不抛错（下次自然还会试）。
    @discardableResult
    public func ensureFreshClientTicket() async -> Bool {
        guard needsClientTicketRenewal else { return true }
        return (try? await refreshClientTicket()) ?? false
    }

    /// `POST /go/auth/get_web_ticket` → 新的 wt，写回 `tid`
    /// （`AppContext.a(String)` 把 wt 存进 tid 字段，Cookie 里发的就是它）
    @discardableResult
    public func refreshWebTicket() async -> Bool {
        do {
            let data = try await request("/go/auth/get_web_ticket", body: [
                "ct": session.ct,
                "user_id": session.userID,
                "config_params": ["lang_type": 0],
            ], retryOnTicketError: false)
            guard let root = data as? [String: Any],
                  let wt = root["wt"] as? String, !wt.isEmpty else { return false }
            var s = session
            s.tid = wt
            updateSession(s)
            return true
        } catch let ZhangwaError.api(code, _, _) where code == Self.resultTicketInvalid {
            // wt 换不出来说明 ct 也过期了，退回刷新 ct 再试一次
            if (try? await refreshClientTicket()) == true {
                return await refreshWebTicket()
            }
            return false
        } catch {
            return false
        }
    }

    @discardableResult
    public func getClientTmpTicket() async throws -> [String: Any] {
        let data = try await request("/go/auth/get_client_tmp_ticket", body: [
            "ct": session.ct,
            "user_id": session.userID,
            "config_params": ["lang_type": 0],
        ])
        return (data as? [String: Any]) ?? [:]
    }

    /// `POST /go/auth/refresh_third_token`
    /// body: `{"type": <0|1|4>, "uuid": <user_id>, "openid": <openid>}`
    /// resp: `{"access_token": "...", "expired": <秒>, "time_interval": <秒>}`
    @discardableResult
    public func refreshThirdToken() async throws -> String? {
        let data = try await request("/go/auth/refresh_third_token", body: [
            "type": session.authType.rawValue,
            "uuid": session.userID,
            "openid": session.openID,
        ])
        guard let root = data as? [String: Any],
              let token = root["access_token"] as? String, !token.isEmpty else { return nil }
        var s = session
        s.accessToken = token
        if let exp = Self.doubleValue(root["expired"]) {
            s.expiresAt = Date().timeIntervalSince1970 + exp
        }
        updateSession(s)
        return token
    }

    /// access_token 快过期 / 已过期时提前换新
    public func ensureFreshToken() async {
        let now = Date().timeIntervalSince1970
        guard session.expiresAt > 0, now > session.expiresAt - 300 else { return }
        _ = try? await refreshThirdToken()
    }

    // MARK: 账号 / 角色

    public func getGameList() async throws -> [Any] {
        let data = try await request("/go/account/getgamelist", body: [:])
        if let root = data as? [String: Any] {
            if let items = root["items"] as? [Any] { return items }
            if let list = root["list"] as? [Any] { return list }
        }
        return (data as? [Any]) ?? []
    }

    public func getRolesByGame(_ gameID: String = ZhangwaClient.zoneVAL) async throws -> Any {
        try await request("/go/account/get_roles_by_game_v2", body: ["game_id": gameID])
    }

    public func getAllRoles() async throws -> Any {
        try await request("/go/account/getallgameroles", body: [:])
    }

    // MARK: 无畏契约游戏数据

    public func gunSkinDetail(armID: String, zone: String = ZhangwaClient.zoneVAL) async throws -> Any {
        let path = zone == Self.zoneCODEV
            ? "/go/codev/asset/gun_skin_detail"
            : "/go/agame/asset/gun_skin_detail"
        return try await request(path, body: ["armId": armID, "from": "gl"], gameZone: zone)
    }

    public func showcaseGet() async throws -> Any {
        try await request("/go/agame/asset/showcase/get", body: [:])
    }

    public func valCardV2() async throws -> Any {
        try await request("/go/mine/card/val_card_v2", body: [:])
    }

    // MARK: 每日商店

    public func fetchStore() async throws -> Any {
        guard let path = shopPath, !path.isEmpty else {
            throw ZhangwaError.notConfigured(
                "还没配置商店接口路径。抓一次包把路径填进设置，或先跑「探测商店接口」。")
        }
        return try await request(path, body: shopBody ?? [:], method: shopMethod)
    }

    /// 每个候选路径 × 每台域名，POST/GET 都试一遍。
    ///
    /// ⚠️ 判断「命中」不能只看 `result == 0`。
    /// `/go/zone/v3/channel?zone=shop` 就是反例：它返回 `result=0` 但 `data` 是 `null`
    /// —— 那只是个空壳容器，把它当成商店接口会覆盖掉真正的那个。
    /// 所以还要求 data 里确实有东西。
    public func probeShop() async -> [(path: String, ok: Bool, detail: String)] {
        var out: [(String, Bool, String)] = []
        let savedHost = host
        defer { host = savedHost }

        for candidate in shopCandidates {
            var hit = false
            var detail = ""
            for h in probeHosts {
                host = h
                for m in ["POST", "GET"] {
                    do {
                        let data = try await request(candidate, body: [:], method: m)
                        if Self.hasPayload(data) {
                            hit = true
                            detail = "命中 [\(m)] @\(h)  \(Self.preview(data))"
                            break
                        }
                        detail = "result=0 但 data 是空的（[\(m)] @\(h)）—— 空壳，不算命中"
                    } catch {
                        detail = "[\(h)] \(error.localizedDescription)"
                    }
                }
                if hit { break }
            }
            out.append((candidate, hit, detail))
        }
        return out
    }

    /// data 里到底有没有内容。null / {} / [] / "" 都算空。
    public nonisolated static func hasPayload(_ any: Any?) -> Bool {
        guard let any else { return false }
        if any is NSNull { return false }
        if let d = any as? [String: Any] { return !d.isEmpty }
        if let a = any as? [Any] { return !a.isEmpty }
        if let s = any as? String { return !s.isEmpty && s != "null" }
        return true
    }

    nonisolated static func preview(_ any: Any?) -> String {
        guard let any else { return "null" }
        if let s = any as? String { return String(s.prefix(240)) }
        // JSONSerialization 只接受 array / dictionary 作为顶层对象，
        // NSNull、标量走这里会直接 crash（corelibs 上是 fatalError）。
        if JSONSerialization.isValidJSONObject(any),
           let d = try? JSONSerialization.data(withJSONObject: any, options: []),
           let s = String(data: d, encoding: .utf8) {
            return String(s.prefix(240))
        }
        return String("\(any)".prefix(240))
    }
}
