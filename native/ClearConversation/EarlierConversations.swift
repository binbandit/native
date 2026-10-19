import Foundation
import Observation

/// Conversations `/clear` set aside: a task cleared starts a fresh agent session, which takes the
/// earlier one's place in the sidebar while the earlier one stays openable from it.
///
/// A clear is remembered across launches once the fresh conversation has had a message, since
/// agents then list both sessions as their own. Before that, agents don't list the fresh one at all,
/// so a clear left empty is forgotten at quit and the earlier conversation is the task again.
@Observable
final class EarlierConversations {
    /// The session `/clear` started, to the one it set aside.
    private var earlier: [SessionKey: SessionKey] = [:]
    /// The sessions `/clear` started that have had a message, whose links are saved.
    @ObservationIgnored private var kept: Set<SessionKey> = []

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
        kept = Set(earlier.keys)
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

    /// The fresh conversation `later` had a message, so its clear is kept across launches.
    func keep(_ later: SessionKey) {
        guard earlier[later] != nil, kept.insert(later).inserted else { return }
        save()
    }

    private func save() {
        let links = earlier.filter { kept.contains($0.key) }.map { Link(later: $0.key, earlier: $0.value) }
        if let data = try? JSONEncoder().encode(links) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
