import SwiftUI
import ZhangwaKit

/// 一张翻牌卡。
///
/// 版面沿用最早那版：**上面是画，下面是信息块**，中间一条系统分隔线。
/// 品质用三处说：斜带、钻标、卡背序号 —— 都在，但不靠玻璃。
///
/// ── 翻牌的三条铁律（都踩过坑，改之前先读）────────────────────────────
///
/// 1. **卡面必须整体被反向预旋转**，而且那个反向旋转要用正投影
///    （`perspective: 0`）。外层旋转带透视（0.35），内层若用默认透视（1），
///    两次透视叠加会把卡面的内容**缩放 + 错位** —— 看起来就是
///    「字和图片跑到卡外面 / 串到隔壁格子里」。
///
/// 2. **卡面内容必须长在 face 里面**。名字、武器、价格、图片、斜带、钻标，
///    一个都不能挂到外面去 —— 挂在外面的那一份不会跟着反向旋转，翻过来就是镜像的。
///
/// 3. **合成一层再翻**（`.compositingGroup()`），并且在旋转之前先裁形状。
///    不然 3D 层会各自找投影，翻的过程里内容会漏出卡片边界。
///
/// 4. 两个面在「转到 90°」那一刻瞬间换（`swapAnimation`）—— 那一刻卡片侧对镜头，
///    换面看不见，所以不会闪。旧版这里是跟着旋转一起淡入淡出，会看到叠影。
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

    /// 换面的时刻：旋转行程的一半。
    /// 配合 `ZW.flipCurve`（时间对称的 easeInOut），这一刻卡片正好转到 90°（侧对镜头），
    /// 所以换面看不见 —— 正面会从"侧着"一路转正，而不是突然蹦出来。
    private var swapAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : ZW.swapCurve
    }

    /// 卡面的反向预旋转角度。减弱动态效果时不做 3D，所以也不镜像。
    private var counterRotation: Double { reduceMotion ? 0 : 180 }

    /// 整张卡的旋转角度
    private var cardRotation: Double { reduceMotion ? 0 : (isFlipped ? 180 : 0) }

    var body: some View {
        ZStack {
            // 卡背：翻过去就藏起来
            back
                .opacity(isFlipped ? 0 : 1)
                .animation(swapAnimation, value: isFlipped)

            // 卡面：先把自己镜像一次（正投影），外层再转 180° 时它正好是正的
            front
                .rotation3DEffect(.degrees(counterRotation),
                                  axis: (x: 0, y: 1, z: 0),
                                  perspective: 0)
                .compositingGroup()
                .opacity(isFlipped ? 1 : 0)
                .animation(swapAnimation, value: isFlipped)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(6.0 / 7.0, contentMode: .fit)
        // 先裁一刀，再合成一层，最后才转 —— 内容出不了卡片，也不会串到隔壁
        .clipShape(shape)
        .background(Color(.secondarySystemGroupedBackground), in: shape)
        .compositingGroup()
        .rotation3DEffect(.degrees(cardRotation),
                          axis: (x: 0, y: 1, z: 0),
                          perspective: reduceMotion ? 0 : 0.35)
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
            // 自己的缓存（磁盘里存的是 340px 缩略图）：冷启动零网络，飞行模式也有图
            CachedImage(url: url, contentMode: .fit) { placeholder }
                .padding(10)
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
