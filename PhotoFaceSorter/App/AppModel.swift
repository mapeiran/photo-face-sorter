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
