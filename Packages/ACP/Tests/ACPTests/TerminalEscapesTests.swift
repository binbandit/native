import Testing

@testable import ACP

struct TerminalEscapesTests {
    /// The shape of codex-acp's stderr: a dimmed timestamp and a red level.
    @Test func colorsAreRemoved() {
        let stderr = "\u{1B}[2m2026-10-18T01:02:03.456Z\u{1B}[0m \u{1B}[31mERROR\u{1B}[0m codex_core: stream disconnected"
        #expect(stderr.withoutTerminalEscapes == "2026-10-18T01:02:03.456Z ERROR codex_core: stream disconnected")
    }

    @Test func titlesCursorMovesAndControlCharactersAreRemoved() {
        let text = "\u{1B}]0;codex\u{07}\u{1B}[2K\rfirst\u{1B}(B line\n\tsecond\u{08}\u{1B}]8;;https://x\u{1B}\\link"
        #expect(text.withoutTerminalEscapes == "first line\n\tsecondlink")
    }

    @Test func plainTextIsUnchanged() {
        let text = "Couldn't reach the server: [error] timed out ✓"
        #expect(text.withoutTerminalEscapes == text)
    }

    @Test func aTrailingEscapeIsDropped() {
        #expect("done\u{1B}".withoutTerminalEscapes == "done")
        #expect("done\u{1B}[31".withoutTerminalEscapes == "done")
    }
}
