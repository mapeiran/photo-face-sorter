import Foundation

/// 人物分组
struct Person: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    /// 封面人脸样本
    var coverSampleID: UUID? = nil
    /// 屏蔽（不再归类）
    var isHidden: Bool = false
    /// 名字是否由「按相簿名命名」自动写入。
    ///
    /// 必须是可选类型：Swift 合成的 `Decodable` 不会为非可选属性使用默认值，
    /// 旧缓存里没有这个键，声明为 `Bool = false` 会让整份 people.json 解码失败。
    /// - `nil` / `false`：用户自己起的名（或旧数据）—— 重聚类绝不改动；
    /// - `true`：自动写入的相簿名 —— 相簿变了要重新推导。
    var nameIsAuto: Bool? = nil

    var displayName: String {
        name.isEmpty ? "未命名" : name
    }
}
