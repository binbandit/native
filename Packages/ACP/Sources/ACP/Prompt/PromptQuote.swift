import Foundation

/// A snapshot of source lines. Its readable prompt representation also preserves draft and queue
/// recovery without introducing a second payload that clients could forget to send.
public struct PromptQuote: Equatable, Sendable {
    public enum Side: String, Sendable, CaseIterable {
        case transcript
        case new = "new file"
        case old = "old file"
    }

    public struct Line: Equatable, Sendable {
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

    public init(source: String, side: Side = .transcript, lines: [Line]) {
        self.source = source
        self.side = side
        self.lines = lines
    }

    /// Expands a nonempty UTF-16 selection to whole source lines, preserving blank lines and tabs.
    public init?(source: String, text: String, selection: NSRange, firstLine: Int = 1, side: Side = .transcript) {
        guard selection.length > 0, let range = Range(selection, in: text) else { return nil }
        let lower = text[..<range.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let last = text.index(before: range.upperBound)
        let upper = text[last...].firstIndex(of: "\n") ?? text.endIndex
        let number = firstLine + text[..<lower].filter { $0 == "\n" }.count
        self.init(
            source: source, side: side,
            lines: text[lower..<upper].split(separator: "\n", omittingEmptySubsequences: false).enumerated().map {
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
        return "> Quoted from \(name) (\(side.rawValue))\n"
            + lines.map { "> \($0.number) | \($0.text)" }.joined(separator: "\n") + "\n\n"
    }

    public static func draft(quotes: [Self], message: String) -> String {
        quotes.map(\.prompt).joined() + message
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
            while rest.hasPrefix("> ") {
                let lineEnd = rest.firstIndex(of: "\n") ?? rest.endIndex
                let line = rest[..<lineEnd].dropFirst(2)
                guard let separator = line.range(of: " | "), let number = Int(line[..<separator.lowerBound]), number > 0
                else { break }
                lines.append(Line(number: number, text: String(line[separator.upperBound...])))
                rest = lineEnd == rest.endIndex ? rest[rest.endIndex...] : rest[rest.index(after: lineEnd)...]
            }
            guard !lines.isEmpty, rest.isEmpty || rest.first == "\n" else { break }
            quotes.append(Self(source: source, side: side, lines: lines))
            remaining = rest.isEmpty ? rest : rest.dropFirst()
        }
        return (quotes, String(remaining))
    }
}
