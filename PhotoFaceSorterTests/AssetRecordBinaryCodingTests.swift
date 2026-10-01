import XCTest
@testable import PhotoFaceSorter

/// 覆盖扫描记录的二进制格式：无损往返、损坏不崩溃、字节布局稳定、旧 JSON 无损迁移。
final class AssetRecordBinaryCodingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // version < 3 会触发针对 pre-v3 的破坏性清理（有意为之），会抢先删掉这里的旧 JSON 夹具
        UserDefaults.standard.set(3, forKey: "cacheSchemaVersion")
    }

    private func tempRoot(_ tag: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(tag)-\(UUID().uuidString)", isDirectory: true)
    }

    private func record(_ id: String,
                        scannedAt: Date = Date(timeIntervalSinceReferenceDate: 700_000_000),
                        faces: Int = 2,
                        modified: Date? = Date(timeIntervalSinceReferenceDate: 690_000_000)) -> AssetRecord {
        AssetRecord(assetLocalIdentifier: id, scannedAt: scannedAt, faceCount: faces, modificationDate: modified)
    }

    // MARK: - 无损往返

    func testRoundTripPreservesEveryField() throws {
        let records = [
            record("a", faces: 0, modified: nil),
            record("b", faces: 7, modified: Date(timeIntervalSinceReferenceDate: 0)),
            record("含中文与 emoji 的标识 🎬", faces: 1, modified: Date(timeIntervalSinceReferenceDate: 123.456))
        ]

        let decoded = try XCTUnwrap(AssetRecordBinaryCoding.decode(AssetRecordBinaryCoding.encode(records)))
        XCTAssertEqual(decoded.count, records.count)

        for (lhs, rhs) in zip(decoded, records) {
            XCTAssertEqual(lhs.assetLocalIdentifier, rhs.assetLocalIdentifier)
            XCTAssertEqual(lhs.faceCount, rhs.faceCount)
            XCTAssertEqual(lhs.scannedAt.timeIntervalSinceReferenceDate,
                           rhs.scannedAt.timeIntervalSinceReferenceDate,
                           accuracy: 1e-9)
            XCTAssertEqual(lhs.modificationDate?.timeIntervalSinceReferenceDate,
                           rhs.modificationDate?.timeIntervalSinceReferenceDate)
        }
    }

    func testEmptyArrayRoundTrips() throws {
        XCTAssertEqual(try XCTUnwrap(AssetRecordBinaryCoding.decode(AssetRecordBinaryCoding.encode([]))).count, 0)
    }

    func testModificationDateNilIsDistinctFromEpoch() throws {
        let decoded = try XCTUnwrap(AssetRecordBinaryCoding.decode(
            AssetRecordBinaryCoding.encode([record("a", modified: nil),
                                            record("b", modified: Date(timeIntervalSinceReferenceDate: 0))])))
        XCTAssertNil(decoded.first { $0.assetLocalIdentifier == "a" }?.modificationDate)
        XCTAssertNotNil(decoded.first { $0.assetLocalIdentifier == "b" }?.modificationDate)
    }

    // MARK: - 损坏数据不能崩溃

    func testCorruptInputsReturnNil() {
        let good = AssetRecordBinaryCoding.encode([record("a"), record("b")])

        XCTAssertNil(AssetRecordBinaryCoding.decode(Data()), "空数据")
        XCTAssertNil(AssetRecordBinaryCoding.decode(Data([0x00, 0x01])), "过短数据")
        XCTAssertNil(AssetRecordBinaryCoding.decode(good.prefix(good.count - 1)), "截断 1 字节")
        XCTAssertNil(AssetRecordBinaryCoding.decode(good.prefix(good.count / 2)), "截断一半")
        XCTAssertNil(AssetRecordBinaryCoding.decode(good + Data([0x00])), "多余尾部字节")

        var badMagic = good
        badMagic[0] = 0x58
        XCTAssertNil(AssetRecordBinaryCoding.decode(badMagic), "魔数错误")
    }

    func testHugeCountIsRejectedQuickly() {
        var payload = Data("PFSR".utf8)
        payload.append(contentsOf: [1, 0, 0, 0])
        payload.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])

        let started = Date()
        XCTAssertNil(AssetRecordBinaryCoding.decode(payload))
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0, "不应尝试巨额分配")
    }

    // MARK: - 字节布局稳定

    /// 固定输入的字节序列必须保持不变，否则已发布的 records.bin 会读不出来
    func testByteLayoutIsPinned() {
        let pinned = record("a", scannedAt: Date(timeIntervalSinceReferenceDate: 0), faces: 0, modified: nil)

        var expected: [UInt8] = Array("PFSR".utf8)
        expected += [1, 0, 0, 0]                       // version
        expected += [1, 0, 0, 0]                       // count
        expected += [1, 0, 0, 0]                       // assetID 长度
        expected += Array("a".utf8)
        expected += [UInt8](repeating: 0, count: 8)    // scannedAt = 0
        expected += [0, 0, 0, 0]                       // faceCount = 0
        expected += [0]                                // hasModificationDate = false

        XCTAssertEqual([UInt8](AssetRecordBinaryCoding.encode([pinned])), expected)
    }

    func testBinaryIsSmallerThanJSON() throws {
        let records = (0..<500).map { record("asset-\($0)-\(UUID().uuidString)", faces: $0 % 5) }
        let binary = AssetRecordBinaryCoding.encode(records)
        let json = try JSONEncoder().encode(Dictionary(uniqueKeysWithValues: records.map { ($0.assetLocalIdentifier, $0) }))

        XCTAssertLessThan(binary.count, json.count, "字典键与值重复存 id 是纯浪费")
    }

    // MARK: - 旧 JSON 迁移

    func testLegacyJSONRecordsAreMigratedLosslessly() throws {
        let root = tempRoot("migrate")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let legacy = ["a": record("a", faces: 3), "b": record("b", faces: 0, modified: nil)]
        try JSONEncoder().encode(legacy).write(to: root.appendingPathComponent("records.json"))

        let store = CacheStore(root: root)
        let loaded = store.records

        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded["a"]?.faceCount, 3)
        XCTAssertNil(loaded["b"]?.modificationDate)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("records.bin").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("records.json").path),
                       "迁移完成后应删除旧 JSON")

        let reloaded = CacheStore(root: root)
        XCTAssertEqual(reloaded.records.count, 2, "再次加载走二进制路径")
        XCTAssertEqual(reloaded.records["a"]?.faceCount, 3)
    }

    func testRecordsBinaryRoundTripThroughStore() {
        let root = tempRoot("binary")
        let store = CacheStore(root: root)
        store.records = ["x": record("x", faces: 9)]
        store.flushPendingWrites()

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("records.bin").path))
        XCTAssertEqual(CacheStore(root: root).records["x"]?.faceCount, 9)

        store.clearFaceCache()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("records.bin").path))
        XCTAssertTrue(CacheStore(root: root).records.isEmpty)
    }

    func testCorruptRecordsBinaryIsQuarantined() throws {
        let root = tempRoot("corrupt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("PFSR".utf8).write(to: root.appendingPathComponent("records.bin"))

        let store = CacheStore(root: root)
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("records.bin.corrupt").path))
    }
}
