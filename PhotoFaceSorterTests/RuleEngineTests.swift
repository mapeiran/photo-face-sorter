import XCTest
@testable import PhotoFaceSorter

/// 规则匹配逻辑（纯函数，不依赖 PhotoKit）
final class RuleEngineTests: XCTestCase {

    private let alice = UUID()
    private let bob = UUID()

    /// 特征内容与匹配逻辑无关，只需非空
    private func sample(asset: String, person: UUID?, ignored: Bool = false) -> FaceSample {
        FaceSample(assetLocalIdentifier: asset,
                   boundingBox: .zero,
                   feature: [1, 0],
                   personID: person,
                   isIgnored: ignored)
    }

    private func record(asset: String, faces: Int) -> AssetRecord {
        AssetRecord(assetLocalIdentifier: asset, scannedAt: Date(), faceCount: faces, modificationDate: nil)
    }

    private func rule(persons: [UUID], mode: RuleMatchMode = .any, minFaces: Int = 1) -> ClassifyRule {
        var rule = ClassifyRule(name: "r", targetAlbumName: "album")
        rule.personIDs = persons
        rule.matchMode = mode
        rule.minFaceCount = minFaces
        return rule
    }

    private func match(_ rule: ClassifyRule,
                       _ samples: [FaceSample],
                       _ records: [AssetRecord],
                       membership: ((String) -> Set<String>)? = nil) -> [String] {
        RuleMatcher.matchedAssetIDs(for: rule,
                                    samples: samples,
                                    records: Dictionary(uniqueKeysWithValues: records.map { ($0.assetLocalIdentifier, $0) }),
                                    albumMembership: membership)
    }

    // MARK: - 人物条件

    func testMatchesAnyPersonInPhoto() {
        let matched = match(rule(persons: [alice]),
                            [sample(asset: "a", person: alice), sample(asset: "b", person: bob)],
                            [record(asset: "a", faces: 1), record(asset: "b", faces: 1)])
        XCTAssertEqual(matched, ["a"])
    }

    func testAllModeRequiresEverySelectedPerson() {
        let matched = match(rule(persons: [alice, bob], mode: .all),
                            [sample(asset: "a", person: alice),
                             sample(asset: "a", person: bob),
                             sample(asset: "b", person: alice)],
                            [record(asset: "a", faces: 2), record(asset: "b", faces: 1)])
        XCTAssertEqual(matched, ["a"], "只有同时含 alice 与 bob 的照片才应匹配")
    }

    func testAnyModeWithMultiplePersonsMatchesEither() {
        let matched = match(rule(persons: [alice, bob]),
                            [sample(asset: "a", person: alice), sample(asset: "b", person: bob)],
                            [record(asset: "a", faces: 1), record(asset: "b", faces: 1)])
        XCTAssertEqual(matched, ["a", "b"])
    }

    func testIgnoredFacesDoNotMatch() {
        let matched = match(rule(persons: [alice]),
                            [sample(asset: "a", person: alice, ignored: true)],
                            [record(asset: "a", faces: 1)])
        XCTAssertTrue(matched.isEmpty, "被标记为非人物的人脸不应参与匹配")
    }

    func testUnassignedFacesDoNotMatch() {
        let matched = match(rule(persons: [alice]),
                            [sample(asset: "a", person: nil)],
                            [record(asset: "a", faces: 1)])
        XCTAssertTrue(matched.isEmpty)
    }

    // MARK: - 人脸数量与记录

    func testMinFaceCountIsRespected() {
        let matched = match(rule(persons: [alice], minFaces: 2),
                            [sample(asset: "a", person: alice), sample(asset: "b", person: alice)],
                            [record(asset: "a", faces: 1), record(asset: "b", faces: 3)])
        XCTAssertEqual(matched, ["b"])
    }

    func testAssetsWithoutRecordAreSkipped() {
        let matched = match(rule(persons: [alice]), [sample(asset: "a", person: alice)], [])
        XCTAssertTrue(matched.isEmpty, "未扫描过的照片不应被规则命中")
    }

    func testEmptyPersonListMatchesByFaceCountOnly() {
        let matched = match(rule(persons: []),
                            [sample(asset: "a", person: nil)],
                            [record(asset: "a", faces: 2)])
        XCTAssertEqual(matched, ["a"])
    }

    /// 「人脸数量」是独立条件：人脸尚未归属到任何人物时也应能匹配。
    /// （早期实现只遍历「已归属的人脸」，导致这条条件永远匹配不到东西。）
    func testFaceCountConditionWorksBeforeClustering() {
        let matched = match(rule(persons: [], minFaces: 2),
                            [sample(asset: "a", person: nil), sample(asset: "b", person: nil)],
                            [record(asset: "a", faces: 2), record(asset: "b", faces: 1)])
        XCTAssertEqual(matched, ["a"])
    }

    /// 不限定人物时，只有 0 张人脸的照片也不该被「人脸数 ≥ 1」命中
    func testFaceCountConditionExcludesPhotosWithoutFaces() {
        let matched = match(rule(persons: [], minFaces: 1),
                            [sample(asset: "a", person: nil)],
                            [record(asset: "a", faces: 0), record(asset: "b", faces: 3)])
        XCTAssertEqual(matched, ["b"])
    }

    // MARK: - 来源相簿条件

    func testSourceAlbumFiltersMatchedAssets() {
        var limited = rule(persons: [alice])
        limited.sourceAlbumLocalID = "album-1"

        let matched = match(limited,
                            [sample(asset: "a", person: alice), sample(asset: "b", person: alice)],
                            [record(asset: "a", faces: 1), record(asset: "b", faces: 1)],
                            membership: { $0 == "a" ? ["album-1"] : ["album-2"] })
        XCTAssertEqual(matched, ["a"])
    }

    /// 限定了来源相簿却没有提供过滤器时，绝不能退化成「不过滤」
    func testSourceAlbumWithoutProviderMatchesNothing() {
        var limited = rule(persons: [alice])
        limited.sourceAlbumLocalID = "album-1"

        let matched = match(limited,
                            [sample(asset: "a", person: alice)],
                            [record(asset: "a", faces: 1)])
        XCTAssertTrue(matched.isEmpty)
    }

    func testNoSourceAlbumIgnoresMembership() {
        let matched = match(rule(persons: [alice]),
                            [sample(asset: "a", person: alice)],
                            [record(asset: "a", faces: 1)],
                            membership: { _ in [] })
        XCTAssertEqual(matched, ["a"], "未限定来源相簿时不应查询相簿")
    }

    func testSourceAlbumAcceptsAssetInMultipleAlbums() {
        var limited = rule(persons: [alice])
        limited.sourceAlbumLocalID = "album-1"

        let matched = match(limited,
                            [sample(asset: "a", person: alice)],
                            [record(asset: "a", faces: 1)],
                            membership: { _ in ["album-1", "album-2", "album-3"] })
        XCTAssertEqual(matched, ["a"])
    }
}
