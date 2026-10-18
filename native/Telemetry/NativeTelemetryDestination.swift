import Foundation
import NativeTelemetry

/// Native's own destination: Sentry (docs/decisions.md), through `SentryTelemetryDestination`. It
/// exists only when this build carries a Sentry DSN, so a build without one keeps Native's own
/// telemetry off and never asks for consent. `TelemetryCenter` decides when it's on.
enum NativeTelemetryDestination {
    static let factory: (@MainActor () -> any TelemetryDestination)? = dsn.map { dsn in
        { SentryTelemetryDestination(dsn: dsn) }
    }

    /// The DSN from Info.plist, when it's a usable one (the same check `SentryTelemetry` makes).
    private static var dsn: String? {
        guard let dsn = SentryTelemetry.configuredDSN, let url = URL(string: dsn), url.scheme == "https",
            url.host() != nil, url.user() != nil
        else { return nil }
        return dsn
    }
}
