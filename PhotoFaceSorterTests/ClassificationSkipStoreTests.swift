import XCTest
@testable import PhotoFaceSorter

final class ClassificationSkipStoreTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "ClassificationSkipStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testRoundTrip() {
        let defaults = makeDefaults()
        let first = UUID()
        let second = UUID()
        ClassificationSkipStore.save([first, second], to: defaults)
        XCTAssertEqual(ClassificationSkipStore.load(from: defaults), [first, second])
    }

    func testEmptyByDefault() {
        XCTAssertTrue(ClassificationSkipStore.load(from: makeDefaults()).isEmpty)
    }

    func testIgnoresInvalidStrings() {
        let defaults = makeDefaults()
        let valid = UUID()
        defaults.set(["not-a-uuid", valid.uuidString], forKey: ClassificationSkipStore.defaultsKey)
        XCTAssertEqual(ClassificationSkipStore.load(from: defaults), [valid])
    }
}
