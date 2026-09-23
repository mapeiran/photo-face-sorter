import Foundation
import Combine
import SwiftUI

/// 全局数据模型（人物、规则、日志、设置）
@MainActor
final class AppModel: ObservableObject {
    let store = CacheStore()

    @Published var people: [Person] = []
    @Published var rules: [ClassifyRule] = []
    @Published var logs: [ExecutionLog] = []

    /// 自动扫描总开关（默认关闭）
    @AppStorage("autoScanEnabled") var autoScanEnabled: Bool = false
    /// 仅充电时后台扫描
    @AppStorage("chargeOnlyBackground") var chargeOnlyBackground: Bool = true
    /// 聚类阈值（越小分组越细）
    @AppStorage("clusterThreshold") var clusterThreshold: Double = 0.9

    /// 按当前阈值重新聚类
    func recluster() {
        ClusterRebuilder.rebuild(store: store, threshold: Float(clusterThreshold))
        reload()
    }

    init() {
        reload()
    }

    func reload() {
        people = store.people
        rules = store.rules.sorted { $0.order < $1.order }
        logs = store.logs.sorted { $0.date > $1.date }
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
        var samples = store.samples
        for index in samples.indices where samples[index].personID == person.id {
            samples[index].personID = nil
        }
        store.samples = samples
        reload()
    }

    /// 合并两个人物（把 from 的样本人脸并入 to）
    func mergePerson(_ from: Person, into to: Person) {
        var samples = store.samples
        for index in samples.indices where samples[index].personID == from.id {
            samples[index].personID = to.id
        }
        store.samples = samples
        store.people = store.people.filter { $0.id != from.id }
        reload()
    }

    func samples(of person: Person) -> [FaceSample] {
        store.samples.filter { $0.personID == person.id }
    }

    /// 批量更新人脸样本
    func updateSamples(_ updated: [FaceSample]) {
        var samples = store.samples
        for sample in updated {
            if let index = samples.firstIndex(where: { $0.id == sample.id }) {
                samples[index] = sample
            }
        }
        store.samples = samples
        cleanupEmptyPeople()
        reload()
    }

    /// 拆分：把选中的人脸移入一个新建人物
    @discardableResult
    func split(_ samplesToSplit: [FaceSample], name: String) -> Person {
        let person = Person(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        var samples = store.samples
        let ids = Set(samplesToSplit.map { $0.id })
        for index in samples.indices where ids.contains(samples[index].id) {
            samples[index].personID = person.id
        }
        store.samples = samples

        var people = store.people
        people.append(person)
        store.people = people

        cleanupEmptyPeople()
        reload()
        return person
    }

    /// 把选中的人脸移动到指定人物（nil = 移出人物）
    func moveSamples(_ samplesToMove: [FaceSample], to person: Person?) {
        var samples = store.samples
        let ids = Set(samplesToMove.map { $0.id })
        for index in samples.indices where ids.contains(samples[index].id) {
            samples[index].personID = person?.id
            samples[index].isIgnored = false
        }
        store.samples = samples
        cleanupEmptyPeople()
        reload()
    }

    /// 标记为非人物人脸（屏蔽）
    func ignoreSamples(_ samplesToIgnore: [FaceSample]) {
        var samples = store.samples
        let ids = Set(samplesToIgnore.map { $0.id })
        for index in samples.indices where ids.contains(samples[index].id) {
            samples[index].isIgnored = true
            samples[index].personID = nil
        }
        store.samples = samples
        cleanupEmptyPeople()
        reload()
    }

    private func cleanupEmptyPeople() {
        let used = Set(store.samples.compactMap { $0.personID })
        store.people = store.people.filter { used.contains($0.id) }
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
        reload()
    }

    func clearLogs() {
        store.clearLogs()
        reload()
    }
}
