import XCTest
@testable import PhotoFaceSorter

final class CacheStoreTests: XCTestCase {

    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CacheStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func assetRecord(_ id: String, faces: Int) -> AssetRecord {
        AssetRecord(assetLocalIdentifier: id, scannedAt: Date(), faceCount: faces, modificationDate: nil)
    }

    func testSamplesAndRecordsSurviveReload() {
        let root = tempRoot()
        let store = CacheStore(root: root)
        store.samples = [FaceSample(assetLocalIdentifier: "a", boundingBox: .zero, feature: [1, 2])]
        store.records = ["a": assetRecord("a", faces: 1)]
        store.flushPendingWrites()

        let reloaded = CacheStore(root: root)
        XCTAssertEqual(reloaded.samples.count, 1)
        XCTAssertEqual(reloaded.samples.first?.assetLocalIdentifier, "a")
        XCTAssertEqual(reloaded.samples.first?.feature, [1, 2])
        XCTAssertEqual(reloaded.records["a"]?.faceCount, 1)
    }

    /// 合并写入：连续多次赋值只应保留最后一次的结果，且 flush 后一定落盘
    func testCoalescedWritesKeepLatestValue() {
        let root = tempRoot()
        let store = CacheStore(root: root)
        for n in 1...20 {
            store.samples = (0..<n).map { FaceSample(assetLocalIdentifier: "a\($0)", boundingBox: .zero, feature: [1]) }
        }
        store.flushPendingWrites()

        XCTAssertEqual(CacheStore(root: root).samples.count, 20)
    }

    /// 损坏的缓存文件必须被保留证据，而不是被静默当成空数据后又被空数据覆盖
    func testCorruptCacheFileIsQuarantinedInsteadOfDropped() throws {
        let root = tempRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("这不是 JSON".utf8).write(to: root.appendingPathComponent("samples.json"))

        let store = CacheStore(root: root)
        XCTAssertTrue(store.samples.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("samples.json.corrupt").path),
                      "损坏文件应被改名保留")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("samples.bin").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("samples.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("records.bin").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("records.json").path))
    }

    func testClearFaceCacheRemovesSamplesPeopleAndRecords() {
        let root = tempRoot()
        let store = CacheStore(root: root)
        store.people = [Person(name: "张三")]
        store.samples = [FaceSample(assetLocalIdentifier: "a", boundingBox: .zero, feature: [1])]
        store.records = ["a": assetRecord("a", faces: 1)]
        store.flushPendingWrites()

        store.clearFaceCache()

        XCTAssertTrue(store.samples.isEmpty)
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertTrue(store.people.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("samples.bin").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("samples.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("records.bin").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("records.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("records.json").path))
    }

    /// 清空之后不得再被在途的合并写入写回
    func testClearFaceCacheIsNotUndoneByPendingWrite() {
        let root = tempRoot()
        let store = CacheStore(root: root)
        store.samples = [FaceSample(assetLocalIdentifier: "a", boundingBox: .zero, feature: [1])]
        store.clearFaceCache()
        store.flushPendingWrites()

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("samples.bin").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("samples.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("records.bin").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("records.json").path))
        XCTAssertTrue(CacheStore(root: root).samples.isEmpty)
    }

    func testRulesAndLogsRoundTrip() {
        let root = tempRoot()
        let store = CacheStore(root: root)
        var rule = ClassifyRule(name: "规则A", targetAlbumName: "相簿A")
        rule.personIDs = [UUID()]
        store.rules = [rule]
        store.logs = [ExecutionLog(ruleID: rule.id,
                                   ruleName: rule.name,
                                   action: .copy,
                                   targetAlbumName: rule.targetAlbumName,
                                   assetLocalIdentifiers: ["x"])]

        XCTAssertEqual(store.rules.first?.name, "规则A")
        XCTAssertEqual(store.logs.first?.assetLocalIdentifiers, ["x"])
    }
}
