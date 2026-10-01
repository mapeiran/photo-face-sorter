import Foundation

/// 聚类阈值的标定。
///
/// 阈值必须与特征提取方式一起标定。实测 `vision-featureprint-256`（256 维、通用图像特征）下，
/// 实测 1038 张人脸两两最大**平方**距离只有约 0.19，旧默认值 0.9 远大于它，
/// 结果所有照片必然并成一个「人物 1」。默认值因此下调到 0.25。
///
/// **换特征模型时这个区间必须重新实测。**
enum ClusterThreshold {

    /// 默认阈值（实测 0.25 附近能把人脸分成若干组）
    static let defaultValue: Double = 0.25

    /// 可调区间：低于 0.10 会把同一个人拆得很碎，高于 0.35 又会并成少数几坨
    static let range: ClosedRange<Double> = 0.10...0.35

    static let step: Double = 0.025

    /// 旧版本（0.5…1.5 标定）的默认值，迁移时用来判断是否需要重标定
    static let legacyDefault: Double = 0.9

    /// 把旧标定下的阈值或越界值夹到新标定区间。
    /// 落在区间内的值原样保留（用户可能已经手动调过）。
    static func calibrated(_ stored: Double) -> Double {
        range.contains(stored) ? stored : defaultValue
    }
}
