import SwiftUI
import ZhangwaKit

/// 「我的」—— 普通人能看懂的那一页。
///
/// 用系统的 `List`（inset grouped）：分隔线、Dynamic Type、VoiceOver、
/// 键盘导航、滑动操作全是白拿的，不用自己画行。
///
/// 页面上不出现「票据 / ct / 接口 / 日志 / 抓包」这类词。用户只需要回答三个问题：
///   1. 我现在登着没？
///   2. 没登 / 掉线了怎么办？（扫码，一步）
///   3. 换号 / 退出
struct ProfileView: View {

    @Environment(AppModel.self) private var model

    @State private var showRolePicker = false
    @State private var showDiagnostics = false
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            List {
                accountSection

                Section {
                    // QQ 在前、微信在后（和登录面板一致）
                    Button {
                        model.loginSheet = .qq
                    } label: {
                        Label("QQ 扫码登录", systemImage: "qrcode")
                    }
                    Button {
                        model.loginSheet = .wechat
                    } label: {
                        Label("微信扫码登录", systemImage: "qrcode")
                    }
                } header: {
                    Text("登录")
                } footer: {
                    Text("扫一次就行。之后会自动续期，不用每次扫。")
                }

                if model.canSwitchRole {
                    Section("角色") {
                        Button {
                            showRolePicker = true
                        } label: {
                            LabeledContent("当前角色",
                                           value: model.userRole?.displayName ?? "—")
                        }
                    }
                }

                Section {
                    Button("退出登录", role: .destructive) {
                        confirmSignOut = true
                    }
                    .disabled(!model.hasSession)
                }

                Section {
                    LabeledContent("版本", value: "\(Bundle.main.shortVersion) (\(AppModel.buildStamp))")
                    LabeledContent("数据来源", value: "掌上无畏契约（同源接口）")
                    // 排障入口：放在最底下、明明白白一行（长按那种藏法文档不认）
                    Button {
                        showDiagnostics = true
                    } label: {
                        Label("诊断", systemImage: "stethoscope")
                    }
                } header: {
                    Text("关于")
                } footer: {
                    Text("只用来读你自己账号的每日商店。")
                }
            }
            .navigationTitle("我的")
            // 和商店页同一层滚动边缘模糊（顶部 + 底部）—— 两页的顶栏/底栏观感要一致
            .zwScrollEdge(.all)
            .sheet(isPresented: $showRolePicker) {
                RolePickerView().environment(model)
            }
            .sheet(isPresented: $showDiagnostics) {
                DiagnosticsView().environment(model)
            }
            .confirmationDialog("退出登录后，看商店需要重新扫码。",
                                isPresented: $confirmSignOut,
                                titleVisibility: .visible) {
                Button("退出登录", role: .destructive) { model.clearSession() }
                Button("取消", role: .cancel) {}
            }
        }
    }

    // MARK: - 账号

    private var accountSection: some View {
        Section {
            HStack(spacing: 14) {
                avatar

                VStack(alignment: .leading, spacing: 3) {
                    // 这里不再重复游戏 ID（商店页已经有了），改成说"怎么登进来的"。
                    // 原来「已登录」前面那个菱形挪到这句前面。
                    HStack(spacing: 6) {
                        ZWDiamond()
                            .fill(model.sessionHealth.tint)
                            .frame(width: 8, height: 8)
                        Text(model.loginMethodLabel)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Text(model.displaySubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        }
    }

    private var avatar: some View {
        ZStack {
            Color(.tertiarySystemFill)
            if let icon = model.userRole?.icon, !icon.isEmpty, let url = URL(string: icon) {
                CachedImage(url: url, contentMode: .fill) { initial }
            } else {
                initial
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var initial: some View {
        Text(String(model.displayName.prefix(1)))
            .font(.title3.weight(.bold))
            .foregroundStyle(model.hasSession ? Color.primary : Color.secondary)
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
