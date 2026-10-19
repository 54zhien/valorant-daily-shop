import SwiftUI

/// 替代 `AsyncImage`：**先看本地，本地没有再联网**。
///
/// 和 `AsyncImage` 的区别就三点：
///   1. 缓存是我们自己的（内存 + 磁盘缩略图），不受服务端 `max-age` 影响
///   2. 命中时**零网络**，飞行模式也能出图
///   3. 加载中可以给占位（卡面用品质钻，头像不用）
///
/// 卡面还要第四件事：**视觉尺寸归一**（`artNormalize`）。
/// 皮肤图的画布尺寸不统一（实测 512×116 / 512×144 / 512×196，内容宽高比 2.5–3.8），
/// 直接 `scaledToFit` 的话，越"方"的图（短枪、近战）高度越顶格，看着比长枪大一圈。
///
/// 用法：
/// ```swift
/// CachedImage(url: item.iconURL, artNormalize: true) { ZWDiamond()… }  // 卡面
/// CachedImage(url: url, contentMode: .fill)                            // 头像
/// ```
struct CachedImage<Placeholder: View>: View {

    let url: URL?
    var contentMode: ContentMode
    /// 卡面专用：按「视觉面积相同 + 高度封顶」排版
    var artNormalize: Bool
    @ViewBuilder var placeholder: Placeholder

    @State private var loaded: SendableImage?

    var body: some View {
        ZStack {
            if let loaded {
                content(loaded.image)
                    .transition(.opacity)
            } else {
                placeholder
            }
        }
        // id: url —— 换商品/换角色时重取，不会串图
        .task(id: url) {
            loaded = await ImageStore.shared.image(for: url)
        }
    }

    @ViewBuilder
    private func content(_ ui: UIImage) -> some View {
        if artNormalize {
            GeometryReader { geo in
                let size = Self.normalizedSize(ui.size, in: geo.size)
                Image(uiImage: ui)
                    .resizable()
                    .frame(width: size.width, height: size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)     // 居中
            }
        } else {
            Image(uiImage: ui)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        }
    }

    /// 视觉尺寸归一 —— 让四张卡的武器看着**一样大**。
    ///
    /// 三步：
    ///   1. **面积归一**：每张图占 art 区固定比例的面积（`areaFraction`）。
    ///      长枪很宽很扁、短枪近战偏方，但面积一样，视觉重量就对上了。
    ///   2. 面积算出来的宽度要是超出卡片 → 按卡片宽度回退（长枪天然吃满宽度）。
    ///   3. **高度封顶**：短枪、近战的图不许比长枪高一大截（`heightCap`）。
    ///
    /// 实测（art 区 153×120pt，areaFraction 0.32，heightCap 0.62）：
    ///   宽高比 3.8 的长枪 → 145×38
    ///   宽高比 2.5        → 121×48
    ///   宽高比 1.4 的手枪 → 91×65
    ///   宽高比 1.0 的近战 → 74×74          四张面积基本一致
    static func normalizedSize(_ intrinsic: CGSize, in box: CGSize) -> CGSize {
        guard intrinsic.width > 0, intrinsic.height > 0,
              box.width > 0, box.height > 0 else { return box }

        let aspect = intrinsic.width / intrinsic.height      // 宽 / 高

        // ① 面积归一
        let area = box.width * box.height * ZW.artAreaFraction
        var height = (area / aspect).squareRoot()
        var width = height * aspect

        // ② 太宽就按宽度回退
        if width > box.width {
            width = box.width
            height = width / aspect
        }

        // ③ 太高就按高度封顶
        let cap = box.height * ZW.artHeightCap
        if height > cap {
            height = cap
            width = height * aspect
        }

        return CGSize(width: width, height: height)
    }
}

extension CachedImage where Placeholder == EmptyView {

    init(url: URL?, contentMode: ContentMode = .fit) {
        self.init(url: url, contentMode: contentMode, artNormalize: false,
                  placeholder: { EmptyView() })
    }
}
