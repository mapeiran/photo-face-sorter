import CoreGraphics
import Foundation

/// 人脸特征提取：ArcFace(MobileFaceNet) Core ML 模型，512 维，输出**已 L2 归一化**。
///
/// 送进来的人脸图必须是**已对齐**的 112×112（见 `FaceAlignmentService`）。
/// 无状态，可安全地在任意线程上使用。
final class FaceEmbeddingService: Sendable {

    /// 当前特征提取方式的稳定标识，会随样本人脸一起记录到缓存里。
    ///
    /// **改动特征语义的任何东西都必须同时改这个字符串**
    /// （换模型、换前处理、改维度、加/去归一化……）。否则新旧特征会被混在一起聚类，
    /// 得到毫无意义的分组却不报任何错。改了它之后，`EmbeddingConsistency`
    /// 会提示用户做一次全量重扫。
    static let signature = "arcface-mobilefacenet-512"

    /// 对**已对齐**的人脸图生成 512 维单位特征
    func embedding(for alignedFace: CGImage) throws -> [Float] {
        let raw = FaceRecognitionModel.shared.embedding(forAlignedFace: alignedFace)
        guard !raw.isEmpty else { return [] }
        return Self.normalized(raw)
    }

    /// L2 归一化：归一化后用余弦（等价于欧氏距离排序）比较，阈值才有稳定的含义。
    static func normalized(_ vector: [Float]) -> [Float] {
        var sum: Float = 0
        for value in vector { sum += value * value }
        let norm = sum.squareRoot()
        guard norm > 1e-6 else { return vector }
        return vector.map { $0 / norm }
    }
}
