import XCTest
@testable import PhotoFaceSorter

/// 单次扫描上限的换算与分批。
///
/// 背景：几万张的大相册一次性扫完会长时间占用设备、界面停在「扫描中」，
/// 用户以为卡死。上限必须先保证「绝不返回 0 或负数」——
/// `Array.prefix(_:)` 收到负数会直接崩溃，那才是真正的卡死/闪退。
final class ScanBatchPolicyTests: XCTestCase {

    // MARK: - limit(setting:cap:)

    func testZeroOrNegativeSettingMeansUnlimited() {
        XCTAssertEqual(ScanBatchPolicy.limit(setting: 0), Int.max)
        XCTAssertEqual(ScanBatchPolicy.limit(setting: -10), Int.max)
    }

    func testPositiveSettingIsUsedAsIs() {
        XCTAssertEqual(ScanBatchPolicy.limit(setting: 1), 1)
        XCTAssertEqual(ScanBatchPolicy.limit(setting: 250), 250)
    }

    func testCapOnlyNarrowsTheLimit() {
        XCTAssertEqual(ScanBatchPolicy.limit(setting: 500, cap: 60), 60,
                       "后台硬上限比用户设置小时以后台为准")
        XCTAssertEqual(ScanBatchPolicy.limit(setting: 30, cap: 60), 30,
                       "用户设置比硬上限小时不能反而放大")
    }

    func testCapAppliesWhenSettingIsUnlimited() {
        XCTAssertEqual(ScanBatchPolicy.limit(setting: 0, cap: 60), 60)
    }

    func testNonPositiveCapIsIgnored() {
        XCTAssertEqual(ScanBatchPolicy.limit(setting: 0, cap: 0), Int.max)
        XCTAssertEqual(ScanBatchPolicy.limit(setting: 10, cap: -1), 10)
    }

    func testLimitIsNeverZeroOrNegative() {
        for setting in [-100, -1, 0, 1, 100] {
            for cap in [nil, -5, 0, 1, 60] as [Int?] {
                XCTAssertGreaterThan(ScanBatchPolicy.limit(setting: setting, cap: cap), 0,
                                     "setting=\(setting) cap=\(String(describing: cap))")
            }
        }
    }

    // MARK: - batch(_:limit:)

    func testBatchWithoutLimitKeepsEverything() {
        let (batch, remaining) = ScanBatchPolicy.batch(Array(1...10), limit: Int.max)
        XCTAssertEqual(batch, Array(1...10))
        XCTAssertEqual(remaining, 0)
    }

    func testBatchSplitsAndReportsRemaining() {
        let (batch, remaining) = ScanBatchPolicy.batch(Array(1...10), limit: 3)
        XCTAssertEqual(batch, [1, 2, 3], "按相册顺序取前 N 张，剩下的留给下一批")
        XCTAssertEqual(remaining, 7)
    }

    func testBatchWithMoreLimitThanItems() {
        let (batch, remaining) = ScanBatchPolicy.batch(Array(1...3), limit: 100)
        XCTAssertEqual(batch.count, 3)
        XCTAssertEqual(remaining, 0)
    }

    func testBatchOnEmptyInput() {
        let (batch, remaining) = ScanBatchPolicy.batch([Int](), limit: 10)
        XCTAssertTrue(batch.isEmpty)
        XCTAssertEqual(remaining, 0)
    }

    func testNegativeLimitDoesNotCrash() {
        let (batch, remaining) = ScanBatchPolicy.batch(Array(1...3), limit: -1)
        XCTAssertTrue(batch.isEmpty)
        XCTAssertEqual(remaining, 3)
    }

    /// 分批扫不会漏照片：每批处理完后再取下一批，直到 remaining 为 0。
    func testBatchesCoverEverythingExactlyOnce() {
        let all = Array(0..<25)
        let limit = ScanBatchPolicy.limit(setting: 10)
        var queue = all
        var seen: [Int] = []
        while !queue.isEmpty {
            let (batch, remaining) = ScanBatchPolicy.batch(queue, limit: limit)
            seen.append(contentsOf: batch)
            queue = Array(queue.dropFirst(batch.count))
            XCTAssertEqual(remaining, queue.count)
        }
        XCTAssertEqual(seen, all, "分批只是切片，不能重复也不能漏")
    }
}
