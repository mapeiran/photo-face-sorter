import XCTest
@testable import PhotoFaceSorter

final class PersonAlbumExporterTests: XCTestCase {

    private func outcome(_ count: Int, action: RuleAction) -> PersonAlbumExporter.Outcome {
        PersonAlbumExporter.Outcome(albumName: "妈妈", addedCount: count, action: action, log: nil)
    }

    func testCopySummary() {
        XCTAssertEqual(outcome(3, action: .copy).summary, "已复制 3 张到系统相簿「妈妈」。")
    }

    func testMoveSummary() {
        XCTAssertEqual(outcome(2, action: .move).summary, "已移动 2 张到系统相簿「妈妈」。")
    }

    func testNothingToAddSummary() {
        XCTAssertEqual(outcome(0, action: .copy).summary,
                       "这些照片都已经在系统相簿「妈妈」里了，没有需要新增的。")
    }
}
