#if NATIVE_PAIRING_WIP
import Foundation
import NativeHostProtocol
import NativeLink

/// Why Add Host couldn't pair, each worded the one way errors are (`ErrorState`): what happened,
/// what Native did about it, what the user can do, and the one next step.
nonisolated enum AddHostFailure: Hashable, Sendable {
    /// What the user typed is neither a pairing link nor an SSH destination.
    case notALinkOrDestination
    /// A link from a newer Native.
    case newerLink
    /// The link ran out before pairing finished.
    case expired(host: String)
    /// SSH couldn't sign in without asking for a password or passphrase.
    case sshSignIn(destination: String)
    /// This Mac doesn't know (or no longer trusts) the other Mac's SSH host key.
    case sshHostKey(destination: String)
    case sshUnknownHost(destination: String)
    /// Nothing answered on the SSH port: Remote Login is off.
    case sshRefused(destination: String)
    case sshUnreachable(destination: String, detail: String)
    /// Its SSH waited for the sign-in to be approved in a browser (Tailscale SSH's check), and
    /// nobody did in time.
    case sshNotApproved(destination: String, page: URL)
    case sshFailed(destination: String, detail: String)
    case notInstalled(destination: String)
    /// Native is there, but from before `pair` existed. Its version, when the script could read it.
    case tooOld(destination: String, version: String?)
    case notAMac(destination: String)
    case hostNotRunning(host: String)
    case notAllowed(host: String)
    /// The two Natives speak different host protocols.
    case versionMismatch(host: String, theirs: PeerInfo, theirProtocol: Int)
    /// The link's host didn't answer at any of its addresses.
    case unreachable(host: String, addresses: String)
    /// Something at the link's address answered with another key.
    case wrongHost(host: String)
    /// The link was used already, or the pairing on the host ended.
    case linkSpent(host: String)
    /// Someone started another pairing on the host, which ends this one.
    case replaced(host: String)
    case tooManyAttempts(host: String)
    /// The host's user turned the pairing down (a link from its Pair iPhone sheet).
    case declined(host: String)
    case unexpected(String)

    /// What happened, in plain words.
    var title: String {
        switch self {
        case .notALinkOrDestination: "That isn't a pairing link or an SSH destination"
        case .newerLink: "This link comes from a newer Native"
        case .expired(let host): "The link for \(host) expired"
        case .sshSignIn(let destination): "SSH couldn't sign in to \(destination) without a password"
        case .sshHostKey(let destination): "SSH doesn't trust \(destination)'s host key"
        case .sshUnknownHost(let destination): "Couldn't find \(Self.machine(destination))"
        case .sshRefused(let destination): "\(Self.machine(destination)) isn't accepting SSH connections"
        case .sshUnreachable(let destination, _): "Couldn't reach \(Self.machine(destination)) over SSH"
        case .sshNotApproved(let destination, _): "The sign-in to \(Self.machine(destination)) wasn't approved"
        case .sshFailed(let destination, _): "SSH to \(destination) failed"
        case .notInstalled(let destination): "Native isn't installed on \(Self.machine(destination))"
        case .tooOld(let destination, let version):
            "Native\(version.map { " \($0)" } ?? "") on \(Self.machine(destination)) can't pair from another Mac"
        case .notAMac(let destination): "\(Self.machine(destination)) isn't a Mac"
        case .hostNotRunning(let host): "Native's background host isn't running on \(host)"
        case .notAllowed(let host): "\(host) doesn't allow paired devices"
        case .versionMismatch(let host, _, _): "\(host) runs a version of Native this Mac can't work with"
        case .unreachable(let host, _): "Couldn't reach \(host) to pair"
        case .wrongHost(let host): "Another machine answered for \(host)"
        case .linkSpent(let host): "The link for \(host) doesn't work anymore"
        case .replaced(let host): "Another pairing started on \(host)"
        case .tooManyAttempts(let host): "\(host) closed the link after wrong attempts"
        case .declined(let host): "\(host) declined"
        case .unexpected: "Pairing stopped unexpectedly"
        }
    }

    /// What Native already did about it.
    var recovery: String? {
        switch self {
        case .wrongHost: "Native stopped before sending anything, so nothing was shared with it."
        case .versionMismatch: "Native stopped before pairing."
        case .expired, .linkSpent, .replaced, .tooManyAttempts: "Nothing was paired."
        default: nil
        }
    }

    /// What the user can do.
    var suggestion: String {
        switch self {
        case .notALinkOrDestination:
            "Enter an SSH destination like me@mac-mini.local, or paste the link that “Native Host” pair printed."
        case .newerLink: "Update Native on this Mac, then paste the link again."
        case .expired: "Links last five minutes. Try again for a new one."
        case .sshSignIn(let destination):
            "Native uses your SSH keys and never types a password. Add this Mac's key to it (ssh-copy-id \(destination)) or load your key into ssh-agent, then try again."
        case .sshHostKey(let destination):
            "Connect once in Terminal (ssh \(destination)) to check and accept its key, then try again."
        case .sshUnknownHost:
            "Check the name, or use its IP address. Names ending in .local only work on the same network."
        case .sshRefused:
            "Turn on Remote Login on it (System Settings › General › Sharing), then try again."
        case .sshUnreachable:
            "Check that it's on and on a network this Mac can reach, like the same Wi-Fi or your tailnet."
        case .sshNotApproved(_, let page):
            "Its SSH asks you to approve each sign-in in a browser (\(page.absoluteString)). Try again, and approve the page Native shows while it waits."
        case .sshFailed: "Check that ssh works in Terminal, then try again."
        case .notInstalled:
            "Install Native in its Applications folder and open it once, so its background host starts. Then try again."
        case .tooOld: "Update Native on it to the same version as this Mac, then try again."
        case .notAMac: "Hosts are Macs for now."
        case .hostNotRunning(let host):
            "Open Native on \(host) once (its host keeps running after that), or turn on Settings › Background › Keep agents running when Native quits there. Then try again."
        case .notAllowed:
            "The organization that manages it turned paired devices off. Ask them to turn on the companion, then try again."
        case .versionMismatch(let host, let theirs, let theirProtocol):
            theirProtocol < HostProtocol.version
                ? "It has Native \(theirs.version). Update Native on \(host), then try again."
                : "It has Native \(theirs.version), newer than this Mac's. Update Native here, then try again."
        case .unreachable(_, let addresses):
            "Tried \(addresses). Check that both Macs are on the same network or tailnet, and that its firewall lets Native Host accept connections."
        case .wrongHost:
            "The address may belong to another machine now. Run pair on the host again for a link with its current addresses."
        case .linkSpent:
            "Each link pairs once, and closes when pair stops. Try again for a new one."
        case .replaced: "Finish or cancel the other pairing there, then try again."
        case .tooManyAttempts: "Try again for a new link, and use only the newest one."
        case .declined: "Ask whoever is at it to choose Pair, or try again."
        case .unexpected(let detail): detail
        }
    }

    /// The raw output behind Show Details.
    var details: String? {
        switch self {
        case .sshUnreachable(_, let detail), .sshFailed(_, let detail): detail.isEmpty ? nil : detail
        default: nil
        }
    }

    /// Whether running the same attempt again can help, rather than changing what was typed first.
    var isWorthRetrying: Bool {
        switch self {
        case .notALinkOrDestination, .newerLink, .notAMac, .sshUnknownHost: false
        default: true
        }
    }

    /// The machine in an SSH destination: `mac-mini.local` from `me@mac-mini.local`.
    static func machine(_ destination: String) -> String {
        String(destination.split(separator: "@").last ?? Substring(destination))
    }

    /// Why pair over SSH ended before printing a link.
    static func ssh(_ ending: LinkSSHPairing.Ending, destination: String) -> AddHostFailure {
        switch ending {
        case .ssh(.signIn, _): .sshSignIn(destination: destination)
        case .ssh(.hostKey, _): .sshHostKey(destination: destination)
        case .ssh(.unknownHost, _): .sshUnknownHost(destination: destination)
        case .ssh(.refused, _): .sshRefused(destination: destination)
        case .ssh(.unreachable, let detail): .sshUnreachable(destination: destination, detail: detail)
        case .ssh(.notApproved(let page), _): .sshNotApproved(destination: destination, page: page)
        case .ssh(.other, let detail), .failed(let detail): .sshFailed(destination: destination, detail: detail)
        case .notInstalled: .notInstalled(destination: destination)
        case .tooOld(let version): .tooOld(destination: destination, version: version)
        case .notAMac: .notAMac(destination: destination)
        case .ran: .unexpected("Native on \(machine(destination)) stopped without printing a pairing link.")
        }
    }

    /// What the host's pair command reported.
    static func pairCommand(_ failure: LinkPairCommandEvent.Failure?, message: String?, host: String) -> AddHostFailure
    {
        switch failure {
        case .hostNotRunning, .hostStopped: .hostNotRunning(host: host)
        case .notAllowed: .notAllowed(host: host)
        case .expired: .expired(host: host)
        case .replaced: .replaced(host: host)
        case .tooManyAttempts: .tooManyAttempts(host: host)
        case .cannotListen, .unknown, nil:
            .unexpected(message ?? "The pair command on \(host) stopped without saying why.")
        }
    }

    /// What pairing over the network threw. `tried` lists the addresses it tried.
    static func pairing(_ error: any Error, host: String, tried: String) -> AddHostFailure {
        guard let error = error as? LinkError else { return .unreachable(host: host, addresses: tried) }
        switch error {
        case .refused(.noPairingWindow): return .linkSpent(host: host)
        case .refused(.tooManyAttempts), .refused(.wrongCode): return .tooManyAttempts(host: host)
        case .refused(.busy): return .replaced(host: host)
        case .refused(.unsupportedVersion): return .tooOld(destination: host, version: nil)
        case .hostKeyMismatch: return .wrongHost(host: host)
        case .rejected: return .declined(host: host)
        case .confirmationExpired: return .expired(host: host)
        case .disabledByPolicy: return .notAllowed(host: host)
        case .timedOut, .closed: return .unreachable(host: host, addresses: tried)
        default: return .unexpected(error.localizedDescription)
        }
    }
}
#endif
