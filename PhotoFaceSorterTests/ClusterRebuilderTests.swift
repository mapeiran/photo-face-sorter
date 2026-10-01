import XCTest
@testable import PhotoFaceSorter

/// 覆盖「重聚类不得撤销用户的手动修正」这一关键保证。
final class ClusterRebuilderTests: XCTestCase {

    /// 两个相距很远的特征方向，阈值 0.5 时一定不会被聚成一类
    private let clusterA: [Float] = [1, 0, 0, 0]
    private let clusterB: [Float] = [0, 1, 0, 0]

    private func tempStore() -> CacheStore {
        CacheStore(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("ClusterRebuilderTests-\(UUID().uuidString)", isDirectory: true))
    }

    func testManualAssignmentSurvivesRebuild() throws {
        let store = tempStore()
        let manualPerson = Person(name: "张三")

        let manual = FaceSample(assetLocalIdentifier: "a1",
                                boundingBox: .zero,
                                feature: clusterA,
                                personID: manualPerson.id,
                                isIgnored: false,
                                assignmentIsManual: true)
        store.people = [manualPerson]
        store.samples = [manual,
                         FaceSample(assetLocalIdentifier: "a2", boundingBox: .zero, feature: clusterA),
                         FaceSample(assetLocalIdentifier: "b1", boundingBox: .zero, feature: clusterB)]

        ClusterRebuilder.rebuild(store: store, threshold: 0.5)

        let rebuilt = try XCTUnwrap(store.samples.first { $0.assetLocalIdentifier == "a1" })
        XCTAssertEqual(rebuilt.personID, manualPerson.id, "手动指定的归属不能被重聚类改掉")
        XCTAssertTrue(store.people.contains { $0.id == manualPerson.id }, "被锁定的人物不能被清理掉")
        XCTAssertEqual(store.people.first { $0.id == manualPerson.id }?.name, "张三", "命名必须保留")
    }

    /// 手动「移出人物」（personID 为 nil 但被锁定）同样不能被重新分配
    func testManuallyUnassignedSampleStaysUnassigned() throws {
        let store = tempStore()
        let manual = FaceSample(assetLocalIdentifier: "a1",
                                boundingBox: .zero,
                                feature: clusterA,
                                personID: nil,
                                isIgnored: false,
                                assignmentIsManual: true)
        store.samples = [manual,
                         FaceSample(assetLocalIdentifier: "a2", boundingBox: .zero, feature: clusterA)]

        ClusterRebuilder.rebuild(store: store, threshold: 0.5)

        let rebuilt = try XCTUnwrap(store.samples.first { $0.assetLocalIdentifier == "a1" })
        XCTAssertNil(rebuilt.personID, "用户手动移出的人脸不应被重新分配")
    }

    func testIgnoredSampleIsNeverReassigned() throws {
        let store = tempStore()
        let ignored = FaceSample(assetLocalIdentifier: "a1",
                                 boundingBox: .zero,
                                 feature: clusterA,
                                 personID: nil,
                                 isIgnored: true,
                                 assignmentIsManual: true)
        store.samples = [ignored,
                         FaceSample(assetLocalIdentifier: "a2", boundingBox: .zero, feature: clusterA)]

        ClusterRebuilder.rebuild(store: store, threshold: 0.5)

        let rebuilt = try XCTUnwrap(store.samples.first { $0.assetLocalIdentifier == "a1" })
        XCTAssertTrue(rebuilt.isIgnored)
        XCTAssertNil(rebuilt.personID)
    }

    /// 自动聚类的样本仍应被正常分组
    func testUnlockedSamplesAreGrouped() throws {
        let store = tempStore()
        store.samples = [FaceSample(assetLocalIdentifier: "a1", boundingBox: .zero, feature: clusterA),
                         FaceSample(assetLocalIdentifier: "a2", boundingBox: .zero, feature: clusterA),
                         FaceSample(assetLocalIdentifier: "b1", boundingBox: .zero, feature: clusterB)]

        ClusterRebuilder.rebuild(store: store, threshold: 0.5)

        let a1 = try XCTUnwrap(store.samples.first { $0.assetLocalIdentifier == "a1" })
        let a2 = try XCTUnwrap(store.samples.first { $0.assetLocalIdentifier == "a2" })
        let b1 = try XCTUnwrap(store.samples.first { $0.assetLocalIdentifier == "b1" })
        XCTAssertNotNil(a1.personID)
        XCTAssertEqual(a1.personID, a2.personID)
        XCTAssertNotEqual(a1.personID, b1.personID)
    }

