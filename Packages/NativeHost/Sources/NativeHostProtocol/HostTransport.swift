import Foundation

/// How a client reaches a host. Every transport carries the same newline-delimited JSON-RPC, so the
/// protocol, the client and the host don't change with the network path: a local socket today, an
/// SSH bridge to another machine next (`ssh <machine> native-host attach`, using the user's own keys),
/// and WebSocket with TLS for cloud hosts later.
public protocol HostTransport: Sendable {
    /// What people see while connecting ("This Mac", "mini over SSH").
    var displayName: String { get }
    func connect() async throws -> any ByteStream
}

/// The host on this machine, through its Unix socket.
public struct LocalSocketTransport: HostTransport {
    public let location: HostLocation

    public init(location: HostLocation) {
        self.location = location
    }

    public var displayName: String { "This Mac" }

    public func connect() async throws -> any ByteStream {
        ByteChannel.socket(try UnixSocket.connect(to: location.socketPath), label: "client")
    }
}
