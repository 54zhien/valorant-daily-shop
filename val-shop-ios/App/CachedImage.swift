import SwiftUI

/// 替代 `AsyncImage`：**先看本地，本地没有再联网**。
///
/// 和 `AsyncImage` 的区别就三点：
///   1. 缓存是我们自己的（内存 + 磁盘缩略图），不受服务端 `max-age` 影响
///   2. 命中时**零网络**，飞行模式也能出图
///   3. 加载中可以给占位（卡面用品质钻，头像不用）
///
/// 用法：
/// ```swift
/// CachedImage(url: item.iconURL) { ZWDiamond().stroke(...) }   // 有占位
/// CachedImage(url: url, contentMode: .fill)                    // 无占位
/// ```
struct CachedImage<Placeholder: View>: View {

    let url: URL?
    var contentMode: ContentMode
    @ViewBuilder var placeholder: Placeholder

    @State private var loaded: SendableImage?

    var body: some View {
        ZStack {
            if let loaded {
                Image(uiImage: loaded.image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
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
}

extension CachedImage where Placeholder == EmptyView {

    init(url: URL?, contentMode: ContentMode = .fit) {
        self.init(url: url, contentMode: contentMode, placeholder: { EmptyView() })
    }
}
