import Foundation

/// 缓存元信息。
struct CacheMeta: Codable {
    /// 生成已缓存样本人脸所用的特征提取方式标识。
    ///
    /// 必须是可选类型：Swift 合成的 `Decodable` 不会为非可选属性使用默认值，
    /// 旧缓存里没有这个键，声明为非可选会让整份 meta 解码失败。
    var embeddingSignature: String?
}
