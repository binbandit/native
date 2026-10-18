import Foundation
import os

/// Keeps Automations' state in Application Support until the durable host owns it.
@MainActor
public final class AutomationStore {
    public static let standard = AutomationStore(
        url: AutomationStorage.file("automations.json")
    )

    private let url: URL
    private let logger = Logger(subsystem: "Native", category: "Automations")

    public init(url: URL) {
        self.url = url
    }

    public func load() -> AutomationBook {
        guard let data = try? Data(contentsOf: url) else { return AutomationBook() }
        do {
            return try JSONDecoder().decode(AutomationBook.self, from: data)
        } catch {
            logger.error("Ignoring unreadable automations: \(error)")
            return AutomationBook()
        }
    }

    public func save(_ book: AutomationBook) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(book).write(to: url, options: .atomic)
        } catch {
            logger.error("Couldn't save automations: \(error)")
        }
    }
}
