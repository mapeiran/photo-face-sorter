import Foundation

/// 决定哪些照片需要参与本次扫描。
///
/// 与 `ScanRecordPolicy` 配合构成完整闭环：
/// 取不到图片时不写记录 → 这里下次仍判定为「需要扫描」，于是自动重试。
/// 一次扫描覆盖哪些照片。
enum ScanScope: Sendable, Equatable {
    /// 默认增量：只扫**不在相簿里**的散图
    case loosePhotos
    /// 只扫**相簿内**的照片（重新识别，刷新「按相簿命名」的人脸锚点）
    case albumPhotos
    /// 全部照片：散图 + 相簿内（「全量重扫」用）
    case allPhotos

    /// 这个范围是不是「**主动重新识别**」：忽略增量记录，范围内的照片全部重认一遍。
    ///
    /// 只有 `.albumPhotos` 是 —— 它就是「重新识别相簿内照片」这个动作本身。
    /// 普通增量扫描不受影响（扫过且没改过的照片仍然跳过）。
    var forcesRescan: Bool { self == .albumPhotos }

    /// 这张照片是否落在本次范围内（只看「在不在相簿里」）
    func contains(isInAlbum: Bool) -> Bool {
        switch self {
        case .loosePhotos: return !isInAlbum
        case .albumPhotos: return isInAlbum
        case .allPhotos:   return true
        }
    }
}

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

    /// 「本次范围」× 「增量判定」的合并判断。
    ///
    /// 注意 `isExcluded` 的语义：相簿内的照片在默认范围下算「已归类、跳过」，
    /// 但在 `.albumPhotos` / `.allPhotos` 范围下是被**主动要求**重新识别的，
    /// 不能再按排除处理，否则会出现「选了重新识别却一张都不扫」。
    static func shouldScan(assetLocalIdentifier: String,
                           modificationDate: Date?,
                           isInAlbum: Bool,
                           scope: ScanScope,
                           records: [String: AssetRecord]) -> Bool {
        guard scope.contains(isInAlbum: isInAlbum) else { return false }
        // 主动重新识别不看增量记录：即使扫过、没改过，也要重新提一遍特征
        if scope.forcesRescan { return true }
        return needsScan(assetLocalIdentifier: assetLocalIdentifier,
                         modificationDate: modificationDate,
                         isExcluded: isInAlbum && scope == .loosePhotos,
                         records: records)
    }
}
