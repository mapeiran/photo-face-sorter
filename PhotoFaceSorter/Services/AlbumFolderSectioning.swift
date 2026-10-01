import Foundation

/// 把相簿名按系统「照片」App 的文件夹分节（供相簿选择器按文件夹分组展示）。
///
/// 纯函数，便于单测。
enum AlbumFolderSectioning {

    struct Section: Identifiable, Equatable {
        let id: String
        let title: String
        /// 该文件夹里的相簿名（保持传入顺序，一般是按名称排好的）
        let albumTitles: [String]
    }

    /// - Parameters:
    ///   - albumTitles: 相簿名（一般已按名称排序）。
    ///   - folderByAlbumTitle: 相簿名 -> 所属文件夹名。
    ///   - folderOrder: 文件夹顺序（跟随系统）。
    /// - Returns: 按文件夹分好的节；没进文件夹的归「未分组」
    ///   （系统里完全没有文件夹时这一节叫「已有相簿」）。
    static func sections(albumTitles: [String],
                         folderByAlbumTitle: [String: String],
                         folderOrder: [String]) -> [Section] {
        var byFolder: [String: [String]] = [:]
        var ungrouped: [String] = []
        for title in albumTitles {
            if let folder = folderByAlbumTitle[title] {
                byFolder[folder, default: []].append(title)
            } else {
                ungrouped.append(title)
            }
        }

        var sections: [Section] = []
        for folder in folderOrder where byFolder[folder] != nil {
            sections.append(Section(id: "folder:\(folder)",
                                    title: folder,
                                    albumTitles: byFolder.removeValue(forKey: folder) ?? []))
        }
        // 系统顺序里没有提到的文件夹（理论上不会有），按名称补在最后
        for folder in byFolder.keys.sorted() {
            sections.append(Section(id: "folder:\(folder)",
                                    title: folder,
                                    albumTitles: byFolder[folder] ?? []))
        }
        if !ungrouped.isEmpty {
            sections.append(Section(id: "ungrouped",
                                    title: folderOrder.isEmpty ? "已有相簿" : "未分组",
                                    albumTitles: ungrouped))
        }
        return sections
    }
}
