import XCTest
@testable import PhotoFaceSorter

final class DuplicateGroupingPolicyTests: XCTestCase {

    func testExactHashesGroupTogether() {
        let groups = DuplicateGroupingPolicy.groups(hashes: [
            (id: "a", hash: UInt64(0b0000)),
            (id: "b", hash: UInt64(0b0000)),
            (id: "c", hash: UInt64(0b1111)),
        ], threshold: 1)
        XCTAssertEqual(groups, [["a", "b"]])
    }

    func testNearHashesGroupWithinThreshold() {
        let groups = DuplicateGroupingPolicy.groups(hashes: [
            (id: "a", hash: UInt64(0b0000)),
            (id: "b", hash: UInt64(0b0011)),
        ], threshold: 2)
        XCTAssertEqual(groups, [["a", "b"]])
    }

    func testBeyondThresholdStaysSeparate() {
        let groups = DuplicateGroupingPolicy.groups(hashes: [
            (id: "a", hash: UInt64(0b0000)),
            (id: "b", hash: UInt64(0b1111)),
        ], threshold: 3)
        XCTAssertTrue(groups.isEmpty)
    }

    /// 代表元分组不做链式传递：c 只和 b 相似、和代表元 a 不相似时不应被并进来。
    func testNoChainingThroughRepresentative() {
        let groups = DuplicateGroupingPolicy.groups(hashes: [
            (id: "a", hash: UInt64(0b0000)),
            (id: "b", hash: UInt64(0b0001)),
            (id: "c", hash: UInt64(0b0011)),
        ], threshold: 1)
        XCTAssertEqual(groups, [["a", "b"]], "c 与代表元 a 的距离是 2，不应被链式并进来")
    }
}
