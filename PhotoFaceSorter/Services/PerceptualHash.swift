import Foundation
import CoreGraphics

/// 感知哈希（dHash）：把图片缩成 9×8 灰度图，逐行比较相邻像素得到 64 位指纹。
///
/// 用途：找「视觉重复」的照片（完全相同的副本、重复导入、缩放/压缩后的同一张）。
/// 局限：只看亮度梯度、不看颜色，且对**大幅裁剪**不敏感 —— 但本功能只列出、不删除，
/// 少量误报由用户自己判断即可。
enum PerceptualHash {

    /// dHash 的计算网格（宽比高大 1，用来做水平差分）
    static let width = 9
    static let height = 8

    /// 从任意尺寸的图片算 64 位差分哈希。
    static func dHash(from image: CGImage) -> UInt64 {
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return 0 }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return 0 }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)

        var hash: UInt64 = 0
        var bit = 0
        for y in 0..<height {
            for x in 0..<(width - 1) {
                if pixels[y * width + x] > pixels[y * width + x + 1] {
                    hash |= (UInt64(1) << UInt64(bit))
                }
                bit += 1
            }
        }
        return hash
    }

    /// 两个哈希的汉明距离（不同的位数）
    static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }
}
