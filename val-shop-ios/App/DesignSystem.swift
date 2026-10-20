import SwiftUI

// ============================================================================
//  设计系统 —— 只保留「文档没规定、但项目需要统一」的那点东西
// ============================================================================
//
//  ── 按 Apple 文档的划分 ────────────────────────────────────────────────
//
//  颜色：**不用自绘色板**。
//    · 文字层级用系统语义色 `.primary` / `.secondary` / `.tertiary`
//      （自动适配深色、浅色、增强对比度，见 HIG Color）
//    · 内容底色用系统语义背景 `Color(.systemBackground)` /
//      `.secondarySystemGroupedBackground`（表单/卡片用它，见 HIG Lists and tables）
//    · 输入区用 `.tertiarySystemFill`
//    · 品牌色（红 / 青绿）放 Assets.xcassets 的 colorset，用名字取
//      —— HIG 明确要求颜色定义在资产目录里，不要在代码里写 RGB
//
//  字体：**不用写死的点数**。
//    · 全部走 Dynamic Type 的文本样式（`.caption2` / `.footnote` / `.subheadline`…），
//      用户把系统字号调大，界面跟着长
//    · 只在这里允许两处「腔调」：机器腔（压缩宽度）和数据腔（等宽数字），
//      都是在系统字体上加 weight / width，不引入第三方字体
//
//  材质：**玻璃只用在控件层**（HIG Materials）。
//    · TabBar / NavigationBar / sheet / 浮动按钮 —— 系统已经帮你做了
//    · 内容层（卡片、列表行、板子）一律不透明：系统背景色 + 分组背景色
//
//  形状：品质钻与卡背斜纹是本项目自绘的（游戏资源的形状语言），
//        放在这里，并附几何验算台 probe/geometry_probe.swift
//
//  ── 并发隔离约定（改形状之前先看）──────────────────────────────────────
//  本项目开了 SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor。自定义 Shape 的
//  `path(in:)` 是 nonisolated 要求，**只能读实例属性**，不能读 static 常量。
//  实验台：probe/isolation_probe.swift
// ============================================================================

enum ZW {

    // MARK: - 几何（文档没规定，只是项目内的统一常数）

    /// 卡片 / 分组容器圆角
    static let radiusGroup: CGFloat = 16
    /// 卡片圆角
    static let radiusCard: CGFloat = 20
    /// 小控件（头像 / 图标）
    static let radiusControl: CGFloat = 11

    /// 发丝线
    static let hairline: CGFloat = 1

    /// 页边距 / 块间距
    static let pad: CGFloat = 16
    static let gap: CGFloat = 12
    static let gapLoose: CGFloat = 18

    /// 2×2 卡阵的间距。**比常规块间距大**：翻牌时光会从卡边往外渗 10pt 左右
    /// （`FlipCard.outerHalo`：外扩 4pt + 同量模糊），
    /// 20pt 的间距让相邻两张各留 10pt —— 光刚好留在自己那块地方，串不到隔壁。
    /// 想加粗外晕，先把这个数一起放大。
    static let cardGap: CGFloat = 20

    /// 内容最大宽度：iPad 上别把 2×2 卡阵拉成两米宽
    static let boardMaxWidth: CGFloat = 520

    /// 身份条头像
    static let avatar: CGFloat = 38

    // MARK: - 卡面画心（视觉尺寸归一）
    //
    //  皮肤图的画布尺寸不统一（实测 512×116 / 512×144 / 512×196，
    //  内容宽高比 2.5–3.8）。直接 scaledToFit 的话，越"方"的图（短枪、近战）
    //  高度越顶格，看着比长枪大一圈 —— 所以按"面积相同 + 高度封顶"来排。
    //  算法见 CachedImage.normalizedSize。

    /// 每张图占 art 区的面积比例
    static let artAreaFraction: CGFloat = 0.32
    /// 图的高度上限（占 art 区高度的比例）—— 短枪、近战不许比长枪高一大截
    static let artHeightCap: CGFloat = 0.62

    // MARK: - 动效

    /// 翻牌时长。
    /// 现在是一整段编排（光跑一圈 → 抬升 → 翻转 → 落下），不是单纯翻转，
    /// 所以比原来长：1.7s（其中细线绕一圈就占 900ms）。四张错开 130ms 连起来约 2.1s。
    static let flip: Double = 1.7
    /// 四张卡错开的间隔（毫秒）
    static let revealStagger: Int = 130

    /// 翻牌曲线。时间对称即可（easeInOut）——
    /// 换面现在由 `progress ≥ 0.5` 决定（见 FlipCard），不再依赖曲线中点。
    static var flipCurve: Animation { .easeInOut(duration: flip) }

    // MARK: - 翻牌的"演出"参数

