import ACP
import Foundation

/// Reads a JSONL file one record at a time, a megabyte at a time: history files run to hundreds
/// of megabytes, mostly lines search doesn't need, and the memory used stays the same whatever
/// their size.
enum JSONLines {
    /// Calls `body` with each complete line from `offset` on that contains one of `markers` and
    /// parses as a JSON object. Returns the offset just past the last complete line, so a line
    /// still being written is read next time. Lines longer than `maxLine` (an image pasted into a
    /// tool result) are skipped whole.
    @discardableResult
    static func forEach(
        in url: URL, from offset: Int = 0, containing markers: [String], maxLine: Int = 4 << 20,
        _ body: ([String: Any]) throws -> Void
    ) throws -> Int {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        try file.seek(toOffset: UInt64(offset))
        let needles = markers.map { Array($0.utf8) }
        var line: [UInt8] = []
        var isOversized = false
        var position = offset
        var consumed = offset
        while let chunk = try autoreleasepool(invoking: { try file.read(upToCount: 1 << 20) }), !chunk.isEmpty {
            try chunk.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) throws -> Void in
                guard let base = buffer.baseAddress else { return }
                var start = 0
                while start < buffer.count {
                    let newline: UnsafeMutableRawPointer? = memchr(base + start, 0x0A, buffer.count - start)
                    let end = newline.map { UnsafeRawPointer($0) - base } ?? buffer.count
                    if !isOversized {
                        if line.count + end - start > maxLine {
                            isOversized = true
                            line.removeAll(keepingCapacity: false)
                        } else {
                            line.append(contentsOf: UnsafeRawBufferPointer(rebasing: buffer[start..<end]))
                        }
                    }
                    guard newline != nil else { break }
                    if !isOversized, needles.contains(where: { contains($0, in: line) }) {
                        try autoreleasepool {
                            if let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] {
                                try body(object)
                            }
                        }
                    }
                    line.removeAll(keepingCapacity: line.capacity <= 1 << 20)
                    isOversized = false
                    consumed = position + end + 1
                    start = end + 1
                }
                position += buffer.count
            }
        }
        return consumed
    }

    private static func contains(_ needle: [UInt8], in line: [UInt8]) -> Bool {
        line.withUnsafeBytes { line in
            needle.withUnsafeBytes { needle in
                guard let base = line.baseAddress else { return false }
                return memmem(base, line.count, needle.baseAddress, needle.count) != nil
            }
        }
    }

    private static let fractionalSeconds = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    /// An ISO 8601 timestamp, as both agents write them (with or without fractional seconds).
    static func date(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return (try? fractionalSeconds.parse(string)) ?? (try? Date(string, strategy: .iso8601))
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
        let inputText = SearchText.capped(
            input.filter { !$0.isEmpty }.joined(separator: "\n"), to: SearchLimits.toolInput)
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
    /// `<command-name>/clear</command-name>`), a bundled instructions file, or the agent's record that
    /// the user stopped a turn (`InterruptionMarker`).
    static func isInjectedContext(_ text: String) -> Bool {
        if InterruptionMarker.texts.contains(text) {
            return true
        }
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
