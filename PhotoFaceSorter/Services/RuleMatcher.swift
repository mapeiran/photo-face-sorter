import Foundation

/// 规则匹配的纯逻辑。
///
/// 特意与 `RuleEngine` 分开：这里不依赖 PhotoKit，可以直接用假数据做单元测试
/// （也可以在无模拟器环境下编译执行）。
enum RuleMatcher {

    /// 匹配规则的照片标识。
    ///
    /// - Parameter albumMembership: 给定照片标识返回其所属用户相簿标识集合。
    ///   仅当规则限定了「来源相簿」时才会被调用。
    static func matchedAssetIDs(for rule: ClassifyRule,
                                samples: [FaceSample],
                                records: [String: AssetRecord],
                                albumMembership: ((String) -> Set<String>)? = nil) -> [String] {
        var assetPersons: [String: Set<UUID>] = [:]
        for sample in samples {
            guard let personID = sample.personID, !sample.isIgnored else { continue }
            assetPersons[sample.assetLocalIdentifier, default: []].insert(personID)
        }

        let target = Set(rule.personIDs)

        // 候选照片的取法取决于是不是限定了人物：
        // - 不限人物时，「人脸数量」以扫描记录为准，包含尚未归属到任何人物的人脸，
        //   否则「人脸数量 ≥ N」这条独立条件会永远匹配不到东西；
        // - 限定人物时，候选照片必须至少有一张归属到所选人物的人脸。
        let candidates: [String]
        if target.isEmpty {
            candidates = records.compactMap { $0.value.faceCount >= rule.minFaceCount ? $0.key : nil }
        } else {
            candidates = Array(assetPersons.keys)
        }

        var result: [String] = []

        for assetID in candidates {
            guard let record = records[assetID], record.faceCount >= rule.minFaceCount else { continue }

            if !target.isEmpty {
                let persons = assetPersons[assetID] ?? []
                let matched = rule.matchMode == .all
                    ? target.isSubset(of: persons)
                    : !target.isDisjoint(with: persons)
                if !matched { continue }
            }

            // 限定来源相簿时，没有过滤器就不能放行 —— 否则会退化成「不过滤」，
            // 把不属于该相簿的照片也归类过去。
            if let sourceAlbumID = rule.sourceAlbumLocalID {
                guard let albumMembership, albumMembership(assetID).contains(sourceAlbumID) else { continue }
            }

            result.append(assetID)
        }

        return result.sorted()
    }
}
