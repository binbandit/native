import Foundation
import NativeLink
import NativePolicy
import Observation

/// Whether this client may reach remote hosts now, and the one way it does: connecting to a paired
/// host, browsing the local network for them, and pairing by link or over SSH. Each operation first
/// checks that remote hosts are turned on for the run (`-NativeRemoteHosts YES`, or that user
/// default) and that the organization allows them (`policy.remoteHosts.enabled`). The organization's
/// false wins over both.
///
/// The organization's answer is followed during the run: off stops this client's discovery,
/// connections and pairing at once (`RemoteHosts`, `AddHostModel`), and on again reconnects. A run
/// that began with them off stays off until the next launch, since the app wires hosts' workspaces
/// and git once, at launch (`RemoteHostsWiring`). This is only this client's outbound work: the
/// agents on a host keep running there, and the companion gateway that lets devices pair with this
/// Mac has its own policy (`policy.companion.enabled`).
struct RemoteHostsPolicy: Sendable {
    /// The app's: the feature as launched, and the organization's policy as `PolicyCenter.shared`
    /// follows it.
    static let app = RemoteHostsPolicy(center: .shared)

    let center: PolicyCenter
    /// Turned on for this run, and allowed by the organization when the run began.
    let isOnForRun: Bool
    private let reach: Reach

    init(center: PolicyCenter, isFeatureOn: Bool = RemoteHosts.isFeatureOn, reach: Reach = .network) {
        self.center = center
        self.reach = reach
        isOnForRun = isFeatureOn && center.policy.remoteHostsEnabled
    }

    /// Whether remote hosts are on now.
    var isEnabled: Bool {
        isOnForRun && center.policy.remoteHostsEnabled
    }

    /// `isEnabled` now, then again whenever the organization's policy changes.
    var changes: Observations<Bool, Never> {
        let center = center
        let isOnForRun = isOnForRun
        return Observations { @MainActor in isOnForRun && center.policy.remoteHostsEnabled }
    }

    /// Why remote hosts are off, in the words Add Host shows.
    var offReason: String {
        center.policy.remoteHostsEnabled
            ? "Remote hosts were off when Native opened. Quit and reopen Native, then try again."
            : "Your organization turned off remote hosts on this Mac. Nothing was paired."
    }

    /// Thrown by `pair` while remote hosts are off, and when they went off while it paired.
    struct TurnedOff: Error {}

    // MARK: - Reaching out

    /// Starts `host`'s connection, unless remote hosts are off. Returns whether it did.
    @discardableResult
    func connect(_ host: RemoteHost) -> Bool {
        guard isEnabled else { return false }
        reach.connect(host)
        return true
    }

    /// Browses the local network for paired hosts, unless remote hosts are off.
    func browse() -> (any RemoteHostBrowsing)? {
        isEnabled ? reach.browse() : nil
    }

    /// Pairs with the host of `invite` over the network. Throws `TurnedOff` without trying while
    /// remote hosts are off, and when they went off meanwhile, so nothing it made is kept.
    func pair(
        _ invite: PairingInvite, as device: LinkDeviceInfo, log: @escaping @Sendable (LinkLogEntry) -> Void,
        awaitingConfirmation: @escaping @Sendable (VerificationCode) -> Void
    ) async throws -> PairedHost {
        guard isEnabled else { throw TurnedOff() }
        let paired = try await reach.pair(invite, device, log, awaitingConfirmation)
        guard isEnabled else { throw TurnedOff() }
        return paired
    }

    /// Runs pair on `destination` over SSH, offering `grants`; nil while remote hosts are off.
    /// Ending the stream's iteration stops ssh.
    func pairOverSSH(
        _ destination: String, offering grants: LinkGrants, environment: [String: String]
    ) -> AsyncStream<LinkSSHPairing.Update>? {
        isEnabled ? reach.ssh(destination, grants, environment) : nil
    }

    /// The operations themselves: the app's reach the network and run ssh; checks record them.
    struct Reach: Sendable {
        typealias SSHUpdates = AsyncStream<LinkSSHPairing.Update>

        /// Connects to a paired host, and keeps reconnecting until it stops (`RemoteHost.start`).
        var connect: @MainActor (RemoteHost) -> Void
        var browse: @MainActor () -> any RemoteHostBrowsing
        /// Pairs with an invite's host, returning the pairing to keep.
        var pair:
            @MainActor (
                PairingInvite, LinkDeviceInfo, _ log: @escaping @Sendable (LinkLogEntry) -> Void,
                _ awaitingConfirmation: @escaping @Sendable (VerificationCode) -> Void
            ) async throws -> PairedHost
        var ssh: @MainActor (_ destination: String, _ grants: LinkGrants, _ environment: [String: String]) -> SSHUpdates

        static var network: Reach {
            Reach(
                connect: { $0.start() },
                browse: { LinkBrowser() },
                pair: { invite, device, log, awaitingConfirmation in
                    let (paired, channel) = try await LinkPairing.pair(
                        credential: .invite(invite), endpoints: LinkPairing.endpoints(for: invite, discovered: []),
                        device: device, installationSecret: RemoteHosts.installationSecret, log: log,
                        awaitingConfirmation: awaitingConfirmation)
                    // The hosts model connects on its own, as for every later launch.
                    channel.close()
                    return paired
                },
                ssh: { destination, grants, environment in
                    #if os(macOS)
                    LinkSSHPairing.pair(
                        destination: destination, grants: grants, appName: Bundle.main.bundleURL.lastPathComponent,
                        environment: environment, ssh: AddHostTesting.sshExecutable)
                    #else
                    AsyncStream { $0.finish() }
                    #endif
                })
        }
    }
}
