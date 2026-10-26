import Dispatch
import Foundation
import NativeHostProtocol
import Synchronization

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Checks who is on the other end of an accepted connection before it may talk to the host.
public protocol PeerVerifier: Sendable {
    /// Throws to turn the connection away.
    func verify(socket descriptor: Int32) throws
}

/// Accepts clients on the host's Unix socket.
final class SocketServer: Sendable {
    private let descriptor: Int32
    // Linux's DispatchSourceRead lacks Sendable; keep access inside the lock after setup.
    private let source: Mutex<any DispatchSourceRead>
    private let logger = HostLogger(category: "SocketServer")

    /// Listens at `path` and hands each verified connection to `accept`.
    init(
        path: String, verifier: (any PeerVerifier)?,
        accept: @escaping @Sendable (any ByteStream, HostClientIdentity) -> Void
    ) throws {
        let descriptor = try UnixSocket.listen(at: path)
        self.descriptor = descriptor
        let source = DispatchSource.makeReadSource(
            fileDescriptor: descriptor, queue: DispatchQueue(label: "Native.SocketServer"))
        let logger = logger
        source.setEventHandler {
            // The listening socket is non-blocking: take every connection that's waiting.
            while true {
                let client = Self.acceptConnection(descriptor)
                guard client >= 0 else { return }
                // Elsewhere, listening already set the process to ignore SIGPIPE (`UnixSocket`).
                #if canImport(Darwin)
                var on: Int32 = 1
                setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
                #endif
                let identity: HostClientIdentity
                do {
                    try verifier?.verify(socket: client)
                    identity = try Self.localIdentity(client)
                } catch {
                    logger.error("Turned a connection away: \(error.localizedDescription)")
                    _ = close(client)
                    continue
                }
                accept(ByteChannel.socket(client, label: "client-\(client)"), identity)
            }
        }
        source.setCancelHandler {
            _ = close(descriptor)
        }
        source.resume()
        self.source = Mutex(source)
    }

    func stop() {
        source.withLock { $0.cancel() }
    }

    /// The kernel, rather than the initialize message, identifies the account on this socket.
    private static func localIdentity(_ descriptor: Int32) throws -> HostClientIdentity {
        let uid: UInt32
        #if canImport(Darwin)
        var peerUID: uid_t = 0
        var peerGID: gid_t = 0
        guard getpeereid(descriptor, &peerUID, &peerGID) == 0 else { throw IdentityFailure.unavailable }
        uid = UInt32(peerUID)
        #else
        // Linux SO_PEERCRED is pid_t, uid_t, gid_t (three 32-bit fields).
        var credentials = [UInt32](repeating: 0, count: 3)
        var size = socklen_t(3 * MemoryLayout<UInt32>.size)
        let result = credentials.withUnsafeMutableBytes {
            getsockopt(descriptor, SOL_SOCKET, SO_PEERCRED, $0.baseAddress, &size)
        }
        guard result == 0, size == 3 * MemoryLayout<UInt32>.size else { throw IdentityFailure.unavailable }
        uid = credentials[1]
        #endif
        guard uid == UInt32(getuid()) else { throw IdentityFailure.otherAccount }
        return .localPeer(uid: uid)
    }

    private enum IdentityFailure: Error {
        case unavailable, otherAccount
    }

    private static func acceptConnection(_ descriptor: Int32) -> Int32 {
        accept(descriptor, nil, nil)
    }
}
