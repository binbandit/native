import ACP
import Foundation
import NativeHostProtocol

/// What this machine's organization lets its host do, decided on the host itself
/// (docs/enterprise/host-policy.md). A `HostPolicySource` loads it before the host recovers,
/// launches, listens or updates anything, and again whenever it changes, with or without an app
/// attached. Clients narrow it with their grants; nothing a client sends widens it.
public struct HostPolicy: Equatable, Sendable {
    public enum Mode: String, Equatable, Sendable {
        /// No organization restrictions beyond its ordinary settings: what the host has always done.
        case ordinary
        /// A restricted deployment: only the capabilities qualified to run restricted.
        case restricted
        /// The managed policy is missing, unreadable or invalid where it must be valid: nothing with
        /// side effects until it can be read again.
        case blocked
    }

    public let mode: Mode
    /// What the host may do now.
    public let capabilities: Set<HostCapability>
    /// The agents, by id, that `agents` covers; nil covers every agent (`policy.agents.allowed`).
    public let allowedAgents: Set<String>?
    /// Why the host is restricted or blocked, for the people using it. Never holds policy values.
    public let reason: String?

    /// A restricted policy keeps only `HostCapability.qualifiedWhenRestricted`, and a blocked one
    /// keeps nothing, whatever `capabilities` asks for.
    public init(
        mode: Mode, capabilities: Set<HostCapability>, allowedAgents: Set<String>? = nil, reason: String? = nil
    ) {
        self.mode = mode
        self.allowedAgents = allowedAgents
        self.reason = reason
        self.capabilities =
            switch mode {
            case .ordinary: capabilities
            case .restricted: capabilities.intersection(HostCapability.qualifiedWhenRestricted)
            case .blocked: []
            }
    }

    /// No managed policy: everything, as before host policy existed.
    public static let unrestricted = HostPolicy(mode: .ordinary, capabilities: Set(HostCapability.allCases))

    public static func blocked(_ reason: String) -> HostPolicy {
        HostPolicy(mode: .blocked, capabilities: [], reason: reason)
    }

    public func allows(_ capability: HostCapability) -> Bool {
        capabilities.contains(capability)
    }

    /// Whether the agent with this id may run here: agents at all, and this one.
    public func allows(agent id: String) -> Bool {
        allows(.agents) && allowedAgents?.contains(id) != false
    }
}

/// Everything a host does that an organization may need to stop: each starts processes, reads the
/// user's shell, listens, reaches the network or hands data to another device.
public enum HostCapability: String, CaseIterable, Sendable {
    /// Start agent processes: sessions, prompts, recovery, sign-in and tasks agents hand each other.
    case agents
    /// Read the user's login-shell environment, which runs their shell's startup files.
    case loginShell
    /// Run clients' commands (`_native/exec/*`).
    case commands
    /// Read files and list projects for clients (`_native/fs/*`, `_native/projects/*`).
    case files
    /// Turn the host's plugins on or off.
    case plugins
    /// Serve Native's tools to agents on a loopback port.
    case agentTools
    /// Listen for, advertise to and pair devices (the paired-device gateway).
    case companion
    /// Check for, download and install updates of this host.
    case updates
    /// The doctor's platform checks, which run tools such as `gh` and read the login shell.
    case diagnostics

    /// What a restricted host can do at all. The others have no qualified restricted path yet
    /// (docs/enterprise/host-policy.md, "Not available in restricted mode"), so they stay off in
    /// restricted mode whatever its policy says.
    public static let qualifiedWhenRestricted: Set<HostCapability> = [.companion]

    /// Finishes "Your organization's policy doesn't allow this host to …".
    var action: String {
        switch self {
        case .agents: "start agents"
        case .loginShell: "read your login shell's environment"
        case .commands: "run commands"
        case .files: "read files in its projects"
        case .plugins: "turn plugins on or off"
        case .agentTools: "serve Native's tools to agents"
        case .companion: "pair or connect devices"
        case .updates: "update itself"
        case .diagnostics: "run the doctor's checks"
        }
    }
}

/// Where a host's policy comes from: the machine's managed preferences on a Mac
/// (`NativeHostMac.MacHostPolicySource`), a deployment file on Linux (`LinuxHostPolicySource`).
/// Read by the host itself, never received from a client.
public protocol HostPolicySource: Sendable {
    /// The policy now. A source that can't read or validate what it must returns a blocked policy,
    /// never a permissive one, and never the last one it read.
    func current() -> HostPolicy
}

