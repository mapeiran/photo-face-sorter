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

    /// 「所有相簿（含系统 / 同步相簿）」与「默认扫描会跳过的相簿」是两个不同的数：
    /// 前者是「重新识别相簿内照片」的范围，后者只是默认扫描的范围。
    func testAllAlbumCountIsReportedSeparately() {
        let counts = LibraryPhotoCountPolicy.counts(allAssetIDs: ["a", "b", "c"],
                                                    albumAssetIDs: ["a"],
                                                    excludedAssetIDs: [],
                                                    allAlbumAssetIDs: ["a", "b"])
        XCTAssertEqual(counts.albumPhotos, 1, "默认会跳过的相簿计数")
        XCTAssertEqual(counts.allAlbumPhotos, 2, "所有相簿（含系统相簿）的计数")
        XCTAssertEqual(counts.loosePhotos, 2)
    }

    func testEmptyLibrary() {
        let counts = LibraryPhotoCountPolicy.counts(allAssetIDs: [],
                                                    albumAssetIDs: [],
                                                    excludedAssetIDs: [])
        XCTAssertEqual(counts, LibraryPhotoCounts(albumPhotos: 0, loosePhotos: 0))
    }
}
