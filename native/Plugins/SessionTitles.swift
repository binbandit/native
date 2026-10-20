import ACP
import Foundation
import Observation
import SessionTitling
import os

/// The titles Native shows for sessions. A title the user typed wins; then one generated from the
/// first prompt, so every agent's sessions read the same way and are named the moment they start;
/// then whatever the agent called it, which never replaces either of those, including when a
/// reopened session's agent reports its own (`SessionTitleRules`).
///
/// Tasks in Native's host get their titles there (`HostTitles`): this mirrors them, sends the
/// user's renames back, and leaves generating them to the host (SessionTitles+Host.swift).
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
    /// Tasks a host couldn't title yet, named from their first message meanwhile.
    private var fallbackTitles: [String: String]
    private var generating: Set<Key> = []
    @ObservationIgnored private var configChoices: [String: ConfigChoices]
    private let logger = Logger(subsystem: "Native", category: "Titles")

    // What SessionTitles+Host.swift keeps about tasks in hosts. Internal only for that file.
    /// Where each task in a host lives, for sending renames there.
    @ObservationIgnored var hostLinks: [Key: HostTitleLink] = [:]
    /// Renames on their way to a host, which keep its older title from coming back meanwhile.
    @ObservationIgnored var renamesInFlight: [Key: Int] = [:]
    /// Renames a host hasn't confirmed, sent again when it's back.
    @ObservationIgnored var unsyncedRenames: Set<Key> = []
    /// Generated titles this app wrote for a host, or handed one it lacked: once a run each.
    @ObservationIgnored var writtenForHosts: Set<Key> = []
    /// Tasks whose title the workspace has heard this run.
    @ObservationIgnored var landedTitles: Set<Key> = []
    /// The titler plugins provide now, and who hears that a task's title landed.
    @ObservationIgnored var hostTitler: () -> (any SessionTitler)? = { nil }
    @ObservationIgnored var titleLanded: (Key, URL, String) -> Void = { _, _, _ in }

    private static let userKey = "sessionTitles.user"
    private static let generatedKey = "sessionTitles.generated"
    private static let fallbackKey = "sessionTitles.fallback"
    private static let configChoicesKey = "sessionConfigChoices"

    init() {
        let defaults = UserDefaults.standard
        userTitles = defaults.dictionary(forKey: Self.userKey) as? [String: String] ?? [:]
        generatedTitles = defaults.dictionary(forKey: Self.generatedKey) as? [String: String] ?? [:]
        fallbackTitles = defaults.dictionary(forKey: Self.fallbackKey) as? [String: String] ?? [:]
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
        SessionTitleRules.display(
            user: userTitles[key.storageKey], generated: generatedTitles[key.storageKey], agent: agentTitle,
            fallback: fallbackTitles[key.storageKey])
    }

    /// The title the user typed, if any, so a rename can be undone back to exactly what was there.
    func userTitle(for key: Key) -> String? {
        userTitles[key.storageKey]
    }

    /// The title generated from the first prompt, if any.
    func generatedTitle(for key: Key) -> String? {
        generatedTitles[key.storageKey]
    }

    /// Sets the user's own title; an empty one goes back to the automatic title. A task in a host
    /// gets it there too.
    func rename(_ key: Key, to title: String) {
        setUserTitle(SessionTitleRules.userTitle(title), for: key)
        sendRename(key)
    }

    /// Names the session from its first prompt, unless it already has a title of Native's or the
    /// user's. Call it when the first prompt is sent. A task in a host is titled there.
    func generateIfNeeded(for key: Key, request: TitleRequest, using titler: (any SessionTitler)?) async {
        guard let titler, !isTitledByHost(key),
            userTitles[key.storageKey] == nil,
            generatedTitles[key.storageKey] == nil,
            generating.insert(key).inserted
        else { return }
        defer { generating.remove(key) }
        do {
            guard let title = try await titler.title(for: request) else { return }
            setGeneratedTitle(title, for: key)
        } catch {
            logger.error("Couldn't title session \(key.storageKey, privacy: .public): \(error)")
        }
    }

    // MARK: - Storing

    /// Sets (or with nil clears) the user's title, saving it.
    func setUserTitle(_ title: String?, for key: Key) {
        guard userTitles[key.storageKey] != title else { return }
        userTitles[key.storageKey] = title
        UserDefaults.standard.set(userTitles, forKey: Self.userKey)
    }

    func setGeneratedTitle(_ title: String?, for key: Key) {
        guard generatedTitles[key.storageKey] != title else { return }
        generatedTitles[key.storageKey] = title
        UserDefaults.standard.set(generatedTitles, forKey: Self.generatedKey)
    }

    func setFallbackTitle(_ title: String?, for key: Key) {
        guard fallbackTitles[key.storageKey] != title else { return }
        fallbackTitles[key.storageKey] = title
        UserDefaults.standard.set(fallbackTitles, forKey: Self.fallbackKey)
    }
}
