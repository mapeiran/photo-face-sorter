import Foundation
import Photos

/// 自动归类规则引擎
final class RuleEngine {
    private let library = PhotoLibraryService()

    /// 匹配规则的照片（不执行，用于测试预览）
    ///
    /// - Parameter albumMembership: 给定照片标识，返回它所属的用户相簿标识集合。
    ///   仅当规则限定了「来源相簿」时才会被调用，避免无谓地逐张查询相册。
    ///   留空表示不做来源相簿过滤（也便于单元测试注入假数据）。
    func matchedAssetIDs(for rule: ClassifyRule,
                         samples: [FaceSample],
                         records: [String: AssetRecord],
                         albumMembership: ((String) -> Set<String>)? = nil) -> [String] {
        RuleMatcher.matchedAssetIDs(for: rule,
                                    samples: samples,
                                    records: records,
                                    albumMembership: albumMembership)
    }

    /// 基于 PhotoKit 的「来源相簿」过滤器。
    /// 返回的闭包只在规则真的限定了来源相簿时才会被调用。
    func photoKitAlbumMembership() -> (String) -> Set<String> {
        let library = self.library
        return { assetID in
            guard let asset = library.asset(localIdentifier: assetID) else { return [] }
            let collections = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
            var ids = Set<String>()
            collections.enumerateObjects { collection, _, _ in ids.insert(collection.localIdentifier) }
            return ids
        }
    }

    /// 执行规则：复制/移动照片到目标相簿
    ///
    /// - Returns: 执行日志。若匹配到的照片**都已经在该相簿里**，返回 nil ——
    ///   既没有实际改动，也就不该产生日志（否则反复执行会无限膨胀日志，
    ///   而且回退时会把不是本次新增的照片一起删掉）。
    func execute(rule: ClassifyRule, assetIDs: [String]) async throws -> ExecutionLog? {
        let assets = library.fetchAssets(localIdentifiers: assetIDs)
        guard let album = library.createOrFetchAlbum(named: rule.targetAlbumName) else {
            throw NSError(domain: "RuleEngine", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "无法创建目标相簿"])
        }

        let alreadyInAlbum = Set(library.fetchAssets(in: album).map { $0.localIdentifier })
        let newIDs = Set(RuleExecutionPolicy.newlyAdded(candidateIDs: assetIDs,
                                                        existingInAlbum: alreadyInAlbum))
        let newAssets = assets.filter { newIDs.contains($0.localIdentifier) }
        guard !newAssets.isEmpty else { return nil }

        try await library.add(newAssets, to: album)

        // 「移动」：把照片从其它用户相簿中移除。
        // PhotoKit 没有真正的「移动」语义 —— 原始照片始终留在系统图库中，
        // 这里改变的只是相簿归属；记录被移出的来源相簿，回退时可以还原。
        var sourceAlbumIDs: [String] = []
        if rule.action == .move {
            let sources = library.albumsContaining(newAssets, excluding: album)
            sourceAlbumIDs = sources.map { $0.localIdentifier }
            for source in sources {
                try? await library.remove(newAssets, from: source)
            }
        }

        return ExecutionLog(ruleID: rule.id,
                            ruleName: rule.name,
                            action: rule.action,
                            targetAlbumName: rule.targetAlbumName,
                            // 只记录本次真正新增的照片，回退才精确
                            assetLocalIdentifiers: newAssets.map { $0.localIdentifier },
                            sourceAlbumLocalIDs: sourceAlbumIDs)
    }

    /// 回退归类：从目标相簿移除；「移动」的额外还原回原来的来源相簿
    func rollback(log: ExecutionLog) async throws {
        let assets = library.fetchAssets(localIdentifiers: log.assetLocalIdentifiers)

        if let album = library.album(named: log.targetAlbumName) {
            try await library.remove(assets, from: album)
        }

        for source in library.albums(localIdentifiers: log.sourceAlbumLocalIDs ?? []) {
            try await library.add(assets, to: source)
        }
    }
}
