import Foundation
import os

/// Keeps goals across launches, in Application Support: conversations live with the agent, but a
/// goal is Native's own addition to a task. One small JSON file, rewritten on every change.
@MainActor
public final class GoalStore {
    public static let standard = GoalStore(
        url: URL.applicationSupportDirectory.appending(path: "Native/goals.json", directoryHint: .notDirectory)
    )

    private let url: URL
    private lazy var loops: [String: GoalLoop] = load()
    private let logger = Logger(subsystem: "Native", category: "Goals")

    public init(url: URL) {
        self.url = url
    }

    public func loop(for key: String) -> GoalLoop? {
        loops[key]
    }

    public func save(_ loop: GoalLoop?, for key: String) {
        guard loops[key] != loop else { return }
        loops[key] = loop
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(loops).write(to: url, options: .atomic)
        } catch {
            logger.error("Couldn't save goals: \(error)")
        }
    }

    private func load() -> [String: GoalLoop] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([String: GoalLoop].self, from: data)
        } catch {
            logger.error("Ignoring unreadable goals file: \(error)")
            return [:]
        }
    }
}
