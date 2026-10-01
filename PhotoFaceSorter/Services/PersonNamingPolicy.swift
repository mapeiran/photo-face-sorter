import Foundation

/// 用已有相簿名给自动分组命名。
///
/// 背景：Vision 的 `VNGenerateImageFeaturePrintRequest` 是通用图像特征而不是身份特征，
/// 自动聚类只能大致分组（实测同一批照片的最大平方距离只有 0.19）。
/// 用户往往早已按人把照片放进了相簿（相簿名就是人名），
/// 于是让相簿名反过来给自动分组命名，比「人物 N」更贴近用户自己的组织方式。
enum PersonNamingPolicy {

    /// 从该人物所有照片所属的相簿名里，挑出现次数最多的一个。
    ///
    /// - Parameters:
    ///   - assetLocalIdentifiers: 该人物包含的照片；同一张照片上的多张脸只算一次。
    ///   - albumNamesByAsset: 照片 -> 所属用户相簿名（可能为空数组）。
    /// - Returns: 出现次数最多的相簿名；完全没有相簿信息时为 nil（保留「人物 N」）。
    ///   次数相同时按名称排序取最小的一个，保证结果可复现。
    static func dominantAlbumName(assetLocalIdentifiers: [String],
                                  albumNamesByAsset: [String: [String]]) -> String? {
        var counts: [String: Int] = [:]
        for assetID in Set(assetLocalIdentifiers) {
            // 同一张照片在多个相簿里的名字各记一次
            for name in Set(albumNamesByAsset[assetID] ?? []) where !name.isEmpty {
                counts[name, default: 0] += 1
            }
        }
        return counts.max { lhs, rhs in
            // 次数不同取次数多的；次数相同取名称较小的，避免结果随字典顺序变化
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }?.key
    }
}
