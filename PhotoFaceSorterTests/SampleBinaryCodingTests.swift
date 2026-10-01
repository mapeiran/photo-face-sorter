import XCTest
import CoreGraphics
@testable import PhotoFaceSorter

/// 覆盖二进制样本格式：逐字段无损、损坏数据不崩溃、以及从旧版 JSON 的无损迁移。
final class SampleBinaryCodingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // 模拟「已在使用旧版本」的升级路径：version < 3 会触发针对 pre-v3 的
        // 破坏性清理（有意为之），那会抢先删掉这里要用的旧 JSON 夹具。
        UserDefaults.standard.set(3, forKey: "cacheSchemaVersion")
    }

    private func tempRoot(_ tag: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(tag)-\(UUID().uuidString)", isDirectory: true)
    }

    private func sample(_ asset: String,
                        feature: [Float] = [1, 2, 3, 4],
                        person: UUID? = nil,
                        ignored: Bool = false,
                        manual: Bool? = nil,
                        box: CGRect = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)) -> FaceSample {
        FaceSample(assetLocalIdentifier: asset,
                   boundingBox: box,
                   feature: feature,
                   personID: person,
                   isIgnored: ignored,
                   assignmentIsManual: manual)
    }

    // MARK: - 无损往返

    func testRoundTripPreservesEveryField() throws {
        let person = UUID()
        let samples = [
            sample("a", feature: [1.5, -2.25, 0, 9.75], person: person, ignored: false, manual: true),
            sample("b", feature: [], person: nil, ignored: true, manual: nil),
            sample("c", feature: [0], person: person, ignored: false, manual: false),
            sample("含中文与 emoji 的标识 🎬", feature: [1, 2], person: nil, ignored: false, manual: true),
            sample("d", feature: [Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude],
                   person: person, ignored: false, manual: false),
            sample("e", feature: [1, 2, 3], person: nil, ignored: false, manual: nil,
                   box: CGRect(x: 0, y: 0, width: 1, height: 1))
        ]

        let decoded = try XCTUnwrap(SampleBinaryCoding.decode(SampleBinaryCoding.encode(samples)))
        XCTAssertEqual(decoded.count, samples.count)

        for (lhs, rhs) in zip(decoded, samples) {
            XCTAssertEqual(lhs.id, rhs.id)
            XCTAssertEqual(lhs.assetLocalIdentifier, rhs.assetLocalIdentifier)
            XCTAssertEqual(lhs.boundingBox, rhs.boundingBox)
            XCTAssertEqual(lhs.featureData, rhs.featureData)
            XCTAssertEqual(lhs.personID, rhs.personID)
            XCTAssertEqual(lhs.isIgnored, rhs.isIgnored)
            XCTAssertEqual(lhs.assignmentIsManual, rhs.assignmentIsManual)
            XCTAssertEqual(lhs.createdAt.timeIntervalSinceReferenceDate,
                           rhs.createdAt.timeIntervalSinceReferenceDate,
                           accuracy: 1e-9)
        }
    }

    func testEmptyArrayRoundTrips() throws {
        let decoded = try XCTUnwrap(SampleBinaryCoding.decode(SampleBinaryCoding.encode([])))
        XCTAssertTrue(decoded.isEmpty)
    }

    // MARK: - 损坏数据不能崩溃

    func testCorruptInputsReturnNil() {
        let good = SampleBinaryCoding.encode([sample("a"), sample("b")])

        XCTAssertNil(SampleBinaryCoding.decode(Data()), "空数据")
        XCTAssertNil(SampleBinaryCoding.decode(Data([0x00, 0x01])), "过短数据")
        XCTAssertNil(SampleBinaryCoding.decode(good.prefix(good.count - 1)), "截断 1 字节")
        XCTAssertNil(SampleBinaryCoding.decode(good.prefix(good.count / 2)), "截断一半")

        var badMagic = good
        badMagic[0] = 0x58
        XCTAssertNil(SampleBinaryCoding.decode(badMagic), "魔数错误")

        XCTAssertNil(SampleBinaryCoding.decode(good + Data([0x00])), "多余尾部字节")
    }

    /// 伪造的超大 count 必须在分配内存之前被拒绝
    func testHugeCountIsRejectedQuickly() {
        var payload = Data("PFSS".utf8)
        payload.append(contentsOf: [1, 0, 0, 0])              // version 1
        payload.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])  // count = 4294967295

        let started = Date()
        XCTAssertNil(SampleBinaryCoding.decode(payload))
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0, "不应尝试巨额分配")
    }

    // MARK: - 体积

    func testBinaryIsMeaningfullySmallerThanJSON() throws {
        let samples = (0..<200).map { index in
            sample("asset-\(index)-\(UUID().uuidString)",
                   feature: (0..<256).map { Float($0 % 17) * 0.5 },
                   person: UUID(),
                   manual: false)
        }
        let binary = SampleBinaryCoding.encode(samples)
        let json = try JSONEncoder().encode(samples)

        XCTAssertLessThan(binary.count, json.count)
        XCTAssertLessThan(Double(binary.count), Double(json.count) * 0.8,
                          "二进制应显著小于 JSON（base64 膨胀约 33%）")
    }

    // MARK: - 旧 JSON 迁移

    func testLegacyJSONIsMigratedLosslesslyToBinary() throws {
        let root = tempRoot("migrate")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let legacy = [sample("a", feature: [1, 2, 3], manual: true),
                      sample("b", feature: [4, 5, 6], ignored: true)]
        try JSONEncoder().encode(legacy).write(to: root.appendingPathComponent("samples.json"))

        let store = CacheStore(root: root)
        let loaded = store.samples

        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.map(\.assetLocalIdentifier).sorted(), ["a", "b"])
        XCTAssertEqual(loaded.first { $0.assetLocalIdentifier == "a" }?.assignmentIsManual, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("samples.bin").path),
                      "应写出二进制文件")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("samples.json").path),
                       "迁移完成后应删除旧 JSON")

        // 再开一个实例：这次走二进制路径
        let reloaded = CacheStore(root: root)
        XCTAssertEqual(reloaded.samples.count, 2)
        XCTAssertEqual(reloaded.samples.first { $0.assetLocalIdentifier == "a" }?.feature, [1, 2, 3])
    }

    func testBinaryStoreRoundTrip() {
        let root = tempRoot("binary")
        let person = UUID()
        let store = CacheStore(root: root)
        store.samples = [sample("x", feature: [7, 8], person: person, manual: true)]
        store.flushPendingWrites()

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("samples.bin").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("samples.json").path),
                       "不应再产生 JSON 样本文件")

        let reloaded = CacheStore(root: root)
        XCTAssertEqual(reloaded.samples.first?.personID, person)
        XCTAssertEqual(reloaded.samples.first?.feature, [7, 8])
    }

    func testCorruptBinaryIsQuarantined() throws {
        let root = tempRoot("corruptbin")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("PFSS".utf8).write(to: root.appendingPathComponent("samples.bin"))

        let store = CacheStore(root: root)
        XCTAssertTrue(store.samples.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("samples.bin.corrupt").path),
                      "损坏的二进制文件应被改名保留")
    }
}
