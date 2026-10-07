import Foundation

/// 聚类阈值的标定（**余弦距离** = 1 − 余弦相似度）。
///
/// v7 起特征换成了 ArcFace(MobileFaceNet) 的 512 维**单位**向量，用余弦距离衡量相似度。
/// 在本机 9 张脸 / 4 个身份上的实测（`build/modelwork/REPORT.md`）：
/// 同人余弦相似度 ∈ [0.657, 0.984]，异人 ∈ [−0.095, 0.082]，可分间隔 0.574。
/// 取**相似度 ≥ 0.40（距离 ≤ 0.60）**为默认操作点 —— 偏精度一侧，
/// 因为「把两个人并成一个」比「把一个人拆成两组」代价更高。
///
/// **换特征模型时这个区间必须重新实测。**
enum ClusterThreshold {

    /// UserDefaults 键。v7 换了特征语义，用新键，避免沿用旧的欧氏距离阈值。
    static let defaultsKey = "clusterThresholdV2"

    /// 默认阈值（余弦距离）。等价于余弦相似度 ≥ 0.40。
    static let defaultValue: Double = 0.60

    /// 可调区间。实测同人最弱的一对在余弦距离 0.343，
    /// 所以低于 0.35 必然开始拆碎同一个人；高于 0.80 则会把不同人并起来。
    static let range: ClosedRange<Double> = 0.30...0.90

    static let step: Double = 0.025

    /// 把越界值夹回区间（历史遗留的旧标定值会落在区间外）。
    static func calibrated(_ stored: Double) -> Double {
        range.contains(stored) ? stored : defaultValue
    }

    /// 换算成 `FaceClusteringService.cluster(threshold:)` 需要的**欧氏距离**上限。
    ///
    /// 单位向量下 `平方欧氏距离 = 2(1 − cos) = 2 × 余弦距离`，
    /// 而 `cluster` 内部会自己再平方一次（它的入参是距离，不是平方距离），
    /// 所以这里必须开方：`√(2d)`。**别把 2d 直接传进去** —— 那等于把阈值又平方了一遍，
    /// 滑杆上半段会瞬间退化成「所有人并成一簇」。
    static func euclideanLimit(forCosineDistance value: Double) -> Float {
        Float((2 * calibrated(value)).squareRoot())
    }
}
