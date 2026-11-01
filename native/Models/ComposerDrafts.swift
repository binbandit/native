import ACP
import Foundation
import NativePolicy

/// What each task's composer holds, kept across launches: quitting, an update, a reinstall or a
/// crash never loses a message being written. Text only; attachments stay with this run
/// (`SessionStore`).
@MainActor
final class ComposerDrafts {
    private var comments: [SessionKey: [PromptQuote]] = [:]
    private var deliveries: [SessionKey: String] = [:]
    private var drafts: [SessionKey: String]
    private let defaults: UserDefaults
    private var pendingSave: Task<Void, Never>?
    private static let key = "composerDrafts"
    /// Typing saves after a pause rather than on every key.
    private static let saveDelay = Duration.milliseconds(300)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        comments =
            defaults.data(forKey: "diffCommentEditors").flatMap {
                try? JSONDecoder().decode([SessionKey: [PromptQuote]].self, from: $0)
            } ?? [:]
        deliveries =
            defaults.data(forKey: "diffCommentDeliveries").flatMap {
                try? JSONDecoder().decode([SessionKey: String].self, from: $0)
            } ?? [:]
        drafts =
            defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([SessionKey: String].self, from: $0) }
            ?? [:]
    }

    func draft(for session: SessionKey) -> String? {
        drafts[session]
    }

    /// Notes what the session's composer holds now; blank forgets it.
    func keep(_ text: String, for session: SessionKey) {
        let parsed = PromptQuote.split(text)
        let retained =
            PolicyCenter.shared.policy.sourceExcerptsRetentionEnabled
            ? text : PromptQuote.draft(quotes: parsed.quotes.filter { $0.side == .transcript }, message: parsed.message)
        let kept = retained.allSatisfy(\.isWhitespace) ? nil : retained
        guard drafts[session] != kept else { return }
        drafts[session] = kept
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func commentEditors(for session: SessionKey) -> [PromptQuote] { comments[session] ?? [] }

    func keepCommentEditors(_ editors: [PromptQuote], for session: SessionKey) {
        comments[session] =
            editors.isEmpty || !PolicyCenter.shared.policy.sourceExcerptsRetentionEnabled ? nil : editors
        save()
    }

    func commentDelivery(for session: SessionKey) -> String? { deliveries[session] }

    func keepCommentDelivery(_ packet: String?, for session: SessionKey) {
        deliveries[session] = PolicyCenter.shared.policy.sourceExcerptsRetentionEnabled ? packet : nil
        save()
    }

    /// Writes what's still waiting for a pause in typing, for when Native quits.
    func save() {
        pendingSave?.cancel()
        pendingSave = nil
        if !PolicyCenter.shared.policy.sourceExcerptsRetentionEnabled {
            comments = [:]
            deliveries = [:]
            for (session, draft) in drafts {
                let current = PromptQuote.split(draft)
                drafts[session] = PromptQuote.draft(
                    quotes: current.quotes.filter { $0.side == .transcript }, message: current.message)
            }
        }
        defaults.set(try? JSONEncoder().encode(drafts), forKey: Self.key)
        defaults.set(try? JSONEncoder().encode(comments), forKey: "diffCommentEditors")
        defaults.set(try? JSONEncoder().encode(deliveries), forKey: "diffCommentDeliveries")
    }
}
