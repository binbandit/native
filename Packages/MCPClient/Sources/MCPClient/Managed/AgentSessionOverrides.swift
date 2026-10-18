import Foundation
import MCP

/// What Native asks an agent for in the sessions it starts, without touching the agent's files.
/// Each feature (MCP switches, skills) builds one in the agent's own terms, and the overrides of
/// all of them are merged before a session starts.
///
/// - `sessionMeta` goes into the `_meta` of `session/new` and `session/load`, so it applies to that
///   one session (Claude Code's adapter reads `claudeCode.options`).
/// - `launchConfiguration` holds JSON environment variables for the agent's process (Codex's
///   adapter reads `CODEX_CONFIG`), so it applies to every session once the agent restarts.
///
/// See docs/agent-session-overrides.md for what each agent supports and how it was verified.
public struct AgentSessionOverrides: Hashable, Sendable {
    public var sessionMeta: [String: JSON]
    /// By environment variable; each value is rendered as JSON.
    public var launchConfiguration: [String: JSON]
    /// What couldn't be asked for, in words for the user.
    public var limitations: [String]

    public init(
        sessionMeta: [String: JSON] = [:], launchConfiguration: [String: JSON] = [:], limitations: [String] = []
    ) {
        self.sessionMeta = sessionMeta
        self.launchConfiguration = launchConfiguration
        self.limitations = limitations
    }

    public static let none = AgentSessionOverrides()

    public var isEmpty: Bool {
        sessionMeta.isEmpty && launchConfiguration.isEmpty
    }

    /// Both sets of overrides: objects merge key by key, arrays concatenate, and for anything else
    /// `other` wins.
    public func merging(_ other: AgentSessionOverrides) -> AgentSessionOverrides {
        AgentSessionOverrides(
            sessionMeta: Self.merge(sessionMeta, other.sessionMeta),
            launchConfiguration: Self.merge(launchConfiguration, other.launchConfiguration),
            limitations: limitations + other.limitations.filter { !limitations.contains($0) }
        )
    }

    /// `launchConfiguration` as environment variables.
    public var launchEnvironment: [String: String] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return launchConfiguration.compactMapValues { value in
            (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) }
        }
    }

    static func merge(_ base: [String: JSON], _ other: [String: JSON]) -> [String: JSON] {
        base.merging(other) { left, right in
            switch (left, right) {
            case (.object(let left), .object(let right)): .object(merge(left, right))
            case (.array(let left), .array(let right)): .array(left + right)
            default: right
            }
        }
    }
}

/// Turning agents' own MCP servers off for the sessions Native starts, in each agent's terms.
public enum MCPSessionOverrides {
    /// Overrides that keep `format`'s agent from loading `servers` (its own entries).
    ///
    /// - Parameters:
    ///   - servers: Entries off in the session's project.
    ///   - offEverywhere: The subset off in every project, which is all Codex can express.
    public static func disabling(
        _ servers: [ConfiguredServer], offEverywhere: [ConfiguredServer], for format: AgentConfigFormat
    ) -> AgentSessionOverrides {
        guard !servers.isEmpty || !offEverywhere.isEmpty else { return .none }
        switch format {
        case .claudeCode:
            // Claude Code merges `deniedMcpServers` from every settings source, the SDK's
            // programmatic tier included, and doesn't start a denied server.
            let denied = Set(servers.map(\.name)).sorted().map { JSON.object(["serverName": .string($0)]) }
            return AgentSessionOverrides(sessionMeta: [
                "claudeCode": ["options": ["settings": ["deniedMcpServers": .array(denied)]]]
            ])
        case .codex:
            // The adapter merges `CODEX_CONFIG` into every session's config: per process, not per
            // session, so only servers off everywhere can be left out.
            let names = Set(offEverywhere.map(\.name)).sorted()
            let projectOnly = Set(servers.map(\.name)).subtracting(names).sorted()
            return AgentSessionOverrides(
                launchConfiguration: names.isEmpty
                    ? [:]
                    : [
                        "CODEX_CONFIG": [
                            "mcp_servers": .object(
                                Dictionary(uniqueKeysWithValues: names.map { ($0, ["enabled": false]) }))
                        ]
                    ],
                limitations: projectOnly.map {
                    "Codex can't leave \($0) out of one project's sessions, only all of them."
                }
            )
        case .cursor:
            return AgentSessionOverrides(
                limitations: Set(servers.map(\.name)).sorted().map {
                    "Cursor can't leave \($0) out of a session; turn it off in Cursor's MCP settings."
                })
        }
    }
}