    /// 新建人物编号要从现有「人物 N」的最大值续接，避免重名
    func testNewPeopleDoNotCollideWithExistingNames() {
        let store = tempStore()
        let existing = Person(name: "人物 3")
        let manual = FaceSample(assetLocalIdentifier: "a1",
                                boundingBox: .zero,
                                feature: clusterA,
                                personID: existing.id,
                                isIgnored: false,
                                assignmentIsManual: true)
        store.people = [existing]
        store.samples = [manual,
                         FaceSample(assetLocalIdentifier: "b1", boundingBox: .zero, feature: clusterB)]

        ClusterRebuilder.rebuild(store: store, threshold: 0.5)

        let names = store.people.map(\.name)
        XCTAssertTrue(names.contains("人物 3"))
        XCTAssertTrue(names.contains("人物 4"), "新人物应续接编号，实际为 \(names)")
        XCTAssertFalse(names.contains("人物 1"))
    }

    /// 自动命名的空人物应被清理（否则每次扫描都会留下垃圾分组）
    func testAutoNamedEmptyPeopleAreRemoved() {
        let store = tempStore()
        store.people = [Person(name: "人物 5")]
        store.samples = [FaceSample(assetLocalIdentifier: "a1", boundingBox: .zero, feature: clusterA)]

        ClusterRebuilder.rebuild(store: store, threshold: 0.5)

        XCTAssertFalse(store.people.contains { $0.name == "人物 5" })
    }

    /// 用户命名过的空分组必须保留 —— 否则「把最后一张脸移出某人」会连名字一起丢掉
    func testUserNamedEmptyPeopleArePreserved() {
        let store = tempStore()
        let named = Person(name: "张三")
        store.people = [named]
        store.samples = [FaceSample(assetLocalIdentifier: "a1", boundingBox: .zero, feature: clusterA)]

        ClusterRebuilder.rebuild(store: store, threshold: 0.5)

        XCTAssertTrue(store.people.contains { $0.id == named.id }, "用户命名过的空分组不应被自动删除")
        XCTAssertEqual(store.people.first { $0.id == named.id }?.name, "张三")
    }

    // MARK: - 按相簿名命名

    func testAutoGroupIsNamedAfterItsAlbum() {
        let store = tempStore()
        store.samples = [FaceSample(assetLocalIdentifier: "a1", boundingBox: .zero, feature: clusterA),
                         FaceSample(assetLocalIdentifier: "a2", boundingBox: .zero, feature: clusterA)]
        ClusterRebuilder.rebuild(store: store, threshold: 0.5,
                                 albumNamesByAsset: ["a1": ["妈妈"], "a2": ["妈妈"]])
        XCTAssertEqual(store.people.map { $0.name }, ["妈妈"])
    }

    /// 用户自己起过的名字不能被相簿名覆盖
    func testUserNamedPersonIsNotRenamedByAlbum() {
        let store = tempStore()
        let person = Person(name: "我起的名字")
        let manual = FaceSample(assetLocalIdentifier: "a1", boundingBox: .zero, feature: clusterA,
                                personID: person.id, isIgnored: false, assignmentIsManual: true)
        store.people = [person]
        store.samples = [manual]
        ClusterRebuilder.rebuild(store: store, threshold: 0.5,
                                 albumNamesByAsset: ["a1": ["妈妈"]])
        XCTAssertEqual(store.people.first?.name, "我起的名字")
    }

