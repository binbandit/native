import Foundation
import Testing

@testable import Search

struct HistoryReaderTests {
    private let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil)

    @Test func readsAClaudeCodeSession() throws {
        let root = try #require(fixtures).appending(path: "claude")
        let reader = ClaudeCodeHistoryReader(root: root)
        let source = try #require(reader.sources().first)
        let session = try #require(try reader.read(source, resuming: nil).session)
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
        #expect(
            session.documents[0].anchor == .message(startingWith: "Fix the flaky login timeout in SessionStore.swift"))
    }

    @Test func readsACodexRollout() throws {
        let home = try #require(fixtures).appending(path: "codex")
        let reader = CodexHistoryReader(
            root: home.appending(path: "sessions"), index: home.appending(path: "session_index.jsonl"))
        let source = try #require(reader.sources().first)
        let session = try #require(try reader.read(source, resuming: nil).session)
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
        #expect(
            !session.documents.contains { $0.text.contains("environment_context") || $0.text.contains("sandboxed") })
    }

    @Test func resumesAFileThatGrew() throws {
        let root = URL.temporaryDirectory.appending(path: "history-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "-repo")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let original = try #require(fixtures).appending(path: "claude/-repo/5f0c2a7e-1111-4222-8333-944445555666.jsonl")
        let file = folder.appending(path: "5f0c2a7e-1111-4222-8333-944445555666.jsonl")
        try FileManager.default.copyItem(at: original, to: file)
        let reader = ClaudeCodeHistoryReader(root: root)
        let first = try reader.read(try #require(reader.sources().first), resuming: nil)
        let session = try #require(first.session)

        // A turn lands, and the next one is still being written when the file is read again.
        let appended = """
            {"parentUuid":"x","isSidechain":false,"type":"user","message":{"role":"user","content":"Now add a test for the retry"},"uuid":"u9","timestamp":"2026-10-01T10:00:00.000Z","cwd":"/repo","sessionId":"5f0c2a7e-1111-4222-8333-944445555666"}
            {"type":"ai-title","aiTitle":"Login timeout and retry test","sessionId":"5f0c2a7e-1111-4222-8333-944445555666"}
            {"parentUuid":"u9","isSidechain":false,"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Half wri
            """
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(appended.utf8))
        try handle.close()

        let resume = HistoryResume(offset: first.offset, sessionID: session.sessionID, cwd: session.cwd)
        let second = try reader.read(try #require(reader.sources().first), resuming: resume)
        let added = try #require(second.session)
        #expect(added.documents.map(\.text) == ["Now add a test for the retry"])
        #expect(added.title == "Login timeout and retry test")
        // The half-written line is left for the next read.
        let size = try #require(
            try FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))[.size] as? Int)
        #expect(second.offset > first.offset && second.offset < size)
    }

    @Test func injectedContextIsRecognized() {
        #expect(
            HistoryTranscriptBuilder.isInjectedContext("<environment_context>\n<cwd>/x</cwd>\n</environment_context>"))
        #expect(HistoryTranscriptBuilder.isInjectedContext("# AGENTS.md instructions for /x\n\nrules"))
        #expect(!HistoryTranscriptBuilder.isInjectedContext("<div> is rendering twice, why?"))
        #expect(!HistoryTranscriptBuilder.isInjectedContext("Fix the bug"))
        #expect(HistoryTranscriptBuilder.isInjectedContext("[Request interrupted by user for tool use]"))
        #expect(!HistoryTranscriptBuilder.isInjectedContext("Why did I see [Request interrupted by user]?"))
    }
}
