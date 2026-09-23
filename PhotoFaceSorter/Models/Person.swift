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

    var displayName: String {
        name.isEmpty ? "未命名" : name
    }
}
