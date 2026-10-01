import SwiftUI
import Photos

/// 选择一个系统相簿（可新建）作为移动目标。
struct AlbumPickerView: View {
    let title: String
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var albums: [PHAssetCollection] = []
    @State private var newName = ""
    @State private var searchText = ""
    @State private var folderByTitle: [String: String] = [:]
    @State private var folderOrder: [String] = []
    /// 已展开的文件夹（默认收起，也可以一键展开/收起）
    @State private var expandedFolders: Set<String> = []

    /// 搜索过滤后的已有相簿（保持按名称排序）
    private var filteredAlbums: [PHAssetCollection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return albums }
        return albums.filter { ($0.localizedTitle ?? "").localizedStandardContains(query) }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 按系统「照片」App 的文件夹分节（没有文件夹时就是「已有相簿」一节）
    private var sections: [AlbumFolderSectioning.Section] {
        AlbumFolderSectioning.sections(
            albumTitles: filteredAlbums.compactMap { $0.localizedTitle },
            folderByAlbumTitle: folderByTitle,
            folderOrder: folderOrder)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("新建相簿名称", text: $newName)
                        Button("创建") { create() }
                            .disabled(trimmedNewName.isEmpty)
                    }
                } header: {
                    Text("新建相簿")
                } footer: {
                    Text("移动会把照片从其它相簿移除（原图不会删除），并记入执行日志，可回退。")
                }

                if sections.isEmpty {
                    Section {
                        Text(trimmedSearchText.isEmpty ? "没有可选的相簿" : "没有匹配的相簿")
                            .foregroundColor(.secondary)
                    }
                } else {
                    ForEach(sections) { section in
                        DisclosureGroup(isExpanded: expansionBinding(for: section.id)) {
                            ForEach(section.albumTitles, id: \.self) { albumTitle in
                                albumRow(albumTitle)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "folder").foregroundColor(.accentColor)
                                Text(section.title).font(.subheadline).bold()
                                Spacer()
                                Text("\(section.albumTitles.count) 个相簿")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // 搜索时可以直接用关键词新建相簿
                if !trimmedSearchText.isEmpty,
                   !albums.contains(where: { $0.localizedTitle == trimmedSearchText }) {
                    Section {
                        Button {
                            pick(trimmedSearchText)
                        } label: {
                            Label("新建相簿「\(trimmedSearchText)」", systemImage: "plus.circle")
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索相簿")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button("展开全部") { expandedFolders = Set(sections.map(\.id)) }
                        Button("折叠全部") { expandedFolders.removeAll() }
                    } label: {
                        Image(systemName: "rectangle.expand.vertical")
                    }
                    .disabled(sections.isEmpty)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                // 系统相簿按名称排序（中文按本地化顺序、名字里的数字按数值），再按系统文件夹分节
                albums = PhotoLibraryService().fetchUserAlbums().sorted {
                    AlbumTitleOrdering.isOrderedBefore($0.localizedTitle, $1.localizedTitle)
                }
                let grouping = PhotoLibraryService().albumFolderGrouping()
                folderByTitle = grouping.folderByAlbumTitle
                folderOrder = grouping.folderOrder
            }
        }
    }

    /// 文件夹展开状态：搜索时强制展开，方便直接看到匹配的相簿
    private func expansionBinding(for sectionID: String) -> Binding<Bool> {
        Binding(
            get: { !trimmedSearchText.isEmpty || expandedFolders.contains(sectionID) },
            set: { expanded in
                if expanded {
                    expandedFolders.insert(sectionID)
                } else {
                    expandedFolders.remove(sectionID)
                }
            })
    }

    private func albumRow(_ albumTitle: String) -> some View {
        Button {
            pick(albumTitle)
        } label: {
            HStack {
                Image(systemName: "rectangle.stack")
                    .foregroundColor(.accentColor)
                Text(albumTitle.isEmpty ? "未命名" : albumTitle)
                    .foregroundColor(.primary)
            }
        }
    }

    private var trimmedNewName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func create() {
        let name = trimmedNewName
        guard !name.isEmpty else { return }
        onPick(name)
        dismiss()
    }

    private func pick(_ name: String) {
        guard !name.isEmpty else { return }
        onPick(name)
        dismiss()
    }
}
