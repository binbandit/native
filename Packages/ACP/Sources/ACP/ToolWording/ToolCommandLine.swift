import Foundation

/// A shell command as a one-line label: the first line, without the `cd <folder> &&` agents put in
/// front to run it somewhere. The whole command stays in the call's details.
struct ToolCommandLine {
    /// Past this a label is cut: no row shows that much, and laying it out costs.
    static let maxLength = 240

    let display: String

    init(_ command: String) {
        var text = Self.unwrappingShell(Substring(command.trimmingCharacters(in: .whitespacesAndNewlines)))
        // `cd /a/b && swift test` and `cd "/a b"; make`: only what runs there says what the call does.
        while let rest = Self.droppingLeadingCD(text), !rest.isEmpty {
            text = rest
        }
        let lines = text.split(whereSeparator: \.isNewline)
        var line = String(lines.first ?? "").trimmingCharacters(in: .whitespaces)
        if lines.count > 1 { line += " …" }
        if line.count > Self.maxLength { line = String(line.prefix(Self.maxLength)) + "…" }
        display = line.isEmpty ? command : line
    }

    /// `/bin/zsh -lc 'cat a && cat b'` is `cat a && cat b`: the script a shell was asked to run, when
    /// it's the whole of what follows. Anything else stays as it was.
    static func unwrappingShell(_ text: Substring) -> Substring {
        let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish"]
        let parts = text.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count == 3, shells.contains(String(parts[0].split(separator: "/").last ?? "")),
            ["-c", "-lc", "-ic"].contains(parts[1])
        else { return text }
        let script = parts[2]
        guard let quote = script.first, quote == "'" || quote == "\"", script.count >= 2, script.last == quote else {
            return text
        }
        let inner = script.dropFirst().dropLast()
        if quote == "'" {
            // A single-quoted script can only hold a quote as `'\''`.
            guard !inner.replacingOccurrences(of: #"'\''"#, with: "").contains("'") else { return text }
            return Substring(inner.replacingOccurrences(of: #"'\''"#, with: "'"))
        }
        var unescaped = ""
        var escaping = false
        for character in inner {
            if escaping {
                unescaped.append(character)
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else if character == "\"" {
                return text
            } else {
                unescaped.append(character)
            }
        }
        return Substring(unescaped)
    }

    /// `text` without a leading `cd <folder> &&` (or `;`), or nil when it doesn't start with one.
    private static func droppingLeadingCD(_ text: Substring) -> Substring? {
        guard text.hasPrefix("cd ") else { return nil }
        var rest = text.dropFirst(3).drop { $0 == " " }
        // The folder: a quoted word, or everything up to the next space.
        if let quote = rest.first, quote == "\"" || quote == "'" {
            guard let end = rest.dropFirst().firstIndex(of: quote) else { return nil }
            rest = rest[rest.index(after: end)...]
        } else {
            rest = rest.drop { $0 != " " && $0 != ";" && $0 != "&" }
        }
        rest = rest.drop { $0 == " " }
        for separator in ["&&", ";"] where rest.hasPrefix(separator) {
            return rest.dropFirst(separator.count).drop { $0 == " " }
        }
        return nil
    }
}
