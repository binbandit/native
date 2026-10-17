import ACP
import Foundation
import os

/// What it takes to reopen each workflow step's session after a restart: its agent, the agent's id
/// for it, and its folder. Runs name tasks by Native's client id, which is new every launch, so
/// this is the bridge from a saved run back to its sessions.
@MainActor
final class StepTaskRecords {
    struct Record: Codable, Hashable {
        var agent: String
        var session: SessionID
        var cwd: URL
    }

    static let standard = StepTaskRecords(
        url: AutomationStorage.file("workflow-tasks.json")
    )

    /// Records kept; runs are capped too, so older ones have nothing left to reopen.
    static let limit = 1_000

    private let url: URL
    private lazy var records: [UUID: Record] = load()
    private let logger = Logger(subsystem: "Native", category: "Workflows")

    init(url: URL) {
        self.url = url
    }

    subscript(task: UUID) -> Record? {
        records[task]
    }

    func remember(_ record: Record, for task: UUID) {
        records[task] = record
        if records.count > Self.limit {
            records = Dictionary(uniqueKeysWithValues: records.suffix(Self.limit / 2).map { ($0.key, $0.value) })
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(records).write(to: url, options: .atomic)
        } catch {
            logger.error("Couldn't save workflow step sessions: \(error)")
        }
    }

    private func load() -> [UUID: Record] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([UUID: Record].self, from: data)) ?? [:]
    }
}
