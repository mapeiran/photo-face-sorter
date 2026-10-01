import Foundation
import BackgroundTasks
import Photos

/// 后台增量扫描（BGAppRefreshTask）
///
/// 关键约束：`BGTaskScheduler.register` 必须在 App **启动完成之前**调用，
/// 否则系统会抛出 "All launch handlers must be registered before application
/// finishes launching"，后台任务永远不会被触发。因此注册由
/// `AppDelegate.application(_:didFinishLaunchingWithOptions:)` 提前完成，
/// 本类只负责保存后台任务真正要执行的工作。
///
/// `@unchecked Sendable` 的依据：可变状态（`work` / `registered`）全部由 `lock` 保护。
final class BackgroundScanService: @unchecked Sendable {

    static let shared = BackgroundScanService()
    static let taskIdentifier = "com.mapeiran.PhotoFaceSorter.refresh"

    /// 后台触发时执行的工作。返回值表示是否在系统截止时间前正常完成。
    private var work: (@Sendable () async -> Bool)?

    private let lock = NSLock()
    private var registered = false

    /// 后台任务的实际工作（由 AutoScanManager 挂载，可在启动之后设置）
    var onRun: (@Sendable () async -> Bool)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return work
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            work = newValue
        }
    }

    private init() {}

    /// 必须在 App 启动完成前调用（见 AppDelegate）。
    func registerIfNeeded() {
        lock.lock()
        guard !registered else {
            lock.unlock()
            return
        }
        registered = true
        lock.unlock()

        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            Self.handle(refreshTask)
        }
    }

    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        // 模拟器或未开启后台刷新权限时提交失败属正常情况，不影响前台增量扫描
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        let service = BackgroundScanService.shared
        // 立刻排队下一次，避免本次被打断后再也不触发
        service.schedule()

        let workTask = Task { () -> Bool in
            guard let onRun = service.onRun else { return false }
            let completed = await onRun()
            return completed && !Task.isCancelled
        }

        task.expirationHandler = { workTask.cancel() }

        // 只有在扫描真正结束（或被系统中断）之后才向系统上报完成，
        // 否则 App 会在扫描中途被挂起。
        //
        // `BGAppRefreshTask` 不是 Sendable，直接捕获进 `Task` 会在严格并发下报
        // “sending closure risks data races”。`setTaskCompleted` 允许从任意线程调用，
        // 所以用一个显式的 Sendable 包装来表明这一点。
        let completer = TaskCompleter(task: task)
        Task {
            let completed = await workTask.value
            completer.complete(success: completed)
        }
    }
}

/// 把后台任务引用安全地传进并发闭包。
/// `BGTask.setTaskCompleted(success:)` 本身允许跨线程调用，故 `@unchecked` 成立。
private struct TaskCompleter: @unchecked Sendable {
    let task: BGAppRefreshTask

    func complete(success: Bool) {
        task.setTaskCompleted(success: success)
    }
}

/// 相册变更监听（前台实时增量）
///
/// `@unchecked Sendable` 的依据：`onChange` 只在主线程上设置与读取
/// （`configure` 在主线程，回调也派发回主线程）。
final class PhotoChangeObserver: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    var onChange: (() -> Void)?

    func register() {
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { [weak self] in
            self?.onChange?()
        }
    }
}
