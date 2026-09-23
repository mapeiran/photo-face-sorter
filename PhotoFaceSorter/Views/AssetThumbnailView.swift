import SwiftUI
import Photos

/// 异步加载照片缩略图；可选按人脸框裁剪
struct AssetThumbnailView: View {
    let localIdentifier: String
    var boundingBox: CGRect? = nil
    var contentMode: ContentMode = .fill
    var side: CGFloat = 80

    @State private var image: UIImage?

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
        .task(id: localIdentifier) { await load() }
    }

    private func load() async {
        guard image == nil else { return }
        let library = PhotoLibraryService()
        guard let asset = library.fetchAssets(localIdentifiers: [localIdentifier]).first else { return }
        let target = CGSize(width: side * 4, height: side * 4)
        guard let cg = await library.cgImage(for: asset, targetSize: target) else { return }
        var ui = UIImage(cgImage: cg)
        if let box = boundingBox {
            ui = Self.cropToFace(ui, boundingBox: box) ?? ui
        }
        await MainActor.run { image = ui }
    }

    static func cropToFace(_ image: UIImage, boundingBox: CGRect) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let width = CGFloat(cg.width)
        let height = CGFloat(cg.height)
        // Vision 归一化（左下原点）→ 像素（左上原点）
        let x = boundingBox.minX * width
        let y = (1 - boundingBox.maxY) * height
        let w = boundingBox.width * width
        let h = boundingBox.height * height
        let rect = CGRect(x: x, y: y, width: w, height: h)
            .insetBy(dx: -w * 0.3, dy: -h * 0.3)
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard rect.width > 1, rect.height > 1, let cropped = cg.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped)
    }
}
