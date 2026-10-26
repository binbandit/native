import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Unix domain sockets, the host's local transport. Paths are limited to 103 bytes by `sockaddr_un`.
public enum UnixSocket {
    public enum Failure: Error, LocalizedError {
        case pathTooLong(String)
        case nonSocketPath(String)
        case system(String, errno: Int32)

        public var errorDescription: String? {
            switch self {
            case .pathTooLong(let path):
                "The socket path is too long for the system (\(path.utf8.count) bytes): \(path)"
            case .nonSocketPath(let path):
                "Refusing to replace a non-socket entry at \(path). Inspect it and move it aside before starting the host."
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
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connectSocket(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let code = errno
            closeDescriptor(descriptor)
            throw Failure.system("connect", errno: code)
        }
        return descriptor
    }

    /// Listens at `path`, replacing an existing socket but refusing other filesystem entries.
    /// Only the owner can connect: the socket file is made readable and writable by the user alone.
    public static func listen(at path: String, backlog: Int32 = 16) throws -> Int32 {
        var address = try makeAddress(path)
        try removeExistingSocket(at: path)
        let descriptor = try makeSocket()
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listenSocket(descriptor, backlog) == 0 else {
            let code = errno
            closeDescriptor(descriptor)
            throw Failure.system("listen", errno: code)
        }
        // Accepting happens from a dispatch source, which must never block.
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        return descriptor
    }

    private static func removeExistingSocket(at path: String) throws {
        var entry = stat()
        // Inspect the entry itself so even a symlink to a socket is preserved.
        guard lstat(path, &entry) == 0 else {
            let code = errno
            if code == ENOENT { return }
            throw Failure.system("lstat \(path)", errno: code)
        }
        guard entry.st_mode & mode_t(S_IFMT) == mode_t(S_IFSOCK) else {
            throw Failure.nonSocketPath(path)
        }
        guard unlink(path) == 0 else {
            throw Failure.system("unlink \(path)", errno: errno)
        }
    }

    /// A pair of connected sockets, for tests and in-process transports.
    public static func pair() throws -> (Int32, Int32) {
        var descriptors: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, streamType, 0, &descriptors) == 0 else {
            throw Failure.system("socketpair", errno: errno)
        }
        for descriptor in descriptors {
            _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
            survivePeerVanishing(descriptor)
        }
        return (descriptors[0], descriptors[1])
    }

    private static func makeSocket() throws -> Int32 {
        let descriptor = socket(AF_UNIX, streamType, 0)
        guard descriptor >= 0 else { throw Failure.system("socket", errno: errno) }
        // No process we start inherits the connection and holds it open.
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        survivePeerVanishing(descriptor)
        return descriptor
    }

    /// A peer that vanished must surface as a write error, not kill the process.
    private static func survivePeerVanishing(_ descriptor: Int32) {
        #if canImport(Darwin)
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        #else
        // There's no such socket option here, and `ByteChannel` writes with write(2), which can't pass
        // MSG_NOSIGNAL, so the process ignores SIGPIPE instead (native-host does from its first line).
        signal(SIGPIPE, SIG_IGN)
        #endif
    }

    /// `SOCK_STREAM`, which Glibc declares as an enum rather than a number.
    private static var streamType: Int32 {
        #if canImport(Glibc)
        Int32(SOCK_STREAM.rawValue)
        #else
        SOCK_STREAM
        #endif
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
        #if canImport(Darwin)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif
        return address
    }
}

// The C functions, under names the enum's own methods don't shadow.
private func connectSocket(_ descriptor: Int32, _ address: UnsafePointer<sockaddr>, _ length: socklen_t) -> Int32 {
    connect(descriptor, address, length)
}

private func listenSocket(_ descriptor: Int32, _ backlog: Int32) -> Int32 {
    listen(descriptor, backlog)
}
