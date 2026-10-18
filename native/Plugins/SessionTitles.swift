import ACP
import Foundation
import Observation
import os

/// The titles Native shows for sessions. A title the user typed wins; then one generated from the
/// first prompt, so every agent's sessions read the same way and are named the moment they start;
/// then whatever the agent called it, which never replaces either of those, including when a
/// reopened session's agent reports its own.
///
/// It also keeps the settings chosen for each session (`ConfigChoices`), the other thing Native
/// knows about a session that its agent may not give back on `session/load`.
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
    @ObservationIgnored private var configChoices: [String: ConfigChoices]
    private let logger = Logger(subsystem: "Native", category: "Titles")

    private static let userKey = "sessionTitles.user"
    private static let generatedKey = "sessionTitles.generated"
    private static let configChoicesKey = "sessionConfigChoices"

    init() {
        let defaults = UserDefaults.standard
        userTitles = defaults.dictionary(forKey: Self.userKey) as? [String: String] ?? [:]
        generatedTitles = defaults.dictionary(forKey: Self.generatedKey) as? [String: String] ?? [:]
        configChoices =
            defaults.data(forKey: Self.configChoicesKey)
            .flatMap { try? JSONDecoder().decode([String: ConfigChoices].self, from: $0) } ?? [:]
    }

    /// The settings chosen for the session so far.
    func configChoices(for key: Key) -> ConfigChoices {
        configChoices[key.storageKey] ?? ConfigChoices()
    }

    /// Changes the session's chosen settings, saving them if that changed anything.
    func updateConfigChoices(for key: Key, _ change: (inout ConfigChoices) -> Void) {
        var choices = configChoices(for: key)
        change(&choices)
        guard choices != configChoices(for: key) else { return }
        configChoices[key.storageKey] = choices.isEmpty ? nil : choices
        if let data = try? JSONEncoder().encode(configChoices) {
            UserDefaults.standard.set(data, forKey: Self.configChoicesKey)
        }
    }

    func title(for key: Key, agentTitle: String?) -> String? {
        userTitles[key.storageKey] ?? generatedTitles[key.storageKey] ?? agentTitle.flatMap(Self.meaningful)
    }

    /// Some agents name a session they haven't titled with a timestamp ("New session -
    /// 2026-10-17T14:19:55.251Z", from OpenCode). That says nothing the row's age doesn't, so it
    /// counts as no title.
    private static func meaningful(_ agentTitle: String) -> String? {
        agentTitle.wholeMatch(of: placeholderTitle) == nil ? agentTitle : nil
    }

    private nonisolated(unsafe) static let placeholderTitle =
        #/(?i)new session\s*[-–]\s*\d{4}-\d{2}-\d{2}T[\d:.]+Z?/#

    /// The title the user typed, if any, so a rename can be undone back to exactly what was there.
    func userTitle(for key: Key) -> String? {
        userTitles[key.storageKey]
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
