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
            List {
                Section {
                    qrBlock
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }

                Section {
                    statusRow
                }

                if !login.log.isEmpty {
                    Section("过程") {
                        ForEach(Array(login.log.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                Section {
                    Text("二维码由微信官方服务器为「掌上无畏契约」的官方 AppID 生成，"
                         + "授权由你在微信里确认。登录成功后拿到的是和官方客户端一样的凭证。")
                } header: {
                    Label("这是官方登录渠道", systemImage: "checkmark.seal")
                } footer: {
                    Text("扫一次就够了 —— 之后会自动续期，不用再扫。")
                }
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
        .onAppear { wire() }
        .onDisappear { login.cancel() }
    }

    // MARK: - 二维码

    private var qrBlock: some View {
        VStack(spacing: 14) {
            ZStack {
                // 白底圆角，投影把它从列表底上托起来
                RoundedRectangle(cornerRadius: ZW.radiusCard, style: .continuous)
                    .fill(.white)
                    .frame(width: Self.qrSide, height: Self.qrSide)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 6)

                if let data = image?.data, let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .interpolation(.none)      // 二维码放大不能糊
                        .resizable()
                        .scaledToFit()
                        .frame(width: Self.qrSide - 24, height: Self.qrSide - 24)
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

            Text("请使用「微信」扫一扫")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private static let qrSide: CGFloat = 224

    private var expiredOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ZW.radiusCard, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: Self.qrSide, height: Self.qrSide)
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

    // MARK: - 状态

    private var statusRow: some View {
        HStack(spacing: 10) {
            if stage.isBusy {
                ProgressView().controlSize(.small)
            } else {
                ZWDiamond()
                    .fill(colorForStage)
                    .frame(width: 8, height: 8)
            }
            Text(stage.text)
                .font(.subheadline)
            Spacer(minLength: 0)
            if stage.isTerminal || stage == .expired {
                Button("重来") { restart() }
                    .buttonStyle(.borderless)
                    .font(.footnote)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var colorForStage: Color {
        switch stage {
        case .success:   return .zwSignal
        case .failed:    return .red
        case .scanned:   return .zwRouge
        case .cancelled: return .secondary
        default:         return .secondary
        }
    }

    // MARK: - 逻辑

    private func wire() {
        login.onStageChange = { s in
            withAnimation(.snappy) { stage = s }
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
        image = nil
        login.start()
        // 二维码是异步回来的，轮询一下 image
        Task {
            for _ in 0..<100 {
                if let img = login.image { withAnimation(.snappy) { image = img }; return }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }
}
