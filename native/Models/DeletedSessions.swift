import Foundation

/// Sessions the user deleted from Native, remembered across launches so an agent that can't delete
/// its own copy doesn't bring them back on the next `session/list`.
final class DeletedSessions {
    private var keys: Set<SessionKey> {
        didSet { save() }
    }

    private let defaults: UserDefaults
    private static let key = "deletedSessions"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        keys = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Set<SessionKey>.self, from: $0) } ?? []
    }

    func contains(_ key: SessionKey) -> Bool {
        keys.contains(key)
    }

    func insert(_ key: SessionKey) {
        keys.insert(key)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(keys) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
