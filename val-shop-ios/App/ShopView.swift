import SwiftUI
import ZhangwaKit

/// 商店主界面 —— 普通人**唯一**需要懂的页面。
///
/// 版式按系统分组内容的做法：
///   NavigationStack（顶部导航栏，inline 标题）
///     ScrollView
///       身份卡（内容卡）
///       出错时一条提示
///       今日四张：小标 + 引信条 + 2×2 卡阵 + 统计行
///     safeAreaInset(.bottom)：主按钮（控件层，系统 glassProminent）
///
/// 材质：**玻璃留给控件层**（导航栏、页签栏、那颗按钮 —— 系统自己就是玻璃），
/// 内容层一律用系统分组背景色，不透明。
struct ShopView: View {

    @Environment(AppModel.self) private var model

    @State private var showRolePicker = false

    private let columns = [
        GridItem(.flexible(), spacing: ZW.gap),
        GridItem(.flexible(), spacing: ZW.gap),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: ZW.gap) {
                    identityCard
                    if let alert = alertInfo {
                        alertRow(alert)
                    }
                    if model.snapshot.items.isEmpty {
                        emptyCard
                    } else {
                        lineUp
                    }
                }
                .padding(.horizontal, ZW.pad)
                .padding(.vertical, ZW.gap)
                .frame(maxWidth: ZW.boardMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .zwScrollEdge(.all)
            .navigationTitle("每日商店")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { actionBar }
            .sheet(isPresented: $showRolePicker) {
                RolePickerView().environment(model)
            }
            // 进页面拉一次角色信息（登录成功后也会由 AppModel 触发）
            .task { await model.loadUserRole() }
        }
    }

    // MARK: - 身份卡

    private var identityCard: some View {
        HStack(spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(model.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if model.canSwitchRole {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(model.displaySubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            statusChip
        }
        .padding(14)
        .zwContentBackground(ZW.radiusGroup)
        // 多角色时才可点 —— 一个人一个号的时候不该有入口
        .contentShape(Rectangle())
        .onTapGesture {
            if model.canSwitchRole { showRolePicker = true }
        }
        .accessibilityElement(children: .contain)
    }

    private var avatar: some View {
        ZStack {
            Color(.tertiarySystemFill)
            if let icon = model.userRole?.icon, !icon.isEmpty, let url = URL(string: icon) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        fallbackInitial
                    }
                }
            } else {
                fallbackInitial
            }
        }
        .frame(width: ZW.avatar, height: ZW.avatar)
        .clipShape(RoundedRectangle(cornerRadius: ZW.radiusControl, style: .continuous))
    }

    private var fallbackInitial: some View {
        Text(String(model.displayName.prefix(1)))
            .font(.subheadline.weight(.bold))
            .foregroundStyle(model.hasSession ? Color.primary : Color.secondary)
    }

    /// 状态只说人话：能用 / 该重新登录
    private var statusChip: some View {
        HStack(spacing: 6) {
            ZWDiamond()
                .fill(model.sessionHealth.tint)
                .frame(width: 7, height: 7)
            Text(model.sessionHealth.text)
                .font(.caption)
                .foregroundStyle(model.sessionHealth.tint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.sessionHealth.text)
    }

    // MARK: - 只在出事时出现的提示

    private var alertInfo: (text: String, ok: Bool)? {
        if case .failed(let msg) = model.state {
            return ("没读到商店：\(msg)。点下面按钮再试一次。", false)
        }
        if !model.hasSession {
            return ("还没登录 —— 登录一下就能看今天的商店。", false)
        }
        if model.sessionHealth == .needsRelogin || model.sessionHealth == .expiring {
            return ("登录状态快到期了，建议到「我的」重新扫一下码。", false)
        }
        return nil
    }

    private func alertRow(_ info: (text: String, ok: Bool)) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: info.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(info.ok ? Color.zwSignal : Color.red)
            Text(info.text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((info.ok ? Color.zwSignal : Color.red).opacity(0.15),
                    in: RoundedRectangle(cornerRadius: ZW.radiusGroup, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - 今日四张

    private var lineUp: some View {
        VStack(spacing: 0) {
            lineUpHeader
            fuse
                .padding(.bottom, 12)

            LazyVGrid(columns: columns, spacing: ZW.gap) {
                ForEach(Array(model.snapshot.items.prefix(4).enumerated()), id: \.offset) { index, item in
                    StoreCardView(item: item,
                                  slot: index + 1,
                                  isFlipped: flipped(at: index)) {
                        toggleFlip(index)
                    }
                }
            }

            lineUpFooter
        }
    }

    private var lineUpHeader: some View {
        HStack(spacing: 10) {
            Text("Daily Store".uppercased())
                .zwMachine(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            countdown

            Button {
                flipAll()
            } label: {
                Text("翻开全部")
                    .font(.footnote)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .disabled(model.flipped.allSatisfy { $0 })
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 8)
    }

    /// 倒计时走自己的一秒一拍 —— 只重绘这一小块
    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let secs = remainingSeconds(now: context.date)
            Text(clock(secs))
                .zwMonoStyle(.caption)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText(countsDown: true))
                .accessibilityLabel("距刷新 \(clock(secs))")
        }
    }

    /// 引信条：时间即几何 —— 轨道烧到哪里，今天就过去多少。
    /// 兼顾无障碍：值报成百分比（自定义控件要报值，见 HIG Accessibility）。
    private var fuse: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let secs = remainingSeconds(now: context.date)
            let ratio = progress(secs)
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.quaternaryLabel))
                        .frame(height: 2)

                    Capsule()
                        .fill(Color.zwRouge)
                        .frame(width: max(0, w * ratio), height: 2)
                }
                .frame(height: 4, alignment: .center)
            }
            .frame(height: 4)
            .accessibilityElement()
            .accessibilityLabel("今天的进度")
            .accessibilityValue("\(Int(ratio * 100))%")
        }
    }

    private var lineUpFooter: some View {
        HStack(spacing: 8) {
            Text("Line-up · \(model.snapshot.items.count)".uppercased())
                .zwMachine(.caption2)
            Text(model.snapshot.gradeSummary)

            Spacer(minLength: 4)

            Text("合计")
            Text(ShopItem.spaced(model.snapshot.totalPrice))
                .zwMonoStyle(.caption)
            Text("VP")
                .zwMachine(.caption2)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .padding(.horizontal, 4)
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 空态

    /// 空的时候只给一步：登录，或者再读一次
    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: model.hasSession ? "tray" : "qrcode")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(model.hasSession ? "今天还没读到商店" : "登录一下就能看今天的商店")
                .font(.headline)

            Text(model.hasSession
                 ? "点下面的按钮再读一次。要是总读不到，到「我的」重新登录。"
                 : "用微信扫一下二维码就行，不用电脑。扫完之后会自动续期，不用每次扫。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                if model.hasSession {
                    Task { await model.loadStore() }
                } else {
                    model.loginSheet = .wechat
                }
            } label: {
                Label(model.hasSession ? "再读一次" : "扫码登录",
                      systemImage: model.hasSession ? "arrow.clockwise" : "qrcode")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.zwRouge)
            .controlSize(.large)
            .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zwContentBackground(ZW.radiusGroup)
    }

    // MARK: - 底部的行动按钮（控件层）

    private var actionBar: some View {
        Button {
            Task { await model.loadStore() }
        } label: {
            if model.state.isLoading {
                Text("读取中…").frame(maxWidth: .infinity)
            } else {
                Label("读取今日商店", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.glassProminent)
        .tint(.zwRouge)
        .controlSize(.large)
        .disabled(model.state.isLoading)
        .padding(.horizontal, ZW.pad)
        .padding(.bottom, 8)
    }

    // MARK: - 时间

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

    /// 已经过去多少（0 → 刚刷新，1 → 该刷新了）
    private func progress(_ secs: TimeInterval) -> Double {
        min(1, max(0, 1 - secs / 86_400))
    }

    private func clock(_ secs: TimeInterval) -> String {
        let s = Int(secs)
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    // MARK: - 翻牌

    private func flipped(at index: Int) -> Bool {
        index < model.flipped.count ? model.flipped[index] : false
    }

    private func toggleFlip(_ index: Int) {
        guard index < model.flipped.count else { return }
        withAnimation(.spring(response: ZW.flip, dampingFraction: 0.8)) {
            model.flipped[index].toggle()
        }
    }

    /// 依次翻开，错开 130ms —— 复刻掌瓦的「每日首次查看翻牌动画」
    private func flipAll() {
        for i in 0..<model.flipped.count {
            Task {
                try? await Task.sleep(for: .milliseconds(i * ZW.revealStagger))
                withAnimation(.spring(response: ZW.flip, dampingFraction: 0.8)) {
                    if i < model.flipped.count { model.flipped[i] = true }
                }
            }
        }
    }
}
