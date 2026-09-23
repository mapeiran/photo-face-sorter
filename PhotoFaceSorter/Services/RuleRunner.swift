import Foundation

/// 规则执行器：按顺序执行启用中的规则
final class RuleRunner {
    private let engine = RuleEngine()

    struct Outcome {
        var logs: [ExecutionLog]
        var movedCount: Int
        var copiedCount: Int
    }

    func runAll(rules: [ClassifyRule],
                samples: [FaceSample],
                records: [String: AssetRecord],
                store: CacheStore) async -> Outcome {
        var logs: [ExecutionLog] = []
        var moved = 0
        var copied = 0

        for rule in rules where rule.enabled {
            let ids = engine.matchedAssetIDs(for: rule, samples: samples, records: records)
            guard !ids.isEmpty else { continue }
            if let log = try? await engine.execute(rule: rule, assetIDs: ids, store: store) {
                logs.append(log)
                if rule.action == .move { moved += ids.count } else { copied += ids.count }
            }
        }
        return Outcome(logs: logs, movedCount: moved, copiedCount: copied)
    }

    /// 预览所有启用规则匹配的总张数
    func previewCount(rules: [ClassifyRule],
                      samples: [FaceSample],
                      records: [String: AssetRecord]) -> Int {
        var total = 0
        for rule in rules where rule.enabled {
            total += engine.matchedAssetIDs(for: rule, samples: samples, records: records).count
        }
        return total
    }
}
