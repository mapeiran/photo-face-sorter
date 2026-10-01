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

    /// 搜索过滤后的已有相簿（保持按名称排序）
    private var filteredAlbums: [PHAssetCollection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return albums }
        return albums.filter { ($0.localizedTitle ?? "").localizedStandardContains(query) }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
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

                Section("已有相簿") {
                    if filteredAlbums.isEmpty {
                        Text(trimmedSearchText.isEmpty ? "没有可选的相簿" : "没有匹配的相簿")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(filteredAlbums, id: \.localIdentifier) { album in
                            Button {
                                pick(album.localizedTitle ?? "")
                            } label: {
                                HStack {
                                    Image(systemName: "rectangle.stack")
                                        .foregroundColor(.accentColor)
                                    Text(album.localizedTitle ?? "未命名")
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                    }
                    // 搜索时可以直接用关键词新建相簿
                    if !trimmedSearchText.isEmpty,
                       !albums.contains(where: { $0.localizedTitle == trimmedSearchText }) {
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                // 系统相簿按名称排序（中文按本地化顺序、名字里的数字按数值）
                albums = PhotoLibraryService().fetchUserAlbums().sorted {
                    AlbumTitleOrdering.isOrderedBefore($0.localizedTitle, $1.localizedTitle)
                }
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
