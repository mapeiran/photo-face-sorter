import Foundation
import CoreGraphics

/// 单个人脸样本
struct FaceSample: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// 所属照片
    var assetLocalIdentifier: String
    /// 归一化人脸框（Vision 坐标系，左下原点）
    var boundingBox: CGRect
    /// 人脸特征向量（Float32 二进制，JSON 中以 base64 存储，体积远小于 [Float]）
    var featureData: Data
    /// 归属人物（nil = 未分配）
    var personID: UUID? = nil
    /// 标记为非人物人脸（误识别，屏蔽）
    var isIgnored: Bool = false
    var createdAt: Date = Date()

    init(id: UUID = UUID(),
         assetLocalIdentifier: String,
         boundingBox: CGRect,
         feature: [Float],
         personID: UUID? = nil,
         isIgnored: Bool = false,
         createdAt: Date = Date()) {
        self.id = id
        self.assetLocalIdentifier = assetLocalIdentifier
        self.boundingBox = boundingBox
        self.featureData = feature.withUnsafeBytes { Data($0) }
        self.personID = personID
        self.isIgnored = isIgnored
        self.createdAt = createdAt
    }

    /// 特征向量（Float 数组）
    var feature: [Float] {
        featureData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
