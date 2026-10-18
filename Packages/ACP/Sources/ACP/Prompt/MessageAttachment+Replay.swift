import Foundation

// Agents keep a prompt's files and images as text, and replay them that way when a session loads:
// codex-acp 2.2.2 and claude-agent-acp 0.93.0 turn a `resource_link` into `[@name](uri)`, an
// embedded file into that link plus `<context ref="uri">…</context>` (Claude Code keeps the two as
// separate blocks), and Codex an image into `[@image](data:image/png;base64,…)`. These read them
// back as attachments, so a reloaded message looks as it did when it was sent.
extension MessageAttachment {
    /// The attachment a replayed text block stands for, when the block is nothing but one of the
    /// forms above; a prompt that merely quotes one stays text.
    init?(replayedText text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let ref = Self.contextRef(text) {
            guard let url = URL(string: ref) else { return nil }
            self.init(name: url.lastPathComponent, url: url)
            return
        }
        guard text.hasPrefix("[@"), let close = text.range(of: "](") else { return nil }
        let name = String(text[text.index(text.startIndex, offsetBy: 2)..<close.lowerBound])
        var link = text[close.upperBound...]
        // Codex sends an embedded file's link and contents as one block.
        if let context = link.range(of: "\n<context ref=\"") {
            guard Self.contextRef(String(link[link.index(after: context.lowerBound)...])) != nil else { return nil }
            link = link[..<context.lowerBound]
        }
        guard link.hasSuffix(")"), !name.isEmpty else { return nil }
        let uri = String(link.dropLast())
        guard !uri.contains(where: \.isWhitespace) else { return nil }
        if uri.hasPrefix("data:") {
            guard let data = Self.imageData(fromDataURI: uri) else { return nil }
            self.init(name: "Image", url: nil, imageData: data)
            return
        }
        guard let url = URL(string: uri), url.scheme != nil else { return nil }
        self.init(name: name.removingPercentEncoding ?? name, url: url)
    }

    /// The `ref` of a whole `<context ref="uri">…</context>` block.
    private static func contextRef(_ text: String) -> String? {
        let open = "<context ref=\""
        guard text.hasPrefix(open), text.hasSuffix("</context>"),
            let quote = text.dropFirst(open.count).firstIndex(of: "\"")
        else { return nil }
        return String(text[text.index(text.startIndex, offsetBy: open.count)..<quote])
    }

    /// An image's bytes from `data:image/…;base64,…`.
    private static func imageData(fromDataURI uri: String) -> Data? {
        guard let comma = uri.firstIndex(of: ","), uri[..<comma].hasPrefix("data:image/"),
            uri[..<comma].hasSuffix(";base64")
        else { return nil }
        return Data(base64Encoded: String(uri[uri.index(after: comma)...]))
    }
}
