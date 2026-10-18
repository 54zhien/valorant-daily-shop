import Foundation

// MARK: - 品质

/// 5 档品质，对应 `res/drawable-xhdpi-v4/ic_val_goods_quality_1..5.png`
public enum Rarity: Int, CaseIterable, Hashable, Sendable {
    case select = 1
    case deluxe = 2
    case premium = 3
    case exquisite = 4
    case ultra = 5

    public var label: String {
        switch self {
        case .select: return "SELECT"
        case .deluxe: return "DELUXE"
        case .premium: return "PREMIUM"
        case .exquisite: return "EXQUISITE"
        case .ultra: return "ULTRA"
        }
    }

    public var cnLabel: String {
        switch self {
        case .select: return "优选"
        case .deluxe: return "豪华"
        case .premium: return "尊贵"
        case .exquisite: return "卓越"
        case .ultra: return "传奇"
        }
    }

    /// 十六进制色值（和 web 端保持一致）
    public var colorHex: String {
        switch self {
        case .select: return "#4A90D9"
        case .deluxe: return "#3AC58A"
        case .premium: return "#A85CE0"
        case .exquisite: return "#E0A020"
        case .ultra: return "#E04A20"
        }
    }

    private static let aliases: [String: Rarity] = [
        "select": .select, "deluxe": .deluxe, "premium": .premium,
        "exquisite": .exquisite, "exclusive": .exquisite, "ultra": .ultra,
        "普通": .select, "优选": .select, "豪华": .deluxe,
        "尊贵": .premium, "卓越": .exquisite, "传奇": .ultra, "终极": .ultra,
    ]

    public static func from(_ raw: Any?) -> Rarity {
        if let n = ZhangwaClient.intValue(raw), n >= 1, n <= 5, let r = Rarity(rawValue: n) {
            return r
        }
        if let s = raw as? String {
            if let n = Int(s), let r = Rarity(rawValue: n) { return r }
            if let r = aliases[s.lowercased()] { return r }
            if let r = aliases[s] { return r }
        }
        return .premium
    }
}

// MARK: - 商品

public struct ShopItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let weaponName: String
    public let iconURL: URL?
    public let price: Int?
    public let rarity: Rarity
    public let owned: Bool
    public let offerID: String

    public init(id: String, name: String, weaponName: String, iconURL: URL?,
                price: Int?, rarity: Rarity, owned: Bool, offerID: String) {
        self.id = id
        self.name = name
        self.weaponName = weaponName
        self.iconURL = iconURL
        self.price = price
        self.rarity = rarity
        self.owned = owned
        self.offerID = offerID
    }
}

public struct StoreSnapshot: Sendable {
    public let items: [ShopItem]
    public let expiresAt: Date?
    public let remaining: String?
    public let currency: String
    public let rawKeys: [String]
    public let rawJSON: String

    public static let empty = StoreSnapshot(items: [], expiresAt: nil, remaining: nil,
                                            currency: "VP", rawKeys: [], rawJSON: "")

    public init(items: [ShopItem], expiresAt: Date?, remaining: String?,
                currency: String, rawKeys: [String], rawJSON: String) {
        self.items = items
        self.expiresAt = expiresAt
        self.remaining = remaining
        self.currency = currency
        self.rawKeys = rawKeys
        self.rawJSON = rawJSON
    }
}

// MARK: - 归一化

/// 把掌瓦（或国际服）的商店响应统一成前端契约。
/// 对应 Python 版 `server/app.py#normalize_store`。
public enum StoreNormalizer {

    private static let containers = [
        "SkinsPanelLayout", "skins_panel_layout", "storefront",
        "panel", "singleItemOffers", "SingleItemOffers", "items", "list", "offers",
    ]

    private static let offerKeys = [
        "SingleItemOffers", "singleItemOffers", "offers", "items", "list",
    ]

