import SwiftUI
import ZhangwaKit

// 颜色尽量交给系统：语义色 + 材质 + Asset Catalog。
// 这里只保留两件系统给不了的东西：品牌色、以及品质→颜色 的映射。

extension Rarity {
    /// 对应 `res/drawable-xhdpi-v4/ic_val_goods_quality_1..5.png` 的五档配色
    var color: Color {
        switch self {
        case .select:    return Color(red: 0.29, green: 0.56, blue: 0.85)
        case .deluxe:    return Color(red: 0.23, green: 0.77, blue: 0.54)
        case .premium:   return Color(red: 0.66, green: 0.36, blue: 0.88)
        case .exquisite: return Color(red: 0.88, green: 0.63, blue: 0.13)
        case .ultra:     return Color(red: 0.88, green: 0.29, blue: 0.13)
        }
    }
}

extension StoreSnapshot {
    /// 给图表/概览用的小统计
    var totalPrice: Int {
        items.compactMap(\.price).reduce(0, +)
    }

    var ownedCount: Int {
        items.filter(\.owned).count
    }
}
