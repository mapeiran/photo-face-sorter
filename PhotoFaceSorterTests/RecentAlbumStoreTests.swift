import XCTest
@testable import PhotoFaceSorter

final class RecentAlbumStoreTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "RecentAlbumStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testMostRecentFirstAndDeduplicated() {
        let defaults = makeDefaults()
        RecentAlbumStore.record("妈妈", to: defaults)
        RecentAlbumStore.record("爸爸", to: defaults)
        RecentAlbumStore.record("妈妈", to: defaults)
        XCTAssertEqual(RecentAlbumStore.load(from: defaults), ["妈妈", "爸爸"])
    }

    func testCapAtMaxCount() {
        let defaults = makeDefaults()
        for name in ["a", "b", "c", "d", "e", "f"] {
            RecentAlbumStore.record(name, to: defaults)
        }
        let list = RecentAlbumStore.load(from: defaults)
        XCTAssertEqual(list.count, RecentAlbumStore.maxCount)
        XCTAssertEqual(list.first, "f")
    }

    func testEmptyNameIsIgnored() {
        let defaults = makeDefaults()
        RecentAlbumStore.record("   ", to: defaults)
        XCTAssertTrue(RecentAlbumStore.load(from: defaults).isEmpty)
    }

    func testFiltersMissingAlbums() {
        XCTAssertEqual(RecentAlbumStore.existing(["妈妈", "已删除", "爸爸"],
                                                 in: ["妈妈", "爸爸"]),
                       ["妈妈", "爸爸"])
    }
}
