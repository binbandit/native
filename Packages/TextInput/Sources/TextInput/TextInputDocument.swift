import Foundation

/// An editor document. Mentions occupy one UTF-16 unit in the editor and expand for the agent.
/// Typed `@path` remains text until a caller explicitly accepts a file suggestion.
public struct TextInputDocument: Equatable, Sendable {
    public enum Run: Equatable, Sendable {
        case text(String)
        case mention(path: String)

        public var plainText: String {
            switch self {
            case .text(let text): text
            case .mention(let path):
                path.contains(where: { $0.isWhitespace || $0 == "\"" || $0 == "\\" })
                    ? "@\""
                        + path.replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "\"", with: "\\\"") + "\"" : "@" + path
            }
        }

        public var displayText: String {
            switch self {
            case .text(let text): text
            case .mention: "\u{FFFC}"
            }
        }
    }

    public let runs: [Run]

    public init(_ text: String = "") { self.init(runs: [.text(text)]) }

    public init(runs: [Run]) {
        var normalized: [Run] = []
        for run in runs {
            if case .text(let text) = run {
                guard !text.isEmpty else { continue }
                if case .text(let previous) = normalized.last {
                    normalized.removeLast()
                    normalized.append(.text(previous + text))
                    continue
                }
            }
            normalized.append(run)
        }
        self.runs = normalized
    }

    public var plainText: String { runs.map(\.plainText).joined() }
    public var displayText: String { runs.map(\.displayText).joined() }

    /// UTF-16 offsets match NSTextView/UITextView. Invalid or split-grapheme ranges are rejected.
    public func slice(_ range: NSRange) -> Self? {
        guard Self.validRange(range, in: displayText) != nil else { return nil }
        var offset = 0
        var selected: [Run] = []
        for run in runs {
            let length = run.displayText.utf16.count
            let intersection = NSIntersectionRange(range, NSRange(location: offset, length: length))
            if intersection.length > 0 {
                if case .text(let text) = run {
                    let local = NSRange(location: intersection.location - offset, length: intersection.length)
                    guard let indices = Range(local, in: text) else { return nil }
                    selected.append(.text(String(text[indices])))
                } else {
                    selected.append(run)
                }
            }
            offset += length
        }
        return Self(runs: selected)
    }

    public static func validRange(_ range: NSRange, in text: String) -> Range<String.Index>? {
        guard range.location >= 0, range.length >= 0, range.location <= text.utf16.count,
            range.length <= text.utf16.count - range.location,
            let indices = Range(range, in: text),
            NSRange(indices, in: text) == range,
            indices.lowerBound == text.endIndex || text.indices.contains(indices.lowerBound),
            indices.upperBound == text.endIndex || text.indices.contains(indices.upperBound)
        else { return nil }
        return indices
    }

    /// Accept a completion using the range from `TextInputQuery`. Native edits still use native undo.
    public func replacing(_ range: NSRange, with replacement: Self) -> Self? {
        let length = displayText.utf16.count
        guard range.location >= 0, range.length >= 0, range.location <= length,
            range.length <= length - range.location,
            let head = slice(NSRange(location: 0, length: range.location)),
            let tail = slice(NSRange(location: NSMaxRange(range), length: length - NSMaxRange(range)))
        else { return nil }
        return Self(runs: head.runs + replacement.runs + tail.runs)
    }
}
