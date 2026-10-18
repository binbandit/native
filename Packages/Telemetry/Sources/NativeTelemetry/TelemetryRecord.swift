import Foundation

/// The schema: every event's name and the only attributes it may carry.
public enum TelemetryEventName: String, CaseIterable, Codable, Sendable {
    case appLaunched = "app.launched"
    case featureUsed = "feature.used"
    case hangDetected = "hang.detected"
    case sessionStarted = "session.started"

    public var allowedAttributes: Set<TelemetryAttributeKey> {
        switch self {
        case .appLaunched: [.launchDurationMs]
        case .featureUsed: [.feature]
        case .hangDetected: [.hangDurationMs]
        case .sessionStarted: [.agent, .agentVersion]
        }
    }
}

public enum TelemetryAttributeKey: String, CaseIterable, Codable, Sendable {
    case launchDurationMs = "launch.duration_ms"
    case feature = "feature.name"
    case hangDurationMs = "hang.duration_ms"
    case agent = "agent.id"
    case agentVersion = "agent.version"

    /// A duration in milliseconds, which metrics keep as a distribution rather than a tag.
    public var isDuration: Bool {
        switch self {
        case .launchDurationMs, .hangDurationMs: true
        case .feature, .agent, .agentVersion: false
        }
    }
}

/// An attribute's value: a number, or a token from a closed vocabulary (an enum's raw value or a
/// version). Tokens can only be made inside this module, from those.
public struct TelemetryAttributeValue: Hashable, Sendable, Codable, CustomStringConvertible {
    public enum Kind: Hashable, Sendable, Codable {
        case int(Int64)
        case token(String)
    }

    public let kind: Kind

    static func int(_ value: Int64) -> Self { Self(kind: .int(value)) }
    static func token(_ value: some RawRepresentable<String>) -> Self { Self(kind: .token(value.rawValue)) }
    static func version(_ value: TelemetryVersion) -> Self { Self(kind: .token(value.description)) }

    public var description: String {
        switch kind {
        case .int(let value): String(value)
        case .token(let value): value
        }
    }
}

public struct TelemetryAttribute: Hashable, Sendable, Codable {
    public let key: TelemetryAttributeKey
    public let value: TelemetryAttributeValue
}

/// An event as sent: its name, when it happened, and its attributes.
public struct TelemetryRecord: Hashable, Sendable, Codable {
    public let name: TelemetryEventName
    public let time: Date
    public let attributes: [TelemetryAttribute]

    public init(_ event: TelemetryEvent, at time: Date) {
        self.time = time
        switch event {
        case .appLaunched(let duration):
            name = .appLaunched
            attributes = [.init(key: .launchDurationMs, value: .int(duration.milliseconds))]
        case .featureUsed(let feature):
            name = .featureUsed
            attributes = [.init(key: .feature, value: .token(feature))]
        case .hangDetected(let duration):
            name = .hangDetected
            attributes = [.init(key: .hangDurationMs, value: .int(duration.milliseconds))]
        case .sessionStarted(let agent, let version):
            name = .sessionStarted
            attributes =
                [.init(key: .agent, value: .token(agent))]
                + (version.map { [.init(key: .agentVersion, value: .version($0))] } ?? [])
        }
    }

    /// Whether every attribute is one the event's schema allows.
    public var conformsToSchema: Bool {
        attributes.allSatisfy { name.allowedAttributes.contains($0.key) }
    }
}

/// Who and where, sent once per batch rather than with every event.
public struct TelemetryResource: Hashable, Sendable, Codable {
    /// Random, rotatable, and never linked to an account.
    public var installationID: UUID
    public var appVersion: TelemetryVersion?
    public var platform: TelemetryPlatform
    public var osVersion: TelemetryVersion?

    public init(
        installationID: UUID, appVersion: TelemetryVersion?, platform: TelemetryPlatform = .current,
        osVersion: TelemetryVersion?
    ) {
        self.installationID = installationID
        self.appVersion = appVersion
        self.platform = platform
        self.osVersion = osVersion
    }
}

extension Duration {
    var milliseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1000 + attoseconds / 1_000_000_000_000_000
    }
}
