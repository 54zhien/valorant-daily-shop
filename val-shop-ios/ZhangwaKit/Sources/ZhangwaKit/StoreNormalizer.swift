import Foundation

// MARK: - 品质

/// 掌瓦商城的品质档位。
///
/// 服务端在 `quality` 字段里给的是**颜色名**，只有 5 个取值：
/// `blue / green / purple / orange / yellow`。
/// 这和 APK 里的 `res/drawable-xhdpi-v4/ic_val_goods_quality_1..5.png`
/// 以及 RN bundle 里的 `QUALITY_ICON_MAP` / `flip_quality_bg_<color>.png` 一一对应。
///
/// ⚠️ 注意：这是**掌瓦商城自己的视觉档位**，不等于游戏里的品质名
/// （实测同一档位下价格并不落在游戏的 875/1275/1775/2175/2475 上）。
/// 所以这里保留原始 `qualityKey`，展示时优先用服务端给的原值。
public enum Rarity: Int, CaseIterable, Hashable, Sendable {
    case blue = 1
    case green = 2
    case purple = 3
    case orange = 4
    case yellow = 5

    /// 服务端的原始颜色名
    public var qualityKey: String {
        switch self {
        case .blue: return "blue"
        case .green: return "green"
        case .purple: return "purple"
        case .orange: return "orange"
        case .yellow: return "yellow"
        }
    }

    public var label: String { qualityKey.uppercased() }

    public var cnLabel: String {
        switch self {
        case .blue: return "蓝"
        case .green: return "绿"
        case .purple: return "紫"
        case .orange: return "橙"
        case .yellow: return "金"
        }
    }

    /// 取自掌瓦资源里的品质色（`val_goods_quality_1..5`）
    public var colorHex: String {
        switch self {
        case .blue: return "#4A90D9"
        case .green: return "#3AC58A"
        case .purple: return "#A85CE0"
        case .orange: return "#E07A20"
        case .yellow: return "#E0B020"
        }
    }

    private static let aliases: [String: Rarity] = [
        "blue": .blue, "green": .green, "purple": .purple,
        "orange": .orange, "yellow": .yellow,
        // 兼容国际服 / 老接口的写法
        "select": .blue, "deluxe": .green, "premium": .purple,
        "exquisite": .orange, "exclusive": .orange, "ultra": .yellow,
    ]

    /// 从服务端的 `quality` 字段解析。认不出来时返回 nil，
    /// 让调用方保留原始字符串，而不是硬塞一个默认档。
    public static func from(_ raw: Any?) -> Rarity? {
        if let n = ZhangwaClient.intValue(raw), let r = Rarity(rawValue: n) { return r }
        if let s = raw as? String {
            if let n = Int(s), let r = Rarity(rawValue: n) { return r }
            if let r = aliases[s.lowercased()] { return r }
        }
        return nil
    }
}

// MARK: - 商品

public struct ShopItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let weaponName: String
    public let iconURL: URL?
    public let price: Int?
    /// 服务端原始 quality 值（认不出档位时也能原样显示）
    public let qualityKey: String
    public let rarity: Rarity?
    /// 品质背景图（服务端会给 pink/yellow/golden 等）
    public let bgImageURL: URL?
    /// 例如 "3.1万人想要"
    public let likeText: String?
    /// 例如 "请前往游戏中购买！"
    public let tips: String?
    public let owned: Bool
    public let offerID: String

    public init(id: String, name: String, weaponName: String, iconURL: URL?,
                price: Int?, qualityKey: String = "", rarity: Rarity?,
                bgImageURL: URL? = nil, likeText: String? = nil, tips: String? = nil,
                owned: Bool, offerID: String) {
        self.id = id
        self.name = name
        self.weaponName = weaponName
        self.iconURL = iconURL
        self.price = price
        self.qualityKey = qualityKey
        self.rarity = rarity
        self.bgImageURL = bgImageURL
        self.likeText = likeText
        self.tips = tips
        self.owned = owned
        self.offerID = offerID
    }

    /// 卡片上显示用的品质文字
    public var qualityText: String {
        if let rarity { return rarity.cnLabel }
        return qualityKey.isEmpty ? "" : qualityKey
    }
}

public struct StoreSnapshot: Sendable {
    /// 面板标题，例如「每日商店」
    public let title: String
    /// 面板 key，例如 `dailystore`
    public let key: String
    public let items: [ShopItem]
    public let expiresAt: Date?
    /// 服务端直接给的剩余秒数（比本地算准）
    public let remainingSeconds: Int?
    public let remaining: String?
    public let currency: String
    public let rawKeys: [String]
    public let rawJSON: String