/// One policy that never changes: tests, and hosts no organization manages.
public struct FixedHostPolicySource: HostPolicySource {
    let policy: HostPolicy

    public init(_ policy: HostPolicy) {
        self.policy = policy
    }

    public func current() -> HostPolicy { policy }
}

/// Linux has no managed preferences, and no supported managed source yet. An administrator who
/// places a deployment file there asks for managed policy, which the host can't honor, so it
/// blocks rather than run unrestricted. Without the file, the host is unmanaged, as before.
public struct LinuxHostPolicySource: HostPolicySource {
    /// Root-owned in a real deployment; any process may only block its own host by creating it.
    public static let deploymentFile = URL(filePath: "/etc/native/host-policy")

    let file: URL

    public init(file: URL = LinuxHostPolicySource.deploymentFile) {
        self.file = file
    }

    public func current() -> HostPolicy {
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return .unrestricted }
        return .blocked("Managed policy isn't supported on Linux hosts yet.")
    }
}

/// What a host method needs from the policy. Every method a client can call is listed: an unknown
/// one is refused outside ordinary mode, before anything looks at its params.
enum HostMethodAdmission: Equatable {
    /// Status, reading what the host already has, and stopping things: available whatever the
    /// policy, so a host that's denied something can still say why and wind down.
    case always
    case needs(HostCapability)
    case unknown

    init(_ method: String) {
        typealias Method = HostProtocol.Method
        switch method {
        case Method.initialize, Method.listAgents, Method.listSessions, Method.attach, Method.detach,
            Method.cancel, Method.closeSession, Method.stopAgent, Method.cancelAgentSignIn, Method.execCancel,
            Method.fsUnwatch, Method.shutdown, Method.listActivity, Method.listNotifications,
            Method.acknowledgeNotifications, Method.listPlugins, Method.pluginAsset, Method.updateStatus,
            Method.updateReport, Method.hostStatus, Method.doctor, Method.setKeepAwake, Method.listCoordinators,
            Method.listTasks, Method.setSessionTitle, Method.configureTitles, Method.updateQueued,
            Method.removeQueued, Method.restoreQueued, Method.moveQueued:
            self = .always
        // Records only: storing a spec never approves launching it (`readyAgent` decides that), and
        // choosing who serves Native's tools never starts their listener (`agentTools` does).
        case Method.syncAgents, Method.configureTasks:
            self = .always
        case Method.startAgent, Method.restartAgent, Method.authenticateAgent, Method.setAgentCredential,
            Method.removeAgentCredential, Method.checkAgentSignIn, Method.listAgentSessions,
            Method.deleteAgentSession, Method.newSession, Method.openSession, Method.prompt,
            Method.respondPermission, Method.respondQuestion, Method.runHidden, Method.setConfigOption,
            Method.sendQueuedNow, Method.setMCPServers, Method.newCoordinator, Method.setCoordinator,
            Method.appToolResult, Method.actOnNotification:
            self = .needs(.agents)
        // Native's tools, called by the Mac app's scripts rather than an agent: the same tools.
        case Method.callTool:
            self = .needs(.agentTools)
        case Method.execRun, Method.execInput:
            self = .needs(.commands)
        case Method.fsRead, Method.fsList, Method.fsStat, Method.fsWatch, Method.listProjects, Method.addProject,
            Method.removeProject:
            self = .needs(.files)
        case Method.setPluginEnabled:
            self = .needs(.plugins)
        case Method.updateCheck, Method.updateInstall:
            self = .needs(.updates)
        default:
            self = .unknown
        }
    }
}

/// The policy refused something. Says what and why, never with any policy value in it.
struct HostPolicyDenial: Error, LocalizedError {
    /// Finishes "Your organization's policy doesn't allow this host to …".
    let action: String
    let reason: String?

    init(_ action: String, policy: HostPolicy) {
        self.action = action
        reason = policy.reason
    }

    var errorDescription: String? {
        let message = "Your organization's policy doesn't allow this host to \(action)."
        return reason.map { "\(message) \($0)" } ?? message
    }

    var rpcError: RPCError {
        HostErrorCode.notAuthorized.rpcError(errorDescription ?? "")
    }
}
