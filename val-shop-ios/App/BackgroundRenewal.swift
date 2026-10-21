import Foundation
import BackgroundTasks

// ============================================================================
//  后台续期
// ============================================================================
//
//  为什么需要：ct 活 7 天，靠「打开 App 时自动续」能一直滚下去 ——
//  但前提是**你得打开 App**。忙起来 8 天没开，ct 就断了，又得回电脑抓包。
//
//  BGAppRefreshTask 让系统在后台隔一段时间叫醒我们一次，续一下 ct。
//  这样即使好几天没打开 App，登录态也不会断。
//
//  ⚠️ iOS 不保证什么时候跑、跑不跑（取决于用户使用习惯、低电量模式、
//  后台 App 刷新开关等）。所以它是**额外一层保险**，不能替代主路径。
//  两条都留着：打开 App 时一定会续，后台刷新是兜底。
//
//  注册必须在启动完成前做完，所以挂在 ValPeekApp 的 init 里。
// ============================================================================

enum BackgroundRenewal {

    /// 必须和 Info.plist 的 BGTaskSchedulerPermittedIdentifiers 完全一致
    static let taskID = "com.imzhien.valpeek.renew"

    /// App 启动时调一次：把任务注册上，并排下一次。
    static func register(model: AppModel) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskID,
            using: nil
        ) { task in
            // 这个闭包跑在非主线程、且是 @Sendable。
            // BGTask 是 NSObject 子类，不是 Sendable —— 想把它带进
            // `Task { @MainActor in }` 里会被 Swift 6 拒绝。
            // 用 nonisolated(unsafe) 明确表态：这个值只在这个闭包和它派生的
            // 一个 Task 之间传递，没有任何并发读写，是安全的。
            nonisolated(unsafe) let bgTask = task
            nonisolated(unsafe) let bgModel = model

            schedule()

            guard let refresh = bgTask as? BGAppRefreshTask else {
                bgTask.setTaskCompleted(success: false)
                return
            }

            // 系统给的时间很短（约 30 秒），超时会被强杀。
            // 所以只做「续 ct」这一件轻活，不去拉商店数据。
            let work = Task { @MainActor in
                await bgModel.renewSessionIfNeeded()
                refresh.setTaskCompleted(success: true)
            }

            refresh.expirationHandler = {
                work.cancel()
                refresh.setTaskCompleted(success: false)
            }
        }

        schedule()
    }

    /// 排下一次后台刷新。系统自己决定什么时候真正执行。
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        // 最早 6 小时后再叫醒我们。
        //
        // 为什么不设 1 天：这个值只是「最早什么时候」，
        // iOS 会按用户使用习惯决定真的什么时候跑（还可能完全不跑）。
        // 设小一点 = 在 7 天的 ct 寿命里多几次机会。
        // 就算 iOS 一次都没跑，还有「打开 App 时自动续」那条主路径兜底。
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // 模拟器、用户关了后台刷新、超出配额时都会到这里。
            // 不影响主流程 —— 打开 App 时那条路照样会续。
            print("[BackgroundRenewal] 排期失败（不影响使用）：\(error)")
        }
    }
}
