import SwiftUI

@main
struct ValPeekApp: App {
    @State private var model: AppModel

    init() {
        // 皮肤图是 CDN 上的**原图**（实测单张 1.6 MB，`ossweb-img.qq.com`），
        // 服务端只给 `Cache-Control: max-age=600`（10 分钟），而 iOS 默认的
        // `URLCache` 磁盘额度只有 10 MB —— 四张图 6.5 MB 直接把它挤爆，
        // 于是每次冷启动都在重新下载。这就是"皮肤图片要加载好一会"的根因。
        //
        // 换成大得多的磁盘缓存之后：10 分钟内的第二次打开是纯本地命中；
        // 过期后也只是一次 304 重验证（ETag 存在），不用再传 1.6 MB。
        URLCache.shared = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024,
            directory: URL.cachesDirectory.appending(path: "zwImageCache"))

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

/// 两个页签 —— 就两件事：看商店、管账号。
/// iOS 26 的玻璃 TabBar 由系统提供，不要自己画背景。
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // @Bindable 必须放在 body 里当局部变量用 —— 写成存储属性是编译不过的
        @Bindable var model = model

        return TabView {
            Tab("商店", systemImage: "bag.fill") {
                ShopView()
            }
            Tab("我的", systemImage: "person.crop.circle") {
                ProfileView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(.zwRouge)
        // ★ 扫码登录挂在这儿（**根视图**），不是挂在「我的」里。
        //   「我的」自己可能就是 sheet（诊断台），再往里弹一层会变成嵌套 sheet ——
        //   iOS 上不稳，之前 .fileImporter 就是栽在这上面。挂根上永远只有一层。
        .sheet(item: $model.loginSheet) { which in
            switch which {
            case .wechat: QRLoginView().environment(model)
            case .qq:     QQLoginView().environment(model)
            }
        }
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
