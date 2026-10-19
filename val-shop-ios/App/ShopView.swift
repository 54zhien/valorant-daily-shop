import SwiftUI
import ZhangwaKit

/// 商店主界面。
///
/// Liquid Glass 用法：
///   · 卡片 → `zwGlassCard(tint:)`，品质色做染色
///   · 按钮 → `.buttonStyle(.glass / .glassProminent)`
///   · 卡片组放在 `ZWGlassGroup` 里，翻开时玻璃会互相 morph
///   · 整页 `.scrollEdgeEffectStyle(.soft, for: .all)`
struct ShopView: View {
    @Environment(AppModel.self) private var model

    @State private var showSession = false
    @State private var showRolePicker = false
    @Namespace private var glassNamespace

    private let columns = [GridItem(.adaptive(minimum: 158), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    actionBar
                    countdown
                    content
                    logPanel
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .zwScrollEdge(.all)
            .background(ZWBrandBackdrop())
            .navigationTitle("每日商店")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarSpacer(.flexible)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSession = true
                    } label: {
                        Label("会话", systemImage: "person.crop.circle")
                    }
                }
            }
            // 进页面拉一次角色信息（登录成功后也会由 AppModel 触发）
            .task { await model.loadUserRole() }
            .sheet(isPresented: $showSession) {
                SettingsView(isSheet: true)
            }
        }
    }

    /// 头像：有卡面 URL 就异步加载，没有就显示游戏 ID 首字。
    ///
    /// 用 AsyncImage 而不是自己缓存 —— 这是首页一张小图，
    /// SwiftUI 自带的够用，不值得为它引入缓存层。
    private var avatar: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.12))
            if let icon = model.userRole?.icon, let url = URL(string: icon),
               !icon.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        fallbackInitial
                    }
                }
            } else {
                fallbackInitial
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(.circle)
        .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 0.5))
    }

    private var fallbackInitial: some View {
        Text(String(model.displayName.prefix(1)))
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
    }

    // MARK: - 头部

    private var header: some View {
        // 有多个角色时整块可点，点开切换。
        // sheet 挂在 header 上而不是 NavigationStack 上 ——
        // 同一个视图挂两个 sheet 在 iOS 上不稳（已经踩过一次）。
        Button {
            if model.canSwitchRole { showRolePicker = true }
        } label: {
            headerContent
        }
        .buttonStyle(.plain)
        .disabled(!model.canSwitchRole)
        .sheet(isPresented: ) {
            RolePickerView().environment(model)
        }
    }

    private var headerContent: some View {
        HStack(alignment: .center, spacing: 12) {
            // 头像（有卡面就显示卡面，没有就显示首字）
            avatar

            VStack(alignment: .leading, spacing: 3) {
                // ★ 游戏 ID，形如「天天开心#26170」
                HStack(spacing: 4) {
                    Text(model.displayName)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if model.canSwitchRole {
                        Image(systemName: chevron.up.chevron.down)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(model.displaySubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(model.hasSession ? "已连接" : "未连接")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .zwGlassChip(tint: model.hasSession ? .zwMint : .zwAccent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .zwGlassPanel()
    }

    // MARK: - 按钮组（靠近会融合成一块玻璃）

    private var actionBar: some View {
        ZWGlassGroup(spacing: 14) {
            HStack(spacing: 12) {
                Button {
                    Task { await model.loadStore() }
                } label: {
                    Label(model.state.isLoading ? "读取中…" : "读取今日商店",
                          systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .zwProminentButton(tint: .zwAccent)
                .disabled(model.state.isLoading)

                Button {
                    flipAll()
                } label: {
                    Label("翻开", systemImage: "rectangle.on.rectangle.angled")
                }
                .zwGlassButton()
                .zwMorphID("flipAll", in: glassNamespace)
            }
            .controlSize(.large)

            HStack(spacing: 12) {
                Button("演示数据") { model.loadDemo() }
                    .zwGlassButton()
                Button("探测接口") { Task { await model.probe() } }
                    .zwGlassButton()
                Button("刷新票据") { Task { await model.refreshTickets() } }
                    .zwGlassButton()
            }
            .controlSize(.regular)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 倒计时

    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let secs = remainingSeconds(now: context.date)
            HStack(spacing: 12) {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                Text("距刷新")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(format(secs))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText(countsDown: true))
                ProgressView(value: progress(secs))
                    .tint(.zwMint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .zwGlassPanel(cornerRadius: 18)
        }
    }

    private func remainingSeconds(now: Date) -> TimeInterval {
        if let expires = model.snapshot.expiresAt {
            return max(0, expires.timeIntervalSince(now))
        }
        // 接口没给过期时间时按本地 08:00 估算
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = 8
        comps.minute = 0
        comps.second = 0
        guard let today8 = cal.date(from: comps) else { return 0 }
        return today8 > now
            ? today8.timeIntervalSince(now)
            : today8.addingTimeInterval(86_400).timeIntervalSince(now)
    }

    private func progress(_ secs: TimeInterval) -> Double {
        min(1, max(0, 1 - secs / 86_400))
    }

    private func format(_ secs: TimeInterval) -> String {
        let s = Int(secs)
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    // MARK: - 卡片

    @ViewBuilder
    private var content: some View {
        if model.snapshot.items.isEmpty {
            ContentUnavailableView {
                Label("还没有数据", systemImage: "tray")
            } description: {
                Text("到「设置」里导入 Cookie 或抓包文件，再点「读取今日商店」。\n想先看效果就点「演示数据」。")
            }
            .padding(.vertical, 28)
            .zwGlassPanel()
        } else {
            ZWGlassGroup(spacing: 16) {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Array(model.snapshot.items.prefix(4).enumerated()), id: \.offset) { index, item in
                        StoreCardView(
                            item: item,
                            isFlipped: flipped(at: index),
                            namespace: glassNamespace,
                            morphID: "card-\(index)"
                        ) {
                            toggleFlip(index)
                        }
                    }
                }
            }
        }
    }

    private func flipped(at index: Int) -> Bool {
        index < model.flipped.count ? model.flipped[index] : false
    }

    private func toggleFlip(_ index: Int) {
        guard index < model.flipped.count else { return }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
            model.flipped[index].toggle()
        }
    }

    private func flipAll() {
        for i in 0..<model.flipped.count {
            Task {
                try? await Task.sleep(for: .milliseconds(i * 130))
                withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
                    if i < model.flipped.count { model.flipped[i] = true }
                }
            }
        }
    }

    // MARK: - 日志

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("运行日志", systemImage: "text.alignleft")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if model.log.isEmpty {
                Text("—").font(.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(Array(model.log.prefix(12).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .zwGlassPanel()
    }
}
