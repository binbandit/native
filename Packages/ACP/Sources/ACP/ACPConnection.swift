import Foundation
import os

/// Something the agent sent that the client has to act on.
public enum AgentEvent: Sendable {
    case sessionUpdate(SessionNotification)
    /// Answer with `ACPConnection.respond(to:with:)`, using `RequestPermissionResponse`.
    case permissionRequest(RequestID, RequestPermissionRequest)
    case disconnected
}

public enum ACPConnectionError: Error, LocalizedError {
    case disconnected

    public var errorDescription: String? {
        switch self {
        case .disconnected: "The agent is no longer running."
        }
    }
}

/// The client side of an ACP connection: newline-delimited JSON-RPC over a pair of file handles,
/// usually the agent process's stdout and stdin.
public actor ACPConnection {
    public typealias EventHandler = @Sendable (AgentEvent) async -> Void

    private let reader: FileHandle
    private let writer: FileHandle
    private let onEvent: EventHandler
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return encoder
    }()
    private let decoder = JSONDecoder()
    private let logger = Logger(subsystem: "Native", category: "ACP")

    private var nextID = 0
    private var pending: [RequestID: CheckedContinuation<Data, any Error>] = [:]
    private var isClosed = false
    private var readTask: Task<Void, Never>?

    /// Events are delivered one at a time, in the order the agent sent them, and each `send` returns
    /// only after the events that preceded its response were handled. So when a `session/prompt`
    /// returns, every update of that turn has been applied.
    public init(reading: FileHandle, writing: FileHandle, onEvent: @escaping EventHandler) {
        self.reader = reading
        self.writer = writing
        self.onEvent = onEvent
    }

    public func start() {
        guard readTask == nil else { return }
        readTask = Task { await readLoop() }
    }

    public func send<Request: ACPRequest>(_ request: Request) async throws -> Request.Response {
        guard !isClosed else { throw ACPConnectionError.disconnected }
        let id = RequestID.int(nextID)
        nextID += 1
        let data = try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try write(OutgoingRequest(id: id, method: Request.method, params: request))
            } catch {
                pending.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
        return try decoder.decode(IncomingResult<Request.Response>.self, from: data).result
    }

    public func notify<Notification: ACPNotification>(_ notification: Notification) throws {
        guard !isClosed else { throw ACPConnectionError.disconnected }
        try write(OutgoingNotification(method: Notification.method, params: notification))
    }

    public func respond(to id: RequestID, with result: some Encodable) throws {
        guard !isClosed else { throw ACPConnectionError.disconnected }
        try write(OutgoingResult(id: id, result: result))
    }

    // MARK: - Reading

    private func readLoop() async {
        // Not `FileHandle.bytes`: its reads block a queue shared by the whole process, so one quiet
        // agent would stall every other connection.
        let chunks = AsyncStream<Data> { continuation in
            reader.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
        }
        // Split on raw "\n" bytes rather than using `lines`, which also breaks on U+2028 and friends,
        // and those can appear unescaped inside JSON strings.
        var buffer = Data()
        for await chunk in chunks {
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
        close()
        await onEvent(.disconnected)
    }

    private func receive(_ line: Data) async {
        let envelope: IncomingEnvelope
        do {
            envelope = try decoder.decode(IncomingEnvelope.self, from: line)
        } catch {
            logger.error("Dropping malformed message: \(String(decoding: line, as: UTF8.self), privacy: .public)")
            return
        }
        switch (envelope.method, envelope.id) {
        case (nil, let id?):
            guard let continuation = pending.removeValue(forKey: id) else { return }
            if let error = envelope.error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: line)
            }
        case (let method?, let id?):
            await handleRequest(method, id: id, line: line)
        case (let method?, nil):
            await handleNotification(method, line: line)
        case (nil, nil):
            break
        }
    }

    private func handleNotification(_ method: String, line: Data) async {
        // Agents may send extension notifications (prefixed `_`), which are safe to ignore.
        guard method == "session/update" else { return }
        do {
            let notification = try decoder.decode(IncomingParams<SessionNotification>.self, from: line).params
            await onEvent(.sessionUpdate(notification))
        } catch {
            logger.error("Dropping undecodable session/update: \(error)")
        }
    }

    private func handleRequest(_ method: String, id: RequestID, line: Data) async {
        do {
            switch method {
            case "session/request_permission":
                let request = try decoder.decode(IncomingParams<RequestPermissionRequest>.self, from: line).params
                await onEvent(.permissionRequest(id, request))
            default:
                // We advertise no optional client capabilities, so anything else (fs, terminals, ...)
                // is unexpected.
                try write(OutgoingError(id: id, error: .methodNotFound(method)))
            }
        } catch {
            try? write(OutgoingError(id: id, error: RPCError(code: -32602, message: "Invalid params: \(error)")))
        }
    }

    // MARK: - Writing

    private func write(_ message: some Encodable) throws {
        var data = try encoder.encode(message)
        data.append(UInt8(ascii: "\n"))
        try writer.write(contentsOf: data)
    }

    private func close() {
        isClosed = true
        let waiting = pending
        pending.removeAll()
        for continuation in waiting.values {
            continuation.resume(throwing: ACPConnectionError.disconnected)
        }
    }
}
