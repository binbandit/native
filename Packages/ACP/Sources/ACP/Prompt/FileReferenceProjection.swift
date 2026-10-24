import Foundation

/// Display-only file tokens. Canonical @paths stay in the draft; counts never enter a prompt.
/// Editing inside a token replaces that token as a unit, including its full path.
public struct FileReferenceProjection: Equatable, Sendable {
    public struct Counts: Equatable, Sendable {
        public var added: Int
        public var removed: Int
        public init(added: Int, removed: Int) { self.added = added; self.removed = removed }
    }
    public struct Token: Equatable, Sendable {
        public let path: String
        public let raw: Range<Int>
        public let display: Range<Int>
        public let counts: Counts?
    }
    public let raw: String
    public let display: String
    public let tokens: [Token]

    public init(
        _ raw: String, counts: [String: Counts] = [:], enabled: Bool = true,
        formatCount: (Int) -> String = { String($0) }
    ) {
        self.raw = raw
        guard enabled else { display = raw; tokens = []; return }
        var output = ""
        var tokens: [Token] = []
        var cursor = raw.startIndex
        var copied = cursor
        while cursor < raw.endIndex {
            defer { if cursor < raw.endIndex { cursor = raw.index(after: cursor) } }
            guard raw[cursor] == "@", cursor == raw.startIndex || raw[raw.index(before: cursor)].isWhitespace,
                !PromptCode.isInCode(cursor, in: raw)
            else { continue }
            let start = cursor
            let after = raw.index(after: start)
            guard after < raw.endIndex else { continue }
            var path: String
            var end: String.Index
            if raw[after] == "\"" {
                let nameStart = raw.index(after: after)
                guard let close = raw[nameStart...].firstIndex(of: "\"") else { continue }
                path = String(raw[nameStart..<close]); end = raw.index(after: close)
            } else {
                // The word being typed remains text until a completion or space finishes it.
                guard let boundary = raw[after...].firstIndex(where: \.isWhitespace) else { continue }
                path = String(raw[after..<boundary]); end = boundary
            }
            if raw[after] != "\"", counts[path] == nil {
                var candidate = path
                while let last = candidate.last, ".,;:!?)]}'\"".contains(last) {
                    candidate.removeLast()
                    if counts[candidate] != nil {
                        end = raw.index(after, offsetBy: candidate.count)
                        path = candidate
                        break
                    }
                }
            }
            guard !path.isEmpty, !path.hasSuffix("/") else { continue }
            output += raw[copied..<start]
            let displayStart = output.utf8.count
            let count = counts[path]
            output += path.split(separator: "/").last.map(String.init) ?? path
            if let count {
                if count.added > 0 { output += " +\(formatCount(count.added))" }
                if count.removed > 0 { output += " −\(formatCount(count.removed))" }
            }
            tokens.append(
                Token(
                    path: path,
                    raw: raw.utf8.distance(
                        from: raw.startIndex, to: start)..<raw.utf8.distance(from: raw.startIndex, to: end),
                    display: displayStart..<output.utf8.count, counts: count))
            copied = end
            cursor = raw.index(before: end)
        }
        output += raw[copied...]
        display = output
        self.tokens = tokens
    }

    public func displayOffset(_ offset: Int, end: Bool = false) -> Int {
        map(offset, end: end, forward: true)
    }
    public func rawOffset(_ offset: Int, end: Bool = false) -> Int {
        map(offset, end: end, forward: false)
    }
    private func map(_ offset: Int, end: Bool, forward: Bool) -> Int {
        var delta = 0
        for token in tokens {
            let source = forward ? token.raw : token.display
            let target = forward ? token.display : token.raw
            if offset <= source.lowerBound { break }
            if offset < source.upperBound { return end ? target.upperBound : target.lowerBound }
            delta += target.count - source.count
        }
        return offset + delta
    }

    public func replacingDisplay(with edited: String) -> (text: String, caret: Int) {
        guard edited != display else { return (raw, raw.utf8.count) }
        var oldStart = display.startIndex, newStart = edited.startIndex
        while oldStart < display.endIndex, newStart < edited.endIndex, display[oldStart] == edited[newStart] {
            oldStart = display.index(after: oldStart); newStart = edited.index(after: newStart)
        }
        var oldEnd = display.endIndex, newEnd = edited.endIndex
        while oldEnd > oldStart, newEnd > newStart,
            display[display.index(before: oldEnd)] == edited[edited.index(before: newEnd)]
        {
            oldEnd = display.index(before: oldEnd); newEnd = edited.index(before: newEnd)
        }
        let lower = rawOffset(display.utf8.distance(from: display.startIndex, to: oldStart))
        let upper = rawOffset(display.utf8.distance(from: display.startIndex, to: oldEnd), end: true)
        let a = raw.utf8.index(raw.startIndex, offsetBy: lower)
        let b = raw.utf8.index(raw.startIndex, offsetBy: upper)
        let inserted = String(edited[newStart..<newEnd])
        return (String(raw[..<a]) + inserted + raw[b...], lower + inserted.utf8.count)
    }
}
