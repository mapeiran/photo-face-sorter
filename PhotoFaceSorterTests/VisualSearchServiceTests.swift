import XCTest
@testable import PhotoFaceSorter

/// 以图搜图结果的解析（不联网，直接喂 Bing Visual Search 的 JSON）。
final class VisualSearchServiceTests: XCTestCase {

    private let sampleJSON = """
    {
      "tags": [
        {
          "displayName": "赵今麦",
          "actions": [
            {
              "actionType": "PagesIncluding",
              "data": {
                "value": [
                  {
                    "name": "赵今麦 - 百度百科",
                    "hostPageUrl": "https://baike.baidu.com/item/赵今麦",
                    "hostPageDisplayUrl": "baike.baidu.com"
                  }
                ]
              }
            },
            {
              "actionType": "VisualSearch",
              "data": {
                "value": [
                  {
                    "name": "相似图",
                    "thumbnailUrl": "https://tse1.mm.bing.net/1",
                    "contentUrl": "https://example.com/1.jpg"
                  }
                ]
              }
            }
          ]
        }
      ]
    }
    """

    func testParseExtractsTagsPagesAndImages() throws {
        let result = try VisualSearchService.parse(Data(sampleJSON.utf8))
        XCTAssertEqual(result.tags, ["赵今麦"])
        XCTAssertEqual(result.pages.count, 1)
        XCTAssertEqual(result.pages.first?.name, "赵今麦 - 百度百科")
        XCTAssertEqual(result.pages.first?.url, "https://baike.baidu.com/item/赵今麦")
        XCTAssertEqual(result.pages.first?.host, "baike.baidu.com")
        XCTAssertEqual(result.similarImages.count, 1)
        XCTAssertEqual(result.similarImages.first?.thumbnailURL, "https://tse1.mm.bing.net/1")
        XCTAssertFalse(result.isEmpty)
    }

    func testParseEmptyObjectIsEmpty() throws {
        let result = try VisualSearchService.parse(Data("{}".utf8))
        XCTAssertTrue(result.isEmpty)
    }

    func testParseSkipsPageWithoutURL() throws {
        let json = """
        {"tags":[{"actions":[{"actionType":"PagesIncluding","data":{"value":[{"name":"no url"}]}}]}]}
        """
        let result = try VisualSearchService.parse(Data(json.utf8))
        XCTAssertTrue(result.pages.isEmpty)
    }

    func testParseInvalidJSONThrows() {
        XCTAssertThrowsError(try VisualSearchService.parse(Data("not json".utf8)))
    }
}
