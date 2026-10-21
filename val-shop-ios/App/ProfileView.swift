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
///
/// ## 关于「不写任何说明文字」
///
/// 每一节下面原来都有一句 footer（「扫一次就行…」「只用来读你自己账号…」）。
/// 全部去掉了 —— 这些信息对**第一次用**的人有点用，但对天天开的人只是噪音，
/// 而且按钮标题本身已经说清楚了（「QQ 扫码登录」不需要再解释一遍）。
/// 真需要解释的东西（比如扫码为什么安全）放在扫码页里，进来才看得到。
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

                Section("关于") {
                    LabeledContent("版本", value: "\(Bundle.main.shortVersion) (\(AppModel.buildStamp))")
                        // 排障入口藏在这里：**长按版本号**才进诊断台。
                        //
                        // 为什么不明着放一行：诊断台是开发阶段的产物（选接口、验登录用的），
                        // 现在两个真实故障场景（读不到商店 / 登录快过期）商店页顶上那行
                        // 提示已经覆盖了，正常用户永远不需要它。
                        //
                        // 为什么还留着：真出问题时这是唯一能看到内部状态的通道，
                        // 长按是零成本，删了以后再要就得重写一遍。
                        // 长按不算"藏功能" —— 它在明处，只是不占版面。
                        .contextMenu {
                            Button {
                                showDiagnostics = true
                            } label: {
                                Label("诊断台", systemImage: "stethoscope")
                            }
                        }
                    LabeledContent("数据来源", value: "掌上无畏契约（同源接口）")
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
        // 提前把两种登录的"二维码材料"取好，用户点开扫码页时就不用等网络：
        //   · 微信：ticket + 二维码（两趟往返，实测约 0.5 秒，但手机网络上可能好几秒）
        //   · QQ：登录页地址（WebView 拿到就能立刻开始加载）
        // 缓存 2 分钟，重复进这一页不会重复请求。
        .task {
            async let wx: Void = QRLogin.preload()
            async let qq: Void = QQLogin.preloadEntry()
            _ = await (wx, qq)
        }
    }

    // MARK: - 账号

    /// 只留一句话：这次是怎么登进来的。
    ///
    /// 头像、段位都不放 —— 商店页的账号条上已经有了，这里不重复。
    /// 前面那个菱形状态点也去掉了：它传达的「连接正常/异常」
    /// 在商店页的提示行里已经写过一遍，这里再放一个纯装饰。反正色弱也分辨不出来。
    private var accountSection: some View {
        Section {
            Text(model.loginMethodLabel)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
                .accessibilityAddTraits(.isStaticText)
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
