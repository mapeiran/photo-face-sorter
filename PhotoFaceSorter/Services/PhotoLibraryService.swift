import Photos
import UIKit
import CoreGraphics

/// 相册读取与相簿管理（PhotoKit）
/// 无状态，可安全地在任意线程上使用
final class PhotoLibraryService: Sendable {

    static let shared = PhotoLibraryService()

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

    /// 用户相簿列表（含系统同步/导入生成的相簿）
    func fetchUserAlbums() -> [PHAssetCollection] {
        let result = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        var albums: [PHAssetCollection] = []
        result.enumerateObjects { collection, _, _ in albums.append(collection) }
        return albums
    }

    /// 所有用户相簿的名字（含系统同步 / 导入生成的相簿）。
    ///
    /// 用途：识别「上一版是按相簿名自动命名的人物」。这些名字是可重新推导的，
    /// 不应当成用户手写的名字永久保留（那时还没有 `Person.nameIsAuto` 标记）。
    func userAlbumTitles() -> Set<String> {
        Set(fetchUserAlbums().compactMap { $0.localizedTitle }.filter { !$0.isEmpty })
    }

    /// **自定义**相簿：用户在「照片」App 里自己建的（`.albumRegular`）。
    ///
    /// 只有这种相簿才用来给人物命名。系统自己生成的相簿（iTunes/iCloud 同步相簿、
    /// 导入相簿等）属于系统组织方式，不是用户对「谁是谁」的标注，
    /// 拿它们的名字命名会得到「最近项目」这种莫名其妙的人物。
    /// 注意：智能相簿（`.smartAlbum`）本来就不在 `.album` 类型里，天然被排除。
    func fetchCustomAlbums() -> [PHAssetCollection] {
        let result = PHAssetCollection.fetchAssetCollections(with: .album,
                                                             subtype: .albumRegular,
                                                             options: nil)
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

    func asset(localIdentifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject
    }

    /// 汇总若干相簿内所有照片的标识（用于排除）
    func fetchAssetIdentifiers(in albums: [PHAssetCollection]) -> Set<String> {
        var ids = Set<String>()
        for album in albums {
            let result = PHAsset.fetchAssets(in: album, options: nil)
            result.enumerateObjects { asset, _, _ in ids.insert(asset.localIdentifier) }
        }
        return ids
    }

    /// 「人脸照片 -> 所属**自定义**相簿名」，用于按相簿名给人物自动命名。
    ///
    /// 只收集 `assetIDs`（有人脸的照片）的归属，避免为大相册里没人脸的照片
    /// 白白建立映射。按相簿遍历而不是逐张查询，相册数量远少于照片数量。
    /// 只认自定义相簿 `fetchCustomAlbums()`：系统生成的相簿不参与命名。
    /// - Parameter excludingAlbumIDs: 被排除的相簿（它们不参与扫描，名字也不该拿来命名）。
    func albumNames(byAssetLocalIdentifier assetIDs: Set<String>,
                    excludingAlbumIDs: Set<String> = []) -> [String: [String]] {
        guard !assetIDs.isEmpty else { return [:] }
        var result: [String: [String]] = [:]
        for album in fetchCustomAlbums() {
            guard !excludingAlbumIDs.contains(album.localIdentifier),
                  let title = album.localizedTitle, !title.isEmpty else { continue }
            PHAsset.fetchAssets(in: album, options: nil).enumerateObjects { asset, _, _ in
                guard assetIDs.contains(asset.localIdentifier) else { return }
                result[asset.localIdentifier, default: []].append(title)
            }
        }
        return result
    }

    // MARK: - 相簿

    /// 按名称查找已存在的用户相簿
    func album(named name: String) -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", name)
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options).firstObject
    }

    func albums(localIdentifiers ids: [String]) -> [PHAssetCollection] {
        guard !ids.isEmpty else { return [] }
        let result = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: ids, options: nil)
        var found: [PHAssetCollection] = []
        result.enumerateObjects { collection, _, _ in found.append(collection) }
        return found
    }

    /// 包含这些照片的用户相簿（排除 `excluding` 指定的相簿），用于「移动」动作
    func albumsContaining(_ assets: [PHAsset], excluding excluded: PHAssetCollection?) -> [PHAssetCollection] {
        var seen = Set<String>()
        var result: [PHAssetCollection] = []
        for asset in assets {
            let collections = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
            collections.enumerateObjects { collection, _, _ in
                guard collection.localIdentifier != excluded?.localIdentifier,
                      seen.insert(collection.localIdentifier).inserted else { return }
                result.append(collection)
            }
        }
        return result
    }

    func createOrFetchAlbum(named name: String) -> PHAssetCollection? {
        if let existing = album(named: name) { return existing }

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

    /// 按目标尺寸取图（缩略图请走 `ThumbnailCache`，它带缓存与像素尺寸换算）
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
}