    /// 同一个相簿名下只能有一个分组，否则人物页会出现两个「妈妈」
    func testGroupsNamedAfterSameAlbumAreMerged() {
        let store = tempStore()
        store.samples = [FaceSample(assetLocalIdentifier: "a1", boundingBox: .zero, feature: clusterA),
                         FaceSample(assetLocalIdentifier: "a2", boundingBox: .zero, feature: clusterA),
                         FaceSample(assetLocalIdentifier: "b1", boundingBox: .zero, feature: clusterB),
                         FaceSample(assetLocalIdentifier: "b2", boundingBox: .zero, feature: clusterB)]
        ClusterRebuilder.rebuild(store: store, threshold: 0.5,
                                 albumNamesByAsset: ["a1": ["妈妈"], "a2": ["妈妈"],
                                                     "b1": ["妈妈"], "b2": ["妈妈"]])
        XCTAssertEqual(store.people.count, 1, "实际分组：\(store.people.map { $0.name })")
        XCTAssertEqual(store.people.first?.name, "妈妈")
        XCTAssertEqual(Set(store.samples.compactMap { $0.personID }).count, 1, "样本也要并到一起")
    }

    func testGroupWithoutAnyAlbumKeepsAutoName() {
        let store = tempStore()
        store.samples = [FaceSample(assetLocalIdentifier: "a1", boundingBox: .zero, feature: clusterA),
                         FaceSample(assetLocalIdentifier: "a2", boundingBox: .zero, feature: clusterA)]
        ClusterRebuilder.rebuild(store: store, threshold: 0.5, albumNamesByAsset: [:])
        XCTAssertEqual(store.people.first?.name, "人物 1")
    }

    // MARK: - 相簿优先、AI 兜底

    /// 只要同在同一个自定义相簿，哪怕两张脸完全不像，也必须归到同一个人物
    func testAlbumMembershipBeatsFaceClustering() {
        let store = tempStore()
        store.samples = [FaceSample(assetLocalIdentifier: "a1", boundingBox: .zero, feature: clusterA),
                         FaceSample(assetLocalIdentifier: "b1", boundingBox: .zero, feature: clusterB)]
        ClusterRebuilder.rebuild(store: store, threshold: 0.5,
                                 albumNamesByAsset: ["a1": ["妈妈"], "b1": ["妈妈"]])

        XCTAssertEqual(store.people.map { $0.name }, ["妈妈"], "同一相簿只应产生一个人物")
        let a1 = store.samples.first { $0.assetLocalIdentifier == "a1" }?.personID
        let b1 = store.samples.first { $0.assetLocalIdentifier == "b1" }?.personID
        XCTAssertNotNil(a1)
        XCTAssertEqual(a1, b1, "相簿优先于人脸相似度")
    }

    /// 没有相簿的照片交给 AI：和相簿照片聚成一簇就跟着走
    func testAlbumLessPhotoFollowsTheClusterItBelongsTo() {
        let store = tempStore()
        store.samples = [FaceSample(assetLocalIdentifier: "a1", boundingBox: .zero, feature: clusterA),
                         FaceSample(assetLocalIdentifier: "a2", boundingBox: .zero, feature: clusterA),
                         FaceSample(assetLocalIdentifier: "b1", boundingBox: .zero, feature: clusterB)]
        ClusterRebuilder.rebuild(store: store, threshold: 0.5,
                                 albumNamesByAsset: ["a1": ["妈妈"]])

        let a1 = store.samples.first { $0.assetLocalIdentifier == "a1" }?.personID
        let a2 = store.samples.first { $0.assetLocalIdentifier == "a2" }?.personID
        let b1 = store.samples.first { $0.assetLocalIdentifier == "b1" }?.personID
        XCTAssertEqual(a1, a2, "a2 没有相簿，但和 a1 聚成一簇，应跟着「妈妈」")
        XCTAssertNotEqual(a1, b1, "b1 是另一簇，应另立人物")
    }

