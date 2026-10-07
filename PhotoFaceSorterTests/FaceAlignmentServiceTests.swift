import XCTest
import CoreGraphics
@testable import PhotoFaceSorter

/// 人脸对齐是识别率的命门：这里把相似变换和像素方向都钉死。
final class FaceAlignmentServiceTests: XCTestCase {

    // MARK: - 相似变换

    func testIdentityWhenSourceEqualsTarget() {
        let transform = FaceAlignmentService.similarityTransform(
            from: FaceAlignmentService.template,
            to: FaceAlignmentService.template)
        let value = try? XCTUnwrap(transform)
        XCTAssertEqual(value?.a ?? 0, 1, accuracy: 1e-6)
        XCTAssertEqual(value?.b ?? 1, 0, accuracy: 1e-6)
        XCTAssertEqual(value?.tx ?? 1, 0, accuracy: 1e-6)
        XCTAssertEqual(value?.ty ?? 1, 0, accuracy: 1e-6)
    }

    func testMapsRotatedScaledTranslatedPointsBackToTemplate() throws {
        let angle = CGFloat.pi / 6
        let scale: CGFloat = 1.5
        let forward = CGAffineTransform(a: cos(angle) * scale,
                                        b: sin(angle) * scale,
                                        c: -sin(angle) * scale,
                                        d: cos(angle) * scale,
                                        tx: 40,
                                        ty: -25)
        let moved = FaceAlignmentService.template.map { $0.applying(forward) }
        let transform = try XCTUnwrap(FaceAlignmentService.similarityTransform(
            from: moved, to: FaceAlignmentService.template))
        for (point, target) in zip(moved, FaceAlignmentService.template) {
            let mapped = point.applying(transform)
            XCTAssertEqual(mapped.x, target.x, accuracy: 1e-3)
            XCTAssertEqual(mapped.y, target.y, accuracy: 1e-3)
        }
    }

    func testDegeneratePointsReturnNil() {
        let collapsed = [CGPoint](repeating: CGPoint(x: 5, y: 5), count: 5)
        XCTAssertNil(FaceAlignmentService.similarityTransform(from: collapsed,
                                                              to: FaceAlignmentService.template))
        XCTAssertNil(FaceAlignmentService.similarityTransform(from: [], to: []))
    }

    // MARK: - 像素方向（对齐的坐标系前提）

    /// 行 0 必须是图像**顶部**。写反的话导出的人脸会上下翻转，而且是静默变差。
    func testPixelSourceKeepsTopRowAtTop() throws {
        let image = try XCTUnwrap(makeImage(rows: [[(255, 0, 0), (255, 0, 0)],
                                                  [(0, 0, 255), (0, 0, 255)]]))
        let source = try XCTUnwrap(RGBAPixelSource(image: image))
        // sample 的约定：整数坐标 = 像素中心
        let top = try XCTUnwrap(source.sample(x: 0, y: 0))
        let bottom = try XCTUnwrap(source.sample(x: 0, y: 1))
        XCTAssertGreaterThan(top.r, 200)
        XCTAssertLessThan(top.b, 50)
        XCTAssertGreaterThan(bottom.b, 200)
        XCTAssertLessThan(bottom.r, 50)
    }

    /// 放大对齐后，图里仍然是「上红下蓝」（不会上下翻转）
    func testAlignedFacePreservesOrientation() throws {
        let image = try XCTUnwrap(makeImage(rows: [[(255, 0, 0), (255, 0, 0)],
                                                  [(0, 0, 255), (0, 0, 255)]]))
        let source = try XCTUnwrap(RGBAPixelSource(image: image))
        // 2×2 源图铺满 112×112（源坐标 0…2 映射到 0…112）
        let transform = CGAffineTransform(scaleX: 56, y: 56)
        let aligned = try XCTUnwrap(FaceAlignmentService.alignedFace(from: source,
                                                                     transform: transform))
        XCTAssertEqual(aligned.width, FaceAlignmentService.outputSize)
        XCTAssertEqual(aligned.height, FaceAlignmentService.outputSize)

        let alignedSource = try XCTUnwrap(RGBAPixelSource(image: aligned))
        let top = try XCTUnwrap(alignedSource.sample(x: 10, y: 10))
        XCTAssertGreaterThan(top.r, 200)
        XCTAssertLessThan(top.b, 50)
        let bottom = try XCTUnwrap(alignedSource.sample(x: 10, y: 100))
        XCTAssertGreaterThan(bottom.b, 200)
        XCTAssertLessThan(bottom.r, 50)
    }

    private func makeImage(rows: [[(UInt8, UInt8, UInt8)]]) -> CGImage? {
        guard let first = rows.first, !first.isEmpty else { return nil }
        let width = first.count
        let height = rows.count
        var bytes: [UInt8] = []
        bytes.reserveCapacity(width * height * 4)
        for row in rows {
            for pixel in row {
                bytes.append(contentsOf: [pixel.0, pixel.1, pixel.2, 255])
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width,
                       height: height,
                       bitsPerComponent: 8,
                       bitsPerPixel: 32,
                       bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue
                                                | CGBitmapInfo.byteOrder32Big.rawValue),
                       provider: provider,
                       decode: nil,
                       shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}
