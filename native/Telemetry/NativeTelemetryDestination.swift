import NativeTelemetry

/// Native's own destination: Sentry (docs/decisions.md), whose start and stop live in
/// `SentryTelemetry`. Until its adapter is wired here, this stays nil, which keeps Native's own
/// telemetry off and its consent prompt from ever showing.
enum NativeTelemetryDestination {
    static let factory: (@MainActor () -> any TelemetryDestination)? = nil
}