    /// 没有相簿、也不和任何相簿照片相似的照片，自己成为一个自动编号人物
    func testUnmatchedPhotoWithoutAlbumGetsAutoName() {
        let store = tempStore()
        store.samples = [FaceSample(assetLocalIdentifier: "a1", boundingBox: .zero, feature: clusterA),
                         FaceSample(assetLocalIdentifier: "b1", boundingBox: .zero, feature: clusterB)]
        ClusterRebuilder.rebuild(store: store, threshold: 0.5,
                                 albumNamesByAsset: ["a1": ["妈妈"]])

        let b1 = store.samples.first { $0.assetLocalIdentifier == "b1" }?.personID
        XCTAssertEqual(store.people.first { $0.id == b1 }?.name, "人物 1")
        let a1 = store.samples.first { $0.assetLocalIdentifier == "a1" }?.personID
        XCTAssertNotEqual(a1, b1)
    }

    // MARK: - 回归：自动名字不能通过投票粘住旧分组

    /// 上一轮把所有脸错误地并成一个「人物 1」后，重聚类必须能重新分开。
    /// 如果「人物 N」也参与归属投票，新的每个簇都会被拉回同一个人，永远修不好。
    func testStaleAutoNameDoesNotSwallowEveryCluster() {
        let store = tempStore()
        let stale = Person(name: "人物 1")
        let clusterC: [Float] = [0, 0, 1, 0]
        store.people = [stale]
        store.samples = [
            FaceSample(assetLocalIdentifier: "a1", boundingBox: .zero, feature: clusterA, personID: stale.id),
            FaceSample(assetLocalIdentifier: "a2", boundingBox: .zero, feature: clusterA, personID: stale.id),
            FaceSample(assetLocalIdentifier: "b1", boundingBox: .zero, feature: clusterB, personID: stale.id),
            FaceSample(assetLocalIdentifier: "b2", boundingBox: .zero, feature: clusterB, personID: stale.id),
            FaceSample(assetLocalIdentifier: "c1", boundingBox: .zero, feature: clusterC, personID: stale.id),
        ]
        ClusterRebuilder.rebuild(store: store, threshold: 0.5)

        let ids = Set(store.samples.compactMap { $0.personID })
        XCTAssertEqual(ids.count, 3, "三个互不相邻的簇必须重新分成 3 个人物")
        XCTAssertFalse(ids.contains(stale.id), "旧的自动分组不应继续吞掉所有簇")
        XCTAssertFalse(store.people.contains { $0.id == stale.id }, "空的自动分组应被清理")
    }

    /// 反过来：用户命名过的人物必须通过投票保留下来（换阈值时不丢名字）
    func testUserNamedPersonKeepsItsSamplesAcrossRebuild() {
        let store = tempStore()
        let named = Person(name: "妈妈")
        store.people = [named]
        store.samples = [
            FaceSample(assetLocalIdentifier: "a1", boundingBox: .zero, feature: clusterA, personID: named.id),
            FaceSample(assetLocalIdentifier: "a2", boundingBox: .zero, feature: clusterA, personID: named.id),
        ]
        ClusterRebuilder.rebuild(store: store, threshold: 0.5)
        XCTAssertEqual(Set(store.samples.compactMap { $0.personID }), [named.id])
        XCTAssertEqual(store.people.map { $0.name }, ["妈妈"])
    }

    // MARK: - 相簿命名是可重新推导的（只认自定义相簿）

    /// 上一轮由相簿命名的人（nameIsAuto），相簿没了要退回自动编号，不能留下错名字
    func testAlbumNamedGroupFallsBackWhenAlbumDisappears() {
        let store = tempStore()
        var person = Person(name: "妈妈")
        person.nameIsAuto = true
        store.people = [person]
        store.samples = [FaceSample(assetLocalIdentifier: "a1", boundingBox: .zero,
                                    feature: clusterA, personID: person.id)]

        ClusterRebuilder.rebuild(store: store, threshold: 0.5, albumNamesByAsset: ["a1": []])

        XCTAssertFalse(store.people.contains { $0.name == "妈妈" }, "相簿没了就不该再有「妈妈」")
        let sample = store.samples.first { $0.assetLocalIdentifier == "a1" }
        XCTAssertNotNil(sample?.personID, "照片应退回 AI 分组")
        XCTAssertEqual(store.people.first { $0.id == sample?.personID }?.name, "人物 1")
    }

