import Foundation
import Photos
import UIKit
import Vision
import Combine

/// 扫描任务协调器（手动全量 / 增量），后台异步、可暂停/终止
///
/// 全 App 只应存在一个实例（由 `AppDelegate` 持有并注入），
/// 否则前台自动扫描与手动扫描会各自快照 `records`/`samples` 并互相覆盖。
///
/// 界面冻结的主要来源（枚举整个相册、解码缓存 JSON、全量聚类）都在
/// `prepare` / `recluster` 里被放到后台线程执行，主线程只保留计数更新与 UI 状态。
@MainActor
final class ScanCoordinator: ObservableObject {

    enum State: Equatable {
        case idle, scanning, paused, finished
        var title: String {
            switch self {
            case .idle:     return "空闲"
            case .scanning: return "扫描中"
            case .paused:   return "已暂停"
            case .finished: return "已完成"
            }
        }
    }

    @Published var state: State = .idle
    @Published var total = 0
    @Published var scanned = 0
    @Published var facePhotos = 0
    @Published var faceCount = 0
    /// 本次扫描中取不到图片（多为 iCloud 未下载）而跳过的张数。
    /// 这些照片**不会**被标记为已扫描，下次扫描会重试。
    @Published var unavailable = 0
    /// 受「单次扫描上限」限制、本批没来得及处理、下次还会被挑出来的张数。
    /// 用来在进度 100% 时提示用户「还有货，再点一次继续」，避免误以为已全部扫完。
    @Published var remaining = 0

    // 这些服务都无状态且 Sendable，标记 nonisolated 以便在后台线程上使用
    private nonisolated let detector = FaceDetectionService()
    private nonisolated let embedder = FaceEmbeddingService()

    /// 每扫描多少张就把样本与记录落盘一次。
    ///
    /// 落盘是「整份重写」：太小会让大相册扫描过程中反复全量编码（每次都要编码整份样本 + 整份记录），
    /// 太大则崩溃时丢的进度多。扫描本身是幂等的，丢掉的进度下次重扫即可，所以取偏大的值。
    private let flushInterval = 100

    private var runTask: Task<Void, Never>?
    private var paused = false
    private var stopped = false

    var progress: Double { total > 0 ? Double(scanned) / Double(total) : 0 }

    // MARK: - 控制

    func start(store: CacheStore, limit: Int = .max) {
        // 只允许从「空闲/已完成」启动；否则会与仍在运行的（或已暂停的）任务并发
        guard state == .idle || state == .finished else { return }
        state = .scanning
        paused = false
        stopped = false
        runTask = Task { await run(store: store, limit: limit) }
    }

    /// 等待当前扫描任务结束。
    /// 后台任务与增量自动扫描必须等它，才能向系统正确上报完成。
    func waitUntilFinished() async {
        let task = runTask
        await task?.value
    }

    func pause() {
        guard state == .scanning else { return }
        paused = true
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        paused = false
        state = .scanning
    }

    func stop() {
        stopped = true
        runTask?.cancel()
        state = .idle
    }

    // MARK: - 扫描准备（后台线程）

    private struct ScanPlan {
        var records: [String: AssetRecord]
        var samples: [FaceSample]
        var pending: [PHAsset]
        /// 超出本次上限、留给下一次扫描的张数
        var remaining: Int
        /// 照片 -> 所属自定义相簿名（用于给自动分组按相簿命名）
        var albumNamesByAsset: [String: [String]]
        /// 全部相簿名（含系统相簿），用于识别上一版自动命名的名字
        var previousAlbumNames: Set<String>
    }

