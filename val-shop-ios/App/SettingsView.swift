import SwiftUI
import UniformTypeIdentifiers
import ZhangwaKit

/// 设置页。既做 TabBar 的第三个页签，也做商店页右上角弹出的 sheet。
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var isSheet: Bool = false

    @State private var capturePath = ""
    @State private var cookieDraft = ""
    @State private var revealingCookie = false
    @State private var importPastedResult: String?

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                importSection
                cookieSection
                shopSection
                maintenanceSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(ZWBrandBackdrop())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isSheet {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                    }
                }
            }

        }
    }

    // MARK: 登录态

    private var statusSection: some View {
        Section {
            LabeledContent("状态") {
                Text(model.hasSession ? "已登录" : "未登录")
                    .foregroundStyle(model.hasSession ? .green : .secondary)
            }
            LabeledContent("账号", value: model.accountLabel)
            LabeledContent("掌瓦 userId", value: model.session.userID.isEmpty ? "—" : model.session.userID)
            LabeledContent("QQ", value: model.session.uin == 0 ? "—" : String(model.session.uin))
            LabeledContent("ct（用于换票）") {
                Text(model.session.ct.isEmpty ? "无" : "有")
                    .foregroundStyle(model.session.ct.isEmpty ? .orange : .green)
            }
            LabeledContent("tid（= wt）") {
                Text(model.session.tid.isEmpty ? "无" : "有")
                    .foregroundStyle(model.session.tid.isEmpty ? .orange : .green)
            }

            DisclosureGroup("Cookie 预览", isExpanded: $revealingCookie) {
                Text(model.session.cookieHeader.isEmpty ? "—" : model.session.cookieHeader)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }

            Button {
                Task { await model.refreshTickets() }
            } label: {
                Label("刷新票据 ct / wt / access_token", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!model.hasSession)
        } header: {
            Text("登录态")
        } footer: {
            if model.session.ct.isEmpty && model.hasSession {
                Text("这份会话没有 ct，无法自刷新 —— tid 过期后需要重新抓包。")
            }
        }
    }

    // MARK: 导入

    private var importSection: some View {
        Section {
            Button {
                Task { await model.importFromAppFolder() }
            } label: {
                Label("扫描 App 文件夹", systemImage: "folder.badge.gearshape")
            }

            // 直接从最上层 VC present，不走 SwiftUI 的 sheet ——
            // 设置页本身已经是 sheet 了，再套一层很容易失效
            Button {
                DocumentPicker.present { url in
                    Task { await model.importCapture(url: url) }
                }
            } label: {
                Label("从「文件」里选", systemImage: "folder")
            }

            TextField("或填完整路径", text: $capturePath)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.caption.monospaced())

            Button {
                Task { await model.importCapture(path: capturePath) }
            } label: {
                Label("按路径导入", systemImage: "square.and.arrow.down")
            }
            .disabled(capturePath.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text("从文件导入")
        } footer: {
            Text("路径：「文件」App → 浏览 → **我的 iPhone** → 「每日商店」→ 把 mval_session.json 放进去 → 回来点「扫描 App 文件夹」。\n\n"
                 + "看不到这个文件夹的话，依次试：\n"
                 + "1. 确认装的是新版本（老版本没有开文件共享）\n"
                 + "2. 把 App 完全退出再启动一次（iOS 要等 App 跑过一次才登记）\n"
                 + "3. 后台杀掉「文件」App 再打开\n"
                 + "4. 还是没有 → 用上面的「粘贴登录态」，那条路不依赖「文件」App")
        }
    }

    // MARK: 直接粘贴
    //
    // 不想/不方便传文件时的通道。整个框智能识别：
    //   · mval_session.json 的整段 JSON  → 含 ct，能自刷新（推荐）
    //   · 纯 Cookie 头                    → 能用，但 tid 过期就得重贴

    private var cookieSection: some View {
        Section {
            TextEditor(text: $cookieDraft)
                .font(.caption.monospaced())
                .frame(minHeight: 110)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .overlay(alignment: .topLeading) {
                    if cookieDraft.isEmpty {
                        Text("粘贴 mval_session.json 的整段内容（以 { 开头，含 ct，能自刷新）\n或直接粘 Cookie 头（clientType=9; acctype=qc; …; tid=…）")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.horizontal, 5)
                            .allowsHitTesting(false)
                    }
                }

            Button {
                importPastedResult = model.importPasted(cookieDraft)
                if importPastedResult?.hasPrefix("导入成功") == true {
                    cookieDraft = ""
                }
            } label: {
                Label("识别并导入", systemImage: "wand.and.stars")
            }
            .disabled(cookieDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let r = importPastedResult {
                Text(r)
                    .font(.caption)
                    .foregroundStyle(r.hasPrefix("导入成功") ? .green : .orange)
            }
        } header: {
            Text("粘贴登录态（最省事，不用传文件）")
        } footer: {
            Text("在电脑上打开 mval_session.json，全选复制，微信/备忘录发到手机再粘过来即可。\n"
                 + "这条路的优点是没有任何前置条件 —— 文件导入要走「文件」App，会受 App 是否启动过、缓存等因素影响。")
        }
    }

    // MARK: 商店接口

    private var shopSection: some View {
        @Bindable var model = model

        return Section {
            TextField("/go/agame/store/storefront", text: $model.shopPathDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.caption.monospaced())

            TextField("{}", text: $model.shopBodyDraft, axis: .vertical)
                .lineLimit(1...5)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.caption.monospaced())

            Button {
                model.saveShopPath(model.shopPathDraft, body: model.shopBodyDraft)
            } label: {
                Label("保存", systemImage: "checkmark.circle")
            }

            Button {
                Task { await model.probe() }
            } label: {
                Label("探测候选路径", systemImage: "magnifyingglass")
            }
        } header: {
            Text("每日商店接口")
        } footer: {
            Text("这条路径不在 APK 里（商店页由服务端下发的 RN bundle 渲染）。抓一次包后在「接口」页一键设为商店接口。")
        }
    }

    // MARK: 维护

    private var maintenanceSection: some View {
        Section {
            Button {
                model.loadDemo()
            } label: {
                Label("载入演示数据", systemImage: "sparkles")
            }

            // 自签装的 App 没有 Xcode 控制台，出问题就把这个发我
            ShareLink(item: model.diagnostics,
                      subject: Text("每日商店诊断信息"),
                      message: Text("App \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")) {
                Label("导出诊断信息", systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive) {
                model.clearSession()
            } label: {
                Label("清除会话", systemImage: "trash")
            }
        } header: {
            Text("维护")
        } footer: {
            Text("导出的是纯文本：登录态概览 + 商店接口 + 归一化结果 + 原始 JSON + 完整日志。里面不含 Cookie / token。")
        }
    }

    // MARK: 关于

    private var aboutSection: some View {
        Section {
            LabeledContent("协议", value: "掌瓦 /go/*")
            LabeledContent("域名", value: ZhangwaClient.hostProd)
            LabeledContent("版本", value: Bundle.main.shortVersion)
            Link(destination: URL(string: "https://developer.apple.com/documentation/swiftui/glass")!) {
                Label("Liquid Glass 文档", systemImage: "sparkles.rectangle.stack")
            }
        } header: {
            Text("关于")
        } footer: {
            Text("只用来读取你自己账号的商店数据。协议细节逆向自 Android 版 com.tencent.apps.valorant 2.10.1。")
        }
    }
}

extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }

    var buildNumber: String {
        (infoDictionary?["CFBundleVersion"] as? String) ?? "—"
    }
}