    /// 相簿改名/换相簿时，自动写进去的名字要跟着变
    func testAlbumNamedGroupFollowsTheCurrentAlbum() {
        let store = tempStore()
        var person = Person(name: "旧相簿")
        person.nameIsAuto = true
        store.people = [person]
        store.samples = [FaceSample(assetLocalIdentifier: "a1", boundingBox: .zero,
                                    feature: clusterA, personID: person.id)]

        ClusterRebuilder.rebuild(store: store, threshold: 0.5,
                                 albumNamesByAsset: ["a1": ["新相簿"]])

        XCTAssertEqual(store.people.map { $0.name }, ["新相簿"], "应按新相簿名建人物")
        XCTAssertEqual(store.people.first?.nameIsAuto, true)
        XCTAssertEqual(store.samples.first { $0.assetLocalIdentifier == "a1" }?.personID,
                       store.people.first?.id)
    }

    /// 用户亲手起的名字即使相簿消失也不能被改掉
    func testUserRenamedPersonSurvivesAlbumLoss() {
        let store = tempStore()
        var person = Person(name: "我起的名字")
        person.nameIsAuto = false
        store.people = [person]
        store.samples = [FaceSample(assetLocalIdentifier: "a1", boundingBox: .zero,
                                    feature: clusterA, personID: person.id)]

        ClusterRebuilder.rebuild(store: store, threshold: 0.5, albumNamesByAsset: ["a1": []])

        XCTAssertEqual(store.people.first { $0.id == person.id }?.name, "我起的名字")
    }

    /// 旧数据：上一版按系统相簿命名、但没写 nameIsAuto。改成「只认自定义相簿」后必须能清掉。
    func testLegacySystemAlbumNameIsReDerived() {
        let store = tempStore()
        let person = Person(name: "系统相簿人名")   // nameIsAuto 为 nil（旧数据）
        store.people = [person]
        store.samples = [FaceSample(assetLocalIdentifier: "a1", boundingBox: .zero,
                                    feature: clusterA, personID: person.id)]

        ClusterRebuilder.rebuild(store: store, threshold: 0.5,
                                 albumNamesByAsset: ["a1": []],
                                 previousAlbumNames: ["系统相簿人名"])

        XCTAssertFalse(store.people.contains { $0.name == "系统相簿人名" }, "系统相簿留下的名字应被清掉")
        XCTAssertEqual(store.people.map { $0.name }, ["人物 1"])
    }

    /// 反过来：用户手写的名字不在任何相簿里，必须原样保留
    func testLegacyManualNameIsKeptWhenNotAnAlbumName() {
        let store = tempStore()
        let person = Person(name: "我自己写的")
        store.people = [person]
        store.samples = [FaceSample(assetLocalIdentifier: "a1", boundingBox: .zero,
                                    feature: clusterA, personID: person.id)]

        ClusterRebuilder.rebuild(store: store, threshold: 0.5,
                                 albumNamesByAsset: ["a1": []],
                                 previousAlbumNames: ["系统相簿人名"])

        XCTAssertEqual(store.people.first { $0.id == person.id }?.name, "我自己写的")
    }

    /// 增量扫描：后续扫到的新照片要并入**已存在**的相簿命名人物，而不是新建一个「人物 N」。
    /// 这正是「后续扫描可以更新之前同步的人物」的回归防线。
    func testIncrementalScanMergesNewPhotoIntoExistingAlbumNamedPerson() {
        let store = tempStore()
        var person = Person(name: "妈妈")
        person.nameIsAuto = true
        store.people = [person]
        store.samples = [
            FaceSample(assetLocalIdentifier: "a1", boundingBox: .zero,
                       feature: clusterA, personID: person.id),
            // 新一轮扫到的照片：脸和 a1 并不相似（会自成一簇），但同在「妈妈」相簿
            FaceSample(assetLocalIdentifier: "b1", boundingBox: .zero, feature: clusterB),
        ]

        ClusterRebuilder.rebuild(store: store, threshold: 0.5,
                                 albumNamesByAsset: ["a1": ["妈妈"], "b1": ["妈妈"]],
                                 previousAlbumNames: ["妈妈"])

        XCTAssertEqual(store.people.count, 1, "不应新建分组：\(store.people.map { $0.name })")
        XCTAssertEqual(store.people.first?.name, "妈妈")
        XCTAssertEqual(store.samples.first { $0.assetLocalIdentifier == "b1" }?.personID, person.id,
                       "新照片应并入已有的人物")
    }

