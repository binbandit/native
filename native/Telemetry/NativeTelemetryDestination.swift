import NativeTelemetry

/// Availability is separate from consent: creating the factory never starts the SDK.
enum NativeTelemetryDestination {
    static var factory: (@MainActor () -> any TelemetryDestination)? {
        guard let dsn = SentryTelemetry.configuredDSN else { return nil }
        return { SentryTelemetryDestination(dsn: dsn) }
    }
}
