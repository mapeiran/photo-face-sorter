import Foundation
import Combine
import SwiftUI

/// 全局数据模型（人物、人脸样本、规则、日志、设置）
@MainActor
final class AppModel: ObservableObject {
    let store = CacheStore()

    @Published var people: [Person] = []
    @Published var rules: [ClassifyRule] = []
    @Published var logs: [ExecutionLog] = []
    /// 人脸样本（内存驻留，异步加载，避免启动阻塞）
    @Published var samples: [FaceSample] = []

    /// 自动扫描总开关（默认关闭）
    @AppStorage("autoScanEnabled") var autoScanEnabled: Bool = false
    /// 仅充电时后台扫描
    @AppStorage("chargeOnlyBackground") var chargeOnlyBackground: Bool = true
    /// 聚类阈值（越小分组越细）
    @AppStorage("clusterThreshold") var clusterThreshold: Double = 0.9

    init() {
        reload()
        loadSamplesAsync()
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

    /// 按当前阈值重新聚类
    func recluster() {
        ClusterRebuilder.rebuild(store: store, threshold: Float(clusterThreshold))
        reload()
        loadSamplesAsync()
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
        }
        store.people = store.people.filter { $0.id != from.id }
        persistSamples(list)
    }

    func samples(of person: Person) -> [FaceSample] {
        samples.filter { $0.personID == person.id }
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
        }
        persistSamples(list)
    }

    private func persistSamples(_ updated: [FaceSample]) {
        samples = updated
        store.samples = updated
        let used = Set(updated.compactMap { $0.personID })
        let filtered = store.people.filter { used.contains($0.id) }
        store.people = filtered
        people = filtered
    }

    // MARK: - 规则

    func upsertRule(_ rule: ClassifyRule) {
        var list = store.rules
        if let index = list.firstIndex(where: { $0.id == rule.id }) {
            list[index] = rule
        } else {
            list.append(rule)
        }
        store.rules = list
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
