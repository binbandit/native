import ACP
import Foundation

/// The sessions Native started as tasks (orchestration, workflow steps), remembered across
/// launches: agents list them like any other session, but they belong to whatever started them, not
/// the sidebar, and reopening one needs its folder and parent.
final class TaskSessionRecords {
    struct Record: Codable, Hashable, Sendable {
        let key: SessionKey
        let cwd: URL
        /// The session that delegated it, if any.
        let parent: SessionKey?
    }

    private var records: [SessionKey: Record] {
        didSet { save() }
    }

    private let defaults: UserDefaults
    private static let key = "taskSessions"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Record].self, from: $0) } ?? []
        records = Dictionary(saved.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
    }

    func contains(_ key: SessionKey) -> Bool {
        records[key] != nil
    }

    func record(_ key: SessionKey) -> Record? {
        records[key]
    }

    func add(_ record: Record) {
        records[record.key] = record
    }

    private func save() {
        if let data = try? JSONEncoder().encode(Array(records.values)) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
