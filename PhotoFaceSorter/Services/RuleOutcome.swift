import Foundation

/// 某条规则执行失败的原因
struct RuleFailure: Identifiable, Hashable {
    var id: UUID { ruleID }
    var ruleID: UUID
    var ruleName: String
    var reason: String
}

/// 一轮规则执行的结果。
///
/// 单独放在这里（不嵌在 `RuleRunner` 内）是为了让它只依赖 Foundation，
/// 从而可以在没有模拟器的环境下直接编译执行测试。
struct RuleOutcome {
    var logs: [ExecutionLog]
    var movedCount: Int
    var copiedCount: Int
    /// 执行失败的规则。以前用 `try?` 把错误吞掉，界面上只会看到一个偏小的成功数字，
    /// 用户根本不知道有规则没跑成功。
    var failures: [RuleFailure]

    /// 面向用户的总结文案（含失败原因）
    var summary: String {
        var text = "已执行 \(logs.count) 条规则：复制 \(copiedCount) 张，移动 \(movedCount) 张"
        guard !failures.isEmpty else { return text }
        text += "\n\n\(failures.count) 条规则未能执行："
        for failure in failures {
            text += "\n· \(failure.ruleName)：\(failure.reason)"
        }
        return text
    }
}
