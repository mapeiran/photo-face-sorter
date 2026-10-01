import XCTest
@testable import PhotoFaceSorter

/// 规则拖动排序（纯逻辑）
final class RuleOrderingTests: XCTestCase {

    private func rules(_ names: [String]) -> [ClassifyRule] {
        names.enumerated().map { index, name in
            var rule = ClassifyRule(name: name, targetAlbumName: "album")
            rule.order = index
            return rule
        }
    }

    private func names(_ rules: [ClassifyRule]) -> [String] { rules.map(\.name) }
    private func orders(_ rules: [ClassifyRule]) -> [Int] { rules.map(\.order) }

    func testMovingFirstRuleToEnd() {
        let result = RuleOrdering.reordered(rules(["A", "B", "C"]), from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(names(result), ["B", "C", "A"])
        XCTAssertEqual(orders(result), [0, 1, 2])
    }

    func testMovingLastRuleToFront() {
        let result = RuleOrdering.reordered(rules(["A", "B", "C"]), from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(names(result), ["C", "A", "B"])
    }

    func testMovingMiddleRuleUp() {
        let result = RuleOrdering.reordered(rules(["A", "B", "C"]), from: IndexSet(integer: 1), to: 0)
        XCTAssertEqual(names(result), ["B", "A", "C"])
    }

    func testMovingMiddleRuleDown() {
        let result = RuleOrdering.reordered(rules(["A", "B", "C", "D"]), from: IndexSet(integer: 1), to: 3)
        XCTAssertEqual(names(result), ["A", "C", "B", "D"])
    }

    func testMovingMultipleRulesAtOnce() {
        let result = RuleOrdering.reordered(rules(["A", "B", "C", "D"]), from: IndexSet([0, 2]), to: 4)
        XCTAssertEqual(names(result), ["B", "D", "A", "C"])
    }

    func testOrderIsAlwaysRenumberedFromZero() {
        let result = RuleOrdering.reordered(rules(["A", "B", "C", "D"]), from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(orders(result), Array(0..<4), "order 必须始终是 0..n-1")
    }

    func testMovingToSamePositionIsNoOp() {
        let result = RuleOrdering.reordered(rules(["A", "B", "C"]), from: IndexSet(integer: 1), to: 1)
        XCTAssertEqual(names(result), ["A", "B", "C"])
    }

    func testEmptySourceOnlyRenumbers() {
        let result = RuleOrdering.reordered(rules(["A", "B"]), from: IndexSet(), to: 0)
        XCTAssertEqual(names(result), ["A", "B"])
        XCTAssertEqual(orders(result), [0, 1])
    }

    func testRenumberedAssignsSequentialOrders() {
        XCTAssertEqual(orders(RuleOrdering.renumbered(rules(["A", "B", "C"]))), [0, 1, 2])
    }

    func testNoRuleIsLostOrDuplicated() {
        let original = rules(["A", "B", "C", "D", "E"])
        for source in [IndexSet(integer: 0), IndexSet(integer: 4), IndexSet([1, 3])] {
            for destination in 0...5 {
                let result = RuleOrdering.reordered(original, from: source, to: destination)
                XCTAssertEqual(Set(names(result)), Set(names(original)),
                               "source=\(source) dest=\(destination) 不应丢失或重复规则")
                XCTAssertEqual(result.count, original.count)
            }
        }
    }
}
