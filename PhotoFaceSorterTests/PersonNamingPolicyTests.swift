import XCTest
@testable import PhotoFaceSorter

/// 按相簿名给人物自动命名的规则。
final class PersonNamingPolicyTests: XCTestCase {

    func testPicksMostFrequentAlbumName() {
        let map = ["a1": ["旅行"], "a2": ["妈妈"], "a3": ["妈妈"], "a4": ["妈妈"]]
        XCTAssertEqual(PersonNamingPolicy.dominantAlbumName(
            assetLocalIdentifiers: ["a1", "a2", "a3", "a4"],
            albumNamesByAsset: map), "妈妈")
    }

    /// 同一张照片上的多张脸只算一次，否则一张合影能决定整个分组的名字
    func testSameAssetCountsOnlyOnce() {
        let map = ["a1": ["妈妈"], "a2": ["旅行"], "a3": ["旅行"]]
        XCTAssertEqual(PersonNamingPolicy.dominantAlbumName(
            assetLocalIdentifiers: ["a1", "a1", "a1", "a2", "a3"],
            albumNamesByAsset: map), "旅行")
    }

    /// 同一张照片在多个相簿里时，每个相簿名各记一次
    func testPhotoInMultipleAlbumsCountsForEach() {
        let map = ["a1": ["妈妈", "宝宝"], "a2": ["宝宝"]]
        XCTAssertEqual(PersonNamingPolicy.dominantAlbumName(
            assetLocalIdentifiers: ["a1", "a2"], albumNamesByAsset: map), "宝宝")
    }

    func testReturnsNilWithoutAlbumInfo() {
        XCTAssertNil(PersonNamingPolicy.dominantAlbumName(assetLocalIdentifiers: ["a1", "a2"],
                                                          albumNamesByAsset: [:]))
        XCTAssertNil(PersonNamingPolicy.dominantAlbumName(assetLocalIdentifiers: ["a1"],
                                                          albumNamesByAsset: ["a1": []]))
    }

    func testIgnoresEmptyNamesAndUnknownAssets() {
        let map = ["a1": [""], "a2": ["妈妈"]]
        XCTAssertEqual(PersonNamingPolicy.dominantAlbumName(
            assetLocalIdentifiers: ["a1", "a2", "不存在的照片"],
            albumNamesByAsset: map), "妈妈")
    }

    /// 平局必须稳定（否则每次重聚类名字会随机变）
    func testTieBreakIsDeterministic() {
        let map = ["a1": ["zebra"], "a2": ["apple"]]
        let first = PersonNamingPolicy.dominantAlbumName(assetLocalIdentifiers: ["a1", "a2"],
                                                         albumNamesByAsset: map)
        let second = PersonNamingPolicy.dominantAlbumName(assetLocalIdentifiers: ["a2", "a1"],
                                                          albumNamesByAsset: map)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, "apple")
    }

    /// 用户选的规则是「只要有照片在相簿里就用相簿名」，所以一张也够
    func testSinglePhotoInAlbumIsEnough() {
        XCTAssertEqual(PersonNamingPolicy.dominantAlbumName(assetLocalIdentifiers: ["a1"],
                                                            albumNamesByAsset: ["a1": ["外婆"]]), "外婆")
    }
}
