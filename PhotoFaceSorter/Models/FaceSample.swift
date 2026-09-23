import Foundation
import CoreGraphics

/// 单个人脸样本
struct FaceSample: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// 所属照片
    var assetLocalIdentifier: String
    /// 归一化人脸框（Vision 坐标系，左下原点）
    var boundingBox: CGRect
    /// 人脸特征向量
    var feature: [Float]
    /// 归属人物（nil = 未分配）
    var personID: UUID? = nil
    /// 标记为非人物人脸（误识别，屏蔽）
    var isIgnored: Bool = false
    var createdAt: Date = Date()
}
