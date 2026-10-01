import XCTest
@testable import PhotoFaceSorter

/// 阈值标定：旧默认值 0.9 会把所有人并成一个分组，必须能迁移到新标定。
final class ClusterThresholdTests: XCTestCase {

    func testOldCalibrationIsResetToNewDefault() {
        XCTAssertEqual(ClusterThreshold.calibrated(ClusterThreshold.legacyDefault),
                       ClusterThreshold.defaultValue)
        XCTAssertEqual(ClusterThreshold.calibrated(1.5), ClusterThreshold.defaultValue)
        XCTAssertEqual(ClusterThreshold.calibrated(0), ClusterThreshold.defaultValue)
    }

    func testValuesInsideRangeAreKept() {
        for value in [0.15, 0.2, 0.25, 0.3, 0.35] {
            XCTAssertEqual(ClusterThreshold.calibrated(value), value)
        }
    }

    func testDefaultIsInsideRange() {
        XCTAssertTrue(ClusterThreshold.range.contains(ClusterThreshold.defaultValue))
    }
}
