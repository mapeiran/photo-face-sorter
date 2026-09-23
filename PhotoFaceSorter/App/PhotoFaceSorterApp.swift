import SwiftUI

@main
struct PhotoFaceSorterApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var autoScan = AutoScanManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(autoScan)
                .task {
                    autoScan.configure(store: model.store)
                    autoScan.setEnabled(model.autoScanEnabled)
                }
        }
    }
}
