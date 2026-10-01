import XCTest
@testable import PhotoFaceSorter

/// 归类审核的提议生成：只把「不在任何相簿、已归属人物、未被忽略」的照片列出来。
final class ClassificationProposalPolicyTests: XCTestCase {

    private func sample(_ asset: String, person: UUID?, ignored: Bool = false) -> FaceSample {
        FaceSample(assetLocalIdentifier: asset,
                   boundingBox: .zero,
                   feature: [1, 0, 0, 0],
                   personID: person,
                   isIgnored: ignored)
    }

    func testLoosePhotosBecomeProposals() {
        let mom = Person(name: "妈妈")
        let ai = Person(name: "人物 1")
        let proposals = ClassificationProposalPolicy.proposals(
            people: [mom, ai],
            samples: [sample("a", person: mom.id),
                      sample("b", person: mom.id),
                      sample("c", person: ai.id)],
            albumedAssetIDs: ["b"],
            existingAlbumTitles: ["妈妈"])

        XCTAssertEqual(proposals.count, 2)
        XCTAssertEqual(proposals[0].personName, "妈妈")
        XCTAssertEqual(proposals[0].assetIDs, ["a"], "已在相簿里的照片不再需要归类")
        XCTAssertTrue(proposals[0].albumExists)
        XCTAssertEqual(proposals[1].personName, "人物 1")
        XCTAssertEqual(proposals[1].assetIDs, ["c"])
        XCTAssertFalse(proposals[1].albumExists, "同名相簿不存在时会新建")
    }

    func testPersonWithEverythingInAlbumsIsOmitted() {
        let person = Person(name: "爸爸")
        let proposals = ClassificationProposalPolicy.proposals(
            people: [person],
            samples: [sample("a", person: person.id)],
            albumedAssetIDs: ["a"],
            existingAlbumTitles: [])
        XCTAssertTrue(proposals.isEmpty)
    }

    func testUnassignedAndIgnoredSamplesAreSkipped() {
        let person = Person(name: "妈妈")
        let proposals = ClassificationProposalPolicy.proposals(
            people: [person],
            samples: [sample("a", person: nil),
                      sample("b", person: person.id, ignored: true),
                      sample("c", person: person.id)],
            albumedAssetIDs: [],
            existingAlbumTitles: [])
        XCTAssertEqual(proposals.count, 1)
        XCTAssertEqual(proposals[0].assetIDs, ["c"])
    }

    func testDuplicateFacesOfTheSamePhotoCountOnce() {
        let person = Person(name: "妈妈")
        let proposals = ClassificationProposalPolicy.proposals(
            people: [person],
            samples: [sample("a", person: person.id),
                      sample("a", person: person.id),
                      sample("b", person: person.id)],
            albumedAssetIDs: [],
            existingAlbumTitles: [])
        XCTAssertEqual(proposals[0].assetIDs, ["a", "b"])
    }
}
