import XCTest
@testable import PhotoFaceSorter

/// 覆盖「旧版本写下的缓存必须仍能解码」。
///
/// 背景：Swift 合成的 `Decodable` **不会**为非可选属性使用默认值，
/// 因此给模型新增一个非可选字段会让整份旧缓存解码失败，而
/// `CacheStore.read` 会把失败静默当成空数据，随后又被空数据覆盖 —— 用户数据就没了。
/// 这两个测试就是这个陷阱的回归防线。
final class ModelCodingTests: XCTestCase {

    /// 去掉某个键，模拟「旧版本写下的 JSON」
    private func removingKey(_ key: String, from value: some Encodable) throws -> Data {
        let encoded = try JSONEncoder().encode(value)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: key)
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testExecutionLogDecodesWithoutSourceAlbumField() throws {
        let original = ExecutionLog(ruleID: UUID(),
                                    ruleName: "测试规则",
                                    action: .move,
                                    targetAlbumName: "目标相簿",
                                    assetLocalIdentifiers: ["a", "b"],
                                    sourceAlbumLocalIDs: ["album-1"])

        let legacy = try removingKey("sourceAlbumLocalIDs", from: original)
        let decoded = try JSONDecoder().decode(ExecutionLog.self, from: legacy)

        XCTAssertNil(decoded.sourceAlbumLocalIDs, "旧日志没有来源相簿字段，应解码为 nil 而不是失败")
        XCTAssertEqual(decoded.ruleName, "测试规则")
        XCTAssertEqual(decoded.action, .move)
        XCTAssertEqual(decoded.assetLocalIdentifiers, ["a", "b"])
        XCTAssertFalse(decoded.rolledBack)
    }

    func testFaceSampleDecodesWithoutManualAssignmentField() throws {
        let original = FaceSample(assetLocalIdentifier: "asset-1",
                                  boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
                                  feature: [1, 2, 3],
                                  personID: nil,
                                  isIgnored: false,
                                  assignmentIsManual: true)

        let legacy = try removingKey("assignmentIsManual", from: original)
        let decoded = try JSONDecoder().decode(FaceSample.self, from: legacy)

        XCTAssertNil(decoded.assignmentIsManual)
        XCTAssertEqual(decoded.assetLocalIdentifier, "asset-1")
        XCTAssertEqual(decoded.feature, [1, 2, 3])
    }

    /// Person 新增 nameIsAuto 后，旧 people.json（没有这个键）必须仍能解码
    func testPersonDecodesWithoutAutoNameField() throws {
        var original = Person(name: "妈妈")
        original.nameIsAuto = true

        let legacy = try removingKey("nameIsAuto", from: original)
        let decoded = try JSONDecoder().decode(Person.self, from: legacy)

        XCTAssertNil(decoded.nameIsAuto, "旧人物没有这个字段，应解码为 nil 而不是失败")
        XCTAssertEqual(decoded.name, "妈妈")
        XCTAssertEqual(decoded.id, original.id)
    }

    func testPersonAutoNameFlagRoundTrips() throws {
        var person = Person(name: "妈妈")
        person.nameIsAuto = true
        let data = try JSONEncoder().encode(person)
        XCTAssertEqual(try JSONDecoder().decode(Person.self, from: data).nameIsAuto, true)
    }

    func testFaceSampleFeatureRoundTripPreservesValues() {
        let values: [Float] = [0, 1, -1, 0.5, 123.456, -0.0001]
        let sample = FaceSample(assetLocalIdentifier: "a",
                                boundingBox: .zero,
                                feature: values)
        XCTAssertEqual(sample.feature, values)
    }

    func testFaceSampleFeatureIsEmptyWhenDataIsEmpty() {
        let sample = FaceSample(assetLocalIdentifier: "a", boundingBox: .zero, feature: [])
        XCTAssertTrue(sample.feature.isEmpty)
    }

    /// 数据长度不是 4 的倍数时不能越界读取
    func testFaceSampleFeatureIgnoresTrailingPartialBytes() {
        var sample = FaceSample(assetLocalIdentifier: "a", boundingBox: .zero, feature: [1, 2])
        sample.featureData.append(contentsOf: [0xFF, 0xFF])
        XCTAssertEqual(sample.feature, [1, 2])
    }
}
