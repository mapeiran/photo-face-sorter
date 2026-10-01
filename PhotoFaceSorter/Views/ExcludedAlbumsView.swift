import SwiftUI
import Photos

/// 「排除相簿」配置：手动决定每个相簿是否参与扫描。
///
/// 自定义相簿默认排除（视为已归类），这里可以取消排除让它们重新参与扫描；
/// 系统 / 同步相簿默认参与，也可以手动排除。
struct ExcludedAlbumsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var coordinator: ScanCoordinator
    @State private var albums: [PHAssetCollection] = []
    @State private var searchText = ""

    private var filteredAlbums: [PHAssetCollection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return albums }
        return albums.filter { ($0.localizedTitle ?? "").localizedStandardContains(query) }
    }

    var body: some View {
        List {
            Section {
                if filteredAlbums.isEmpty {
                    Text(searchText.isEmpty ? "没有可选的相簿" : "没有匹配的相簿")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(filteredAlbums, id: \.localIdentifier) { album in
                        Button {
                            toggle(album)
                        } label: {
                            HStack {
                                Text(album.localizedTitle ?? "未命名").foregroundColor(.primary)
                                Spacer()
                                if isExcluded(album) {
                                    Text("已排除")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Image(systemName: "checkmark").foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
            } footer: {
                Text("被排除相簿中的照片在扫描时会被跳过（如截图、表情、下载等）。"
                     + "自定义相簿默认排除，点一下即可取消排除、重新参与扫描。")
            }
        }
        .navigationTitle("排除相簿")
        .searchable(text: $searchText, prompt: "搜索相簿")
        .onAppear {
            albums = PhotoLibraryService().fetchUserAlbums().sorted {
                AlbumTitleOrdering.isOrderedBefore($0.localizedTitle, $1.localizedTitle)
            }
        }
    }

    private func isExcluded(_ album: PHAssetCollection) -> Bool {
        model.isAlbumExcludedFromScan(localID: album.localIdentifier,
                                      isCustom: album.assetCollectionSubtype == .albumRegular)
    }

    private func toggle(_ album: PHAssetCollection) {
        model.setAlbumExcludedFromScan(!isExcluded(album),
                                       localID: album.localIdentifier,
                                       isCustom: album.assetCollectionSubtype == .albumRegular)
        coordinator.refreshLibraryCounts()
    }
}
