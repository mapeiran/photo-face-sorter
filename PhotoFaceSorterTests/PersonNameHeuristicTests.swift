import XCTest
@testable import PhotoFaceSorter

/// 「像人名」的启发式：只有通过的自定义相簿才参与归类，
/// 否则「旅行 2024」「截图」这类相簿会凭空变成一个人物。
final class PersonNameHeuristicTests: XCTestCase {

    func testRealPersonNamesPass() {
        let names = ["妈妈", "爸爸", "赵今麦", "张可", "宋轶", "李沁", "景甜",
                     "绸缪小姐", "咻咻满", "尹远航", "Mary Jane"]
        for name in names {
            XCTAssertTrue(PersonNameHeuristic.looksLikePersonName(name), "「\(name)」应该被当作人名")
        }
    }

    func testNamesWithNumbersAreRejected() {
        for name in ["2024", "旅行2024", "生日 2023", "IMG_1234", "第1天"] {
            XCTAssertFalse(PersonNameHeuristic.looksLikePersonName(name), "「\(name)」不该当人名")
        }
    }

    func testEventAndCategoryAlbumsAreRejected() {
        let names = ["旅行", "全家福", "截图", "工作", "毕业照", "聚会", "美食",
                     "表情包", "我的相册", "周末出游"]
        for name in names {
            XCTAssertFalse(PersonNameHeuristic.looksLikePersonName(name), "「\(name)」不该当人名")
        }
    }

    func testEmptyAndTooLongNamesAreRejected() {
        XCTAssertFalse(PersonNameHeuristic.looksLikePersonName(""))
        XCTAssertFalse(PersonNameHeuristic.looksLikePersonName("   "))
        XCTAssertFalse(PersonNameHeuristic.looksLikePersonName(String(repeating: "人", count: 13)))
    }

    func testNamesWithSeparatorsAreRejected() {
        for name in ["a/b", "a|b", "a:b", "a#b", "a(b)"] {
            XCTAssertFalse(PersonNameHeuristic.looksLikePersonName(name), "「\(name)」不该当人名")
        }
    }
}
