import Foundation

/// 规则执行日志
struct ExecutionLog: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var ruleID: UUID
    var ruleName: String
    var date: Date = Date()
    var action: RuleAction
    var targetAlbumName: String
    var assetLocalIdentifiers: [String]
    /// 「移动」动作中被移出的来源相簿，回退时用于还原。
    ///
    /// 这里必须是可选类型：Swift 合成的 `Decodable` 不会为非可选属性使用默认值，
    /// 旧版本写入的 `logs.json` 中没有该键，声明为 `[String] = []` 会导致
    /// 整份日志解码失败并被 `CacheStore` 静默丢弃。
    var sourceAlbumLocalIDs: [String]? = nil
    var rolledBack: Bool = false
}
