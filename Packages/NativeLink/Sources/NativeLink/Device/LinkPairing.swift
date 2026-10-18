import Foundation
import NativeHostProtocol
import Network

/// Pairing from the device's side, over the network: finds the host, runs the pairing handshake
/// with a fresh key for this host alone, and returns what to keep and the live channel.
public enum LinkPairing {
    /// Where to try: an invite's own addresses (and its Bonjour service, if the network shows it),
    /// or the host the person picked from the ones Bonjour found.
    public static func endpoints(for invite: PairingInvite, discovered: [DiscoveredHost]) -> [(NWEndpoint, String)] {
        let fingerprint = invite.hostKey.fingerprint
        var result = discovered.filter { $0.fingerprint == fingerprint }.map { ($0.endpoint, "\($0.name) (Bonjour)") }
        for address in invite.addresses {
            guard let port = address.port, let nwPort = NWEndpoint.Port(rawValue: port),
                [.lan, .tailnet, .loopback].contains(address.kind)
            else { continue }
            result.append((.hostPort(host: NWEndpoint.Host(address.host), port: nwPort), address.label))
        }
        return result
    }

    public static func pair(
        credential: LinkInitiator.Credential, endpoints: [(NWEndpoint, String)], device: LinkDeviceInfo,
        log: @escaping @Sendable (LinkLogEntry) -> Void,
        awaitingConfirmation: @escaping @Sendable (VerificationCode) -> Void
    ) async throws -> (PairedHost, SecureChannel) {
        let identity = LinkIdentity()
        var lastError: any Error = LinkError.timedOut
        for (endpoint, label) in endpoints {
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
            log(LinkLogEntry(.info, "Connected to \(label); proving the code"))
            // Once a host answered, its verdict stands: another address reaches the same host.
            let (channel, result) = try await LinkInitiator.pair(
                over: raw, identity: identity, credential: credential, device: device,
                awaitingConfirmation: awaitingConfirmation)
            log(LinkLogEntry(.success, "Paired with \(result.hostName)"))
            return (PairedHost(result: result, identity: identity), channel)
        }
        throw lastError
    }
}
