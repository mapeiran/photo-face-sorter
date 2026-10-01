import XCTest
@testable import PhotoFaceSorter

/// 相簿优先的归类规则：一张照片归到哪个人物，由它所属的相簿名决定。
final class PersonNamingPolicyTests: XCTestCase {

    private func albumName(_ asset: String,
                           _ map: [String: [String]],
                           _ counts: [String: Int] = [:]) -> String? {
        PersonNamingPolicy.albumName(assetLocalIdentifier: asset,
                                     albumNamesByAsset: map,
                                     albumMemberCounts: counts)
    }

    func testSingleAlbumDecidesTheName() {
        XCTAssertEqual(albumName("a1", ["a1": ["妈妈"]]), "妈妈")
    }

    func testNoAlbumReturnsNilSoAITakesOver() {
        XCTAssertNil(albumName("a1", [:]))
        XCTAssertNil(albumName("a1", ["a1": []]))
    }

    func testEmptyAlbumNameIsIgnored() {
        XCTAssertNil(albumName("a1", ["a1": [""]]))
    }

    /// 同一张照片在多个相簿里时选**成员最少**（最专有）的那个，
    /// 避免「全家福」这种大杂烩相簿盖过「妈妈」
    func testMostSpecificAlbumWins() {
        let map = ["a1": ["全家福", "妈妈"]]
        let counts = ["全家福": 500, "妈妈": 120]
        XCTAssertEqual(albumName("a1", map, counts), "妈妈")
    }

    /// 成员数相同则按名称稳定排序，保证每次结果一致
    func testTieBreakIsDeterministic() {
        let map = ["a1": ["zebra", "apple"]]
        let counts = ["zebra": 10, "apple": 10]
        XCTAssertEqual(albumName("a1", map, counts), "apple")
        XCTAssertEqual(albumName("a1", ["a1": ["apple", "zebra"]], ["zebra": 10, "apple": 10]), "apple")
    }

    func testMissingMemberCountsFallsBackToNameOrder() {
        XCTAssertEqual(albumName("a1", ["a1": ["bbb", "aaa"]]), "aaa")
    }

    func testUnknownAssetReturnsNil() {
        XCTAssertNil(albumName("不存在", ["a1": ["妈妈"]]))
    }
}
