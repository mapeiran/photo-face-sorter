import XCTest
@testable import PhotoFaceSorter

/// 覆盖扫描的两个关键不变量：
/// 1. 取不到图片的照片**不能**被标记为已扫描；
/// 2. 因此它下次扫描仍然会被挑出来重试。
///
/// 背景：iCloud 尚未下载或读取失败时拿不到图片、人脸数为 0。
/// 若照样写记录，该照片会被当成「已扫描、0 张人脸」，而 modificationDate 没有变化，
/// 增量扫描再也不会挑中它 —— 人脸永久丢失且没有任何报错。
final class ScanPolicyTests: XCTestCase {

    private let modified = Date(timeIntervalSinceReferenceDate: 700_000_000)
    private let otherModified = Date(timeIntervalSinceReferenceDate: 710_000_000)

    // MARK: - ScanRecordPolicy

    func testNoRecordWhenImageIsUnavailable() {
        XCTAssertNil(ScanRecordPolicy.record(assetLocalIdentifier: "asset-1",
                                             modificationDate: modified,
                                             imageAvailable: false,
                                             faceCount: 0),
                     "取不到图片时不能写扫描记录，否则会永不再重试")
    }

    func testRecordWhenImageIsAvailableEvenWithZeroFaces() {
        let scannedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let record = ScanRecordPolicy.record(assetLocalIdentifier: "asset-1",
                                             modificationDate: modified,
                                             imageAvailable: true,
                                             faceCount: 0,
                                             scannedAt: scannedAt)
        XCTAssertNotNil(record, "确实没有脸的照片应当被标记为已扫描")
        XCTAssertEqual(record?.faceCount, 0)
        XCTAssertEqual(record?.assetLocalIdentifier, "asset-1")
        XCTAssertEqual(record?.modificationDate, modified)
        XCTAssertEqual(record?.scannedAt, scannedAt)
    }

    func testRecordKeepsFaceCountAndModificationDate() {
        let record = ScanRecordPolicy.record(assetLocalIdentifier: "asset-2",
                                             modificationDate: modified,
                                             imageAvailable: true,
                                             faceCount: 3)
        XCTAssertEqual(record?.faceCount, 3)
        XCTAssertEqual(record?.modificationDate, modified)
    }

    func testRecordAllowsNilModificationDate() {
        let record = ScanRecordPolicy.record(assetLocalIdentifier: "asset-3",
                                             modificationDate: nil,
                                             imageAvailable: true,
                                             faceCount: 1)
        XCTAssertNotNil(record)
        XCTAssertNil(record?.modificationDate)
    }

    // MARK: - ScanPlanPolicy

    func testUnscannedAssetNeedsScan() {
        XCTAssertTrue(ScanPlanPolicy.needsScan(assetLocalIdentifier: "a",
                                               modificationDate: modified,
                                               isExcluded: false,
                                               records: [:]))
    }

    func testExcludedAlbumAssetIsSkipped() {
        XCTAssertFalse(ScanPlanPolicy.needsScan(assetLocalIdentifier: "a",
                                                modificationDate: modified,
                                                isExcluded: true,
                                                records: [:]))
    }


    func testAlreadyScannedUnchangedAssetIsSkipped() {
        let record = AssetRecord(assetLocalIdentifier: "a",
                                 scannedAt: Date(),
                                 faceCount: 2,
                                 modificationDate: modified)
        XCTAssertFalse(ScanPlanPolicy.needsScan(assetLocalIdentifier: "a",
                                                modificationDate: modified,
                                                isExcluded: false,
                                                records: ["a": record]))
    }

    func testModifiedAssetNeedsRescan() {
        let record = AssetRecord(assetLocalIdentifier: "a",
                                 scannedAt: Date(),
                                 faceCount: 2,
                                 modificationDate: modified)
        XCTAssertTrue(ScanPlanPolicy.needsScan(assetLocalIdentifier: "a",
                                               modificationDate: otherModified,
                                               isExcluded: false,
                                               records: ["a": record]),
                      "照片内容被修改后应重新识别")
    }

    // MARK: - 闭环

    /// 完整闭环：读不到图片 → 不写记录 → 下次仍是待扫描
    func testUnavailableAssetIsRetriedOnTheNextRun() {
        var records: [String: AssetRecord] = [:]

        // 第一次扫描：iCloud 未下载，取不到图片
        if let record = ScanRecordPolicy.record(assetLocalIdentifier: "asset-1",
                                                modificationDate: modified,
                                                imageAvailable: false,
                                                faceCount: 0) {
            records[record.assetLocalIdentifier] = record
        }
        XCTAssertTrue(records.isEmpty)

        // 第二次扫描：同一条照片，modificationDate 未变，仍应被挑出来
        XCTAssertTrue(ScanPlanPolicy.needsScan(assetLocalIdentifier: "asset-1",
                                               modificationDate: modified,
                                               isExcluded: false,
                                               records: records),
                      "读不到的照片下次扫描必须仍然是待扫描状态")

        // 第三次：这次下载成功但确实没有脸 → 写记录 → 之后不再重复扫描
        if let record = ScanRecordPolicy.record(assetLocalIdentifier: "asset-1",
                                                modificationDate: modified,
                                                imageAvailable: true,
                                                faceCount: 0) {
            records[record.assetLocalIdentifier] = record
        }
        XCTAssertFalse(ScanPlanPolicy.needsScan(assetLocalIdentifier: "asset-1",
                                                modificationDate: modified,
                                                isExcluded: false,
                                                records: records),
                       "成功确认没有脸之后不应反复重扫")
    }
}
