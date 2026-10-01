import Foundation

/// 扫描记录的二进制编解码。
///
/// 之前用 JSON 存 `[String: AssetRecord]`，有两个浪费：
/// 1. 字典的键与值里的 `assetLocalIdentifier` 是同一个字符串，被存了两遍；
/// 2. 几万条记录的 JSON 解析远慢于二进制。
///
/// 格式（全部小端）：
/// ```
/// magic   "PFSR"   4 字节
/// version UInt32
/// count   UInt32
/// 每条记录：
///   assetID            UInt32 长度 + UTF-8 字节
///   scannedAt          Float64
///   faceCount          UInt32
///   hasModificationDate UInt8（1 表示随后有 8 字节）
///   modificationDate   Float64（可选）
/// ```
enum AssetRecordBinaryCoding {

    private static let magic: [UInt8] = Array("PFSR".utf8)
    private static let version: UInt32 = 1

    static func encode(_ records: [AssetRecord]) -> Data {
        var data = Data()
        data.reserveCapacity(records.count * 48 + 16)
        data.append(contentsOf: magic)
        BinaryFormat.append(version, to: &data)
        BinaryFormat.append(UInt32(records.count), to: &data)

        for record in records {
            BinaryFormat.append(record.assetLocalIdentifier, to: &data)
            BinaryFormat.append(record.scannedAt, to: &data)
            BinaryFormat.append(UInt32(max(0, record.faceCount)), to: &data)
            if let modificationDate = record.modificationDate {
                BinaryFormat.append(UInt8(1), to: &data)
                BinaryFormat.append(modificationDate, to: &data)
            } else {
                BinaryFormat.append(UInt8(0), to: &data)
            }
        }

        return data
    }

    /// 任何不一致都返回 nil（调用方会把文件保留为 `.corrupt`），绝不崩溃。
    static func decode(_ data: Data) -> [AssetRecord]? {
        var reader = BinaryFormat.Reader(data)

        guard reader.matchesMagic(magic),
              reader.readUInt32() == version,
              let rawCount = reader.readUInt32() else { return nil }

        // 每条记录至少 13 字节，用剩余长度给 count 设上界
        let count = Int(rawCount)
        guard count >= 0, count <= reader.remaining else { return nil }

        var records: [AssetRecord] = []
        records.reserveCapacity(count)

        for _ in 0..<count {
            guard let assetID = reader.readString(),
                  let scannedAt = reader.readDate(),
                  let faceCount = reader.readUInt32(),
                  let hasModificationDate = reader.readUInt8() else { return nil }

            var modificationDate: Date?
            if hasModificationDate == 1 {
                guard let parsed = reader.readDate() else { return nil }
                modificationDate = parsed
            } else if hasModificationDate != 0 {
                return nil
            }

            records.append(AssetRecord(assetLocalIdentifier: assetID,
                                       scannedAt: scannedAt,
                                       faceCount: Int(faceCount),
                                       modificationDate: modificationDate))
        }

        guard reader.isAtEnd else { return nil }
        return records
    }
}
