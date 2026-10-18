import Testing

@testable import CodeThemes

/// Code that changes while it's shown: a code block streaming into a reply.
@MainActor
struct LiveCodeHighlighterTests {
    private let python = CodeLanguage.named("python")
    private let code = """
        def label(user, width=10):
            n = len(user.items)
            return f"{user.name!r:>{width}} has {n} {'item' if n == 1 else 'items'}"
        """

    /// The code as it streams in, a few characters at a time.
    private var versions: [String] {
        stride(from: 1, through: code.count, by: 3).map { String(code.prefix($0)) } + [code]
    }

    @Test func theLastVersionAlwaysGetsItsColors() async {
        let highlighter = LiveCodeHighlighter(cache: CodeHighlightCache(), interval: .milliseconds(5))
        for version in versions {
            _ = highlighter.segments(for: version, language: python)
        }
        await highlighter.settled()
        #expect(highlighter.segments(for: code, language: python) == CodeHighlighter.segments(code, language: python))
    }

    @Test func growingCodeKeepsTheColorsItHad() async throws {
        let highlighter = LiveCodeHighlighter(cache: CodeHighlightCache())
        let start = String(code.prefix(40))
        _ = highlighter.segments(for: start, language: python)
        await highlighter.settled()
        let colors = try #require(highlighter.segments(for: start, language: python))

        let grown = try #require(highlighter.segments(for: code, language: python))
        #expect(grown.map(\.text).joined() == code)
        #expect(Array(grown.prefix(colors.count - 1)) == Array(colors.dropLast()))
        #expect(grown.last == CodeSegment(String(code.dropFirst(40)), .foreground))
    }

    @Test func finishedCodeIsCachedOnce() async {
        let cache = CodeHighlightCache()
        let highlighter = LiveCodeHighlighter(cache: cache, interval: .zero)
        let start = String(code.prefix(40))
        _ = highlighter.segments(for: start, language: python)
        await highlighter.settled()
        _ = highlighter.segments(for: code, language: python)
        await highlighter.settled()
        #expect(cache.cached(start, language: python) == nil)
        #expect(cache.cached(code, language: python) == CodeHighlighter.segments(code, language: python))
    }

    @Test func cachedCodeDrawsAtOnce() async {
        let cache = CodeHighlightCache()
        _ = await cache.highlight(code, language: python)
        let highlighter = LiveCodeHighlighter(cache: cache)
        #expect(highlighter.segments(for: code, language: python) == CodeHighlighter.segments(code, language: python))
    }

    @Test func unknownLanguagesDrawPlain() {
        #expect(LiveCodeHighlighter().segments(for: code, language: nil) == nil)
    }

    @Test(arguments: [
        ("let a = 1", "let a = 12"),
        ("let a = 12", "let a"),
        ("let a = \"x\"", "let b = \"x\""),
        ("let s = \"e\u{301}\"", "let s = \"e\u{301}\u{301}!\""),
        ("let a = 1", ""),
    ])
    func reusedSegmentsRebuildTheNewCode(previous: String, code: String) {
        let segments = CodeHighlighter.segments(previous, language: .named("swift"))
        let reused = CodeHighlighter.reused(segments, of: previous, for: code)
        #expect(reused.map(\.text).joined() == code)
        #expect(reused.allSatisfy { !$0.text.isEmpty })
    }

    @Test func reusedSegmentsKeepTheSharedStart() {
        let previous = "let a = 1"
        let segments = CodeHighlighter.segments(previous, language: .named("swift"))
        let reused = CodeHighlighter.reused(segments, of: previous, for: "let a = 12")
        #expect(reused.dropLast() == segments[...])
        #expect(reused.last == CodeSegment("2", .foreground))
    }
}
