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
    /// Native editor undo restores attributes along with visible text. The full path travels
    /// with that text so restoring a deleted token never turns its basename/counts into prose.
    public struct RestoredToken: Equatable, Sendable {
        public let display: Range<Int>
        public let raw: String

        public init(display: Range<Int>, raw: String) { self.display = display; self.raw = raw }
    }
    public let raw: String
    public let display: String
    public let tokens: [Token]

    public init(
        _ raw: String, counts: [String: Counts] = [:], enabled: Bool = true,
        tokenPadding: String = "", formatCount: (Int) -> String = { String($0) }
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
            output += tokenPadding
            output += path.split(separator: "/").last.map(String.init) ?? path
            if let count {
                if count.added > 0 { output += " +\(formatCount(count.added))" }
                if count.removed > 0 { output += " −\(formatCount(count.removed))" }
            }
            output += tokenPadding
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

    /// The editor's own selection in `typed`, in this draft's offsets, when the draft reads exactly as
    /// `typed`. The editor knows where an edit happened; a text diff can't tell among repeated
    /// characters, so `replacingDisplay`'s caret is only for edits that changed a token.
    public func rawSelection(_ selection: Range<Int>, showing typed: String) -> Range<Int>? {
        guard display == typed else { return nil }
        return rawOffset(selection.lowerBound)..<rawOffset(selection.upperBound, end: !selection.isEmpty)
    }

    public func replacingDisplay(with edited: String, restored: [RestoredToken] = []) -> (text: String, caret: Int) {
        let restored = restored.filter {
            $0.display.lowerBound >= 0 && $0.display.upperBound <= edited.utf8.count && !$0.display.isEmpty
        }.sorted { $0.display.lowerBound < $1.display.lowerBound }
        func canonical(_ range: Range<Int>) -> String {
            var text = ""
            var cursor = range.lowerBound
            func slice(_ bounds: Range<Int>) -> Substring {
                let a = edited.utf8.index(edited.startIndex, offsetBy: bounds.lowerBound)
                let b = edited.utf8.index(edited.startIndex, offsetBy: bounds.upperBound)
                return edited[a..<b]
            }
            for token in restored
            where token.display.lowerBound >= cursor && token.display.upperBound <= range.upperBound {
                text += slice(cursor..<token.display.lowerBound) + token.raw
                cursor = token.display.upperBound
            }
            return text + slice(cursor..<range.upperBound)
        }
        guard edited != display else {
            let text = restored.isEmpty ? raw : canonical(0..<edited.utf8.count)
            return (text, text.utf8.count)
        }
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
        var start = edited.utf8.distance(from: edited.startIndex, to: newStart)
        var end = edited.utf8.distance(from: edited.startIndex, to: newEnd)
        var oldLower = display.utf8.distance(from: display.startIndex, to: oldStart)
        var oldUpper = display.utf8.distance(from: display.startIndex, to: oldEnd)
        for token in restored {
            if token.display.lowerBound < start, start < token.display.upperBound {
                oldLower -= start - token.display.lowerBound
                start = token.display.lowerBound
            }
            if token.display.lowerBound < end, end < token.display.upperBound {
                oldUpper += token.display.upperBound - end
                end = token.display.upperBound
            }
        }
        let lower = rawOffset(oldLower)
        let upper = rawOffset(oldUpper, end: true)
        let a = raw.utf8.index(raw.startIndex, offsetBy: lower)
        let b = raw.utf8.index(raw.startIndex, offsetBy: upper)
        let inserted = canonical(start..<end)
        return (String(raw[..<a]) + inserted + raw[b...], lower + inserted.utf8.count)
    }
}
