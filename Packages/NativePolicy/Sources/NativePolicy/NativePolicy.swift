import Foundation

/// What an organization (or the user) allows, resolved from every policy key: the organization's
/// value, then the user's, then Native's default. Every feature asks this rather than reading
/// preferences itself. A value that fails validation is reported in `diagnostics` and ignored.
public struct NativePolicy: Equatable, Sendable {
    public struct Agents: Equatable, Sendable {
        /// Agent ids that may be listed or started; nil allows every agent.
        public var allowed: Set<String>?
        /// Extra environment for each agent's process, by agent id.
        public var environment: [String: [String: String]] = [:]

        public func allows(_ agentID: String) -> Bool {
            allowed?.contains(agentID) ?? true
        }
    }

    public struct MCP: Equatable, Sendable {
        /// Servers that may run; nil allows every server that isn't blocked.
        public var allowed: [MCPServerPattern]?
        public var blocked: [MCPServerPattern] = []
        /// Servers every session gets.
        public var required: [RequiredMCPServer] = []

        /// Whether a server may run. `command` is its command line, when Native knows it.
        public func allows(name: String, command: String? = nil) -> Bool {
            if blocked.contains(where: { $0.matches(name: name, command: command) }) { return false }
            return allowed?.contains { $0.matches(name: name, command: command) } ?? true
        }
    }

    public struct Updates: Equatable, Sendable {
        public var isEnabled = true
        /// An internal update feed in place of Native's.
        public var feedURL: URL?
        /// Channel ids ("stable", "beta", "nightly") the user may pick; nil allows all.
        public var allowedChannels: Set<String>?

        public func allows(channel: String) -> Bool {
            allowedChannels?.contains(channel) ?? true
        }
    }

    public struct Telemetry: Equatable, Sendable {
        /// Who decides whether Native's own telemetry is on.
        public enum NativeMode: String, Equatable, Sendable, CaseIterable {
            /// Forced on by the organization.
            case on
            /// Forced off by the organization.
            case off
            /// The user decides (the default).
            case user
        }

        public var native = NativeMode.user
        /// The organization's own collectors.
        public var endpoints: [TelemetryEndpoint] = []
    }

    /// The scripts Native runs as tasks' worktrees are made and removed, tasks start and are deleted,
    /// and turns finish (docs/scripts.md). Not the script runtime, which is `scriptsEnabled`.
    public struct TaskScripts: Equatable, Sendable {
        /// Scripts users write in Native's settings: global, and each project's own.
        public var userScriptsEnabled = true
        /// Scripts committed to repositories (`.native/<event>.sh`).
        public var repositoryScriptsEnabled = true
    }

    public var agents = Agents()
    public var mcp = MCP()
    /// Ids of the plugins installed from manifests that may load; nil allows all. Built-in plugins
    /// are part of Native and governed by their own keys.
    public var allowedPlugins: Set<String>?
    public var catalog = Catalog()
    /// Skills, by name, denied in every session.
    public var blockedSkills: [String] = []
    /// Permission mode ids (an agent's `mode` choices) users can't pick.
    public var forbiddenPermissionModes: Set<String> = []
    public var scriptsEnabled = true
    /// Fetch the base branch before creating a task worktree. False keeps creation entirely local.
    public var worktreeFetchEnabled = true
    public var taskScripts = TaskScripts()
    /// False removes celebrations and their entry points, while keeping personal choices for later.
    public var celebrationsEnabled = true
    /// A display name supplied by the administrator, never inferred from an account or hostname.
    public var organizationName: String?
    public var labsEnabled = true
    public var companionEnabled = true
    public var remoteHostsEnabled = true
    public var updates = Updates()
    /// How long search keeps sessions; nil keeps them as long as the user chooses.
    public var searchRetentionDays: Int?
    /// Keyboard shortcuts by command id ("session.archive": "opt+cmd+a", "" for none), as Settings ▸
    /// Keyboard Shortcuts exports them; nil keeps Native's defaults. The organization's set replaces
    /// the user's changes and locks them.
    public var shortcutBindings: [String: String]?
    /// Instructions for what Native writes with AI, by purpose id ("branchName": "Start with the
    /// Jira key"); nil leaves them to the user. The organization's set replaces the user's and
    /// locks them, and a purpose it doesn't name gets none.
    public var aiInstructions: [String: String]?
    public var telemetry = Telemetry()

