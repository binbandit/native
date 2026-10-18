import Foundation
import NativeLink
import Network
import Observation

/// Adding a host: connecting with the scanned link or typed code, waiting while the Mac's user
/// confirms (both screens show the same six digits), then keeping the pairing. Every step goes to
/// a pairing log, shown under any failure.
@Observable
final class PairingFlow {
    enum Step: Equatable {
        case idle
        case connecting(String)
        case confirming(hostName: String, VerificationCode)
        case paired(PairedHost)
        case failed(String)
    }

    private(set) var step = Step.idle
    private(set) var log: [LinkLogEntry] = []
    @ObservationIgnored private var task: Task<Void, Never>?

    func pair(invite: PairingInvite, discovered: [DiscoveredHost], store: CompanionStore) {
        guard !invite.isExpired(at: .now) else {
            step = .failed("This code expired. On \(invite.hostName), make a new one in Settings › Paired Devices.")
            return
        }
        run(
            hostName: invite.hostName, credential: .invite(invite),
            endpoints: LinkPairing.endpoints(for: invite, discovered: discovered), store: store)
    }

    func pair(code: PairingCode, with host: DiscoveredHost, store: CompanionStore) {
        run(
            hostName: host.name, credential: .code(code), endpoints: [(host.endpoint, "\(host.name) (Bonjour)")],
            store: store)
    }

    func cancel() {
        task?.cancel()
        task = nil
        step = .idle
    }

    func reset() {
        cancel()
        log = []
    }

    private func run(
        hostName: String, credential: LinkInitiator.Credential, endpoints: [(NWEndpoint, String)], store: CompanionStore
    ) {
        task?.cancel()
        log = []
        step = .connecting(hostName)
        task = Task { [weak self] in
            do {
                let (host, channel) = try await LinkPairing.pair(
                    credential: credential, endpoints: endpoints, device: CompanionDevice.info,
                    installationSecret: CompanionDevice.installationSecret,
                    log: { entry in Task { @MainActor in self?.log.append(entry) } },
                    awaitingConfirmation: { code in
                        Task { @MainActor in self?.step = .confirming(hostName: hostName, code) }
                    })
                // The host's connection opens its own channel; this one only carried the pairing.
                channel.close()
                store.add(host)
                self?.step = .paired(host)
            } catch is CancellationError {
                self?.step = .idle
            } catch {
                self?.log.append(LinkLogEntry(.failure, error.localizedDescription))
                self?.step = .failed(error.localizedDescription)
            }
        }
    }
}
