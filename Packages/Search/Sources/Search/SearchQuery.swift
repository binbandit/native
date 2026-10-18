import Foundation

/// What to look for: plain text as the user typed it, plus filters.
public struct SearchQuery: Hashable, Sendable, Codable {
    /// Plain words, `"quoted phrases"` and operators (`agent:codex`, `project:native`, `role:user`,
    /// `has:diff`, `is:archived`, `after:2026-01-31`, `before:2026-02-28`). Everything else, symbols
    /// included, is text: `AppModel.swift` and `git rebase -i` search as written.
    public var text: String
    public var filters: SearchFilters
    /// How many tasks to return at most, and how many hits each shows.
    public var limit: Int
    public var hitsPerSession: Int

    public init(_ text: String, filters: SearchFilters = SearchFilters(), limit: Int = 50, hitsPerSession: Int = 3) {
        self.text = text
        self.filters = filters
        self.limit = limit
        self.hitsPerSession = hitsPerSession
    }
}

/// Narrows a search. Empty sets mean "any".
public struct SearchFilters: Hashable, Sendable, Codable {
    /// Agent ids; `agent:` operators match ids containing the text.
    public var agents: Set<String> = []
    /// Project folders, as `SearchSessionRecord.project`.
    public var projects: Set<String> = []
    public var roles: Set<SearchRole> = []
    public var after: Date?
    public var before: Date?
    /// Only tool calls that changed files.
    public var hasDiff = false
    /// Archived tasks are left out unless this is on.
    public var includeArchived = false
    /// Reasoning is left out unless this is on (or `role:thinking` asks for it).
    public var includeThinking = false

    public init(
        agents: Set<String> = [], projects: Set<String> = [], roles: Set<SearchRole> = [], after: Date? = nil,
        before: Date? = nil, hasDiff: Bool = false, includeArchived: Bool = false, includeThinking: Bool = false
    ) {
        self.agents = agents
        self.projects = projects
        self.roles = roles
        self.after = after
        self.before = before
        self.hasDiff = hasDiff
        self.includeArchived = includeArchived
        self.includeThinking = includeThinking
    }

    public var isEmpty: Bool {
        self == SearchFilters()
    }
}

/// A query taken apart: the FTS5 expression for its text, and its operators folded into filters.
public struct ParsedSearchQuery: Hashable, Sendable {
    /// One word or phrase to match. Every term must match (AND).
    public struct Term: Hashable, Sendable {
        public var words: [String]
        /// The last word is still being typed, so it matches as a prefix.
        public var isPrefix: Bool
    }

    public var terms: [Term] = []
    public var filters: SearchFilters
    /// Text from `agent:` and `project:` operators, matched as parts of agent ids and project paths.
    public var agentNames: [String] = []
    public var projectNames: [String] = []

    /// Parses `query.text`, adding its operators to `query.filters`.
    public init(_ query: SearchQuery) {
        filters = query.filters
        let tokens = Self.tokens(of: query.text)
        let endsMidWord = query.text.last.map { !$0.isWhitespace && $0 != "\"" } ?? false
        for (offset, token) in tokens.enumerated() {
            if !token.isQuoted, apply(operator: token.text) { continue }
            let words = SearchText.words(in: token.text)
            guard !words.isEmpty else { continue }
            let isLast = offset == tokens.count - 1
            // A one-letter prefix matches half the index; it waits for the next letter.
            let isPrefix = isLast && endsMidWord && !token.isQuoted && (words.last?.count ?? 0) > 1
            terms.append(Term(words: words, isPrefix: isPrefix))
        }
    }

    /// The FTS5 MATCH expression, or nil when there's no text to match (only filters).
    public var expression: String? {
        guard !terms.isEmpty else { return nil }
        // Words hold only letters and digits, so quoting them can't break the expression.
        return terms.map { "\"\($0.words.joined(separator: " "))\"" + ($0.isPrefix ? "*" : "") }
            .joined(separator: " ")
    }

    /// Every word to highlight in snippets.
    public var highlightWords: [String] {
        Array(Set(terms.flatMap(\.words))).sorted { $0.count > $1.count }
    }

    private struct Token {
        var text: String
        var isQuoted: Bool
    }

    private static func tokens(of text: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var isQuoted = false
        for character in text {
            if character == "\"" {
                if !current.isEmpty || isQuoted {
                    tokens.append(Token(text: current, isQuoted: isQuoted))
                }
                current = ""
                isQuoted.toggle()
            } else if character.isWhitespace && !isQuoted {
                if !current.isEmpty {
                    tokens.append(Token(text: current, isQuoted: false))
                }
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty {
            tokens.append(Token(text: current, isQuoted: isQuoted))
        }
        return tokens
    }

    /// Folds `token` into the filters when it's an operator Native knows; anything else is text.
    private mutating func apply(operator token: String) -> Bool {
        guard let colon = token.firstIndex(of: ":") else { return false }
        let key = token[..<colon].lowercased()
        let value = String(token[token.index(after: colon)...])
        guard !value.isEmpty else { return false }
        switch (key, value.lowercased()) {
        case ("agent", let agent):
            agentNames.append(agent)
        case ("is", "archived"), ("in", "archived"):
            filters.includeArchived = true
        case ("project", let project), ("in", let project):
            projectNames.append(project)
        case ("role", let role):
            guard let role = Self.role(named: role) else { return false }
            filters.roles.insert(role)
            if role == .thought {
                filters.includeThinking = true
            }
        case ("has", "diff"), ("has", "diffs"), ("has", "changes"):
            filters.hasDiff = true
        case ("after", _), ("since", _):
            guard let date = Self.day(value) else { return false }
            filters.after = date
        case ("before", _), ("until", _):
            guard let date = Self.day(value) else { return false }
            filters.before = date
        default:
            return false
        }
        return true
    }

    private static func role(named name: String) -> SearchRole? {
        switch name {
        case "user", "you", "me", "prompt", "prompts": .user
        case "agent", "assistant", "reply", "replies": .agent
        case "thinking", "thought", "thoughts", "reasoning": .thought
        case "tool", "tools", "command", "commands": .tool
        case "plan": .plan
        case "title", "task": .title
        default: nil
        }
    }

    private static func day(_ text: String) -> Date? {
        try? Date(text, strategy: Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }
}