    /// The keys the organization sets with a valid value.
    public var managedKeys: Set<PolicyKey> = []
    /// Values that were ignored, and why.
    public var diagnostics: [PolicyDiagnostic] = []

    public init() {}

    /// Native's defaults: everything allowed, nothing managed.
    public static let `default` = NativePolicy()

    public func isManaged(_ key: PolicyKey) -> Bool {
        managedKeys.contains(key)
    }

    public func allowsPlugin(_ id: String) -> Bool {
        allowedPlugins?.contains(id) ?? true
    }

    public func forbids(permissionMode: String) -> Bool {
        forbiddenPermissionModes.contains(permissionMode)
    }
}

/// A policy value that was ignored.
public struct PolicyDiagnostic: Equatable, Sendable, CustomStringConvertible {
    public enum Origin: String, Equatable, Sendable {
        case organization, user
    }

    public var key: String
    public var origin: Origin
    public var problem: String

    public var description: String {
        "\(key) (\(origin.rawValue)): \(problem)"
    }
}

/// An MCP server named in a policy: by name (`github`, or a pattern such as `internal-*`), or by
/// the command it runs (`command:npx *@modelcontextprotocol/*`). Patterns use `*` and `?`.
public struct MCPServerPattern: Equatable, Hashable, Sendable {
    public enum Target: Equatable, Hashable, Sendable {
        case name, command
    }

    public var target: Target
    public var pattern: String

    public init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("command:") {
            target = .command
            pattern = String(trimmed.dropFirst("command:".count)).trimmingCharacters(in: .whitespaces)
        } else {
            target = .name
            pattern = trimmed
        }
        guard !pattern.isEmpty else { return nil }
    }

    /// A plain name, without wildcards, which agents can be told to turn off by name.
    public var exactName: String? {
        target == .name && !pattern.contains(where: { $0 == "*" || $0 == "?" }) ? pattern : nil
    }

    public func matches(name: String, command: String?) -> Bool {
        switch target {
        case .name: Wildcard.matches(pattern, name, caseSensitive: false)
        case .command: command.map { Wildcard.matches(pattern, $0, caseSensitive: true) } ?? false
        }
    }
}

/// An MCP server the organization gives every session.
public struct RequiredMCPServer: Equatable, Sendable {
    public enum Transport: Equatable, Sendable {
        case stdio(command: String, arguments: [String], environment: [String: String])
        case http(url: URL, headers: [String: String])
    }

    public var name: String
    public var transport: Transport
}

/// An organization collector for OpenTelemetry logs over OTLP/HTTP.
public struct TelemetryEndpoint: Equatable, Sendable {
    public var url: URL
    public var headers: [String: String]
    /// Resource attributes the organization adds for its own collector, such as a team name.
    public var attributes: [String: String]
}

/// `*` and `?` matching, so patterns behave the same on every platform.
enum Wildcard {
    static func matches(_ pattern: String, _ text: String, caseSensitive: Bool) -> Bool {
        let pattern = Array(caseSensitive ? pattern : pattern.lowercased())
        let text = Array(caseSensitive ? text : text.lowercased())
        var p = 0, t = 0, star = -1, mark = 0
        while t < text.count {
            if p < pattern.count, pattern[p] == "?" || pattern[p] == text[t] {
                p += 1
                t += 1
            } else if p < pattern.count, pattern[p] == "*" {
                star = p
                mark = t
                p += 1
            } else if star >= 0 {
                p = star + 1
                mark += 1
                t = mark
            } else {
                return false
            }
        }
        while p < pattern.count, pattern[p] == "*" { p += 1 }
        return p == pattern.count
    }
}
