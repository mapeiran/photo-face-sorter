import XCTest
@testable import PhotoFaceSorter

/// 规则执行结果的汇报文案。
/// 以前 `RuleRunner` 用 `try?` 吞掉错误，界面上只显示一个偏小的成功数字，
/// 用户无法知道有规则根本没跑成功。
final class RuleOutcomeTests: XCTestCase {

    private func log(_ name: String) -> ExecutionLog {
        ExecutionLog(ruleID: UUID(),
                     ruleName: name,
                     action: .copy,
                     targetAlbumName: "相簿",
                     assetLocalIdentifiers: ["a"])
    }

    func testSummaryWithoutFailures() {
        let outcome = RuleOutcome(logs: [log("规则A")],
                                  movedCount: 0,
                                  copiedCount: 3,
                                  failures: [])
        XCTAssertEqual(outcome.summary, "已执行 1 条规则：复制 3 张，移动 0 张")
        XCTAssertFalse(outcome.summary.contains("未能执行"))
    }

    func testSummaryListsEveryFailureWithReason() {
        let outcome = RuleOutcome(logs: [log("规则A")],
                                  movedCount: 2,
                                  copiedCount: 1,
                                  failures: [
                                    RuleFailure(ruleID: UUID(), ruleName: "规则B", reason: "无法创建目标相簿"),
                                    RuleFailure(ruleID: UUID(), ruleName: "规则C", reason: "无权访问照片")
                                  ])
        let summary = outcome.summary

        XCTAssertTrue(summary.hasPrefix("已执行 1 条规则：复制 1 张，移动 2 张"))
        XCTAssertTrue(summary.contains("2 条规则未能执行"))
        XCTAssertTrue(summary.contains("· 规则B：无法创建目标相簿"))
        XCTAssertTrue(summary.contains("· 规则C：无权访问照片"))
    }

    func testSummaryWhenNothingMatched() {
        let outcome = RuleOutcome(logs: [], movedCount: 0, copiedCount: 0, failures: [])
        XCTAssertEqual(outcome.summary, "已执行 0 条规则：复制 0 张，移动 0 张")
    }

    func testSummaryWithOnlyFailures() {
        let outcome = RuleOutcome(logs: [],
                                  movedCount: 0,
                                  copiedCount: 0,
                                  failures: [RuleFailure(ruleID: UUID(), ruleName: "规则X", reason: "失败原因")])
        XCTAssertTrue(outcome.summary.contains("已执行 0 条规则"))
        XCTAssertTrue(outcome.summary.contains("1 条规则未能执行"))
        XCTAssertTrue(outcome.summary.contains("规则X"))
    }

    func testFailureIdentityIsItsRule() {
        let ruleID = UUID()
        let failure = RuleFailure(ruleID: ruleID, ruleName: "规则", reason: "原因")
        XCTAssertEqual(failure.id, ruleID)
    }
}
