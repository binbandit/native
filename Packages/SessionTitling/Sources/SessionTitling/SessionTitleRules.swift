import Foundation

/// How Native picks and tidies a task's title, the same in the app and the host.
public enum SessionTitleRules {
    /// The most of a title that's kept, whoever wrote it.
    public static let maximumLength = 120

    /// The title to show: the user's, then the one generated from the first message, then
    /// whatever the agent called it (in sentence case, like Native's own), then the first message
    /// itself, so a task is never nameless while there's anything to name it by.
    public static func display(
        user: String?, generated: String?, agent: String?, fallback: String? = nil
    ) -> String? {
        user ?? generated ?? agent.flatMap(meaningful).map { sentenceCase($0) } ?? fallback
    }

    /// Some agents name a session they haven't titled with a timestamp ("New session -
    /// 2026-10-17T14:19:55.251Z", from OpenCode). That says nothing the row's age doesn't, so it
    /// counts as no title.
    public static func meaningful(_ agentTitle: String) -> String? {
        agentTitle.wholeMatch(of: placeholderTitle) == nil ? agentTitle : nil
    }

    private nonisolated(unsafe) static let placeholderTitle =
        #/(?i)new session\s*[-–]\s*\d{4}-\d{2}-\d{2}T[\d:.]+Z?/#

    /// A model's answer as a title: one line, trimmed of spaces and punctuation at either end, its
    /// first word capitalized (unless it's a name like "iOS"). Nil when nothing is left.
    public static func cleaned(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let title = String(
            line.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                .prefix(maximumLength))
        guard !title.isEmpty else { return nil }
        let firstWord = title.prefix { $0 != " " }
        return capitalized(String(firstWord)) + title.dropFirst(firstWord.count)
    }

    /// A title the user typed: trimmed, and nil when empty (which means "use the automatic one").
    public static func userTitle(_ text: String?) -> String? {
        let title = String(
            (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumLength))
        return title.isEmpty ? nil : title
    }

    /// The most words a title taken from the first message keeps.
    static let fallbackWords = 8

    /// A title made from the first message itself, for when no model can write one: its first line,
    /// cut after a few words. Nil when the message has no words.
    public static func fallback(from prompt: String) -> String? {
        guard
            let line = prompt.split(whereSeparator: \.isNewline).lazy
                .map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty })
        else { return nil }
        let words = line.split(whereSeparator: \.isWhitespace)
        guard let title = cleaned(words.prefix(fallbackWords).joined(separator: " ")) else { return nil }
        return words.count > fallbackWords ? title + "…" : title
    }
}
