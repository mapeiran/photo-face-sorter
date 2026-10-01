import Foundation

/// 规则执行器：按 order 顺序执行启用中的规则
final class RuleRunner {
    private let engine = RuleEngine()

    func runAll(rules: [ClassifyRule],
                samples: [FaceSample],
                records: [String: AssetRecord]) async -> RuleOutcome {
        var logs: [ExecutionLog] = []
        var moved = 0
        var copied = 0
        var failures: [RuleFailure] = []

        // 只在规则真的限定了来源相簿时才会真正查询相册
        let membership = engine.photoKitAlbumMembership()

        for rule in rules.sorted(by: { $0.order < $1.order }) where rule.enabled {
            let ids = engine.matchedAssetIDs(for: rule,
                                             samples: samples,
                                             records: records,
                                             albumMembership: membership)
            guard !ids.isEmpty else { continue }

            do {
                // 匹配到的照片都已在目标相簿里时 execute 返回 nil：没有实际改动，不记日志
                if let log = try await engine.execute(rule: rule, assetIDs: ids) {
                    logs.append(log)
                    // 用「本次真正新增的张数」，而不是匹配总数
                    let count = log.assetLocalIdentifiers.count
                    if rule.action == .move { moved += count } else { copied += count }
                }
            } catch {
                // 不再吞掉错误：失败的规则要如实告诉用户
                failures.append(RuleFailure(ruleID: rule.id,
                                            ruleName: rule.name,
                                            reason: error.localizedDescription))
            }
        }

        return RuleOutcome(logs: logs,
                           movedCount: moved,
                           copiedCount: copied,
                           failures: failures)
    }

    /// 预览所有启用规则匹配的总张数
    func previewCount(rules: [ClassifyRule],
                      samples: [FaceSample],
                      records: [String: AssetRecord]) -> Int {
        let membership = engine.photoKitAlbumMembership()
        var total = 0
        for rule in rules where rule.enabled {
            total += engine.matchedAssetIDs(for: rule,
                                            samples: samples,
                                            records: records,
                                            albumMembership: membership).count
        }
        return total
    }
}
