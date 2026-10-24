import ACP
import Foundation

// Running commands on a host for a client (docs/durability.md, "Commands"), so Git and GitHub code
// runs unchanged against a project on another machine. Remote code execution by design: only
// clients with the `runCommands` grant may, and the folder must be inside one of the host's projects.

extension HostProtocol.Method {
    public static let execRun = "_native/exec/run"
    public static let execCancel = "_native/exec/cancel"
    /// Private stdin for an interactive command owned by this client. Never journaled.
    public static let execInput = "_native/exec/input"
    /// Host → client: output of a command it's running, before the command's answer.
    public static let execOutput = "_native/exec/output"
}

public struct ExecRunParams: Codable, Sendable {
    /// Chosen by the client: names the command's output notifications and what `exec/cancel` stops.
    public var execID: UUID
    /// A name looked up on the host's PATH, or an absolute path on the host.
    public var executable: String
    public var arguments: [String]
    /// An absolute folder on the host, inside one of its projects. Nil runs the command with no
    /// folder of its own (`git --version`).
    public var directory: String?
    /// Set on top of the host's login-shell environment: only what the command needs on top, since
    /// the client's own PATH and HOME mean nothing on the host.
    public var environment: [String: String]
    public var stdin: Data?
    /// Seconds before the host stops the command and everything it started.
    public var timeout: Double?
    /// Send output as it arrives (`exec/output`), for showing a long command's progress. Without it,
    /// the host still sends output early once there's more than `ExecRunResult.inlineLimit`.
    public var stream: Bool
    /// A private terminal for CLI sign-ins that reject pipes. Optional for older hosts.
    public var interactive: Bool?

    public init(
        execID: UUID = UUID(), executable: String, arguments: [String], directory: String?,
        environment: [String: String] = [:], stdin: Data? = nil, timeout: Double? = nil, stream: Bool = false,
        interactive: Bool? = nil
    ) {
        self.execID = execID
        self.executable = executable
        self.arguments = arguments
        self.directory = directory
        self.environment = environment
        self.stdin = stdin
        self.timeout = timeout
        self.stream = stream
        self.interactive = interactive
    }
}

public struct ExecInputParams: Codable, Sendable {
    public var execID: UUID
    public var data: Data

    public init(execID: UUID, data: Data) {
        self.execID = execID
        self.data = data
    }
}

extension ExecInputParams: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "ExecInputParams(execID: \(execID), data: <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["execID": execID]) }
}

/// How a command ended. Its output is every `exec/output` notification for it, in order, followed by
/// `stdout` and `stderr` here: what hadn't been sent yet.
public struct ExecRunResult: Codable, Hashable, Sendable {
    public var exitCode: Int32
    public var stdout: Data
    public var stderr: Data

    public init(exitCode: Int32, stdout: Data, stderr: Data) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    /// The most output one answer carries; past it, the host sends what it has as notifications, so
    /// no single message grows with a command's output.
    public static let inlineLimit = 1 << 20
}

public enum ExecStream: String, WireEnum {
    case stdout
    case stderr
    case unknown
}

public struct ExecOutputNotification: Codable, Hashable, Sendable {
    public var execID: UUID
    public var stream: ExecStream
    public var data: Data

    public init(execID: UUID, stream: ExecStream, data: Data) {
        self.execID = execID
        self.stream = stream
        self.data = data
    }
}

/// Stops a command this client started, and everything it started; its `exec/run` then fails with
/// `cancelled`. A client that disconnects has its commands stopped the same way.
public struct ExecCancelParams: Codable, Sendable {
    public var execID: UUID

    public init(execID: UUID) {
        self.execID = execID
    }
}

extension HostProtocol {
    /// Whether a session request (`session/new`, `_native/session/open`, `set_mcp_servers`) would have
    /// the agent start commands of the client's choosing: a stdio MCP server is a command the agent
    /// launches, and `_meta` holds agent-specific options that can name more (hooks, servers,
    /// executables). Either takes the `runCommands` grant. Only servers that are plainly remote, HTTP
    /// or SSE with no command, don't.
    public static func sessionRequestRunsCommands(mcpServers: [JSONValue], meta: JSONValue?) -> Bool {
        if let meta, meta != .null, meta != .object([:]) { return true }
        return mcpServers.contains { server in
            guard case .object(let fields) = server, case .string(let type)? = fields["type"] else { return true }
            return !["http", "sse"].contains(type) || fields["command"] != nil
        }
    }
}
