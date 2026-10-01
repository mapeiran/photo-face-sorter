import Foundation
import UIKit
import Combine

/// 增量自动扫描管理：前台相册变更监听 + 后台刷新
///
/// 使用 App 内**唯一**的 `ScanCoordinator`（由 `PhotoFaceSorterApp` 注入），
/// 避免前台自动扫描与手动扫描各自持有协调器而互相覆盖扫描结果。
@MainActor
final class AutoScanManager: ObservableObject {

    @Published var lastRunDate: Date?
    @Published var lastRunMessage: String?

    private let observer = PhotoChangeObserver()
    private let background = BackgroundScanService.shared
    private weak var coordinator: ScanCoordinator?
    private var store: CacheStore?
    private var debounceTask: Task<Void, Never>?

    /// 后台单次处理上限（控制耗电）
    private let backgroundBatchLimit = 60

    func configure(store: CacheStore, coordinator: ScanCoordinator) {
        self.store = store
        self.coordinator = coordinator

        // 注册已在 AppDelegate 完成；这里只挂载后台任务真正要执行的工作
        background.onRun = { [weak self] in
            guard let self else { return false }
            return await self.runIncremental(isBackground: true)
        }

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

    /// - Returns: 工作是否正常结束（未被执行系统中断）。
    ///   无事可做（扫描器忙、仅充电跳过）视为正常结束，避免误报后台任务失败。
    @discardableResult
    private func runIncremental(isBackground: Bool) async -> Bool {
        guard let store, let coordinator else { return false }
        guard coordinator.state == .idle || coordinator.state == .finished else { return true }

        if isBackground {
            let chargeOnly = UserDefaults.standard.bool(forKey: "chargeOnlyBackground")
            if chargeOnly {
                UIDevice.current.isBatteryMonitoringEnabled = true
                defer { UIDevice.current.isBatteryMonitoringEnabled = false }
                if UIDevice.current.batteryState == .unplugged {
                    lastRunMessage = "仅充电时后台扫描，已跳过"
                    return true
                }
            }
        }

        lastRunDate = Date()
        lastRunMessage = isBackground ? "后台增量扫描中…" : "前台增量扫描中…"

        // 用户设置的「单次扫描上限」优先；后台再叠加 60 张的硬上限以控制耗电，
        // 避免自动扫描在用户不知情时长时间占用设备。
        let limit = ScanBatchPolicy.configuredLimit(cap: isBackground ? backgroundBatchLimit : nil)
        coordinator.start(store: store, limit: limit)
        // 必须等扫描真正结束，否则后台任务会在扫描进行中就被系统挂起
        await coordinator.waitUntilFinished()
        // 写入是合并异步的，上报完成前先确保落盘
        store.flushPendingWrites()

        let interrupted = Task.isCancelled
        lastRunMessage = interrupted ? "增量扫描被系统中断，已保存进度" : "增量扫描完成"
        return !interrupted
    }
}
