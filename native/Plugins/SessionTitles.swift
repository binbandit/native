import ACP
import Foundation
import Observation
import os

/// The titles Native shows for sessions. A title the user typed wins; then one generated from the
/// first prompt, so every agent's sessions read the same way and are named the moment they start;
/// then whatever the agent called it.
@Observable
final class SessionTitles {
    struct Key: Hashable, Sendable {
        let agent: AgentDefinition.ID
        let session: SessionID

        fileprivate var storageKey: String { "\(agent.rawValue)/\(session.rawValue)" }
    }

    private var userTitles: [String: String]
    private var generatedTitles: [String: String]
    private var generating: Set<Key> = []
    private let logger = Logger(subsystem: "Native", category: "Titles")

    private static let userKey = "sessionTitles.user"
    private static let generatedKey = "sessionTitles.generated"

    init() {
        let defaults = UserDefaults.standard
        userTitles = defaults.dictionary(forKey: Self.userKey) as? [String: String] ?? [:]
        generatedTitles = defaults.dictionary(forKey: Self.generatedKey) as? [String: String] ?? [:]
    }

    func title(for key: Key, agentTitle: String?) -> String? {
        userTitles[key.storageKey] ?? generatedTitles[key.storageKey] ?? agentTitle
    }

    /// Sets the user's own title; an empty one goes back to the automatic title.
    func rename(_ key: Key, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        userTitles[key.storageKey] = title.isEmpty ? nil : title
        UserDefaults.standard.set(userTitles, forKey: Self.userKey)
    }

    /// Names the session from its first prompt, unless it already has a title of Native's or the
    /// user's. Call it when the first prompt is sent.
    func generateIfNeeded(for key: Key, request: TitleRequest, using titler: (any SessionTitler)?) async {
        guard let titler,
              userTitles[key.storageKey] == nil,
              generatedTitles[key.storageKey] == nil,
              generating.insert(key).inserted
        else { return }
        defer { generating.remove(key) }
        do {
            guard let title = try await titler.title(for: request) else { return }
            generatedTitles[key.storageKey] = title
            UserDefaults.standard.set(generatedTitles, forKey: Self.generatedKey)
        } catch {
            logger.error("Couldn't title session \(key.storageKey, privacy: .public): \(error)")
        }
    }
}
