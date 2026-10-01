import Foundation

/// 「归类审核」里的一条待确认提议：某个人物名下有若干**不在任何相簿**的照片，
/// 建议写入（已有则复用、没有则新建）目标相簿，由用户确认。
struct PendingClassification: Identifiable, Equatable, Sendable {
    var personID: UUID
    var personName: String
    /// 待归类的散图（localIdentifier，已去重）
    var assetIDs: [String]
    /// 目标系统相簿名
    var targetAlbumName: String
    /// 目标相簿是否已存在（false = 会新建）
    var albumExists: Bool

    var id: UUID { personID }
}
