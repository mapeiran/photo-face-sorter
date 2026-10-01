import SwiftUI
import Photos

/// 系统相簿详情：展示相簿里的照片，点开可全屏查看。
///
/// 人物页里「还没有对应人物」的相簿（事件相簿、还没扫到的相簿等）走这里，
/// 保证系统相册的相簿结构在 App 里都能点进去看。
struct AlbumDetailView: View {
    let albumTitle: String

    @State private var identifiers: [String] = []
    @State private var loading = true
    @State private var preview: Preview?

    private struct Preview: Identifiable {
        let id = UUID()
        let index: Int
    }

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 6)]

    var body: some View {
        Group {
            if loading {
                ProgressView("正在读取相簿…")
            } else if identifiers.isEmpty {
                ContentUnavailableView("相簿是空的", systemImage: "rectangle.stack")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(identifiers.indices, id: \.self) { index in
                            Button {
                                preview = Preview(index: index)
                            } label: {
                                AssetThumbnailView(localIdentifier: identifiers[index],
                                                   contentMode: .fill,
                                                   side: 88)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(albumTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .fullScreenCover(item: $preview) { preview in
            PhotoViewerView(assetIdentifiers: identifiers, initialIndex: preview.index)
        }
    }

    private func load() async {
        let ids = await Task.detached(priority: .userInitiated) {
            let library = PhotoLibraryService.shared
            guard let album = library.album(named: albumTitle) else { return [String]() }
            return library.fetchAssets(in: album).map { $0.localIdentifier }
        }.value
        identifiers = ids
        loading = false
    }
}
