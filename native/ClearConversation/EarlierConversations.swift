import Foundation
import Observation

/// Conversations `/clear` set aside: a task cleared starts a fresh agent session, which takes the
/// earlier one's place in the sidebar while the earlier one stays openable from it. Remembered
/// across launches, since agents list both sessions as their own.
@Observable
final class EarlierConversations {
    /// The session `/clear` started, to the one it set aside.
    private var earlier: [SessionKey: SessionKey] {
        didSet { save() }
    }

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "earlierConversations"

    private struct Link: Codable {
        let later: SessionKey
        let earlier: SessionKey
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let links = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Link].self, from: $0) } ?? []
        earlier = Dictionary(links.map { ($0.later, $0.earlier) }, uniquingKeysWith: { _, last in last })
    }

    /// The conversation `key` continues from, if `/clear` started it.
    func conversation(before key: SessionKey) -> SessionKey? {
        earlier[key]
    }

    /// The conversation that replaced `key`, if it was cleared.
    func conversation(after key: SessionKey) -> SessionKey? {
        earlier.first { $0.value == key }?.key
    }

    /// Whether `/clear` set `key` aside, which keeps it out of the sidebar.
    func isSetAside(_ key: SessionKey) -> Bool {
        earlier.values.contains(key)
    }

    func record(_ later: SessionKey, after earlierKey: SessionKey) {
        earlier[later] = earlierKey
    }

    private func save() {
        let links = earlier.map { Link(later: $0.key, earlier: $0.value) }
        if let data = try? JSONEncoder().encode(links) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
