import Foundation
import Photos
import ImageIO
import CoreGraphics

/// 扫描整个照片库、按感知哈希找出视觉重复的照片。
///
/// 只做识别，**不删除**任何照片。iCloud 未下载的照片
/// （`isNetworkAccessAllowed = false`）会被跳过并计数，避免触发大量下载。
enum DuplicateDetector {

    /// 汉明距离阈值：64 位里最多差这么多位就算视觉重复。
    static let hammingThreshold = 6

    struct Fingerprint: Sendable {
        var localIdentifier: String
        var hash: UInt64
        var byteSize: Int64
        var creationDate: Date?
        var pixelWidth: Int
        var pixelHeight: Int
    }

    /// - Parameter progress: 已分析 / 总数；回主线程更新界面。
    static func detect(progress: @MainActor @Sendable (Int, Int) -> Void) async -> DuplicateDetectionResult {
        let assets = PhotoLibraryService.shared.fetchAllPhotoAssets()
        let total = assets.count
        var fingerprints: [Fingerprint] = []
        var skipped = 0

        for (index, asset) in assets.enumerated() {
            if Task.isCancelled {
                return DuplicateDetectionResult(groups: [], analyzed: fingerprints.count,
                                                skipped: skipped, total: total)
            }
            if let fingerprint = await fingerprint(for: asset) {
                fingerprints.append(fingerprint)
            } else {
                skipped += 1
            }
            if index % 8 == 0 { await progress(index + 1, total) }
        }
        await progress(total, total)

        let ids = DuplicateGroupingPolicy.groups(
            hashes: fingerprints.map { (id: $0.localIdentifier, hash: $0.hash) },
            threshold: hammingThreshold)

        var byID: [String: Fingerprint] = [:]
        for fingerprint in fingerprints where byID[fingerprint.localIdentifier] == nil {
            byID[fingerprint.localIdentifier] = fingerprint
        }

        let groups: [DuplicateGroup] = ids.compactMap { identifiers in
            var members: [DuplicateAsset] = []
            for id in identifiers {
                guard let fingerprint = byID[id] else { continue }
                members.append(DuplicateAsset(id: id,
                                              creationDate: fingerprint.creationDate,
                                              pixelWidth: fingerprint.pixelWidth,
                                              pixelHeight: fingerprint.pixelHeight,
                                              byteSize: fingerprint.byteSize))
            }
            guard members.count > 1 else { return nil }
            members.sort { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
            return DuplicateGroup(id: members[0].id, assets: members)
        }

        return DuplicateDetectionResult(groups: groups,
                                        analyzed: fingerprints.count,
                                        skipped: skipped,
                                        total: total)
    }

    private static func fingerprint(for asset: PHAsset) async -> Fingerprint? {
        // 先取出需要的元数据，避免在回调里捕获 PHAsset
        let identifier = asset.localIdentifier
        let creationDate = asset.creationDate
        let pixelWidth = asset.pixelWidth
        let pixelHeight = asset.pixelHeight

        final class Box { var resumed = false }
        let box = Box()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Fingerprint?, Never>) in
            let options = PHImageRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = false
            PHImageManager.default().requestImageDataAndOrientation(for: asset,
                                                                    options: options) { data, _, _, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if degraded || box.resumed { return }
                box.resumed = true

                guard let data,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                          kCGImageSourceCreateThumbnailFromImageAlways: true,
                          kCGImageSourceCreateThumbnailWithTransform: true,
                          kCGImageSourceThumbnailMaxPixelSize: 64
                      ] as CFDictionary) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Fingerprint(localIdentifier: identifier,
                                                           hash: PerceptualHash.dHash(from: image),
                                                           byteSize: Int64(data.count),
                                                           creationDate: creationDate,
                                                           pixelWidth: pixelWidth,
                                                           pixelHeight: pixelHeight))
            }
        }
    }
}
