import Foundation
import NativeHostProtocol
import Synchronization

/// An encrypted, authenticated byte stream over a raw one, after a Noise handshake: each write
/// becomes one or more Noise transport messages, and each message read is checked before its bytes
/// are handed on. A message that fails authentication closes the channel. The host protocol runs
/// over it unchanged, exactly as over the local socket.
public final class SecureChannel: ByteStream {
    /// What fits in one Noise message once the tag is added.
    static let maximumPlaintext = LinkFrame.maximumBodyLength - NoiseCipherState.tagLength

    /// The peer's pinned key.
    public let remoteKey: LinkPublicKey
    /// Binds the session; both ends agree on it.
    let handshakeHash: Data

    private let raw: any ByteStream
    private let reader: LinkFrameReader
    private let sender: Mutex<NoiseCipherState>
    private let receiver: Mutex<NoiseCipherState>
    private let closeActions = Mutex<[@Sendable () -> Void]?>([])

    init(
        raw: any ByteStream, reader: LinkFrameReader, ciphers: (send: NoiseCipherState, receive: NoiseCipherState),
        remoteKey: LinkPublicKey, handshakeHash: Data
    ) {
        self.raw = raw
        self.reader = reader
        sender = Mutex(ciphers.send)
        receiver = Mutex(ciphers.receive)
        self.remoteKey = remoteKey
        self.handshakeHash = handshakeHash
    }

    public func incoming() -> AsyncStream<Data> {
        AsyncStream { continuation in
            let task = Task {
                while let message = try? await receiveMessage() {
                    continuation.yield(message)
                }
                continuation.finish()
                close()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    @discardableResult
    public func write(_ data: Data) -> Bool {
        // Encrypting and writing under one lock keeps nonces in the order the frames go out.
        let written = sender.withLock { cipher -> Bool in
            var offset = data.startIndex
            while offset < data.endIndex {
                let end = data.index(offset, offsetBy: Self.maximumPlaintext, limitedBy: data.endIndex) ?? data.endIndex
                guard let ciphertext = try? cipher.encrypt(Data(data[offset..<end]), associatedData: Data()),
                    raw.write(LinkFrame(kind: .noise, body: ciphertext).encoded)
                else { return false }
                offset = end
            }
            return true
        }
        if !written { close() }
        return written
    }

    public func close() {
        raw.close()
        let actions = closeActions.withLock { actions in
            defer { actions = nil }
            return actions
        }
        for action in actions ?? [] { action() }
    }

    /// Runs `action` once the channel closes, right away if it already has.
    public func onClose(_ action: @escaping @Sendable () -> Void) {
        let isClosed = closeActions.withLock { actions in
            actions?.append(action)
            return actions == nil
        }
        if isClosed { action() }
    }

    /// One whole message, decrypted. Handshake follow-ups (the welcome) use this before the stream
    /// is handed on; afterwards `incoming()` does.
    func receiveMessage() async throws -> Data {
        let frame = try await reader.next()
        // A wrong pairing code is only noticed by the host after the handshake's last message, so
        // its refusal can come here, in place of the first encrypted message.
        guard frame.kind == .noise else { throw LinkError.refused(LinkRefusal(byte: frame.body.first)) }
        return try receiver.withLock { try $0.decrypt(frame.body, associatedData: Data()) }
    }

    func send<Message: Encodable>(_ message: Message) throws {
        guard write(try JSONEncoder().encode(message)) else { throw LinkError.closed }
    }

    func receive<Message: Decodable>(_ type: Message.Type) async throws -> Message {
        do {
            return try JSONDecoder().decode(type, from: try await receiveMessage())
        } catch let error as DecodingError {
            throw LinkError.malformed("\(error)")
        }
    }
}
