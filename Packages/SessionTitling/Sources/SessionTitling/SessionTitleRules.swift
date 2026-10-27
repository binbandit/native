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
        user ?? generated ?? agent.flatMap(meaningful).flatMap {
            SessionTitleInput.isSafeTitle($0) ? sentenceCase($0) : nil
        } ?? fallback
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

    /// A quick local name while a provider is busy or unavailable. Prefer the actual request
    /// following a pasted log, strip conversational preambles, and keep six words at most.
    public static func fallback(from prompt: String) -> String? {
        let safe = SessionTitleInput.prepared(prompt)
        let lines = safe.split(whereSeparator: \.isNewline).map(String.init)
        guard !lines.isEmpty else { return nil }
        let actions =
            #"(?i)^(?:(?:can|could|would) you |please |first |then )*(?:fix|add|make|update|remove|stop|handle|return|refactor|write|improve|compress|keep|explain|why|is |review|ignore|the script)\b"#
        var line = lines.last(where: { $0.range(of: actions, options: .regularExpression) != nil }) ?? lines[0]
        for pattern in [
            #"(?i)^(?:can|could|would) you (?:please )?(?:help (?:me |with )?)?"#,
            #"(?i)^(?:please |help (?:me |with )|first )+"#,
            #"(?i)^(?:task to |request for |title: |help with )"#,
        ] { line = line.replacingOccurrences(of: pattern, with: "", options: .regularExpression) }
        line = line.replacingOccurrences(of: #"\[(?:path|link)\]"#, with: "", options: .regularExpression)
        var words = Array(line.split(whereSeparator: \.isWhitespace).prefix(6))
        let endings: Set<String> = [
            "a", "an", "the", "in", "on", "for", "to", "with", "of", "after", "before", "when", "so", "it", "and",
        ]
        while words.last.map({ endings.contains($0.lowercased()) }) == true { words.removeLast() }
        return cleaned(words.joined(separator: " ")).map { sentenceCase($0, keeping: safe) }
    }
}
