import Foundation
import NativeAutomation
import os

/// Keeps expeditions across launches, beside goals and workflow runs. It moves into the host
/// process with the other engines; the state is plain JSON either way.
@MainActor
public final class ExpeditionStore {
    public static let standard = ExpeditionStore(url: AutomationStorage.file("expeditions.json"))

    private let url: URL
    private let logger = Logger(subsystem: "Native", category: "Expeditions")

    public init(url: URL) {
        self.url = url
    }

    /// The saved expeditions, as found after a restart: turns that were in flight are interrupted.
    public func load() -> [Expedition] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try JSONDecoder().decode([Expedition].self, from: data).map { $0.restored() }
        } catch {
            logger.error("Ignoring unreadable expeditions: \(error)")
            return []
        }
    }

    public func save(_ expeditions: [Expedition]) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(expeditions).write(to: url, options: .atomic)
        } catch {
            logger.error("Couldn't save expeditions: \(error)")
        }
    }
}
