import UIKit

/// 在 App 启动完成前注册后台任务处理器，并提前装配共享对象。
///
/// 两件事都必须在这里做：
/// 1. `BGTaskScheduler.register` 必须在 `didFinishLaunching` 期间调用，否则后台任务永远不会被触发；
/// 2. 系统以后台方式拉起 App 执行刷新任务时，SwiftUI 的窗口可能根本不会出现，
///    若把装配放在 `.task` / `.onAppear` 里，后台任务的回调就永远是空的。
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {

    /// 全 App 共享对象。由 AppDelegate 持有，保证后台启动时也已就绪。
    let model = AppModel()
    let coordinator = ScanCoordinator()
    let autoScan = AutoScanManager()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundScanService.shared.registerIfNeeded()
        autoScan.configure(store: model.store, coordinator: coordinator)
        return true
    }

    /// 进入后台前把合并写入的数据落盘，避免被系统回收时丢数据
    func applicationDidEnterBackground(_ application: UIApplication) {
        model.store.flushPendingWrites()
    }
}
