import Foundation
import Vision
import CoreGraphics

/// 人脸检测（Vision，本地运算）
final class FaceDetectionService {

    /// 检测图片中的人脸，返回人脸观测
    func detectFaces(in image: CGImage) throws -> [VNFaceObservation] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        try handler.perform([request])
        return (request.results as? [VNFaceObservation]) ?? []
    }

    /// 按归一化人脸框裁剪出人脸图
    func cropFace(from image: CGImage, boundingBox: CGRect, padding: CGFloat = 0.2) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        // Vision 归一化坐标（左下原点）→ 像素坐标（左上原点）
        let x = boundingBox.minX * width
        let y = (1 - boundingBox.maxY) * height
        let w = boundingBox.width * width
        let h = boundingBox.height * height
        let rect = CGRect(x: x, y: y, width: w, height: h)
            .insetBy(dx: -w * padding, dy: -h * padding)
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard rect.width > 1, rect.height > 1 else { return nil }
        return image.cropping(to: rect)
    }
}
