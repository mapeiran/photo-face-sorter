import XCTest
@testable import PhotoFaceSorter

/// 覆盖「本次真正需要新增哪些照片」这条策略。
///
/// 它决定了规则回退的精确性：日志只记本次新增的照片，
/// 回退时才不会把别的规则或用户自己放进该相簿的照片一并删掉。
final class RuleExecutionPolicyTests: XCTestCase {

    func testAllCandidatesAreNewWhenAlbumIsEmpty() {
        XCTAssertEqual(RuleExecutionPolicy.newlyAdded(candidateIDs: ["a", "b", "c"],
                                                      existingInAlbum: []),
                       ["a", "b", "c"])
    }

    func testAlreadyPresentCandidatesAreExcluded() {
        XCTAssertEqual(RuleExecutionPolicy.newlyAdded(candidateIDs: ["a", "b", "c"],
                                                      existingInAlbum: ["b"]),
                       ["a", "c"])
    }

    /// 全部已在相簿里 → 空结果 → 调用方据此判断「没有实际改动，不记日志」
    func testNoNewCandidatesWhenEverythingIsPresent() {
        XCTAssertTrue(RuleExecutionPolicy.newlyAdded(candidateIDs: ["a", "b"],
                                                     existingInAlbum: ["a", "b"]).isEmpty)
    }

    func testInputOrderIsPreserved() {
        XCTAssertEqual(RuleExecutionPolicy.newlyAdded(candidateIDs: ["c", "a", "b"],
                                                      existingInAlbum: []),
                       ["c", "a", "b"])
    }

    func testDuplicatesAreRemoved() {
        XCTAssertEqual(RuleExecutionPolicy.newlyAdded(candidateIDs: ["a", "a", "b", "a"],
                                                      existingInAlbum: []),
                       ["a", "b"])
    }

    func testEmptyInputProducesEmptyOutput() {
        XCTAssertTrue(RuleExecutionPolicy.newlyAdded(candidateIDs: [], existingInAlbum: ["a"]).isEmpty)
    }

    /// 回归：回退只应移除本次新增的照片。
    /// 若日志按「匹配到的全部照片」记录，回退就会误删本来就在相簿里的照片。
    func testRollbackSetIsOnlyWhatThisRunAdded() {
        let matched = ["already-there", "new-1", "new-2"]
        let existing: Set<String> = ["already-there"]

        let logged = RuleExecutionPolicy.newlyAdded(candidateIDs: matched, existingInAlbum: existing)

        XCTAssertEqual(logged, ["new-1", "new-2"])
        XCTAssertFalse(logged.contains("already-there"),
                       "回退不能删掉不是本次新增的照片")
    }
}
