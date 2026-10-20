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
        /// Bytes accepted and not yet written.
        var backlog = 0
        /// Bytes accepted since the last hand-off to the writer; see `write`.
        var pending = Data()
        var isFlushScheduled = false
        var isClosed = false
        var onClose: [@Sendable () -> Void] = []
        var flushWaiters: [CheckedContinuation<Void, Never>] = []
    }

    /// Takes ownership of both descriptors: nothing else may close them. Each closes from its dispatch
    /// channel's cleanup handler, the first moment libdispatch has stopped watching it; closed any
    /// earlier, libdispatch traps ("Unexpected EV_VANISHED") or, once the number is reused, acts on
    /// someone else's file. They may not be the same descriptor; use `socket(_:)` for a socket.
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
    /// direction can shut down on its own. Both are close-on-exec, so no process we start inherits the
    /// connection and holds it open (an accepted socket arrives without the flag).
    public static func socket(_ descriptor: Int32, label: String) -> ByteChannel {
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        return ByteChannel(reading: descriptor, writing: fcntl(descriptor, F_DUPFD_CLOEXEC, 0), label: label)
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
    ///
    /// Writes made in a burst (a streaming agent's updates going out to a client) are handed to the
    /// system together: one write per burst instead of one per message, each of which wakes the
    /// event loop.
    @discardableResult
    public func write(_ data: Data) -> Bool {
        enum Outcome { case refused, scheduled, joined }
        let outcome = state.withLock { state -> Outcome in
            guard !state.isClosed, state.backlog + data.count <= Self.backlogLimit else { return .refused }
            state.backlog += data.count
            state.pending.append(data)
            guard !state.isFlushScheduled else { return .joined }
            state.isFlushScheduled = true
            return .scheduled
        }
        switch outcome {
        case .refused:
            close(discardingPendingWrites: true)
            return false
        case .scheduled:
            queue.async { [weak self] in self?.flush() }
        case .joined:
            break
        }
        return true
    }

    /// Hands what's pending to the writer. On `queue`.
    private func flush() {
        let data = state.withLock { state in
            state.isFlushScheduled = false
            defer { state.pending = Data() }
            return state.pending
        }
        guard !data.isEmpty else { return }
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
        let closing: (actions: [@Sendable () -> Void], waiters: [CheckedContinuation<Void, Never>])? = state.withLock {
            state in
            guard !state.isClosed else { return nil }
            state.isClosed = true
            var waiters: [CheckedContinuation<Void, Never>] = []
            if discardingPendingWrites {
                // What was never handed to the writer won't go out; nobody should wait for it.
                state.backlog -= state.pending.count
                state.pending = Data()
                if state.backlog == 0 {
                    waiters = state.flushWaiters
                    state.flushWaiters = []
                }
            }
            defer { state.onClose = [] }
            return (state.onClose, waiters)
        }
        guard let (actions, waiters) = closing else { return }
        for waiter in waiters { waiter.resume() }
        reader.close(flags: .stop)
        if discardingPendingWrites {
            writer.close(flags: .stop)
        } else {
            // After what's pending, which `queue` hands to the writer first.
            queue.async { [self] in
                flush()
                writer.close(flags: [])
            }
        }
        for action in actions { action() }
    }
}
