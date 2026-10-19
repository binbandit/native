import Foundation

/// Instructions a client sends the agent ahead of the user's own words, such as a mode's way of
/// working. They go as the prompt's first text block, framed as
/// `<native_instructions id="…" label="…" symbol="…">…</native_instructions>`, and the transcript
/// shows a quiet marker in their place. Agents replay each text block of a prompt as a chunk of its
/// own (codex-acp 2.2.2 and claude-agent-acp 0.93.0 both do), so a reopened session reads the frame
/// back whole and shows the same marker.
public struct PromptPreamble: Hashable, Sendable {
    /// What the transcript shows where the instructions went.
    public struct Marker: Hashable, Sendable {
        /// Stable across renames, so a client can tell which instructions the agent last had.
        public var id: String
        /// "Debug mode".
        public var label: String
        /// An SF Symbol to show with the label.
        public var symbol: String?

        public init(id: String, label: String, symbol: String? = nil) {
            self.id = id
            self.label = label
            self.symbol = symbol
        }
    }

    public var marker: Marker
    public var instructions: String

    public init(marker: Marker, instructions: String) {
        self.marker = marker
        self.instructions = instructions
    }

    /// The prompt block that carries it.
    public var block: ContentBlock {
        .text(framed)
    }

    /// The instructions in their frame. A closing tag inside them is escaped, so they can't end it early.
    public var framed: String {
        var attributes = "id=\"\(Self.escaped(marker.id))\" label=\"\(Self.escaped(marker.label))\""
        if let symbol = marker.symbol {
            attributes += " symbol=\"\(Self.escaped(symbol))\""
        }
        let body = instructions.replacingOccurrences(of: Self.close, with: Self.escapedClose)
        return "<\(Self.tag) \(attributes)>\n\(body)\n\(Self.close)"
    }

    /// The preamble a replayed text block is, when the block is nothing but one. A prompt that
    /// merely mentions the tag stays the user's text.
    public init?(framed text: String) {
        guard let (preamble, rest) = Self.leading(text), rest.allSatisfy(\.isWhitespace) else { return nil }
        self = preamble
    }

    /// The preamble `text` starts with and the text after it, for an agent that replays the frame
    /// and the user's words as one block.
    public static func leading(_ text: String) -> (PromptPreamble, Substring)? {
        let text = text.drop(while: \.isWhitespace)
        let open = "<\(tag) "
        guard text.hasPrefix(open), let headEnd = text.firstIndex(of: ">"),
            let closing = text.range(of: close, range: headEnd..<text.endIndex)
        else { return nil }
        let attributes = Self.attributes(in: text[text.index(text.startIndex, offsetBy: open.count)..<headEnd])
        guard let id = attributes["id"], let label = attributes["label"] else { return nil }
        var body = text[text.index(after: headEnd)..<closing.lowerBound]
        if body.hasPrefix("\n") { body = body.dropFirst() }
        if body.hasSuffix("\n") { body = body.dropLast() }
        let preamble = PromptPreamble(
            marker: Marker(id: id, label: label, symbol: attributes["symbol"]),
            instructions: body.replacingOccurrences(of: escapedClose, with: close))
        return (preamble, text[closing.upperBound...].drop(while: \.isNewline))
    }

    // MARK: - Framing

    private static let tag = "native_instructions"
    private static let close = "</\(tag)>"
    private static let escapedClose = "<\\/\(tag)>"

    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func unescaped(_ value: Substring) -> String {
        value.replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
    }

    /// `name="value"` pairs, in any order.
    private static func attributes(in head: Substring) -> [String: String] {
        var attributes: [String: String] = [:]
        var rest = head[...]
        while let equals = rest.range(of: "=\"") {
            let name = rest[..<equals.lowerBound].trimmingCharacters(in: .whitespaces)
            let valueStart = equals.upperBound
            guard let quote = rest[valueStart...].firstIndex(of: "\"") else { break }
            attributes[name] = unescaped(rest[valueStart..<quote])
            rest = rest[rest.index(after: quote)...]
        }
        return attributes
    }
}
