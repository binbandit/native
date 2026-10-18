import Foundation

/// Reads a JSONL file one record at a time, without loading it whole: history files run to
/// hundreds of megabytes, mostly lines search doesn't need.
enum JSONLines {
    /// Calls `body` with each line that contains one of `markers` and parses as a JSON object.
    /// The markers are a cheap first cut (`"type":"user"`); the caller still checks the record.
    static func forEach(in url: URL, containing markers: [String], _ body: ([String: Any]) throws -> Void) throws {
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        let needles = markers.map { Array($0.utf8) }
        try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let base = buffer.baseAddress else { return }
            var start = 0
            while start < buffer.count {
                let remaining = buffer.count - start
                let end = memchr(base + start, 0x0A, remaining).map { $0 - base } ?? buffer.count
                let line = UnsafeRawBufferPointer(start: base + start, count: end - start)
                if needles.contains(where: { contains($0, in: line) }),
                    let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
                {
                    try body(object)
                }
                start = end + 1
            }
        }
    }

    private static func contains(_ needle: [UInt8], in line: UnsafeRawBufferPointer) -> Bool {
        guard let base = line.baseAddress else { return false }
        return needle.withUnsafeBytes { needle in
            memmem(base, line.count, needle.baseAddress, needle.count) != nil
        }
    }

    /// An ISO 8601 timestamp, as both agents write them (with or without fractional seconds).
    static func date(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return (try? Date(string, strategy: .iso8601WithFractions)) ?? (try? Date(string, strategy: .iso8601))
    }

    /// Every string in a decoded JSON value, depth first, with arrays of strings joined by spaces.
    static func strings(in value: Any?) -> [String] {
        switch value {
        case let string as String: return [string]
        case let array as [Any]:
            if let strings = array as? [String] { return [strings.joined(separator: " ")] }
            return array.flatMap { strings(in: $0) }
        case let object as [String: Any]: return object.keys.sorted().flatMap { strings(in: object[$0]) }
        default: return []
        }
    }
}

extension Date.ISO8601FormatStyle {
    fileprivate static let iso8601WithFractions = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}

/// Builds a session's documents the way the ACP reducer builds its transcript, so anchors found in
/// history match the transcript Native shows after loading the session: consecutive pieces of one
/// message are one message, and a tool call's output joins its call.
struct HistoryTranscriptBuilder {
    private(set) var documents: [SearchDocument] = []
    private var toolCalls: [String: Int] = [:]
    /// The message `documents.last` is, while more of it may follow.
    private var openMessage: (role: SearchRole, text: String)?

    mutating func message(_ role: SearchRole, _ text: String, date: Date?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let open = openMessage, open.role == role, let last = documents.indices.last {
            let joined = open.text + "\n\n" + trimmed
            openMessage = (role, joined)
            documents[last].text = SearchText.capped(joined, to: limit(for: role))
            return
        }
        openMessage = (role, trimmed)
        documents.append(
            SearchDocument(
                role: role, text: SearchText.capped(trimmed, to: limit(for: role)),
                anchor: .message(startingWith: trimmed), date: date))
    }

    /// A tool call: its name and the strings of its input (paths, commands, patterns).
    mutating func toolCall(id: String, name: String, input: [String], date: Date?, hasDiff: Bool = false) {
        openMessage = nil
        let inputText = SearchText.capped(input.filter { !$0.isEmpty }.joined(separator: "\n"), to: SearchLimits.toolInput)
        toolCalls[id] = documents.count
        documents.append(
            SearchDocument(
                role: .tool, text: [name, inputText].filter { !$0.isEmpty }.joined(separator: "\n"),
                anchor: .toolCall(id: id), date: date, hasDiff: hasDiff))
    }

    /// What a tool call returned, added to its call.
    mutating func toolOutput(id: String, output: String) {
        guard let index = toolCalls[id], !output.isEmpty else { return }
        documents[index].text += "\n" + SearchText.capped(output, to: SearchLimits.toolOutput)
    }

    /// The agent's plan. Only the latest one is kept, as the transcript does.
    mutating func plan(_ steps: [String], date: Date?) {
        openMessage = nil
        let text = SearchText.capped(steps.joined(separator: "\n"), to: SearchLimits.plan)
        documents.removeAll { $0.role == .plan }
        documents.append(SearchDocument(role: .plan, text: text, anchor: .session, date: date))
    }

    private func limit(for role: SearchRole) -> Int {
        role == .thought ? SearchLimits.thought : SearchLimits.message
    }

    /// Whether a user message is context the agent's harness injected rather than something the
    /// user typed: a whole message wrapped in one tag (`<environment_context>…</environment_context>`,
    /// `<command-name>/clear</command-name>`), or a bundled instructions file.
    static func isInjectedContext(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("# AGENTS.md instructions") || trimmed.hasPrefix("Caveat: The messages below") {
            return true
        }
        guard trimmed.hasPrefix("<"), let close = trimmed.firstIndex(where: { $0 == ">" || $0 == " " }) else {
            return false
        }
        let tag = trimmed[trimmed.index(after: trimmed.startIndex)..<close]
        guard !tag.isEmpty, tag.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else {
            return false
        }
        return trimmed.contains("</\(tag)>")
    }
}
