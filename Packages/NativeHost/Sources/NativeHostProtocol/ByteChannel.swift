import Foundation
import Synchronization

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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
///
/// Each channel does its I/O on a thread of its own, waiting in `poll(2)`, rather than through
/// dispatch sources. On Linux, libdispatch's epoll backend can free a source's bookkeeping while it
/// is still delivering that descriptor's hang-up, so the host crashed whenever an agent exited or a
/// client went away (swift-corelibs-libdispatch#949).
public final class ByteChannel: ByteStream {
    public static let backlogLimit = 64 << 20

    private let engine: ByteChannelEngine

    /// Takes ownership of both descriptors: nothing else may close them. The channel's thread makes
    /// them non-blocking while it uses them and closes them when it's done. They may not be the same
    /// descriptor; use `socket(_:)` for a socket.
    public init(reading readDescriptor: Int32, writing writeDescriptor: Int32, label: String) {
        let engine = ByteChannelEngine(reading: readDescriptor, writing: writeDescriptor)
        self.engine = engine
        let thread = Thread { engine.run() }
        thread.name = "Native.ByteChannel.\(label)"
        thread.start()
    }

    /// What's queued still goes out. A stream something is still reading keeps the channel open
    /// until the other end hangs up.
    deinit {
        engine.release()
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
        let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
        engine.startReading(into: continuation)
        return stream
    }

    /// Queues `data` for the other end. Returns false when the channel is closed or the other end
    /// has stopped reading, in which case the channel closes.
    ///
    /// Writes made in a burst (a streaming agent's updates going out to a client) go out together:
    /// the channel's thread takes everything queued since its last write in one go.
    @discardableResult
    public func write(_ data: Data) -> Bool {
        guard engine.queue(data, limit: Self.backlogLimit) else {
            engine.end(discardingPendingWrites: true)
            return false
        }
        return true
    }

    /// Returns once everything written so far has gone out (or failed to).
    public func flushed() async {
        await engine.flushed()
    }

    public var isClosed: Bool {
        engine.isClosed
    }

    /// Runs `action` once the channel closes, right away if it already has.
    public func onClose(_ action: @escaping @Sendable () -> Void) {
        engine.onClose(action)
    }

    public func close() {
        close(discardingPendingWrites: false)
    }

    /// Stops reading. Queued writes still go out before the descriptors close, unless the other end
    /// has stopped listening anyway (`discardingPendingWrites`).
    public func close(discardingPendingWrites: Bool) {
        engine.end(discardingPendingWrites: discardingPendingWrites)
    }
}

/// What a channel's thread shares with its callers. Only the thread touches the channel's
/// descriptors: it reads, writes and finally closes them. Callers change the state and wake it
/// through a pipe it waits on too.
private final class ByteChannelEngine: Sendable {
    private struct State {
        var isClosed = false
        /// Nothing queued will go out: the channel closed discarding it, the other end hung up, or a
        /// write failed.
        var discardsWrites = false
        /// The thread has closed every descriptor, the wake pipe's included.
        var isFinished = false
        /// Where reads go, from `incoming()` until the channel closes.
        var reader: AsyncStream<Data>.Continuation?
        /// Bytes queued and not yet taken by the thread.
        var pending = Data()
        /// Bytes accepted and not yet written: `pending` and the rest of the thread's batch.
        var backlog = 0
        var onClose: [@Sendable () -> Void] = []
        var flushWaiters: [CheckedContinuation<Void, Never>] = []
    }

    /// A descriptor's settings before the channel changed them, restored before it's closed.
    private struct Settings: Sendable {
        var flags: Int32
        var noSigPipe: Int32

        /// Non-blocking, so the thread never waits inside a read or a write; and on Apple platforms
        /// writing to a vanished reader fails instead of raising SIGPIPE.
        static func prepare(_ descriptor: Int32) -> Settings {
            let flags = fcntl(descriptor, F_GETFL)
            if flags >= 0 { _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) }
            #if canImport(Darwin)
            let noSigPipe = fcntl(descriptor, F_GETNOSIGPIPE)
            _ = fcntl(descriptor, F_SETNOSIGPIPE, 1)
            #else
            let noSigPipe: Int32 = -1
            #endif
            return Settings(flags: flags, noSigPipe: noSigPipe)
        }

