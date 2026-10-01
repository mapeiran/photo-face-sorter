import XCTest
@testable import PhotoFaceSorter

final class PhotoDetailTests: XCTestCase {

    func testDimensionsText() {
        let detail = PhotoDetail(mediaTypeText: "照片",
                                 pixelWidth: 4032,
                                 pixelHeight: 3024,
                                 isFavorite: false,
                                 creationDate: nil,
                                 modificationDate: nil,
                                 locationText: nil,
                                 resourceFileNames: ["IMG_0001.HEIC"])
        XCTAssertEqual(detail.dimensionsText, "4032 × 3024")
    }

    func testEquatableComparesAllFields() {
        let base = PhotoDetail(mediaTypeText: "照片",
                               pixelWidth: 1,
                               pixelHeight: 2,
                               isFavorite: false,
                               creationDate: nil,
                               modificationDate: nil,
                               locationText: nil,
                               resourceFileNames: [])
        var other = base
        other.isFavorite = true
        XCTAssertNotEqual(base, other)
        XCTAssertEqual(other, other)
    }
}
