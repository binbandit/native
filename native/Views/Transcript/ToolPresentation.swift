import ACP
import Foundation

/// How a tool call reads as a single transcript row, modeled on the reference app's tool rows: a verb in
/// secondary text, the subject after it in tertiary, a per-tool icon, and per-tool failure wording.
/// The verb's tense follows the call: "Reading" while it runs, "Read" once it's done.
///
/// Claude Code names its tools (`call.name`), so known tools get tailored rows; other agents fall
/// back to the ACP kind and the agent's own title.
struct ToolPresentation {
    enum SubjectStyle {
        /// Tertiary after a verb, secondary when it stands alone.
        case plain
        /// A shell command shown as the subject.
        case command
        /// A file name in a filled chip, with line stats when known.
        case chip
        /// Primary text, for rows that summarize work (subagents, plan updates).
        case emphasized
    }

    enum Body {
        /// Content blocks as the agent sent them, or the raw input when there are none.
        case generic
        /// A shell command and its output.
        case command(String)
        /// Plain output lines, like search results; Markdown would join them into one paragraph.
        case lines
        /// MCP input and output, split by a hairline.
        case mcp
        /// The file diffs of an edit.
        case diff
    }

    var symbol: String
    var verbs: ToolVerb?
    var subject: String
    var subtitle: String?
    var subjectStyle = SubjectStyle.plain
    var stats: DiffStats?
    var failureLabel = "Error"
    var body = Body.generic
    /// Subagent rows show their own status in place of the tool icon.
    var showsStatusIcon = false
    /// Where the call is, which picks the verb's tense.
    var phase = ToolPhase.completed

    var verb: String? {
        verbs?.form(for: phase)
    }
}

/// A tool's verb in each tense a row needs: "Edit 3 lines" waiting for approval, "Editing 3 lines"
/// while it runs, "Edited 3 lines" once it's done.
struct ToolVerb {
    var base: String
    var progressive: String
    var past: String

    func form(for phase: ToolPhase) -> String {
        switch phase {
        case .running: progressive
        case .completed: past
        // Not done: the row names what was asked, and the trailing label says what happened.
        case .awaitingApproval, .failed, .cancelled: base
        }
    }

    /// The same verb with an object or preposition after it in every tense: "Read" + "for".
    func appending(_ words: String) -> ToolVerb {
        ToolVerb(base: "\(base) \(words)", progressive: "\(progressive) \(words)", past: "\(past) \(words)")
    }

    static let read = ToolVerb(base: "Read", progressive: "Reading", past: "Read")
    static let edit = ToolVerb(base: "Edit", progressive: "Editing", past: "Edited")
    static let write = ToolVerb(base: "Write", progressive: "Writing", past: "Wrote")
    static let delete = ToolVerb(base: "Delete", progressive: "Deleting", past: "Deleted")
    static let grep = ToolVerb(base: "Grep for", progressive: "Grepping for", past: "Grepped for")
    static let search = ToolVerb(base: "Search", progressive: "Searching", past: "Searched")
}

extension ToolPresentation {
    init(_ call: ToolCallState) {
        self.init(describing: call)
        phase = ToolPhase(call)
    }

    private init(describing call: ToolCallState) {
        let input = call.rawInput
        let name = call.name ?? ""

        if let mcp = MCPToolName(name) {
            self.init(symbol: "puzzlepiece.extension", subject: mcp.tool.titleCased, subtitle: mcp.server.humanized, body: .mcp)
            return
        }

        switch name {
        case "Read":
            self.init(symbol: "book", verbs: .read, subject: Self.readSubject(input) ?? call.title.dropping(prefix: "Read "))
        case "Edit", "MultiEdit", "Write", "NotebookEdit":
            self = .fileChange(call)
        case "Bash":
            let command = input?["command"]?.stringValue
            if let description = input?["description"]?.stringValue, !description.isEmpty {
                self.init(symbol: "terminal", subject: description.capitalizingFirstLetter)
            } else {
                self.init(symbol: "terminal", subject: command ?? call.title, subjectStyle: command == nil ? .plain : .command)
            }
            failureLabel = "Command failed"
            body = .command(command ?? call.title)
        case "Grep":
            let pattern = input?["pattern"]?.stringValue.map { "\"\($0)\"" }
            self.init(symbol: "magnifyingglass", verbs: .grep, subject: Self.join(pattern, in: input?["path"]?.stringValue) ?? call.title, body: .lines)
        case "Glob":
            let pattern = input?["pattern"]?.stringValue
            self.init(symbol: "doc.text.magnifyingglass", verbs: ToolVerb.search.appending("files for"), subject: Self.join(pattern, in: input?["path"]?.stringValue) ?? call.title, body: .lines)
        case "WebSearch":
            let query = input?["query"]?.stringValue.map { "\"\($0)\"" }
            self.init(symbol: "globe", verbs: ToolVerb.search.appending("the web for"), subject: query ?? call.title)
        case "WebFetch":
            self.init(symbol: "globe", subject: "Fetch Content", subtitle: input?["url"]?.stringValue)
        case "Task", "Agent":
            let description = input?["description"]?.stringValue ?? call.title
            self.init(symbol: "sparkles", subject: description, subjectStyle: .emphasized)
            showsStatusIcon = true
        case "TodoWrite":
            self.init(symbol: "checklist", subject: "Updated plan", subjectStyle: .emphasized)
        default:
            self = .byKind(call)
        }
    }

