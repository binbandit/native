import Dispatch
import Foundation
import Synchronization

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// The last few KB of an agent's stderr, for explaining why it failed.
final class StderrTail: Sendable {
    private static let limit = 16 * 1024
    private let input: FileHandle?
    private let buffer = Mutex(Data())

    init() {
        input = nil
    }

    /// Takes ownership of the read end. Snapshots must not wait for an agent or a descendant
    /// still holding stderr open, even when it has no more output to give us.
    init(reading input: FileHandle) throws {
        let descriptor = input.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        self.input = input
        input.readabilityHandler = { [weak self] _ in
            guard let self else { return }
            buffer.withLock { drain(into: &$0) }
        }
    }

    deinit {
        input?.readabilityHandler = nil
        if let input {
            // The callback can release the last tail reference. Corelibs FileHandle.close()
            // synchronizes with that callback's queue, so it must run on another queue.
            DispatchQueue.global(qos: .utility).async { try? input.close() }
        }
    }

    var text: String {
        buffer.withLock {
            // stdout closing and initialize failing can both beat the stderr callback. Read
            // what is already in the pipe under the same lock as the background reader.
            drain(into: &$0)
            return String(decoding: $0, as: UTF8.self)
        }
    }

    private func drain(into buffer: inout Data) {
        guard let input else { return }
        let descriptor = input.fileDescriptor
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
                buffer.append(contentsOf: bytes.prefix(count))
                if buffer.count > Self.limit {
                    buffer.removeFirst(buffer.count - Self.limit)
                }
                remaining -= count
            } else if count < 0, errno == EINTR {
                continue
            } else {
                if count == 0 || (errno != EAGAIN && errno != EWOULDBLOCK) {
                    input.readabilityHandler = nil
                }
                return
            }
        }
    }
}
