import Photos
import UIKit
import CoreGraphics

/// 相册读取与相簿管理（PhotoKit）
final class PhotoLibraryService {

    func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    var authorizationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    // MARK: - 读取

    /// 全部照片（静态图片）
    func fetchAllPhotoAssets() -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    /// 用户相簿列表
    func fetchUserAlbums() -> [PHAssetCollection] {
        let result = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        var albums: [PHAssetCollection] = []
        result.enumerateObjects { collection, _, _ in albums.append(collection) }
        return albums
    }

    /// 某相簿内照片
    func fetchAssets(in album: PHAssetCollection) -> [PHAsset] {
        let result = PHAsset.fetchAssets(in: album, options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    func fetchAssets(localIdentifiers: [String]) -> [PHAsset] {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    // MARK: - 相簿

    func createOrFetchAlbum(named name: String) -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", name)
        let existing = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options)
        if let collection = existing.firstObject { return collection }

        var placeholder: PHObjectPlaceholder?
        do {
            try PHPhotoLibrary.shared().performChangesAndWait {
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
                placeholder = request.placeholderForCreatedAssetCollection
            }
        } catch {
            return nil
        }
        guard let localID = placeholder?.localIdentifier else { return nil }
        return PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [localID], options: nil).firstObject
    }

    func add(_ assets: [PHAsset], to album: PHAssetCollection) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            guard let request = PHAssetCollectionChangeRequest(for: album) else { return }
            request.addAssets(assets as NSArray)
        }
    }

    func remove(_ assets: [PHAsset], from album: PHAssetCollection) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            guard let request = PHAssetCollectionChangeRequest(for: album) else { return }
            request.removeAssets(assets as NSArray)
        }
    }

    // MARK: - 图像

    func cgImage(for asset: PHAsset, targetSize: CGSize) async -> CGImage? {
        final class Box { var resumed = false }
        let box = Box()
        return await withCheckedContinuation { (continuation: CheckedContinuation<CGImage?, Never>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(for: asset,
                                                  targetSize: targetSize,
                                                  contentMode: .aspectFit,
                                                  options: options) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if degraded || box.resumed { return }
                box.resumed = true
                continuation.resume(returning: image?.cgImage)
            }
        }
    }

    func thumbnail(for asset: PHAsset, size: CGSize) async -> UIImage? {
        final class Box { var resumed = false }
        let box = Box()
        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(for: asset,
                                                  targetSize: size,
                                                  contentMode: .aspectFill,
                                                  options: options) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if degraded || box.resumed { return }
                box.resumed = true
                continuation.resume(returning: image)
            }
        }
    }
}
