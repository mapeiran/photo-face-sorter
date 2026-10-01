import SwiftUI

@main
struct PhotoFaceSorterApp: App {
    /// 共享对象由 AppDelegate 持有并在 `didFinishLaunching` 中装配 ——
    /// 系统后台拉起 App 执行刷新任务时窗口可能不出现，只有该回调一定会执行。
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appDelegate.model)
                .environmentObject(appDelegate.coordinator)
                .environmentObject(appDelegate.autoScan)
                .task {
                    // 自动扫描总开关只在有 UI 时才需要同步
                    appDelegate.autoScan.setEnabled(appDelegate.model.autoScanEnabled)
                }
        }
    }
}
