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
    private let clusterer = FaceClusteringService()

    private var runTask: Task<Void, Never>?
    private var paused = false
    private var stopped = false

    var progress: Double { total > 0 ? Double(scanned) / Double(total) : 0 }

    // MARK: - 控制

    func start(store: CacheStore) {
        guard state != .scanning else { return }
        state = .scanning
        paused = false
        stopped = false
        runTask = Task { await run(store: store) }
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

    private func run(store: CacheStore) async {
        let assets = library.fetchAllPhotoAssets()
        let records = store.records
        let pending = assets.filter { records[$0.localIdentifier] == nil }

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
        var samples = store.samples
        let features = samples.map { $0.feature }
        let assignments = clusterer.cluster(features: features, threshold: 0.9)

        var people = store.people
        var clusterToPerson: [Int: UUID] = [:]

        // 先按已有样本归属投票，尽量保留已命名的人物
        var votes: [Int: [UUID: Int]] = [:]
        for (index, cluster) in assignments.enumerated() where cluster >= 0 {
            if let personID = samples[index].personID {
                votes[cluster, default: [:]][personID, default: 0] += 1
            }
        }
        for (cluster, tally) in votes {
            if let (personID, _) = tally.max(by: { $0.value < $1.value }) {
                clusterToPerson[cluster] = personID
            }
        }

        for (index, cluster) in assignments.enumerated() {
            guard cluster >= 0 else { continue }
            if let personID = clusterToPerson[cluster] {
                samples[index].personID = personID
            } else {
                let person = Person(name: "人物 \(people.count + 1)")
                people.append(person)
                clusterToPerson[cluster] = person.id
                samples[index].personID = person.id
            }
        }

        // 清理没有任何样本的人物
        let usedPersonIDs = Set(samples.compactMap { $0.personID })
        people = people.filter { usedPersonIDs.contains($0.id) }

        store.people = people
        store.samples = samples
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
