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
    /// 该归属是否由用户手动指定。手动指定的样本不会被自动重聚类覆盖。
    ///
    /// 必须是可选类型：Swift 合成的 `Decodable` 不会为非可选属性使用默认值，
    /// 旧缓存里没有这个键，声明为 `Bool = false` 会导致整份 samples 解码失败。
    var assignmentIsManual: Bool? = nil
    var createdAt: Date = Date()

    init(id: UUID = UUID(),
         assetLocalIdentifier: String,
         boundingBox: CGRect,
         feature: [Float],
         personID: UUID? = nil,
         isIgnored: Bool = false,
         assignmentIsManual: Bool? = nil,
         createdAt: Date = Date()) {
        self.id = id
        self.assetLocalIdentifier = assetLocalIdentifier
        self.boundingBox = boundingBox
        self.featureData = feature.withUnsafeBytes { Data($0) }
        self.personID = personID
        self.isIgnored = isIgnored
        self.assignmentIsManual = assignmentIsManual
        self.createdAt = createdAt
    }

    /// 特征向量（Float 数组）
    ///
    /// 用 `loadUnaligned` 逐元素读取：`Data` 的底层存储不保证 4 字节对齐，
    /// 直接 `bindMemory(to: Float.self)` 属于未定义行为。
    var feature: [Float] {
        featureData.withUnsafeBytes { raw in
            let stride = MemoryLayout<Float>.size
            let count = raw.count / stride
            guard count > 0 else { return [] }
            var result = [Float](repeating: 0, count: count)
            for i in 0..<count {
                result[i] = raw.loadUnaligned(fromByteOffset: i * stride, as: Float.self)
            }
            return result
        }
    }
}
