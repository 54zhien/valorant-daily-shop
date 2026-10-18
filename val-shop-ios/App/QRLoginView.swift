import SwiftUI
import ZhangwaKit

// ============================================================================
//  扫码登录界面
// ============================================================================
//
//  这是给普通人用的入口：打开 → 出二维码 → 微信扫一下 → 完事。
//
//  没有电脑、没有 frida、没有模拟器、没有粘贴 Cookie。
//  而且每次登录都会拿到一份全新的 ct + wt，
//  之后交给现有的 ct 滚动续期机制养着，扫一次就够长期用了。
//
//  二维码是**微信官方服务器**为掌瓦的官方 AppID 生成的（不是伪造的），
//  授权码也是微信下发的 —— 这是正经的官方登录渠道。
// ============================================================================

struct QRLoginView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var login = QRLogin()
    @State private var stage: QRLogin.Stage = .idle
    @State private var image: QRLogin.QRImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    qrCard
                    statusRow
                    if !login.log.isEmpty { logCard }
                    hintCard
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background(ZWBrandBackdrop())
            .navigationTitle("扫码登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        login.cancel()
                        dismiss()
                    }
                }
            }
        }
        .onAppear { wire() }
        .onDisappear { login.cancel() }
    }

    // MARK: 二维码

    private var qrCard: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white)
                    .frame(width: 236, height: 236)

                if let data = image?.data, let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .interpolation(.none)      // 二维码放大不能糊
                        .resizable()
                        .scaledToFit()
                        .frame(width: 212, height: 212)
                        .transition(.opacity)
                } else {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            // 二维码外面套一层玻璃，和整体风格对齐
            .glassEffect(.regular.tint(.white.opacity(0.25)), in: .rect(cornerRadius: 24))
            .overlay {
                if stage == .expired {
                    expiredOverlay
                }
            }
            .onTapGesture {
                guard stage == .expired || stage.isTerminal else { return }
                restart()
            }

            Text("请使用「微信」扫一扫")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var expiredOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.black.opacity(0.55))
                .frame(width: 236, height: 236)
            VStack(spacing: 8) {
                Image(systemName: "arrow.clockwise")
                    .font(.title)
                Text("已过期\n点一下换一张")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
        }
    }

    // MARK: 状态

    private var statusRow: some View {
        HStack(spacing: 10) {
            if stage.isBusy {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: iconForStage)
                    .foregroundStyle(colorForStage)
            }
            Text(stage.text)
                .font(.callout)
                .foregroundStyle(colorForStage)
            Spacer()
            if stage.isTerminal || stage == .expired {
                Button("重来") { restart() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var iconForStage: String {
        switch stage {
        case .success:   return "checkmark.circle.fill"
        case .scanned:   return "iphone.gen3.badge.checkmark"
        case .cancelled: return "xmark.circle"
        case .failed:    return "exclamationmark.triangle.fill"
        case .expired:   return "clock.badge.exclamationmark"
        default:         return "qrcode"
        }
    }

    private var colorForStage: Color {
        switch stage {
        case .success:   return .green
        case .failed:    return .orange
        case .scanned:   return .zwAccent
        default:         return .secondary
        }
    }

    // MARK: 日志

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("过程")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(login.log.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    // MARK: 说明

    private var hintCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("这是官方登录渠道", systemImage: "checkmark.seal")
                .font(.caption.weight(.semibold))
            Text("二维码由微信官方服务器为「掌上无畏契约」的官方 AppID 生成，"
                 + "授权由你在微信里确认。登录成功后拿到的是和官方客户端一样的凭证。\n\n"
                 + "扫一次就够了 —— 之后会自动续期，不用再扫。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.zwAccent.opacity(0.12)), in: .rect(cornerRadius: 16))
    }

    // MARK: 逻辑

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
