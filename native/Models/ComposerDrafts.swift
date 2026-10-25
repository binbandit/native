import Foundation

/// What each task's composer holds, kept across launches: quitting, an update, a reinstall or a
/// crash never loses a message being written. Text only; attachments stay with this run
/// (`SessionStore`).
@MainActor
final class ComposerDrafts {
    private var drafts: [SessionKey: String]
    private let defaults: UserDefaults
    private var pendingSave: Task<Void, Never>?
    private static let key = "composerDrafts"
    /// Typing saves after a pause rather than on every key.
    private static let saveDelay = Duration.milliseconds(300)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        drafts =
            defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([SessionKey: String].self, from: $0) }
            ?? [:]
    }

    func draft(for session: SessionKey) -> String? {
        drafts[session]
    }

    /// Notes what the session's composer holds now; blank forgets it.
    func keep(_ text: String, for session: SessionKey) {
        let kept = text.allSatisfy(\.isWhitespace) ? nil : text
        guard drafts[session] != kept else { return }
        drafts[session] = kept
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Writes what's still waiting for a pause in typing, for when Native quits.
    func save() {
        pendingSave?.cancel()
        pendingSave = nil
        defaults.set(try? JSONEncoder().encode(drafts), forKey: Self.key)
    }
}
