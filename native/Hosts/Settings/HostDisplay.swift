import Foundation
import NativeHostProtocol

/// One device as Settings ▸ Hosts shows it: This Mac or a paired host, made from the app's hosts
/// (`AppHostsDirectory`) or from fixtures, so the page renders the same from either.
struct HostDisplay: Identifiable {
    let device: SessionDevice
    var name: String
    /// What the machine calls itself, when the user named it something else here.
    var machineName: String?
    var look: HostLook
    var state: HostDisplayState
    var machine = HostMachineSummary()
    var agents: [HostAgentDisplay] = []
    var sessions = HostSessionCounts()
    /// Where `ssh` reaches it from this Mac ("mac-mini.local", "you@10.0.0.4"), for signing in
    /// on it; nil for This Mac.
    var sshDestination: String?
    /// When it keeps itself awake, while that can be set from here; nil when it can't.
    var keepAwakeMode: KeepAwakeMode?

    var id: SessionDevice { device }

    var isThisMac: Bool {
        device == .thisMac
    }
}

/// A device's connection, with the words and tone each state gets on the Hosts page.
enum HostDisplayState: Hashable {
    case online
    case connecting
    /// The connection dropped and Native is reconnecting; a blip, not offline.
    case reconnecting(reason: String)
    /// Nothing answered for a while; Native keeps trying.
    case offline(reason: String, lastConnected: Date?)
    /// It speaks another version of Native's protocol; `message` says which side to update.
    case needsUpdate(message: String)
    /// The host ended the pairing (revoked, or it can't prove its key), so Native stopped trying.
    case pairingEnded(reason: String)

    /// The same state as the device picker and badges show it.
    var availability: SessionDeviceOption.Availability {
        switch self {
        case .online: .online
        case .connecting, .reconnecting: .connecting
        case .offline(let reason, _): .offline(reason: reason)
        case .needsUpdate(let message): .offline(reason: message)
        case .pairingEnded(let reason): .offline(reason: reason)
        }
    }

    var title: String {
        switch self {
        case .online: "Online"
        case .connecting: "Connecting…"
        case .reconnecting: "Reconnecting…"
        case .offline: "Offline"
        case .needsUpdate: "Needs update"
        case .pairingEnded: "Unpaired"
        }
    }

    var tone: Badge.Tone {
        switch self {
        case .online: .success
        case .connecting, .reconnecting: .neutral
        case .offline, .needsUpdate: .warning
        case .pairingEnded: .danger
        }
    }
}

/// What a device says about the machine it runs on. Every part is optional: hosts that don't
/// report one leave it out of the line.
struct HostMachineSummary: Hashable {
    /// "macOS 26.1", "Ubuntu 24.04".
    var system: String?
    /// Native's version on it, with its build: "1.4.2 (212)".
    var nativeVersion: String?
    var bootedAt: Date?
    /// The 1-minute load average.
    var loadAverage: Double?
    /// Whether it stays awake for its tasks: "Stays awake", "Awake while agents work", "May sleep".
    /// A host that sleeps stops its tasks, so this belongs in the line.
    var keepAwake: String?

    /// "macOS 26.1 · Native 1.4.2 (212) · Up 3d · Load 0.42 · Stays awake", or nil when nothing is
    /// known.
    func line(now: Date) -> String? {
        let parts = [
            system,
            nativeVersion.map { "Native \($0)" },
            bootedAt.map { "Up \(DSFormat.compactAge($0, now: now))" },
            loadAverage.map { "Load \($0.formatted(.number.precision(.fractionLength(2))))" },
            keepAwake,
        ]
        let known = parts.compactMap(\.self)
        return known.isEmpty ? nil : known.joined(separator: " · ")
    }
}

/// How many of the user's tasks a device holds, for the page and the removal confirmation.
struct HostSessionCounts: Hashable {
    var total = 0
    var working = 0

    /// "No tasks", "1 task", "3 tasks · 1 working".
    var line: String {
        let tasks =
            switch total {
            case 0: "No tasks"
            case 1: "1 task"
            default: "\(total) tasks"
            }
        return working > 0 ? "\(tasks) · \(working) working" : tasks
    }
}

/// One agent on a device: how it's running, whom it's signed in as, and the ways it offers.
struct HostAgentDisplay: Identifiable {
    let agent: AgentDefinition
    var status: AgentRuntimeStatus
    var needsSignIn = false
    var isSigningIn = false
    /// What the agent says it's signed in with ("ChatGPT Pro · you@example.com", "Not logged
    /// in"), when it says.
    var signInLabel: String?
    /// Whether it says it's signed in; nil when it doesn't say.
    var isSignedIn: Bool?
    var methods: [HostSignInMethod] = []
    /// The methods whose key the host keeps (by method id), so the sheet says "Key saved".
    var savedKeys: Set<String> = []
    /// The terminal command that signs it in (its manifest's, or a terminal-only method's), for
    /// signing in on a host over SSH.
    var terminalSignIn: String?
    /// How to install it, for a host that doesn't have it.
    var installCommand: String?
    var docs: URL?
    /// The page (and code) a sign-in waits on, while it does.
    var signInLink: HostSignInLink?

    var id: AgentDefinition.ID { agent.id }

    /// Whether Sign In makes sense: the agent offers a way.
    var canSignIn: Bool {
        !methods.isEmpty || terminalSignIn != nil
    }

    /// Whether it signs in with a key now, which a sign-in another way replaces.
    var usesAPIKey = false

    /// Whether to ask for a sign-in. What the agent says about itself wins: signing in again when
    /// it's signed in costs restarts (and two with Codex's device code). An agent that says
    /// nothing asks once it turns a request away.
    var wantsSignIn: Bool {
        isSignedIn.map { !$0 } ?? needsSignIn
    }
}
