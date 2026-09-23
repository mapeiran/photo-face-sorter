import Foundation

/// 聚类重建器：按阈值重新聚类所有样本，并尽量保留已命名人物
enum ClusterRebuilder {

    static func rebuild(store: CacheStore, threshold: Float) {
        var samples = store.samples
        let features = samples.map { $0.feature }
        let assignments = FaceClusteringService().cluster(features: features, threshold: threshold)

        var people = store.people
        var clusterToPerson: [Int: UUID] = [:]

        // 已有人物归属投票，尽量保留命名
        var votes: [Int: [UUID: Int]] = [:]
        for (index, cluster) in assignments.enumerated() where cluster >= 0 {
            if let personID = samples[index].personID {
                votes[cluster, default: [:]][personID, default: 0] += 1
            }
        }
        for (cluster, tally) in votes {
            if let (personID, _) = tally.max(by: { $0.value < $1.value }) {
                clusterToPerson[cluster] = personID
            }
        }

        for (index, cluster) in assignments.enumerated() {
            guard cluster >= 0 else { continue }
            if let personID = clusterToPerson[cluster] {
                samples[index].personID = personID
            } else {
                let person = Person(name: "人物 \(people.count + 1)")
                people.append(person)
                clusterToPerson[cluster] = person.id
                samples[index].personID = person.id
            }
        }

        // 清理空人物
        let used = Set(samples.compactMap { $0.personID })
        people = people.filter { used.contains($0.id) }

        store.people = people
        store.samples = samples
    }
}