        func restore(_ descriptor: Int32) {
            if flags >= 0 { _ = fcntl(descriptor, F_SETFL, flags) }
            #if canImport(Darwin)
            if noSigPipe >= 0 { _ = fcntl(descriptor, F_SETNOSIGPIPE, noSigPipe) }
            #endif
        }
    }

    private enum Step {
        case wait(reads: Bool, writes: Bool)
        case finish
    }

    private static let readSize = 64 << 10

    private let reading: Int32
    private let writing: Int32
    /// In the order they were prepared; restored the other way round, since a socket's two
    /// descriptors share their flags.
    private let settings: (reading: Settings, writing: Settings)
    private let wake: (read: Int32, write: Int32)?
    private let state = Mutex(State())

    init(reading: Int32, writing: Int32) {
        self.reading = reading
        self.writing = writing
        let readingSettings = Settings.prepare(reading)
        settings = (readingSettings, Settings.prepare(writing))
        wake = Self.makeWakePipe()
    }

    var isClosed: Bool {
        state.withLock(\.isClosed)
    }

    func startReading(into reader: AsyncStream<Data>.Continuation) {
        let started = state.withLock { state in
            guard !state.isClosed else { return false }
            state.reader = reader
            wakeThread(unlessFinished: state.isFinished)
            return true
        }
        if !started { reader.finish() }
    }

    /// False when the channel is closed or `data` would take the backlog past `limit`.
    func queue(_ data: Data, limit: Int) -> Bool {
        state.withLock { state in
            guard !state.isClosed, state.backlog + data.count <= limit else { return false }
            // With nothing pending the thread may be waiting without watching for writability; with
            // something pending it takes this along.
            if state.pending.isEmpty { wakeThread(unlessFinished: state.isFinished) }
            state.backlog += data.count
            state.pending.append(data)
            return true
        }
    }

    func release() {
        if !state.withLock({ $0.reader != nil }) {
            end(discardingPendingWrites: false)
        }
    }

    func end(discardingPendingWrites: Bool) {
        let ending = state.withLock { state -> (AsyncStream<Data>.Continuation?, [@Sendable () -> Void])? in
            guard !state.isClosed else { return nil }
            state.isClosed = true
            if discardingPendingWrites { state.discardsWrites = true }
            wakeThread(unlessFinished: state.isFinished)
            defer {
                state.reader = nil
                state.onClose = []
            }
            return (state.reader, state.onClose)
        }
        guard let (reader, actions) = ending else { return }
        for action in actions { action() }
        // Nothing more is read; whoever reads sees the end after the close actions have run.
        reader?.finish()
    }

    func flushed() async {
        await withCheckedContinuation { continuation in
            let isFlushed = state.withLock { state in
                let isFlushed = state.backlog == 0 || state.isFinished
                if !isFlushed { state.flushWaiters.append(continuation) }
                return isFlushed
            }
            if isFlushed { continuation.resume() }
        }
    }

    func onClose(_ action: @escaping @Sendable () -> Void) {
        let alreadyClosed = state.withLock { state in
            if !state.isClosed { state.onClose.append(action) }
            return state.isClosed
        }
        if alreadyClosed { action() }
    }

    // MARK: - The channel's thread

    /// Waits for the descriptors or a wake-up, reads and writes what it can, and once the channel has
    /// closed and its last write has gone out, closes everything.
    func run() {
        guard let wake else {
            // Without a way to be woken the channel can't work; it reads as closed straight away.
            end(discardingPendingWrites: true)
            finish()
            return
        }
        var buffer = [UInt8](repeating: 0, count: Self.readSize)
        // Taken from `pending` whole and written in order, `written` bytes of it so far.
        var batch = Data()
        var written = 0
        while true {
            let (step, flushed) = state.withLock { state -> (Step, [CheckedContinuation<Void, Never>]) in
                if state.discardsWrites {
                    state.pending = Data()
                    state.backlog = 0
                    batch = Data()
                    written = 0
                } else if written == batch.count, !state.pending.isEmpty {
                    batch = state.pending
                    written = 0
                    state.pending = Data()
                }
                var flushed: [CheckedContinuation<Void, Never>] = []
                if state.backlog == 0 { swap(&flushed, &state.flushWaiters) }
                let writes = written < batch.count
                if state.isClosed, !writes { return (.finish, flushed) }
                return (.wait(reads: state.reader != nil, writes: writes), flushed)
            }
            for waiter in flushed { waiter.resume() }
            guard case .wait(let reads, let writes) = step else { break }

            var descriptors = [pollfd(fd: wake.read, events: Int16(POLLIN), revents: 0)]
            if reads { descriptors.append(pollfd(fd: reading, events: Int16(POLLIN), revents: 0)) }
            if writes { descriptors.append(pollfd(fd: writing, events: Int16(POLLOUT), revents: 0)) }
            guard poll(&descriptors, nfds_t(descriptors.count), -1) >= 0 else {
                if errno != EINTR, errno != EAGAIN { hangUp() }
                continue
            }
            if descriptors[0].revents != 0 { drain(wake.read) }
            if reads, descriptors[1].revents != 0 { receive(into: &buffer) }
            if writes, let last = descriptors.last, last.revents != 0 { send(batch, from: &written) }
        }
        finish()
    }

    private func receive(into buffer: inout [UInt8]) {
        let count = buffer.withUnsafeMutableBytes { bytes in read(reading, bytes.baseAddress, bytes.count) }
        if count > 0 {
            let chunk = Data(buffer[..<count])
            state.withLock(\.reader)?.yield(chunk)
        } else if count == 0 || !Self.isTransient(errno) {
            hangUp()
        }
    }

    private func send(_ batch: Data, from written: inout Int) {
        let offset = written
        let count = batch.withUnsafeBytes { bytes in
            bytes.baseAddress.map { write(writing, $0 + offset, bytes.count - offset) } ?? 0
        }
        if count > 0 {
            written += count
            state.withLock { $0.backlog -= count }
        } else if count < 0, !Self.isTransient(errno) {
            hangUp()
        }
    }

    /// The other end hung up (or reading or writing failed), so nothing more can be said either way.
    private func hangUp() {
        state.withLock { $0.discardsWrites = true }
        end(discardingPendingWrites: true)
    }

    /// Restores and closes the descriptors, then lets go of anyone still waiting.
    private func finish() {
        let (reader, waiters) = state.withLock { state in
            state.isFinished = true
            state.isClosed = true
            // While holding the lock, so `wakeThread` never writes to a closed (or reused) descriptor.
            if let wake {
                closeDescriptor(wake.read)
                closeDescriptor(wake.write)
            }
            defer {
                state.reader = nil
                state.flushWaiters = []
                state.pending = Data()
                state.backlog = 0
            }
            return (state.reader, state.flushWaiters)
        }
        settings.writing.restore(writing)
        settings.reading.restore(reading)
        closeDescriptor(writing)
        closeDescriptor(reading)
        reader?.finish()
        for waiter in waiters { waiter.resume() }
    }

    /// Makes the thread look at the state again. Called holding the lock, which the thread holds to
    /// close the pipe.
    private func wakeThread(unlessFinished isFinished: Bool) {
        guard !isFinished, let wake else { return }
        var byte: UInt8 = 1
        // A full pipe already has the thread's attention.
        _ = write(wake.write, &byte, 1)
    }

    private func drain(_ descriptor: Int32) {
        var bytes = [UInt8](repeating: 0, count: 64)
        while read(descriptor, &bytes, bytes.count) > 0 {}
    }

    private static func isTransient(_ code: Int32) -> Bool {
        code == EAGAIN || code == EWOULDBLOCK || code == EINTR
    }

    /// Non-blocking and close-on-exec at both ends.
    private static func makeWakePipe() -> (read: Int32, write: Int32)? {
        var descriptors: [Int32] = [-1, -1]
        guard pipe(&descriptors) == 0 else { return nil }
        for descriptor in descriptors {
            _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
            _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
        }
        return (descriptors[0], descriptors[1])
    }
}
