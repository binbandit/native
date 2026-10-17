import Dispatch
import Foundation
import NativeHostProtocol

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
    private let source: any DispatchSourceRead
    private let logger = HostLogger(category: "SocketServer")

    /// Listens at `path` and hands each verified connection to `accept`.
    init(path: String, verifier: (any PeerVerifier)?, accept: @escaping @Sendable (any ByteStream) -> Void) throws {
        let descriptor = try UnixSocket.listen(at: path)
        self.descriptor = descriptor
        let source = DispatchSource.makeReadSource(
            fileDescriptor: descriptor, queue: DispatchQueue(label: "Native.SocketServer"))
        self.source = source
        let logger = logger
        source.setEventHandler {
            // The listening socket is non-blocking: take every connection that's waiting.
            while true {
                let client = Self.acceptConnection(descriptor)
                guard client >= 0 else { return }
                var on: Int32 = 1
                setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
                do {
                    try verifier?.verify(socket: client)
                } catch {
                    logger.error("Turned a connection away: \(error.localizedDescription)")
                    _ = close(client)
                    continue
                }
                accept(ByteChannel.socket(client, label: "client-\(client)"))
            }
        }
        source.setCancelHandler {
            _ = close(descriptor)
        }
        source.resume()
    }

    func stop() {
        source.cancel()
    }

    private static func acceptConnection(_ descriptor: Int32) -> Int32 {
        accept(descriptor, nil, nil)
    }
}
