import Foundation

/// 决定哪些照片需要参与本次扫描。
///
/// 与 `ScanRecordPolicy` 配合构成完整闭环：
/// 取不到图片时不写记录 → 这里下次仍判定为「需要扫描」，于是自动重试。
enum ScanPlanPolicy {

    /// 这张照片是否需要扫描。
    ///
    /// - Parameter isExcluded: 是否属于「扫描排除」的相簿。用户把照片放进相簿、
    ///   或手动排除了某个相簿，就说明这些照片已经分好类，不必再跑人脸识别 ——
    ///   扫描只处理散图。排除名单由 `AlbumExclusionStore` 决定
    ///   （自定义相簿默认排除，可手动取消）。
    static func needsScan(assetLocalIdentifier: String,
                          modificationDate: Date?,
                          isExcluded: Bool,
                          records: [String: AssetRecord]) -> Bool {
        guard !isExcluded else { return false }
        guard let record = records[assetLocalIdentifier] else { return true }
        // 新增的会走到上面；这里覆盖「内容被修改过」的照片
        return record.modificationDate != modificationDate
    }

    /// 这张照片是否应该被本次扫描挑中。
    ///
    /// 在增量判定之外还排掉「**已忽略 / 已跳过**」的照片：用户在归类页跳过的那张，
    /// 重扫时也不该复活（跳过名单持久化在 `ClassificationSkipStore`，清缓存不会丢）。
    static func shouldScan(assetLocalIdentifier: String,
                           modificationDate: Date?,
                           isExcluded: Bool,
                           ignoredAssetIDs: Set<String>,
                           records: [String: AssetRecord]) -> Bool {
        guard !ignoredAssetIDs.contains(assetLocalIdentifier) else { return false }
        return needsScan(assetLocalIdentifier: assetLocalIdentifier,
                         modificationDate: modificationDate,
                         isExcluded: isExcluded,
                         records: records)
    }
}
