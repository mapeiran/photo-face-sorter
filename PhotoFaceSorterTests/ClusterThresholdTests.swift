import XCTest
@testable import PhotoFaceSorter

/// 阈值标定：v7 起是**余弦距离**语义，越界的历史值必须被拉回新标定。
final class ClusterThresholdTests: XCTestCase {

    func testOutOfRangeValuesFallBackToDefault() {
        XCTAssertEqual(ClusterThreshold.calibrated(1.5), ClusterThreshold.defaultValue)
        XCTAssertEqual(ClusterThreshold.calibrated(0), ClusterThreshold.defaultValue)
        XCTAssertEqual(ClusterThreshold.calibrated(-1), ClusterThreshold.defaultValue)
    }

    func testValuesInsideRangeAreKept() {
        for value in [0.3, 0.4, 0.6, 0.7, 0.9] {
            XCTAssertEqual(ClusterThreshold.calibrated(value), value)
        }
    }

    func testDefaultIsInsideRange() {
        XCTAssertTrue(ClusterThreshold.range.contains(ClusterThreshold.defaultValue))
    }

    /// 默认操作点：余弦距离 0.60 ⇔ 余弦相似度 0.40（实测推荐值）
    func testDefaultMatchesRecommendedCosineSimilarity() {
        XCTAssertEqual(1 - ClusterThreshold.defaultValue, 0.40, accuracy: 1e-9)
    }

    /// 单位向量下弦距 = √(2(1−cos)) = √(2d)
    func testEuclideanLimitIsChordDistanceOfUnitVectors() {
        XCTAssertEqual(ClusterThreshold.euclideanLimit(forCosineDistance: 0.5),
                       Float(1.0), accuracy: 1e-6)
        XCTAssertEqual(ClusterThreshold.euclideanLimit(forCosineDistance: 0.60),
                       Float(1.2).squareRoot(), accuracy: 1e-6)
    }

    /// 回归：`cluster` 内部会自己平方一次，所以这里**不能**把平方距离 2d 直接当距离传下去，
    /// 否则实际阈值变成 4d²，滑杆上半段会把所有人并成一簇。
    func testEuclideanLimitIsNotTheSquaredDistance() {
        let limit = ClusterThreshold.euclideanLimit(forCosineDistance: 0.6)
        XCTAssertLessThan(limit, Float(1.2))
        // 端到端：夹角 60° 的两个单位向量，弦距 1.0
        let a: [Float] = [1, 0]
        let b: [Float] = [0.5, Float(0.75).squareRoot()]
        let service = FaceClusteringService()
        XCTAssertEqual(service.cluster(features: [a, b],
                                       threshold: ClusterThreshold.euclideanLimit(forCosineDistance: 0.6))[0],
                       service.cluster(features: [a, b],
                                       threshold: ClusterThreshold.euclideanLimit(forCosineDistance: 0.6))[1])
        let split = service.cluster(features: [a, b],
                                    threshold: ClusterThreshold.euclideanLimit(forCosineDistance: 0.35))
        XCTAssertNotEqual(split[0], split[1])
    }
}
