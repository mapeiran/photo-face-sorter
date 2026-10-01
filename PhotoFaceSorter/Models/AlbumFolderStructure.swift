import Foundation

/// 系统「照片」App 的文件夹 / 相簿结构快照，供人物页按文件夹分节展示。
///
/// 与「有哪些人物」无关：这里只描述系统相册本身的结构，
/// 所以即使某个文件夹/相簿还没有识别出人物，也能照常展示。
struct AlbumFolderStructure: Equatable {
    /// 全部文件夹名，顺序跟随系统（含没有相簿的空文件夹；嵌套文件夹扁平列出）
    var folderOrder: [String] = []
    /// 文件夹名 -> 其中的相簿名（按系统顺序，只含**直接**子相簿）
    var albumsByFolder: [String: [String]] = [:]
    /// 相簿名 -> 所属文件夹名（嵌套文件夹取最近一层；不在任何文件夹里则没有条目）
    var folderByAlbumTitle: [String: String] = [:]
    /// 不在任何文件夹里的自定义相簿名，按系统顺序
    var ungroupedAlbumTitles: [String] = []
    /// 相簿名 -> 展示摘要（张数 / 封面），用于「还没有对应人物」的相簿单元格
    var summaries: [String: AlbumSummary] = [:]
    /// 相簿名 -> localIdentifier，用于「是否排除此相簿」等按相簿操作
    var localIdentifierByAlbumTitle: [String: String] = [:]
    /// 用户自建相簿（`.albumRegular`）的 localIdentifier；它们默认不参与扫描
    var customAlbumLocalIDs: Set<String> = []

    static let empty = AlbumFolderStructure()

    var isEmpty: Bool {
        folderOrder.isEmpty && ungroupedAlbumTitles.isEmpty
    }
}

/// 相簿的展示摘要。只取便宜的信息（估计张数 + 关键照片），
/// 不为展示去逐张枚举整个相簿。
struct AlbumSummary: Equatable {
    var photoCount: Int
    var coverLocalIdentifier: String?
}

/// 「相簿内照片 / 不在相簿中的散图」两类计数，用于扫描页说明扫描范围。
struct LibraryPhotoCounts: Equatable, Sendable {
    /// 在自定义相簿里的照片数（扫描会跳过）
    var albumPhotos: Int
    /// 不在任何相簿中、会被识别的散图数（被排除相簿的照片不算）
    var loosePhotos: Int
}
