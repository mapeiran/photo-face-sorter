import Foundation
import Combine
import SwiftUI

/// 全局数据模型（人物、人脸样本、规则、日志、设置）
@MainActor
final class AppModel: ObservableObject {
    /// 存储层是线程安全的，标记 nonisolated 以便后台线程读取样本
    nonisolated let store = CacheStore()

    @Published var people: [Person] = []
    @Published var rules: [ClassifyRule] = []
    @Published var logs: [ExecutionLog] = []
    /// 人脸样本（内存驻留，异步加载，避免启动阻塞）
    @Published var samples: [FaceSample] = [] {
        didSet { rebuildSamplesIndex() }
    }

    /// personID -> 该人物的样本人脸。
    /// 列表若每次都全量过滤 `samples`，复杂度是 O(人物数 × 样本数)，
    /// 几千个样本时每次渲染都会明显卡顿，因此预先建好索引。
    private(set) var samplesByPerson: [UUID: [FaceSample]] = [:]

    /// 是否正在进行后台重聚类（用于禁用按钮，避免重复触发）
    @Published private(set) var isReclustering = false

    /// 自动扫描总开关（默认关闭）
    @AppStorage("autoScanEnabled") var autoScanEnabled: Bool = false
    /// 仅充电时后台扫描
    @AppStorage("chargeOnlyBackground") var chargeOnlyBackground: Bool = true
    /// 聚类阈值（越小分组越细）。标定见 `ClusterThreshold`：
    /// 默认值必须和特征提取方式配套，换特征模型时要重新实测。
    @AppStorage("clusterThreshold") var clusterThreshold: Double = ClusterThreshold.defaultValue
    /// 单次扫描的照片数量上限（0 = 不限制）。
    /// 大相册一次性扫完会长时间占用设备、界面像卡死，分批扫可随时停。
    @AppStorage(ScanBatchPolicy.defaultsKey) var maxPhotosPerScan: Int = ScanBatchPolicy.unlimited

    /// 聚类规则版本。v1 = 旧的 0.5…1.5（默认 0.9），v2 = 新的 0.10…0.35（默认 0.25），
    /// v3 = 只用自定义相簿命名。版本变旧会在启动时自动重聚一次。
    private static let thresholdVersionKey = "clusterThresholdVersion"
    private static let thresholdVersion = 3

    init() {
        reload()
        loadSamplesAsync()
        // 旧标定会把所有人并成一个分组，迁移时重置阈值并用新阈值重聚一次，
        // 否则用户升级后看到的还是旧的「人物 1」。
        if migrateThresholdIfNeeded() {
            recluster()
        }
    }

    /// - Returns: 是否需要重聚一次。
    ///
    /// 注意：**不能**只在数值变化时才重聚。旧版本用的是代码里的 0.9，
    /// 但存储里可能根本没有这个键（用户从没调过），迁移时读到的是新默认值 0.25，
    /// 「值没变」≠「结果是对的」。所以只要标定版本旧，就一定重聚一次。
    private func migrateThresholdIfNeeded() -> Bool {
        guard UserDefaults.standard.integer(forKey: Self.thresholdVersionKey) < Self.thresholdVersion else {
            return false
        }
        UserDefaults.standard.set(Self.thresholdVersion, forKey: Self.thresholdVersionKey)
        clusterThreshold = ClusterThreshold.calibrated(clusterThreshold)
        return true
    }

