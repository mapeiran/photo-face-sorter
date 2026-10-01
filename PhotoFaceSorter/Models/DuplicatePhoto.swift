import Foundation

/// 重复图片分组里的一张照片（只带展示需要的元数据）。
struct DuplicateAsset: Identifiable, Equatable, Sendable {
    /// PHAsset localIdentifier
    let id: String
    var creationDate: Date?
    var pixelWidth: Int
    var pixelHeight: Int
    /// 原始文件字节数（用于统计可省空间）
    var byteSize: Int64

    var dimensionsText: String { "\(pixelWidth) × \(pixelHeight)" }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }
}

/// 一组视觉重复的照片（成员数一定 > 1）。
struct DuplicateGroup: Identifiable, Equatable, Sendable {
    /// 组内第一张（按创建时间）的标识，保证同一批结果里 id 稳定
    let id: String
    var assets: [DuplicateAsset]

    /// 保留其中最大的一张时可省下的字节数
    var wastedBytes: Int64 {
        let total = assets.reduce(Int64(0)) { $0 + $1.byteSize }
        return max(0, total - (assets.map(\.byteSize).max() ?? 0))
    }

    var largest: DuplicateAsset? {
        assets.max { $0.byteSize < $1.byteSize }
    }
}

/// 一次重复检测的结果。
struct DuplicateDetectionResult: Sendable {
    var groups: [DuplicateGroup]
    /// 成功算出感知哈希的张数
    var analyzed: Int
    /// 读不到原图（多为 iCloud 未下载）而跳过的张数
    var skipped: Int
    /// 参与检测的照片总数
    var total: Int
}
