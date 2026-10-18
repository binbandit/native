import Foundation
import Testing

@testable import Search

struct HistoryReaderTests {
    private let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil)

    @Test func readsAClaudeCodeSession() throws {
        let root = try #require(fixtures).appending(path: "claude")
        let reader = ClaudeCodeHistoryReader(root: root)
        let source = try #require(reader.sources().first)
        let session = try #require(try reader.read(source))
        #expect(session.sessionID == "5f0c2a7e-1111-4222-8333-944445555666")
        #expect(session.title == "Fix flaky login timeout")
        #expect(session.cwd == "/repo")
        #expect(session.documents.map(\.role) == [.user, .thought, .agent, .tool, .tool, .plan, .tool, .agent])
        let bash = session.documents[3]
        #expect(bash.anchor == .toolCall(id: "toolu_01Search"))
        #expect(bash.text.contains("rg -n loginTimeout native/Models"))
        #expect(bash.text.contains("static let loginTimeout"))
        #expect(session.documents[4].hasDiff)
        #expect(session.documents[4].text.contains("The file has been updated."))
        #expect(session.documents[5].text == "Raise the login timeout\nAdd a retry on token refresh")
        // Injected context, sidechains and API request blobs aren't part of the conversation.
        let text = session.documents.map(\.text).joined()
        #expect(!text.contains("Caveat") && !text.contains("compact") && !text.contains("Subagent chatter"))
        #expect(!text.contains("A request body"))
        #expect(session.documents[0].anchor == .message(startingWith: "Fix the flaky login timeout in SessionStore.swift"))
    }

    @Test func readsACodexRollout() throws {
        let home = try #require(fixtures).appending(path: "codex")
        let reader = CodexHistoryReader(root: home.appending(path: "sessions"), index: home.appending(path: "session_index.jsonl"))
        let source = try #require(reader.sources().first)
        let session = try #require(try reader.read(source))
        #expect(session.sessionID == "0199aaaa-bbbb-7ccc-8ddd-eeeeffff0000")
        #expect(session.title == "Orders migration rollback")
        #expect(session.cwd == "/work/orders")
        #expect(session.documents.map(\.role) == [.user, .thought, .tool, .tool, .plan, .tool, .agent])
        #expect(session.documents[0].text == "Write a migration rollback plan for the orders table")
        let exec = session.documents[2]
        #expect(exec.anchor == .toolCall(id: "call_exec1"))
        #expect(exec.text.contains("cargo test -p orders migration_rollback"))
        #expect(exec.text.contains("3 passed"))
        let patch = session.documents[3]
        #expect(patch.hasDiff)
        #expect(patch.text.contains("src/migrations/0042_orders_index.rs"))
        #expect(patch.text.contains("Success. Updated"))
        #expect(session.documents[4].text == "Drop the new index first\nRestore the old column")
        #expect(!session.documents.contains { $0.text.contains("environment_context") || $0.text.contains("sandboxed") })
    }

    @Test func injectedContextIsRecognized() {
        #expect(HistoryTranscriptBuilder.isInjectedContext("<environment_context>\n<cwd>/x</cwd>\n</environment_context>"))
        #expect(HistoryTranscriptBuilder.isInjectedContext("# AGENTS.md instructions for /x\n\nrules"))
        #expect(!HistoryTranscriptBuilder.isInjectedContext("<div> is rendering twice, why?"))
        #expect(!HistoryTranscriptBuilder.isInjectedContext("Fix the bug"))
    }
}