    public static let empty = StoreSnapshot(
        title: "", key: "", items: [], expiresAt: nil, remainingSeconds: nil,
        remaining: nil, currency: "VP", rawKeys: [], rawJSON: "")

    public init(title: String, key: String, items: [ShopItem],
                expiresAt: Date?, remainingSeconds: Int?, remaining: String?,
                currency: String, rawKeys: [String], rawJSON: String) {
        self.title = title
        self.key = key
        self.items = items
        self.expiresAt = expiresAt
        self.remainingSeconds = remainingSeconds
        self.remaining = remaining
        self.currency = currency
        self.rawKeys = rawKeys
        self.rawJSON = rawJSON
    }
}

// MARK: - 归一化
//
// 真实响应（2026-10 抓包，POST /go/mlol_store/agame/user_store body={}）：
//
//   {
//     "result": 0,
//     "data": [
//       {
//         "key": "dailystore",
//         "title": "每日商店",
//         "time": 60433,            // 距离刷新还有多少秒
//         "end_ts": 1792367999,     // 刷新时刻（unix 秒）
//         "cur_ts": 1792307566,     // 服务端当前时间
//         "list": [
//           {
//             "goods_name": "金角生辉 判官",
//             "goods_pic": "https://game.gtimg.cn/.../WeaponSkins/xxx.png",
//             "goods_id": "4f45735c-...", "guid": "57AD1E5D-...",
//             "rmb_price": "1290",     // 字符串！单位是点券
//             "quality": "purple",
//             "bg_image": "https://game.gtimg.cn/.../store/pink.png",
//             "like_num": "3.1万人想要",
//             "tips": "请前往游戏中购买！",
//             "showed": 1, "show_mask_quality": 0,
//             "token": "", "skin_tag": "", "intent": "", "package_bg": "..."
//           }
//         ]
//       }
//     ]
//   }

public enum StoreNormalizer {

    /// 首选面板（按这个顺序找）。`kingdomstore` 故意不列进来 ——
    /// 它是「王国商店」，只有每日商店不存在时才退而求其次。
    public static let preferredKeys = ["dailystore", "userstore", "dailyshop"]

    public static func normalize(_ raw: Any?) -> StoreSnapshot {
        // 注意：ZhangwaClient.request 返回的是**信封里的 data**，
        // 也就是直接给到这里的是 `[{key: dailystore, ...}]` 这种数组，
        // 不是 {"result":0,"data":[...]}。两种都要认。
        let root: [String: Any]
        if let dict = raw as? [String: Any] {
            root = dict
        } else if let array = raw as? [Any] {
            root = ["data": array]
        } else {
            return .empty
        }

        let rawKeys = Array(root.keys).sorted()
        let rawJSON = preview(root)

        // 找面板列表
        let panels = findPanels(in: root)
        guard !panels.isEmpty else { return blank(root, rawKeys, rawJSON) }

        // 优先拿 dailystore，没有就按顺序第一个
        let panel = panels.first(where: { preferredKeys.contains(keyOf($0)) })
            ?? panels[0]

        let list = firstList(in: panel)
        let items = list.compactMap { item(from: $0) }

        let remaining = ZhangwaClient.intValue(panel["time"])
        let expires = expiryDate(in: panel)

        return StoreSnapshot(
            title: stringValue(panel["title"]) ?? "",
            key: keyOf(panel),
            items: items,
            expiresAt: expires,
            remainingSeconds: remaining,
            remaining: remaining.map { formatRemaining($0) },
            currency: "点券",
            rawKeys: rawKeys,
            rawJSON: rawJSON)
    }

    private static let expiryKeys = [
        "end_ts", "endTime", "expire_time", "expiresAt", "expire_ts",
        "next_refresh", "NextRefreshAt", "refreshTime",
        "SingleItemOfferExpirationTime", "singleItemOfferExpirationTime",
    ]

    private static func expiryDate(in panel: [String: Any]) -> Date? {
        for k in expiryKeys {
            if let ts = ZhangwaClient.doubleValue(panel[k]), ts > 0 {
                return Date(timeIntervalSince1970: ts)
            }
        }
        return nil
    }

    // MARK: 面板