    /// 相簿信息（按相簿名给人物命名用）。PhotoKit 查询可能较慢，放到后台线程。
    /// - byAsset: 照片 -> 所属**自定义**相簿名（命名依据）
    /// - allTitles: 全部相簿名（含系统相簿），用于识别上一版自动命名的名字
    private nonisolated static func albumNameIndex(store: CacheStore)
        async -> (byAsset: [String: [String]], allTitles: Set<String>) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let library = PhotoLibraryService.shared
                let assetIDs = Set(store.samples.map { $0.assetLocalIdentifier })
                let excluded = Set(UserDefaults.standard.stringArray(forKey: "excludedAlbumIDs") ?? [])
                continuation.resume(returning: (
                    byAsset: library.albumNames(byAssetLocalIdentifier: assetIDs,
                                                excludingAlbumIDs: excluded),
                    allTitles: library.userAlbumTitles()))
            }
        }
    }

    // MARK: - 加载

    func reload() {
        people = store.people
        rules = store.rules.sorted { $0.order < $1.order }
        logs = store.logs.sorted { $0.date > $1.date }
    }

    /// 异步加载人脸样本（体积较大，避免主线程阻塞）
    func loadSamplesAsync() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let loaded = self.store.samples
            DispatchQueue.main.async { self.samples = loaded }
        }
    }

    /// 按当前阈值重新聚类（全量聚类较重，放到后台线程）
    func recluster() {
        guard !isReclustering else { return }
        isReclustering = true
        let threshold = Float(ClusterThreshold.calibrated(clusterThreshold))
        Task {
            let albums = await Self.albumNameIndex(store: store)
            await ClusterRebuilder.rebuildInBackground(store: store,
                                                       threshold: threshold,
                                                       albumNamesByAsset: albums.byAsset,
                                                       previousAlbumNames: albums.allTitles)
            reload()
            loadSamplesAsync()
            isReclustering = false
        }
    }

    // MARK: - 人物

    func upsertPerson(_ person: Person) {
        var list = store.people
        if let index = list.firstIndex(where: { $0.id == person.id }) {
            list[index] = person
        } else {
            list.append(person)
        }
        store.people = list
        reload()
    }

    func renamePerson(_ person: Person, to name: String) {
        var p = person
        p.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // 用户亲手起的名字：重聚类时不能再被相簿名覆盖
        p.nameIsAuto = false
        upsertPerson(p)
    }

    func deletePerson(_ person: Person) {
        store.people = store.people.filter { $0.id != person.id }
        var list = samples
        for index in list.indices where list[index].personID == person.id {
            list[index].personID = nil
        }
        persistSamples(list)
    }

    /// 合并两个人物（把 from 的样本人脸并入 to）
    func mergePerson(_ from: Person, into to: Person) {
        var list = samples
        for index in list.indices where list[index].personID == from.id {
            list[index].personID = to.id
            list[index].assignmentIsManual = true
        }
        store.people = store.people.filter { $0.id != from.id }
        persistSamples(list)
    }

    func samples(of person: Person) -> [FaceSample] {
        samplesByPerson[person.id] ?? []
    }

    private func rebuildSamplesIndex() {
        var index: [UUID: [FaceSample]] = [:]
        index.reserveCapacity(people.count)
        for sample in samples {
            guard let personID = sample.personID else { continue }
            index[personID, default: []].append(sample)
        }
        samplesByPerson = index
    }

    /// 已缓存的人脸特征是否与当前特征提取方式一致。
    /// 不一致时聚类结果没有意义，需要引导用户全量重扫。
    var embeddingStatus: EmbeddingConsistency.Status {
        EmbeddingConsistency.status(storedSignature: store.embeddingSignature,
                                    currentSignature: FaceEmbeddingService.signature,
                                    sampleCount: samples.count)
    }

    /// 批量更新人脸样本
    func updateSamples(_ updated: [FaceSample]) {
        var list = samples
        for sample in updated {
            if let index = list.firstIndex(where: { $0.id == sample.id }) {
                list[index] = sample
            }
        }
        persistSamples(list)
    }

    /// 拆分：把选中的人脸移入一个新建人物
    @discardableResult
    func split(_ samplesToSplit: [FaceSample], name: String) -> Person {
        let person = Person(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        var list = samples
        let ids = Set(samplesToSplit.map { $0.id })
        for index in list.indices where ids.contains(list[index].id) {
            list[index].personID = person.id
            list[index].assignmentIsManual = true
        }
        var people = store.people
        people.append(person)
        store.people = people
        persistSamples(list)
        return person
    }

    /// 把选中的人脸移动到指定人物（nil = 移出人物）
    func moveSamples(_ samplesToMove: [FaceSample], to person: Person?) {
        var list = samples
        let ids = Set(samplesToMove.map { $0.id })
        for index in list.indices where ids.contains(list[index].id) {
            list[index].personID = person?.id
            list[index].isIgnored = false
            list[index].assignmentIsManual = true
        }
        persistSamples(list)
    }

    /// 标记为非人物人脸（屏蔽）
    func ignoreSamples(_ samplesToIgnore: [FaceSample]) {
        var list = samples
        let ids = Set(samplesToIgnore.map { $0.id })
        for index in list.indices where ids.contains(list[index].id) {
            list[index].isIgnored = true
            list[index].personID = nil
            list[index].assignmentIsManual = true
        }
        persistSamples(list)
    }

    /// 负责持久化样本人脸，并把 `@Published` 的 `people` 与存储层同步。
    ///
    /// 刻意**不**在这里清理「没有样本人脸的人物」：那是一个隐形副作用，
    /// 会让「把最后一张脸移出某人」这类操作顺带删掉用户命名过的分组。
    /// 空人物的清理统一交给 `ClusterRebuilder`，且只清理自动命名的那些。
    ///
    /// 注意：这里的 `people = store.people` 不能省 —— `deletePerson` /
    /// `mergePerson` / `split` 都是先写 `store.people` 再调用本方法，
    /// 靠这一行刷新界面状态。
    private func persistSamples(_ updated: [FaceSample]) {
        samples = updated
        store.samples = updated
        people = store.people
    }

    // MARK: - 规则

    func upsertRule(_ rule: ClassifyRule) {
        var list = store.rules.sorted { $0.order < $1.order }
        if let index = list.firstIndex(where: { $0.id == rule.id }) {
            list[index] = rule
        } else {
            // 新规则排在最后
            var newRule = rule
            newRule.order = (list.map(\.order).max() ?? -1) + 1
            list.append(newRule)
        }
        store.rules = list
        reload()
    }

    /// 拖动排序（对应 List.onMove），并重新编号 order
    func moveRules(from source: IndexSet, to destination: Int) {
        store.rules = RuleOrdering.reordered(rules, from: source, to: destination)
        reload()
    }

    func deleteRule(_ rule: ClassifyRule) {
        store.rules = store.rules.filter { $0.id != rule.id }
        reload()
    }

    // MARK: - 日志

    func appendLog(_ log: ExecutionLog) {
        var list = store.logs
        list.append(log)
        store.logs = list
        reload()
    }

    func markLogRolledBack(_ log: ExecutionLog) {
        var list = store.logs
        if let index = list.firstIndex(where: { $0.id == log.id }) {
            list[index].rolledBack = true
        }
        store.logs = list
        reload()
    }

    // MARK: - 缓存

    func clearFaceCache() {
        store.clearFaceCache()
        samples = []
        reload()
    }

    func clearLogs() {
        store.clearLogs()
        reload()
    }
}
