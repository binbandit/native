import Foundation
import Testing

@testable import NativeTelemetry

/// Collects batches; fails while `failing` is set.
actor RecordingDestination: TelemetryDestination {
    nonisolated let id: TelemetryDestinationID
    private(set) var batches: [TelemetryBatch] = []
    private(set) var activations = 0
    private(set) var deactivations = 0
    var failing = false

    init(_ id: TelemetryDestinationID = .native) {
        self.id = id
    }

    func activate() async { activations += 1 }
    func deactivate() async { deactivations += 1 }

    func setFailing(_ failing: Bool) { self.failing = failing }

    func send(_ batch: TelemetryBatch) async throws {
        if failing { throw TelemetrySendError.status(503) }
        batches.append(batch)
    }
}

struct Never: TelemetrySendingConditions {
    func allowsSending() async -> Bool { false }
}

final class CapturingTransport: TelemetryTransport, @unchecked Sendable {
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> Int {
        requests.append(request)
        return 200
    }
}

@Suite struct NativeTelemetryTests {
    let resource = TelemetryResource(
        installationID: UUID(), appVersion: TelemetryVersion("1.4.0-nightly.20261018"), osVersion: TelemetryVersion("27.2"))

    static let everyEvent: [TelemetryEvent] = [
        .appLaunched(launchDuration: .milliseconds(812)),
        .featureUsed(.terminal),
        .hangDetected(duration: .seconds(3)),
        .sessionStarted(agent: .codex, agentVersion: TelemetryVersion("0.93.0")),
        .sessionStarted(agent: .other, agentVersion: nil),
    ]

    @Test(arguments: everyEvent) func everyEventConformsToItsSchema(event: TelemetryEvent) {
        #expect(TelemetryRecord(event, at: .now).conformsToSchema)
    }

    @Test func versionsKeepOnlyTheirNumbers() {
        #expect(TelemetryVersion("1.4.0-nightly.20261018.abc1234")?.description == "1.4.0")
        #expect(TelemetryVersion("v2.10")?.description == "2.10.0")
        #expect(TelemetryVersion("codex-cli 0.46.0 (build secret)")?.description == "0.46.0")
        #expect(TelemetryVersion("unknown") == nil)
    }

    @Test func userAgentIDsBecomeOther() {
        #expect(TelemetryAgent(agentID: "codex") == .codex)
        #expect(TelemetryAgent(agentID: "acme-secret-agent") == .other)
        #expect(TelemetryAgent(agentID: "other") == .other)
    }

    @Test func nothingIsQueuedWhileNoDestinationIsOn() async {
        let pipeline = TelemetryPipeline()
        await pipeline.configure(resource: resource, conditions: AlwaysSend(), log: nil)
        await pipeline.record(.featureUsed(.git))
        let destination = RecordingDestination()
        await pipeline.setDestinations([destination])
        #expect(await pipeline.pendingCount(for: .native) == 0)
        await pipeline.flush()
        #expect(await destination.batches.isEmpty)
    }

    @Test func sendsInBatchesAndLogsWhatWasSent() async throws {
        var configuration = TelemetryPipeline.Configuration()
        configuration.batchSize = 2
        let pipeline = TelemetryPipeline(configuration: configuration)
        let logURL = FileManager.default.temporaryDirectory.appending(path: "telemetry-\(UUID()).log")
        defer { try? FileManager.default.removeItem(at: logURL) }
        let log = TelemetrySentLog(url: logURL)
        await pipeline.configure(resource: resource, conditions: AlwaysSend(), log: log)
        let destination = RecordingDestination()
        await pipeline.setDestinations([destination])
        for event in Self.everyEvent { await pipeline.record(event) }
        #expect(await pipeline.flush() == 5)
        #expect(await destination.batches.map(\.records.count) == [2, 2, 1])
        #expect(log.entries().flatMap(\.records).map(\.name) == Self.everyEvent.map { TelemetryRecord($0, at: .now).name })
        #expect(await destination.activations == 1)
    }

