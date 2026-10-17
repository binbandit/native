import Dispatch
import Foundation
import Synchronization

/// A byte stream in both directions that JSON-RPC runs over: a local socket, an agent's stdio, an
/// SSH bridge's stdio, and later a WebSocket. Writes must never block the caller.
public protocol ByteStream: Sendable {
    /// The bytes the other end sends, until it closes its end. Call once.
    func incoming() -> AsyncStream<Data>
    /// Queues `data` for the other end; false when the stream is closed.
    @discardableResult func write(_ data: Data) -> Bool
    func close()
}

/// A file-descriptor stream in both directions (a socket, or an agent's stdout and stdin) that never blocks
/// its caller: reads arrive as chunks, and writes queue up in the order they were made. A peer that
/// stops reading can't stall the host; once its backlog passes `backlogLimit` the channel closes.
public final class ByteChannel: ByteStream {
    public static let backlogLimit = 64 << 20

    private let reader: DispatchIO
    private let writer: DispatchIO
    private let queue: DispatchQueue
    private let state = Mutex(State())

    private struct State {
        var backlog = 0
        var isClosed = false
        var onClose: [@Sendable () -> Void] = []
        var flushWaiters: [CheckedContinuation<Void, Never>] = []
    }

    /// Takes ownership of both descriptors and closes them when the channel closes. They may not be
    /// the same descriptor; use `socket(_:)` for a socket.
    public init(reading readDescriptor: Int32, writing writeDescriptor: Int32, label: String) {
        let queue = DispatchQueue(label: "Native.ByteChannel.\(label)")
        self.queue = queue
        reader = DispatchIO(type: .stream, fileDescriptor: readDescriptor, queue: queue) { _ in
            closeDescriptor(readDescriptor)
        }
        writer = DispatchIO(type: .stream, fileDescriptor: writeDescriptor, queue: queue) { _ in
            closeDescriptor(writeDescriptor)
        }
        // Deliver whatever has arrived rather than waiting to fill a buffer.
        reader.setLimit(lowWater: 1)
    }

    /// A channel over a connected socket. Reading and writing get their own descriptor so each
    /// direction can shut down on its own.
    public static func socket(_ descriptor: Int32, label: String) -> ByteChannel {
        ByteChannel(reading: descriptor, writing: dup(descriptor), label: label)
    }

    /// The bytes the other end sends, until it closes its end. Call once.
    public func incoming() -> AsyncStream<Data> {
        AsyncStream { continuation in
            reader.read(offset: 0, length: Int.max, queue: queue) { [weak self] done, data, error in
                if let data, !data.isEmpty {
                    continuation.yield(Data(data))
                }
                if done {
                    continuation.finish()
                    // The other end hung up (or the read failed), so nothing more can be said either.
                    self?.close(discardingPendingWrites: true)
                }
            }
        }
    }

    /// Queues `data` for the other end. Returns false when the channel is closed or the other end
    /// has stopped reading, in which case the channel closes.
    @discardableResult
    public func write(_ data: Data) -> Bool {
        let accepted = state.withLock { state in
            guard !state.isClosed, state.backlog + data.count <= Self.backlogLimit else { return false }
            state.backlog += data.count
            return true
        }
        guard accepted else {
            close(discardingPendingWrites: true)
            return false
        }
        let count = data.count
        let bytes = data.withUnsafeBytes { DispatchData(bytes: $0) }
        writer.write(offset: 0, data: bytes, queue: queue) { [weak self] done, _, error in
            guard done, let self else { return }
            let waiters = state.withLock { state in
                state.backlog -= count
                defer { if state.backlog == 0 { state.flushWaiters = [] } }
                return state.backlog == 0 ? state.flushWaiters : []
            }
            for waiter in waiters { waiter.resume() }
            if error != 0 {
                close(discardingPendingWrites: true)
            }
        }
        return true
    }

    /// Returns once everything written so far has gone out (or failed to).
    public func flushed() async {
        await withCheckedContinuation { continuation in
            let isEmpty = state.withLock { state in
                if state.backlog > 0 { state.flushWaiters.append(continuation) }
                return state.backlog == 0
            }
            if isEmpty { continuation.resume() }
        }
    }

    public var isClosed: Bool {
        state.withLock(\.isClosed)
    }

    /// Runs `action` once the channel closes, right away if it already has.
    public func onClose(_ action: @escaping @Sendable () -> Void) {
        let alreadyClosed = state.withLock { state in
            if !state.isClosed { state.onClose.append(action) }
            return state.isClosed
        }
        if alreadyClosed { action() }
    }

    public func close() {
        close(discardingPendingWrites: false)
    }

    /// Stops reading. Queued writes still go out before the descriptors close, unless the other end
    /// has stopped listening anyway (`discardingPendingWrites`).
    public func close(discardingPendingWrites: Bool) {
        let actions: [@Sendable () -> Void]? = state.withLock { state in
            guard !state.isClosed else { return nil }
            state.isClosed = true
            defer { state.onClose = [] }
            return state.onClose
        }
        guard let actions else { return }
        reader.close(flags: .stop)
        writer.close(flags: discardingPendingWrites ? .stop : [])
        for action in actions { action() }
    }
}
