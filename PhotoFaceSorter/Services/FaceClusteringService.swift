import Foundation

/// 人脸聚类（在线贪心建簇 + 真实均值质心 + 一次整体重分配细化）
///
/// 两处关键修正：
/// 1. 质心必须按样本数加权。旧实现用 `(质心 + 新样本) / 2`，等于每个新样本
///    都占一半权重，质心会严重偏向最后扫描到的照片（簇越大偏得越离谱）。
/// 2. 建簇之后按最终质心整体重分配一次。这一步与样本顺序无关，
///    可以修正「先扫到的照片主导簇形状」造成的误分组。
///
/// 局限：第一遍建簇本质上仍是顺序相关的在线算法。真正与顺序完全无关的
/// 方案（连通分量 / 层次聚类）代价是 O(n²)，计划在更换人脸特征模型时一起评估。
final class FaceClusteringService {

    /// 输入特征向量数组，返回每个样本所属簇编号（-1 = 无法参与聚类，例如空特征）
    func cluster(features: [[Float]], threshold: Float) -> [Int] {
        var assignments = [Int](repeating: -1, count: features.count)
        var centroids: [[Float]] = []
        var counts: [Int] = []
        let limit = threshold * threshold

        // 第一遍：在线贪心建簇
        for (index, feature) in features.enumerated() {
            guard !feature.isEmpty else { continue }
            if let cluster = nearestCluster(to: feature, in: centroids, limit: limit) {
                counts[cluster] += 1
                centroids[cluster] = Self.incrementalMean(centroids[cluster],
                                                          count: counts[cluster],
                                                          adding: feature)
                assignments[index] = cluster
            } else {
                centroids.append(feature)
                counts.append(1)
                assignments[index] = centroids.count - 1
            }
        }

        guard !centroids.isEmpty else { return assignments }

        // 第二遍：用成员的真实均值重算质心，再整体重分配一次
        let refined = recomputeCentroids(features: features,
                                         assignments: assignments,
                                         clusterCount: centroids.count)
        for index in features.indices where assignments[index] >= 0 {
            if let cluster = nearestCluster(to: features[index], in: refined, limit: limit) {
                assignments[index] = cluster
            }
        }

        return compact(assignments, clusterCount: refined.count)
    }

    func distance(_ a: [Float], _ b: [Float]) -> Float {
        // 维度不一致时保持返回「无穷远」的既有契约（不能是 sqrt(.greatestFiniteMagnitude)）
        guard a.count == b.count else { return .greatestFiniteMagnitude }
        return sqrt(squaredDistance(a, b))
    }

    /// 平方距离。最近邻比较不需要开方，可省掉热点循环里的 sqrt。
    func squaredDistance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return .greatestFiniteMagnitude }
        var sum: Float = 0
        for i in 0..<a.count {
            let d = a[i] - b[i]
            sum += d * d
        }
        return sum
    }

    /// 增量均值：把 `value` 并入已有 `count - 1` 个样本的均值。
    /// `count` 是并入之后的样本总数。
    static func incrementalMean(_ mean: [Float], count: Int, adding value: [Float]) -> [Float] {
        guard count > 0, mean.count == value.count else { return mean }
        let total = Float(count)
        let previous = Float(count - 1)
        var result = [Float](repeating: 0, count: mean.count)
        for i in 0..<mean.count {
            result[i] = (mean[i] * previous + value[i]) / total
        }
        return result
    }

    // MARK: - 私有

    /// 返回距离不超过 `limit`（平方距离）、且最近的簇编号
    private func nearestCluster(to feature: [Float], in centroids: [[Float]], limit: Float) -> Int? {
        var best: Int?
        var bestDistance = Float.greatestFiniteMagnitude
        for (index, centroid) in centroids.enumerated() {
            let d = squaredDistance(feature, centroid)
            if d < bestDistance {
                bestDistance = d
                best = index
            }
        }
        guard let best, bestDistance <= limit else { return nil }
        return best
    }

    /// 按当前归属重算每个簇的真实均值质心
    private func recomputeCentroids(features: [[Float]],
                                    assignments: [Int],
                                    clusterCount: Int) -> [[Float]] {
        var sums = [[Float]](repeating: [], count: clusterCount)
        var counts = [Int](repeating: 0, count: clusterCount)

        for index in features.indices {
            let cluster = assignments[index]
            guard cluster >= 0, !features[index].isEmpty else { continue }
            if sums[cluster].isEmpty {
                sums[cluster] = [Float](repeating: 0, count: features[index].count)
            }
            // 维度不一致的特征不参与求均值（正常情况下来自同一模型，维度总是相同）
            guard sums[cluster].count == features[index].count else { continue }
            for i in 0..<features[index].count { sums[cluster][i] += features[index][i] }
            counts[cluster] += 1
        }

        return sums.indices.map { cluster in
            guard counts[cluster] > 0 else { return [] }
            let n = Float(counts[cluster])
            return sums[cluster].map { $0 / n }
        }
    }

    /// 把簇编号压缩成连续的 0..m-1 并丢弃空簇；-1 保持不变
    private func compact(_ assignments: [Int], clusterCount: Int) -> [Int] {
        var remap = [Int](repeating: -1, count: clusterCount)
        var next = 0
        for cluster in assignments where cluster >= 0 && remap[cluster] == -1 {
            remap[cluster] = next
            next += 1
        }
        return assignments.map { $0 >= 0 ? remap[$0] : -1 }
    }
}
