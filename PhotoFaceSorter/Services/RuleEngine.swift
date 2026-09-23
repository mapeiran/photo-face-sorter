import Foundation
import Photos

/// 自动归类规则引擎
final class RuleEngine {
    private let library = PhotoLibraryService()

    /// 匹配规则的照片（不执行，用于测试预览）
    func matchedAssetIDs(for rule: ClassifyRule,
                         samples: [FaceSample],
                         records: [String: AssetRecord]) -> [String] {
        var assetPersons: [String: Set<UUID>] = [:]
        for sample in samples {
            guard let personID = sample.personID, !sample.isIgnored else { continue }
            assetPersons[sample.assetLocalIdentifier, default: []].insert(personID)
        }

        let target = Set(rule.personIDs)
        var result: [String] = []

        for (assetID, persons) in assetPersons {
            guard let record = records[assetID], record.faceCount >= rule.minFaceCount else { continue }
            if !target.isEmpty {
                let matched = rule.matchMode == .all
                    ? target.isSubset(of: persons)
                    : !target.isDisjoint(with: persons)
                if !matched { continue }
            }
            result.append(assetID)
        }
        return result.sorted()
    }

    /// 执行规则：复制/移动照片到目标相簿
    func execute(rule: ClassifyRule, assetIDs: [String], store: CacheStore) async throws -> ExecutionLog {
        let assets = library.fetchAssets(localIdentifiers: assetIDs)
        guard let album = library.createOrFetchAlbum(named: rule.targetAlbumName) else {
            throw NSError(domain: "RuleEngine", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "无法创建目标相簿"])
        }

        try await library.add(assets, to: album)

        // 「移动」模式：从来源相簿移除（需已知来源相簿）
        if rule.action == .move, let sourceID = rule.sourceAlbumLocalID {
            let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [sourceID], options: nil)
            if let source = collections.firstObject {
                try? await library.remove(assets, from: source)
            }
        }

        return ExecutionLog(ruleID: rule.id,
                            ruleName: rule.name,
                            action: rule.action,
                            targetAlbumName: rule.targetAlbumName,
                            assetLocalIdentifiers: assetIDs)
    }

    /// 回退归类（从目标相簿移除）
    func rollback(log: ExecutionLog) async throws {
        let assets = library.fetchAssets(localIdentifiers: log.assetLocalIdentifiers)
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", log.targetAlbumName)
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options)
        guard let album = collections.firstObject else { return }
        try await library.remove(assets, from: album)
    }
}
