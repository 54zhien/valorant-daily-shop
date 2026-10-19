import SwiftUI
import ZhangwaKit

// ============================================================================
//  模型 → 视图的取值助手
// ============================================================================
//
//  颜色 / 形状 / 字体这些**视觉 token** 全在 `DesignSystem.swift`；
//  这个文件只管「把 ZhangwaKit 的模型翻译成 UI 要用的东西」。
// ============================================================================

extension Rarity {
    /// 取自掌瓦资源里的品质色（`ic_val_goods_quality_1..5.png`）
    var color: Color {
        Color(hexString: colorHex) ?? .secondary
    }
}

extension ShopItem {
    /// 卡片主色。认不出品质时退回中性灰，不要瞎猜一个档
    var accentColor: Color {
        rarity?.color ?? Color(white: 0.45)
    }

    /// 卡上那个字的品质名：紫 / 金 / 橙 …… 认不出就退回服务端原值
    var gradeGlyph: String {
        if let rarity { return rarity.cnLabel }
        return qualityKey.isEmpty ? "—" : qualityKey
    }

    /// 价格带千位空格：1290 -> "1 290"（等宽数字读起来更利落）
    var priceText: String {
        guard let price else { return "—" }
        return Self.spaced(price)
    }

    /// 1290 -> "1 290"
    static func spaced(_ value: Int) -> String {
        let digits = String(value)
        guard digits.count > 3 else { return digits }
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(" ") }
            out.append(ch)
        }
        return out
    }
}

extension StoreSnapshot {
    /// 概览：这一屏四张卡加起来多少钱
    var totalPrice: Int {
        items.compactMap(\.price).reduce(0, +)
    }

    var ownedCount: Int {
        items.filter(\.owned).count
    }

    /// 品质分布，形如「紫×2 金×1」——按档位从高到低排
    var gradeSummary: String {
        var counts: [(Rarity, Int)] = []
        for rarity in Rarity.allCases.reversed() {
            let n = items.filter { $0.rarity == rarity }.count
            if n > 0 { counts.append((rarity, n)) }
        }
        if counts.isEmpty { return "" }
        return counts.map { "\($0.0.cnLabel)×\($0.1)" }.joined(separator: "  ")
    }

    /// 没解析出品质档时也要有话说
    var gradeSummaryOrDash: String {
        let s = gradeSummary
        return s.isEmpty ? "—" : s
    }
}

// ============================================================================
//  会话健康度 —— 给普通人看的一句话
// ============================================================================
//
//  界面上一律不出现 ct / tid / 票据 / 接口 这类词。用户只需要知道：
//  能用 / 快去重新登录。细节留给诊断台。

enum SessionHealth {
    /// 没有登录态
    case none
    /// 登录着，但这套凭据不会自己续命了 —— 该提醒重新扫
    case needsRelogin
    /// 快到期（续期窗口最后 2 天）
    case expiring
    /// 一切正常
    case ok

    var text: String {
        switch self {
        case .none:        return "未登录"
        case .needsRelogin: return "建议重新登录"
        case .expiring:    return "即将过期"
        case .ok:          return "已登录"
        }
    }

    var tint: Color {
        switch self {
        case .none:        return .secondary
        case .needsRelogin: return .zwRouge
        case .expiring:    return .zwRouge
        case .ok:          return .zwSignal
        }
    }
}

extension AppModel {
    var sessionHealth: SessionHealth {
        guard hasSession else { return .none }
        if session.ct.isEmpty { return .needsRelogin }
        if let days = ctDaysLeft, days <= 2 { return .expiring }
        return .ok
    }
}
