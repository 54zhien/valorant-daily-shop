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
//  落盘时要不要降采样
//    实测皮肤图（`game.gtimg.cn/images/val/agamezlk/WeaponSkins/*.png`）本身就是
//    512×144、RGBA、63 KB。而卡面画心最宽约 153pt，@3x 需要 459px ——
//    512 的原图刚好够、再缩就糊。所以**只有最长边超过 1024 才降采样**。
//    （第一版一律缩到 340px，等于把 512 缩到 340 再放大回 459，边缘就发虚了。）
//
//  ⚠️ 存 **PNG，不能存 JPEG**
//    皮肤图是带透明通道的 RGBA（颜色类型 6）。JPEG 没有 alpha，转码时透明底
//    会被压成实色 —— 表现就是武器后面一块白框。
//
//  磁盘目录的版本号
//    `zwimg`        → 第一版，存的是 JPEG（白框）
//    `zwimg-png-v1` → 改成 PNG，但一律缩到 340px（3x 屏上边缘发虚）
//    `zwimg-v2`     → 现在这版：512 的原图直接用，只有大图才降采样
//    每次换编码方式都必须换目录名，否则旧文件会继续被读到。
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

    /// 最长边超过这个才降采样。皮肤图是 512×144，刚好够 3x 屏（卡面 153pt ≈ 459px）
    private let maxStoredSide: CGFloat = 1024
    /// 磁盘上限。1B 之后单张约 40 KB，这个额度基本不会触发
    private let diskBudget: Int64 = 200 << 20        // 200 MB

    // MARK: 状态

    private let memory = NSCache<NSURL, SendableImage>()
    private var inFlight: [URL: Task<SendableImage?, Never>] = [:]
    private let dir: URL

    init() {
        // 目录名带版本：上一版存的是 JPEG（把透明底压成了白框），必须整批作废
    dir = URL.cachesDirectory.appending(path: "zwimg-v2")
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
        let maxSide = self.maxStoredSide
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

            // ⑤ 只有真·大图才降采样：皮肤图 512×144 保持原样（缩了反而糊）
            let longest = max(full.size.width, full.size.height) * full.scale
            var stored = full
            if longest > maxSide {
                stored = (try? await full.byPreparingThumbnail(
                    ofSize: CGSize(width: maxSide, height: maxSide))) ?? full
            }

            // ⚠️ 必须存 PNG，不能存 JPEG：皮肤图是**带透明通道**的 RGBA，
            //    JPEG 没有 alpha，转码时透明底会被压成实色 —— 武器后面一块白框。
            if let png = stored.pngData() {
                try? png.write(to: file, options: .atomic)
            }
            return SendableImage(stored)
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
