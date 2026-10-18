import Synchronization

/// Highlighting off the main thread, cached by content: views draw `cached(_:language:)` at once
/// (plain text when it's nil), then `highlight(_:language:)` in a task and redraw with the colors.
public final class CodeHighlightCache: Sendable {
    public static let shared = CodeHighlightCache()

    private struct Key: Hashable {
        let code: String
        let language: String?
    }

    /// Roughly how much code the cache keeps, in characters, before it starts over.
    private let budget: Int
    private let entries = Mutex<(segments: [Key: [CodeSegment]], size: Int)>(([:], 0))

    public init(budget: Int = 4_000_000) {
        self.budget = budget
    }

    /// The segments if this code was highlighted before; never does the work itself.
    public func cached(_ code: String, language: CodeLanguage?) -> [CodeSegment]? {
        let key = Key(code: code, language: language?.id)
        return entries.withLock { $0.segments[key] }
    }

    /// The segments, from the cache or highlighted on a background thread.
    public func highlight(_ code: String, language: CodeLanguage?) async -> [CodeSegment] {
        if let cached = cached(code, language: language) {
            return cached
        }
        let segments = await Self.work(code, language: language)
        let key = Key(code: code, language: language?.id)
        entries.withLock { entries in
            if entries.size + code.utf8.count > budget {
                entries = ([:], 0)
            }
            entries.segments[key] = segments
            entries.size += code.utf8.count
        }
        return segments
    }

    /// The code's lines as segments (see `CodeHighlighter.lines`), highlighted the same way.
    public func highlightLines(_ code: String, language: CodeLanguage?) async -> [[CodeSegment]] {
        CodeHighlighter.lines(
            segments: await highlight(code, language: language), endsWithNewline: code.hasSuffix("\n"))
    }

    @concurrent private static func work(_ code: String, language: CodeLanguage?) async -> [CodeSegment] {
        CodeHighlighter.segments(code, language: language)
    }
}
