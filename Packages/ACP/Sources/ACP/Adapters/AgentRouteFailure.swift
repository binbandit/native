import Foundation

/// Stable, content-free failures. Do not attach raw URLs, configuration, environment or CLI stderr.
public enum AgentRouteFailure: String, Error, LocalizedError, Sendable {
    case invalidRoute, conflictingConfiguration, unsupportedControl, unqualified, declarationMismatch, networkDenied

    public var errorDescription: String? { "Agent route denied (\(rawValue))." }
}
