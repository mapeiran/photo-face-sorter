import XCTest
@testable import PhotoFaceSorter

/// 扫描页展示的计数：相簿内照片会被跳过，散图才会被识别；
/// 被排除相簿的照片两边都不算。
final class LibraryPhotoCountPolicyTests: XCTestCase {

    func testSplitsAlbumPhotosFromLoosePhotos() {
        let counts = LibraryPhotoCountPolicy.counts(allAssetIDs: ["a", "b", "c", "d", "e"],
                                                    albumAssetIDs: ["a", "b", "c"],
                                                    excludedAssetIDs: ["d"])
        XCTAssertEqual(counts.albumPhotos, 3)
        XCTAssertEqual(counts.loosePhotos, 1, "只有 e 是既不在相簿中、也没被排除的散图")
    }

    func testEverythingInAlbumsMeansNoLoosePhotos() {
        let counts = LibraryPhotoCountPolicy.counts(allAssetIDs: ["a", "b"],
                                                    albumAssetIDs: ["a", "b"],
                                                    excludedAssetIDs: [])
        XCTAssertEqual(counts.albumPhotos, 2)
        XCTAssertEqual(counts.loosePhotos, 0)
    }

    func testExcludedPhotoInAlbumStillCountsAsAlbum() {
        // 唯一的照片 a 同时在一个自定义相簿和一个被排除相簿里
        let counts = LibraryPhotoCountPolicy.counts(allAssetIDs: ["a"],
                                                    albumAssetIDs: ["a"],
                                                    excludedAssetIDs: ["a"])
        XCTAssertEqual(counts.albumPhotos, 1, "相簿计数不受排除相簿影响")
        XCTAssertEqual(counts.loosePhotos, 0, "被排除的照片不能算成散图")
    }

    /// 界面上「照片总数」用的是 albumPhotos + loosePhotos，必须等于全部照片数。
    func testAlbumPlusLooseEqualsAllPhotos() {
        let all: Set<String> = ["a", "b", "c", "d"]
        let counts = LibraryPhotoCountPolicy.counts(allAssetIDs: all,
                                                    albumAssetIDs: ["a", "b"],
                                                    excludedAssetIDs: [])
        XCTAssertEqual(counts.albumPhotos + counts.loosePhotos, all.count)
    }

    func testEmptyLibrary() {
        let counts = LibraryPhotoCountPolicy.counts(allAssetIDs: [],
                                                    albumAssetIDs: [],
                                                    excludedAssetIDs: [])
        XCTAssertEqual(counts, LibraryPhotoCounts(albumPhotos: 0, loosePhotos: 0))
    }
}
