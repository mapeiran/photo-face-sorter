import Foundation

/// 单张照片的详情（全部是可展示的文本，便于跨线程传递与单测）。
struct PhotoDetail: Equatable, Sendable {
    var mediaTypeText: String
    var pixelWidth: Int
    var pixelHeight: Int
    var isFavorite: Bool
    var creationDate: Date?
    var modificationDate: Date?
    /// 经纬度文本（没有定位信息时为 nil）
    var locationText: String?
    /// 底层资源文件名（原图 / 编辑后 / 实况视频等）
    var resourceFileNames: [String]

    var dimensionsText: String { "\(pixelWidth) × \(pixelHeight)" }
}
