import Foundation

/// 扫描页要展示的「相簿内 / 散图」计数。
///
/// 规则与 `ScanPlanPolicy` 一致：
/// - 自定义相簿里的照片 = 已归类，扫描跳过；
/// - 被排除相簿里的照片两边都不算；
/// - 剩下的就是不在任何相簿中的散图，扫描时会被识别。
///
/// 纯函数，便于单测。
enum LibraryPhotoCountPolicy {

    static func counts(allAssetIDs: Set<String>,
                       albumAssetIDs: Set<String>,
                       excludedAssetIDs: Set<String>) -> LibraryPhotoCounts {
        let loose = allAssetIDs
            .subtracting(albumAssetIDs)
            .subtracting(excludedAssetIDs)
            .count
        return LibraryPhotoCounts(albumPhotos: albumAssetIDs.count, loosePhotos: loose)
    }
}
