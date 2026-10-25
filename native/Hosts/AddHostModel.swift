import Foundation
import NativeHostProtocol
import NativeLink
import NativePolicy
import Observation

/// Add Host: pairs this Mac with a host that has no screen (a Mac mini in a closet), from the link
/// its `"Native Host" pair` printed, or by running that command over the user's own SSH and pairing
/// with what it prints. Either way the user sees what the pairing gives and chooses before it
/// happens, and the new host joins `RemoteHosts` (`docs/durability.md`, "Pairing a host without a
/// screen").
@Observable
final class AddHostModel {
    enum Phase: Equatable {
        /// Typing a destination or pasting a link.
        case entering
        /// Running pair on the destination over SSH.
        case reaching(destination: String)
        /// The link is read; the user chooses what to allow.
        case confirming(AddHostOffer)
        case pairing(AddHostOffer)
        /// Paired: the host's name and what this Mac may do there.
        case paired(name: String, grants: LinkGrants)
        case failed(AddHostFailure)
    }

    /// An SSH destination or a pairing link, as typed or pasted.
    var input = ""
    /// What this Mac asks for, within what the link offers.
    var requested = LinkGrants()
    private(set) var phase = Phase.entering
    /// The step pairing is on ("Trying 192.168.1.20:47118"), or what the host's screen should show.
    private(set) var progress: String?
    /// While reaching: the page the other Mac's SSH waits on until the sign-in is approved there.
    private(set) var approvalPage: URL?

    @ObservationIgnored private let register: (PairedHost) -> Void
    @ObservationIgnored private let environment: () async -> [String: String]
    /// Whether remote hosts are on, and the only way Add Host pairs.
    @ObservationIgnored private let policy: RemoteHostsPolicy
    @ObservationIgnored private var remote: Task<Void, Never>?
    @ObservationIgnored private var work: Task<Void, Never>?
    /// While an attempt runs: ends it as soon as remote hosts go off (`followPolicy`).
    @ObservationIgnored private var policyWatch: Task<Void, Never>?
    /// The SSH destination of the last attempt, for Try Again; nil after a pasted link.
    @ObservationIgnored private var lastDestination: String?

    /// What an owner's Mac asks for by default: tasks there need commands (git, diffs, terminals),
    /// and a host nobody sits at needs updating from somewhere. Plugins stay off, as for phones.
    static let defaultRequest = LinkGrants(manageHost: true, runCommands: true)
    /// What Add Host asks `pair` over SSH to offer; the confirmation then picks within it.
    static let sshOffer = LinkGrants(managePlugins: true, manageHost: true, runCommands: true)

    /// `register` keeps a new pairing and connects to it (`RemoteHosts.add`); `environment` is the
    /// login shell's, which carries the user's ssh-agent.
    init(
        register: @escaping (PairedHost) -> Void, environment: @escaping () async -> [String: String],
        input: String = "", phase: Phase = .entering, approvalPage: URL? = nil, policy: RemoteHostsPolicy = .app
    ) {
        self.register = register
        self.environment = environment
        self.policy = policy
        self.input = input
        self.phase = phase
        self.approvalPage = approvalPage
        if case .confirming(let offer) = phase { requested = Self.defaultRequest.intersection(offer.grants) }
    }

    // MARK: - What the user does

