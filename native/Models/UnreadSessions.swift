import Foundation
import Observation

/// Sessions with news the user hasn't looked at: a turn that ended or a permission request that
/// arrived while another session was showing. Remembered across launches.
@Observable
final class UnreadSessions {
    private var keys: Set<SessionKey> {
        didSet { save() }
    }

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "unreadSessions"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        keys =
            defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Set<SessionKey>.self, from: $0) } ?? []
    }

    func contains(_ key: SessionKey) -> Bool {
        keys.contains(key)
    }

    func set(_ key: SessionKey, unread: Bool) {
        guard keys.contains(key) != unread else { return }
        if unread {
            keys.insert(key)
        } else {
            keys.remove(key)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(keys) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
