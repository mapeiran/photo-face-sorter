import Foundation

/// 把「人物」分组的照片写入系统相簿。
///
/// 复用 RuleEngine 的复制 / 移动语义：复制只增不改；移动会从其它相簿移除（原图不动）。
/// 返回一条 ExecutionLog，所以能在「执行日志」里看到、也能回退。
enum PersonAlbumExporter {

    struct Outcome: Sendable {
        var albumName: String
        var addedCount: Int
        var action: RuleAction
        var log: ExecutionLog?

        var summary: String {
            if addedCount == 0 {
                return "这些照片都已经在系统相簿「\(albumName)」里了，没有需要新增的。"
            }
            let verb = action == .move ? "移动" : "复制"
            return "已\(verb) \(addedCount) 张到系统相簿「\(albumName)」。"
        }
    }

    /// - Parameters:
    ///   - personName: 相簿名（也是人物名）；不存在会新建。
    ///   - assetIDs: 该人物所有照片的 localIdentifier（内部去重）。
    ///   - action: copy 只加入相簿；move 额外从其它相簿移除。
    static func export(personName: String,
                       assetIDs: [String],
                       action: RuleAction) async throws -> Outcome {
        let uniqueIDs = Array(Set(assetIDs))
        let rule = ClassifyRule(name: personName, action: action, targetAlbumName: personName)
        let log = try await RuleEngine().execute(rule: rule, assetIDs: uniqueIDs)
        return Outcome(albumName: personName,
                       addedCount: log?.assetLocalIdentifiers.count ?? 0,
                       action: action,
                       log: log)
    }
}
