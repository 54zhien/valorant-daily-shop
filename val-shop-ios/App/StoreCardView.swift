import SwiftUI
import ZhangwaKit

/// 一张翻牌卡。
///
/// 掌瓦原生只留了两个开关（`val_close_shop_commodity_animation`、
/// `val_hide_shop_commodity_quality`），动画本身在这里实现：
/// 整块玻璃面板绕 Y 轴翻 180°，玻璃用品质色染色。
struct StoreCardView: View {
    let item: ShopItem
    let isFlipped: Bool
    let namespace: Namespace.ID
    let morphID: String
    let onTap: () -> Void

    var body: some View {
        ZStack {
            back
                .opacity(isFlipped ? 0 : 1)
            front
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(0.76, contentMode: .fit)
        .zwGlassCard(tint: isFlipped ? item.rarity.color.opacity(0.30) : nil,
                     interactive: true)
        .zwMorphID(morphID, in: namespace)
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0),
                          axis: (x: 0, y: 1, z: 0),
                          perspective: 0.35)
        .contentShape(RoundedRectangle(cornerRadius: ZWGlass.cardRadius, style: .continuous))
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(isFlipped ? "双击翻回卡背" : "双击翻开")
    }

    private var accessibilityText: String {
        guard isFlipped else { return "未翻开的商店卡" }
        let price = item.price.map { "\($0) VP" } ?? "价格未知"
        let owned = item.owned ? "，已拥有" : ""
        return "\(item.name)，\(item.weaponName)，\(price)，\(item.rarity.cnLabel)\(owned)"
    }

    // MARK: 卡背

    private var back: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ZWGlass.cardRadius, style: .continuous)
                .fill(.clear)
            VStack(spacing: 6) {
                Image(systemName: "questionmark")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.tertiary)
                Text("点击翻开")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: 卡面

    private var front: some View {
        VStack(spacing: 0) {
            ZStack {
                RadialGradient(colors: [item.rarity.color.opacity(0.35), .clear],
                               center: UnitPoint(x: 0.5, y: 0.4),
                               startRadius: 2, endRadius: 140)
                thumbnail
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                if item.owned {
                    Text("已拥有")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .zwGlassChip(tint: .zwMint)
                        .padding(8)
                }
            }

            meta
        }
        .clipShape(RoundedRectangle(cornerRadius: ZWGlass.cardRadius, style: .continuous))
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = item.iconURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure:
                    placeholder
                default:
                    ProgressView()
                }
            }
            .padding(10)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .font(.system(size: 26))
            .foregroundStyle(.tertiary)
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .frame(height: 34, alignment: .topLeading)

            Text(item.weaponName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 6) {
                Text(item.price.map(String.init) ?? "—")
                    .font(.subheadline.weight(.bold))
                    .contentTransition(.numericText())
                Text("VP")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(item.rarity.label)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(item.rarity.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(item.rarity.color, lineWidth: 1)
                    )
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
