import SwiftUI
import Photos

/// 选择一个系统相簿（可新建）作为移动目标。
struct AlbumPickerView: View {
    let title: String
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var albums: [PHAssetCollection] = []
    @State private var newName = ""

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
                    if albums.isEmpty {
                        Text("没有可选的相簿").foregroundColor(.secondary)
                    } else {
                        ForEach(albums, id: \.localIdentifier) { album in
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
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear { albums = PhotoLibraryService().fetchUserAlbums() }
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
