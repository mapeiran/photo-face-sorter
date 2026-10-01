import SwiftUI

/// 用 `.sheet(item:)` 弹出照片详情的目标（照片 localIdentifier 不是 Identifiable）。
struct PhotoDetailTarget: Identifiable {
    let id: String
}

/// 照片详情：类型、尺寸、时间、位置、文件名，并提供「在系统相册中打开」。
struct PhotoDetailView: View {
    let assetLocalIdentifier: String

    @Environment(\.dismiss) private var dismiss
    @State private var detail: PhotoDetail?

    var body: some View {
        NavigationStack {
            List {
                if let detail {
                    Section("基本信息") {
                        labeled("类型", detail.mediaTypeText)
                        labeled("尺寸", detail.dimensionsText)
                        labeled("收藏", detail.isFavorite ? "是" : "否")
                        labeled("拍摄时间", Self.dateText(detail.creationDate))
                        labeled("修改时间", Self.dateText(detail.modificationDate))
                        if let location = detail.locationText {
                            labeled("位置", location)
                        }
                    }
                    if !detail.resourceFileNames.isEmpty {
                        Section("文件") {
                            ForEach(detail.resourceFileNames, id: \.self) { name in
                                Text(name).font(.subheadline)
                            }
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在读取详情…").foregroundColor(.secondary)
                    }
                }

                Section {
                    Button {
                        PhotoLibraryService.searchSystemPhotos(
                            forAssetLocalIdentifier: assetLocalIdentifier)
                    } label: {
                        Label("在「照片」中按日期搜索", systemImage: "photo.on.rectangle.angled")
                    }
                    Button {
                        PhotoLibraryService.openSystemPhotosApp()
                    } label: {
                        Label("打开「照片」App", systemImage: "photo.on.rectangle")
                    }
                } footer: {
                    Text("iOS 没有公开接口能直接定位到某一张照片（能直开的 photos:// 是私有 scheme，"
                         + "外部 App 会被系统拒绝）。「按日期搜索」会打开「照片」的搜索并填入拍摄日期，"
                         + "显示当天的照片，再自己找到那张。")
                }
            }
            .navigationTitle("照片详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .task {
                let identifier = assetLocalIdentifier
                detail = await Task.detached(priority: .userInitiated) {
                    PhotoLibraryService.shared.photoDetail(localIdentifier: identifier)
                }.value
            }
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundColor(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }

    private static func dateText(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