    @Test func holdsBatchesUntilConditionsAllow() async {
        let pipeline = TelemetryPipeline()
        await pipeline.configure(resource: resource, conditions: Never(), log: nil)
        let destination = RecordingDestination()
        await pipeline.setDestinations([destination])
        await pipeline.record(.featureUsed(.labs))
        #expect(await pipeline.flush() == 0)
        #expect(await pipeline.pendingCount(for: .native) == 1)
    }

    @Test func backlogIsBounded() async {
        var configuration = TelemetryPipeline.Configuration()
        configuration.backlogLimit = 3
        let pipeline = TelemetryPipeline(configuration: configuration)
        await pipeline.setDestinations([RecordingDestination()])
        for _ in 0..<5 { await pipeline.record(.featureUsed(.search)) }
        #expect(await pipeline.pendingCount(for: .native) == 3)
        #expect(await pipeline.droppedCount == 2)
    }

    @Test func failedBatchesStayQueuedAndTurningOffDropsThem() async {
        let pipeline = TelemetryPipeline()
        await pipeline.configure(resource: resource, conditions: AlwaysSend(), log: nil)
        let destination = RecordingDestination()
        await destination.setFailing(true)
        await pipeline.setDestinations([destination])
        await pipeline.record(.featureUsed(.git))
        #expect(await pipeline.flush() == 0)
        #expect(await pipeline.pendingCount(for: .native) == 1)
        await pipeline.setDestinations([])
        #expect(await pipeline.pendingCount(for: .native) == 0)
        #expect(await destination.deactivations == 1)
    }

    @Test func otlpRequestIsGzippedJSONWithTheOrganizationsHeadersAndAttributes() async throws {
        let transport = CapturingTransport()
        let destination = OTLPLogDestination(
            url: URL(string: "https://otel.example.com")!, headers: ["x-api-key": "k"], attributes: ["team": "web"],
            transport: transport)
        let records = Self.everyEvent.prefix(2).map { TelemetryRecord($0, at: Date(timeIntervalSince1970: 1)) }
        try await destination.send(TelemetryBatch(resource: resource, records: records))
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://otel.example.com/v1/logs")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "k")
        #expect(request.value(forHTTPHeaderField: "Content-Encoding") == "gzip")
        let body = try #require(request.httpBody)
        #expect(body.prefix(2) == Data([0x1F, 0x8B]))
        let json = try String(decoding: gunzip(body), as: UTF8.self)
        #expect(json.contains(#""eventName":"app.launched""#))
        #expect(json.contains(#""key":"launch.duration_ms","value":{"intValue":"812"}"#))
        #expect(json.contains(#""key":"team","value":{"stringValue":"web"}"#))
        #expect(json.contains(#""key":"service.version","value":{"stringValue":"1.4.0"}"#))
        #expect(json.contains(#""timeUnixNano":"1000000000""#))
    }

    @Test func installationIDRotates() throws {
        let suite = "NativeTelemetryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ids = TelemetryInstallationID(defaults: defaults)
        let first = ids.current
        #expect(ids.current == first)
        #expect(ids.rotate() != first)
    }

    @Test func sentLogKeepsTheNewestEntries() {
        let url = FileManager.default.temporaryDirectory.appending(path: "telemetry-\(UUID()).log")
        defer { try? FileManager.default.removeItem(at: url) }
        let log = TelemetrySentLog(url: url, limit: 2)
        for feature in [TelemetryFeature.git, .labs, .search] {
            log.append(.init(destination: .native, resource: resource, records: [TelemetryRecord(.featureUsed(feature), at: .now)]))
        }
        #expect(log.entries().flatMap(\.records).map(\.attributes.first?.value.description) == ["labs", "search"])
    }

    /// Strips the gzip framing and inflates, checking the trailer.
    private func gunzip(_ data: Data) throws -> Data {
        let deflated = data.dropFirst(10).dropLast(8)
        let inflated = try (Data(deflated) as NSData).decompressed(using: .zlib) as Data
        let crc = data.suffix(8).prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        #expect(UInt32(littleEndian: crc) == CRC32.checksum(inflated))
        return inflated
    }
}
