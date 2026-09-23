import Foundation
import Photos
import UIKit
import Vision
import Combine

/// 扫描任务协调器（手动全量 / 增量），后台异步、可暂停/终止
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

    private let library = PhotoLibraryService()
    private let detector = FaceDetectionService()
    private let embedder = FaceEmbeddingService()

    private var runTask: Task<Void, Never>?
    private var paused = false
    private var stopped = false

    var progress: Double { total > 0 ? Double(scanned) / Double(total) : 0 }

    // MARK: - 控制

    func start(store: CacheStore, limit: Int = .max) {
        guard state != .scanning else { return }
        state = .scanning
        paused = false
        stopped = false
        runTask = Task { await run(store: store, limit: limit) }
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

    // MARK: - 扫描

    private func run(store: CacheStore, limit: Int) async {
        let assets = library.fetchAllPhotoAssets()
        let records = store.records

        // 排除相簿
        let excludedIDs = UserDefaults.standard.stringArray(forKey: "excludedAlbumIDs") ?? []
        let excludedAlbums = library.fetchUserAlbums().filter { excludedIDs.contains($0.localIdentifier) }
        let excludedAssetIDs = library.fetchAssetIdentifiers(in: excludedAlbums)

        let pending = Array(assets.filter {
            records[$0.localIdentifier] == nil && !excludedAssetIDs.contains($0.localIdentifier)
        }.prefix(limit))

        total = pending.count
        scanned = 0
        facePhotos = 0
        faceCount = 0

        var samples = store.samples
        var newRecords = records

        for asset in pending {
            if stopped { break }
            while paused && !stopped {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            if stopped { break }

            let image = await library.cgImage(for: asset, targetSize: CGSize(width: 1024, height: 1024))
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
            }

            newRecords[asset.localIdentifier] = AssetRecord(assetLocalIdentifier: asset.localIdentifier,
                                                            scannedAt: Date(),
                                                            faceCount: count,
                                                            modificationDate: asset.modificationDate)
            scanned += 1

            if scanned % 5 == 0 {
                store.samples = samples
                store.records = newRecords
            }
        }

        store.samples = samples
        store.records = newRecords
        recluster(store: store)
        if !stopped { state = .finished }
    }

    // MARK: - 聚类

    private func recluster(store: CacheStore) {
        let stored = UserDefaults.standard.object(forKey: "clusterThreshold") as? Double
        let threshold = Float(stored ?? 0.9)
        ClusterRebuilder.rebuild(store: store, threshold: threshold)
    }

    // MARK: - 离主线程计算

    private func detectOffMain(_ image: CGImage) async -> [VNFaceObservation] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let faces = (try? self.detector.detectFaces(in: image)) ?? []
                continuation.resume(returning: faces)
            }
        }
    }

    private func embedOffMain(_ image: CGImage) async -> [Float]? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: try? self.embedder.embedding(for: image))
            }
        }
    }
}
