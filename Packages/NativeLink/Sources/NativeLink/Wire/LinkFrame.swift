import Foundation

/// One message on a link connection: a two-byte big-endian length, a kind byte, then the body.
/// Noise messages are at most 65535 bytes, so one frame always holds one.
struct LinkFrame: Sendable, Equatable {
    enum Kind: UInt8, Sendable {
        /// A Noise handshake or transport message.
        case noise = 0
        /// The host turning a connection away before any keys exist (`LinkRefusal`). Unauthenticated,
        /// so it's only ever shown as what the host said, never acted on beyond ending the attempt.
        case refusal = 1
    }

    static let maximumBodyLength = 65_534

    var kind: Kind
    var body: Data

    var encoded: Data {
        let length = body.count + 1
        var data = Data([UInt8(length >> 8), UInt8(length & 0xFF), kind.rawValue])
        data += body
        return data
    }
}

/// Reads frames off a byte stream, however the bytes arrive in chunks.
actor LinkFrameReader {
    private var chunks: AsyncStream<Data>.Iterator
    private var buffer = Data()

    init(_ stream: AsyncStream<Data>) {
        chunks = stream.makeAsyncIterator()
    }

    /// The next frame; throws `LinkError.closed` once the stream ends.
    func next() async throws -> LinkFrame {
        while true {
            if buffer.count >= 2 {
                let start = buffer.startIndex
                let length = Int(buffer[start]) << 8 | Int(buffer[start + 1])
                guard length >= 1 else { throw LinkError.malformed("an empty frame") }
                if buffer.count >= 2 + length {
                    let kindByte = buffer[start + 2]
                    let body = Data(buffer[(start + 3)..<(start + 2 + length)])
                    buffer = Data(buffer.dropFirst(2 + length))
                    guard let kind = LinkFrame.Kind(rawValue: kindByte) else {
                        throw LinkError.malformed("frame kind \(kindByte)")
                    }
                    return LinkFrame(kind: kind, body: body)
                }
            }
            guard let chunk = await chunks.next(isolation: self) else { throw LinkError.closed }
            buffer += chunk
        }
    }
}
