import Foundation
import Photos
import UIKit
import Combine

/// 增量自动扫描管理：前台相册变更监听 + 后台刷新
@MainActor
final class AutoScanManager: ObservableObject {

    @Published var lastRunDate: Date?
    @Published var lastRunMessage: String?

    private let observer = PhotoChangeObserver()
    private let background = BackgroundScanService()
    private let coordinator = ScanCoordinator()
    private var store: CacheStore?
    private var debounceTask: Task<Void, Never>?

    /// 后台单次处理上限（控制耗电）
    private let backgroundBatchLimit = 60

    func configure(store: CacheStore) {
        self.store = store

        background.onRun = { [weak self] in
            await self?.runIncremental(isBackground: true)
        }
        background.register()

        observer.onChange = { [weak self] in
            self?.handleLibraryChange()
        }
        observer.register()
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            background.schedule()
        }
    }

    // MARK: - 前台变更

    private func handleLibraryChange() {
        guard UserDefaults.standard.bool(forKey: "autoScanEnabled") else { return }
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s 防抖
            guard !Task.isCancelled else { return }
            await runIncremental(isBackground: false)
        }
    }

    // MARK: - 增量扫描

    private func runIncremental(isBackground: Bool) async {
        guard let store else { return }
        guard coordinator.state == .idle || coordinator.state == .finished else { return }

        if isBackground {
            let chargeOnly = UserDefaults.standard.bool(forKey: "chargeOnlyBackground")
            if chargeOnly {
                UIDevice.current.isBatteryMonitoringEnabled = true
                if UIDevice.current.batteryState == .unplugged {
                    lastRunMessage = "仅充电时后台扫描，已跳过"
                    return
                }
            }
        }

        lastRunDate = Date()
        lastRunMessage = isBackground ? "后台增量扫描中…" : "前台增量扫描中…"
        coordinator.start(store: store, limit: isBackground ? backgroundBatchLimit : .max)
    }
}
