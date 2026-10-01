import Foundation
import CoreGraphics

/// 人脸样本的二进制编解码。
///
/// 为什么不用 JSON：`featureData` 在 JSON 里必须走 base64，体积膨胀约 33%；
/// 而且几万条样本的每次编解码都要走一遍字符串与 Base64 解析。
/// 二进制格式下特征向量基本只是一次内存拷贝。
///
/// 格式（全部小端，由 `BinaryFormat` 提供原语）：
/// ```
/// magic   "PFSS"            4 字节
/// version UInt32
/// count   UInt32
/// 每条样本：
///   id            16 字节
///   assetID       UInt32 长度 + UTF-8 字节
///   boundingBox   4 × Float64（x, y, w, h）
///   feature       UInt32 长度 + 原始字节
///   personFlag    UInt8（1 表示随后有 16 字节 UUID）
///   isIgnored     UInt8
///   manualState   UInt8（0 = nil, 1 = true, 2 = false）
///   createdAt     Float64（timeIntervalSinceReferenceDate）
/// ```
enum SampleBinaryCoding {

    private static let magic: [UInt8] = Array("PFSS".utf8)
    private static let version: UInt32 = 1

    // MARK: - 编码

    static func encode(_ samples: [FaceSample]) -> Data {
        var data = Data()
        data.reserveCapacity(samples.count * 64 + 16)
        data.append(contentsOf: magic)
        BinaryFormat.append(version, to: &data)
        BinaryFormat.append(UInt32(samples.count), to: &data)

        for sample in samples {
            BinaryFormat.append(sample.id, to: &data)
            BinaryFormat.append(sample.assetLocalIdentifier, to: &data)

            BinaryFormat.append(Double(sample.boundingBox.origin.x), to: &data)
            BinaryFormat.append(Double(sample.boundingBox.origin.y), to: &data)
            BinaryFormat.append(Double(sample.boundingBox.size.width), to: &data)
            BinaryFormat.append(Double(sample.boundingBox.size.height), to: &data)

            BinaryFormat.appendBytes(sample.featureData, to: &data)

            if let personID = sample.personID {
                BinaryFormat.append(UInt8(1), to: &data)
                BinaryFormat.append(personID, to: &data)
            } else {
                BinaryFormat.append(UInt8(0), to: &data)
            }

            BinaryFormat.append(sample.isIgnored, to: &data)

            switch sample.assignmentIsManual {
            case .none:        BinaryFormat.append(UInt8(0), to: &data)
            case .some(true):  BinaryFormat.append(UInt8(1), to: &data)
            case .some(false): BinaryFormat.append(UInt8(2), to: &data)
            }

            BinaryFormat.append(sample.createdAt, to: &data)
        }

        return data
    }

    // MARK: - 解码

    /// 任何不一致都返回 nil（调用方会把文件保留为 `.corrupt`），绝不崩溃。
    static func decode(_ data: Data) -> [FaceSample]? {
        var reader = BinaryFormat.Reader(data)

        guard reader.matchesMagic(magic),
              reader.readUInt32() == version,
              let rawCount = reader.readUInt32() else { return nil }

        // 每条样本至少 40 字节，用剩余长度给 count 设上界，避免损坏数据触发巨额分配
        let count = Int(rawCount)
        guard count >= 0, count <= reader.remaining else { return nil }

        var samples: [FaceSample] = []
        samples.reserveCapacity(count)

        for _ in 0..<count {
            guard let id = reader.readUUID(),
                  let assetID = reader.readString(),
                  let x = reader.readDouble(),
                  let y = reader.readDouble(),
                  let w = reader.readDouble(),
                  let h = reader.readDouble(),
                  let featureData = reader.readData(),
                  let personFlag = reader.readUInt8() else { return nil }

            var personID: UUID?
            if personFlag == 1 {
                guard let parsed = reader.readUUID() else { return nil }
                personID = parsed
            } else if personFlag != 0 {
                return nil
            }

            guard let isIgnored = reader.readBool(),
                  let manualState = reader.readUInt8(),
                  let createdAt = reader.readDate() else { return nil }

            let manual: Bool?
            switch manualState {
            case 0: manual = nil
            case 1: manual = true
            case 2: manual = false
            default: return nil
            }

            // 直接构造二进制成员，避免 featureData 再经由 [Float] 往返一次
            var sample = FaceSample(assetLocalIdentifier: assetID,
                                    boundingBox: CGRect(x: x, y: y, width: w, height: h),
                                    feature: [],
                                    personID: personID,
                                    isIgnored: isIgnored,
                                    assignmentIsManual: manual,
                                    createdAt: createdAt)
            sample.id = id
            sample.featureData = featureData
            samples.append(sample)
        }

        guard reader.isAtEnd else { return nil }
        return samples
    }
}
