import Foundation
import NativeHostProtocol
import Network
import Synchronization

/// A TCP connection as the byte stream link connections run over. Writes queue in order and never
/// block; a peer that stops reading is cut off once its backlog passes `backlogLimit`, like the
/// host's own `ByteChannel`.
public final class NetworkByteStream: ByteStream {
    static let backlogLimit = 64 << 20

    let connection: NWConnection
    private let queue: DispatchQueue
    private let state = Mutex(State())

    private struct State {
        var backlog = 0
        var isClosed = false
        var onClose: [@Sendable () -> Void] = []
    }

    /// Takes a connection the listener accepted, or one `connect` made ready, and starts it if needed.
    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.markClosed()
            default: break
            }
        }
        if connection.state == .setup {
            connection.start(queue: queue)
        }
    }

    /// TCP with keepalive, so a phone that walked out of range is noticed in seconds, not hours.
    static var parameters: NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        tcp.keepaliveInterval = 5
        tcp.keepaliveCount = 3
        tcp.connectionTimeout = 5
        return NWParameters(tls: nil, tcp: tcp)
    }

    public enum ConnectError: Error, LocalizedError, Sendable {
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .failed(let reason): reason
            }
        }
    }

    /// Connects to `endpoint`, or throws why it couldn't within `timeout`.
    public static func connect(
        to endpoint: NWEndpoint, timeout: Duration = .seconds(5)
    ) async throws -> NetworkByteStream {
        let queue = DispatchQueue(label: "Native.Link.connection")
        let connection = NWConnection(to: endpoint, using: parameters)
        let resumed = LinkLocked(false)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<NetworkByteStream, any Error>) in
                /// Resumes once; false when the connection already succeeded or failed.
                @Sendable @discardableResult func finish(_ result: Result<NetworkByteStream, any Error>) -> Bool {
                    guard
                        resumed.withLock({ done in
                            defer { done = true }; return !done
                        })
                    else { return false }
                    continuation.resume(with: result)
                    return true
                }
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        finish(.success(NetworkByteStream(connection: connection, queue: queue)))
                    case .waiting(let error), .failed(let error):
                        // Waiting means no route right now; the caller tries the next address instead.
                        connection.cancel()
                        finish(.failure(ConnectError.failed(describe(error))))
                    case .cancelled:
                        finish(.failure(CancellationError()))
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
                queue.asyncAfter(deadline: .now() + .milliseconds(Int(timeout.components.seconds * 1_000))) {
                    // Only a connection still trying is given up on; a ready one is the caller's now.
                    if finish(.failure(ConnectError.failed("No answer within \(timeout.components.seconds) seconds.")))
                    {
                        connection.cancel()
                    }
                }
            }
        } onCancel: {
            connection.cancel()
        }
    }

    public func incoming() -> AsyncStream<Data> {
        AsyncStream { continuation in
            receive(into: continuation)
        }
    }

    private func receive(into continuation: AsyncStream<Data>.Continuation) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
            [weak self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                continuation.yield(data)
            }
            if isComplete || error != nil || self == nil {
                continuation.finish()
                self?.close()
            } else {
                self?.receive(into: continuation)
            }
        }
    }

    @discardableResult
    public func write(_ data: Data) -> Bool {
        let accepted = state.withLock { state in
            guard !state.isClosed, state.backlog + data.count <= Self.backlogLimit else { return false }
            state.backlog += data.count
            return true
        }
        guard accepted else {
            close()
            return false
        }
        let count = data.count
        connection.send(
            content: data,
            completion: .contentProcessed { [weak self] error in
                self?.state.withLock { $0.backlog -= count }
                if error != nil { self?.close() }
            })
        return true
    }

    public func close() {
        connection.cancel()
        markClosed()
    }

    /// Runs `action` once the connection closes, right away if it already has.
    public func onClose(_ action: @escaping @Sendable () -> Void) {
        let alreadyClosed = state.withLock { state in
            if !state.isClosed { state.onClose.append(action) }
            return state.isClosed
        }
        if alreadyClosed { action() }
    }

    private func markClosed() {
        let actions: [@Sendable () -> Void]? = state.withLock { state in
            guard !state.isClosed else { return nil }
            state.isClosed = true
            defer { state.onClose = [] }
            return state.onClose
        }
        for action in actions ?? [] { action() }
    }
}

/// Network.framework's errors in words a person can act on.
func describe(_ error: NWError) -> String {
    switch error {
    case .posix(let code):
        switch code {
        case .ECONNREFUSED: return "Nothing is accepting connections there (Native's gateway may be off)."
        case .ETIMEDOUT: return "No answer: the Mac may be asleep or on another network."
        case .EHOSTUNREACH, .ENETUNREACH, .EHOSTDOWN, .ENETDOWN:
            return "That address isn't reachable from this network."
        default: return "\(code)"
        }
    case .dns: return "The name didn't resolve on this network."
    default: return error.localizedDescription
    }
}
