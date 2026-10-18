import Foundation

extension ToolCallState {
    /// The shell command the call runs, as someone would type it, when its input names one.
    ///
    /// Agents send `rawInput.command` in three shapes: a plain string (Claude Code's Bash, Codex's
    /// `tool_call`), that string JSON-encoded a second time (codex-acp 2.2.2's permission requests,
    /// which replace the plain one), or an argv array, where `bash -lc <script>` is just the script.
    public var shellCommand: String? {
        ShellCommandText(rawInput?["command"])?.text
    }
}

private struct ShellCommandText {
    let text: String

    private static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish"]
    private static let scriptFlags: Set<String> = ["-c", "-lc", "-ic"]

    init?(_ value: JSONValue?) {
        switch value {
        case .string(let string):
            text = Self.decodingQuotedLiteral(string)
        case .array(let parts):
            let words = parts.compactMap(\.stringValue)
            guard !words.isEmpty, words.count == parts.count else { return nil }
            if words.count == 3, Self.shells.contains((words[0] as NSString).lastPathComponent),
                Self.scriptFlags.contains(words[1])
            {
                text = words[2]
            } else {
                text = words.map(Self.quotedIfNeeded).joined(separator: " ")
            }
        default:
            return nil
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
    }

    /// `"printf 'ship\\n' > todo.txt"` (quotes included) is `printf 'ship\n' > todo.txt`. A command
    /// that only looks quoted, like `"a" "b"`, isn't one JSON string and stays as it is.
    private static func decodingQuotedLiteral(_ string: String) -> String {
        guard string.count >= 2, string.hasPrefix("\""), string.hasSuffix("\""),
            let decoded = try? JSONDecoder().decode(String.self, from: Data(string.utf8))
        else { return string }
        return decoded
    }

    private static func quotedIfNeeded(_ word: String) -> String {
        let plain = word.allSatisfy { $0.isLetter || $0.isNumber || "-_./=:@%+,".contains($0) }
        guard !plain || word.isEmpty else { return word }
        return "'" + word.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
