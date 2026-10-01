import XCTest
@testable import PhotoFaceSorter

/// 扫描排除相簿的三态判定：
/// - 显式排除 → 跳过；
/// - 显式包含 → 不跳过（覆盖「自定义相簿默认跳过」）；
/// - 其余：自定义相簿默认跳过，系统 / 同步相簿默认参与。
final class AlbumExclusionStoreTests: XCTestCase {

    private func isExcluded(_ id: String,
                            custom: Bool,
                            excluded: Set<String> = [],
                            included: Set<String> = []) -> Bool {
        AlbumExclusionStore.isExcludedFromScan(albumLocalID: id,
                                               isCustomAlbum: custom,
                                               excluded: excluded,
                                               included: included)
    }

    func testCustomAlbumIsExcludedByDefault() {
        XCTAssertTrue(isExcluded("a", custom: true), "自定义相簿默认视为已归类，扫描跳过")
    }

    func testSystemAlbumParticipatesByDefault() {
        XCTAssertFalse(isExcluded("a", custom: false), "系统相簿默认参与扫描")
    }

    func testExplicitInclusionOverridesCustomDefault() {
        XCTAssertFalse(isExcluded("a", custom: true, included: ["a"]),
                       "手动取消排除后，自定义相簿应重新参与扫描")
    }

    func testExplicitExclusionSkipsSystemAlbum() {
        XCTAssertTrue(isExcluded("a", custom: false, excluded: ["a"]))
    }

    func testExplicitExclusionWinsWhenBothSetsContainAlbum() {
        XCTAssertTrue(isExcluded("a", custom: true, excluded: ["a"], included: ["a"]),
                      "显式排除优先，避免状态自相矛盾")
    }

    func testOtherAlbumsAreNotAffected() {
        XCTAssertFalse(isExcluded("b", custom: true, excluded: ["a"], included: ["b"]))
        XCTAssertTrue(isExcluded("c", custom: true, excluded: ["a"], included: ["b"]))
    }

    func testPersistenceRoundTrip() {
        let defaults = UserDefaults(suiteName: "AlbumExclusionStoreTests-\(UUID().uuidString)")!
        AlbumExclusionStore.saveExcluded(["a", "b"], to: defaults)
        AlbumExclusionStore.saveIncluded(["c"], to: defaults)
        XCTAssertEqual(AlbumExclusionStore.loadExcluded(from: defaults), ["a", "b"])
        XCTAssertEqual(AlbumExclusionStore.loadIncluded(from: defaults), ["c"])
    }
}
