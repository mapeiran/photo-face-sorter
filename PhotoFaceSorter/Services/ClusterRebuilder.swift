import Foundation

/// 聚类重建器：按阈值重新聚类所有样本，并保留用户的手动修正与已命名人物。
///
/// 关键保证：
/// - `assignmentIsManual == true` 或 `isIgnored == true` 的样本**完全保留原状**，
///   既不参与投票也不被重新赋值 —— 用户的手动合并/拆分/移出不会被重聚类撤销；
/// - 投票只统计自动归属的样本，且只为**用户命名过**的人物保留归属
///   （「人物 N」这种自动名字不参与投票，否则上一轮的错误分组会永远粘住）；
/// - 新建人物的编号从现有「人物 N」的最大值继续，不会重名；
/// - 有相簿信息时，自动分组会按出现最多的相簿名命名，同名分组自动合并；
/// - 只清理**自动命名**的空人物，用户命名过的空分组会保留。
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

    /// - Parameter albumNamesByAsset: 照片 -> 所属**自定义**相簿名，用于给自动分组按相簿命名。
    ///   传空字典时退化为纯「人物 N」命名（单元测试与拿不到相册权限时就是这样）。
    /// - Parameter previousAlbumNames: 现有全部相簿名（含系统相簿）。名字与相簿同名的人
    ///   视为「上一版自动命名的」，允许被重新推导（旧版本没有 `nameIsAuto` 标记）。
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

        var clusterToPerson: [Int: UUID] = [:]

        // 已有人物归属投票（只看自动归属的样本），尽量保留**用户命名过**的人物。
        //
        // 关键：不保留「人物 N」这类自动名字。否则上一轮错误的分组（例如把所有脸
        // 并成一个「人物 1」）会通过投票把新一轮的每一个簇都拉回同一个人，
        // 重聚类永远分不开 —— 这正是「人物页只有一个分组」修不掉的原因。
        var votes: [Int: [UUID: Int]] = [:]
        let namedPersonIDs = Set(people.filter { personNumber(in: $0.name) == nil }.map(\.id))
        for (index, cluster) in assignments.enumerated() where cluster >= 0 {
            guard !locked.contains(index) else { continue }
            if let personID = samples[index].personID, namedPersonIDs.contains(personID) {
                votes[cluster, default: [:]][personID, default: 0] += 1
            }
        }
        for (cluster, tally) in votes {
            if let (personID, _) = tally.max(by: { $0.value < $1.value }) {
                clusterToPerson[cluster] = personID
            }
        }

        var nextNumber = (people.compactMap { personNumber(in: $0.name) }.max() ?? 0) + 1

        for (index, cluster) in assignments.enumerated() {
            guard cluster >= 0, !locked.contains(index) else { continue }
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

        // 按已有相簿名给自动分组命名（同名的分组会合并），再清理空人物
        applyAlbumNames(&people,
                        samples: &samples,
                        albumNamesByAsset: albumNamesByAsset,
                        previousAlbumNames: previousAlbumNames,
                        nextNumber: &nextNumber)

        // 清理空人物：只清理**自动**名字（「人物 N」或自动写入的相簿名）。
        // 用户命名过的分组即使暂时没有样本人脸也保留 —— 否则「把最后一张脸移出某人」
        // 会连用户起的名字一起丢掉，而下次重聚类只会另外生成一个「人物 N」。
        let used = Set(samples.compactMap { $0.personID })
        people = people.filter { used.contains($0.id) || isUserNamed($0, previousAlbumNames) }

        store.people = people
        store.samples = samples
    }

    /// 按相簿名给**自动命名**的分组改名；同名分组合并成一个。
    ///
    /// - 用户自己起过的名字（`isUserNamed`）绝不改动；
    /// - 上一轮由相簿写入的名字（`nameIsAuto == true`）会按当前相簿重新推导：
    ///   相簿被删掉、或从自定义相簿变成系统相簿时，退回「人物 N」，不会留下错名字；
    /// - 同一个相簿名下只应有一个分组，否则人物页会出现两个「妈妈」，
    ///   所以自动分组算出同名时直接并入已有的那个。
    private static func applyAlbumNames(_ people: inout [Person],
                                        samples: inout [FaceSample],
                                        albumNamesByAsset: [String: [String]],
                                        previousAlbumNames: Set<String>,
                                        nextNumber: inout Int) {
        // 即使没有任何自定义相簿，也要跑一遍：旧数据里按系统相簿命名的名字要退回去
        guard !albumNamesByAsset.isEmpty || !previousAlbumNames.isEmpty else { return }

        var assetsByPerson: [UUID: [String]] = [:]
        for sample in samples {
            guard let personID = sample.personID else { continue }
            assetsByPerson[personID, default: []].append(sample.assetLocalIdentifier)
        }

        // 已被占用的名字：用户命名的 + 上一轮相簿命名的，都用于查重合并
        var personByName: [String: UUID] = [:]
        for person in people
        where personNumber(in: person.name) == nil && personByName[person.name] == nil {
            personByName[person.name] = person.id
        }

        var mergedInto: [UUID: UUID] = [:]
        for index in people.indices {
            let person = people[index]
            guard !isUserNamed(person, previousAlbumNames) else { continue }

            let name = PersonNamingPolicy.dominantAlbumName(
                assetLocalIdentifiers: assetsByPerson[person.id] ?? [],
                albumNamesByAsset: albumNamesByAsset)

            if let name {
                if let target = personByName[name], target != person.id {
                    mergedInto[person.id] = target
                } else {
                    people[index].name = name
                    people[index].nameIsAuto = true
                    personByName[name] = person.id
                }
            } else if people[index].nameIsAuto == true || previousAlbumNames.contains(people[index].name) {
                // 相簿没了 / 不再是自定义相簿：退回自动编号，并释放旧名字，
                // 否则它会继续占位，让别的分组没法用这个相簿名。
                // 第二种情况是旧数据：当时按相簿名命名但没写 nameIsAuto。
                if personByName[people[index].name] == person.id {
                    personByName.removeValue(forKey: people[index].name)
                }
                people[index].name = "人物 \(nextNumber)"
                people[index].nameIsAuto = nil
                nextNumber += 1
            }
        }

        guard !mergedInto.isEmpty else { return }
        for index in samples.indices {
            if let personID = samples[index].personID, let target = mergedInto[personID] {
                samples[index].personID = target
            }
        }
        people.removeAll { mergedInto[$0.id] != nil }
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
