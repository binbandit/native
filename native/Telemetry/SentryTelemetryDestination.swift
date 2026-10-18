import NativeTelemetry
// The Swift 5 SDK synchronizes its mutable metrics singleton internally.
@preconcurrency import Sentry

/// Sentry receives diagnostics and timing metrics; product-use events remain separate.
nonisolated struct SentryTelemetryDestination: TelemetryDestination {
    let dsn: String
    let id = TelemetryDestinationID.native

    func accepts(_ name: TelemetryEventName) -> Bool {
        name == .appLaunched || name == .hangDetected
    }

    func activate() async {
        await MainActor.run { SentryTelemetry.start(dsn: dsn) }
    }

    func deactivate() async {
        await MainActor.run { SentryTelemetry.stop() }
    }

    func send(_ batch: TelemetryBatch) async throws {
        for record in batch.records where accepts(record.name) {
            let key: TelemetryAttributeKey = record.name == .appLaunched ? .launchDurationMs : .hangDurationMs
            guard let attribute = record.attributes.first(where: { $0.key == key }),
                case .int(let milliseconds) = attribute.value.kind, milliseconds >= 0
            else { continue }
            SentrySDK.metrics.distribution(
                key: record.name == .appLaunched ? "native.launch.duration_ms" : "native.hang.duration_ms",
                value: Double(milliseconds), unit: .millisecond)
        }
    }
}
