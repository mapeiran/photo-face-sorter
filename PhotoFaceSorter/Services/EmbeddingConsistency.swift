import Foundation

/// 判断已缓存的人脸特征是不是用「当前这套特征提取方式」算出来的。
///
/// 为什么必须有这个检查：一旦特征提取方式变了（换模型、换 Vision revision、
/// 改变输出维度），新旧特征就**不可比**。混在一起聚类会得到毫无意义的分组，
/// 而且不会报任何错 —— 用户只会觉得「这个 App 分得乱七八糟」。
///
/// 有了签名记录，这种情况会变成一句明确的提示 + 一次全量重扫。
enum EmbeddingConsistency {

    enum Status: Equatable {
        /// 还没有任何样本人脸，无需担心
        case notScanned
        /// 签名一致，缓存可用
        case consistent
        /// 签名不一致：必须全量重扫，否则聚类结果是垃圾
        case needsFullRescan(stored: String, current: String)
    }

    /// - Parameter storedSignature: 生成已缓存样本时记录的签名；nil 表示旧版本没记录过。
    static func status(storedSignature: String?,
                       currentSignature: String,
                       sampleCount: Int) -> Status {
        guard sampleCount > 0 else { return .notScanned }

        // 旧版本没有写签名，而它们的样本正是当前这套算法算出来的 ——
        // 直接视为一致并补记，避免升级时对所有老用户误报「需要重扫」。
        guard let storedSignature else { return .consistent }

        return storedSignature == currentSignature
            ? .consistent
            : .needsFullRescan(stored: storedSignature, current: currentSignature)
    }
}
