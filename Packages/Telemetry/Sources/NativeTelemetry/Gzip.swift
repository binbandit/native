import Foundation

/// gzip (RFC 1952) around Foundation's raw DEFLATE, which is what OTLP's `Content-Encoding: gzip`
/// expects.
enum Gzip {
    static func compress(_ data: Data) throws -> Data {
        let deflated = try (data as NSData).compressed(using: .zlib) as Data
        var output = Data([0x1F, 0x8B, 0x08, 0, 0, 0, 0, 0, 0, 0xFF])
        output.append(deflated)
        output.append(littleEndian: CRC32.checksum(data))
        output.append(littleEndian: UInt32(truncatingIfNeeded: data.count))
        return output
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        (0..<8).reduce(UInt32(index)) { crc, _ in crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
    }

    static func checksum(_ data: Data) -> UInt32 {
        ~data.reduce(~UInt32(0)) { crc, byte in table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
    }
}

extension Data {
    fileprivate mutating func append(littleEndian value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
