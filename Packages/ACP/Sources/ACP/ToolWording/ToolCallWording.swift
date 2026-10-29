import Foundation

/// What a client says about one tool call, as one plain sentence: a verb in the tense of where the
/// call is, then what it acts on. "Reading ToolRow.swift" while it runs, "Read ToolRow.swift" once
/// it's done, "Ran swift test" then "Exit 1".
///
/// The words come from what the call says it will do: Claude Code's tool name and input first,
/// then the ACP kind, locations and input, then the agent's own title. Never from the output, so a
/// row reads the same while it runs and after. Commands that only read or search say so ("Read
/// greet.py"), and Codex's code mode programs say the step they take. A call with no natural verb
/// (an MCP tool) is a label instead: "GitHub: Search issues".
public struct ToolCallWording: Hashable, Sendable {
    public var verb: ToolVerb?
    /// What the verb acts on (a file name, a command's first line, a quoted pattern), or the whole
    /// label when there's no verb.
    public var object: String
    /// The object is code (a file, a command, a pattern) rather than words.
    public var objectIsCode = false
    /// The longer form for a tooltip or a detail header: the whole path, the whole command, the URL,
    /// or the agent's own description of a command.
    public var detail: String?
    /// Lines an edit adds and removes, once it carries its diffs.
    public var lineChanges: LineChanges?
    public var category: ToolCategory
    /// The shell command the call runs, as the agent wrote it, when it runs one.
    public var command: String?
    /// The files a command read, for counting them once each.
    var files: [String] = []
    /// The folder a search ran in or a listing listed, as the agent named it, so a client that
    /// knows the task's folder can name it from there (`relative(to:)`).
    var folder: String?

    public struct LineChanges: Hashable, Sendable {
        public var added: Int
        public var removed: Int

        public init(added: Int, removed: Int) {
            self.added = added
            self.removed = removed
        }
    }

    public init(
        verb: ToolVerb? = nil, object: String, objectIsCode: Bool = false, detail: String? = nil,
        lineChanges: LineChanges? = nil, category: ToolCategory
    ) {
        self.verb = verb
        self.object = object
        self.objectIsCode = objectIsCode
        self.detail = detail
        self.lineChanges = lineChanges
        self.category = category
    }

    /// The same words with the folder a search or a listing names put relative to `root`, the
    /// task's own folder: a search of the whole project says no folder at all ("in my-project"
    /// tells the user nothing), one of a folder inside it names it from there ("in Sources/Views").
    public func relative(to root: String?) -> Self {
        guard let root, let folder, folder.hasPrefix("/") else { return self }
        let base = root.hasSuffix("/") ? String(root.dropLast()) : root
        let relative: String? =
            folder == base ? nil : folder.hasPrefix(base + "/") ? String(folder.dropFirst(base.count + 1)) : folder
        var wording = self
        if verb == .list {
            wording.object = relative ?? "files"
            wording.objectIsCode = relative != nil
        } else if object.hasSuffix(" in \(folder.fileName)") {
            wording.object =
                String(object.dropLast(" in \(folder.fileName)".count)) + (relative.map { " in \($0)" } ?? "")
        }
        return wording
    }

    /// The sentence for a call in `phase`. A command that ran and exited non-zero did run, so it
    /// keeps the past tense ("Ran swift test", then "Exit 1"); anything else that didn't happen names
    /// what was asked ("Edit notes.txt", then "Rejected").
    public func sentence(for phase: ToolPhase, exitCode: Int? = nil) -> String {
        guard let verb else { return object }
        let ran = phase == .failed && category == .command && (exitCode ?? 0) > 0
        return "\(verb.form(for: ran ? .completed : phase)) \(object)"
    }
}

extension ToolCallState {
    /// What to say about the call (`ToolCallWording`).
    public var wording: ToolCallWording {
        ToolCallWording(self)
    }

    /// The call's sentence where it is now: "Reading notes.txt", "Read notes.txt".
    public var sentence: String {
        wording.sentence(for: ToolPhase(self), exitCode: exitCode)
    }
}

extension ToolCallWording {
    init(_ call: ToolCallState) {
        let category = call.category
        if let mcp = call.mcpTool {
            // A call a script made through Native's run_script also says where in the script.
            let line = call.meta?["native"]?["script"]?["line"]?.intValue
            self.init(
                object: "\(mcp.server.titleCased): \(mcp.tool.sentenceCased)",
                detail: line.map { "\(mcp.rawName), script line \($0)" } ?? mcp.rawName, category: category)
        } else if let program = CodeModeProgram(call) {
            self = Self.codeMode(program, call: call)
        } else if call.isPolling {
            self = Self.waiting(call)
        } else if let wording = Self.claudeCode(call, category: category) {
            self = wording
        } else {
            self = Self.byKind(call, category: category)
        }
    }

