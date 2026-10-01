import Foundation

/// 规则执行时决定「本次真正需要新增哪些照片」。
///
/// 为什么要单独算一次，而不是把匹配到的照片整批塞进相簿：
/// 1. **回退的正确性**：日志只记录*本次真正新增*的照片，
///    回退时才不会把别的规则（或用户自己）放进该相簿的照片一并删掉；
/// 2. **避免无谓的相册写入**：规则反复执行时，已在相簿里的照片不必再 add；
/// 3. **日志体积**：匹配 2 万张却一张都没新增时，不该再追加一条 2 万条 ID 的记录。
enum RuleExecutionPolicy {

    /// 只保留还不在目标相簿里的照片，保持原有顺序并去重。
    static func newlyAdded(candidateIDs: [String], existingInAlbum: Set<String>) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in candidateIDs where !existingInAlbum.contains(id) && seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }
}
