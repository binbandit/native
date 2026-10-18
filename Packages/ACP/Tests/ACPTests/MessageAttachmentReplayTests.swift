import Foundation
import Testing

@testable import ACP

/// Reloaded prompts whose files and images the agent replays as text. The lines are captured from
/// `session/load` on codex-acp 2.2.2 after Native sent an image block and an embedded text file;
/// only the image's base64 is shortened.
struct MessageAttachmentReplayTests {
    static let codexReplay = [
        #"{"sessionId":"01a14deb","update":{"sessionUpdate":"user_message_chunk","messageId":"01a14deb-a995","content":{"type":"text","text":"What does this image show? Answer in one short sentence."}}}"#,
        #"{"sessionId":"01a14deb","update":{"sessionUpdate":"user_message_chunk","messageId":"01a14deb-a995","content":{"type":"text","text":"[@image](data:image/png;base64,AQID)"}}}"#,
        #"{"sessionId":"01a14deb","update":{"sessionUpdate":"agent_message_chunk","messageId":"msg_05c670b4","content":{"type":"text","text":"The image shows a red circle beside the yellow word “BANANA” on a blue background."}}}"#,
        #"{"sessionId":"01a14deb","update":{"sessionUpdate":"user_message_chunk","messageId":"01a14ded-86e2","content":{"type":"text","text":"What is the first line of the attached file? Reply with just that line."}}}"#,
        #"{"sessionId":"01a14deb","update":{"sessionUpdate":"user_message_chunk","messageId":"01a14ded-86e2","content":{"type":"text","text":"[@notes.txt](file:///tmp/attachments-probe/project/files/notes.txt)\n<context ref=\"file:///tmp/attachments-probe/project/files/notes.txt\">\nThe quick brown fox jumps over the lazy dog.\nSecond line here.\n\n</context>"}}}"#,
    ]

    @Test func codexReplaysImagesAndFilesAsAttachments() throws {
        var state = SessionState()
        for line in Self.codexReplay {
            state.apply(try JSONDecoder().decode(SessionNotification.self, from: Data(line.utf8)).update)
        }
        let users = state.items.compactMap { item -> TranscriptMessage? in
            if case .message(let message) = item, message.role == .user { message } else { nil }
        }
        #expect(
            users.map(\.text) == [
                "What does this image show? Answer in one short sentence.",
                "What is the first line of the attached file? Reply with just that line.",
            ])
        #expect(users.first?.attachments.first?.imageData == Data([1, 2, 3]))
        #expect(users.last?.attachments.map(\.name) == ["notes.txt"])
        #expect(users.last?.attachments.first?.url == URL(filePath: "/tmp/attachments-probe/project/files/notes.txt"))
    }

    /// Claude Code keeps an embedded file's link and its contents as separate blocks: one file.
    @Test func claudeCodeLinkAndContextAreOneFile() {
        var state = SessionState()
        let blocks: [ContentBlock] = [
            .text("Summarize it"),
            .text("[@My%20Notes.md](file:///repo/My%20Notes.md)"),
            .text("\n<context ref=\"file:///repo/My%20Notes.md\">\n# Notes\n</context>"),
        ]
        for block in blocks {
            state.apply(.userMessageChunk(ContentChunk(content: block, messageId: "u1")))
        }
        guard case .message(let message) = state.items.last else {
            Issue.record("no message")
            return
        }
        #expect(message.text == "Summarize it")
        #expect(message.attachments.map(\.name) == ["My Notes.md"])
    }

    @Test func textThatOnlyQuotesALinkStaysText() {
        for text in [
            "See [@a.swift](file:///repo/a.swift) for details",
            "[@a.swift](file:///repo/a.swift) and more",
            "[@image](data:text/plain;base64,AQID)",
            "[@x](not a uri)",
            "<context ref=\"file:///a\">unterminated",
        ] {
            #expect(MessageAttachment(replayedText: text) == nil, "\(text)")
        }
    }
}
