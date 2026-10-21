import SwiftUI
import ZhangwaKit

/// 商店主界面 —— 普通人**唯一**需要懂的页面。
///
/// 版式按系统分组内容的做法：
///   NavigationStack（顶部导航栏，inline 标题）
///     ScrollView（下拉可刷新）
///       身份卡（内容卡）
///       出错时一条提示
///       今日四张：小标 + 引信条 + 2×2 卡阵
///
/// 没有「读取」按钮：进来自动读一次（`loadStoreIfNeeded`），要重读就下拉。
///
/// 材质：玻璃留给控件层（导航栏、页签栏、翻开全部 —— 系统自己就是玻璃），
/// 内容层一律用系统分组背景色，不透明。
/// **唯一例外是身份条**：它长得像控件、也确实可点（多角色时点开切换），
/// 所以走 `zwGlassCard()`（系统原生 `glassEffect`），圆角 `ZW.radiusGlass` 比内容卡更大。
struct ShopView: View {

    @Environment(AppModel.self) private var model

    @State private var showRolePicker = false

    private let columns = [
        GridItem(.flexible(), spacing: ZW.cardGap),
        GridItem(.flexible(), spacing: ZW.cardGap),
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
            .navigationTitle("皮肤商店")
            .navigationBarTitleDisplayMode(.inline)
            // 下拉重读：系统标准手势，不需要额外的按钮
            .refreshable {
                await model.loadStore()
            }
            .sheet(isPresented: $showRolePicker) {
                RolePickerView().environment(model)
            }
            // 进来就自动读一次；这一期已经读过就直接用现有的
            .task {
                await model.loadStoreIfNeeded()
            }
        }
    }

    // MARK: - 身份卡

    /// 身份条：卡面居中放大 → 游戏 ID → 段位。
    ///
    /// 三条设计决定，都是用户明确提的：
    ///   1. **不要液态玻璃** —— 直接坐在页面底色上，不用 `zwGlassCard()`
    ///   2. **不要状态点（那个菱形）和「已登录」字样** ——
    ///      正常使用时这两个信息没有价值；真出问题时上面的 alertInfo 会说清楚
    ///   3. **竖向居中排布** —— 原来是横着的一行，卡面只有 38pt；
    ///      现在 76pt 居中，名字和段位各占一行
    ///
    /// 多角色时才可点（一个人一个号的时候不该有入口）。
    private var identityCard: some View {
        Button {
            if model.canSwitchRole { showRolePicker = true }
        } label: {
            VStack(spacing: 9) {
                avatar

                HStack(spacing: 4) {
                    Text(model.displayName)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if model.canSwitchRole {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(model.displaySubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!model.canSwitchRole)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.displayName)，\(model.displaySubtitle)")
    }

    /// 卡面。放大到 76pt、圆形裁切、居中 —— 整条信息栏的视觉重心。
    private var avatar: some View {
        ZStack {
            Circle().fill(Color(.tertiarySystemFill))
            if let icon = model.userRole?.icon, !icon.isEmpty, let url = URL(string: icon) {
                CachedImage(url: url, contentMode: .fill) { fallbackInitial }
            } else {
                fallbackInitial
            }
        }
        .frame(width: ZW.avatar, height: ZW.avatar)
        .clipShape(.circle)
        .overlay(Circle().stroke(.primary.opacity(0.08), lineWidth: 0.5))
    }

    private var fallbackInitial: some View {
        Text(String(model.displayName.prefix(1)))
            .font(.title2.weight(.bold))
            .foregroundStyle(model.hasSession ? Color.primary : Color.secondary)
    }

    // MARK: - 只在出事时出现的提示

    private var alertInfo: (text: String, ok: Bool)? {
        if case .failed(let msg) = model.state {
            return ("没读到商店：\(msg)。下拉刷新再试一次。", false)
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

            // 卡阵间距用 cardGap（比常规块间距大）：翻牌的光要留在自己那块地方
            LazyVGrid(columns: columns, spacing: ZW.cardGap) {
                ForEach(Array(model.snapshot.items.prefix(4).enumerated()), id: \.offset) { index, item in
                    StoreCardView(item: item,
                                  slot: index + 1,
                                  isFlipped: flipped(at: index)) {
                        toggleFlip(index)
                    }
                }
            }
        }
    }

    /// 一行说明：`下次刷新时间 · 引信条 · 倒计时`（+ 右边的「翻开全部」）。
    /// 引信条**顶满**：它把标签和倒计时之间、以及倒计时到按钮之间的空当全吃掉，
    /// 右端不会留一截死空。
    private var lineUpHeader: some View {
        HStack(spacing: 8) {
            Text("下次刷新时间")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize()

            // 顶满：进度条吃掉标签和时间之间的所有空当（右边不留死空）
            fuse
                .frame(minWidth: ZW.fuseWidth, maxWidth: .infinity)

            countdown

            // 冷启动时可能先在显示上一期的缓存，正在拉新的 —— 给个不打扰的提示
            if model.state.isLoading {
                ProgressView()
                    .controlSize(.mini)
            }

            Button {
                flipAll()
            } label: {
                Text("翻开全部")
                    .font(.subheadline)
                    .lineLimit(1)
                    .fixedSize()          // 别让这一行被挤成两行
            }
            .buttonStyle(.glass)
            .controlSize(.regular)
            .disabled(model.flipped.allSatisfy { $0 })
        }
        .padding(.horizontal, 2)
        // 这一行整体往下、靠卡阵近一些：上边距吃掉原来那段空白（8 → 30）。
        // 下边距 32pt —— 翻牌时光晕外扩约 15pt、抬升再 11pt，合起来约 26pt，
        // 留出一点余量，光不会糊到这一行上。
        .padding(.top, 40)
        .padding(.bottom, 26)
    }

    /// 倒计时走自己的一秒一拍 —— 只重绘这一小块
    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let secs = remainingSeconds(now: context.date)
            Text(clock(secs))
                .zwMonoStyle(.footnote)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText(countsDown: true))
                .lineLimit(1)
                .minimumScaleFactor(0.8)      // 被挤的时候缩一点，别换行
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
                        .frame(height: 3)

                    Capsule()
                        .fill(Color.zwRouge)
                        .frame(width: max(0, w * ratio), height: 3)
                }
                .frame(height: 5, alignment: .center)
            }
            .frame(height: 5)
            .accessibilityElement()
            .accessibilityLabel("距离下次刷新的进度")
            .accessibilityValue("\(Int(ratio * 100))%")
        }
    }

    // MARK: - 空态

    /// 空的时候只给一步：没登录就登录；登录了就是"下拉刷新"（没有按钮可点）
    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: model.hasSession ? "tray" : "qrcode")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(model.hasSession ? "今天还没读到商店" : "登录一下就能看今天的商店")
                .font(.headline)

            Text(model.hasSession
                 ? "下拉刷新再试一次。要是总读不到，到「我的」重新登录。"
                 : "用微信扫一下二维码就行，不用电脑。扫完之后会自动续期，不用每次扫。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // 只有「还没登录」才给按钮 —— 读取本身没有按钮了，重读就是下拉
            if !model.hasSession {
                Button {
                    model.loginSheet = .wechat
                } label: {
                    Label("扫码登录", systemImage: "qrcode")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.zwRouge)
                .controlSize(.large)
                .padding(.top, 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zwContentBackground(ZW.radiusGroup)
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

    /// 翻一张：一次干净的镜像翻转。
    /// 曲线是 `ZW.flipCurve`（时间对称），两个面在转到 90° 那一刻换 —— 见 DesignSystem。
    private func toggleFlip(_ index: Int) {
        guard index < model.flipped.count else { return }
        let next = !flipped(at: index)
        withAnimation(ZW.flipCurve) {
            model.setFlipped(index, to: next)
        }
    }

    /// 依次翻开，错开 130ms —— 复刻掌瓦的「每日首次查看翻牌动画」
    private func flipAll() {
        for i in 0..<min(4, max(model.flipped.count, 1)) {
            Task {
                try? await Task.sleep(for: .milliseconds(i * ZW.revealStagger))
                withAnimation(ZW.flipCurve) {
                    model.setFlipped(i, to: true)
                }
            }
        }
    }
}
