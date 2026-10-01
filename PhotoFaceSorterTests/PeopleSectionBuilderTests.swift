import XCTest
@testable import PhotoFaceSorter

/// 人物页分节：展示系统「照片」App 的**全部**文件夹，
/// 并在每个文件夹下列出其中的相簿（即使那些相簿还没有对应人物）。
final class PeopleSectionBuilderTests: XCTestCase {

    private func structure() -> AlbumFolderStructure {
        var s = AlbumFolderStructure()
        s.folderOrder = ["同学", "明星", "空文件夹"]
        s.albumsByFolder = [
            "同学": ["张三", "同学会"],
            "明星": ["赵今麦"],
            "空文件夹": [],
        ]
        s.folderByAlbumTitle = [
            "张三": "同学",
            "同学会": "同学",
            "赵今麦": "明星",
        ]
        s.ungroupedAlbumTitles = ["妈妈", "旅行"]
        return s
    }

    func testAllFoldersArePresentInSystemOrder() {
        let sections = PeopleSectionBuilder.sections(people: [], structure: structure())
        XCTAssertEqual(sections.map(\.title), ["同学", "明星", "空文件夹", "未分组"],
                       "空文件夹也要展示，顺序跟随系统")
        XCTAssertTrue(sections.contains { $0.title == "空文件夹" }, "空文件夹不能因为没人而消失")
    }

    func testEmptyFolderHasNoAlbumCells() {
        let sections = PeopleSectionBuilder.sections(people: [], structure: structure())
        let empty = sections.first { $0.title == "空文件夹" }
        XCTAssertTrue(empty?.isEmpty == true)
    }

    func testAlbumWithoutPersonIsListedAsAlbumCell() {
        let sections = PeopleSectionBuilder.sections(people: [], structure: structure())
        let classmates = sections.first { $0.title == "同学" }
        XCTAssertEqual(classmates?.albumTitles, ["张三", "同学会"], "还没成为人物的相簿也要列出来")
        XCTAssertTrue(classmates?.people.isEmpty == true)
    }

    func testPersonNamedAfterFolderAlbumGoesIntoThatFolder() {
        let zhang = Person(name: "张三")
        let zhao = Person(name: "赵今麦")
        let sections = PeopleSectionBuilder.sections(people: [zhang, zhao], structure: structure())

        let classmates = sections.first { $0.title == "同学" }
        XCTAssertEqual(classmates?.people.map(\.id), [zhang.id])
        XCTAssertEqual(classmates?.albumTitles, ["同学会"],
                       "已经有对应人物的相簿不应再作为相簿卡片重复出现")

        let stars = sections.first { $0.title == "明星" }
        XCTAssertEqual(stars?.people.map(\.id), [zhao.id])
    }

    func testUngroupedAlbumsAndTheirPeople() {
        let mom = Person(name: "妈妈")
        let sections = PeopleSectionBuilder.sections(people: [mom], structure: structure())
        let ungrouped = sections.first { $0.id == "ungrouped" }
        XCTAssertEqual(ungrouped?.title, "未分组")
        XCTAssertEqual(ungrouped?.people.map(\.id), [mom.id])
        XCTAssertEqual(ungrouped?.albumTitles, ["旅行"])
    }

    func testPeopleWithoutAlbumGoToAIGroup() {
        let ai = Person(name: "人物 1")
        let named = Person(name: "张三")
        let sections = PeopleSectionBuilder.sections(people: [ai, named], structure: structure())
        let aiSection = sections.first { $0.id == "ai" }
        XCTAssertEqual(aiSection?.people.map(\.id), [ai.id])
        XCTAssertTrue(aiSection?.albumTitles.isEmpty == true)
    }

    func testNoFoldersFallsBackToSingleAlbumSection() {
        var s = AlbumFolderStructure()
        s.ungroupedAlbumTitles = ["妈妈"]
        let sections = PeopleSectionBuilder.sections(people: [Person(name: "妈妈")], structure: s)
        XCTAssertEqual(sections.map(\.title), ["相簿"])
        XCTAssertEqual(sections.first?.people.map(\.name), ["妈妈"])
    }

    /// 两个同名但样本不同的分组都应保留（不能凭空吞掉一个人物），
    /// 但「张三」这张相簿卡片不能重复出现。
    func testDuplicatePersonNamesDoNotDuplicateAlbumCards() {
        let first = Person(name: "张三")
        let second = Person(name: "张三")
        let sections = PeopleSectionBuilder.sections(people: [first, second], structure: structure())
        let classmates = sections.first { $0.title == "同学" }
        XCTAssertEqual(classmates?.people.count, 2, "同名人物都应保留")
        XCTAssertEqual(Set(classmates?.people.map(\.id) ?? []), [first.id, second.id])
        XCTAssertEqual(classmates?.albumTitles, ["同学会"], "已有对应人物的相簿不应再作为相簿卡片出现")
    }
}
