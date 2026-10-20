import Testing

@testable import ACP

struct ToolErrorMarkupTests {
    /// What the hook said, exactly, in the captured replay's failed command.
    static let hookMessage =
        "Blocked: standalone sleep 30. To wait for a condition, use Monitor with an until-loop (e.g. `until <check>; "
        + "do sleep 2; done`). To wait for a command you started, use run_in_background: true. Do not chain shorter "
        + "sleeps to work around this block."

    @Test func aCapturedToolUseErrorReadsAsItsMessage() throws {
        var state = SessionState()
        for line in InterruptionMarkerTests.replay {
            state.apply(try Wire.update(line))
        }
        let call = try #require(
            state.items.lazy.compactMap { item -> ToolCallState? in
                if case .toolCall(let call) = item { call } else { nil }
            }.first)
        #expect(call.status == .failed)

        let rawOutput = try #require(call.rawOutput?.stringValue)
        #expect(ToolErrorMarkup.stripped(rawOutput) == Self.hookMessage)
        // The content repeats it in a code fence, which the transcript takes off first.
        guard case .content(let block) = call.content.first, let text = block.text,
            case .code(let body, _, _)? = FencedText.segments(of: text).first
        else {
            Issue.record("Expected fenced content, got \(call.content)")
            return
        }
        #expect(ToolErrorMarkup.stripped(body) == Self.hookMessage)
    }

    @Test func anAbortedCommandKeepsWhatItPrinted() {
        // Claude Code 2.1.304's own words for a command it aborted.
        let aborted = "<error>Command was aborted before completion</error>"
        let output = "PING 127.0.0.1 (127.0.0.1): 56 data bytes\n64 bytes from 127.0.0.1: icmp_seq=0 ttl=64\n"
        #expect(
            ToolErrorMarkup.stripped(output + aborted) == output + "Command was aborted before completion")
        #expect(ToolErrorMarkup.stripped(aborted) == "Command was aborted before completion")
    }

    @Test func textThatOnlyMentionsATagStaysAsIs() {
        for text in [
            "Exit code 1\nerror: no such file",
            "Wrap failures in <tool_use_error> tags",
            "<tool_use_error>one</tool_use_error>\n<tool_use_error>two</tool_use_error>",
            "<error>an earlier line</error>\nthen more output",
            "<errors>3</errors>",
            "",
        ] {
            #expect(ToolErrorMarkup.stripped(text) == text)
        }
    }
}
