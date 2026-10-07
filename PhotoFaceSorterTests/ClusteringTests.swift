import XCTest
@testable import PhotoFaceSorter

final class ClusteringTests: XCTestCase {

    private let service = FaceClusteringService()

    // MARK: - 基础行为

    func testIdenticalFeaturesShareOneCluster() {
        let feature: [Float] = [1, 0, 0]
        let assignments = service.cluster(features: [feature, feature, feature], threshold: 0.5)
        XCTAssertEqual(Set(assignments).count, 1)
    }

    func testDistantFeaturesGetSeparateClusters() {
        let assignments = service.cluster(features: [[1, 0, 0], [0, 1, 0]], threshold: 0.5)
        XCTAssertEqual(assignments.count, 2)
        XCTAssertNotEqual(assignments[0], assignments[1])
    }

    func testEmptyFeatureIsLeftUnassigned() {
        let assignments = service.cluster(features: [[], [1, 0, 0]], threshold: 0.5)
        XCTAssertEqual(assignments[0], -1, "空特征无法参与聚类")
        XCTAssertGreaterThanOrEqual(assignments[1], 0)
    }

    func testAssignmentCountMatchesInputCount() {
        let features: [[Float]] = [[1, 0], [0, 1], [1, 1], []]
        XCTAssertEqual(service.cluster(features: features, threshold: 0.5).count, features.count)
    }

    func testAllEmptyFeaturesProduceNoClusters() {
        XCTAssertEqual(service.cluster(features: [[], []], threshold: 0.5), [-1, -1])
    }

    /// 簇编号必须是连续的 0..m-1（重分配后可能出现空簇，必须被压掉）
    func testClusterIdentifiersAreContiguous() {
        let assignments = service.cluster(features: [[1, 0], [0, 1], [0, 0], [1, 1], []], threshold: 0.5)
        let used = Set(assignments).subtracting([-1]).sorted()
        XCTAssertEqual(used, Array(0..<used.count), "簇编号应连续，实际 \(used)")
    }

    // MARK: - 质心修正（回归测试）

    /// 旧实现用 (质心 + 新样本) / 2，会让每个新样本占一半权重。
    /// 这里直接验证增量均值等于算术平均。
    func testIncrementalMeanEqualsArithmeticMean() {
        // 样本 (0,0) (2,2) (4,4) (6,6)，算术平均应为 (3,3)
        var mean: [Float] = [0, 0]
        var count = 1
        for value: [Float] in [[2, 2], [4, 4], [6, 6]] {
            count += 1
            mean = FaceClusteringService.incrementalMean(mean, count: count, adding: value)
        }
        XCTAssertEqual(mean[0], 3, accuracy: 1e-5, "旧公式 (a+b)/2 会得到 4.25")
        XCTAssertEqual(mean[1], 3, accuracy: 1e-5)
    }

    func testIncrementalMeanWithSingleSampleIsThatSample() {
        let mean = FaceClusteringService.incrementalMean([0, 0], count: 1, adding: [5, -3])
        XCTAssertEqual(mean, [5, -3])
    }

    func testIncrementalMeanIgnoresMismatchedDimensions() {
        let mean = FaceClusteringService.incrementalMean([1, 2], count: 3, adding: [1, 2, 3])
        XCTAssertEqual(mean, [1, 2])
    }

    /// 长链上的质心不应偏向最后加入的样本。
    /// 10 个等距样本，质心应落在中间附近而不是尾端。
    func testCentroidDoesNotDriftTowardRecentSamples() {
        var mean: [Float] = [0]
        var count = 1
        for i in 1..<10 {
            count += 1
            mean = FaceClusteringService.incrementalMean(mean, count: count, adding: [Float(i)])
        }
        // 0...9 的均值是 4.5；旧公式会得到接近 8.x
        XCTAssertEqual(mean[0], 4.5, accuracy: 1e-4)
    }

    // MARK: - 顺序稳定性

    /// 两组明显分离的特征，打乱输入顺序后应当得到相同的「分区」
    func testPartitionIsInvariantToInputOrderForSeparatedGroups() {
        let a: [Float] = [1, 0]
        let b: [Float] = [0, 1]
        let forward: [[Float]] = [a, a, b, b, a, b]
        let backward: [[Float]] = Array(forward.reversed())

        let first = service.cluster(features: forward, threshold: 0.5)
        let second = Array(service.cluster(features: backward, threshold: 0.5).reversed())

        XCTAssertTrue(samePartition(first, second),
                      "分区应一致：\(first) vs \(second)")
    }

    private func samePartition(_ x: [Int], _ y: [Int]) -> Bool {
        guard x.count == y.count else { return false }
        for i in x.indices {
            for j in x.indices where (x[i] == x[j]) != (y[i] == y[j]) {
                return false
            }
        }
        return true
    }

    // MARK: - 距离

    func testDistanceIsZeroForIdenticalVectors() {
        XCTAssertEqual(service.distance([1, 2, 3], [1, 2, 3]), 0, accuracy: 1e-6)
    }

    func testDistanceIsSymmetric() {
        let a: [Float] = [1, 2, 3]
        let b: [Float] = [4, 5, 6]
        XCTAssertEqual(service.distance(a, b), service.distance(b, a), accuracy: 1e-6)
    }

    func testDistanceOfMismatchedLengthsIsInfinite() {
        XCTAssertEqual(service.distance([1], [1, 2]), .greatestFiniteMagnitude)
    }

    func testSquaredDistanceMatchesSquaredDistanceValue() {
        let a: [Float] = [0, 0]
        let b: [Float] = [3, 4]
        XCTAssertEqual(service.squaredDistance(a, b), 25, accuracy: 1e-6)
        XCTAssertEqual(service.distance(a, b), 5, accuracy: 1e-6)
    }

    func testSquaredDistanceOfMismatchedLengthsIsInfinite() {
        XCTAssertEqual(service.squaredDistance([1], [1, 2]), .greatestFiniteMagnitude)
    }

    // MARK: - 特征归一化

    func testNormalizedVectorHasUnitLength() {
        let normalized = FaceEmbeddingService.normalized([3, 4])
        XCTAssertEqual(normalized[0], 0.6, accuracy: 1e-6)
        XCTAssertEqual(normalized[1], 0.8, accuracy: 1e-6)
    }

    func testNormalizedZeroVectorIsReturnedUnchanged() {
        XCTAssertEqual(FaceEmbeddingService.normalized([0, 0]), [0, 0])
    }

    /// 归一化后：平方欧氏距离 = 2 × 余弦距离，聚类阈值换算就依赖这个恒等式
    func testSquaredDistanceEqualsTwiceCosineDistance() {
        let a = FaceEmbeddingService.normalized([1, 2, 3])
        let b = FaceEmbeddingService.normalized([3, 1, 2])
        let cosine = zip(a, b).reduce(Float(0)) { $0 + $1.0 * $1.1 }
        XCTAssertEqual(service.squaredDistance(a, b), 2 * (1 - cosine), accuracy: 1e-5)
    }
}