    /// 抬升：向上位移多少 pt（"向顶部抬升"）
    static let flipLiftOffset: CGFloat = 7
    /// 抬升时顺带放大多少（0.04 = 4%，和位移一起才有"离开桌面"的错觉）
    static let flipLiftScale: CGFloat = 0.04

    // 光效分成两层：一根细线 + 线外面的一圈光晕。
    // 细线从点下去就有，绕完一圈也一直在；光晕只在"转完一圈"之后才亮起来。

    /// 品质细线：**贴着卡边**（外扩 0.5pt ≈ 压在轮廓上），而且要"细细一根"
    ///
    /// 0.7pt：3x 屏上约 2px，仍然是一根线而不是一条边。
    /// **扫的时候和翻完之后是同一根线、同一个宽度**（`edgeLine` 只画一份，
    /// 落地只降不透明度、不改粗细），所以两边天然同步。
    static let flipLineInset: CGFloat = 0.5
    static let flipLineWidth: CGFloat = 0.6
    /// 细线正常亮度 / 落定之后的亮度 —— **不是完全消失**，只是降下来
    static let flipLineOpacity: Double = 1.0
    static let flipLineRestOpacity: Double = 0.55

    /// 晕染光的"宽柔层"：粗细 / 模糊
    static let flipGlowBand: CGFloat = 6
    static let flipGlowBlur: CGFloat = 12
    /// 晕染光的"紧光层"：贴着细线再压一层，翻转那一下的"重"主要来自它
    static let flipGlowCoreBand: CGFloat = 2.5
    static let flipGlowCoreBlur: CGFloat = 2
    /// 细线转动时的那层薄晕（"转的时候也得有点晕染"）
    static let flipGlowDuringSweep: Double = 0.35
    /// 抬起 / 翻转时的峰值 —— 这一段光要**再重一点**
    static let flipGlowPeak: Double = 1.0
    /// 落定之后
    static let flipRestGlow: Double = 0.35
}

// ============================================================================
//  MARK: - 品牌色（资产目录 · 由 Xcode 生成符号）
// ============================================================================
//
//  只有两个颜色是「品牌」而不是「语义」：
//    zwRouge —— VALORANT 红，主行动 / 告警
//    zwSignal —— 青绿，已拥有 / 在线
//
//  ⚠️ **不要在这里再写 `extension Color { static let zwRouge = ... }`**。
//  工程开了 `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS`，
//  Xcode 会照着 `Assets.xcassets/zwRouge.colorset` 自动生成同名符号
//  （`Color` 和 `ShapeStyle` 两份都有），手写一遍就是 invalid redeclaration。
//  第一版就是栽在这儿 —— CI 报了 4 个重复声明。
//
//  想加品牌色：往 Assets.xcassets 里加 colorset，名字即符号名，然后用 `.名字`。
//
//  品质五档（蓝绿紫橙金）**不在这里** —— 它们不是 App 色板，是服务端数据
//  （`Rarity.colorHex`，取自掌瓦 ic_val_goods_quality_1..5），
//  由 `Theme.swift` 的 `Rarity.color` 现算，改不了也不该改。

extension Color {

    /// 从 `#RRGGBB`（也接受不带 `#`）建色。
    ///
    /// 只服务于**数据里的颜色**（现在就是品质五档）——
    /// App 自己的颜色一律走资产目录或系统语义色，不要用这个。
    init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255.0,
                  green: Double((v >> 8) & 0xFF) / 255.0,
                  blue: Double(v & 0xFF) / 255.0,
                  opacity: 1)
    }
}

// ============================================================================
//  MARK: - 形状（自绘）
// ============================================================================

/// 品质钻：旋转 45° 的方框（掌瓦 `ic_val_goods_quality_1..5` 的形状语言）
struct ZWDiamond: Shape {

    /// 内缩比例：0 = 实心菱形，0.34 = 方框
    let inset: CGFloat

    init(inset: CGFloat = 0) {
        self.inset = inset
    }

    nonisolated func path(in rect: CGRect) -> Path {
        // 只读实例属性 + CGRect 自带的值（隔离要求，见文件头）
        let r = min(rect.width, rect.height) / 2 * (1 - inset)
        let cx = rect.midX
        let cy = rect.midY
        var p = Path()
        p.move(to: CGPoint(x: cx, y: cy - r))
        p.addLine(to: CGPoint(x: cx + r, y: cy))
        p.addLine(to: CGPoint(x: cx, y: cy + r))
        p.addLine(to: CGPoint(x: cx - r, y: cy))
        p.closeSubpath()
        return p
    }
}

/// 45° 斜纹：卡背的磨砂纹，以及没有卡面图时的占位
struct ZWHatchTexture: Shape {

    let pitch: CGFloat

    init(pitch: CGFloat = 9) {
        self.pitch = pitch
    }

