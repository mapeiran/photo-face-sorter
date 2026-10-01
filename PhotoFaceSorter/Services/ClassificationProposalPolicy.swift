import Foundation

/// 「归类审核」的提议生成：把**不在任何相簿**的人脸样本按人物分组。
///
/// 纯函数，便于单测；PhotoKit 查询（哪些照片已在相簿里）由调用方注入。
enum ClassificationProposalPolicy {

    /// - Parameters:
    ///   - people: 现有人物（顺序即展示顺序）。
    ///   - samples: 全部人脸样本。
    ///   - albumedAssetIDs: 已经在任意用户相簿里的照片标识（这些不需要再归类）。
    ///   - existingAlbumTitles: 已存在的用户相簿名（用于判断「新建」还是「已有」）。
    /// - Returns: 只为「有散图的人物」生成提议。
    static func proposals(people: [Person],
                          samples: [FaceSample],
                          albumedAssetIDs: Set<String>,
                          existingAlbumTitles: Set<String>) -> [PendingClassification] {
        var seen = Set<String>()
        var assetsByPerson: [UUID: [String]] = [:]
        for sample in samples {
            guard let personID = sample.personID, !sample.isIgnored else { continue }
            let asset = sample.assetLocalIdentifier
            guard !albumedAssetIDs.contains(asset) else { continue }
            let key = "\(personID.uuidString)|\(asset)"
            if seen.insert(key).inserted {
                assetsByPerson[personID, default: []].append(asset)
            }
        }

        return people.compactMap { person in
            guard let assets = assetsByPerson[person.id], !assets.isEmpty else { return nil }
            let name = person.displayName
            return PendingClassification(personID: person.id,
                                         personName: name,
                                         assetIDs: assets,
                                         targetAlbumName: name,
                                         albumExists: existingAlbumTitles.contains(name))
        }
    }
}
