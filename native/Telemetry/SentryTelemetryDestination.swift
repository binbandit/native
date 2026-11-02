import NativeDiagnostics
import NativeTelemetry
// The Swift 5 SDK synchronizes its mutable metrics singleton internally.
@preconcurrency import Sentry

/// Native's own destination: every typed event as Sentry metrics. Each event is a count tagged
/// with its enum and version attributes, and each duration a distribution in milliseconds
/// (`TelemetryRecord.metrics`). The names and tags come only from the telemetry schema, and
/// `SentryPrivacy` drops anything outside `metricAllowlist` again before it leaves.
nonisolated struct SentryTelemetryDestination: TelemetryDestination {
    let dsn: String
    let id = TelemetryDestinationID.native

    /// What `SentryPrivacy` lets through: exactly what the schema can produce.
    static let metricAllowlist = SentryMetricAllowlist(
        counts: TelemetryMetric.allowlist.counts,
        distributions: TelemetryMetric.allowlist.distributions,
        tagKeys: TelemetryMetric.allowlist.tagKeys)

    func activate() async {
        await MainActor.run { SentryTelemetry.start(dsn: dsn) }
    }

    func deactivate() async {
        await MainActor.run { SentryTelemetry.stop() }
    }

    func send(_ batch: TelemetryBatch) async throws {
        for metric in batch.records.flatMap(\.metrics) {
            let attributes = metric.tags.mapValues { $0 as any SentryAttributeValue }
            switch metric.value {
            case .count(let count):
                SentrySDK.metrics.count(key: metric.name, value: count, attributes: attributes)
            case .milliseconds(let milliseconds):
                SentrySDK.metrics.distribution(
                    key: metric.name, value: Double(milliseconds), unit: .millisecond, attributes: attributes)
            }
        }
    }
}
