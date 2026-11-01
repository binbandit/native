import Foundation

extension SessionState {
    /// Why the agent is making a tool call, in its own words: what it said just before the call in
    /// the same turn, or the justification an agent attaches to the call itself (Codex asks for
    /// escalated permissions with one). Nil when it went straight to the call, so an ask never
    /// borrows a reason that belonged to an earlier step.
    public func reason(forToolCall id: String) -> String? {
        guard let index = items.lastIndex(where: { if case .toolCall(let call) = $0 { call.id == id } else { false } })
        else { return nil }
        if case .toolCall(let call) = items[index],
            let stated = (call.rawInput?["justification"] ?? call.rawInput?["reason"])?.stringValue
        {
            return Self.lastParagraph(of: stated)
        }
        for item in items[..<index].reversed() {
            switch item {
            case .message(let message) where message.role == .thought: continue
            case .message(let message) where message.role == .agent: return Self.lastParagraph(of: message.text)
            default: return nil
            }
        }
        return nil
    }

    /// The sentence nearest the call. A code block or table is shown in the transcript, not here.
    private static func lastParagraph(of text: String) -> String? {
        let paragraph = text.components(separatedBy: "\n\n").lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last { !$0.isEmpty }
        guard let paragraph, !paragraph.hasPrefix("```"), !paragraph.hasPrefix("|") else { return nil }
        return paragraph.replacingOccurrences(of: "\n", with: " ")
    }
}
