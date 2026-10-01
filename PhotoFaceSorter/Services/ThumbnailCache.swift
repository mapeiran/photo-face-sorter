import UIKit
import Photos

/// 缩略图加载与缓存。
///
/// 原先每个网格 cell 都会新建 `PhotoLibraryService`、按 identifier 重新 fetch，
/// 再按 4× 边长解码一张图，滚动时开销很大。这里统一做三件事：
/// 1. 用 `PHCachingImageManager` 按目标像素尺寸请求，避免解码原图；
/// 2. 用 `NSCache` 缓存已解码（含已按人脸框裁剪）的结果；
/// 3. 缓存 key 包含尺寸与人脸框，避免不同用途互相串图。
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let images = NSCache<NSString, UIImage>()
    private let manager = PHCachingImageManager()
    private let library = PhotoLibraryService.shared

    private init() {
        images.countLimit = 600
    }

    /// 取缩略图。`boundingBox` 非空时按人脸框裁剪。
    func thumbnail(localIdentifier: String, side: CGFloat, boundingBox: CGRect?) async -> UIImage? {
        let pixels = max(1, Int((side * UIScreen.main.scale).rounded(.up)))
        let key = Self.cacheKey(localIdentifier, pixels, boundingBox)
        if let cached = images.object(forKey: key) { return cached }

        guard let asset = library.asset(localIdentifier: localIdentifier),
              let base = await requestImage(for: asset, pixels: pixels) else { return nil }

        let result = boundingBox.flatMap { Self.cropToFace(base, boundingBox: $0) } ?? base
        images.setObject(result, forKey: key)
        return result
    }

    // MARK: - 查看大图

    /// 大图预览：中等尺寸，通常很快（本地已有缩略图缓存时几乎瞬时）。
    /// 先用它填满屏幕，再等原图替换，避免点开就是长时间白屏。
    func preview(localIdentifier: String, maxSide: CGFloat) async -> UIImage? {
        guard let asset = library.asset(localIdentifier: localIdentifier) else { return nil }
        let pixels = max(1, Int((maxSide * UIScreen.main.scale).rounded(.up)))
        return await requestImage(for: asset, pixels: pixels)
    }

    /// 原图（`PHImageManagerMaximumSize`）。iCloud 照片会联网下载，可能较慢。
    /// 原图很大，不放进 `NSCache`，由调用方（看图页）自己持有。
    func original(localIdentifier: String) async -> UIImage? {
        guard let asset = library.asset(localIdentifier: localIdentifier) else { return nil }
        return await requestOriginal(for: asset)
    }

    private func requestOriginal(for asset: PHAsset) async -> UIImage? {
        final class Box { var resumed = false }
        let box = Box()
        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .none
            options.isNetworkAccessAllowed = true
            manager.requestImage(for: asset,
                                 targetSize: PHImageManagerMaximumSize,
                                 contentMode: .aspectFit,
                                 options: options) { image, info in
                // 忽略低清预览，等最终结果；失败（nil）也要 resume，否则页面会一直转圈
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if degraded || box.resumed { return }
                box.resumed = true
                continuation.resume(returning: image)
            }
        }
    }

    private func requestImage(for asset: PHAsset, pixels: Int) async -> UIImage? {
        final class Box { var resumed = false }
        let box = Box()
        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            manager.requestImage(for: asset,
                                 targetSize: CGSize(width: pixels, height: pixels),
                                 contentMode: .aspectFit,
                                 options: options) { image, info in
                // 忽略低清预览，等最终结果
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if degraded || box.resumed { return }
                box.resumed = true
                continuation.resume(returning: image)
            }
        }
    }

    private static func cacheKey(_ localIdentifier: String, _ pixels: Int, _ box: CGRect?) -> NSString {
        let boxPart = box.map { "\($0.minX),\($0.minY),\($0.width),\($0.height)" } ?? "-"
        return "\(localIdentifier)|\(pixels)|\(boxPart)" as NSString
    }

    /// 按归一化人脸框（Vision 坐标系，左下原点）裁剪
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
