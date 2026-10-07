import CoreML
import CoreGraphics
import Foundation

/// ArcFace(MobileFaceNet, InsightFace `w600k_mbf`) 的 512 维人脸身份特征。
///
/// 与之前的 `VNGenerateImageFeaturePrintRequest` 有本质区别：那是**通用图像相似度**
/// 特征（会把光线、背景、发型一起编码进去），这是**真正的人脸识别模型**，
/// 同一个人的余弦相似度显著高于不同人 —— 命中率的根本来源。
///
/// 模型完全在本机（Core ML / 神经网络引擎）运行，不联网、不上传。
final class FaceRecognitionModel: @unchecked Sendable {

    static let shared = FaceRecognitionModel()

    static let featureDimension = 512
    static let inputName = "face"
    static let outputName = "embedding"

    private let model: MLModel?

    /// 模型是否成功加载。加载不到时特征恒为空，扫描不会产出人脸样本。
    let isAvailable: Bool

    init(bundle: Bundle = .main) {
        var configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        if let url = bundle.url(forResource: "FaceRecognition", withExtension: "mlmodelc"),
           let loaded = try? MLModel(contentsOf: url, configuration: configuration) {
            model = loaded
            isAvailable = true
        } else {
            model = nil
            isAvailable = false
        }
    }

    /// 对**已对齐**的 112×112 人脸图提取 512 维特征（**未**归一化）
    func embedding(forAlignedFace face: CGImage) -> [Float] {
        guard let model, let input = multiArray(from: face) else { return [] }
        guard let provider = try? MLDictionaryFeatureProvider(
            dictionary: [Self.inputName: MLFeatureValue(multiArray: input)]) else { return [] }
        guard let prediction = try? model.prediction(from: provider),
              let value = prediction.featureValue(for: Self.outputName)?.multiArrayValue else {
            return []
        }
        var result = [Float](repeating: 0, count: value.count)
        for index in 0..<value.count {
            result[index] = value[index].floatValue
        }
        return result
    }

    /// 112×112 RGB → [1, 3, 112, 112]，像素归一化到 [-1, 1]（InsightFace 的标准预处理）
    private func multiArray(from face: CGImage) -> MLMultiArray? {
        let size = FaceAlignmentService.outputSize
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress,
                                          width: size,
                                          height: size,
                                          bitsPerComponent: 8,
                                          bytesPerRow: size * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                                              | CGBitmapInfo.byteOrder32Big.rawValue) else {
                return false
            }
            context.interpolationQuality = .high
            context.draw(face, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard drawn,
              let array = try? MLMultiArray(shape: [1, 3, NSNumber(value: size), NSNumber(value: size)],
                                            dataType: .float32) else {
            return nil
        }

        let strides = array.strides.map { $0.intValue }
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: 3 * size * size)
        for y in 0..<size {
            for x in 0..<size {
                let offset = (y * size + x) * 4
                let base = y * strides[2] + x * strides[3]
                pointer[base] = Float(pixels[offset]) / 127.5 - 1
                pointer[strides[1] + base] = Float(pixels[offset + 1]) / 127.5 - 1
                pointer[2 * strides[1] + base] = Float(pixels[offset + 2]) / 127.5 - 1
            }
        }
        return array
    }
}
