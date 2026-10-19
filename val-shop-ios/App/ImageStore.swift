import SwiftUI
import CryptoKit

// ============================================================================
//  皮肤图缓存 —— 内存一级 + 磁盘一级，落盘的是**降采样后的缩略图**
// ============================================================================
//
//  为什么不用 `AsyncImage`
//    它在内部自己建 URLRequest，改不了 `cachePolicy`，于是：
//      · 缓存过期（服务端 `max-age=600`）后每次冷启动都要付一次 304 往返
//      · 飞行模式 / 网络差的时候，图上永远不出来
//
//  为什么落盘的是缩略图
//    真实皮肤图（`game.gtimg.cn/images/val/agamezlk/WeaponSkins/*.png`）实测
//    512×144、RGBA、63 KB；卡面只用 170pt 宽 ≈ 340px @2x，
//    缩到 340 存下来约 20–40 KB，解码几 ms。
//
//  ⚠️ 存 **PNG，不能存 JPEG**
//    皮肤图是带透明通道的 RGBA（颜色类型 6）。JPEG 没有 alpha，转码时透明底
//    会被压成实色 —— 表现就是武器后面一块白框。第一版就是这么踩的，
//    所以缓存目录名从 `zwimg` 换成了 `zwimg-png-v1`，把旧的白框缩略图整批作废。
//
//  为什么 `.returnCacheDataElseLoad`
//    同一 URL 对应的图内容永不变化，"新鲜度"对它没意义。
//    这条策略 = 有就用、不问服务器，把那次 304 也省掉。
//    我们自己的磁盘目录是主保障，URLCache 只是兜底 —— 顺序不能反。
// ============================================================================

/// UIImage 只读，跨隔离传递是安全的；但 UIKit 没给它标 `Sendable`，
/// 这里显式承担这个责任（全项目仅此一处）。
///
/// ⚠️ 整个类型必须标 `nonisolated`：本项目开了 `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`，
/// 不标就会被推成 MainActor 隔离，`ImageStore` 里那个非 MainActor 的 Task 根本构造不了它
/// （CI 报的就是 `main actor-isolated initializer 'init(_:)' cannot be called from outside of the actor`）。
///
/// 用 `final class` 是为了能放进 `NSCache`（它的 value 必须 `AnyObject`）。
nonisolated final class SendableImage: @unchecked Sendable {
    let image: UIImage
    init(_ image: UIImage) { self.image = image }
}

actor ImageStore {

    static let shared = ImageStore()

    // MARK: 配置

    /// 卡面 170pt × 2x。再大就是白解码
    private let thumbSide: CGFloat = 340
    /// 磁盘上限。1B 之后单张约 40 KB，这个额度基本不会触发
    private let diskBudget: Int64 = 200 << 20        // 200 MB

    // MARK: 状态

    private let memory = NSCache<NSURL, SendableImage>()
    private var inFlight: [URL: Task<SendableImage?, Never>] = [:]
    private let dir: URL

    init() {
        // 目录名带版本：上一版存的是 JPEG（把透明底压成了白框），必须整批作废
    dir = URL.cachesDirectory.appending(path: "zwimg-png-v1")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        memory.countLimit = 60          // 一期 4 张，留够来回切的余量
        // 清磁盘放到后台，别挡启动
        Task { await self.pruneIfNeeded() }
    }

    // MARK: 取图

    func image(for url: URL?) async -> SendableImage? {
        guard let url else { return nil }

        // ① 内存
        if let hit = memory.object(forKey: url as NSURL) { return hit }

        // ② 同一张正在下 —— 挂到同一个 task 上，不下第二遍
        if let running = inFlight[url] { return await running.value }

        let dir = self.dir
        let side = self.thumbSide
        let file = dir.appending(path: Self.fileName(url))

        let task = Task<SendableImage?, Never> {
            // ③ 磁盘（已经是缩略图）
            if let data = try? Data(contentsOf: file),
               let cached = UIImage(data: data) {
                return SendableImage(cached)
            }

            // ④ 网络：有缓存就直接用，不校验新鲜度
            var req = URLRequest(url: url)
            req.cachePolicy = .returnCacheDataElseLoad
            req.timeoutInterval = 20
            guard let (data, response) = try? await URLSession.shared.data(for: req),
                  ((response as? HTTPURLResponse)?.statusCode ?? 0) == 200,
                  let full = UIImage(data: data) else {
                return nil          // 失败不落盘，下次还会重试
            }

            // ⑤ 降采样再存 —— 这一步是 1B 的全部价值
            let thumb = try? await full.byPreparingThumbnail(
                ofSize: CGSize(width: side, height: side))
            let small = thumb ?? full
            // ⚠️ 必须存 PNG，不能存 JPEG：皮肤图（512×144）是**带透明通道**的 RGBA，
            //    JPEG 没有 alpha，转码时透明底会被压成实色 —— 表现就是武器后面一块白框。
            //    340px 的 PNG 也就 20–40 KB，和 JPEG 差不了多少，没必要省这点。
            if let png = small.pngData() {
                try? png.write(to: file, options: .atomic)
            }
            return SendableImage(small)
        }

        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        if let result { memory.setObject(result, forKey: url as NSURL) }
        return result
    }

    // MARK: 工具

    /// 文件名 = URL 的 SHA256 前 16 位。
    /// 不能直接用 URL 当文件名：里面带 `//`、`?` 和中文。
    /// `nonisolated` 是必须的 —— 本项目默认隔离是 MainActor，
    /// 不标的话从 Task 里调不到（同 Shape.path(in:) 的坑）。
    private nonisolated static func fileName(_ url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined() + ".png"
    }

    /// 超过预算就按修改时间删最旧的
    private func pruneIfNeeded() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return }

        var entries: [(url: URL, date: Date, size: Int64)] = []
        var total: Int64 = 0
        for f in files {
            let v = try? f.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let size = Int64(v?.fileSize ?? 0)
            entries.append((f, v?.contentModificationDate ?? .distantPast, size))
            total += size
        }
        guard total > diskBudget else { return }

        let target = diskBudget * 8 / 10          // 一次删到 80%
        for e in entries.sorted(by: { $0.date < $1.date }) {
            guard total > target else { break }
            try? fm.removeItem(at: e.url)
            total -= e.size
        }
    }
}
