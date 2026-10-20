/// The tags Claude Code puts around tool errors for its model, which a person shouldn't have to read
/// past: a whole result in `<tool_use_error>…</tool_use_error>` (a call it refused, input it
/// rejected, a hook's block), and a last line in `<error>…</error>` (a command it aborted, "Command
/// was aborted before completion"). Read from Claude Code 2.1.304 and captured through
/// claude-agent-acp 0.93.0; codex-acp 2.2.2 sends its errors as plain text.
public enum ToolErrorMarkup {
    /// `text` without those tags, everything else exactly as sent. Only a tag pair that encloses the
    /// whole text, or the whole last line, counts, so output that merely mentions one stays as is.
    public static func stripped(_ text: String) -> String {
        if let message = enclosed(text, in: "tool_use_error") {
            return message
        }
        guard let lastLine = text.split(separator: "\n", omittingEmptySubsequences: true).last,
            let message = enclosed(lastLine, in: "error"),
            let range = text.range(of: lastLine, options: .backwards)
        else { return text }
        return text.replacingCharacters(in: range, with: message)
    }

    /// What's between `<tag>` and `</tag>` when they enclose all of `text` but surrounding
    /// whitespace, and there's only the one pair.
    private static func enclosed(_ text: some StringProtocol, in tag: String) -> String? {
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= open.count + close.count, trimmed.hasPrefix(open), trimmed.hasSuffix(close) else {
            return nil
        }
        let inner = trimmed.dropFirst(open.count).dropLast(close.count)
        guard !inner.contains(open), !inner.contains(close) else { return nil }
        return String(inner)
    }
}
