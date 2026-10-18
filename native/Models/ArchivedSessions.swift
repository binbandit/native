import Foundation
import Observation

/// Sessions the user archived: out of the sidebar, history kept, back with Unarchive. Remembered
/// across launches.
@Observable
final class ArchivedSessions {
    private var archived: [SessionKey: Date] {
        didSet { save() }
    }

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "archivedSessions"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
        archived = Dictionary(saved.map { ($0.key, $0.date) }, uniquingKeysWith: { first, _ in first })
    }

    func contains(_ key: SessionKey) -> Bool {
        archived[key] != nil
    }

    /// Every archived session, for keeping search's archived filter in step.
    var keys: Set<SessionKey> {
        Set(archived.keys)
    }

    /// When the session was archived, for ordering the Archived view.
    func date(_ key: SessionKey) -> Date? {
        archived[key]
    }

    func set(_ key: SessionKey, archived isArchived: Bool) {
        archived[key] = isArchived ? (archived[key] ?? .now) : nil
    }

    private struct Entry: Codable {
        let key: SessionKey
        let date: Date
    }

    private func save() {
        let entries = archived.map { Entry(key: $0.key, date: $0.value) }
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
