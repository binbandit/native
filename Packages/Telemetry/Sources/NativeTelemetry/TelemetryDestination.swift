import Foundation

/// Which stream a destination is.
public enum TelemetryDestinationID: Hashable, Sendable, Codable, CustomStringConvertible {
    /// Native's own (Sentry, behind the user's consent and the organization's policy).
    case native
    /// An organization's collector.
    case organization(URL)

    public var description: String {
        switch self {
        case .native: "Native"
        case .organization(let url): url.host() ?? url.absoluteString
        }
    }
}

/// Events on their way to one destination.
public struct TelemetryBatch: Sendable {
    public let resource: TelemetryResource
    public let records: [TelemetryRecord]
}

/// Somewhere telemetry goes. The pipeline activates a destination when it's turned on and
/// deactivates it when it's turned off, so an SDK behind it can start and stop with consent.
public protocol TelemetryDestination: Sendable {
    var id: TelemetryDestinationID { get }
    func activate() async
    func deactivate() async
    func send(_ batch: TelemetryBatch) async throws
}

extension TelemetryDestination {
    public func activate() async {}
    public func deactivate() async {}
}

/// Whether now is a good time to send: the pipeline holds batches back otherwise.
public protocol TelemetrySendingConditions: Sendable {
    func allowsSending() async -> Bool
}

/// Sends whenever there's something to send; for tests.
public struct AlwaysSend: TelemetrySendingConditions {
    public init() {}
    public func allowsSending() async -> Bool { true }
}
