import Foundation
import BackgroundTasks
import Photos

/// 后台增量扫描（BGAppRefreshTask）+ 相册变更监听
final class BackgroundScanService {

    static let taskIdentifier = "com.mapeiran.PhotoFaceSorter.refresh"

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            self.handle(refreshTask)
        }
    }

    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handle(_ task: BGAppRefreshTask) {
        schedule()
        let operation = Task {
            // TODO: 增量扫描新增照片（受系统后台时长限制）
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { operation.cancel() }
    }
}

/// 相册变更监听（前台实时增量）
final class PhotoChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
    var onChange: (() -> Void)?

    func register() {
        PHPhotoLibrary.shared().register(self)
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { [weak self] in
            self?.onChange?()
        }
    }
}
