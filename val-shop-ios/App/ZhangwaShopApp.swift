import SwiftUI

@main
struct ZhangwaShopApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

/// 三个页签。iOS 26 的玻璃 TabBar 由系统提供，不要自己画背景。
struct RootView: View {
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
    }
}
