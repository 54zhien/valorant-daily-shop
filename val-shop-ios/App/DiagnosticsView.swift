import SwiftUI
import ZhangwaKit

/// 诊断台 —— 排障用的一切。
///
/// 入口是「我的 → 关于 → 诊断」（一行明码，不做隐藏手势 ——
/// 自定义手势不该是唯一入口，这是 HIG Gestures 的要求）。
///
/// 为什么要留着：自签装的 App 没有 Xcode 控制台，出问题时这里是唯一的窗口。
///
/// 结构用系统的 `List` + `LabeledContent`，日志用等宽字体。
struct DiagnosticsView: View {

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var pasteDraft = ""
    @State private var pasteResult: String?

    var body: some View {
        NavigationStack {
            List {
                lastReadSection
                actionsSection
                pasteSection
                endpointsSection
                logSection

                Section {
                    Button("清除会话", role: .destructive) {
                        model.clearSession()
                    }
                }
            }
            .navigationTitle("诊断台")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - 上次读取

    private var lastReadSection: some View {
        Section("上次读取") {
            LabeledContent("结果", value: statusText)
            LabeledContent("时间",
                           value: model.lastLoadedAt.map(Self.clock.string(from:)) ?? "还没读过")
            LabeledContent("接口", value: model.client.shopPath ?? "（未配置）")
            LabeledContent("刷新于", value: refreshAtText)
            LabeledContent("登录态", value: sessionText)
        }
    }

    private var statusText: String {
        switch model.state {
        case .loading:  return "读取中…"
        case .loaded:   return "成功 · \(model.snapshot.items.count) 件商品"
        case .failed:   return "失败"
        case .idle:     return model.lastLoadedAt == nil ? "还没读过" : "空闲"
        }
    }

    private var refreshAtText: String {
        guard let expires = model.snapshot.expiresAt else { return "未知" }
        return Self.clock.string(from: expires)
    }

    private var sessionText: String {
        if !model.hasSession { return "没有登录态" }
        if model.session.ct.isEmpty { return "有会话，但没有 ct（不能自刷新）" }
        return "正常 · \(model.ctExpiryText)"
    }

    // MARK: - 动作

    private var actionsSection: some View {
        Section("动作") {
            Button {
                Task { await model.loadStore() }
            } label: {
                Label("读取今日商店", systemImage: "arrow.clockwise")
            }
            Button {
                Task { await model.refreshTickets() }
            } label: {
                Label("刷新票据 ct / wt", systemImage: "arrow.triangle.2.circlepath")
            }
            Button {
                Task { await model.probe() }
            } label: {
                Label("探测候选路径", systemImage: "magnifyingglass")
            }
            Button {
                model.resetShopPath()
            } label: {
                Label("恢复默认接口", systemImage: "arrow.uturn.backward")
            }
            Button {
                model.loadDemo()
            } label: {
                Label("载入演示数据", systemImage: "sparkles")
            }
            Button {
                Task { await model.importFromAppFolder() }
            } label: {
                Label("扫描 App 文件夹", systemImage: "folder.badge.gearshape")
            }
            Button {
                // 直接从最上层 VC present，不走 SwiftUI 的 sheet
                DocumentPicker.present { url in
                    Task { await model.importCapture(url: url) }
                }
            } label: {
                Label("从「文件」里选", systemImage: "folder")
            }
            ShareLink(item: model.diagnostics,
                      subject: Text("每日商店诊断信息"),
                      message: Text("App \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")) {
                Label("导出诊断信息", systemImage: "square.and.arrow.up")
            }
        }
    }

    // MARK: - 粘贴登录态

    private var pasteSection: some View {
        Section {
            TextEditor(text: $pasteDraft)
                .font(.system(.footnote, design: .monospaced))
                .frame(minHeight: 96)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                pasteResult = model.importPasted(pasteDraft)
                if pasteResult?.hasPrefix("导入成功") == true { pasteDraft = "" }
            } label: {
                Label("识别并导入", systemImage: "wand.and.stars")
            }
            .disabled(pasteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let r = pasteResult {
                Text(r)
                    .font(.footnote)
                    .foregroundStyle(r.hasPrefix("导入成功") ? Color.zwSignal : Color.red)
            }
        } header: {
            Text("粘贴登录态")
        } footer: {
            Text("贴 mval_session.json 的整段内容（以 { 开头，含 ct），或直接粘 Cookie 头。")
        }
    }

    // MARK: - 抓包接口

    private var endpointsSection: some View {
        Section("抓到的接口") {
            NavigationLink {
                EndpointsView()
            } label: {
                LabeledContent("接口清单", value: "\(model.endpoints.count) 条")
            }
        }
    }

    // MARK: - 日志

    private var logSection: some View {
        Section("运行日志") {
            if model.log.isEmpty {
                Text("—")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(model.log.prefix(80).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(logColor(line))
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func logColor(_ line: String) -> Color {
        if line.contains("✅") { return .zwSignal }
        if line.contains("❌") || line.contains("失败") { return .red }
        return .secondary
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()
}
