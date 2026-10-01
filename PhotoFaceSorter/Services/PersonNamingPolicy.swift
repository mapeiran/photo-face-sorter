import Foundation

/// 用相簿名决定人物归属。
///
/// 背景：Vision 的 `VNGenerateImageFeaturePrintRequest` 是通用图像特征而不是身份特征，
/// 自动聚类只能大致分组。用户往往早已按人把照片放进了自定义相簿（相簿名就是人名），
/// 所以归类时**相簿优先**：照片在哪个自定义相簿里，就归到以该相簿命名的人物；
/// AI 聚类只用来处理没有相簿的照片。
enum PersonNamingPolicy {

    /// 一张照片应该归到哪个人物（由它所属的相簿名决定）。
    ///
    /// 照片同时在多个自定义相簿里时，选**最专有**的那个（样本集里成员最少的相簿），
    /// 避免「全家福 / 旅行」这类大杂烩相簿盖过「妈妈」这种人物相簿；
    /// 成员数相同则按名称排序取最小，保证结果稳定可复现。
    ///
    /// - Parameters:
    ///   - assetLocalIdentifier: 照片标识。
    ///   - albumNamesByAsset: 照片 -> 所属自定义相簿名（可能为空数组）。
    ///   - albumMemberCounts: 相簿名 -> 它覆盖的照片数。
    ///   - existingNames: 本轮开始时**已经存在**的人物名。照片同时在多个「像人名」的
    ///     相簿里时优先复用它们，让识别到的分组并入同名 / 同相簿的已有人物，
    ///     而不是被「最专有」的新相簿另立一个分组。
    /// - Returns: 相簿名；没有相簿信息时返回 nil（交给 AI 聚类）。
    static func albumName(assetLocalIdentifier: String,
                          albumNamesByAsset: [String: [String]],
                          albumMemberCounts: [String: Int],
                          existingNames: Set<String> = []) -> String? {
        let names = Set(albumNamesByAsset[assetLocalIdentifier] ?? []).filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }

        // 1) 有已存在的人物名时只在其中选：强化「同相簿 / 同名就合并」
        let reusable = names.intersection(existingNames)
        let candidates = reusable.isEmpty ? names : reusable

        // 2) 再选成员最少（最专有）的，避免大杂烩相簿盖过具体人物
        return candidates.min { lhs, rhs in
            let left = albumMemberCounts[lhs] ?? Int.max
            let right = albumMemberCounts[rhs] ?? Int.max
            return left == right ? lhs < rhs : left < right
        }
    }
}