    /// 枚举相册、解码缓存、算出待扫描照片 —— 全部在后台线程完成
    private nonisolated func prepare(store: CacheStore, limit: Int) async -> ScanPlan {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.buildPlan(store: store, limit: limit))
            }
        }
    }

    private nonisolated static func buildPlan(store: CacheStore, limit: Int) -> ScanPlan {
        let library = PhotoLibraryService.shared

        let assets = library.fetchAllPhotoAssets()
        var records = store.records

        // 排除相簿
        let excludedIDs = UserDefaults.standard.stringArray(forKey: "excludedAlbumIDs") ?? []
        let excludedAlbums = library.fetchUserAlbums().filter { excludedIDs.contains($0.localIdentifier) }
        let excludedAssetIDs = library.fetchAssetIdentifiers(in: excludedAlbums)

        // 清理已从相册删除的照片记录，避免 records.json 无限增长。
        // 仅在「完全访问」下执行：受限访问时 fetch 只返回用户挑选的照片，
        // 此时清理会误删其余照片的扫描进度。
        if library.authorizationStatus == .authorized {
            let liveIDs = Set(assets.map { $0.localIdentifier })
            let staleIDs = records.keys.filter { !liveIDs.contains($0) }
            for id in staleIDs { records.removeValue(forKey: id) }
        }

        // 增量范围：从未扫描过的 + 内容被修改过（modificationDate 变化）的照片
        let candidates = assets.filter { asset in
            ScanPlanPolicy.needsScan(assetLocalIdentifier: asset.localIdentifier,
                                     modificationDate: asset.modificationDate,
                                     isExcluded: excludedAssetIDs.contains(asset.localIdentifier),
                                     records: records)
        }
        // 单次上限：大相册分批扫，避免长时间占用设备/看起来像卡死。
        // 上限换算与兜底（绝不返回 0/负数）在 ScanBatchPolicy 里：prefix 收到负数会崩溃。
        let (pending, remaining) = ScanBatchPolicy.batch(candidates, limit: limit)

        var samples = store.samples
        // 重扫的照片先丢弃旧的人脸样本，否则同一张脸会重复入库
        let rescanIDs = Set(pending.map { $0.localIdentifier })
        if !rescanIDs.isEmpty {
            samples.removeAll { rescanIDs.contains($0.assetLocalIdentifier) }
        }

        // 「照片 -> 所属相簿名」：用于给自动分组按相簿命名。
        // 必须同时覆盖现有样本与本次待扫描的照片 —— 后者扫完才会产生样本，
        // 但它们的相簿归属现在就能拿到。
        let sampledAssetIDs = Set(samples.map { $0.assetLocalIdentifier })
            .union(pending.map { $0.localIdentifier })
        let albumNamesByAsset = library.albumNames(byAssetLocalIdentifier: sampledAssetIDs,
                                                   excludingAlbumIDs: Set(excludedIDs))
        let previousAlbumNames = library.userAlbumTitles()

        return ScanPlan(records: records,
                        samples: samples,
                        pending: pending,
                        remaining: remaining,
                        albumNamesByAsset: albumNamesByAsset,
                        previousAlbumNames: previousAlbumNames)
    }

    // MARK: - 扫描

    private func run(store: CacheStore, limit: Int) async {
        let plan = await prepare(store: store, limit: limit)
        let pending = plan.pending
        var records = plan.records
        var samples = plan.samples

        total = pending.count
        scanned = 0
        facePhotos = 0
        faceCount = 0
        unavailable = 0
        remaining = plan.remaining

        for asset in pending {
            if stopped || Task.isCancelled { break }
            while paused && !stopped {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            if stopped || Task.isCancelled { break }

            let image = await PhotoLibraryService.shared.cgImage(for: asset,
                                                                targetSize: CGSize(width: 1024, height: 1024))
            var count = 0

            if let image {
                let faces = await detectOffMain(image)
                count = faces.count
                if count > 0 { facePhotos += 1 }
                faceCount += count

                for face in faces {
                    if let crop = detector.cropFace(from: image, boundingBox: face.boundingBox),
                       let feature = await embedOffMain(crop), !feature.isEmpty {
                        samples.append(FaceSample(assetLocalIdentifier: asset.localIdentifier,
                                                  boundingBox: face.boundingBox,
                                                  feature: feature))
                    }
                }
            } else {
                unavailable += 1
            }

            // 取不到图片时不写记录：否则会被当成「已扫描、0 张人脸」而永不再识别
            if let record = ScanRecordPolicy.record(assetLocalIdentifier: asset.localIdentifier,
                                                    modificationDate: asset.modificationDate,
                                                    imageAvailable: image != nil,
                                                    faceCount: count) {
                records[asset.localIdentifier] = record
            }
            scanned += 1

            if scanned % flushInterval == 0 {
                persist(samples: samples, records: records, store: store)
            }
        }

        persist(samples: samples, records: records, store: store)

        // 被用户终止或被系统中断：保留已完成的部分，不做重聚类
        if stopped || Task.isCancelled {
            state = .idle
            return
        }

        // 没有任何新照片时不必重聚类，避免无谓开销并减少覆盖手工修正的机会
        if scanned > 0 {
            await ClusterRebuilder.rebuildInBackground(store: store,
                                                       threshold: Self.currentThreshold(),
                                                       albumNamesByAsset: plan.albumNamesByAsset,
                                                       previousAlbumNames: plan.previousAlbumNames)
        }
        state = .finished
    }

    // MARK: - 聚类

    /// 落盘样本与记录，并记下这些特征是用哪套算法算出来的。
    /// 签名不一致时 `EmbeddingConsistency` 会提示用户全量重扫，
    /// 避免新旧特征混在一起聚类却不报错。
    private func persist(samples: [FaceSample], records: [String: AssetRecord], store: CacheStore) {
        store.samples = samples
        store.records = records
        store.embeddingSignature = FaceEmbeddingService.signature
    }

    private nonisolated static func currentThreshold() -> Float {
        let stored = UserDefaults.standard.object(forKey: "clusterThreshold") as? Double
        return Float(ClusterThreshold.calibrated(stored ?? ClusterThreshold.defaultValue))
    }

    // MARK: - 离主线程计算

    private func detectOffMain(_ image: CGImage) async -> [VNFaceObservation] {
        let detector = self.detector
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let faces = (try? detector.detectFaces(in: image)) ?? []
                continuation.resume(returning: faces)
            }
        }
    }

    private func embedOffMain(_ image: CGImage) async -> [Float]? {
        let embedder = self.embedder
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: try? embedder.embedding(for: image))
            }
        }
    }
}
