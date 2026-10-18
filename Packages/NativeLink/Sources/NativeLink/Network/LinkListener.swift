import Foundation
import Network

/// The gateway's TCP listener, advertised over Bonjour as `_native-link._tcp` with the host's key
/// fingerprint and id in its TXT record, so a device can tell its paired host from any other Native
/// on the network. Every accepted connection must still complete the Noise handshake before it can
/// say anything to the host.
final class LinkListener: Sendable {
    enum Event: Sendable {
        case ready(port: UInt16)
        case failed(String, addressInUse: Bool)
    }

    static let serviceType = "_native-link._tcp"

    private let listener: NWListener

    init(
        port: UInt16?, serviceName: String?, txtRecord: [String: String],
        events: @escaping @Sendable (Event) -> Void, connections: @escaping @Sendable (NetworkByteStream) -> Void
    ) throws {
        let queue = DispatchQueue(label: "Native.Link.listener")
        let listenPort = port.flatMap(NWEndpoint.Port.init(rawValue:)) ?? .any
        listener = try NWListener(using: NetworkByteStream.parameters, on: listenPort)
        if let serviceName {
            listener.service = NWListener.Service(
                name: serviceName, type: Self.serviceType, txtRecord: NWTXTRecord(txtRecord))
        }
        listener.stateUpdateHandler = { [listener] state in
            switch state {
            case .ready:
                events(.ready(port: listener.port?.rawValue ?? 0))
            case .failed(let error):
                let inUse = if case .posix(.EADDRINUSE) = error { true } else { false }
                events(.failed(describe(error), addressInUse: inUse))
                listener.cancel()
            default:
                break
            }
        }
        listener.newConnectionHandler = { connection in
            connections(NetworkByteStream(connection: connection, queue: queue))
        }
        listener.start(queue: queue)
    }

    func cancel() {
        listener.cancel()
    }
}
