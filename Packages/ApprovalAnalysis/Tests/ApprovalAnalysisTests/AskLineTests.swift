import ApprovalAnalysis
import Foundation
import Testing

@testable import ACP

@Suite struct AskLineTests {
    private func ask(_ call: ToolCallState, place: String? = nil, branch: String? = nil) -> String {
        AskLine(call: call, workingDirectory: "/repo", pushPlace: place, pushBranch: branch).text
    }

    private func command(_ command: String) -> ToolCallState {
        var call = ToolCallState(id: "command", title: "Allow python3?", kind: .execute)
        call.rawInput = .object(["command": .string(command)])
        return call
    }

    @Test(arguments: [
        ("swift test --filter PermissionRequestTests", "Run `swift test`?"),
        ("/usr/bin/swift build", "Run `swift build`?"),
        ("git status --short", "Run `git status`?"),
        ("gh pr view 42", "Run `gh pr view`?"),
        ("npm test", "Run `npm test`?"),
        ("python3 -m unittest", "Run `python3`?"),
        ("./scripts/check.sh", "Run `check.sh`?"),
        ("git push -u origin feature", "Run `git push`?"),
    ])
    func commandsUseReviewedSubcommands(command: String, expected: String) {
        #expect(ask(self.command(command)) == expected)
    }

    @Test(arguments: [
        "swift test && git push --force origin main", "swift test; rm -rf /repo",
        "swift test\nrm -rf /repo", "swift test | cat", "swift test $(rm file)",
        "git push --unknown origin main", "'unclosed", "", "rm -rf *",
    ])
    func unsupportedCommandsDoNotDescribeOnlyAFamiliarPrefix(_ command: String) {
        #expect(ask(self.command(command)) == "Run this command?")
    }

    @Test(arguments: [
        ("git push --force origin main:main", "Overwrite `main` on origin?"),
        ("git push origin +HEAD:refs/heads/main", "Overwrite `main` on origin?"),
        ("git push origin :old-topic", "Delete `old-topic` on origin?"),
        ("git push --delete origin old-topic", "Delete `old-topic` on origin?"),
        ("git push --force origin main", "Overwrite refs on origin?"),
        ("rm -rf build", "Delete `build`?"),
        ("rm a b", "Delete 2 files or folders?"),
        ("git reset --hard origin/main", "Replace index and working tree content?"),
        ("git clean -fdx", "Remove untracked files?"),
        ("npm publish", "Publish a package?"),
    ])
    func irreversibleCommandsNameTheirConsequence(command: String, expected: String) {
        #expect(ask(self.command(command)) == expected)
    }

    @Test func pushUsesResolvedContextWithoutGuessingTheDestination() {
        let call = command("git push --force origin HEAD")
        #expect(ask(call, place: "github.com", branch: "main") == "Overwrite `main` on github.com?")
        #expect(ask(call, place: "github.com") == "Overwrite refs on github.com?")
    }

    @Test func editsCountFilesOnceUsingTheExistingSummary() throws {
        let update = try JSONDecoder().decode(
            ToolCallUpdate.self,
            from: Data(
                #"{"toolCallId":"edit","kind":"edit","locations":[{"path":"/repo/a.swift"},{"path":"/repo/a.swift"},{"path":"/repo/b.swift"},{"path":"/repo/c.swift"}]}"#
                    .utf8))
        let permission = RequestPermissionRequest(sessionId: SessionID("fixture"), toolCall: update, options: [])
        #expect(AskLine(permission: permission, workingDirectory: "/repo").text == "Edit 3 files?")
    }

    @Test func deletionNamesTheFileOrTheCount() {
        var call = ToolCallState(id: "delete", title: "Delete /repo/greet.py", kind: .delete)
        #expect(ask(call) == "Delete `greet.py`?")
        call.locations = (1...14).map { ToolCallLocation(path: "/repo/file\($0).swift") }
        #expect(ask(call) == "Delete 14 files?")
    }

    @Test func fetchNamesOnlyTheHost() {
        var call = ToolCallState(id: "fetch", title: "WebFetch", kind: .fetch)
        call.rawInput = .object(["url": .string("https://docs.swift.org/documentation/?query=private")])
        #expect(ask(call) == "Open docs.swift.org?")
    }

    @Test func codexFetchUsesTheSameHostWording() {
        let call = ToolCallState(id: "fetch", title: "Open page: https://docs.swift.org/guide", kind: .search)
        #expect(ask(call) == "Open docs.swift.org?")
    }

