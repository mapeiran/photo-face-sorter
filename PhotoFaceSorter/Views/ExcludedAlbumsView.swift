import SwiftUI
import Photos

struct ExcludedAlbumsView: View {
    @State private var albums: [PHAssetCollection] = []
    @State private var selected: Set<String> = []

    var body: some View {
        List {
            Section {
                if albums.isEmpty {
                    Text("没有可选的相簿").foregroundColor(.secondary)
                } else {
                    ForEach(albums, id: \.localIdentifier) { album in
                        Button {
                            toggle(album)
                        } label: {
                            HStack {
                                Text(album.localizedTitle ?? "未命名").foregroundColor(.primary)
                                Spacer()
                                if selected.contains(album.localIdentifier) {
                                    Image(systemName: "checkmark").foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
            } footer: {
                Text("被排除相簿中的照片在扫描时会被跳过（如截图、表情、下载等）。")
            }
        }
        .navigationTitle("排除相簿")
        .onAppear {
            albums = PhotoLibraryService().fetchUserAlbums()
            selected = Set(UserDefaults.standard.stringArray(forKey: "excludedAlbumIDs") ?? [])
        }
        .onChange(of: selected) { _, newValue in
            UserDefaults.standard.set(Array(newValue), forKey: "excludedAlbumIDs")
        }
    }

    private func toggle(_ album: PHAssetCollection) {
        if selected.contains(album.localIdentifier) {
            selected.remove(album.localIdentifier)
        } else {
            selected.insert(album.localIdentifier)
        }
    }
}
