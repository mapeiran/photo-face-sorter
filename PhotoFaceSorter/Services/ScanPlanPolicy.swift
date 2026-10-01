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
}
