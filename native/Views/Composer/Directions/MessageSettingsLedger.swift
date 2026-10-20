#if DEBUG
import Foundation
import Observation

/// Which settings each message went out with, for direction C's chips on sent messages. A prototype
/// keeps them by the message's text in its own defaults; a real build would keep them on the turn.
@Observable
final class MessageSettingsLedger {
    static let shared = MessageSettingsLedger()

    private static let storageKey = "composerDesign.sentSettings"
    private var facts: [String: [String]]

    private init() {
        facts = UserDefaults.standard.dictionary(forKey: Self.storageKey) as? [String: [String]] ?? [:]
    }

    func facts(for text: String) -> [String]? {
        facts[Self.key(text)]
    }

    /// Keeps the first record: a message's settings are the ones it went out with.
    func record(_ text: String, facts newFacts: [String]) {
        let key = Self.key(text)
        guard !key.isEmpty, facts[key] == nil, !newFacts.isEmpty else { return }
        facts[key] = newFacts
        UserDefaults.standard.set(facts, forKey: Self.storageKey)
    }

    private static func key(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