    nonisolated func path(in rect: CGRect) -> Path {
        var p = Path()
        guard pitch > 0 else { return p }
        // 从左上外侧起步，一路铺到右下，保证覆盖整个矩形
        var x = rect.minX - rect.height
        while x < rect.maxX {
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += pitch
        }
        return p
    }
}

/// 圆角矩形轮廓上的**一段**，按弧长采样成一条连续折线。
///
/// 为什么不用 `Shape.trim`：trim 是按路径的**参数**分段切的，圆角矩形的
/// 直线段和四段圆弧会被切得很碎 —— 表现就是光跑到拐角处像被切块。
/// 这里自己按弧长均匀取点连折线，无论怎么切都是连续的一条。
///
/// **零长度 = 不画**：`from == to` 时返回空路径。否则 stroke 的圆帽会在起点
/// （上边中点）留下一个光点 —— 未翻开的卡顶上那颗就是这么来的。
/// 验算台：probe/ring_probe.swift ⑦。
///
/// 参数化：从**上边中点**起，顺时针一圈（t = 0…1）。
struct ZWRingSweep: Shape {

    var cornerRadius: CGFloat
    var inset: CGFloat
    /// 起点（0…1）
    var from: Double
    /// 终点（0…1），可以 > 1 表示绕过起点
    var to: Double

    init(cornerRadius: CGFloat, inset: CGFloat = 0, from: Double, to: Double) {
        self.cornerRadius = cornerRadius
        self.inset = inset
        self.from = from
        self.to = to
    }

    nonisolated func path(in rect: CGRect) -> Path {
        let a = min(from, to)
        let b = max(from, to)
        let span = b - a

        // 退化（from == to，或者短到不足半点）：**什么都不画**。
        // 起点在上边中点，如果给一条零长度折线，`lineCap: .round` 会在那儿
        // 戳出一个圆帽 —— 没翻开的卡顶上那个光点就是它（不是"光效起点"该露出来的样子）。
        // 阈值按**弧长**算而不是按 span 算：卡越小，同样的 span 越短。
        let perimeter = 2 * (Double(rect.width) + Double(rect.height))
        guard span > 0, span * perimeter >= 0.5 else { return Path() }

        // 采样密度：一整圈 240 段，短片段按比例，最少 6 段
        let count = max(6, Int(240 * min(span, 1)))
        var path = Path()
        for i in 0...count {
            let t = a + span * Double(i) / Double(count)
            let pt = Self.point(at: t, in: rect, cornerRadius: cornerRadius, inset: inset)
            if i == 0 {
                path.move(to: pt)
            } else {
                path.addLine(to: pt)
            }
        }
        return path
    }

    /// 轮廓上 t ∈ [0,1] 处的点。t 可以越界（会自动取小数部分）。
    ///
    /// 顺序（顺时针，起于上边中点）：
    ///   1 上边右半   2 右上弧   3 右边   4 右下弧
    ///   5 下边       6 左下弧   7 左边   8 左上弧   9 上边左半
    nonisolated static func point(at t: Double,
                                  in rect: CGRect,
                                  cornerRadius: CGFloat,
                                  inset: CGFloat = 0) -> CGPoint {
        let r0 = rect.insetBy(dx: inset, dy: inset)
        let radius = max(0, min(cornerRadius, min(r0.width, r0.height) / 2))
        let minX = r0.minX, maxX = r0.maxX
        let minY = r0.minY, maxY = r0.maxY
        let midX = r0.midX

        // 各段长度
        let straightH = max(0, r0.width - 2 * radius)     // 上边、下边
        let straightV = max(0, r0.height - 2 * radius)    // 左边、右边
        let arc = Double.pi * Double(radius) / 2          // 一个四分之一弧
        let halfTop = straightH / 2                       // 起点的左右两半

        let lengths: [CGFloat] = [halfTop, arc, straightV, arc,
                                  straightH, arc, straightV, arc, halfTop]
        let total = lengths.reduce(0, +)
        guard total > 0 else { return CGPoint(x: midX, y: minY) }

        // 归一化 t 到 [0, total)
        var dist = t.truncatingRemainder(dividingBy: 1)
        if dist < 0 { dist += 1 }
        var remain = dist * Double(total)

        func lerp(_ a: CGFloat, _ b: CGFloat, _ f: CGFloat) -> CGFloat { a + (b - a) * f }
        func onArc(_ cx: CGFloat, _ cy: CGFloat, _ start: Double, _ f: Double) -> CGPoint {
            let ang = start + f * (.pi / 2)
            return CGPoint(x: cx + radius * CGFloat(cos(ang)),
                           y: cy + radius * CGFloat(sin(ang)))
        }

        // 1 上边右半
        if remain <= Double(lengths[0]) {
            let f = CGFloat(remain / Double(lengths[0]))
            return CGPoint(x: lerp(midX, maxX - radius, f), y: minY)
        }
        remain -= Double(lengths[0])
        // 2 右上弧 (-90° → 0°)
        if remain <= Double(lengths[1]) {
            let f = remain / Double(lengths[1])
            return onArc(maxX - radius, minY + radius, -.pi / 2, f)
        }
        remain -= Double(lengths[1])
        // 3 右边
        if remain <= Double(lengths[2]) {
            let f = CGFloat(remain / Double(lengths[2]))
            return CGPoint(x: maxX, y: lerp(minY + radius, maxY - radius, f))
        }
        remain -= Double(lengths[2])
        // 4 右下弧 (0° → 90°)
        if remain <= Double(lengths[3]) {
            let f = remain / Double(lengths[3])
            return onArc(maxX - radius, maxY - radius, 0, f)
        }
        remain -= Double(lengths[3])
        // 5 下边（右 → 左）
        if remain <= Double(lengths[4]) {
            let f = CGFloat(remain / Double(lengths[4]))
            return CGPoint(x: lerp(maxX - radius, minX + radius, f), y: maxY)
        }
        remain -= Double(lengths[4])
        // 6 左下弧 (90° → 180°)
        if remain <= Double(lengths[5]) {
            let f = remain / Double(lengths[5])
            return onArc(minX + radius, maxY - radius, .pi / 2, f)
        }
        remain -= Double(lengths[5])
        // 7 左边（下 → 上）
        if remain <= Double(lengths[6]) {
            let f = CGFloat(remain / Double(lengths[6]))
            return CGPoint(x: minX, y: lerp(maxY - radius, minY + radius, f))
        }
        remain -= Double(lengths[6])
        // 8 左上弧 (180° → 270°)
        if remain <= Double(lengths[7]) {
            let f = remain / Double(lengths[7])
            return onArc(minX + radius, minY + radius, .pi, f)
        }
        remain -= Double(lengths[7])
        // 9 上边左半
        let f = CGFloat(remain / Double(lengths[8]))
        return CGPoint(x: lerp(minX + radius, midX, f), y: minY)
    }
}
/// 一颗品质钻：外框或实心
struct ZWGradeMark: View {
    let tint: Color
    var size: CGFloat = 14
    var filled: Bool = false

