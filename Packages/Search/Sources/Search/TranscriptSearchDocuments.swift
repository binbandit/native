import ACP
import Foundation

/// How much of each kind of text is indexed. Enough to find a piece by what it said, small enough
/// that years of history stay a modest file: tool output repeats whole files and logs, so only its
/// start and end are kept.
public enum SearchLimits {
    public static let message = 24_000
    public static let thought = 8_000
    public static let toolInput = 2_000
    public static let toolOutput = 2_000
    public static let plan = 4_000
}

extension SearchDocument {
    /// The documents for a live (or loaded) ACP transcript and its plan.
    public static func documents(transcript items: [TranscriptItem], plan: [PlanEntry] = []) -> [SearchDocument] {
        var documents = items.compactMap(document(for:))
        let planText = plan.map(\.content).joined(separator: "\n")
        if !planText.isEmpty {
            documents.append(
                SearchDocument(role: .plan, text: SearchText.capped(planText, to: SearchLimits.plan), anchor: .session))
        }
        return documents
    }

    static func document(for item: TranscriptItem) -> SearchDocument? {
        switch item {
        case .message(let message):
            let role: SearchRole =
                switch message.role {
                case .user: .user
                case .agent: .agent
                case .thought: .thought
                }
            let limit = role == .thought ? SearchLimits.thought : SearchLimits.message
            return SearchDocument(
                role: role, text: SearchText.capped(message.text, to: limit),
                anchor: .message(startingWith: message.text), date: message.startedAt)
        case .toolCall(let call):
            return toolDocument(for: call)
        case .sessionMessage(let message):
            return SearchDocument(
                role: .agent, text: SearchText.capped(message.text, to: SearchLimits.message),
                anchor: .item(id: item.id))
        case .notice, .subagent:
            return nil
        }
    }

    private static func toolDocument(for call: ToolCallState) -> SearchDocument {
        var input: [String] = call.locations.map(\.path)
        if let rawInput = call.rawInput {
            input += rawInput.searchableStrings
        }
        var output: [String] = []
        var hasDiff = false
        for content in call.content {
            switch content {
            case .content(let block):
                output += block.text.map { [$0] } ?? []
            case .diff(let diff):
                hasDiff = true
                input.append(diff.path)
                output.append(diff.newText)
            case .terminal, .unsupported:
                break
            }
        }
        if let rawOutput = call.rawOutput, output.isEmpty {
            output += rawOutput.searchableStrings
        }
        hasDiff = hasDiff || ([.edit, .delete, .move].contains(call.kind) && call.status == .completed)
        var seen: Set<String> = [call.title]
        let text = [
            call.title,
            SearchText.capped(input.filter { seen.insert($0).inserted }.joined(separator: "\n"), to: SearchLimits.toolInput),
            SearchText.capped(output.joined(separator: "\n"), to: SearchLimits.toolOutput),
        ].filter { !$0.isEmpty }.joined(separator: "\n")
        return SearchDocument(
            role: .tool, text: text, anchor: .toolCall(id: call.id), date: call.startedAt, hasDiff: hasDiff)
    }
}

extension JSONValue {
    /// Every string in the value, depth first, with arrays of strings (an argv) joined by spaces.
    var searchableStrings: [String] {
        switch self {
        case .string(let string): [string]
        case .array(let values):
            if values.allSatisfy({ if case .string = $0 { true } else { false } }) {
                [values.compactMap(\.stringValue).joined(separator: " ")]
            } else {
                values.flatMap(\.searchableStrings)
            }
        case .object(let object): object.keys.sorted().flatMap { object[$0]?.searchableStrings ?? [] }
        case .null, .bool, .number: []
        }
    }

    private var stringValue: String? {
        if case .string(let string) = self { string } else { nil }
    }
}

extension SearchAnchor {
    /// Where the anchored piece is in `items`, if it's still there. A message is the first whose
    /// text starts with the probe, then the first that contains it.
    public func index(in items: [TranscriptItem]) -> Int? {
        switch self {
        case .toolCall(let id):
            return items.firstIndex { if case .toolCall(let call) = $0 { call.id == id } else { false } }
        case .item(let id):
            return items.firstIndex { $0.id == id }
        case .message(let probe):
            guard !probe.isEmpty else { return nil }
            let texts = items.map { item -> String? in
                if case .message(let message) = item { SearchText.collapsingWhitespace(message.text) } else { nil }
            }
            return texts.firstIndex { $0?.hasPrefix(probe) == true }
                ?? texts.firstIndex { $0?.contains(probe) == true }
        case .session:
            return nil
        }
    }
}
