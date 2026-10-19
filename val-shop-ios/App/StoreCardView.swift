import SwiftUI
import ZhangwaKit

/// 一张翻牌卡。
///
/// 版面沿用最早那版：**上面是画，下面是信息块**，中间一条系统分隔线。
/// 品质用一个钻标表示（不再配「紫/金」那个字）。
///
/// ── 翻牌：全部交给 `FlipCard` ─────────────────────────────────────────
///
/// 这里只准备两个面（卡背 / 卡面）和外面的尺寸、点击、无障碍。
/// **进度驱动的翻牌逻辑、抬升投影、边缘透光都在 `FlipCard.swift`。**
///
/// 下面几条是踩过坑留下的纪律，改动这两个面之前先读：
///
/// 1. **卡面内容必须长在 face 里面**（名字、武器、价格、图片、斜带、钻标一个都不能挂外面），
///    挂在外面的那份不会跟着反向旋转，翻过来就是镜像的。
/// 2. 卡面自己会被 `FlipCard` 反向预旋转（正投影）—— 不要在这里再转一次。
/// 3. 两个面各自的形状裁切要保留，不然卡面的画会盖住圆角。
struct StoreCardView: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let item: ShopItem
    /// 第几张（01–04）—— 服务端给的槽位顺序，不是装饰
    let slot: Int
    let isFlipped: Bool
    let onTap: () -> Void

    private var tint: Color { item.accentColor }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ZW.radiusCard, style: .continuous)
    }

    var body: some View {
        FlipCard(isFlipped: isFlipped,
                 reduceMotion: reduceMotion,
                 cornerRadius: ZW.radiusCard,
                 accent: tint) {          // 想"不剧透"就换成 .white
            back
        } front: {
            front
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(6.0 / 7.0, contentMode: .fit)
        .contentShape(shape)
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(isFlipped ? "双击翻回卡背" : "双击翻开")
    }

    private var accessibilityText: String {
        guard isFlipped else { return "第 \(slot) 张，未翻开的商店卡" }
        let price = item.price.map { "\($0) 点券" } ?? "价格未知"
        let owned = item.owned ? "，已拥有" : ""
        let grade = item.gradeGlyph.isEmpty ? "" : "，\(item.gradeGlyph)档"
        return "\(item.name)，\(item.weaponName)，\(price)\(grade)\(owned)"
    }

    // MARK: - 卡背

    private var back: some View {
        ZStack {
            // 磨砂斜纹：给卡背一点质感，翻之前**不上品质色**（不泄漏品质）
            ZWHatchTexture(pitch: 8)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)

            VStack(spacing: 12) {
                ZWDiamond(inset: 0.30)
                    // `.tertiary` 是层级语义样式（不是 Color.tertiary —— 没有那个成员）
                    .stroke(.tertiary, lineWidth: 2)
                    .frame(width: 30, height: 30)
                Text("点一下翻开")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .overlay(alignment: .topLeading) {
            Text(String(format: "%02d", slot))
                .font(.zwMono(.caption2, weight: .regular))
                .foregroundStyle(.tertiary)
                .padding(.leading, 12)
                .padding(.top, 10)
        }
        .clipShape(shape)
    }

    // MARK: - 卡面

    private var front: some View {
        VStack(spacing: 0) {
            // 画：品质斜带打底 + 物品图
            ZStack {
                LinearGradient(colors: [tint.opacity(0.22), .clear],
                               startPoint: .topLeading,
                               endPoint: UnitPoint(x: 0.9, y: 0.7))

                art
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                // 品质只用一个钻标表示，不再配「紫 / 金 / 橙」那个字。
                // 文字版留在无障碍标签里（VoiceOver 仍然念得出档位）。
                ZWGradeMark(tint: tint, size: 9, filled: true)
                    .padding(.leading, 12)
                    .padding(.top, 10)
            }
            .overlay(alignment: .topTrailing) {
                if item.owned {
                    Text("已拥有")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.zwSignal)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.zwSignal.opacity(0.18), in: Capsule())
                        .padding(.trailing, 10)
                        .padding(.top, 9)
                }
            }

            Divider()

            meta
        }
        .clipShape(shape)
    }

    @ViewBuilder
    private var art: some View {
        if let url = item.iconURL {
            // 自己的缓存（磁盘里存的是 340px 缩略图）：冷启动零网络，飞行模式也有图。
            // artNormalize：所有皮肤图按"面积相同 + 高度封顶"排，短枪不会比长枪大一圈
            CachedImage(url: url, contentMode: .fit, artNormalize: true) { placeholder }
                .padding(.horizontal, 4)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZWDiamond(inset: 0.34)
            .stroke(tint.opacity(0.45), lineWidth: 2)
            .frame(width: 46, height: 46)
    }

    /// 信息块：名字 / 武器 / 价格。不透明底，不需要压暗渐层
    private var meta: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(weaponLine)
                .zwMachine(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(item.priceText)
                    .zwMonoStyle(.callout)
                    .contentTransition(.numericText())
                Text("VP")
                    .zwMachine(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 武器行：服务端没给武器名时退回「多少人想要」那句
    private var weaponLine: String {
        if !item.weaponName.isEmpty { return item.weaponName.uppercased() }
        return (item.likeText ?? "").uppercased()
    }
}
