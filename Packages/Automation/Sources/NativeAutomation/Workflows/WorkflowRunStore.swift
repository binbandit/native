import Foundation
import os

/// Keeps workflow runs across launches, in Application Support, because Native is durable by
/// default. It moves into the host process once that exists; the runs are plain JSON either way.
@MainActor
public final class WorkflowRunStore {
    public static let standard = WorkflowRunStore(
        url: AutomationStorage.file("workflow-runs.json")
    )

    /// Older runs are dropped past this, newest kept.
    public static let limit = 100

    private let url: URL
    private let logger = Logger(subsystem: "Native", category: "Workflows")

    public init(url: URL) {
        self.url = url
    }

    /// The saved runs, as found after a restart: turns that were in flight are interrupted.
    public func load() -> [WorkflowRun] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try JSONDecoder().decode([WorkflowRun].self, from: data).map { $0.restored() }
        } catch {
            logger.error("Ignoring unreadable workflow runs: \(error)")
            return []
        }
    }

    public func save(_ runs: [WorkflowRun]) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Array(runs.prefix(Self.limit))).write(to: url, options: .atomic)
        } catch {
            logger.error("Couldn't save workflow runs: \(error)")
        }
    }
}