    public static func normalize(_ raw: Any) -> StoreSnapshot {
        let rawJSON: String
        if let d = try? JSONSerialization.data(withJSONObject: raw,
                                               options: [.prettyPrinted, .sortedKeys]),
           let s = String(data: d, encoding: .utf8) {
            rawJSON = s
        } else {
            rawJSON = "\(raw)"
        }

        guard let root = raw as? [String: Any] else {
            return StoreSnapshot(items: [], expiresAt: nil, remaining: nil,
                                 currency: "VP", rawKeys: [], rawJSON: rawJSON)
        }

        // 1) 找容器
        var container: [String: Any] = root
        for key in containers {
            if let node = root[key] as? [String: Any] {
                container = node
                break
            }
            if let node = root[key] as? [Any] {
                container = ["offers": node]
                break
            }
        }

        // 2) 找商品数组
        var offers: [Any] = []
        for key in offerKeys {
            if let node = container[key] as? [Any] {
                offers = node
                break
            }
        }
        if offers.isEmpty {
            for value in container.values {
                if let arr = value as? [Any], arr.first is [String: Any] {
                    offers = arr
                    break
                }
            }
        }

        // 3) 逐条映射
        var items: [ShopItem] = []
        for (index, element) in offers.enumerated() {
            guard let offer = element as? [String: Any] else { continue }

            let offerID = pickString(offer, ["OfferID", "offer_id", "offerId", "id"]) ?? "#\(index)"
            let skinUUID = pickString(offer, ["ItemID", "item_id", "skinUuid", "sku"]) ?? ""
            let name = pickString(offer, ["Name", "name", "skin_name", "displayName",
                                          "ItemName", "item_name"]) ?? "未知商品"
            let weapon = pickString(offer, ["weapon", "weaponName", "gun_name", "armName"]) ?? ""
            let icon = pickString(offer, ["IconUrl", "icon", "icon_url", "skin_icon",
                                          "displayIcon", "image", "img"])
            let price = pickInt(offer, ["Cost", "cost", "price", "vp", "point", "Price"])
            let rarity = Rarity.from(offer["quality"] ?? offer["Quality"]
                                     ?? offer["rarity"] ?? offer["tier"])
            let owned = pickBool(offer, ["owned", "is_owned", "Owned"])

            items.append(ShopItem(
                id: offerID.isEmpty ? "\(index)-\(skinUUID)" : offerID,
                name: name,
                weaponName: weapon,
                iconURL: normalizeImageURL(icon),
                price: price,
                rarity: rarity,
                owned: owned,
                offerID: offerID))
        }

        // 过期时间可能在外层，也可能在 panel 里（国际服是
        // SkinsPanelLayout.SingleItemOfferExpirationTime）
        let expireKeys = ["expiresAt", "expire_ts", "expire_ts_ms", "expire_time",
                          "expiration", "expiry", "next_refresh", "next_refresh_ts",
                          "refresh_at", "refreshTime", "NextRefreshAt",
                          "SingleItemOfferExpirationTime", "singleItemOfferExpirationTime"]
        let expiresAt = pickDate(root, expireKeys) ?? pickDate(container, expireKeys)
        let remainingKeys = ["remaining", "remain", "left_time", "time_left", "remainingTime"]
        let remaining = pickString(root, remainingKeys) ?? pickString(container, remainingKeys)
        let currency = pickString(root, ["currency", "VP", "vp", "currencyId"]) ?? "VP"

        return StoreSnapshot(items: items,
                             expiresAt: expiresAt,
                             remaining: remaining,
                             currency: currency,
                             rawKeys: root.keys.sorted(),
                             rawJSON: rawJSON)
    }

    // MARK: helpers

    private static func pick(_ dict: [String: Any], _ keys: [String]) -> Any? {
        for k in keys {
            if let v = dict[k], !(v is NSNull) {
                if let s = v as? String, s.isEmpty { continue }
                return v
            }
        }
        return nil
    }

    private static func pickString(_ dict: [String: Any], _ keys: [String]) -> String? {
        ZhangwaClient.stringValue(pick(dict, keys))
    }

    private static func pickInt(_ dict: [String: Any], _ keys: [String]) -> Int? {
        ZhangwaClient.intValue(pick(dict, keys))
    }

    private static func pickBool(_ dict: [String: Any], _ keys: [String]) -> Bool {
        guard let v = pick(dict, keys) else { return false }
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        if let s = v as? String { return s == "1" || s.lowercased() == "true" }
        return false
    }

    private static func pickDate(_ dict: [String: Any], _ keys: [String]) -> Date? {
        guard let v = pick(dict, keys) else { return nil }
        guard let n = ZhangwaClient.doubleValue(v), n > 0 else { return nil }
        // 秒 / 毫秒 都能吃
        let seconds = n > 1_000_000_000_000 ? n / 1000 : (n > 1_000_000_000 ? n : 0)
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// 掌瓦的图有些写成 `//xxx`（协议相对），补成 https；
    /// 其余原样保留 —— 部分 CDN（down.qq.com 等）只有 http，
    /// 交给 Info.plist 里针对 qq.com / qpic.cn 的 ATS 例外处理。
    private static func normalizeImageURL(_ raw: String?) -> URL? {
        guard var s = raw, !s.isEmpty else { return nil }
        if s.hasPrefix("//") { s = "https:" + s }
        return URL(string: s)
    }
}