    private static func fileChange(_ call: ToolCallState) -> ToolPresentation {
        let diffs = call.content.compactMap { content -> FileDiff? in
            if case .diff(let diff) = content { diff } else { nil }
        }
        let stats = diffs.reduce(DiffStats()) { $0 + $1.stats }
        let isNewFile = diffs.first.map { $0.oldText == nil } ?? (call.name == "Write")
        let verb = isNewFile ? ToolVerb.write : .edit
        let lines = stats.added + stats.removed
        let path = diffs.first?.path ?? call.rawInput?["file_path"]?.stringValue ?? call.locations.first?.path
        return ToolPresentation(
            symbol: isNewFile ? "doc.badge.plus" : "pencil.line",
            verbs: verb.appending(lines > 0 ? "\(lines) \(lines == 1 ? "line" : "lines")" : "file"),
            subject: path.map { ($0 as NSString).lastPathComponent } ?? call.title,
            subjectStyle: path == nil ? .plain : .chip,
            stats: lines > 0 ? stats : nil,
            failureLabel: isNewFile ? "Error writing file" : "Error editing file",
            body: .diff
        )
    }

    private static func byKind(_ call: ToolCallState) -> ToolPresentation {
        let title = call.title
        return switch call.kind {
        case .read: ToolPresentation(symbol: "book", verbs: .read, subject: title.dropping(prefix: "Read "))
        case .edit: fileChange(call)
        case .delete: ToolPresentation(symbol: "trash", verbs: .delete, subject: title.dropping(prefix: "Delete "))
        case .move: ToolPresentation(symbol: "arrow.right.doc.on.clipboard", subject: title)
        case .search: ToolPresentation(symbol: "magnifyingglass", subject: title, body: .lines)
        case .execute: ToolPresentation(symbol: "terminal", subject: title, subjectStyle: .command, failureLabel: "Command failed", body: .command(title))
        case .think: ToolPresentation(symbol: "brain", subject: title)
        case .fetch: ToolPresentation(symbol: "globe", subject: title)
        case .switchMode: ToolPresentation(symbol: "arrow.triangle.branch", subject: title)
        case .other: ToolPresentation(symbol: "doc", subject: call.name.map(\.humanized) ?? title)
        }
    }

    /// `notes.txt, lines 10-59`: the last path segments, then the range when the read is partial.
    private static func readSubject(_ input: JSONValue?) -> String? {
        guard let path = input?["file_path"]?.stringValue else { return nil }
        let offset = input?["offset"]?.intValue
        var parts = [path.abbreviatedPath]
        if let limit = input?["limit"]?.intValue, limit > 0 {
            let start = offset ?? 1
            parts.append("lines \(start)-\(start + limit - 1)")
        } else if let offset {
            parts.append("from line \(offset)")
        }
        return parts.joined(separator: ", ")
    }

    private static func join(_ pattern: String?, in path: String?) -> String? {
        guard let pattern else { return nil }
        guard let path, !path.isEmpty else { return pattern }
        return "\(pattern) in \(path.abbreviatedPath)"
    }
}

/// Claude Code names MCP tools `mcp__<server>__<tool>`: the server runs to the next `__` and the
/// tool is the rest.
private struct MCPToolName {
    let server: String
    let tool: String

    init?(_ name: String) {
        guard name.hasPrefix("mcp__") else { return nil }
        let rest = name.dropFirst("mcp__".count)
        guard let separator = rest.range(of: "__"), separator.lowerBound > rest.startIndex else { return nil }
        let tool = rest[separator.upperBound...]
        guard !tool.isEmpty else { return nil }
        server = String(rest[..<separator.lowerBound])
        self.tool = String(tool)
    }
}

private extension JSONValue {
    var intValue: Int? {
        guard case .number(let number) = self else { return nil }
        return Int(exactly: number)
    }
}

private extension String {
    /// `fetch_pull-requestDetails` -> `fetch pull request Details`.
    var humanized: String {
        var words: [String] = []
        var current = ""
        for character in self {
            if character == "_" || character == "-" || character == " " {
                if !current.isEmpty { words.append(current) }
                current = ""
            } else if character.isUppercase, let last = current.last, last.isLowercase || last.isNumber {
                words.append(current)
                current = String(character)
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words.joined(separator: " ")
    }

    /// `search_issues` -> `Search Issues`; acronyms stay upper case.
    var titleCased: String {
        humanized.split(separator: " ").map { word in
            word.allSatisfy { $0.isUppercase || $0.isNumber } ? String(word) : word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }
        .joined(separator: " ")
    }

    var capitalizingFirstLetter: String {
        prefix(1).uppercased() + dropFirst()
    }

    /// Keeps the last three path segments: `/a/b/c/d/e.swift` -> `…/c/d/e.swift`.
    var abbreviatedPath: String {
        let segments = split(separator: "/", omittingEmptySubsequences: false)
        return segments.count > 3 ? "…/" + segments.suffix(3).joined(separator: "/") : self
    }

    func dropping(prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
