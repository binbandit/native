import Foundation

// What commands say: shell commands, Codex's code mode programs and the polling between them.
extension ToolCallWording {
    /// A shell command: what it reads or searches when that's all it does, else its first line
    /// without the shell or the `cd` into a folder that agents wrap it in. Claude Code's description
    /// of the command goes in the detail.
    static func command(_ call: ToolCallState, category: ToolCategory) -> Self {
        let description = call.rawInput?["description"]?.stringValue
        guard let command = call.shellCommand ?? call.title.meaningfulTitle else {
            return Self(verb: .run, object: "a command", detail: description, category: category)
        }
        return commandLine(command, description: description, category: category)
    }

    static func commandLine(_ command: String, description: String?, category: ToolCategory) -> Self {
        var wording = intent(of: command, description: description, category: category)
        wording.command = command
        return wording
    }

    private static func intent(of command: String, description: String?, category: ToolCategory) -> Self {
        let line = ToolCommandLine(command).display
        let detail = description ?? (line == command ? nil : command)
        switch ToolCommandIntent(line) {
        case .read(let paths, let lines)?:
            let names = paths.map(\.fileName)
            let object =
                names.count > 2 ? "\(names[0]) and \(names.count - 1) other files" : names.joined(separator: " and ")
            var wording = Self(
                verb: .read, object: object + (lines.map { ", lines \($0)" } ?? ""), objectIsCode: true,
                detail: detail ?? command, category: .read)
            wording.files = paths
            return wording
        case .search(let pattern, let path)?:
            return search(
                verb: ToolVerb.search.appending("for"), quoted(pattern), in: path, detail: detail ?? command,
                category: .search)
        case .list(let path)?:
            var wording = Self(
                verb: .list, object: path?.fileName ?? "files", objectIsCode: path != nil, detail: detail ?? command,
                category: .read)
            wording.folder = path
            return wording
        case nil:
            return Self(verb: .run, object: line, objectIsCode: true, detail: detail, category: category)
        }
    }

    /// A code mode program, as the step it takes: its first one that isn't waiting, and how many
    /// more there are.
    static func codeMode(_ program: CodeModeProgram, call: ToolCallState) -> Self {
        let steps = program.steps.filter { !$0.isPolling }
        guard let first = steps.first else { return waiting(call) }
        var wording: Self
        switch first {
        case .command(let command):
            wording = commandLine(command, description: nil, category: .command)
        case .patch(let patch):
            let verb: ToolVerb = patch.deletesFile ? .delete : patch.createsFile ? .create : .edit
            let files = patch.files.map(\.fileName)
            var object = files.first ?? "a file"
            if files.count > 1 { object += " and \(files.count - 1) other \(files.count == 2 ? "file" : "files")" }
            wording = Self(
                verb: verb, object: object, objectIsCode: !files.isEmpty, detail: patch.files.first,
                lineChanges: LineChanges(added: patch.added, removed: patch.removed), category: .edit)
        case .input:
            wording = Self(verb: .send, object: "input to a command", category: .command)
        case .other(let tool):
            wording = Self(verb: .use, object: tool.humanized, detail: tool, category: .other)
        }
        if steps.count > 1 {
            wording.object += " and \(steps.count - 1) more \(steps.count == 2 ? "step" : "steps")"
        }
        return wording
    }

    /// A call that only waits: "Waited 30s" when it says how long, else for a command's output.
    static func waiting(_ call: ToolCallState) -> Self {
        guard let seconds = waitedSeconds(call) else {
            return Self(verb: .wait, object: "for output", category: .command)
        }
        return Self(verb: .wait, object: "\(seconds)s", category: .command)
    }

    /// How long a sleep lasted ("Wall time: 30.0032 seconds") or was asked to.
    private static func waitedSeconds(_ call: ToolCallState) -> Int? {
        let texts = call.content.compactMap { content -> String? in
            if case .content(let block) = content { block.text } else { nil }
        }
        for text in texts {
            if let range = text.range(of: "Wall time: ") {
                let number = text[range.upperBound...].prefix { $0.isNumber || $0 == "." }
                if let value = Double(number) { return Int(value.rounded()) }
            }
        }
        for key in ["seconds", "duration", "secs"] {
            if case .number(let value)? = call.rawInput?[key] { return Int(value.rounded()) }
        }
        if case .number(let value)? = call.rawInput?["ms"] { return Int((value / 1000).rounded()) }
        return nil
    }
}
