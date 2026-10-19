import Foundation
import Testing

@testable import ACP

struct HiddenCommandCaptureTests {
    /// claude-agent-acp 0.93.0 answering `/context`: the report, then its mirror (another message
    /// id, two more characters of whitespace). Shortened from a captured 10 KB report.
    private static let report = """
        ## Context Usage

        **Model:** claude-opus-5-5
        **Tokens:** 246.3k / 1m (25%)

        ### Estimated usage by category

        | Category | Tokens | Percentage |
        |----------|--------|------------|
        | System prompt | 2.1k | 0.2% |
        | Messages | 6.8k | 0.7% |

        """

    private func chunk(_ text: String, id: String) -> SessionUpdate {
        .agentMessageChunk(ContentChunk(content: .text(text), messageId: id))
    }

    @Test func takesOnlyTheReply() {
        var capture = HiddenCommandCapture()
        let tookReply = capture.capture(chunk(Self.report, id: "fb2c68b5"))
        let tookPlan = capture.capture(.plan([]))
        #expect(tookReply)
        #expect(!tookPlan)
        #expect(capture.output == Self.report)
    }

    @Test func recognizesTheMirrorThatTrailsTheTurn() {
        var capture = HiddenCommandCapture()
        _ = capture.capture(chunk(Self.report, id: "fb2c68b5"))
        #expect(capture.isEcho(chunk(Self.report + "\n\n", id: "6181be30")))
    }

    @Test func letsEverythingElseThrough() {
        var capture = HiddenCommandCapture()
        _ = capture.capture(chunk(Self.report, id: "fb2c68b5"))
        #expect(!capture.isEcho(chunk("Here's what I changed.", id: "msg_1")))
        #expect(!capture.isEcho(chunk("\n\n", id: "msg_2")))
        #expect(!capture.isEcho(.agentThoughtChunk(ContentChunk(content: .text("## Context Usage")))))
    }
}
