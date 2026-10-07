import Foundation
import Vision
import CoreGraphics

/// 人脸检测（Vision，本地运算）：一次拿到人脸框和关键点。
/// 无状态，可安全地在任意线程上使用。
final class FaceDetectionService: Sendable {

    /// 检测图片中的人脸（带关键点，供 `FaceAlignmentService` 做对齐）
    func detectFaces(in image: CGImage) throws -> [VNFaceObservation] {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        try handler.perform([request])
        return request.results ?? []
    }

    /// 从观测里取对齐用的 5 个点，返回**图像像素坐标（原点左上、y 向下）**。
    ///
    /// ⚠️ Vision 的 `pointsInImage(imageSize:)` 给的是**左下原点（y 向上）**的坐标。
    /// 实测证据：原始坐标下 9/9 张脸都满足「眼睛的 y > 嘴巴的 y」，而眼睛在物理上方，
    /// 说明 y 向上；按 `(x, H − y)` 转换后 5 点能精准落回原图的双眼/鼻/嘴角。
    ///
    /// 所以翻转是**主路径**，不是兜底。忘了翻转会让对齐出来的人脸上下颠倒 ——
    /// 而且同一个人的相似度几乎不变（0.795 → 0.826），崩掉的是**不同人**的地板
    /// （异人 cos 从 −0.012 涨到 0.548），属于静默灾难。
    ///
    /// 关键点不全会返回 nil —— 对齐做不了的样本就不该进聚类。
    func landmarks5(from observation: VNFaceObservation, imageSize: CGSize) -> FaceLandmarks5? {
        guard let landmarks = observation.landmarks,
              let leftEye = landmarks.leftEye,
              let rightEye = landmarks.rightEye,
              let nose = landmarks.nose,
              let lips = landmarks.outerLips else {
            return nil
        }

        // 先统一换成左上原点，再挑点，避免在 y 向上的坐标里把鼻尖取反
        func topLeft(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x, y: imageSize.height - point.y)
        }

        let leftEyePoints = leftEye.pointsInImage(imageSize: imageSize).map(topLeft)
        let rightEyePoints = rightEye.pointsInImage(imageSize: imageSize).map(topLeft)
        let nosePoints = nose.pointsInImage(imageSize: imageSize).map(topLeft)
        let lipPoints = lips.pointsInImage(imageSize: imageSize).map(topLeft)
        guard !leftEyePoints.isEmpty, !rightEyePoints.isEmpty,
              !nosePoints.isEmpty, lipPoints.count >= 2,
              let leftMouth = lipPoints.min(by: { $0.x < $1.x }),
              let rightMouth = lipPoints.max(by: { $0.x < $1.x }) else {
            return nil
        }

        return FaceLandmarks5(leftEye: Self.centroid(leftEyePoints),
                              rightEye: Self.centroid(rightEyePoints),
                              nose: Self.noseTip(nosePoints),
                              leftMouth: leftMouth,
                              rightMouth: rightMouth)
    }

    private static func centroid(_ points: [CGPoint]) -> CGPoint {
        let count = CGFloat(points.count)
        return CGPoint(x: points.reduce(0) { $0 + $1.x } / count,
                       y: points.reduce(0) { $0 + $1.y } / count)
    }

    /// 鼻尖：左上坐标系里最靠下的那个点（实测与取质心差别 < 0.02，不敏感）
    private static func noseTip(_ points: [CGPoint]) -> CGPoint {
        points.max(by: { $0.y < $1.y }) ?? centroid(points)
    }
}
