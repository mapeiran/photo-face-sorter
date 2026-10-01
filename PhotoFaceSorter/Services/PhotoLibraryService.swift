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

    /// 系统「照片」App 的完整文件夹 / 相簿结构。
    ///
    /// 人物页按它分节 —— 你在照片 App 里把相簿归到「家人」「同事」这类文件夹时，
    /// App 里也按同样的分组展示。和旧版的区别：**空文件夹也会返回**，
    /// 并且每个文件夹都带上其中的相簿（即使那些相簿还没有识别出人物）。
    /// 只取文件夹的直接子相簿，嵌套文件夹取最近的一层。
    /// 相簿标题在「照片」里是唯一的，所以用标题做键就够了，不必再存相簿 ID。
    func albumFolderStructure() -> AlbumFolderStructure {
        var structure = AlbumFolderStructure()

        // 1) 全部文件夹（含空文件夹），顺序跟随系统
        let folders = PHCollectionList.fetchCollectionLists(with: .folder, subtype: .any, options: nil)
        folders.enumerateObjects { folder, _, _ in
            guard let folderTitle = folder.localizedTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !folderTitle.isEmpty else { return }
            if !structure.folderOrder.contains(folderTitle) { structure.folderOrder.append(folderTitle) }

            var childTitles = structure.albumsByFolder[folderTitle] ?? []
            PHCollection.fetchCollections(in: folder, options: nil).enumerateObjects { collection, _, _ in
                guard let album = collection as? PHAssetCollection,
                      let title = album.localizedTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !title.isEmpty else { return }
                if structure.folderByAlbumTitle[title] == nil {
                    structure.folderByAlbumTitle[title] = folderTitle
                }
                if !childTitles.contains(title) { childTitles.append(title) }
                if structure.localIdentifierByAlbumTitle[title] == nil {
                    structure.localIdentifierByAlbumTitle[title] = album.localIdentifier
                }
                if structure.summaries[title] == nil {
                    structure.summaries[title] = self.summary(of: album)
                }
            }
            structure.albumsByFolder[folderTitle] = childTitles
        }

        // 2) 自定义相簿：补摘要，并挑出不在任何文件夹里的
        for album in fetchCustomAlbums() {
            guard let title = album.localizedTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { continue }
            structure.customAlbumLocalIDs.insert(album.localIdentifier)
            if structure.localIdentifierByAlbumTitle[title] == nil {
                structure.localIdentifierByAlbumTitle[title] = album.localIdentifier
            }
            if structure.summaries[title] == nil {
                structure.summaries[title] = summary(of: album)
            }
            guard structure.folderByAlbumTitle[title] == nil else { continue }
            if !structure.ungroupedAlbumTitles.contains(title) {
                structure.ungroupedAlbumTitles.append(title)
            }
        }

        return structure
    }

    /// 相簿展示摘要：估计张数 + 关键照片。都不需要枚举整个相簿。
    private func summary(of album: PHAssetCollection) -> AlbumSummary {
        let estimated = album.estimatedAssetCount
        let count = (estimated == NSNotFound || estimated < 0)
            ? PHAsset.fetchAssets(in: album, options: nil).count
            : estimated
        let cover = PHAsset.fetchKeyAssets(in: album, options: nil)?.firstObject
        return AlbumSummary(photoCount: count, coverLocalIdentifier: cover?.localIdentifier)
    }

    /// 扫描页用的计数：会被跳过的相簿照片数与会被识别的散图数。
    func photoCounts() -> LibraryPhotoCounts {
        let allAssetIDs = Set(fetchAllPhotoAssets().map { $0.localIdentifier })
        let skippedAssetIDs = fetchAssetIdentifiers(in: albumsExcludedFromScan())
        return LibraryPhotoCountPolicy.counts(allAssetIDs: allAssetIDs,
                                              albumAssetIDs: skippedAssetIDs,
                                              excludedAssetIDs: [])
    }

    /// 本次扫描会跳过的相簿：显式排除的相簿 + 默认跳过的自定义相簿，
    /// 再减去用户显式「取消排除（包含）」的相簿。
    func albumsExcludedFromScan() -> [PHAssetCollection] {
        let excluded = AlbumExclusionStore.loadExcluded()
        let included = AlbumExclusionStore.loadIncluded()
        return fetchUserAlbums().filter { album in
            AlbumExclusionStore.isExcludedFromScan(albumLocalID: album.localIdentifier,
                                                   isCustomAlbum: album.assetCollectionSubtype == .albumRegular,
                                                   excluded: excluded,
                                                   included: included)
        }
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

    /// 读取照片详情（类型、尺寸、时间、位置、文件名）。
    func photoDetail(localIdentifier: String) -> PhotoDetail? {
        guard let asset = asset(localIdentifier: localIdentifier) else { return nil }
        return PhotoDetail(
            mediaTypeText: Self.mediaTypeText(for: asset),
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            isFavorite: asset.isFavorite,
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            locationText: asset.location.map {
                String(format: "%.5f, %.5f", $0.coordinate.latitude, $0.coordinate.longitude)
            },
            resourceFileNames: PHAssetResource.assetResources(for: asset).map { $0.originalFilename })
    }

    private static func mediaTypeText(for asset: PHAsset) -> String {
        if asset.mediaType == .video { return "视频" }
        if asset.mediaSubtypes.contains(.photoLive) { return "实况照片" }
        if asset.mediaSubtypes.contains(.photoScreenshot) { return "截屏" }
        if asset.mediaSubtypes.contains(.photoPanorama) { return "全景照片" }
        return "照片"
    }

    /// 打开系统「照片」App。
    ///
    /// iOS **没有公开接口**能直接定位到某张具体照片：Photos.app 虽然注册了
    /// `photos://asset?uuid=` / `photos://contentmode?...&assetuuid=`，但它们被标记为
    /// `CFBundleURLIsPrivate = true`，外部 App 调用会被系统拒绝
    /// （实测返回 `LSApplicationWorkspaceErrorDomain error 115`）。
    /// 所以只能打开「照片」App；要尽量靠近某张照片请用 `searchSystemPhotos`。
    @MainActor
    static func openSystemPhotosApp() {
        guard let url = URL(string: "photos-redirect://") else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    /// 在系统「照片」App 里按**拍摄日期**搜索这张照片。
    ///
    /// 用公开 scheme `photos-navigation://search?searchTerm=`（Photos.app 的
    /// Info.plist 里 `CFBundleURLIsPrivate = false`，实测可打开搜索并填入关键词）。
    /// 这是目前唯一能「尽量靠近」某张具体照片的公开做法：会显示**当天的照片**，
    /// 仍需用户自己找到那一张。读不到拍摄日期时退回只打开「照片」App。
    @MainActor
    static func searchSystemPhotos(forAssetLocalIdentifier identifier: String) {
        guard let date = shared.asset(localIdentifier: identifier)?.creationDate else {
            openSystemPhotosApp()
            return
        }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        var components = URLComponents()
        components.scheme = "photos-navigation"
        components.host = "search"
        components.queryItems = [URLQueryItem(name: "searchTerm",
                                              value: formatter.string(from: date))]
        guard let url = components.url else {
            openSystemPhotosApp()
            return
        }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
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

    /// 「人脸照片 -> 所属**自定义**相簿名」，用于按相簿名决定人物归属。
    ///
    /// 只收集 `assetIDs`（有人脸的照片）的归属，避免为大相册里没人脸的照片
    /// 白白建立映射。按相簿遍历而不是逐张查询，相册数量远少于照片数量。
    /// 只认自定义相簿 `fetchCustomAlbums()`，且名字要**像人名**
    /// （`PersonNameHeuristic`）—— 系统相簿和「旅行 / 截图」这类相簿都不参与，
    /// 否则它们会凭空变成一个人物。被过滤掉的照片会退回 AI 聚类。
    /// - Parameter excludingAlbumIDs: 被排除的相簿（它们不参与扫描，名字也不该拿来命名）。
    func albumNames(byAssetLocalIdentifier assetIDs: Set<String>,
                    excludingAlbumIDs: Set<String> = []) -> [String: [String]] {
        guard !assetIDs.isEmpty else { return [:] }
        var result: [String: [String]] = [:]
        for album in fetchCustomAlbums() {
            guard !excludingAlbumIDs.contains(album.localIdentifier),
                  let title = album.localizedTitle, !title.isEmpty,
                  PersonNameHeuristic.looksLikePersonName(title) else { continue }
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

    /// 取一张适合上传的 JPEG（最长边 maxDimension），用于「网络识别人像（以图搜图）」。
    /// 只在用户主动点识别时调用，不会用于扫描 / 聚类。
    func uploadImageData(for assetLocalIdentifier: String,
                         maxDimension: CGFloat = 1600) async -> Data? {
        guard let asset = asset(localIdentifier: assetLocalIdentifier) else { return nil }
        let size = CGSize(width: maxDimension, height: maxDimension)
        guard let cgImage = await cgImage(for: asset, targetSize: size) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8)
    }
}
