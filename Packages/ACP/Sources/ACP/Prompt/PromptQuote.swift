import Foundation

/// A snapshot of source lines. Its readable prompt representation also preserves draft and queue
/// recovery without introducing a second payload that clients could forget to send.
public struct PromptQuote: Equatable, Sendable, Codable {
    public enum Side: String, Sendable, CaseIterable, Codable {
        case transcript
        case new = "new file"
        case old = "old file"
    }

    public struct Line: Equatable, Sendable, Codable {
        public let number: Int
        public let text: String

        public init(number: Int, text: String) {
            self.number = number
            self.text = text
        }
    }

    public let source: String
    public let side: Side
    public let lines: [Line]
    public var comment: PromptDiffComment?

    public init(source: String, side: Side = .transcript, lines: [Line], comment: PromptDiffComment? = nil) {
        self.source = source
        self.side = side
        self.lines = lines
        self.comment = comment
    }

    /// Expands a nonempty UTF-16 selection to whole source lines, preserving blank lines and tabs.
    public init?(source: String, text: String, selection: NSRange, firstLine: Int = 1, side: Side = .transcript) {
        guard selection.length > 0, let range = Range(selection, in: text) else { return nil }
        let lower =
            text[..<range.lowerBound].lastIndex(where: \.isNewline).map { text.index(after: $0) } ?? text.startIndex
        let last = text.index(before: range.upperBound)
        let upper = text[last...].firstIndex(where: \.isNewline) ?? text.endIndex
        let number = firstLine + text[..<lower].filter(\.isNewline).count
        self.init(
            source: source, side: side,
            lines: text[lower..<upper].split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated()
                .map {
                    Line(number: number + $0.offset, text: String($0.element))
                })
    }

    /// The shared indentation belongs to the source, not the field's inset. Sending still uses
    /// the original lines, including every tab and space.
    public var displayLines: [Line] {
        let prefixes = lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { String($0.text.prefix { $0 == " " || $0 == "\t" }) }
        guard var common = prefixes.first, !common.isEmpty else { return lines }
        for prefix in prefixes.dropFirst() {
            while !prefix.hasPrefix(common), !common.isEmpty { common.removeLast() }
        }
        return lines.map {
            Line(number: $0.number, text: $0.text.hasPrefix(common) ? String($0.text.dropFirst(common.count)) : $0.text)
        }
    }

    public var prompt: String {
        let name = (try? JSONEncoder().encode(source)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"Source\""
        let annotation = comment.map { "> Comment: " + Self.encoded($0) + "\n" } ?? ""
        return "> Quoted from \(name) (\(side.rawValue))\n"
            + lines.map { "> \($0.number) | \($0.text)" }.joined(separator: "\n") + "\n" + annotation + "\n"
    }

    private static func encoded(_ comment: PromptDiffComment) -> String {
        (try? JSONEncoder().encode(comment)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    public static func draft(quotes: [Self], message: String) -> String {
        quotes.map(\.prompt).joined() + message
    }

    /// Trims a prompt for sending like any other, except its leading quotes: their lines are source
    /// text, so a quote-only prompt keeps a final blank line or trailing spaces and still reads back.
    public static func trimmed(_ prompt: String) -> String {
        let (quotes, message) = split(prompt)
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !quotes.isEmpty else { return trimmedMessage }
        guard trimmedMessage.isEmpty else { return draft(quotes: quotes, message: trimmedMessage) }
        return String(quotes.map(\.prompt).joined().dropLast(2))
    }

    /// Only our complete leading blocks are interpreted; incomplete or ordinary Markdown stays editable.
    public static func split(_ draft: String) -> (quotes: [Self], message: String) {
        var remaining = draft[...]
        var quotes: [Self] = []
        let prefix = "> Quoted from "
        while remaining.hasPrefix(prefix), let end = remaining.firstIndex(of: "\n") {
            let header = remaining[..<end]
            guard let side = Side.allCases.first(where: { header.hasSuffix(" (\($0.rawValue))") }) else { break }
            let name = header.dropFirst(prefix.count).dropLast(side.rawValue.count + 3)
            guard let source = try? JSONDecoder().decode(String.self, from: Data(name.utf8)) else { break }
            var rest = remaining[remaining.index(after: end)...]
            var lines: [Line] = []
            while rest.hasPrefix("> "), !rest.hasPrefix("> Comment: ") {
                let lineEnd = rest.firstIndex(of: "\n") ?? rest.endIndex
                // A trim elsewhere may have taken the space after an empty last line's bar.
                var line = rest[..<lineEnd].dropFirst(2)
                if line.hasSuffix(" |"), !line.contains(" | ") { line += " " }
                guard let separator = line.range(of: " | "), let number = Int(line[..<separator.lowerBound]), number > 0
                else { break }
                lines.append(Line(number: number, text: String(line[separator.upperBound...])))
                rest = lineEnd == rest.endIndex ? rest[rest.endIndex...] : rest[rest.index(after: lineEnd)...]
            }
            var comment: PromptDiffComment?
            if rest.hasPrefix("> Comment: ") {
                let end = rest.firstIndex(of: "\n") ?? rest.endIndex
                guard
                    let decoded = try? JSONDecoder().decode(
                        PromptDiffComment.self, from: Data(rest[..<end].dropFirst(11).utf8))
                else { break }
                comment = decoded
                rest = end == rest.endIndex ? rest[rest.endIndex...] : rest[rest.index(after: end)...]
            }
            guard !lines.isEmpty, rest.isEmpty || rest.first == "\n" else { break }
            quotes.append(Self(source: source, side: side, lines: lines, comment: comment))
            remaining = rest.isEmpty ? rest : rest.dropFirst()
        }
        return (quotes, String(remaining))
    }
}
