import Darwin
import Foundation

/// Unix domain sockets, the host's local transport. Paths are limited to 103 bytes by `sockaddr_un`.
public enum UnixSocket {
    public enum Failure: Error, LocalizedError {
        case pathTooLong(String)
        case system(String, errno: Int32)

        public var errorDescription: String? {
            switch self {
            case .pathTooLong(let path): "The socket path is too long for the system (\(path.utf8.count) bytes): \(path)"
            case .system(let call, let code): "\(call) failed: \(String(cString: strerror(code)))"
            }
        }

        /// Nobody is listening at the path (yet): the host isn't running, or is still starting.
        public var isNotListening: Bool {
            if case .system(_, let code) = self { code == ENOENT || code == ECONNREFUSED } else { false }
        }
    }

    /// Connects to a listening socket, returning the connected descriptor.
    public static func connect(to path: String) throws -> Int32 {
        var address = try makeAddress(path)
        let descriptor = try makeSocket()
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw Failure.system("connect", errno: code)
        }
        return descriptor
    }

    /// Listens at `path`, replacing whatever stale socket file is there. Only the owner can connect:
    /// the socket file is made readable and writable by the user alone.
    public static func listen(at path: String, backlog: Int32 = 16) throws -> Int32 {
        var address = try makeAddress(path)
        let descriptor = try makeSocket()
        unlink(path)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, Darwin.listen(descriptor, backlog) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw Failure.system("listen", errno: code)
        }
        // Accepting happens from a dispatch source, which must never block.
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        return descriptor
    }

    /// A pair of connected sockets, for tests and in-process transports.
    public static func pair() throws -> (Int32, Int32) {
        var descriptors: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else {
            throw Failure.system("socketpair", errno: errno)
        }
        for descriptor in descriptors {
            var on: Int32 = 1
            setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        }
        return (descriptors[0], descriptors[1])
    }

    private static func makeSocket() throws -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw Failure.system("socket", errno: errno) }
        // A peer that vanished must surface as a write error, not kill the process.
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        return descriptor
    }

    private static func makeAddress(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { throw Failure.pathTooLong(path) }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }
}
