import ACP
import Foundation

/// New sessions the user started here that haven't had a message yet, and the draft each was left
/// with at quit, kept across launches. Their agents never saved them, so there's nothing to reopen:
/// at the next launch an empty one leaves the sidebar, and one left with a draft stays, labelled as a
/// draft, until it's opened and the draft carries on in a fresh session.
@MainActor
final class UnsentSessions {
    /// Each session's draft by key ("agent/session"), empty for none yet.
    private var drafts: [String: String] {
        didSet { defaults.set(drafts, forKey: Self.key) }
    }
    /// Sessions being reopened, so a second load of the same one doesn't start another.
    private var claimed: Set<String> = []
    private let defaults: UserDefaults
    private static let key = "unsentSessions"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        drafts = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }

    /// A new session the user just started.
    func started(_ session: SessionKey) {
        drafts[Self.id(session)] = ""
    }

    /// The session got its first message, so its agent keeps it from now on.
    func sent(_ session: SessionKey) {
        guard drafts[Self.id(session)] != nil else { return }
        drafts[Self.id(session)] = nil
    }

    func contains(_ session: SessionKey) -> Bool {
        drafts[Self.id(session)] != nil
    }

    /// What the user wrote in it before quitting, if anything.
    func draft(for session: SessionKey) -> String? {
        drafts[Self.id(session)].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The draft of a session to reopen, unless it's being reopened already. `release` it if that
    /// fails; `forget` it once a fresh session took its place.
    func claim(_ session: SessionKey) -> String? {
        guard let draft = draft(for: session), claimed.insert(Self.id(session)).inserted else { return nil }
        return draft
    }

    func release(_ session: SessionKey) {
        claimed.remove(Self.id(session))
    }

    /// Forgets a session that a fresh one replaced.
    func forget(_ session: SessionKey) {
        claimed.remove(Self.id(session))
        drafts[Self.id(session)] = nil
    }

    /// Notes what each session still unsent has in its composer, for when Native quits. `draft` is
    /// nil for one that isn't open, which keeps what it had.
    func keepDrafts(_ draft: (SessionKey) -> String?) {
        var kept = drafts
        for id in drafts.keys {
            guard let key = Self.key(id), let text = draft(key) else { continue }
            kept[id] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        drafts = kept
    }

    /// Forgets the sessions `drop` says to, returning their keys.
    func removeAll(where drop: (SessionKey, _ draft: String?) -> Bool) -> [SessionKey] {
        let dropped = drafts.compactMap { id, draft in
            Self.key(id).flatMap { drop($0, draft.isEmpty ? nil : draft) ? $0 : nil }
        }
        guard !dropped.isEmpty else { return [] }
        for key in dropped {
            drafts[Self.id(key)] = nil
        }
        return dropped
    }

    private static func id(_ key: SessionKey) -> String {
        "\(key.agent.rawValue)/\(key.id.rawValue)"
    }

    private static func key(_ id: String) -> SessionKey? {
        guard let slash = id.firstIndex(of: "/") else { return nil }
        return SessionKey(
            agent: AgentDefinition.ID(rawValue: String(id[..<slash])),
            id: SessionID(String(id[id.index(after: slash)...])))
    }
}