    /// 商品数组可能挂在这些 key 下面：
    ///   · `list`              —— 掌瓦真实接口（/go/mlol_store/agame/user_store）
    ///   · `SingleItemOffers`  —— 国际服 storefront
    ///   · 其余是各种兼容写法
    private static let listKeys = [
        "list", "items", "offers", "SingleItemOffers", "singleItemOffers",
        "Offers", "goods", "goods_list",
    ]

    private static func firstList(in panel: [String: Any]) -> [Any] {
        for k in listKeys {
            if let a = panel[k] as? [Any] { return a }
        }
        return []
    }

    private static func findPanels(in root: [String: Any]) -> [[String: Any]] {
        // 真实形态：data 是数组
        if let data = ZhaoArray(root["data"]) {
            let panels = data.compactMap { $0 as? [String: Any] }
            let withList = panels.filter { $0["list"] != nil }
            if !withList.isEmpty { return withList }
        }
        // data 是单个对象
        if let data = root["data"] as? [String: Any] {
            for key in ["list", "panels", "storefront", "SkinsPanelLayout"] {
                if let arr = ZhaoArray(data[key]) {
                    let panels = arr.compactMap { $0 as? [String: Any] }
                    if !panels.isEmpty { return panels }
                }
            }
            if data["list"] != nil { return [data] }
        }
        // 顶层直接就是一个面板（含 list / items）
        if root["list"] != nil || root["items"] != nil { return [root] }
        // 兼容国际服形态
        if let skins = root["SkinsPanelLayout"] as? [String: Any] { return [skins] }
        return []
    }

    private static func keyOf(_ panel: [String: Any]) -> String {
        stringValue(panel["key"])?.lowercased() ?? ""
    }

    // MARK: 单件商品

    private static func item(from raw: Any) -> ShopItem? {
        guard let d = raw as? [String: Any] else { return nil }

        let name = firstString(d, ["goods_name", "Name", "name"]) ?? ""
        guard !name.isEmpty else { return nil }

        let qualityRaw = firstString(d, ["quality", "Quality", "tier", "rarity"])
        let rarity = Rarity.from(qualityRaw)

        let id = firstString(d, ["goods_id", "OfferID", "id"]) ?? name
        let guid = firstString(d, ["guid"]) ?? ""

        return ShopItem(
            id: id,
            name: name,
            weaponName: firstString(d, ["weapon_name", "weaponName", "skin_tag"]) ?? "",
            iconURL: url(firstString(d, ["goods_pic", "icon", "icon_url", "image"])),
            price: ZhangwaClient.intValue(d["rmb_price"] ?? d["Cost"] ?? d["price"]),
            qualityKey: qualityRaw ?? "",
            rarity: rarity,
            bgImageURL: url(firstString(d, ["bg_image", "bgImage"])),
            likeText: firstString(d, ["like_num", "likeText"]),
            tips: firstString(d, ["tips"]),
            owned: ZhangwaClient.intValue(d["showed"]) == 0
                || (d["owned"] as? Bool == true),
            offerID: guid.isEmpty ? id : guid)
    }

    // MARK: 工具

    private static func blank(_ root: [String: Any], _ keys: [String], _ json: String) -> StoreSnapshot {
        StoreSnapshot(title: "", key: "", items: [], expiresAt: nil,
                      remainingSeconds: nil, remaining: nil, currency: "点券",
                      rawKeys: keys, rawJSON: json)
    }

    private static func firstString(_ d: [String: Any], _ keys: [String]) -> String? {
        for k in keys {
            if let s = d[k] as? String, !s.isEmpty { return s }
            if let n = d[k] as? NSNumber { return n.stringValue }
        }
        return nil
    }

    private static func stringValue(_ any: Any?) -> String? {
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    private static func url(_ raw: String?) -> URL? {
        guard var s = raw, !s.isEmpty else { return nil }
        // 有些图写成协议相对的 //xxx
        if s.hasPrefix("//") { s = "https:" + s }
        return URL(string: s)
    }

    private static func formatRemaining(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return h > 0 ? "\(h) 小时 \(m) 分" : "\(m) 分钟"
    }

    private static func preview(_ any: Any) -> String {
        if JSONSerialization.isValidJSONObject(any),
           let d = try? JSONSerialization.data(withJSONObject: any, options: []),
           let s = String(data: d, encoding: .utf8) {
            return String(s.prefix(20000))
        }
        return ""
    }
}

/// 小工具：把可能是数组也可能不是的东西统一成数组
private func ZhaoArray(_ any: Any?) -> [Any]? {
    if let a = any as? [Any] { return a }
    return nil
}
