import Foundation
import Testing

@testable import NativeTelemetry

struct TelemetryDestinationFilteringTests {
    private actor TimingsOnly: TelemetryDestination {
        nonisolated let id = TelemetryDestinationID.native
        private(set) var records: [TelemetryRecord] = []

        nonisolated func accepts(_ name: TelemetryEventName) -> Bool { name == .appLaunched }
        func send(_ batch: TelemetryBatch) async throws { records += batch.records }
    }

    @Test func rejectedEventsAreNeverQueuedOrLogged() async throws {
        let pipeline = TelemetryPipeline()
        let url = FileManager.default.temporaryDirectory.appending(path: "telemetry-filter-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let log = TelemetrySentLog(url: url)
        await pipeline.configure(
            resource: TelemetryResource(installationID: UUID(), appVersion: nil, osVersion: nil),
            conditions: AlwaysSend(), log: log)
        let destination = TimingsOnly()
        await pipeline.setDestinations([destination])
        await pipeline.record(.featureUsed(.terminal))
        await pipeline.record(.appLaunched(launchDuration: .milliseconds(100)))
        #expect(await pipeline.pendingCount(for: .native) == 1)
        #expect(await pipeline.flush() == 1)
        #expect(await destination.records.map(\.name) == [.appLaunched])
        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(!contents.contains("feature.used"))
        #expect(contents.contains("app.launched"))
        await pipeline.setDestinations([])
    }
}
