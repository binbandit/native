import ACP
import Foundation
import NativeAutomation
import os

/// What it takes to reopen each crew member's session after a restart: its agent, the agent's id
/// for it, and its folder. Expeditions name sessions by Native's client id, which is new every
/// launch, so this is the bridge from a saved expedition back to its sessions.
@MainActor
final class ExpeditionCrewRecords {
    struct Record: Codable, Hashable {
        var agent: String
        var session: SessionID
        var cwd: URL
    }

    static let standard = ExpeditionCrewRecords(url: AutomationStorage.file("expedition-tasks.json"))

    private let url: URL
    private lazy var records: [UUID: Record] = load()
    private let logger = Logger(subsystem: "Native", category: "Expeditions")

    init(url: URL) {
        self.url = url
    }

    subscript(task: UUID) -> Record? {
        records[task]
    }

    func remember(_ record: Record, for task: UUID) {
        records[task] = record
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(records).write(to: url, options: .atomic)
        } catch {
            logger.error("Couldn't save expedition sessions: \(error)")
        }
    }

    private func load() -> [UUID: Record] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([UUID: Record].self, from: data)) ?? [:]
    }
}
