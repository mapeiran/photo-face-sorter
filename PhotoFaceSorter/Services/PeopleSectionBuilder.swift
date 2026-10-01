import Foundation

/// 人物页的分节逻辑：按系统「照片」App 的文件夹分节，
/// 在每个文件夹下**列出其中所有相簿** —— 已经有对应人物的显示成人物卡片，
/// 还没识别出人物的显示成相簿卡片（不丢结构）。
///
/// 纯函数，不碰 PhotoKit，可在单元测试里直接验证。
enum PeopleSectionBuilder {

    struct Section: Identifiable, Equatable {
        let id: String
        let title: String
        /// 该节里已有对应人物的分组（保持输入顺序，输入一般已按名字排好）
        let people: [Person]
        /// 该节里还没有对应人物的相簿名（按系统顺序）
        let albumTitles: [String]

        var isEmpty: Bool { people.isEmpty && albumTitles.isEmpty }
    }

    /// - Parameters:
    ///   - people: 现有人物分组，通常已按名字排序。
    ///   - structure: 系统相册的文件夹 / 相簿结构快照。
    /// - Returns: 文件夹节（顺序跟随系统）、未分组节、最后的 AI 分组节。
    static func sections(people: [Person],
                         structure: AlbumFolderStructure) -> [Section] {
        // 同名人物只认第一个，避免重名时同一相簿被展示两次
        var personByName: [String: Person] = [:]
        for person in people where personByName[person.name] == nil {
            personByName[person.name] = person
        }

        var usedPersonIDs = Set<UUID>()
        var sections: [Section] = []

        // 1) 系统里每一个文件夹各一节（含空文件夹）
        for folder in structure.folderOrder {
            let albumTitles = structure.albumsByFolder[folder] ?? []
            let sectionPeople = people.filter { person in
                guard structure.folderByAlbumTitle[person.name] == folder else { return false }
                usedPersonIDs.insert(person.id)
                return true
            }
            let albumCells = albumTitles.filter { personByName[$0] == nil }
            sections.append(Section(id: "folder:\(folder)",
                                    title: folder,
                                    people: sectionPeople,
                                    albumTitles: albumCells))
        }

        // 2) 不在任何文件夹里的相簿（跟着它们的人物一起），
        //    系统里完全没有文件夹时它就是唯一的相簿节。
        let ungroupedSet = Set(structure.ungroupedAlbumTitles)
        let ungroupedPeople = people.filter { ungroupedSet.contains($0.name) }
        usedPersonIDs.formUnion(ungroupedPeople.map(\.id))
        let ungroupedCells = structure.ungroupedAlbumTitles.filter { personByName[$0] == nil }
        if !ungroupedPeople.isEmpty || !ungroupedCells.isEmpty {
            sections.append(Section(id: "ungrouped",
                                    title: structure.folderOrder.isEmpty ? "相簿" : "未分组",
                                    people: ungroupedPeople,
                                    albumTitles: ungroupedCells))
        }

        // 3) 没有任何相簿对应的人物 = AI 分组
        let aiPeople = people.filter { !usedPersonIDs.contains($0.id) }
        if !aiPeople.isEmpty {
            sections.append(Section(id: "ai",
                                    title: "AI 分组（没有相簿）",
                                    people: aiPeople,
                                    albumTitles: []))
        }

        return sections
    }
}
