import SwiftUI

/// 异步加载照片缩略图；可选按人脸框裁剪。
/// 实际加载与缓存由 `ThumbnailCache` 负责，这里只处理视图状态。
struct AssetThumbnailView: View {
    let localIdentifier: String
    var boundingBox: CGRect? = nil
    var contentMode: ContentMode = .fill
    var side: CGFloat = 80

    @State private var image: UIImage?
    @State private var loadedKey: String?

    private var requestKey: String {
        let box = boundingBox.map { "\($0.minX),\($0.minY),\($0.width),\($0.height)" } ?? "-"
        return "\(localIdentifier)|\(side)|\(box)"
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color(.secondarySystemBackground)
                    .overlay(Image(systemName: "photo").foregroundColor(.secondary))
            }
        }
        .frame(width: side, height: side)
        .clipped()
        .task(id: requestKey) { await load() }
    }

    private func load() async {
        // 同一个视图被复用到另一张照片时必须重新加载，否则会残留上一张的缩略图
        let key = requestKey
        guard loadedKey != key else { return }
        let loaded = await ThumbnailCache.shared.thumbnail(localIdentifier: localIdentifier,
                                                           side: side,
                                                           boundingBox: boundingBox)
        await MainActor.run {
            image = loaded
            loadedKey = key
        }
    }
}
