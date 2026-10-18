import Foundation

/// The single gate every event passes through. Events are queued only for destinations that are
/// on, in a bounded backlog per destination, and sent in batches when `TelemetrySendingConditions`
/// allow. Turning a destination off drops what it had queued.
public actor TelemetryPipeline {
    public struct Configuration: Sendable {
        public var batchSize = 50
        /// Beyond this many unsent events per destination, the oldest are dropped.
        public var backlogLimit = 500
        public var flushInterval = Duration.seconds(60)

        public init() {}
    }

    private let configuration: Configuration
    private var destinations: [TelemetryDestinationID: any TelemetryDestination] = [:]
    private var queues: [TelemetryDestinationID: [TelemetryRecord]] = [:]
    private var resource: TelemetryResource?
    private var conditions: any TelemetrySendingConditions = AlwaysSend()
    private var log: TelemetrySentLog?
    private var flushLoop: Task<Void, Never>?
    private var isFlushing = false
    /// Events dropped because a backlog was full, since launch.
    public private(set) var droppedCount = 0

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Who's sending and how; until this is called, nothing is sent.
    public func configure(
        resource: TelemetryResource, conditions: any TelemetrySendingConditions, log: TelemetrySentLog?
    ) {
        self.resource = resource
        self.conditions = conditions
        self.log = log
    }

    /// A new installation id for batches from now on, as after the user resets it.
    public func setInstallationID(_ id: UUID) {
        resource?.installationID = id
    }

    /// The destinations that are on. Ones no longer listed are deactivated and their queues
    /// dropped; new ones are activated.
    public func setDestinations(_ wanted: [any TelemetryDestination]) async {
        let wantedIDs = Set(wanted.map(\.id))
        for (id, destination) in destinations where !wantedIDs.contains(id) {
            destinations[id] = nil
            queues[id] = nil
            await destination.deactivate()
        }
        for destination in wanted where destinations[destination.id] == nil {
            destinations[destination.id] = destination
            await destination.activate()
        }
        updateFlushLoop()
    }

    public var activeDestinations: [TelemetryDestinationID] {
        Array(destinations.keys)
    }

    public func record(_ event: TelemetryEvent, at time: Date = .now) {
        guard !destinations.isEmpty else { return }
        let record = TelemetryRecord(event, at: time)
        for (id, destination) in destinations where destination.accepts(record.name) {
            var queue = queues[id, default: []]
            queue.append(record)
            if queue.count > configuration.backlogLimit {
                droppedCount += queue.count - configuration.backlogLimit
                queue.removeFirst(queue.count - configuration.backlogLimit)
            }
            queues[id] = queue
        }
    }

    public func pendingCount(for id: TelemetryDestinationID) -> Int {
        queues[id]?.count ?? 0
    }

    /// Sends what's queued, one batch per destination at a time, if conditions allow. Returns how
    /// many events were sent.
    @discardableResult
    public func flush() async -> Int {
        guard !isFlushing, let resource, await conditions.allowsSending() else { return 0 }
        isFlushing = true
        defer { isFlushing = false }
        var sent = 0
        for (id, destination) in destinations {
            while let queue = queues[id], !queue.isEmpty, destinations[id] != nil {
                let records = Array(queue.prefix(configuration.batchSize))
                queues[id] = Array(queue.dropFirst(records.count))
                do {
                    try await destination.send(TelemetryBatch(resource: resource, records: records))
                    sent += records.count
                    log?.append(TelemetrySentLog.Entry(destination: id, resource: resource, records: records))
                } catch {
                    // Keep them for the next flush, unless the destination was turned off meanwhile.
                    if destinations[id] != nil {
                        queues[id] = Array((records + (queues[id] ?? [])).suffix(configuration.backlogLimit))
                    }
                    break
                }
            }
        }
        return sent
    }

    private func updateFlushLoop() {
        if destinations.isEmpty {
            flushLoop?.cancel()
            flushLoop = nil
        } else if flushLoop == nil {
            let interval = configuration.flushInterval
            flushLoop = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: interval)
                    await self?.flush()
                }
            }
        }
    }
}

/// Where call sites record events: `Telemetry.record(.featureUsed(.terminal))`.
public enum Telemetry {
    public static let pipeline = TelemetryPipeline()

    public static func record(_ event: TelemetryEvent) {
        let time = Date.now
        Task { await pipeline.record(event, at: time) }
    }
}
