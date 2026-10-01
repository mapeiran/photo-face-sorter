import Foundation

/// 二进制编解码的共享原语（全部小端）。
///
/// 样本与扫描记录都用它，避免两套手写的字节读写逻辑各自出错。
enum BinaryFormat {

    // MARK: - 写入

    static func append(_ value: UInt8, to data: inout Data) {
        data.append(value)
    }

    static func append(_ value: UInt32, to data: inout Data) {
        let v = value.littleEndian
        data.append(UInt8(v & 0xFF))
        data.append(UInt8((v >> 8) & 0xFF))
        data.append(UInt8((v >> 16) & 0xFF))
        data.append(UInt8((v >> 24) & 0xFF))
    }

    static func append(_ value: UInt64, to data: inout Data) {
        let v = value.littleEndian
        for shift in 0..<8 {
            data.append(UInt8((v >> (8 * UInt64(shift))) & 0xFF))
        }
    }

    static func append(_ value: Double, to data: inout Data) {
        append(value.bitPattern, to: &data)
    }

    static func append(_ value: Date, to data: inout Data) {
        append(value.timeIntervalSinceReferenceDate, to: &data)
    }

    static func append(_ value: Bool, to data: inout Data) {
        append(UInt8(value ? 1 : 0), to: &data)
    }

    static func append(_ value: UUID, to data: inout Data) {
        let u = value.uuid
        data.append(contentsOf: [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7,
                                 u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15])
    }

    /// 长度前缀 + UTF-8 字节
    static func append(_ value: String, to data: inout Data) {
        let bytes = Array(value.utf8)
        append(UInt32(bytes.count), to: &data)
        data.append(contentsOf: bytes)
    }

    /// 长度前缀 + 原始字节
    static func appendBytes(_ value: Data, to data: inout Data) {
        append(UInt32(value.count), to: &data)
        data.append(value)
    }

    // MARK: - 读取

    /// 顺序读取游标。任何越界都返回 nil，绝不崩溃。
    struct Reader {
        private let bytes: [UInt8]
        private var offset = 0

        init(_ data: Data) {
            bytes = [UInt8](data)
        }

        var remaining: Int { bytes.count - offset }
        var isAtEnd: Bool { offset >= bytes.count }

        mutating func readUInt8() -> UInt8? {
            guard offset < bytes.count else { return nil }
            defer { offset += 1 }
            return bytes[offset]
        }

        mutating func readBool() -> Bool? {
            readUInt8().map { $0 == 1 }
        }

        mutating func readUInt32() -> UInt32? {
            guard let raw = readRawBytes(4) else { return nil }
            return UInt32(raw[0])
                | UInt32(raw[1]) << 8
                | UInt32(raw[2]) << 16
                | UInt32(raw[3]) << 24
        }

        mutating func readUInt64() -> UInt64? {
            guard let raw = readRawBytes(8) else { return nil }
            var value: UInt64 = 0
            for index in 0..<8 {
                value |= UInt64(raw[index]) << (8 * UInt64(index))
            }
            return value
        }

        mutating func readDouble() -> Double? {
            readUInt64().map { Double(bitPattern: $0) }
        }

        mutating func readDate() -> Date? {
            readDouble().map { Date(timeIntervalSinceReferenceDate: $0) }
        }

        mutating func readUUID() -> UUID? {
            guard let raw = readRawBytes(16) else { return nil }
            return UUID(uuid: (raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
                               raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15]))
        }

        /// 定长字节（不做长度前缀）
        mutating func readRawBytes(_ count: Int) -> [UInt8]? {
            guard count >= 0, offset + count <= bytes.count else { return nil }
            defer { offset += count }
            return Array(bytes[offset..<(offset + count)])
        }

        /// 长度前缀的原始字节。长度来自文件本身，必须先做上界检查再分配。
        mutating func readLengthPrefixedBytes() -> [UInt8]? {
            guard let length = readUInt32() else { return nil }
            return readRawBytes(Int(length))
        }

        mutating func readString() -> String? {
            guard let raw = readLengthPrefixedBytes() else { return nil }
            return String(bytes: raw, encoding: .utf8)
        }

        mutating func readData() -> Data? {
            readLengthPrefixedBytes().map { Data($0) }
        }

        /// 读取并比对魔数
        mutating func matchesMagic(_ magic: [UInt8]) -> Bool {
            readRawBytes(magic.count) == magic
        }
    }
}
