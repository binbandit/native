import Foundation

extension SessionTitleRules {
    /// A title with no distinguishing subject can be refined from the first turn's outcome.
    public static func isWeak(_ title: String, projectName: String = "") -> Bool {
        let words = title.lowercased().split(whereSeparator: \.isWhitespace).map { core(of: String($0)) }
        guard (2...6).contains(words.count), SessionTitleInput.isSafeTitle(title) else { return true }
        if filler.contains(where: { title.lowercased().hasPrefix($0) }) { return true }
        let generic: Set<String> = [
            "fix", "fixing", "the", "a", "an", "in", "on", "for", "to", "and", "with", "of", "it", "this",
            "that", "again", "please", "help", "build", "test", "tests", "bug", "issue", "task", "request",
            "update", "improve", "add", "change", "code", "work", "stuff", "thing", "things", "project", "feature",
            "component",
            "run", "shell", "command", "refactor", "review", "inspect", "investigate", "explain", "create",
            "implement", "docs", "documentation", "performance", "memory", "leak", "crash",
            "failing", "failure", "failures", "broken", "flaky",
            projectName.lowercased(),
        ]
        return words.allSatisfy { generic.contains($0) }
    }

    /// Preserve the subject at the end of a verbose model answer rather than substituting the
    /// first six words of the original request, which often omits the very thing being changed.
    static func compact(_ title: String) -> String {
        var words = title.split(whereSeparator: \.isWhitespace).map(String.init)
        for group: Set<String> in [
            ["the", "a", "an", "please"],
            ["in", "on", "for", "to", "with", "of", "from", "after", "before", "when", "by"],
        ] {
            if words.count > 6 { words.removeAll { group.contains($0.lowercased()) } }
        }

        return words.joined(separator: " ")
    }

    static func restoringNames(in title: String, from source: String) -> String {
        var names: [String: String] = [:]
        for word in source.split(whereSeparator: \.isWhitespace) {
            let name = core(of: String(word))
            if knownNames.contains(name) || (Shape(name) == .other && name.contains(where: \.isUppercase)) {
                names[name.lowercased()] = name
            }
        }
        return title.split(separator: " ").map { word in
            let text = String(word)
            let name = core(of: text)
            guard let original = names[name.lowercased()], let range = text.range(of: name) else { return text }
            return text.replacingCharacters(in: range, with: original)
        }.joined(separator: " ")
    }

    /// A follow-up without its earlier conversation cannot honestly name the subject yet.
    public static func needsOutcome(_ prompt: String, projectName: String = "") -> Bool {
        (prompt.split(whereSeparator: \.isWhitespace).count <= 6 && isWeak(prompt, projectName: projectName))
            || prompt.range(
                of: #"(?i)^\s*(?:same (?:thing|as)|again\b|continue\b|do (?:that|it)\b|try again\b)"#,
                options: .regularExpression) != nil
    }

    static let filler = ["help with", "task to", "request for", "fix issue", "task:", "title:"]

    /// Enforce the same format on every provider. Invalid model output falls back to the request
    /// rather than displaying a path, credential, or a long sentence in the sidebar.
    public static func automatic(_ text: String, from request: SessionTitleRequest) -> String? {
        guard let cleaned = cleaned(text) else { return nil }
        guard SessionTitleInput.isSafeTitle(cleaned) else {
            return fallback(from: request.firstTurnOutcome ?? request.prompt)
        }
        let source = request.prompt + "\n" + (request.firstTurnOutcome ?? "")
        let title = restoringNames(in: sentenceCase(compact(cleaned), keeping: source), from: source)
        let words = title.split(whereSeparator: \.isWhitespace)
        guard (2...6).contains(words.count), !filler.contains(where: { title.lowercased().hasPrefix($0) }) else {
            return fallback(from: request.firstTurnOutcome ?? request.prompt)
        }
        return title
    }
}
