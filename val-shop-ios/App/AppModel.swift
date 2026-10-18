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
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// 读构建期注入的默认配置。CI 会覆写 App/BundledConfig.plist。
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

    var hasSession: Bool { session.isValid }

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
    /// AirDrop 过来的文件直接丢进「我的 iPhone → 每日商店」，然后点一下就行。
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
            push("App 文件夹是空的。把 mval_session.json / mval_capture.log 放进「文件」App 的「我的 iPhone → 每日商店」再试。")
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
        out.append("=== 每日商店诊断 ===")
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
        client.updateSession(ZhangwaSession())
        applySession(ZhangwaSession())
        snapshot = .empty
        state = .idle
        endpoints = []
        push("已清除会话")
    }

    func refreshTickets() async {
        push("刷新票据 …")
        if (try? await client.refreshClientTicket()) == true {
            push("refresh_client_ticket 成功，ct 已更新")
        }
        if await client.refreshWebTicket() {
            push("get_web_ticket 成功，tid 已更新")
        }
        if (try? await client.refreshThirdToken()) != nil {
            push("refresh_third_token 成功，access_token 已更新")
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
        state = .loading
        flipped = [false, false, false, false]
        do {
            let raw = try await client.fetchStore()
            let snap = StoreNormalizer.normalize(raw)
            snapshot = snap
            state = .loaded
            push("商店读取成功，\(snap.items.count) 件商品")
            if snap.items.isEmpty {
                push("没解析出商品，原始字段：\(snap.rawKeys.joined(separator: ", "))")
            }
        } catch {
            state = .failed(error.localizedDescription)
            push("读取失败：\(error.localizedDescription)")
        }
    }

    func probe() async {
        state = .loading
        push("探测候选路径（POST/GET 都试）…")
        let results = await client.probeShop()
        for r in results {
            push("\(r.ok ? "✅" : "❌") \(r.path)  \(r.detail)")
        }
        if let first = results.first(where: { $0.ok }) {
            saveShopPath(first.path, body: shopBodyDraft)
            push("已自动填入命中路径：\(first.path)")
        } else {
            push("没命中 —— 必须抓包拿到真实路径（见 README）")
        }
        state = .idle
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
        flipped = [false, false, false, false]
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
