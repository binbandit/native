import Foundation

/// A call to Codex's code mode `exec` tool: a JavaScript program that does its work through nested
/// tools, `text(await tools.exec_command({cmd: "rg -n 'playful' native"}))`. Read for the steps it
/// takes, so a row says what the program did ("Searched for "playful" in native") rather than
/// showing the program. Only string arguments written out in the call are read; a program that
/// builds them at run time keeps its generic wording.
struct CodeModeProgram: Equatable {
    enum Step: Equatable {
        case command(String)
        case patch(Patch)
        /// Input written to a running command; empty input only polls it for output.
        case input(String)
        case other(tool: String)

        var isPolling: Bool {
            if case .input(let chars) = self { chars.isEmpty } else { false }
        }
    }

    /// The files an `apply_patch` changes and the lines it adds and removes.
    struct Patch: Equatable {
        var files: [String] = []
        var createsFile = false
        var deletesFile = false
        var added = 0
        var removed = 0

        init(_ text: String) {
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                for (marker, flag) in [("*** Update File: ", 0), ("*** Add File: ", 1), ("*** Delete File: ", 2)]
                where line.hasPrefix(marker) {
                    files.append(String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces))
                    if flag == 1 { createsFile = true }
                    if flag == 2 { deletesFile = true }
                }
                if line.hasPrefix("*** ") { continue }
                if line.hasPrefix("+") { added += 1 } else if line.hasPrefix("-") { removed += 1 }
            }
        }
    }

    let steps: [Step]

    /// The program in a call's input, when the call is code mode's: its source names `tools.`.
    init?(_ call: ToolCallState) {
        guard call.mcpTool == nil, let source = Self.source(in: call.rawInput), source.contains("tools.") else {
            return nil
        }
        self.init(source: source)
    }

    init(source: String) {
        var steps: [Step] = []
        var rest = Substring(source)
        while let call = rest.range(of: "tools.") {
            rest = rest[call.upperBound...]
            let name = String(rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
            rest = rest.dropFirst(name.count)
            guard rest.first == "(" else { continue }
            let arguments = Self.argumentText(rest)
            switch name {
            case "exec_command":
                if let command = Self.string(named: "cmd", in: arguments)
                    ?? Self.string(named: "command", in: arguments)
                {
                    steps.append(.command(command))
                } else {
                    steps.append(.other(tool: name))
                }
            case "apply_patch":
                if let patch = Self.string(named: "input", in: arguments) ?? Self.firstString(in: arguments) {
                    steps.append(.patch(Patch(patch)))
                } else {
                    steps.append(.other(tool: name))
                }
            case "write_stdin":
                steps.append(.input(Self.string(named: "chars", in: arguments) ?? ""))
            default:
                steps.append(.other(tool: name))
            }
        }
        self.steps = steps
    }

    /// Every step only polls a running command.
    var isPolling: Bool {
        !steps.isEmpty && steps.allSatisfy(\.isPolling)
    }

    /// The source, from `arguments` (a string, or an object holding one) or the input itself.
    private static func source(in input: JSONValue?) -> String? {
        for value in [input?["arguments"], input] {
            if let text = value?.stringValue { return text }
            for key in ["code", "source", "input", "script"] {
                if let text = value?[key]?.stringValue { return text }
            }
        }
        return nil
    }

    /// A call's arguments, `(` to its matching `)`, skipping parentheses inside strings.
    private static func argumentText(_ text: Substring) -> Substring {
        var depth = 0
        var quote: Character?
        var escaping = false
        for index in text.indices {
            let character = text[index]
            if let open = quote {
                if escaping {
                    escaping = false
                } else if character == "\\" {
                    escaping = true
                } else if character == open {
                    quote = nil
                }
            } else if character == "\"" || character == "'" || character == "`" {
                quote = character
            } else if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0 { return text[...index] }
            }
        }
        return text
    }

    /// The string literal after `name:` (or `"name":`) in an object literal.
    private static func string(named name: String, in text: Substring) -> String? {
        for key in [name, "\"\(name)\"", "'\(name)'"] {
            var rest = text
            while let found = rest.range(of: key) {
                let before = rest[..<found.lowerBound].last
                rest = rest[found.upperBound...]
                guard before.map({ !$0.isLetter && !$0.isNumber && $0 != "_" }) ?? true else { continue }
                let afterKey = rest.drop { $0 == " " }
                guard afterKey.first == ":" else { continue }
                return firstString(in: afterKey.dropFirst())
            }
        }
        return nil
    }

    /// The first string literal in `text`, its escapes decoded.
    private static func firstString(in text: Substring) -> String? {
        guard let start = text.firstIndex(where: { $0 == "\"" || $0 == "'" || $0 == "`" }) else { return nil }
        // Only whitespace and an opening brace may come first, so a later argument isn't taken.
        guard text[..<start].allSatisfy({ $0 == " " || $0 == "(" || $0 == "{" || $0 == "\n" }) else { return nil }
        let quote = text[start]
        var value = ""
        var escaping = false
        for character in text[text.index(after: start)...] {
            if escaping {
                switch character {
                case "n": value.append("\n")
                case "t": value.append("\t")
                default: value.append(character)
                }
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else if character == quote {
                return value
            } else {
                value.append(character)
            }
        }
        return nil
    }
}

extension ToolCallState {
    /// Only output-free, successful polls can disappear. Results belong to this call's ID,
    /// so hiding one with content would lose the only way to inspect that output.
    public var isSuppressiblePolling: Bool {
        isPolling && status == .completed && permission == nil && content.isEmpty
            && rawOutput == nil && terminalOutput == nil && (exitCode ?? 0) == 0
    }

    /// A call that only waits on another: Codex polling a running command for output (an empty
    /// `write_stdin`, alone or in a code mode program) or sleeping between polls. Its time belongs
    /// to the step it waits on; result-bearing polls still need their own accessible row.
    public var isPolling: Bool {
        guard mcpTool == nil else { return false }
        if let program = CodeModeProgram(self) { return program.isPolling }
        switch name ?? title {
        case "sleep", "wait": return shellCommand == nil
        case "write_stdin":
            return (rawInput?["chars"]?.stringValue ?? rawInput?["input"]?.stringValue ?? "").isEmpty
        default: return false
        }
    }
}
