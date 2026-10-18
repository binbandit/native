import Foundation
import NativeHostProtocol
import Network
import Synchronization

/// How `NativeHostClient` reaches a paired host: the Bonjour service with the host's fingerprint
/// if the network shows one, then each address the host gave when pairing, each with the mutually
/// authenticated handshake. Every step goes to `log`, for the connection log the phone shows.
public struct PairedHostTransport: HostTransport {
    public let host: PairedHost
    public let device: LinkDeviceInfo
    private let discovered: @Sendable () -> [DiscoveredHost]
    private let log: @Sendable (LinkLogEntry) -> Void

    public init(
        host: PairedHost, device: LinkDeviceInfo, discovered: @escaping @Sendable () -> [DiscoveredHost] = { [] },
        log: @escaping @Sendable (LinkLogEntry) -> Void = { _ in }
    ) {
        self.host = host
        self.device = device
        self.discovered = discovered
        self.log = log
    }

    public var displayName: String { host.displayName }

    /// Bonjour first (it's the current address), then the saved ones in the order the host gave.
    public var endpoints: [(NWEndpoint, String)] {
        let fingerprint = host.hostKey.fingerprint
        var result = discovered().filter { $0.fingerprint == fingerprint }.map { ($0.endpoint, "\($0.name) (Bonjour)") }
        for address in host.addresses {
            guard let port = address.port, let nwPort = NWEndpoint.Port(rawValue: port) else { continue }
            switch address.kind {
            case .lan, .tailnet, .loopback:
                result.append((.hostPort(host: NWEndpoint.Host(address.host), port: nwPort), address.label))
            case .bonjour, .relay, .unknown:
                continue
            }
        }
        return result
    }

    public func connect() async throws -> any ByteStream {
        let identity = try host.identity()
        let candidates = endpoints
        guard !candidates.isEmpty else {
            log(LinkLogEntry(.failure, "No address to try: \(host.displayName) isn't on this network and saved no other address."))
            throw LinkError.timedOut
        }
        var lastError: any Error = LinkError.timedOut
        for (endpoint, label) in candidates {
            try Task.checkCancellation()
            log(LinkLogEntry(.attempt, "Trying \(label)"))
            let raw: NetworkByteStream
            do {
                raw = try await NetworkByteStream.connect(to: endpoint, timeout: .seconds(4))
            } catch {
                log(LinkLogEntry(.failure, "\(label): \(error.localizedDescription)"))
                lastError = error
                continue
            }
            do {
                let channel = try await LinkInitiator.connect(
                    over: raw, identity: identity, hostKey: host.hostKey, device: device)
                log(LinkLogEntry(.success, "Connected over \(label), end-to-end encrypted"))
                return channel
            } catch let error as LinkError where error.endsPairing || error == .hostKeyMismatch {
                // Another address won't change the host's answer.
                log(LinkLogEntry(.failure, error.localizedDescription))
                throw error
            } catch {
                log(LinkLogEntry(.failure, "\(label): \(error.localizedDescription)"))
                lastError = error
            }
        }
        throw lastError
    }
}

/// One line of a connection log.
public struct LinkLogEntry: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case attempt, success, failure, info
    }

    public let id = UUID()
    public let date: Date
    public let kind: Kind
    public let message: String

    public init(_ kind: Kind, _ message: String, date: Date = .now) {
        self.kind = kind
        self.message = message
        self.date = date
    }
}
