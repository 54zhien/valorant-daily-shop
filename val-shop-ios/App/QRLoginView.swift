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
    @State private var image: QRLogin.QRImage?

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

                if let data = image?.data, let ui = UIImage(data: data) {
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
            withAnimation(.snappy) { image = qr }
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
