import Foundation

/// CLI output is transient and bounded. Only a complete OAuth authorization URL leaves this parser;
/// prompts, tokens and callback addresses are never copied into the task transcript or command log.
public struct MCPLoginOutput: Sendable {
    private var pending = Data()

    public init() {}

    public mutating func receive(_ data: Data) -> [MCPAuthorizationLink] {
        pending.append(data)
        guard pending.count <= 65_536 else {
            pending.removeAll()
            return []
        }
        var links: [MCPAuthorizationLink] = []
        while let end = pending.firstIndex(of: 10) {
            let line = String(decoding: pending[..<end], as: UTF8.self)
            pending.removeSubrange(...end)
            let plain =
                line
                .replacingOccurrences(
                    of: "\u{1b}\\][^\u{7}\u{1b}]*(?:\u{7}|\u{1b}\\\\)", with: "", options: .regularExpression
                )
                .replacingOccurrences(of: "\u{1b}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
            for word in plain.split(whereSeparator: { $0.isWhitespace }) {
                let text = String(word).trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'"))
                if let url = URL(string: text), let link = MCPAuthorizationLink(url) { links.append(link) }
            }
        }
        return links
    }
}
