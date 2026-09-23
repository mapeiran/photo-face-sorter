import Foundation
import Vision
import CoreGraphics

/// 人脸特征提取（Vision FeaturePrint）
/// 说明：Apple 无人脸身份识别 API，此处用通用图像特征做聚类，准确度有限。
final class FaceEmbeddingService {

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
            vector.withUnsafeMutableBytes { buffer in
                observation.data.copyBytes(to: buffer)
            }
        } else if observation.elementType == .double {
            var doubles = [Double](repeating: 0, count: observation.elementCount)
            doubles.withUnsafeMutableBytes { buffer in
                observation.data.copyBytes(to: buffer)
            }
            vector = doubles.map { Float($0) }
        }
        return vector
    }
}
