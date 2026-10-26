import Foundation
import Synchronization

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// The last few KB of an agent's stderr, for explaining why it failed.
///
/// A thread of its own keeps the pipe drained, so a chatty agent never blocks on a full one. It waits
/// in `poll(2)` rather than on a dispatch source, which on Linux can crash the host when the agent
/// exits (see `ByteChannel`).
final class StderrTail: Sendable {
    private let reader: StderrTailReader?

    /// Nothing to read, as before an agent first starts.
    init() {
        reader = nil
    }

    /// Takes ownership of `descriptor`, the read end of the agent's stderr.
    init(reading descriptor: Int32) throws {
        let reader = try StderrTailReader(descriptor)
        self.reader = reader
        let thread = Thread { reader.run() }
        thread.name = "Native.StderrTail"
        thread.start()
    }

    /// Stops reading: the reader closes the pipe, so whatever still writes to it gets an error.
    deinit {
        reader?.stop()
    }

    var text: String {
        reader?.snapshot() ?? ""
    }
}

/// What the tail shares with its reader thread. Only the thread closes the descriptors, holding the
/// lock, so a snapshot or a stop never uses a closed (or reused) one.
private final class StderrTailReader: Sendable {
    private static let limit = 16 * 1024

    private struct State {
        var buffer = Data()
        /// The writers are gone, or the thread has closed the pipe: nothing more to read.
        var isAtEnd = false
        /// The thread has closed the pipe and its wake pipe.
        var isFinished = false
    }

    private let descriptor: Int32
    private let wake: (read: Int32, write: Int32)
    private let state = Mutex(State())

    /// A snapshot must not wait for an agent or a descendant still holding stderr open, even when it
    /// has no more output to give us, so the descriptor is made non-blocking.
    init(_ descriptor: Int32) throws {
        var wake: [Int32] = [-1, -1]
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0, pipe(&wake) == 0 else {
            let code = errno
            _ = close(descriptor)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        for end in wake {
            _ = fcntl(end, F_SETFD, FD_CLOEXEC)
            _ = fcntl(end, F_SETFL, O_NONBLOCK)
        }
        self.descriptor = descriptor
        self.wake = (wake[0], wake[1])
    }

    func snapshot() -> String {
        state.withLock { state in
            // stdout closing and initialize failing can both beat the reader. Read what is already in
            // the pipe under the same lock as the reader.
            drain(into: &state)
            return String(decoding: state.buffer, as: UTF8.self)
        }
    }

    func stop() {
        state.withLock { state in
            guard !state.isFinished else { return }
            var byte: UInt8 = 1
            _ = write(wake.write, &byte, 1)
        }
    }

    /// The reader thread: drains the pipe until its writers are gone or the tail is released.
    func run() {
        while true {
            var descriptors = [
                pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0),
                pollfd(fd: wake.read, events: Int16(POLLIN), revents: 0),
            ]
            guard poll(&descriptors, nfds_t(descriptors.count), -1) >= 0 else {
                if errno == EINTR || errno == EAGAIN { continue }
                break
            }
            if descriptors[1].revents != 0 { break }
            let isAtEnd = state.withLock { state in
                drain(into: &state)
                return state.isAtEnd
            }
            if isAtEnd { break }
        }
        state.withLock { state in
            state.isAtEnd = true
            state.isFinished = true
            _ = close(descriptor)
            _ = close(wake.read)
            _ = close(wake.write)
        }
    }

    private func drain(into state: inout State) {
        guard !state.isAtEnd else { return }
        var available: Int32 = 0
        #if canImport(Darwin)
        // Darwin's _IOR('f', 127, int) macro is not imported into Swift.
        let bytesAvailable: UInt = 0x4004_667F
        #else
        let bytesAvailable = UInt(FIONREAD)
        #endif
        guard ioctl(descriptor, bytesAvailable, &available) == 0 else { return }
        // Bound each drain to what was pending when it began, so a continuously writing agent
        // cannot keep the host busy indefinitely. One empty read distinguishes EOF from EAGAIN.
        var remaining = max(Int(available), 1)
        var bytes = [UInt8](repeating: 0, count: min(remaining, Self.limit))
        while remaining > 0 {
            let count = read(descriptor, &bytes, min(remaining, bytes.count))
            if count > 0 {
                state.buffer.append(contentsOf: bytes.prefix(count))
                if state.buffer.count > Self.limit {
                    state.buffer.removeFirst(state.buffer.count - Self.limit)
                }
                remaining -= count
            } else if count < 0, errno == EINTR {
                continue
            } else {
                if count == 0 || (errno != EAGAIN && errno != EWOULDBLOCK) {
                    state.isAtEnd = true
                }
                return
            }
        }
    }
}
