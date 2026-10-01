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
    /// 执行顺序（越小越先执行）
    var order: Int = 0
}

/// 规则排序
enum RuleOrdering {

    /// 复刻 SwiftUI `List.onMove` 的语义：把 `source` 位置的规则移动到 `destination` 之前，
    /// 然后按新顺序重新编号 `order`。
    ///
    /// `destination` 是「移动之前」的插入下标，因此需要扣掉已被移走、且原本位于它之前的元素个数。
    static func reordered(_ rules: [ClassifyRule],
                          from source: IndexSet,
                          to destination: Int) -> [ClassifyRule] {
        guard !source.isEmpty else { return renumbered(rules) }

        var moving: [ClassifyRule] = []
        var remaining: [ClassifyRule] = []
        for (index, rule) in rules.enumerated() {
            if source.contains(index) {
                moving.append(rule)
            } else {
                remaining.append(rule)
            }
        }

        let removedBefore = source.filter { $0 < destination }.count
        let insertAt = max(0, min(remaining.count, destination - removedBefore))

        var result = remaining
        result.insert(contentsOf: moving, at: insertAt)
        return renumbered(result)
    }

    /// 按数组顺序重新编号 `order`
    static func renumbered(_ rules: [ClassifyRule]) -> [ClassifyRule] {
        var result = rules
        for index in result.indices {
            result[index].order = index
        }
        return result
    }
}
