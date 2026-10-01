import XCTest
@testable import PhotoFaceSorter

/// 覆盖「特征提取方式变了要能被发现」这条保护。
///
/// 如果发现不了，新旧特征会被混在一起聚类，得到毫无意义的分组却不报任何错。
final class EmbeddingConsistencyTests: XCTestCase {

    func testNoSamplesNeedsNoWarning() {
        XCTAssertEqual(EmbeddingConsistency.status(storedSignature: nil,
                                                   currentSignature: "v2",
                                                   sampleCount: 0),
                       .notScanned)
        XCTAssertEqual(EmbeddingConsistency.status(storedSignature: "v1",
                                                   currentSignature: "v2",
                                                   sampleCount: 0),
                       .notScanned, "没有样本时不应提示重扫")
    }

    func testMatchingSignatureIsConsistent() {
        XCTAssertEqual(EmbeddingConsistency.status(storedSignature: "v2",
                                                   currentSignature: "v2",
                                                   sampleCount: 10),
                       .consistent)
    }

    func testDifferentSignatureRequiresFullRescan() {
        XCTAssertEqual(EmbeddingConsistency.status(storedSignature: "v1",
                                                   currentSignature: "v2",
                                                   sampleCount: 10),
                       .needsFullRescan(stored: "v1", current: "v2"))
    }

    /// 旧版本没记录过签名，而它们的样本正是当前算法算出来的 ——
    /// 升级时不能对老用户误报「需要重扫」。
    func testMissingSignatureIsTreatedAsConsistentForUpgradePath() {
        XCTAssertEqual(EmbeddingConsistency.status(storedSignature: nil,
                                                   currentSignature: "v2",
                                                   sampleCount: 10),
                       .consistent)
    }

    // MARK: - CacheStore 持久化

    private func tempRoot(_ tag: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(tag)-\(UUID().uuidString)", isDirectory: true)
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(3, forKey: "cacheSchemaVersion")
    }

    func testMetaSurvivesReload() {
        let root = tempRoot("meta")
        let store = CacheStore(root: root)
        store.embeddingSignature = "vision-featureprint-256"

        XCTAssertEqual(store.meta.embeddingSignature, "vision-featureprint-256")
        XCTAssertEqual(CacheStore(root: root).embeddingSignature, "vision-featureprint-256")
    }

    func testMetaDefaultsToNilWhenAbsent() {
        let root = tempRoot("nometa")
        XCTAssertNil(CacheStore(root: root).embeddingSignature)
    }

    /// 旧的 meta.json 没有这个键，也不能整份解码失败
    func testMetaDecodesLegacyJSONWithoutSignature() throws {
        let root = tempRoot("legacyjson")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: root.appendingPathComponent("meta.json"))

        XCTAssertNil(CacheStore(root: root).embeddingSignature)
    }

    func testClearFaceCacheResetsSignature() {
        let root = tempRoot("clear")
        let store = CacheStore(root: root)
        store.embeddingSignature = "v1"
        store.samples = [FaceSample(assetLocalIdentifier: "a", boundingBox: .zero, feature: [1])]
        store.flushPendingWrites()

        store.clearFaceCache()

        XCTAssertNil(store.embeddingSignature)
        XCTAssertNil(CacheStore(root: root).embeddingSignature)
    }
}