    @Test(arguments: [
        #"["/bin/zsh","-lc","swift test --filter PermissionRequestTests"]"#,
        #"["swift","test","--filter","PermissionRequestTests"]"#,
        #""swift test --filter PermissionRequestTests""#,
    ])
    func commandShapesUseACPsExistingDecoder(_ json: String) throws {
        var call = ToolCallState(id: "command", kind: .execute)
        call.rawInput = .object(["command": try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))])
        #expect(ask(call) == "Run `swift test`?")
    }

    @Test func mcpUsesTheExistingServerAndToolExtraction() {
        var call = ToolCallState(id: "mcp", kind: .other)
        call.name = "mcp__tracker__create_issue"
        #expect(ask(call) == "Use `create_issue` from `tracker`?")
        call.name = nil
        call.kind = .execute
        call.title = "mcp.tracker.create_issue"
        call.rawInput = .object(["server": .string("tracker"), "tool": .string("create_issue")])
        #expect(ask(call) == "Use `create_issue` from `tracker`?")
    }

    @Test func questionKeepsTheActualWordsInsteadOfItsHeader() {
        var call = ToolCallState(id: "question", kind: .other)
        call.name = "AskUserQuestion"
        call.rawInput = .object([
            "questions": .array([
                .object(["header": .string("Template"), "question": .string("Use the repo's PR template?")])
            ])
        ])
        #expect(ask(call) == "Use the repo's PR template?")
        #expect(AskLine(question: "  Use the repo's\n PR template?  ").text == "Use the repo's PR template?")
    }

    @Test func planCountsOnlyStructuredSteps() {
        #expect(AskLine(planStepCount: 6).text == "Plan ready: 6 steps")
        #expect(AskLine(planStepCount: 1).text == "Plan ready: 1 step")
        #expect(AskLine(planStepCount: 0).text == "Plan ready")
        #expect(ask(ToolCallState(id: "plan", title: "ExitPlanMode", kind: .switchMode)) == "Plan ready")
    }

    @Test func failureWordsComeFromKnownCausesAndRecoveredFailuresHaveNoLine() {
        #expect(AskLine(failure: .overloaded(model: "Opus 5.5"))?.text == "Opus 5.5 was overloaded")
        #expect(AskLine(failure: .signIn(agent: "Claude Code"))?.text == "Claude Code needs you to sign in")
        #expect(AskLine(failure: .pushBranchMoved(branch: "main"))?.text == "Couldn't push: `main` moved")
        #expect(
            AskLine(failure: .other(message: "The agent stopped.\nDiagnostic details"))?.text == "The agent stopped.")
        #expect(AskLine(failure: .other(message: "  "))?.text == "The task stopped unexpectedly")
        #expect(AskLine(failure: .overloaded(model: "Opus 5.5"), recovered: true) == nil)
    }

    @Test func missingInputsNeverLeakToolNames() {
        var call = ToolCallState(id: "unknown", title: "Allow InternalTool42?")
        call.name = "InternalTool42"
        #expect(ask(call) == "Review this request?")
        call.kind = .execute
        #expect(ask(call) == "Run this command?")
    }

    @Test func codeNamesRemainOneInlineSpanAndOneLine() {
        #expect(ask(command("rm 'a`b'")) == "Run this command?")
        let text = AskLine(failure: .pushBranchMoved(branch: "a`b\nnext"))?.text
        #expect(text == "Couldn't push: ``a`b next`` moved")
    }
}

extension AskLineTests {
    private struct Envelope<Params: Decodable>: Decodable {
        let params: Params
    }

    @Test(arguments: [
        (AskLineCaptures.claudeWrite, "Edit `out.txt`?"),
        (AskLineCaptures.codexCommand, "Run this command?"),
    ])
    func capturedPermissionRequests(json: String, expected: String) throws {
        let request = try JSONDecoder().decode(
            Envelope<RequestPermissionRequest>.self, from: Data(json.utf8)
        ).params
        #expect(AskLine(permission: request, workingDirectory: "/repo").text == expected)
        var state = SessionState()
        state.requestPermission(request, id: .int(0))
        let call = try #require(state.permissionRequests.first)
        #expect(ask(call) == expected)
    }

    @Test func capturedCodexMCPKeepsTheToolAndServer() throws {
        let notification = try JSONDecoder().decode(
            Envelope<SessionNotification>.self, from: Data(AskLineCaptures.codexMCP.utf8)
        ).params
        var state = SessionState()
        state.apply(notification.update)
        guard case .toolCall(let call)? = state.items.first else {
            Issue.record("Expected a captured MCP call")
            return
        }
        #expect(ask(call) == "Use `setup_status` from `native`?")
    }

    @Test func capturedClaudeQuestionKeepsItsQuestion() throws {
        let update = try JSONDecoder().decode(ToolCallUpdate.self, from: Data(AskLineCaptures.claudeQuestion.utf8))
        let start = try JSONDecoder().decode(
            ToolCallUpdate.self, from: Data(AskLineCaptures.claudeQuestionStart.utf8))
        var state = SessionState()
        state.apply(.toolCall(start))
        state.apply(.toolCallUpdate(update))
        guard case .toolCall(let call)? = state.items.first else {
            Issue.record("Expected a captured question")
            return
        }
        #expect(ask(call) == "Which color do you prefer?")
    }
}