    /// Claude Code's tools, by name.
    private static func claudeCode(_ call: ToolCallState, category: ToolCategory) -> Self? {
        let input = call.rawInput
        switch call.name {
        case "Read", "NotebookRead":
            let path =
                input?["file_path"]?.stringValue ?? input?["notebook_path"]?.stringValue
                ?? call.locations.first?.path
            guard let path else { return Self(verb: .read, object: "a file", category: category) }
            return Self(
                verb: .read, object: path.fileName + readRange(input), objectIsCode: true, detail: path,
                category: category)
        case "LS":
            let path = input?["path"]?.stringValue ?? call.locations.first?.path
            var wording = Self(
                verb: .list, object: path?.fileName ?? "a folder", objectIsCode: path != nil, detail: path,
                category: category)
            wording.folder = path
            return wording
        case "Edit", "MultiEdit", "Write", "NotebookEdit":
            return fileChange(call, category: category)
        case "Bash":
            return command(call, category: category)
        case "BashOutput":
            return Self(verb: .check, object: "a background command", category: category)
        case "KillShell", "KillBash":
            return Self(verb: .stop, object: "a background command", category: category)
        case "Grep":
            guard let pattern = input?["pattern"]?.stringValue else { return nil }
            return search(
                verb: ToolVerb.search.appending("for"), quoted(pattern), in: input?["path"]?.stringValue,
                detail: input?["path"]?.stringValue, category: category)
        case "Glob":
            guard let pattern = input?["pattern"]?.stringValue else { return nil }
            return search(
                verb: ToolVerb.search.appending("for files matching"), pattern, in: input?["path"]?.stringValue,
                detail: input?["path"]?.stringValue, category: category)
        case "WebSearch":
            guard let query = input?["query"]?.stringValue else { return nil }
            return Self(verb: ToolVerb.search.appending("the web for"), object: quoted(query), category: category)
        case "WebFetch":
            guard let url = input?["url"]?.stringValue else { return nil }
            return Self(verb: .fetch, object: url.urlHost, detail: url, category: category)
        case "Task", "Agent":
            let description = input?["description"]?.stringValue ?? call.title.meaningfulTitle
            return Self(
                verb: .delegate, object: description.map(quoted) ?? "to a subagent",
                detail: input?["subagent_type"]?.stringValue, category: category)
        case "TodoWrite":
            return Self(verb: .update, object: "the plan", category: category)
        case "ExitPlanMode":
            return Self(verb: .present, object: "a plan", category: category)
        case "EnterPlanMode":
            return Self(verb: .start, object: "planning", category: category)
        case "Skill":
            guard let skill = input?["skill"]?.stringValue ?? input?["command"]?.stringValue else { return nil }
            return Self(verb: .use, object: "the \(skill) skill", category: category)
        case "ToolSearch":
            return Self(verb: .lookUp, object: "tools", detail: input?["query"]?.stringValue, category: category)
        default:
            return nil
        }
    }