    /// Reads what was typed: a link goes straight to the confirmation, a destination over SSH.
    func submit() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        stop()
        lastDestination = nil
        guard policy.isEnabled else { return fail(turnedOff) }
        if text.hasPrefix("\(PairingInvite.scheme):") {
            do {
                offer(AddHostOffer(invite: try PairingInvite(url: text)))
            } catch PairingInvite.ParseError.newerVersion {
                fail(.newerLink)
            } catch {
                fail(.notALinkOrDestination)
            }
        } else if canUseSSH, LinkSSHPairing.isDestination(text) {
            reach(text)
        } else {
            fail(.notALinkOrDestination)
        }
    }

    /// Pairs with what's on the confirmation.
    func pair() {
        guard case .confirming(let offer) = phase else { return }
        guard !offer.invite.isExpired(at: .now) else { return fail(.expired(host: offer.hostName)) }
        guard policy.isEnabled else { return fail(turnedOff) }
        phase = .pairing(offer)
        progress = nil
        var device = RemoteHosts.deviceInfo
        device.requestedGrants = requested.intersection(offer.grants)
        let invite = offer.invite
        let tried = invite.addresses.filter { $0.port != nil }.map(\.label).joined(separator: ", ")
        work?.cancel()
        followPolicy()
        work = Task { [weak self, policy] in
            do {
                let paired = try await policy.pair(
                    invite, as: device, log: { entry in Task { @MainActor in self?.progress = entry.message } },
                    awaitingConfirmation: { code in
                        Task { @MainActor in
                            self?.progress = "Choose Pair on \(offer.hostName), where it shows \(code.description)."
                        }
                    })
                // Stopped meanwhile (Edit, the sheet closing, remote hosts going off): nothing is kept.
                guard !Task.isCancelled else { return }
                self?.paired(paired, offer: offer)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self else { return }
                fail(
                    error is RemoteHostsPolicy.TurnedOff
                        ? turnedOff : .pairing(error, host: offer.hostName, tried: tried.isEmpty ? "no address" : tried)
                )
            }
        }
    }

    /// Runs the same attempt again: a new link over SSH, or back to the field to paste a new one.
    func retry() {
        stop()
        guard case .failed(let failure) = phase, failure.isWorthRetrying, let destination = lastDestination else {
            phase = .entering
            return
        }
        reach(destination)
    }

    /// Whether Try Again can run the same attempt: over SSH, a new link comes with it.
    var canTryAgain: Bool {
        guard case .failed(let failure) = phase else { return false }
        return failure.isWorthRetrying && lastDestination != nil
    }

    /// Whether the last attempt ran pair over SSH, rather than using a pasted link.
    var wasOverSSH: Bool {
        lastDestination != nil
    }

    /// Back to an empty field, for a new link.
    func startOver() {
        input = ""
        edit()
    }

    /// Back to the field, keeping what was typed.
    func edit() {
        stop()
        phase = .entering
    }

    /// Stops whatever runs: ssh ends, which closes the host's pairing window.
    func stop() {
        remote?.cancel()
        remote = nil
        work?.cancel()
        work = nil
        policyWatch?.cancel()
        policyWatch = nil
    }

    // MARK: - Steps

    private var canUseSSH: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    private func offer(_ offer: AddHostOffer) {
        guard !offer.invite.isExpired(at: .now) else { return fail(.expired(host: offer.hostName)) }
        var offer = offer
        if RemoteHostsTesting.isLoopbackOnly {
            // Only what will be tried, so a stand-in host on this Mac shows no real addresses either.
            offer.invite.addresses = offer.invite.addresses.filter { $0.kind == .loopback }
        }
        requested = Self.defaultRequest.intersection(offer.grants)
        phase = .confirming(offer)
        // A pasted link has nobody to say it expired; an SSH one hears it from pair.
        guard offer.sshDestination == nil else { return }
        work?.cancel()
        work = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(offer.invite.expiresAt.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled, let self, case .confirming = self.phase else { return }
            self.fail(.expired(host: offer.hostName))
        }
    }

    private func reach(_ destination: String) {
        #if os(macOS)
        stop()
        lastDestination = destination
        approvalPage = nil
        guard policy.isEnabled else { return fail(turnedOff) }
        phase = .reaching(destination: destination)
        followPolicy()
        remote = Task { [weak self, environment, policy] in
            let environment = await environment()
            // Off meanwhile: the policy watch says so.
            guard !Task.isCancelled,
                let updates = policy.pairOverSSH(destination, offering: Self.sshOffer, environment: environment)
            else { return }
            for await update in updates {
                self?.receive(update, from: destination)
            }
        }
        #endif
    }

    /// Ends the attempt under way as soon as remote hosts go off (the organization's policy): ssh
    /// stops, which closes the host's pairing window, and pairing stops, keeping nothing it finishes.
    private func followPolicy() {
        guard policyWatch == nil else { return }
        policyWatch = Task { [weak self, policy] in
            for await isEnabled in policy.changes where !isEnabled {
                self?.policyTurnedOff()
                return
            }
        }
    }

    private func policyTurnedOff() {
        switch phase {
        case .reaching, .confirming, .pairing: fail(turnedOff)
        case .entering, .paired, .failed: stop()
        }
    }

    private var turnedOff: AddHostFailure {
        policy.center.policy.remoteHostsEnabled
            ? .unexpected(policy.offReason)
            : .organizationTurnedOff(name: policy.center.policy.organizationName)
    }

    #if os(macOS)
    private func receive(_ update: LinkSSHPairing.Update, from destination: String) {
        let host = AddHostFailure.machine(destination)
        switch update {
        case .needsApproval(let page):
            guard case .reaching = phase else { return }
            approvalPage = page
        case .event(let event) where event.event == .invite:
            guard case .reaching = phase else { return }
            let invite: PairingInvite
            do {
                invite = try PairingInvite(url: event.link ?? "")
            } catch PairingInvite.ParseError.newerVersion {
                return fail(.newerLink)
            } catch {
                return fail(.unexpected("Native on \(host) printed a pairing link this Mac can't read."))
            }
            if let theirs = event.protocolVersion, theirs != HostProtocol.version, let build = event.host {
                return fail(.versionMismatch(host: invite.hostName, theirs: build, theirProtocol: theirs))
            }
            offer(AddHostOffer(invite: invite, sshDestination: destination, hostBuild: event.host))
        case .event(let event) where event.event == .failed:
            switch phase {
            case .reaching, .confirming:
                fail(.pairCommand(event.failure, message: event.message, host: offerHost ?? host))
            case .entering, .pairing, .paired, .failed:
                // While pairing, the attempt itself reports what went wrong.
                break
            }
        case .event:
            break
        case .ended(let ending):
            switch phase {
            case .reaching: fail(.ssh(ending, destination: destination))
            // The window on the host closed with the command, so the link can't pair anymore.
            case .confirming(let offer): fail(.linkSpent(host: offer.hostName))
            case .entering, .pairing, .paired, .failed: break
            }
        }
    }
    #endif

    private var offerHost: String? {
        switch phase {
        case .confirming(let offer), .pairing(let offer): offer.hostName
        default: nil
        }
    }

    private func paired(_ paired: PairedHost, offer: AddHostOffer) {
        var paired = paired
        paired.sshDestination = offer.sshDestination
        register(paired)
        phase = .paired(name: paired.displayName, grants: paired.grants)
        progress = nil
    }

    private func fail(_ failure: AddHostFailure) {
        // Nothing more will come of the remote command; ending it closes the host's window.
        stop()
        phase = .failed(failure)
        progress = nil
    }
}

/// A pairing link read and ready to confirm: who it pairs with and what it would give.
struct AddHostOffer: Equatable {
    var invite: PairingInvite
    /// Set when Add Host ran pair over SSH.
    var sshDestination: String?
    /// The Native that printed it, when known (over SSH).
    var hostBuild: PeerInfo?

    var hostName: String { invite.hostName }

    /// The most the link gives: what pair was asked for, or nothing beyond tasks for an older link.
    var grants: LinkGrants { invite.grants ?? .standard }
}
