import Foundation
import Vision
import CoreGraphics

/// 人脸特征提取（Vision FeaturePrint）
/// 说明：Apple 无人脸身份识别 API，此处用通用图像特征做聚类，准确度有限。
/// 无状态，可安全地在任意线程上使用
final class FaceEmbeddingService: Sendable {

    /// 当前特征提取方式的稳定标识，会随样本人脸一起记录到缓存里。
    ///
    /// **改动 `embedding(for:)` 的任何语义都必须同时修改这个字符串**
    /// （换请求、换模型、改输出维度、加归一化……）。否则新旧特征会被混在一起聚类，
    /// 得到毫无意义的分组却不报任何错。改了它之后，`EmbeddingConsistency`
    /// 会提示用户做一次全量重扫。
    static let signature = "vision-featureprint-256"

    /// 对人脸裁剪图生成特征向量
    func embedding(for faceImage: CGImage) throws -> [Float] {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: faceImage, orientation: .up, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first as? VNFeaturePrintObservation else {
            return []
        }
        var vector = [Float](repeating: 0, count: observation.elementCount)
        if observation.elementType == .float {
            _ = vector.withUnsafeMutableBytes { buffer in
                observation.data.copyBytes(to: buffer)
            }
        } else if observation.elementType == .double {
            var doubles = [Double](repeating: 0, count: observation.elementCount)
            _ = doubles.withUnsafeMutableBytes { buffer in
                observation.data.copyBytes(to: buffer)
            }
            vector = doubles.map { Float($0) }
        }
        return Self.downsample(vector, to: 256)
    }

    /// 降维（分块平均），减小存储与聚类开销
    static func downsample(_ vector: [Float], to target: Int) -> [Float] {
        guard vector.count > target, target > 0 else { return vector }
        let block = vector.count / target
        guard block > 0 else { return Array(vector.prefix(target)) }
        var result = [Float](repeating: 0, count: target)
        for i in 0..<target {
            var sum: Float = 0
            let base = i * block
            for j in 0..<block where base + j < vector.count {
                sum += vector[base + j]
            }
            result[i] = sum / Float(block)
        }
        return result
    }
}