    var body: some View {
        ZStack {
            if filled {
                ZWDiamond().fill(tint)
            } else {
                ZWDiamond(inset: 0.30).stroke(tint, lineWidth: 2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// ============================================================================
//  MARK: - 内容容器（不透明，不是玻璃）
// ============================================================================

extension View {

    /// 内容块底：系统的分组背景色。
    /// 卡片、板子、身份条都用它 —— 玻璃是控件层的材质，内容层保持不透明。
    func zwContentBackground(_ radius: CGFloat = ZW.radiusGroup) -> some View {
        background(Color(.secondarySystemGroupedBackground),
                   in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// ============================================================================
//  MARK: - 字体（Dynamic Type）
// ============================================================================

extension Font {

    /// 机器腔：拉丁压缩大写。**只用于拉丁小标**（`DAILY STORE` / `VP`）——
    /// 中文没有压缩变体，拿它排中文只会变小不会变窄。
    /// ⚠️ `Font.width(_:)` 是 iOS 16+；万一某版 SDK 上签名变了，只改这一行。
    static func zwMachine(_ style: Font.TextStyle = .caption2) -> Font {
        .system(style).weight(.heavy).width(.compressed)
    }

    /// 数据腔：等宽数字（价格、倒计时、接口路径）
    static func zwMono(_ style: Font.TextStyle = .callout,
                       weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .monospaced).weight(weight)
    }
}

/// 机器腔 / 数据腔 —— 都定义在 **Text** 上。
///
/// `.kerning(_:)` 和 `.monospacedDigit()` 在 SwiftUI 里是 **Text** 的方法
/// （View 级的文本修饰器是 iOS 16 才补的，名字也不完全一样）。
/// 两种腔调永远只落在 Text 上，所以直接用 Text 的方法，少一层版本不确定性。
extension Text {

    /// 机器腔：压缩大写 + 字距（调用方自己 `.uppercased()`）
    func zwMachine(_ style: Font.TextStyle = .caption2,
                   tracking: CGFloat = 1.4) -> Text {
        font(.zwMachine(style)).kerning(tracking)
    }

    /// 数据腔：等宽数字（价格/倒计时滚动时不会左右跳）
    func zwMonoStyle(_ style: Font.TextStyle = .callout,
                     weight: Font.Weight = .semibold) -> Text {
        font(.zwMono(style, weight: weight)).monospacedDigit()
    }
}

extension View {

    /// 只要机器腔的字形、不要字距 —— 给 Button / 容器这类不是 Text 的宿主用
    func zwMachineFont(_ style: Font.TextStyle = .caption2) -> some View {
        font(.zwMachine(style))
    }
}
