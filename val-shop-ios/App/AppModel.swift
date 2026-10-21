import Foundation
import Observation
import ZhangwaKit

/// 全局状态。
///
/// 用的是 Observation 框架（`@Observable`）而不是老的 `ObservableObject`：
/// SwiftUI 只会在真正读到的属性变化时重绘，不用再手写 `@Published`。
@MainActor
@Observable
final class AppModel {

    enum LoadState: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(String)

        var isLoading: Bool { self == .loading }
    }

    private(set) var session: ZhangwaSession
    private(set) var snapshot: StoreSnapshot = .empty
    private(set) var state: LoadState = .idle
    private(set) var endpoints: [CaptureImporter.Endpoint] = []
    private(set) var log: [String] = []

    /// 上次成功读到商店的时间。维护台要显示它，不然「这次到底读没读成功」只能靠翻日志。
    private(set) var lastLoadedAt: Date?

    /// 四张卡是否已翻开
    var flipped: [Bool] = [false, false, false, false]

    /// 会话页/设置页的输入草稿
    var shopPathDraft: String
    var shopBodyDraft: String

    let client: ZhangwaClient

    private static let kSession = "zw.session"
    private static let kShopPath = "zw.shopPath"
    private static let kShopBody = "zw.shopBody"

    init() {
        var s = ZhangwaSession()
        if let data = UserDefaults.standard.data(forKey: Self.kSession),
           let decoded = try? JSONDecoder().decode(ZhangwaSession.self, from: data) {
            s = decoded
        }
        session = s

        let c = ZhangwaClient(session: s)

        // 优先级：App 里改过的（UserDefaults） > 构建期注入的（BundledConfig.plist）
        let bundled = Self.loadBundledConfig()
        let path = Self.firstNonEmpty(UserDefaults.standard.string(forKey: Self.kShopPath),
                                      bundled.path) ?? ""
        let body = Self.firstNonEmpty(UserDefaults.standard.string(forKey: Self.kShopBody),
                                      bundled.body) ?? "{}"
        c.shopPath = path.isEmpty ? nil : path
        c.shopBody = Self.parseJSONObject(body)
        client = c

        shopPathDraft = path
        shopBodyDraft = body

        // onSessionChanged 声明成 @MainActor 闭包，这里直接同步调用即可
        c.onSessionChanged = { [weak self] new in
            self?.applySession(new)
        }

        // 冷启动就把上一期读到的东西铺上屏 —— 别让用户对着空页面等网络。
        // 顺序很重要：先快照，再按快照恢复翻牌状态（翻牌状态是跟"这一期"绑定的）。
        if let snap = Self.loadCachedSnapshot() {
            snapshot = snap
            restoreFlippedFlags()
        }
        if let role = Self.loadCachedRole() {
            userRole = role
        }
        if let roles = Self.loadCachedRoles(), !roles.isEmpty {
            availableRoles = roles
        }
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// 读构建期注入的默认配置。CI 会覆写 App/BundledConfig.plist。
    /// 构建指纹：CI 会把提交短 SHA 写进 BundledConfig.plist。
    /// 本地 xcodegen 直接跑没有这一项，显示 `—`。
    /// 为什么需要它：自签安装换包之后，"我装的是哪一次"完全没有别的办法分辨。
    static var buildStamp: String {
        guard let url = Bundle.main.url(forResource: "BundledConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = plist as? [String: Any],
              let sha = dict["buildSHA"] as? String,
              !sha.isEmpty else { return "—" }
        return sha
    }

    private static func loadBundledConfig() -> (path: String, body: String) {
        guard let url = Bundle.main.url(forResource: "BundledConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url) else {
            return ("", "{}")
        }
        let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = plist as? [String: Any] else { return ("", "{}") }
        return (dict["shopPath"] as? String ?? "", dict["shopBody"] as? String ?? "{}")
    }

    // MARK: - 会话

    private func applySession(_ new: ZhangwaSession) {
        session = new
        if let data = try? JSONEncoder().encode(new) {
            UserDefaults.standard.set(data, forKey: Self.kSession)
        }
    }

    /// 扫码登录成功后接手会话。
    ///
    /// 扫码拿到的是**全新的 ct + wt**（和抓包拿到的是同一个东西），
    /// 所以不用做任何特殊处理 —— 交给现有的 ct 滚动续期机制养着就行。
    /// 扫码登录界面开不开。放在 model 上而不是某个页面的 @State —— 
    /// 设置页自己可能就是 sheet，再往里弹一层会变成嵌套 sheet（iOS 上不稳）。
    /// 挂到根视图就永远只有一层。
    /// 登录方式。用一个 enum 驱动**唯一一个** sheet。
    ///
    /// 为什么不用两个 .sheet(isPresented:) 挂在同一个视图上 ——
    /// 同一个视图挂多个 sheet 在 iOS 上不稳（可能只弹第一个/都不弹）。
    /// 这是踩过的坑，别改回去。
    enum LoginSheet: String, Identifiable, Sendable {
        case wechat, qq
        var id: String { rawValue }
    }

    var loginSheet: LoginSheet?

    /// 最近一次续期失败的原因。nil = 一切正常。
    ///
    /// 为什么要暴露到界面上：续期失败以前只打日志，用户看不到，
    /// 等真掉了线才发现「原来早就一直在失败」。
    var renewError: String?

    func adopt(_ s: ZhangwaSession) {
        client.updateSession(s)
        applySession(s)
        // 刚拿到登录态，顺手把游戏 ID 拉出来显示
        Task { await loadUserRole() }
        // 登录完直接读今天的商店 —— 界面上已经没有「读取」按钮了
        Task { await loadStore() }
        push("扫码登录成功：userID=\(s.userID.isEmpty ? "?" : s.userID)"
             + "，ct \(s.ct.isEmpty ? "无" : "有")，有效期 7 天（会自动续）")
    }

    /// 启动 / 每次回到前台时调一次。
    ///
    /// **这是「脱离电脑」的关键**：ct 的 7 天寿命靠自己续下去，
    /// 只要 App 每次被打开时都续一下，就永远不需要再回电脑上抓包。
    /// 所以这个不能只在「读取商店」时调 —— 用户可能只是想看一眼就关掉。
    func renewSessionIfNeeded() async {
        guard hasSession else { return }
        guard client.needsClientTicketRenewal else { return }
        let ok = await client.ensureFreshClientTicket()
        applySession(client.session)
        if ok {
            renewError = nil
            push("登录态已自动续期")
        } else {
            // 失败要说清楚「不影响现在用」—— ct 还有余量，
            // 下次打开或者后台刷新还会再试。别一上来就吓唬人。
            renewError = client.lastError
            push("续期暂时失败（不影响现在看商店，下次打开会再试）")
        }
    }

    /// 把登录态导出成一段文本，方便备份。
    ///
    /// 为什么需要：这是**唯一一份**能长期用的凭证。
    /// 万一 App 被删、换手机、或者 ct 真的断了，有备份就能直接粘回来，
    /// 不用再回电脑上抓一次包。
    func exportSession() -> String {
        let s = client.session
        let dict: [String: Any] = [
            "user_id": s.userID,
            "ct": s.ct,
            "auth_type": s.authType.rawValue,
            "openid": s.openID,
            "uin": String(s.uin),
            "access_token": s.accessToken,
            "tid": s.tid,
            "ct_updated_at": s.ctUpdatedAt,
        ]
        guard let data = try? JSONSerialization.data(
                withJSONObject: dict, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    var hasSession: Bool { session.isValid }

    /// ct 还有多久过期。
    ///
    /// ⚠️ 这里用的是 `refreh_ct_span` 的 7 天，**不是** `expires` 的 30 天。
    /// 两个字段在协议里都存在（RefreshClientTicketProtocol.RefreshCTInfo）：
    ///   · refresh_ct_span = 604800 (7 天)  -> 建议的续期间隔
    ///   · expires         = 2592000 (30 天) -> 实际有效期（推测）
    ///
    /// 按 7 天算是因为**两边都安全**：
    ///   · 如果真实是 7 天  -> 算得准
    ///   · 如果真实是 30 天 -> 只是显示偏保守 + 续得偏勤，没有坏处
    /// 反过来按 30 天算，万一真实是 7 天就会误报「还有 23 天」然后突然掉线。
    /// 这种地方宁可用保守值。
    var ctExpiryText: String {
        guard !session.ct.isEmpty else { return "无 ct —— 无法自刷新" }
        guard session.ctUpdatedAt > 0 else { return "未知（导入时没记时间）" }
        let left = session.ctUpdatedAt + ZhangwaSession.ctLifetime
            - Date().timeIntervalSince1970
        if left <= 0 { return "该续期了（会自动续）" }
        let days = Int(left) / 86_400
        let hours = (Int(left) % 86_400) / 3_600
        return days > 0 ? "还有 \(days) 天 \(hours) 小时" : "还有 \(hours) 小时"
    }

    /// 上次续期是多久以前
    var lastRenewText: String {
        guard session.ctUpdatedAt > 0 else { return "未知" }
        let ago = Date().timeIntervalSince1970 - session.ctUpdatedAt
        if ago < 60 { return "刚刚" }
        let m = Int(ago) / 60
        if m < 60 { return "\(m) 分钟前" }
        let h = m / 60
        if h < 24 { return "\(h) 小时前" }
        return "\(h / 24) 天前"
    }

    /// ct 还剩几天 —— 首页那条 7 格「票据弹药条」用。
    ///
    /// nil 表示没有 ct（或导入时没记时间），界面要显式说出这个区别：
    /// 「没有 ct」和「有 ct 但快到期」是两件完全不同的事。
    var ctDaysLeft: Int? {
        guard !session.ct.isEmpty else { return nil }
        guard session.ctUpdatedAt > 0 else { return nil }
        let left = session.ctUpdatedAt + ZhangwaSession.ctLifetime
            - Date().timeIntervalSince1970
        guard left > 0 else { return 0 }
        return max(0, min(7, Int(ceil(left / 86_400))))
    }

    /// 当前登录用户的游戏角色（游戏 ID、段位、等级、卡面）
    ///
    /// 单独存一份而不是每次现拉：首页左上角要显示，属于高频读取；
    /// 而且拉失败时保留上一次的值，比显示空白好。
    var userRole: UserRole?

    /// 可切换的全部角色（端游的）
    var availableRoles: [UserRole] = []

    /// 用户手选的角色。存 identityKey 而不是下标 ——
    /// 角色顺序可能变，下标会串。
    private static let selectedRoleKey = "zw.selectedRoleKey"

    /// 拉一次角色信息。失败静默保留旧值 —— 这只是首页装饰，不该影响看商店。
    func loadUserRole() async {
        guard hasSession else {
            userRole = nil
            availableRoles = []
            return
        }
        guard let roles = await client.fetchGameRoles() else { return }

        availableRoles = roles.selectableRoles

        // 优先用用户手选的那个；它不在列表里了（删号/换号）就退回默认
        let saved = UserDefaults.standard.string(forKey: Self.selectedRoleKey)
        if let saved, let hit = availableRoles.first(where: { $0.identityKey == saved }) {
            userRole = hit
        } else {
            userRole = roles.preferred
        }
        cacheRoles()      // 下次冷启动直接有名字和段位可显示
    }

    /// 用户切角色
    func selectRole(_ role: UserRole) {
        UserDefaults.standard.set(role.identityKey, forKey: Self.selectedRoleKey)
        userRole = role
        cacheRoles()
        push("已切换到 \(role.displayName)")
    }

    /// 要不要显示角色切换入口。只有一个角色时不必显示。
    var canSwitchRole: Bool { availableRoles.count > 1 }

    /// 首页左上角的主标题。
    ///
    /// 优先游戏 ID（`天天开心#26170`）—— 那才是玩家认得的东西。
    /// 拿不到才退回一个中性文案，绝不显示内部 userID
    /// （那是 `JA-3095d6174193457a-b8d058817457ae26` 这种，用户看了只会困惑）。
    var displayName: String {
        if let r = userRole { return r.displayName }
        return session.isValid ? "已登录" : "未登录"
    }

    /// 主标题下面的副标题：段位 · 等级
    var displaySubtitle: String {
        guard let r = userRole else {
            return state.isLoading ? "正在读取…" : "数据来自官方同源接口"
        }
        var bits: [String] = []
        let rank = r.rankText
        if !rank.isEmpty { bits.append(rank) }
        if r.level > 0 { bits.append("Lv\(r.level)") }
        if bits.isEmpty {
            bits.append(r.areaName.isEmpty ? r.platformText : r.areaName)
        }
        return bits.joined(separator: " · ")
    }

    /// 退出登录时把角色缓存也清掉 —— 否则换了账号还会显示上一个人的游戏 ID
    func clearRoleCache() {
        userRole = nil
        availableRoles = []
        UserDefaults.standard.removeObject(forKey: Self.selectedRoleKey)
    }

    /// 「我的」页顶部那句：说明这次是用什么登进来的。
    /// 不再重复游戏 ID —— 那个商店页已经显示了。
    var loginMethodLabel: String {
        guard hasSession else { return "未登录" }
        return "已使用 \(session.authType.displayName) 登录"
    }

    var accountLabel: String {
        guard session.isValid else { return "未登录" }
        let id = session.userID.isEmpty ? "?" : session.userID
        return "\(session.authType.displayName) · \(id)"
    }

    var shopPathLabel: String {
        (client.shopPath?.isEmpty == false) ? "接口已配置" : "接口未配置"
    }

    func saveCookie(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let s = ZhangwaSession.from(cookieHeader: trimmed)
        client.updateSession(s)
        applySession(s)
        push("已保存 Cookie：userId=\(s.userID.isEmpty ? "?" : s.userID)，账号=\(s.authType.displayName)")
    }

    /// 智能粘贴：一段文本既可能是 Cookie 头，也可能是 mval_session.json 的内容。
    /// 自动认，认不出来的话给出明确提示（而不是默默失败）。
    ///
    /// 为什么要这个：iOS 上把文件弄进 App 有前置条件（App 至少启动过一次、
    /// 「文件」App 缓存……），任一环不对就传不进去。粘贴没有任何依赖。
    @discardableResult
    func importPasted(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "粘贴框是空的" }

        // ① JSON（mval_session.json，含 ct，可自刷新）
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if let data = trimmed.data(using: .utf8),
               let s = try? ZhangwaSession.from(sessionJSON: data) {
                client.updateSession(s)
                applySession(s)
                let msg = "导入成功（JSON）：userId=\(s.userID)，ct=\(s.ct.isEmpty ? "无" : "有")"
                push(msg)
                return msg
            }
            let msg = "看着像 JSON 但解析不出 user_id / tid，检查一下是不是贴串了"
            push(msg)
            return msg
        }

        // ② Cookie 头
        if trimmed.contains("=") && (trimmed.contains("tid=") || trimmed.contains("clientType=")
                                     || trimmed.contains("openid=")) {
            let s = ZhangwaSession.from(cookieHeader: trimmed)
            guard s.isValid else {
                let msg = "认得出是 Cookie，但缺关键字段（至少要 userId + tid）"
                push(msg)
                return msg
            }
            client.updateSession(s)
            applySession(s)
            let msg = "导入成功（Cookie）：userId=\(s.userID)，ct=\(s.ct.isEmpty ? "无（不能自刷新）" : "有")"
            push(msg)
            return msg
        }

        let msg = "认不出这是什么。要么贴完整 Cookie（含 tid=），要么贴 session 的整段 JSON（以 { 开头）"
        push(msg)
        return msg
    }

    func importCapture(path: String) async {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        push("读取 \(trimmed) …")
        do {
            let s = try CaptureImporter.session(fromFileAt: trimmed)
            client.updateSession(s)
            applySession(s)
            push("导入成功：userId=\(s.userID)，ct=\(s.ct.isEmpty ? "无" : "有")，tid=\(s.tid.isEmpty ? "无" : "有")")

            if FileManager.default.fileExists(atPath: trimmed) {
                let eps = (try? CaptureImporter.endpoints(fromFileAt: trimmed)) ?? []
                endpoints = eps
                push("发现 \(eps.count) 个 /go/ 接口，疑似商店 \(eps.filter(\.looksLikeStore).count) 个")
            }
        } catch {
            push("导入失败：\(error.localizedDescription)")
        }
    }

    func importCapture(url: URL) async {
        // 沙盒外选中的文件必须先拷进 app 容器再读
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("zw-capture-\(UUID().uuidString).log")
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            await importCapture(path: dest.path)
        } catch {
            push("复制抓包文件失败：\(error.localizedDescription)")
        }
    }

    /// 自签装的 App 没有 Xcode 控制台，所以走「文件」App：
    /// Info.plist 里开了 UIFileSharingEnabled + LSSupportsOpeningDocumentsInPlace，
    /// AirDrop 过来的文件直接丢进「我的 iPhone → ValPeek」，然后点一下就行。
    func importFromAppFolder() async {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: docs,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []

        let candidates = files
            .filter { !$0.hasDirectoryPath }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !candidates.isEmpty else {
            push("App 文件夹是空的。把 mval_session.json / mval_capture.log 放进「文件」App 的「我的 iPhone → ValPeek」再试。")
            return
        }

        for file in candidates {
            push("发现 \(file.lastPathComponent)")
            await importCapture(path: file.path)
        }
    }

    /// 自签环境排错全靠这个：把状态、归一化结果、原始 JSON、日志全导出来
    var diagnostics: String {
        var out: [String] = []
        out.append("=== ValPeek 诊断 ===")
        out.append("时间: \(Self.stamp.string(from: Date()))")
        out.append("App 版本: \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
        out.append("")
        out.append("[会话]")
        out.append("  有会话: \(hasSession)")
        out.append("  userId: \(session.userID)")
        out.append("  uin: \(session.uin)")
        out.append("  authType: \(session.authType.rawValue) (\(session.authType.displayName))")
        out.append("  ct: \(session.ct.isEmpty ? "无（无法自刷新）" : "有")")
        out.append("  tid: \(session.tid.isEmpty ? "无" : "有")")
        out.append("  access_token: \(session.accessToken.isEmpty ? "无" : "有")")
        out.append("")
        out.append("[商店接口]")
        out.append("  path: \(client.shopPath ?? "(未配置)")")
        out.append("")
        out.append("[归一化]")
        out.append("  rawKeys: \(snapshot.rawKeys.joined(separator: ", "))")
        out.append("  items: \(snapshot.items.count)")
        out.append("  expiresAt: \(snapshot.expiresAt.map { Self.stamp.string(from: $0) } ?? "nil")")
        out.append("")
        out.append("[原始 JSON]")
        out.append(snapshot.rawJSON.isEmpty ? "(空)" : snapshot.rawJSON)
        out.append("")
        out.append("[接口清单]")
        if endpoints.isEmpty {
            out.append("  (空)")
        } else {
            for e in endpoints {
                out.append("  \(e.methods.joined(separator: "/")) \(e.url)\(e.looksLikeStore ? "   ← 疑似商店" : "")")
            }
        }
        out.append("")
        out.append("[日志]")
        out.append(contentsOf: log.reversed())
        return out.joined(separator: "\n")
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    func clearSession() {
        // 顺手清掉角色缓存 —— 否则换了账号还会显示上一个人的游戏 ID
        clearRoleCache()
        client.updateSession(ZhangwaSession())
        applySession(ZhangwaSession())
        snapshot = .empty
        state = .idle
        endpoints = []
        flipped = [false, false, false, false]
        clearCachedStore()
        clearCachedRoles()
        push("已清除会话")
    }

    /// 刷新票据。
    ///
    /// 掌瓦两个票据的有效期差了三个数量级（来自抓包里的 ct_info）：
    ///   refresh_wt_span = 1800     → wt（Cookie 里的 tid）只有 **30 分钟**
    ///   refresh_ct_span = 604800   → ct 有 **7 天**
    /// 所以必须用 ct 现换 wt，失败时也要**把真实错误打出来**，
    /// 不能像以前那样静默什么都不显示。
    func refreshTickets() async {
        guard hasSession else {
            push("还没有登录态，先导入")
            return
        }
        if session.ct.isEmpty {
            push("这份登录态没有 ct，换不了新票据 —— 只能重新导入带 ct 的 session")
            return
        }

        push("用 ct 换新 wt …")
        do {
            _ = try await client.refreshClientTicket()
        } catch {
            push("  refresh_client_ticket 失败：\(error.localizedDescription)")
        }

        if await client.refreshWebTicket() {
            push("  ✅ get_web_ticket 成功，tid 已更新（30 分钟后要再换）")
        } else {
            push("  ❌ get_web_ticket 失败 —— ct 可能也过期了，重新导入一份带 ct 的 session")
        }

        do {
            if try await client.refreshThirdToken() != nil {
                push("  refresh_third_token 成功")
            }
        } catch {
            push("  refresh_third_token 失败：\(error.localizedDescription)")
        }
        applySession(client.session)
    }

    // MARK: - 商店配置

    func saveShopPath(_ path: String, body: String) {
        let p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        client.shopPath = p.isEmpty ? nil : p
        UserDefaults.standard.set(p, forKey: Self.kShopPath)
        shopPathDraft = p

        let b = body.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(b, forKey: Self.kShopBody)
        client.shopBody = Self.parseJSONObject(b)
        shopBodyDraft = b

        push("商店接口已保存：\(p.isEmpty ? "(空)" : p)")
    }

    func setShopPath(fromEndpoint url: String) {
        // "https://app.mval.qq.com/go/xxx?y=1" → "/go/xxx"
        var path = url
        if let range = path.range(of: "/go/") {
            path = String(path[range.lowerBound...])
        }
        path = path.components(separatedBy: "?").first ?? path
        saveShopPath(path, body: shopBodyDraft)
    }

    // MARK: - 拉取

    func loadStore() async {
        // 顺带刷新游戏 ID —— 只拉一次的话换了名字/段位就不同步了。
        // 放在最前面是因为它比商店请求轻，先出名字体感更好。
        await loadUserRole()

        state = .loading
        // 注意：**不要**在这里把 flipped 清空。清空会让已经翻开的卡先合上再翻，
        // 画面会闪一下。等新数据到了由 restoreFlippedFlags() 一次性定。

        // ct 有效期 7 天，但过期前用旧的换一张新的就能一直滚下去。
        // 顺手在这里续一次，用户就不需要关心「什么时候该重新抓包」。
        if client.needsClientTicketRenewal {
            push("ct 快到 7 天了，自动续期中…")
            if await client.ensureFreshClientTicket() {
                applySession(client.session)
                push("  ✅ ct 已续期，又是 7 天")
            } else {
                push("  ⚠️ 续期失败（可能 ct 已经过期），需要重新抓一次包")
            }
        }

        do {
            let raw = try await client.fetchStore()
            let snap = StoreNormalizer.normalize(raw)
            snapshot = snap
            state = .loaded
            lastLoadedAt = Date()
            restoreFlippedFlags()
            cacheSnapshot()          // 下次冷启动直接拿这份铺屏
            push("商店读取成功，\(snap.items.count) 件商品")
            if snap.items.isEmpty {
                push("没解析出商品，原始字段：\(snap.rawKeys.joined(separator: ", "))")
            }
        } catch {
            state = .failed(error.localizedDescription)
            push("读取失败：\(error.localizedDescription)")
        }
    }

    /// 进 App 自动读一次 —— 但**这一期已经读到过就不重复读**。
    ///
    /// "这一期"用 `snapshot.expiresAt`（= 下一次刷新点）判定：它还没到，
    /// 手上这份就是当前这一期的商店，没必要再打一次接口。
    ///
    /// 冷启动时 `init()` 已经把上一期读到的快照塞进 `snapshot` 了，
    /// 所以这里命中"已读过"就等于**界面立刻有东西**，不等网络。
    func loadStoreIfNeeded() async {
        guard hasSession else { return }
        let fresh = !snapshot.items.isEmpty
            && (snapshot.expiresAt.map { $0 > Date() } ?? false)
        if fresh {
            push("这一期已经读过了，用现有数据")
            // 角色信息在后台刷一下就好，不挡界面（卡面/价格已经在屏幕上了）
            Task { await loadUserRole() }
            restoreFlippedFlags()
            return
        }
        await loadStore()                 // 里面会先刷角色再拉商店
    }

    // MARK: - 翻牌状态的记忆
    //
    //  "翻过就不再翻一遍"：记的是**这一期商店**（期号 + 商品 id）的状态，
    //  明天 8 点刷新后期号变了，自然就回到全部卡背。

    private static let kFlipped = "zw.flippedPeriod"

    /// 这一期商店的标识：刷新时间所在的日期 + 四件商品的 id
    private var flipPeriodKey: String {
        let day = Calendar.current.startOfDay(for: snapshot.expiresAt ?? Date())
        let ids = snapshot.items.map(\.id).joined(separator: "|")
        return "\(Int(day.timeIntervalSince1970))#\(ids)"
    }

    /// 从本地恢复「这一期翻过没」。翻过的直接呈现翻开状态。
    func restoreFlippedFlags() {
        var flags = [false, false, false, false]     // 固定四格，和 2×2 卡阵对齐
        if let rec = UserDefaults.standard.dictionary(forKey: Self.kFlipped),
           rec["key"] as? String == flipPeriodKey,
           let bits = rec["flags"] as? String {
            for (i, ch) in bits.enumerated() where i < flags.count {
                flags[i] = (ch == "1")
            }
        }
        flipped = flags
    }

    /// 记下这一期的翻牌状态。翻一张存一次，杀进程再进也还在。
    private func persistFlippedFlags() {
        guard !snapshot.items.isEmpty else { return }
        let bits = flipped.map { $0 ? "1" : "0" }.joined()
        UserDefaults.standard.set(["key": flipPeriodKey, "flags": bits],
                                  forKey: Self.kFlipped)
    }

    // MARK: - 冷启动缓存
    //
    //  为什么要有这一层：冷启动原来必须等两轮网络（角色 + 商店），之后四张卡
    //  才开始下皮肤图（每张 1.6MB 原图）。用户看到的就是"账号和图片都要加载好一会"。
    //  现在把上一期读到的商店和角色写在本地，`init()` 里同步铺上屏，
    //  网络回来只是覆盖同一份数据 —— 界面上没有空窗期。

    private static let kCachedSnapshot = "zw.cachedSnapshot.v1"
    private static let kCachedRole = "zw.cachedRole.v1"
    private static let kCachedRoles = "zw.cachedRoles.v1"

    private static func loadCachedSnapshot() -> StoreSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: kCachedSnapshot) else { return nil }
        return try? JSONDecoder().decode(StoreSnapshot.self, from: data)
    }

    private static func loadCachedRole() -> UserRole? {
        guard let data = UserDefaults.standard.data(forKey: kCachedRole) else { return nil }
        return try? JSONDecoder().decode(UserRole.self, from: data)
    }

    private static func loadCachedRoles() -> [UserRole]? {
        guard let data = UserDefaults.standard.data(forKey: kCachedRoles) else { return nil }
        return try? JSONDecoder().decode([UserRole].self, from: data)
    }

    /// 商店读成功后存一份（只有 URL 和字段，几十 KB）
    private func cacheSnapshot() {
        guard !snapshot.items.isEmpty,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.kCachedSnapshot)
    }

    private func cacheRoles() {
        if let role = userRole, let data = try? JSONEncoder().encode(role) {
            UserDefaults.standard.set(data, forKey: Self.kCachedRole)
        }
        if !availableRoles.isEmpty, let data = try? JSONEncoder().encode(availableRoles) {
            UserDefaults.standard.set(data, forKey: Self.kCachedRoles)
        }
    }

    private func clearCachedStore() {
        UserDefaults.standard.removeObject(forKey: Self.kCachedSnapshot)
    }

    private func clearCachedRoles() {
        UserDefaults.standard.removeObject(forKey: Self.kCachedRole)
        UserDefaults.standard.removeObject(forKey: Self.kCachedRoles)
    }

    /// 翻一张（视图负责包 `withAnimation`）
    func setFlipped(_ index: Int, to value: Bool) {
        guard index < flipped.count else { return }
        flipped[index] = value
        persistFlippedFlags()
    }

    func probe() async {
        state = .loading
        push("探测候选路径（POST/GET 都试；只看 result=0 不算数，data 里得有东西）…")
        let results = await client.probeShop()
        for r in results {
            push("\(r.ok ? "✅" : "❌") \(r.path)  \(r.detail)")
        }
        let hits = results.filter { $0.ok }
        if hits.count == 1, let only = hits.first {
            saveShopPath(only.path, body: shopBodyDraft)
            push("唯一命中，已自动填入：\(only.path)")
        } else if hits.count > 1 {
            push("有 \(hits.count) 个命中，不自动填了，你挑一个。")
        } else {
            push("没命中。默认值本来就是实测确认的接口，点「恢复默认接口」即可。")
        }
        state = .idle
    }

    /// 把商店接口恢复成实测确认的默认值。
    /// 探测一旦填入错的路径（比如那个返回空壳的 zone=shop），用户得有办法退回来。
    func resetShopPath() {
        saveShopPath(ZhangwaClient.dailyStorePath, body: "{}")
        push("已恢复默认接口：\(ZhangwaClient.dailyStorePath)")
    }

    // MARK: - 演示

    /// 演示数据。用真实抓包里的商品名，纯离线，不联网。
    func loadDemo() {
        func item(_ id: String, _ name: String, _ weapon: String,
                  _ price: Int, _ quality: String, _ owned: Bool) -> ShopItem {
            ShopItem(id: id, name: name, weaponName: weapon, iconURL: nil,
                     price: price, qualityKey: quality, rarity: Rarity.from(quality),
                     owned: owned, offerID: id)
        }

        snapshot = StoreSnapshot(
            title: "每日商店",
            key: "dailystore",
            items: [
                item("d1", "金角生辉 判官", "判官 / Sheriff", 1290, "purple", false),
                item("d2", "荆刺链刃", "近战 / Melee", 3180, "orange", true),
                item("d3", "天界神兵//2.0 奥丁", "奥丁 / Odin", 1290, "purple", false),
                item("d4", "ORA x 颗秒 狂徒", "狂徒 / Vandal", 1790, "yellow", false),
            ],
            expiresAt: Date().addingTimeInterval(60_433),
            remainingSeconds: 60_433,
            remaining: "16 小时 47 分",
            currency: "点券",
            rawKeys: ["demo"],
            rawJSON: "{}")
        state = .loaded
        restoreFlippedFlags()
        lastLoadedAt = Date()
        push("已载入演示数据（真实抓包里的商品名，但价格/品质只是样例）")
    }

    // MARK: - 工具

    func push(_ line: String) {
        log.insert("\(Self.clock.string(from: Date()))  \(line)", at: 0)
        if log.count > 300 { log.removeLast(log.count - 300) }
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static func parseJSONObject(_ text: String) -> [String: Any]? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let data = t.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
