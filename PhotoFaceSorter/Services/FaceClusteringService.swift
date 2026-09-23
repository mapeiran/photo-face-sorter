import Foundation

/// 人脸聚类（贪心 + 质心距离）
final class FaceClusteringService {

    /// 输入特征向量数组，返回每个样本所属簇编号
    func cluster(features: [[Float]], threshold: Float) -> [Int] {
        var assignments = [Int](repeating: -1, count: features.count)
        var centroids: [[Float]] = []

        for (index, feature) in features.enumerated() {
            guard !feature.isEmpty else {
                assignments[index] = -1
                continue
            }
            var bestIndex = -1
            var bestDistance = Float.greatestFiniteMagnitude
            for (clusterIndex, centroid) in centroids.enumerated() {
                let distance = self.distance(feature, centroid)
                if distance < bestDistance {
                    bestDistance = distance
                    bestIndex = clusterIndex
                }
            }
            if bestIndex >= 0, bestDistance <= threshold {
                assignments[index] = bestIndex
                centroids[bestIndex] = average(centroids[bestIndex], feature)
            } else {
                centroids.append(feature)
                assignments[index] = centroids.count - 1
            }
        }
        return assignments
    }

    func distance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return .greatestFiniteMagnitude }
        var sum: Float = 0
        for i in 0..<a.count {
            let d = a[i] - b[i]
            sum += d * d
        }
        return sqrt(sum)
    }

    private func average(_ a: [Float], _ b: [Float]) -> [Float] {
        guard a.count == b.count else { return a }
        return zip(a, b).map { ($0 + $1) / 2 }
    }
}
