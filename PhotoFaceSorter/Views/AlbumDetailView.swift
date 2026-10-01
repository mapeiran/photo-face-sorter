import SwiftUI
import Photos

/// 系统相簿详情：展示相簿里的照片，点开可全屏查看。
///
/// 人物页里「还没有对应人物」的相簿（事件相簿、还没扫到的相簿等）走这里，
/// 保证系统相册的相簿结构在 App 里都能点进去看。
struct AlbumDetailView: View {
    let albumTitle: String

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var coordinator: ScanCoordinator

    @State private var identifiers: [String] = []
    @State private var loading = true
    @State private var preview: Preview?
    @State private var detailTarget: PhotoDetailTarget?
    /// 单张照片 -> 移到系统相簿
    @State private var albumPickAssetID: String?
    @State private var albumMessage: String?

    private struct Preview: Identifiable {
        let id = UUID()
        let index: Int
    }

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 6)]

    /// 能否修改扫描排除状态（相簿要能在系统相册结构里找到）
    private var canToggleScanExclusion: Bool {
        model.albumLocalIdentifier(title: albumTitle) != nil
    }

    private var isExcludedFromScan: Bool {
        model.isAlbumExcludedFromScan(title: albumTitle)
    }

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
                            .contextMenu {
                                Button {
                                    detailTarget = PhotoDetailTarget(id: identifiers[index])
                                } label: {
                                    Label("查看详情", systemImage: "info.circle")
                                }
                                Button {
                                    PhotoLibraryService.openSystemPhotosApp()
                                } label: {
                                    Label("在系统相册中打开", systemImage: "photo.on.rectangle")
                                }
                                Button {
                                    albumPickAssetID = identifiers[index]
                                } label: {
                                    Label("移到系统相簿…", systemImage: "rectangle.stack.badge.minus")
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(albumTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    model.setAlbumExcludedFromScan(!isExcludedFromScan, title: albumTitle)
                    coordinator.refreshLibraryCounts()
                } label: {
                    Label(isExcludedFromScan ? "取消排除，参与扫描" : "从扫描中排除",
                          systemImage: isExcludedFromScan ? "eye" : "eye.slash")
                }
                .disabled(!canToggleScanExclusion)
            }
        }
        .safeAreaInset(edge: .top) {
            if isExcludedFromScan {
                Text("此相簿已从扫描中排除：里面的照片不会被识别。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.08))
            }
        }
        .task { await load() }
        .fullScreenCover(item: $preview) { preview in
            PhotoViewerView(assetIdentifiers: identifiers, initialIndex: preview.index)
        }
        .sheet(item: $detailTarget) { target in
            PhotoDetailView(assetLocalIdentifier: target.id)
        }
        .sheet(isPresented: Binding(get: { albumPickAssetID != nil },
                                    set: { if !$0 { albumPickAssetID = nil } })) {
            AlbumPickerView(title: "移到系统相簿") { albumName in
                if let id = albumPickAssetID { moveToAlbum(id: id, albumName: albumName) }
            }
        }
        .alert("完成",
               isPresented: Binding(get: { albumMessage != nil },
                                    set: { if !$0 { albumMessage = nil } })) {
            Button("好", role: .cancel) { albumMessage = nil }
        } message: {
            Text(albumMessage ?? "")
        }
    }

    /// 把单张照片移到选定的系统相簿
    private func moveToAlbum(id: String, albumName: String) {
        Task {
            albumMessage = await model.moveAssetsToAlbum([id], albumName: albumName)
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
