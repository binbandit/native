import ACP
import Foundation
import Synchronization

/// One end of a newline-delimited JSON-RPC 2.0 connection, the framing ACP uses over stdio. The host
/// speaks it to agents (over their stdio) and to clients (over a socket), and clients speak it back,
/// so there is one implementation of the wire for all three.
///
/// Incoming requests and notifications are handled one at a time, in the order they arrived, and a
/// request's response is delivered only after everything that arrived before it was handled. Writes
/// never block: they queue on the channel in the order they were made.
public final class JSONRPCPeer: Sendable {
    public enum Event: Sendable {
        /// Answer with `respond(to:with:)` or `respond(to:error:)`.
        case request(Message)
        case notification(Message)
        /// The other end went away; nothing more will arrive and requests in flight have failed.
        case closed
    }

    /// An incoming request or notification. Its params are decoded on demand, so handlers can keep
    /// them verbatim (`rawParams`) or decode the type they expect.
    public struct Message: Sendable {
        public let id: RequestID?
        public let method: String
        let line: Data

        public func params<Params: Decodable>(as type: Params.Type = Params.self) throws -> Params {
            try JSONRPCPeer.makeDecoder().decode(IncomingParams<Params>.self, from: line).params
        }

        /// The params exactly as sent, for forwarding.
        public var rawParams: JSONValue? {
            JSONValue(json: line)?["params"]
        }
    }

    public typealias Handler = @Sendable (Event) async -> Void

    private let channel: any ByteStream
    private let handler: Handler
    private let label: String
    private let state = Mutex(State())
    private let logger = HostLogger(category: "JSONRPC")

    private struct State {
        var nextID = 0
        var pending: [RequestID: CheckedContinuation<Data, any Error>] = [:]
        var isClosed = false
        var reading: Task<Void, Never>?
    }

    public init(channel: any ByteStream, label: String, handler: @escaping Handler) {
        self.channel = channel
        self.label = label
        self.handler = handler
    }

    /// Starts reading. Events go to the handler until the other end closes.
    public func start() {
        let task = Task { await readLoop() }
        state.withLock { $0.reading = task }
    }

    public var isClosed: Bool {
        state.withLock(\.isClosed)
    }

    /// Returns once the connection has closed and the handler has seen `.closed`.
    public func closed() async {
        await state.withLock(\.reading)?.value
    }

    public func close() {
        channel.close()
    }

    // MARK: - Sending

    public func request<Result: Decodable & Sendable>(
        _ method: String, _ params: some Encodable & Sendable, as result: Result.Type = Result.self
    ) async throws -> Result {
        let line = try await requestLine(method, params)
        return try Self.makeDecoder().decode(IncomingResult<Result>.self, from: line).result
    }

    /// Sends one of ACP's typed requests.
    public func send<Request: ACPRequest>(_ request: Request) async throws -> Request.Response {
        try await self.request(Request.method, request, as: Request.Response.self)
    }

    public func notify(_ method: String, _ params: some Encodable & Sendable) throws {
        try write(OutgoingNotification(method: method, params: params))
    }

    public func respond(to id: RequestID, with result: some Encodable & Sendable) throws {
        try write(OutgoingResult(id: id, result: result))
    }

    public func respond(to id: RequestID, error: RPCError) throws {
        try write(OutgoingError(id: id, error: error))
    }

    private func requestLine(_ method: String, _ params: some Encodable & Sendable) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let id: RequestID? = state.withLock { state in
                guard !state.isClosed else { return nil }
                let id = RequestID.int(state.nextID)
                state.nextID += 1
                state.pending[id] = continuation
                return id
            }
            guard let id else {
                continuation.resume(throwing: PeerError.closed)
                return
            }
            do {
                try write(OutgoingRequest(id: id, method: method, params: params))
            } catch {
                if let continuation = state.withLock({ $0.pending.removeValue(forKey: id) }) {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func write(_ message: some Encodable) throws {
        var data = try Self.makeEncoder().encode(message)
        data.append(UInt8(ascii: "\n"))
        guard channel.write(data) else { throw PeerError.closed }
    }

    // MARK: - Reading

    private func readLoop() async {
        // Split on raw "\n" bytes rather than lines, which also breaks on U+2028 and friends, and
        // those can appear unescaped inside JSON strings.
        var buffer = Data()
        for await chunk in channel.incoming() {
            buffer.append(chunk)
            var lineStart = buffer.startIndex
            while let newline = buffer[lineStart...].firstIndex(of: UInt8(ascii: "\n")) {
                if newline > lineStart {
                    await receive(Data(buffer[lineStart..<newline]))
                }
                lineStart = buffer.index(after: newline)
            }
            buffer.removeSubrange(buffer.startIndex..<lineStart)
        }
        let waiting = state.withLock { state in
            state.isClosed = true
            defer { state.pending.removeAll() }
            return Array(state.pending.values)
        }
        for continuation in waiting {
            continuation.resume(throwing: PeerError.closed)
        }
        await handler(.closed)
    }

    private func receive(_ line: Data) async {
        let envelope: IncomingEnvelope
        do {
            envelope = try Self.makeDecoder().decode(IncomingEnvelope.self, from: line)
        } catch {
            logger.error("\(label): dropping malformed message: \(String(decoding: line.prefix(512), as: UTF8.self))")
            return
        }
        switch (envelope.method, envelope.id) {
        case (nil, let id?):
            guard let continuation = state.withLock({ $0.pending.removeValue(forKey: id) }) else { return }
            if let error = envelope.error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: line)
            }
        case (let method?, let id?):
            await handler(.request(Message(id: id, method: method, line: line)))
        case (let method?, nil):
            await handler(.notification(Message(id: nil, method: method, line: line)))
        case (nil, nil):
            break
        }
    }

    // MARK: - Coding

    /// Dates travel as milliseconds since 1970, which both ends (and anything else reading the log)
    /// agree on without parsing calendars.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

public enum PeerError: Error, LocalizedError, Equatable {
    case closed

    public var errorDescription: String? {
        switch self {
        case .closed: "The connection closed."
        }
    }
}

extension RPCError {
    public static func methodNotFound(_ method: String) -> RPCError {
        RPCError(code: -32601, message: "Method not found: \(method)")
    }

    public static func invalidParams(_ error: any Error) -> RPCError {
        RPCError(code: -32602, message: "Invalid params: \(error.localizedDescription)")
    }
}

// MARK: - Wire envelopes

private struct OutgoingRequest<Params: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: RequestID
    let method: String
    let params: Params
}

private struct OutgoingNotification<Params: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let method: String
    let params: Params
}

private struct OutgoingResult<Result: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: RequestID
    let result: Result
}

private struct OutgoingError: Encodable {
    let jsonrpc = "2.0"
    let id: RequestID
    let error: RPCError
}

/// Just enough of an incoming message to route it; the payload is decoded again once its type is known.
private struct IncomingEnvelope: Decodable {
    let id: RequestID?
    let method: String?
    let error: RPCError?
}

private struct IncomingParams<Params: Decodable>: Decodable {
    let params: Params
}

private struct IncomingResult<Result: Decodable>: Decodable {
    let result: Result
}
