import SwiftUI
import ZhangwaKit

// 颜色尽量交给系统：语义色 + 材质 + Asset Catalog。
// 这里只保留系统给不了的两件东西：品质色映射、以及掌瓦的品牌色。

extension Rarity {
    /// 取自掌瓦资源里的品质色（`ic_val_goods_quality_1..5.png`）
    var color: Color {
        Color(hexString: colorHex) ?? .gray
    }
}

extension ShopItem {
    /// 卡片主色。认不出品质时退回中性灰，不要瞎猜一个档
    var accentColor: Color {
        rarity?.color ?? Color(white: 0.45)
    }

}

extension Color {
    init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }

    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8) & 0xFF) / 255.0,
                  blue: Double(hex & 0xFF) / 255.0,
                  opacity: 1.0)
    }
}

extension StoreSnapshot {
    /// 概览用的小统计
    var totalPrice: Int {
        items.compactMap(\.price).reduce(0, +)
    }

    var ownedCount: Int {
        items.filter(\.owned).count
    }
}
