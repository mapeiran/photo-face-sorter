import XCTest
@testable import PhotoFaceSorter

/// 相簿名排序：数字按数值（人物 2 在 人物 10 前），空名字排最前。
final class AlbumTitleOrderingTests: XCTestCase {

    func testNumbersSortNumerically() {
        let sorted = ["人物 10", "人物 2"].sorted {
            AlbumTitleOrdering.isOrderedBefore($0, $1)
        }
        XCTAssertEqual(sorted, ["人物 2", "人物 10"])
    }

    func testNilTitleSortsFirst() {
        XCTAssertTrue(AlbumTitleOrdering.isOrderedBefore(nil, "妈妈"))
        XCTAssertFalse(AlbumTitleOrdering.isOrderedBefore("妈妈", nil))
        XCTAssertFalse(AlbumTitleOrdering.isOrderedBefore(nil, nil))
    }

    func testSortingAlbumsKeepsStableOrder() {
        let titles: [String?] = ["b", "a", "c", nil]
        let sorted = titles.sorted { AlbumTitleOrdering.isOrderedBefore($0, $1) }
        XCTAssertEqual(sorted.map { $0 ?? "（空）" }, ["（空）", "a", "b", "c"])
    }
}
