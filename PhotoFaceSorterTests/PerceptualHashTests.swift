import XCTest
import CoreGraphics
@testable import PhotoFaceSorter

final class PerceptualHashTests: XCTestCase {

    /// 生成 width×height 灰度图，像素值由 value(x, y) 决定。
    private func image(width: Int, height: Int, _ value: (Int, Int) -> UInt8) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixels[y * width + x] = value(x, y)
            }
        }
        return context.makeImage()
    }

    func testIdenticalImagesHashEqually() throws {
        let a = try XCTUnwrap(image(width: 18, height: 16) { x, _ in UInt8(x * 255 / 17) })
        let b = try XCTUnwrap(image(width: 18, height: 16) { x, _ in UInt8(x * 255 / 17) })
        XCTAssertEqual(PerceptualHash.hammingDistance(PerceptualHash.dHash(from: a),
                                                      PerceptualHash.dHash(from: b)), 0)
    }

    func testOppositeGradientsDifferEnough() throws {
        let leftToRight = try XCTUnwrap(image(width: 18, height: 16) { x, _ in UInt8(x * 255 / 17) })
        let rightToLeft = try XCTUnwrap(image(width: 18, height: 16) { x, _ in UInt8(255 - x * 255 / 17) })
        XCTAssertGreaterThan(PerceptualHash.hammingDistance(PerceptualHash.dHash(from: leftToRight),
                                                            PerceptualHash.dHash(from: rightToLeft)),
                             DuplicateDetector.hammingThreshold)
    }

    func testHammingDistanceCountsBits() {
        XCTAssertEqual(PerceptualHash.hammingDistance(0, 0), 0)
        XCTAssertEqual(PerceptualHash.hammingDistance(0, 1), 1)
        XCTAssertEqual(PerceptualHash.hammingDistance(0, 0b1011), 3)
        XCTAssertEqual(PerceptualHash.hammingDistance(UInt64.max, 0), 64)
    }
}
