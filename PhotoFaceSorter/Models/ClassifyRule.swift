import Foundation

/// 归类动作
enum RuleAction: String, Codable, CaseIterable, Identifiable {
    case copy = "复制到相簿"
    case move = "移动到相簿"
    var id: String { rawValue }

    var isRisky: Bool { self == .move }
}

/// 多人物匹配方式
enum RuleMatchMode: String, Codable, CaseIterable, Identifiable {
    case any = "任一匹配"
    case all = "全部匹配"
    var id: String { rawValue }
}

/// 自动归类规则
struct ClassifyRule: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var enabled: Bool = true
    /// 包含指定人物
    var personIDs: [UUID] = []
    var matchMode: RuleMatchMode = .any
    /// 图片人脸数量下限
    var minFaceCount: Int = 1
    /// 限定来源相簿（nil = 不限）
    var sourceAlbumLocalID: String? = nil
    var action: RuleAction = .copy
    /// 目标相簿名称
    var targetAlbumName: String
    var order: Int = 0
}
