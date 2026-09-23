import Foundation

/// 已扫描照片记录（用于增量扫描，避免重复识别）
struct AssetRecord: Codable, Identifiable, Hashable {
    var id: String { assetLocalIdentifier }
    var assetLocalIdentifier: String
    var scannedAt: Date
    var faceCount: Int
    /// 照片修改时间（用于判断变更）
    var modificationDate: Date?
}
