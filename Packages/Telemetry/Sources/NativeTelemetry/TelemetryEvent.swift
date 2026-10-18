import Foundation

/// Something worth counting. Every case carries only enums, durations and versions, so free text
/// (prompts, paths, commands, names) can't reach telemetry by construction. Add a case, its name and
/// its attributes to the schema (`TelemetryEventName.allowedAttributes`) together.
public enum TelemetryEvent: Equatable, Sendable {
    /// Native finished launching: from the process starting to the first window.
    case appLaunched(launchDuration: Duration)
    case featureUsed(TelemetryFeature)
    /// The main thread didn't respond for `duration`.
    case hangDetected(duration: Duration)
    case sessionStarted(agent: TelemetryAgent, agentVersion: TelemetryVersion?)
}

/// Features whose use is counted. Add a case for a new feature; never a free-form name.
public enum TelemetryFeature: String, CaseIterable, Codable, Sendable {
    case settings
    case terminal
    case workflows
    case automations
    case expeditions
    case pullRequests = "pull-requests"
    case planMode = "plan-mode"
    case steering
    case queuedMessage = "queued-message"
    case subagents
    case search
    case git
    case mcpServers = "mcp-servers"
    case labs
    case keepAwake = "keep-awake"
}

/// The agents Native ships plugins for. Agents from a user's own plugin are `other`, since their
/// ids are the user's own words.
public enum TelemetryAgent: String, CaseIterable, Codable, Sendable {
    case claudeCode = "claude-code"
    case codex
    case cursor
    case openCode = "opencode"
    case pi
    case copilot
    case gemini
    case goose
    case amp
    case other

    public init(agentID: String) {
        self = Self(rawValue: agentID.lowercased()).flatMap { $0 == .other ? nil : $0 } ?? .other
    }
}

/// A version reduced to its numbers ("1.4.2"), so build suffixes and anything else after them
/// never leave the machine.
public struct TelemetryVersion: Hashable, Sendable, Codable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ string: String) {
        let numbers = string.drop { !$0.isNumber }.prefix { $0.isNumber || $0 == "." }
            .split(separator: ".", omittingEmptySubsequences: false).prefix(3)
        guard let first = numbers.first, let major = Int(first) else { return nil }
        self.major = major
        minor = numbers.dropFirst().first.flatMap { Int($0) } ?? 0
        patch = numbers.dropFirst(2).first.flatMap { Int($0) } ?? 0
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public init(from decoder: any Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        guard let version = Self(string) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a version"))
        }
        self = version
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// Where Native runs.
public enum TelemetryPlatform: String, Codable, Sendable {
    case macOS = "macos"
    case iPadOS = "ipados"

    public static var current: Self {
        #if os(macOS)
            .macOS
        #else
            .iPadOS
        #endif
    }
}
