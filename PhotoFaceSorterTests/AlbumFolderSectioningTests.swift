import XCTest
@testable import PhotoFaceSorter

/// 相簿按系统文件夹分节：顺序跟随系统，没进文件夹的归「未分组」。
final class AlbumFolderSectioningTests: XCTestCase {

    func testGroupsByFolderInSystemOrder() {
        let sections = AlbumFolderSectioning.sections(
            albumTitles: ["a", "b", "c", "d"],
            folderByAlbumTitle: ["a": "同学", "b": "明星", "c": "同学"],
            folderOrder: ["明星", "同学"])
        XCTAssertEqual(sections.map(\.title), ["明星", "同学", "未分组"])
        XCTAssertEqual(sections[0].albumTitles, ["b"])
        XCTAssertEqual(sections[1].albumTitles, ["a", "c"])
        XCTAssertEqual(sections[2].albumTitles, ["d"])
    }

    func testNoFoldersFallsBackToSingleSection() {
        let sections = AlbumFolderSectioning.sections(
            albumTitles: ["a", "b"],
            folderByAlbumTitle: [:],
            folderOrder: [])
        XCTAssertEqual(sections.map(\.title), ["已有相簿"])
        XCTAssertEqual(sections.first?.albumTitles, ["a", "b"])
    }

    func testFolderNotInSystemOrderAppearsAfter() {
        let sections = AlbumFolderSectioning.sections(
            albumTitles: ["a", "b"],
            folderByAlbumTitle: ["a": "已知", "b": "额外"],
            folderOrder: ["已知"])
        XCTAssertEqual(sections.map(\.title), ["已知", "额外"])
    }

    func testEmptyInput() {
        let sections = AlbumFolderSectioning.sections(albumTitles: [],
                                                      folderByAlbumTitle: [:],
                                                      folderOrder: [])
        XCTAssertTrue(sections.isEmpty)
    }
}
