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
    var rolledBack: Bool = false
}
