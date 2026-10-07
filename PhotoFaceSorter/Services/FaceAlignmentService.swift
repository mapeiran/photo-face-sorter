import CoreGraphics
import Foundation

/// 人脸 5 点关键点（图像像素坐标：原点在左上、y 向下）
struct FaceLandmarks5: Equatable {
    var leftEye: CGPoint
    var rightEye: CGPoint
    var nose: CGPoint
    var leftMouth: CGPoint
    var rightMouth: CGPoint

    /// ArcFace 模板要求的顺序：左眼、右眼、鼻尖、左嘴角、右嘴角
    var templateOrdered: [CGPoint] { [leftEye, rightEye, nose, leftMouth, rightMouth] }
}

/// 一张图的 RGBA8 像素（行 0 = 图像顶部），支持任意仿射重采样。
///
/// 之所以自己做重采样而不是用 `CGContext` 的变换：Core Graphics 的坐标系与
/// Vision 的关键点坐标系（原点左上、y 向下）不一致，写错一步人脸就会上下翻转，
/// 而且是**静默**变差。这里把采样点算清楚，行为可测、可读。
struct RGBAPixelSource {

    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init?(image: CGImage) {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                                              | CGBitmapInfo.byteOrder32Big.rawValue) else {
                return false
            }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        self.bytes = buffer
    }

    /// 双线性采样（坐标原点左上、y 向下，像素中心在 i + 0.5）。越界返回 nil。
    func sample(x: CGFloat, y: CGFloat) -> (r: Float, g: Float, b: Float)? {
        guard x >= -1, y >= -1, x <= CGFloat(width), y <= CGFloat(height) else { return nil }
        let clampedX = min(max(x, 0), CGFloat(width - 1))
        let clampedY = min(max(y, 0), CGFloat(height - 1))
        let x0 = Int(clampedX.rounded(.down))
        let y0 = Int(clampedY.rounded(.down))
        let x1 = min(x0 + 1, width - 1)
        let y1 = min(y0 + 1, height - 1)
        let fx = Float(clampedX - CGFloat(x0))
        let fy = Float(clampedY - CGFloat(y0))

        func channel(_ px: Int, _ py: Int, _ index: Int) -> Float {
            Float(bytes[(py * width + px) * 4 + index])
        }

        func mix(_ index: Int) -> Float {
            let top = channel(x0, y0, index) + (channel(x1, y0, index) - channel(x0, y0, index)) * fx
            let bottom = channel(x0, y1, index) + (channel(x1, y1, index) - channel(x0, y1, index)) * fx
            return top + (bottom - top) * fy
        }

        return (mix(0), mix(1), mix(2))
    }
}

/// 人脸对齐：5 点相似变换，把任意姿态的脸摆正到 ArcFace 的 112×112 标准姿态。
///
/// 这一步不能省。ArcFace 系模型都是在**对齐后**的 112×112 上训练的，
/// 直接把人脸框 resize 进去，同一个人换个角度/远近就差得很远，识别率会明显变差。
enum FaceAlignmentService {

    static let outputSize = 112

    /// ArcFace 官方 112×112 模板：左眼、右眼、鼻尖、左嘴角、右嘴角
    static let template: [CGPoint] = [
        CGPoint(x: 38.2946, y: 51.6963),
        CGPoint(x: 73.5318, y: 51.5014),
        CGPoint(x: 56.0252, y: 71.7366),
        CGPoint(x: 41.5493, y: 92.3655),
        CGPoint(x: 70.7299, y: 92.2041),
    ]

    /// 求 source → target 的最优**相似变换**（只有旋转 / 均匀缩放 / 平移，无剪切、无镜像）
    static func similarityTransform(from source: [CGPoint],
                                    to target: [CGPoint]) -> CGAffineTransform? {
        guard source.count == target.count, source.count >= 2 else { return nil }
        let count = CGFloat(source.count)
        let sourceMean = CGPoint(x: source.reduce(0) { $0 + $1.x } / count,
                                 y: source.reduce(0) { $0 + $1.y } / count)
        let targetMean = CGPoint(x: target.reduce(0) { $0 + $1.x } / count,
                                 y: target.reduce(0) { $0 + $1.y } / count)

        var a: CGFloat = 0
        var b: CGFloat = 0
        var denominator: CGFloat = 0
        for (point, reference) in zip(source, target) {
            let px = point.x - sourceMean.x
            let py = point.y - sourceMean.y
            let qx = reference.x - targetMean.x
            let qy = reference.y - targetMean.y
            a += px * qx + py * qy
            b += px * qy - py * qx
            denominator += px * px + py * py
        }
        guard denominator > 1e-6 else { return nil }
        a /= denominator
        b /= denominator

        let scale = (a * a + b * b).squareRoot()
        // 关键点异常时别硬对齐，宁可放弃这张脸
        guard scale > 0.02, scale < 50 else { return nil }

        let tx = targetMean.x - (a * sourceMean.x - b * sourceMean.y)
        let ty = targetMean.y - (b * sourceMean.x + a * sourceMean.y)
        return CGAffineTransform(a: a, b: b, c: -b, d: a, tx: tx, ty: ty)
    }

    /// 按 transform 把源图重采样成 112×112 的 RGBA 人脸图。
    static func alignedFace(from source: RGBAPixelSource,
                            transform: CGAffineTransform) -> CGImage? {
        let size = outputSize
        let inverse = transform.inverted()
        var output = [UInt8](repeating: 0, count: size * size * 4)

        for y in 0..<size {
            for x in 0..<size {
                let destination = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                let point = destination.applying(inverse)
                guard let rgb = source.sample(x: point.x - 0.5, y: point.y - 0.5) else { continue }
                let offset = (y * size + x) * 4
                output[offset] = UInt8(min(max(rgb.r, 0), 255))
                output[offset + 1] = UInt8(min(max(rgb.g, 0), 255))
                output[offset + 2] = UInt8(min(max(rgb.b, 0), 255))
                output[offset + 3] = 255
            }
        }

        guard let provider = CGDataProvider(data: Data(output) as CFData) else { return nil }
        return CGImage(width: size,
                       height: size,
                       bitsPerComponent: 8,
                       bitsPerPixel: 32,
                       bytesPerRow: size * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue
                                                | CGBitmapInfo.byteOrder32Big.rawValue),
                       provider: provider,
                       decode: nil,
                       shouldInterpolate: true,
                       intent: .defaultIntent)
    }
}
