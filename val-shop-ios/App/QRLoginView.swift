import SwiftUI
import ZhangwaKit

// ============================================================================
//  微信扫码登录
// ============================================================================
//
//  给普通人用的入口：打开 → 出二维码 → 微信扫一下 → 完事。
//
//  没有电脑、没有 frida、没有模拟器、没有粘贴 Cookie。
//  每次登录都会拿到一份全新的 ct + wt，之后交给 ct 滚动续期机制养着，
//  扫一次就够长期用了。
//
//  二维码是**微信官方服务器**为掌瓦的官方 AppID 生成的（不是伪造的），
//  授权码也是微信下发的 —— 这是正经的官方登录渠道。
//
//  版式：NavigationStack + List（系统分组），二维码那格居中放。
// ============================================================================

struct QRLoginView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var login = QRLogin()
    @State private var stage: QRLogin.Stage = .idle
    /// 裁掉四周白边之后的二维码位图（微信返回的 JPEG 自带约 12% 白边）
    @State private var qrImage: UIImage?

    var body: some View {
        NavigationStack {
            // 只有一张码：和 QQ 那边同一套版式（medium sheet + 居中白卡 + 无任何提示条）
            VStack {
                Spacer(minLength: 0)
                qrBlock
                Spacer(minLength: 0)
            }
            .navigationTitle("微信扫码登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        login.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        restart()
                    } label: {
                        Label("换一张码", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { wire() }
        .onDisappear { login.cancel() }
    }

    // MARK: - 二维码

    private var qrBlock: some View {
        ZStack {
                // 白底圆角，投影把它从列表底上托起来
                RoundedRectangle(cornerRadius: ZW.radiusCard, style: .continuous)
                    .fill(.white)
                    .frame(width: ZW.qrCardSide, height: ZW.qrCardSide)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 6)

                if let ui = qrImage {
                    Image(uiImage: ui)
                        .interpolation(.none)      // 二维码放大不能糊
                        .resizable()
                        .scaledToFit()
                        .frame(width: ZW.qrCardSide - ZW.qrMargin * 2, height: ZW.qrCardSide - ZW.qrMargin * 2)
                        .transition(.opacity)
                } else {
                    ProgressView()
                        .controlSize(.large)
                }

                if stage == .expired || stage.isTerminal {
                    expiredOverlay
                }
            }
            .onTapGesture {
                guard stage == .expired || stage.isTerminal else { return }
                restart()
            }
    }

    private var expiredOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ZW.radiusCard, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: ZW.qrCardSide, height: ZW.qrCardSide)
            VStack(spacing: 8) {
                Image(systemName: "arrow.clockwise")
                    .font(.title2)
                Text(stage.isTerminal ? "点一下重新开始" : "已过期\n点一下换一张")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.primary)
        }
    }


    // MARK: - 逻辑

    private func wire() {
        login.onStageChange = { s in
            withAnimation(.snappy) { stage = s }
        }
        // 码一到就显示。以前是「每 50ms 轮询 login.image，最多 100 次」——
        // 等于给取码设了 5 秒上限：网慢一点（或者重试了一次）码就算回来了也不显示，
        // 用户看到的就是一直转圈。这是这次"加载很久"的主因之一。
        login.onImage = { qr in
            let ui = UIImage(data: qr.data)?.zwTrimmingWhiteBorder()
            withAnimation(.snappy) { qrImage = ui }
        }
        login.onSession = { session in
            model.adopt(session)
            // 停一下让用户看到"成功"，再自动关掉
            Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                dismiss()
            }
        }
        restart()
    }

    private func restart() {
        // 不先清空：新码回来之前先留着旧的那张，避免闪一下白
        login.start()
    }
}
// ============================================================================
//  MARK: - 二维码裁边
// ============================================================================

extension UIImage {

    /// 把二维码四周的白边裁掉。
    ///
    /// 微信下发的 JPEG 自带一圈白边（实测：176pt 的框里，可见码块只有约 154pt，
    /// 也就是 12% 的纯白），而 QQ 那边是网页直接渲染的码、几乎没有这层白边。
    /// 不裁的话两个登录页的码看起来一大一小 —— 裁完两边可见尺寸就一致了。
    func zwTrimmingWhiteBorder(threshold: UInt8 = 160) -> UIImage {
        guard let cg = cgImage else { return self }
        let w = cg.width, h = cg.height
        guard w > 16, h > 16 else { return self }

        var pixels = [UInt8](repeating: 255, count: w * h)
        let drew = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress,
                                      width: w, height: h,
                                      bitsPerComponent: 8,
                                      bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drew else { return self }

        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h {
            let row = y * w
            for x in 0..<w where pixels[row + x] < threshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX > minX, maxY > minY else { return self }

        // CGContext 是左下原点，CGImage.cropping 是左上原点 —— 这里换一下坐标系
        let top = h - 1 - maxY
        let bottom = h - 1 - minY
        // 留一个码点左右余量，别把定位角裁贴边（扫描器需要一点静区）
        let padX = max(2, (maxX - minX) / 48)
        let padY = max(2, (bottom - top) / 48)
        // 拆成几步算：一行里塞太多 CGFloat/Int 混算，Swift 的类型检查会超时
        let left = max(0, minX - padX)
        let topEdge = max(0, top - padY)
        let right = min(w - 1, maxX + padX)
        let bottomEdge = min(h - 1, bottom + padY)
        let rect = CGRect(x: CGFloat(left),
                          y: CGFloat(topEdge),
                          width: CGFloat(right - left + 1),
                          height: CGFloat(bottomEdge - topEdge + 1))
        guard let cropped = cg.cropping(to: rect) else { return self }
        return UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
    }
}