import Foundation

/// 决定哪些照片需要参与本次扫描。
///
/// 与 `ScanRecordPolicy` 配合构成完整闭环：
/// 取不到图片时不写记录 → 这里下次仍判定为「需要扫描」，于是自动重试。
enum ScanPlanPolicy {

    /// 这张照片是否需要扫描。
    ///
    /// - Parameter isExcluded: 是否属于被排除的相簿。
    /// - Parameter isInAlbum: 是否属于某个**自定义相簿**。用户把照片放进相簿
    ///   就说明已经分好类了，不必再跑人脸识别 —— 扫描只处理「散图」。
    static func needsScan(assetLocalIdentifier: String,
                          modificationDate: Date?,
                          isExcluded: Bool,
                          isInAlbum: Bool = false,
                          records: [String: AssetRecord]) -> Bool {
        guard !isExcluded else { return false }
        guard !isInAlbum else { return false }
        guard let record = records[assetLocalIdentifier] else { return true }
        // 新增的会走到上面；这里覆盖「内容被修改过」的照片
        return record.modificationDate != modificationDate
    }
}
