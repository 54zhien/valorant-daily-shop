import SwiftUI
import UniformTypeIdentifiers
import ZhangwaKit

/// 设置页。既做 TabBar 的第三个页签，也做商店页右上角弹出的 sheet。
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var isSheet: Bool = false

    @State private var showImporter = false
    @State private var capturePath = ""
    @State private var cookieDraft = ""
    @State private var revealingCookie = false

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
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.json, .plainText, .data],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        Task { await model.importCapture(url: url) }
                    }
                case .failure(let error):
                    model.push("选择文件失败：\(error.localizedDescription)")
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

            Button {
                showImporter = true
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
            Text("导入抓包")
        } footer: {
            Text("AirDrop 过来的文件存到「文件」App 的「我的 iPhone → 每日商店」，再点「扫描 App 文件夹」，一次把两个文件都读进来。\n支持 mval_session.json（推荐，含 ct）、mval_capture.log、mitmproxy 的 mval-*.jsonl。")
        }
    }

    // MARK: 直接粘贴 Cookie
    //
    // 不想抓包传文件时的快速通道：从任何地方（浏览器 devtools / mitmproxy 的
    // headers / 已有的抓包记录）复制整行 Cookie 贴进来就行。
    //
    // 代价：Cookie 里没有 ct，所以**不能自刷新**，tid 过期就得重新贴。

    private var cookieSection: some View {
        Section {
            TextEditor(text: $cookieDraft)
                .font(.caption.monospaced())
                .frame(minHeight: 88)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .overlay(alignment: .topLeading) {
                    if cookieDraft.isEmpty {
                        Text("clientType=9; acctype=qc; uin=o10001; appid=102061775; openid=…; access_token=…; userId=u-…; accountType=5; tid=…")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.horizontal, 5)
                            .allowsHitTesting(false)
                    }
                }

            Button {
                model.saveCookie(cookieDraft)
                cookieDraft = ""
            } label: {
                Label("保存这份 Cookie", systemImage: "checkmark.circle")
            }
            .disabled(cookieDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text("直接粘贴 Cookie（快速通道）")
        } footer: {
            Text("不用传文件的方式。但 Cookie 里没有 ct —— 贴上就能读，tid 一过期就得重贴。想一劳永逸还是走上面的抓包导入。")
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