    /// 同一张照片上的多张脸只能归一个人物，避免同一张照片同时出现在多个人物（相簿）里
    func testFacesOfTheSamePhotoShareOnePerson() {
        let store = tempStore()
        let clusterC: [Float] = [0, 0, 1, 0]
        store.samples = [
            FaceSample(assetLocalIdentifier: "p1", boundingBox: .zero, feature: clusterA),
            FaceSample(assetLocalIdentifier: "p1", boundingBox: .zero, feature: clusterA),
            FaceSample(assetLocalIdentifier: "p1", boundingBox: .zero, feature: clusterB),
            FaceSample(assetLocalIdentifier: "p2", boundingBox: .zero, feature: clusterC),
        ]

        ClusterRebuilder.rebuild(store: store, threshold: 0.5)

        let p1People = Set(store.samples.filter { $0.assetLocalIdentifier == "p1" }
            .compactMap { $0.personID })
        XCTAssertEqual(p1People.count, 1, "同一张照片只能归一个人物（按多数票取）")
        XCTAssertNotEqual(store.samples.first { $0.assetLocalIdentifier == "p2" }?.personID,
                          p1People.first)
    }

    /// 手动指定的脸不参与「同照片归一」，仍留在用户指定的人物里
    func testManualFaceIsNotMovedByPhotoConsolidation() {
        let store = tempStore()
        let manualPerson = Person(name: "张三")
        let manual = FaceSample(assetLocalIdentifier: "p1", boundingBox: .zero, feature: clusterB,
                                personID: manualPerson.id, isIgnored: false, assignmentIsManual: true)
        store.people = [manualPerson]
        store.samples = [
            manual,
            FaceSample(assetLocalIdentifier: "p1", boundingBox: .zero, feature: clusterA),
            FaceSample(assetLocalIdentifier: "p1", boundingBox: .zero, feature: clusterA),
        ]

        ClusterRebuilder.rebuild(store: store, threshold: 0.5)

        XCTAssertEqual(store.samples.first { $0.id == manual.id }?.personID, manualPerson.id,
                       "手动指定的归属不能被同照片归一改动")
    }

    /// 命名过的人物即使被清空，其编号也不应被新人物重新占用（避免名字撞车）
    func testPreservedEmptyPersonKeepsItsNumberReserved() {
        let store = tempStore()
        let named = Person(name: "人物 7")   // 看起来像自动命名，但先被"命名"过
        store.people = [named]
        store.samples = [FaceSample(assetLocalIdentifier: "b1", boundingBox: .zero, feature: clusterB)]

        ClusterRebuilder.rebuild(store: store, threshold: 0.5)

        let names = store.people.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "不应出现重名：\(names)")
    }

    /// 强化「同相簿 / 同名合并」：新照片同时在已有人物相簿和一个更专有的新相簿里时，
    /// 必须并入已有人物，而不是另立一个分组。
    func testExistingPersonWinsWhenMultipleAlbumsMatch() {
        let store = tempStore()
        var existing = Person(name: "妈妈")
        existing.nameIsAuto = true
        store.people = [existing]
        store.samples = [
            FaceSample(assetLocalIdentifier: "a1", boundingBox: .zero,
                       feature: clusterA, personID: existing.id),
            FaceSample(assetLocalIdentifier: "b1", boundingBox: .zero, feature: clusterB),
        ]

        ClusterRebuilder.rebuild(store: store, threshold: 0.5,
                                 albumNamesByAsset: ["a1": ["妈妈"], "b1": ["妈妈", "亲子"]])

        XCTAssertEqual(store.people.count, 1, "不应新建分组：\(store.people.map { $0.name })")
        XCTAssertEqual(store.people.first?.name, "妈妈")
        XCTAssertEqual(store.samples.first { $0.assetLocalIdentifier == "b1" }?.personID, existing.id,
                       "新照片应并入同相簿的已有人物")
    }
}