    /// Other agents: the ACP kind, refined by the title they send (codex-acp's shapes are noted).
    private static func byKind(_ call: ToolCallState, category: ToolCategory) -> Self {
        let title = call.title
        switch call.kind {
        // codex-acp: "Read file '/a/b/notes.txt'".
        case .read where title.hasPrefix("Read file '"):
            let path = call.locations.first?.path ?? title.dropping(prefix: "Read file '").dropping(suffix: "'")
            return Self(verb: .read, object: path.fileName, objectIsCode: true, detail: path, category: category)
        case .read where title.hasPrefix("Read "):
            let subject = title.dropping(prefix: "Read ")
            return Self(
                verb: .read, object: subject.fileName, objectIsCode: true, detail: subject, category: category)
        // codex-acp: "List files" and "List files in 'does-not-exist'".
        case .read where title.hasPrefix("List files in '"):
            let path = title.dropping(prefix: "List files in '").dropping(suffix: "'")
            return Self(verb: .list, object: path.fileName, objectIsCode: true, detail: path, category: category)
        case .read where title == "List files":
            return Self(verb: .list, object: "files", category: category)
        case .read:
            return Self(object: title.unquoted, category: category)
        case .edit:
            return fileChange(call, category: category)
        case .delete:
            let path = call.locations.first?.path ?? title.dropping(prefix: "Delete ")
            return Self(verb: .delete, object: path.fileName, objectIsCode: true, detail: path, category: category)
        case .move:
            let path = call.locations.first?.path
            return path.map {
                Self(verb: .move, object: $0.fileName, objectIsCode: true, detail: $0, category: category)
            }
                ?? Self(object: title, category: category)
        // codex-acp files web searches under `search`: "Web search: swift testing", or "Web search"
        // before it knows the query.
        case .search where title.hasPrefix("Web search: "):
            let query = title.dropping(prefix: "Web search: ")
            return Self(verb: ToolVerb.search.appending("the web for"), object: quoted(query), category: category)
        case .search where title == "Web search":
            return Self(verb: .search, object: "the web", category: category)
        case .search where title.hasPrefix("Open page: "):
            let url = title.dropping(prefix: "Open page: ")
            return Self(verb: .fetch, object: url.urlHost, detail: url, category: category)
        // codex-acp: "Search for 'def' in .".
        case .search where title.hasPrefix("Search for "):
            let subject = title.dropping(prefix: "Search for ").dropping(suffix: " in .").unquoted
            return Self(
                verb: ToolVerb.search.appending("for"), object: subject, objectIsCode: true, category: category)
        case .search:
            return Self(object: title, category: category)
        case .execute:
            return command(call, category: category)
        case .fetch:
            let url = call.rawInput?["url"]?.stringValue
            return url.map { Self(verb: .fetch, object: $0.urlHost, detail: $0, category: category) }
                ?? Self(object: title, category: category)
        case .think, .switchMode:
            return Self(object: title.meaningfulTitle ?? "Planned", category: category)
        case .other:
            // The agent's own words when it sent any, else the tool's name.
            if let title = title.meaningfulTitle {
                return Self(object: title, category: category)
            }
            if let name = call.name, !name.isEmpty {
                return Self(verb: .use, object: name.humanized, detail: name, category: category)
            }
            return Self(verb: .use, object: "a tool", category: category)
        }
    }

    /// A file change: what it does to which file, with the lines it adds and removes once its diffs
    /// arrive. A diff without old text creates the file.
    private static func fileChange(_ call: ToolCallState, category: ToolCategory) -> Self {
        let diffs = call.content.compactMap { content -> FileDiff? in
            if case .diff(let diff) = content { diff } else { nil }
        }
        let isNewFile = diffs.first.map { $0.oldText == nil } ?? false
        let verb: ToolVerb = isNewFile ? .create : call.name == "Write" ? .write : .edit
        let input = call.rawInput
        let path =
            diffs.first?.path ?? input?["file_path"]?.stringValue ?? input?["notebook_path"]?.stringValue
            ?? call.locations.first?.path ?? input?["path"]?.stringValue
        let files = Set(diffs.map(\.path)).count
        var object = path?.fileName ?? "a file"
        if files > 1 { object += " and \(files - 1) other \(files == 2 ? "file" : "files")" }
        let counts = diffs.reduce(into: LineChanges(added: 0, removed: 0)) { total, diff in
            total.added += diff.lineCounts.added
            total.removed += diff.lineCounts.removed
        }
        return Self(
            verb: verb, object: object, objectIsCode: path != nil, detail: path,
            lineChanges: diffs.isEmpty ? nil : counts, category: category)
    }

    /// `, lines 10-59` for a partial read, `, from line 120` for one with only an offset.
    private static func readRange(_ input: JSONValue?) -> String {
        let offset = input?["offset"]?.intValue
        if let limit = input?["limit"]?.intValue, limit > 0 {
            let start = offset ?? 1
            return ", lines \(start)-\(start + limit - 1)"
        }
        return offset.map { ", from line \($0)" } ?? ""
    }

    /// A search of `pattern`, then ` in Sources` when it names a folder other than the current one.
    static func search(
        verb: ToolVerb, _ pattern: String, in folder: String?, detail: String?, category: ToolCategory
    ) -> Self {
        let folder = folder.flatMap { $0.isEmpty || $0 == "." ? nil : $0 }
        var wording = Self(
            verb: verb, object: pattern + (folder.map { " in \($0.fileName)" } ?? ""), objectIsCode: true,
            detail: detail, category: category)
        wording.folder = folder
        return wording
    }

    static func quoted(_ text: String) -> String {
        "\"\(text)\""
    }
}

extension JSONValue {
    var intValue: Int? {
        guard case .number(let number) = self else { return nil }
        return Int(exactly: number)
    }
}
