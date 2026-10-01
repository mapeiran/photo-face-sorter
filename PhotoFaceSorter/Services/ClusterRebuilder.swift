import Foundation

/// 聚类重建器：**相簿优先、AI 兜底**，并保留用户的手动修正。
///
/// 归类顺序：
/// 1. `assignmentIsManual == true` / `isIgnored == true` 的样本完全保留原状，谁都不改；
/// 2. 照片在某个**自定义相簿**里 → 直接归到以该相簿命名的人物（相簿优先）；
/// 3. 其余照片按人脸聚类分组（AI 兜底）。已确定身份的样本参与投票，
///    同一簇里没有相簿的照片会跟着相簿 / 用户命名走；
/// 4. 新建自动人物的编号从现有「人物 N」的最大值继续，不会重名；
/// 5. 只清理**自动命名**的空人物，用户命名过的空分组会保留。
enum ClusterRebuilder {

    /// 在后台线程重建聚类（全量聚类是重活，不能放在主线程）
    static func rebuildInBackground(store: CacheStore,
                                    threshold: Float,
                                    albumNamesByAsset: [String: [String]] = [:],
                                    previousAlbumNames: Set<String> = []) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                rebuild(store: store,
                        threshold: threshold,
                        albumNamesByAsset: albumNamesByAsset,
                        previousAlbumNames: previousAlbumNames)
                continuation.resume()
            }
        }
    }

    /// - Parameter albumNamesByAsset: 照片 -> 所属**自定义**相簿名。有值时相簿优先。
    ///   空字典时退化为纯 AI 聚类（单元测试与拿不到相册权限时就是这样）。
    /// - Parameter previousAlbumNames: 现有全部相簿名（含系统相簿），用于识别旧版
    ///   按相簿名自动写入的名字 —— 那些名字可重新推导，不当成用户手写的。
    static func rebuild(store: CacheStore,
                        threshold: Float,
                        albumNamesByAsset: [String: [String]] = [:],
                        previousAlbumNames: Set<String> = []) {
        var samples = store.samples
        let features = samples.map { $0.feature }
        let assignments = FaceClusteringService().cluster(features: features, threshold: threshold)

        var people = store.people

        /// 手动修正过（或被标记为非人物）的样本：归属原样保留
        let locked = Set(samples.indices.filter {
            samples[$0].assignmentIsManual == true || samples[$0].isIgnored
        })

        // 名字 -> 人物：相簿名直接复用同名人物（包括用户自己命名过的那个）
        var personByName: [String: UUID] = [:]
        var personIndexByID: [UUID: Int] = [:]
        for (index, person) in people.enumerated() {
            personIndexByID[person.id] = index
            if personNumber(in: person.name) == nil, personByName[person.name] == nil {
                personByName[person.name] = person.id
            }
        }

        // 参与归属投票的人物：用户命名的 + 本轮按相簿命名的人物。
        // 旧版按系统相簿命名（名字在 previousAlbumNames 里）的不在其中 —— 它们要被重新推导掉。
        var votePersonIDs = Set<UUID>()
        for person in people
        where personNumber(in: person.name) == nil
            && person.nameIsAuto != true
            && !previousAlbumNames.contains(person.name) {
            votePersonIDs.insert(person.id)
        }

        // 1) 相簿优先
        var assignedByAlbum = [Bool](repeating: false, count: samples.count)
        if !albumNamesByAsset.isEmpty {
            let memberCounts = albumMemberCounts(albumNamesByAsset)
            for index in samples.indices where !locked.contains(index) {
                guard let name = PersonNamingPolicy.albumName(
                    assetLocalIdentifier: samples[index].assetLocalIdentifier,
                    albumNamesByAsset: albumNamesByAsset,
                    albumMemberCounts: memberCounts) else { continue }

                let personID: UUID
                if let existing = personByName[name] {
                    personID = existing
                    // 复用到的是自动名字（含旧版相簿名）就补上标记；用户起的名字不动
                    if let personIndex = personIndexByID[existing],
                       !isUserNamed(people[personIndex], previousAlbumNames) {
                        people[personIndex].nameIsAuto = true
                    }
                } else {
                    var person = Person(name: name)
                    person.nameIsAuto = true
                    people.append(person)
                    personIndexByID[person.id] = people.count - 1
                    personByName[name] = person.id
                    personID = person.id
                }
                samples[index].personID = personID
                assignedByAlbum[index] = true
                votePersonIDs.insert(personID)
            }
        }

        // 2) AI 兜底：没有相簿归属的照片按聚类分组。
        //    投票只统计「身份已确定」的样本（相簿人物 + 用户命名人物），
        //    于是同一簇里没有相簿的照片会跟着它们走。
        var votes: [Int: [UUID: Int]] = [:]
        for (index, cluster) in assignments.enumerated() where cluster >= 0 {
            guard !locked.contains(index) else { continue }
            if let personID = samples[index].personID, votePersonIDs.contains(personID) {
                votes[cluster, default: [:]][personID, default: 0] += 1
            }
        }
        var clusterToPerson: [Int: UUID] = [:]
        for (cluster, tally) in votes {
            if let (personID, _) = tally.max(by: { $0.value < $1.value }) {
                clusterToPerson[cluster] = personID
            }
        }

        var nextNumber = (people.compactMap { personNumber(in: $0.name) }.max() ?? 0) + 1
        for (index, cluster) in assignments.enumerated() {
            guard cluster >= 0, !locked.contains(index), !assignedByAlbum[index] else { continue }
            if let personID = clusterToPerson[cluster] {
                samples[index].personID = personID
            } else {
                let person = Person(name: "人物 \(nextNumber)")
                nextNumber += 1
                people.append(person)
                clusterToPerson[cluster] = person.id
                samples[index].personID = person.id
            }
        }

        // 3) 同一张照片只归一个人物。
        //    一张合影上可能有多张脸，AI 可能把它们分到不同人物；按多数票统一成一个人物，
        //    避免同一张照片同时出现在多个人物（相簿）里。手动修正 / 忽略的样本不参与。
        var personVotesByAsset: [String: [UUID: (count: Int, firstSeen: Int)]] = [:]
        for index in samples.indices where !locked.contains(index) && !assignedByAlbum[index] {
            guard let personID = samples[index].personID else { continue }
            let asset = samples[index].assetLocalIdentifier
            var tally = personVotesByAsset[asset] ?? [:]
            let existing = tally[personID]
            tally[personID] = (count: (existing?.count ?? 0) + 1,
                               firstSeen: existing?.firstSeen ?? index)
            personVotesByAsset[asset] = tally
        }
        for index in samples.indices where !locked.contains(index) && !assignedByAlbum[index] {
            guard let personID = samples[index].personID,
                  let winner = winningPerson(in: personVotesByAsset[samples[index].assetLocalIdentifier] ?? [:]),
                  winner != personID else { continue }
            samples[index].personID = winner
        }

        // 4) 清理空人物：只保留用户命名过的，避免每次扫描留下垃圾分组
        let used = Set(samples.compactMap { $0.personID })
        people = people.filter { used.contains($0.id) || isUserNamed($0, previousAlbumNames) }

        store.people = people
        store.samples = samples
    }

    /// 一张照片上票数最多的人物；票数相同时取最早出现的那张脸，保证结果可复现。
    private static func winningPerson(in tally: [UUID: (count: Int, firstSeen: Int)]) -> UUID? {
        tally.max { lhs, rhs in
            lhs.value.count == rhs.value.count
                ? lhs.value.firstSeen > rhs.value.firstSeen
                : lhs.value.count < rhs.value.count
        }?.key
    }

    /// 每个相簿名覆盖多少张（去重后）照片，用于多相簿时选更「专有」的那个
    private static func albumMemberCounts(_ albumNamesByAsset: [String: [String]]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for names in albumNamesByAsset.values {
            for name in Set(names) where !name.isEmpty {
                counts[name, default: 0] += 1
            }
        }
        return counts
    }

    /// 用户自己命名的：既不是「人物 N」，也不是自动写入的相簿名。
    /// 只有这类名字完全不受重聚类影响。
    ///
    /// 旧数据兼容：上一版按相簿名命名时没有写 `nameIsAuto`，
    /// 因此「名字恰好等于某个相簿名」也视为自动命名，允许重新推导 ——
    /// 否则系统相簿（同步/导入）留下的名字永远清不掉。
    private static func isUserNamed(_ person: Person, _ previousAlbumNames: Set<String>) -> Bool {
        guard personNumber(in: person.name) == nil else { return false }
        if person.nameIsAuto == true { return false }
        return !previousAlbumNames.contains(person.name)
    }

    /// 解析「人物 N」中的编号，用于避免重名
    private static func personNumber(in name: String) -> Int? {
        let prefix = "人物 "
        guard name.hasPrefix(prefix) else { return nil }
        return Int(name.dropFirst(prefix.count))
    }
}
