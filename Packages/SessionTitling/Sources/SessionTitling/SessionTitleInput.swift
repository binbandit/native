import Foundation

/// Removes pasted credentials and locations before they can become sidebar text. It works locally
/// even when Apple Intelligence is unavailable; it never opens a referenced file or URL.
public enum SessionTitleInput {
    public static func prepared(_ text: String, limit: Int = 2_000) -> String {
        var text = text
        for pattern in [
            #"(?im)^\s*(?:authorization|cookie|set-cookie|x-api-key|title)\s*:.*$"#,
            #"(?im)^.*\b(?:[A-Z0-9_]*(?:_key|_token|_password|_secret|_credential)[A-Z0-9_]*|api[_-]?key|access[_-]?token|key|password|secret|token|credential)\s*[=:].*$"#,
            #"(?s)-----BEGIN [^-]*(?:PRIVATE KEY|CREDENTIAL)[^-]*-----.*?-----END [^-]+-----"#,
            #"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"#,
            #"\b(?:sk-|ghp_|github_pat_)[A-Za-z0-9_-]+"#,
            #"\b[A-Za-z0-9_+/=-]{32,}\b"#,
        ] {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: #"https?://[^\s<>]+"#, with: "[link]", options: .regularExpression)
        if let paths = try? NSRegularExpression(pattern: #"(?:[A-Za-z]:\\|~/|/)[^\s\"'`<>]*"#) {
            for match in paths.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                guard let range = Range(match.range, in: text) else { continue }
                let path = String(text[range]).replacingOccurrences(of: "\\", with: "/")
                let name = path.split(separator: "/").last.map(String.init) ?? "file"
                text.replaceSubrange(range, with: name)
            }
        }
        text = text.replacingOccurrences(of: #"(?m)^\s*```[^\n]*$"#, with: "", options: .regularExpression)
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        text = lines.filter { !$0.isEmpty && $0 != "[link]" && $0 != "[path]" }.joined(separator: "\n")
        guard text.count > limit else { return text }
        // Requests often follow a long pasted log. Keep both ends rather than only the log's start.
        return String(text.prefix(limit / 2)) + "\n[...]\n" + String(text.suffix(max(0, limit / 2 - 7)))
    }

    public static func isSafeTitle(_ text: String) -> Bool {
        let safe = prepared(text)
        return safe == text && !text.contains("[path]") && !text.contains("[link]")
    }
}
