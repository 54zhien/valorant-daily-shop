import SwiftUI

@main
struct ZhangwaShopApp: App {
    @State private var model: AppModel

    init() {
        let m = AppModel()
        _model = State(initialValue: m)
        // BGTaskScheduler 的注册必须在启动完成前做完，App.init() 是最晚的合适位置。
        // （用 AppDelegate 也行，但这里没必要为了一行注册引入一个 delegate）
        BackgroundRenewal.register(model: m)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

/// 三个页签。iOS 26 的玻璃 TabBar 由系统提供，不要自己画背景。
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            Tab("商店", systemImage: "bag.fill") {
                ShopView()
            }
            Tab("接口", systemImage: "list.bullet.rectangle") {
                EndpointsView()
            }
            Tab("设置", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
        // 向下滚动时 TabBar 收起，把屏幕让给内容
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(.zwAccent)
        // ★ 每次回到前台都续一次 ct。
        //
        // 这是「脱离电脑」的关键：ct 活 7 天，靠它自己滚下去。
        // 用户可能只是想瞄一眼商店就关掉，不会去点「读取」，
        // 所以续期必须挂在 App 生命周期上，不能只挂在「读取商店」上。
        .task { await model.renewSessionIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.renewSessionIfNeeded() }
            }
        }
    }
}
