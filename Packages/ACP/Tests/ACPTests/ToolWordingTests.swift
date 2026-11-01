import Foundation
import Testing

@testable import ACP

/// What Native says about tool calls, checked on real captured traffic: claude-agent-acp 0.93.0
/// (`Wire`, `SubagentWire`) and codex-acp 2.2.2 (`CodexToolWire`, `CodexMCPWire`,
/// `CodexCodeModeWire`).
struct ToolWordingTests {
    /// The session after `lines`. A permission request stays open unless `answered`, as the
    /// captured turn's was once the client allowed it.
    private func fold(_ lines: [String], answered: Bool = true) throws -> SessionState {
        var state = SessionState()
        state.appendUserMessage("Do it")
        for line in lines {
            switch try Wire.event(line) {
            case .sessionUpdate(let notification):
                state.apply(notification.update)
            case .permissionRequest(let id, let request):
                state.requestPermission(request, id: id)
                if answered { _ = state.resolvePermission(toolCallID: request.toolCall.toolCallId) }
            default:
                Issue.record("Unexpected line")
            }
        }
        return state
    }

    // MARK: - One call

    @Test func claudeCodeReadNamesTheFileOnceItsInputArrives() throws {
        let announced = try fold([Wire.readToolCall])
        #expect(announced.call(Wire.readToolCallID)?.sentence == "Reading a file")
        let running = try fold([Wire.readToolCall, Wire.readInputUpdate])
        #expect(running.call(Wire.readToolCallID)?.sentence == "Reading notes.txt")
        let done = try fold(Wire.promptTurn)
        let read = try #require(done.call(Wire.readToolCallID))
        #expect(read.sentence == "Read notes.txt")
        #expect(read.wording.detail == "/private/tmp/acp-research/sandbox/notes.txt")
    }

    @Test func claudeCodeWriteAsksThenCreates() throws {
        let asking = try fold(
            Array(Wire.promptTurn.prefix(while: { $0 != Wire.permissionRequest })) + [Wire.permissionRequest],
            answered: false)
        #expect(asking.call(Wire.writeToolCallID)?.sentence == "Create out.txt")
        let done = try #require(try fold(Wire.promptTurn).call(Wire.writeToolCallID))
        #expect(done.sentence == "Created out.txt")
        #expect(done.wording.lineChanges == .init(added: 1, removed: 0))
    }

    @Test func claudeCodeCommandIsTheCommandWithItsDescriptionAside() throws {
        let terminal = try fold([Wire.bashToolCall])
        // Before its input arrives the adapter titles it "Terminal", which says nothing.
        #expect(terminal.call(Wire.bashToolCallID)?.sentence == "Running a command")
        let bash = try #require(try fold(Wire.promptTurn).call(Wire.bashToolCallID))
        // `ls` only lists, so it reads as the listing it is; the description stays aside.
        #expect(bash.sentence == "Listed files")
        #expect(bash.wording.detail == "List files in current directory")
        #expect(bash.wording.category == .read)
    }

    @Test func claudeCodeSubagentIsTheTaskItWasGiven() throws {
        // Only the parent's own tool call updates; the rest belong to the subagent's session.
        let state = try fold(SubagentWire.promptTurn.filter { $0.contains(#""toolName":"Agent""#) })
        let agent = try #require(state.call(SubagentWire.agentToolCallID))
        #expect(agent.sentence == "Delegated \"Reply with hi\"")
    }

    @Test func codexCallsReadFromTheirKindAndTitle() throws {
        let state = try fold(CodexToolWire.lines)
        let sentences = [
            "exec-22338a01-0465-4d5b-b935-f17f2603d5c3", "exec-8a26cae5-d027-4589-a0bc-bc83b3c81892",
            "exec-0b5d3d1b-3ad7-46b2-9c8c-9f1f07d543a0", "exec-0d506541-e41c-46a0-b533-deb68d753ec8",
            "exec-6d9fe7cb-acb8-4071-a0b6-313204851627", "exec-b6290148-eb0a-48d8-8eb2-9387957aec73",
        ].map { state.call($0)?.sentence }
        #expect(
            sentences == [
                "Listed files", "Reading calc.py", "Searching for \"def\"",
                "Ran python3 -c 'print(sum(range(1000)))'",
                "List does-not-exist", "Searched the web for \"swift testing parameterized tests\"",
            ])
        let failed = try #require(state.call("exec-6d9fe7cb-acb8-4071-a0b6-313204851627"))
        #expect(ToolPhase(failed).outcome(exitCode: failed.exitCode) == "Exit 1")
    }

    @Test func mcpToolsAreTheirServerAndTool() throws {
        let call = try #require(try fold([CodexMCPWire.toolCall]).call("call_mcp_1"))
        #expect(call.sentence == "Native: Setup status")
        #expect(call.wording.detail == "mcp.native.setup_status")
    }

    @Test func unknownToolsKeepTheAgentsWordsOrTheirName() {
        let titled = ToolCallState(id: "a", title: "Overwrite main on github.com")
        #expect(titled.sentence == "Overwrite main on github.com")
        var named = ToolCallState(id: "b", title: "Tool call")
        named.name = "fetch_pullRequestDetails"
        #expect(named.sentence == "Using fetch pull Request Details")
        #expect(ToolCallState(id: "c", title: "").sentence == "Using a tool")
        #expect(ToolCallState(id: "d", title: "Indexing completed").sentence == "Indexing")
    }

    @Test func searchesNameTheirFolderFromTheTasks() {
        func grep(_ path: String) -> ToolCallState {
            var call = ToolCallState(id: path, title: "grep", kind: .search, status: .completed)
            call.name = "Grep"
            call.rawInput = .object(["pattern": .string("TODO"), "path": .string(path)])
            return call
        }
        let root = "/Users/me/project/"
        #expect(
            grep("/Users/me/project").wording.relative(to: root).sentence(for: .completed) == "Searched for \"TODO\"")
        #expect(
            grep("/Users/me/project/Sources/Views").wording.relative(to: root).sentence(for: .completed)
                == "Searched for \"TODO\" in Sources/Views")
        #expect(
            grep("/elsewhere/lib").wording.relative(to: root).sentence(for: .completed)
                == "Searched for \"TODO\" in /elsewhere/lib")
        #expect(grep("/Users/me/project").sentence == "Searched for \"TODO\" in project")
        var list = ToolCallState(id: "ls", title: "ls", kind: .execute, status: .completed)
        list.rawInput = .object(["command": .string("ls /Users/me/project")])
        #expect(list.wording.relative(to: root).sentence(for: .completed) == "Listed files")
    }

    @Test(arguments: [
        (ToolPhase.running, "Running swift test"), (.completed, "Ran swift test"),
        (.awaitingApproval, "Run swift test"),
        (.rejected, "Run swift test"), (.cancelled, "Run swift test"),
    ])
    func tenseFollowsThePhase(phase: ToolPhase, sentence: String) {
        let wording = ToolCallWording(verb: .run, object: "swift test", category: .command)
        #expect(wording.sentence(for: phase) == sentence)
    }

    @Test func aCommandThatExitedNonZeroStillRan() {
        let wording = ToolCallWording(verb: .run, object: "swift test", category: .command)
        #expect(wording.sentence(for: .failed, exitCode: 1) == "Ran swift test")
        #expect(wording.sentence(for: .failed) == "Run swift test")
        #expect(ToolPhase.failed.outcome(exitCode: 1) == "Exit 1")
        #expect(ToolPhase.failed.outcome(exitCode: -1) == "Failed")
        #expect(ToolPhase.completed.outcome(exitCode: 0) == nil)
    }

    @Test(arguments: [
        ("cd /Users/me/app && swift test", "swift test"),
        ("cd \"/Users/me/my app\"; make", "make"),
        ("cd /a && cd b && git status", "git status"),
        ("python3 - <<'EOF'\nprint(1)\nEOF", "python3 - <<'EOF' …"),
        ("cd /Users/me/app", "cd /Users/me/app"),
        ("  ls -la  ", "ls -la"),
    ])
    func commandsReadAsTheirFirstLine(command: String, display: String) {
        #expect(ToolCommandLine(command).display == display)
    }

    @Test(arguments: [
        ("cat greet.py", "Read greet.py"),
        ("sed -n '1,80p' Sources/WorkingSpinnerSamples.swift", "Read WorkingSpinnerSamples.swift, lines 1-80"),
        ("nl -ba Sources/A.swift | sed -n '10,59p'", "Read A.swift, lines 10-59"),
        ("rg -n 'playful' native | head -80", "Searched for \"playful\" in native"),
        ("grep -rn \"def initials|initials\" .", "Searched for \"def initials|initials\""),
        ("rg --files Sources", "Listed Sources"),
        ("/bin/zsh -lc 'cat a.txt b.txt'", "Read a.txt and b.txt"),
        ("cat greet.py && cat test_greet.py", "Read greet.py and test_greet.py"),
        ("cat greet.py && swift test", "Ran cat greet.py && swift test"),
        ("cat a.txt > b.txt", "Ran cat a.txt > b.txt"),
        ("cat $(ls)", "Ran cat $(ls)"),
        ("rg x || true", "Ran rg x || true"),
        ("sed -i '' 's/a/b/' greet.py", "Ran sed -i '' 's/a/b/' greet.py"),
    ])
    func commandsThatOnlyReadOrSearchSaySo(command: String, sentence: String) {
        let wording = ToolCallWording.commandLine(command, description: nil, category: .command)
        #expect(wording.sentence(for: .completed) == sentence)
        #expect(wording.command == command)
    }

    @Test func aHugeCommandIsCut() {
        let display = ToolCommandLine(String(repeating: "x", count: 10_000)).display
        #expect(display.count == ToolCommandLine.maxLength + 1)
        #expect(display.hasSuffix("…"))
    }

    // MARK: - Codex code mode

    @Test func codeModeStepsReadAsWhatTheyDo() throws {
        let state = try fold(CodexCodeModeWire.lines)
        let sentences = CodexCodeModeWire.callIDs.map { state.call($0)?.sentence }
        #expect(
            sentences == [
                "Ran python3 -m unittest", "Listed files", "Searched for \"def initials|initials\"",
                "Read greet.py and test_greet.py", "Edited greet.py", "Ran sleep 40; python3 -m unittest",
            ])
        let failed = try #require(state.call(CodexCodeModeWire.callIDs[0]))
        #expect(ToolPhase(failed).outcome(exitCode: failed.exitCode) == "Exit 1")
        let edit = try #require(state.call(CodexCodeModeWire.callIDs[4]))
        #expect(edit.wording.lineChanges == .init(added: 1, removed: 1))
        let rows = TranscriptRow.rows(from: state.items)
        guard case .toolGroup(let group)? = rows.last else {
            Issue.record("Expected the steps as one group")
            return
        }
        #expect(group.summary == "Read 2 files, edited 1 file, ran 2 commands and made 2 other calls")
    }

    @Test func aCodeModeProgramSaysTheStepItTakes() {
        let search = CodexExecWire.call(
            "search",
            #"text(await tools.exec_command({cmd:"rg -n 'playful' native | head -80","max_output_tokens":4000}))"#)
        #expect(search.sentence == "Searched for \"playful\" in native")
        #expect(search.wording.category == .search)
        let patch = CodexExecWire.call(
            "patch",
            #"text(await tools.apply_patch("*** Begin Patch\n*** Update File: native/DesignSystem/DotGridLoader+Working.swift\n@@\n-let a = 1\n+let a = 2\n+let b = 3\n*** End Patch"))"#
        )
        #expect(patch.sentence == "Edited DotGridLoader+Working.swift")
        #expect(patch.wording.lineChanges == .init(added: 2, removed: 1))
        let two = CodexExecWire.call(
            "two", #"await tools.exec_command({cmd: "swift build"}); await tools.exec_command({cmd: "swift test"})"#)
        #expect(two.sentence == "Ran swift build and 1 more step")
    }

    @Test func dynamicCodeModeArgumentsKeepGenericWording() {
        for program in [
            "const cmd = 'swift test'; text(await tools.exec_command({cmd}));",
            "const patch = buildPatch(); text(await tools.apply_patch(patch));",
            "await tools.exec_command({cmd}); await tools.write_stdin({session_id:11732,chars: \"\"});",
        ] {
            let call = CodexExecWire.call("dynamic", program)
            #expect(!call.isPolling)
            #expect(call.wording.verb != .wait)
        }
    }

    @Test func explicitSearchPatternsArePreserved() {
        #expect(ToolCommandIntent("rg -n -e TODO Sources") == .search(pattern: "TODO", path: "Sources"))
        #expect(ToolCommandIntent("grep --regexp=TODO Sources") == .search(pattern: "TODO", path: "Sources"))
        #expect(ToolCommandIntent("rg -e TODO -e FIXME Sources") == nil)
        let search = CodexExecWire.call("search", #"await tools.exec_command({cmd:"rg -n -e alpha notes.txt"})"#)
        #expect(search.sentence == "Searched for \"alpha\" in notes.txt")
    }

    @Test func matchedPollingResultsBelongToTheOriginalCommand() throws {
        var command = CodexExecWire.call("run", #"await tools.exec_command({cmd:"swift test"})"#)
        command.content = [.content(.text("Process running with session ID 11732\ninitial output"))]
        var poll = CodexExecWire.call("poll", #"await tools.write_stdin({session_id:11732,chars:""})"#)
        poll.content = [.content(.text("Process exited with code 1\nFAILED: testExample"))]
        let other = CodexExecWire.call("other", #"await tools.exec_command({cmd:"swift build"})"#)
        for grouping in [true, false] {
            for grouped in [true, false] {
                let items = (grouped ? [command, poll, other] : [command, poll]).map(TranscriptItem.toolCall)
                let rows = TranscriptRow.rows(from: items, grouping: grouping)
                let visible = rows.flatMap { row -> [TranscriptItem] in
                    switch row {
                    case .item(let item): [item]
                    case .toolGroup(let group): group.items
                    }
                }
                #expect(!visible.contains { $0.toolCall?.id == poll.id })
                let result = try #require(visible.compactMap(\.toolCall).first { $0.id == command.id })
                #expect(result.status == .failed)
                #expect(result.exitCode == 1)
                #expect(result.content.contains(.content(.text("Process exited with code 1\nFAILED: testExample"))))
                #expect(
                    result.content.contains(.content(.text("Process running with session ID 11732\ninitial output"))))
            }
        }
        let group = ToolWorkGroup(items: [command, poll, other].map(TranscriptItem.toolCall))
        #expect(group.items.count == 2)
        #expect(group.calls.first?.status == .failed)
    }

    @Test func pollingTracksTheMatchingProcessAndKeepsEveryChunk() throws {
        var first = CodexExecWire.call("first", #"await tools.exec_command({cmd:"swift test"})"#)
        first.rawOutput = .object(["session_id": .number(11732)])
        var second = CodexExecWire.call("second", #"await tools.exec_command({cmd:"swift build"})"#)
        second.rawOutput = .object(["session_id": .number(221)])
        var poll = CodexExecWire.call("poll", #"await tools.write_stdin({"session_id":11732,"chars":""})"#)
        poll.rawOutput = .object(["session_id": .number(11732), "output": .string("still running")])
        poll.terminalOutput = "chunk one\n"
        var final = ToolCallState(id: "final", title: "write_stdin", name: "write_stdin", status: .completed)
        final.rawInput = .object(["session_id": .number(11732), "chars": .string("")])
        final.rawOutput = .object(["exit_code": .number(0)])
        final.terminalOutput = "chunk two\n"
        let running = TranscriptRow.rows(from: [first, second, poll].map(TranscriptItem.toolCall), grouping: false)
        #expect(running.first?.id == "tool-first")
        if case .item(.toolCall(let call))? = running.first { #expect(call.status == .inProgress) }
        let done = TranscriptRow.rows(from: [first, second, poll, final].map(TranscriptItem.toolCall), grouping: false)
        #expect(done.count == 2)
        let call = try #require(done.first.flatMap { if case .item(let item) = $0 { item.toolCall } else { nil } })
        #expect(call.status == .completed)
        #expect(call.terminalOutput == "chunk one\nchunk two\n")
        #expect(call.exitCode == 0)
        var orphan = ToolCallState(id: "orphan", title: "write_stdin", name: "write_stdin", status: .failed)
        orphan.rawInput = final.rawInput
        orphan.terminalOutput = "Unknown process"
        let rows = TranscriptRow.rows(from: [first, second, poll, final, orphan].map(TranscriptItem.toolCall))
        guard case .toolGroup(let group)? = rows.first else {
            Issue.record("Expected a group with the unmatched poll still accessible")
            return
        }
        #expect(group.calls.map(\.id) == ["first", "second", "orphan"])
    }

    @Test(arguments: [
        #"await tools.write_stdin({session_id:11732,chars:""}); await tools.write_stdin({session_id:otherSession,chars:""});"#,
        #"await tools.write_stdin({session_id:11732 + 1,chars:""});"#,
        #"await tools.write_stdin({session_id:11732,chars:answer});"#,
        #"await tools.write_stdin({session_id:"11732" + suffix,chars:""});"#,
        #"await tools.write_stdin({session_id:11732,chars:"" + answer});"#,
        #"await tools.write_stdin({session_id:11732,chars:"",...options});"#,
        #"await tools.write_stdin({session_id:11732,chars:""}); await tools.write_stdin({session_id:221,chars:""});"#,
    ])
    func unresolvedPollingInputKeepsItsOwnResults(source: String) {
        var command = CodexExecWire.call("run", #"await tools.exec_command({cmd:"swift test"})"#)
        command.rawOutput = .object(["session_id": .number(11732)])
        var other = CodexExecWire.call("other", #"await tools.exec_command({cmd:"swift build"})"#)
        other.rawOutput = .object(["session_id": .number(221)])
        var poll = CodexExecWire.call("poll", source)
        poll.content = [.content(.text("Process exited with code 0\nProcess exited with code 1\nfinal diagnostics"))]
        #expect(!poll.isPolling)
        for grouping in [true, false] {
            let rows = TranscriptRow.rows(
                from: [command, other, poll].map(TranscriptItem.toolCall), grouping: grouping)
            let calls = rows.flatMap { row -> [ToolCallState] in
                switch row {
                case .item(.toolCall(let call)): [call]
                case .toolGroup(let group): group.calls
                default: []
                }
            }
            #expect(calls == [command, other, poll])
        }
    }

    @Test(arguments: [
        #"await tools.write_stdin({session_id:11732,chars:""});"#,
        #"await tools.write_stdin({'session_id':'11732', 'chars':'', yield_time_ms:30000});"#,
        #"await tools.write_stdin({"session_id":11732});"#,
        #"await tools.write_stdin({chars:``,session_id:11732,}); await tools.write_stdin({session_id:11732,chars:""});"#,
    ])
    func fullyLiteralPollsStillFold(source: String) {
        var command = CodexExecWire.call("run", #"await tools.exec_command({cmd:"swift test"})"#)
        command.rawOutput = .object(["session_id": .number(11732)])
        var poll = CodexExecWire.call("poll", source)
        poll.content = [.content(.text("Process exited with code 0"))]
        #expect(poll.isPolling)
        let rows = TranscriptRow.rowsWithSources(from: [command, poll].map(TranscriptItem.toolCall))
        #expect(rows.count == 1)
        #expect(rows.first?.sourceIndices == [0, 1])
    }

    @Test func pollingFoldsKeepOriginalPositionsForRevealAndReasoning() throws {
        var command = CodexExecWire.call("run", #"await tools.exec_command({cmd:"swift test"})"#)
        command.rawOutput = .object(["session_id": .number(11732)])
        var poll = CodexExecWire.call("poll", #"await tools.write_stdin({session_id:11732,chars:""})"#)
        poll.content = [.content(.text("Process exited with code 0"))]
        let sleep = ToolCallState(id: "sleep", title: "sleep", name: "sleep", status: .completed)
        let thought = TranscriptMessage(role: .thought, text: "Check the build next.", startedAt: Date())
        let other = CodexExecWire.call("other", #"await tools.exec_command({cmd:"swift build"})"#)
        let reply = TranscriptMessage(role: .agent, text: "All done.")
        let items: [TranscriptItem] = [
            .toolCall(command), .toolCall(poll), .toolCall(sleep), .message(thought), .toolCall(other), .message(reply),
        ]
        for grouping in [true, false] {
            let single = TranscriptRow.rowsWithSources(
                from: [.toolCall(command), .toolCall(poll), .message(reply)], grouping: grouping)
            #expect(single.count == 2)
            #expect(single.first?.sourceIndices == [0, 1])
            #expect(single.last?.itemIndices == [2])
            let rows = TranscriptRow.rowsWithSources(from: items, grouping: grouping)
            #expect(Set(rows.flatMap(\.sourceIndices)) == Set(items.indices))
            let commandRow = try #require(rows.first { $0.sourceIndices.contains(0) })
            #expect(commandRow.sourceIndices.contains(1))
            let replyRow = try #require(rows.first { $0.sourceIndices.contains(5) })
            #expect(replyRow.row.id == items[5].id)
            #expect(replyRow.itemIndices == [5])
            let thoughtRow = try #require(rows.first { $0.sourceIndices.contains(3) })
            let visible: [TranscriptItem]
            switch thoughtRow.row {
            case .item(let item): visible = [item]
            case .toolGroup(let group): visible = group.items
            }
            #expect(visible.count == thoughtRow.itemIndices.count)
            for (item, sourceIndex) in zip(visible, thoughtRow.itemIndices) {
                #expect(item.id == items[sourceIndex].id)
                if item.id == items[3].id { #expect(sourceIndex == 3) }
            }
            if grouping {
                #expect(commandRow.itemIndices == [0, 3, 4])
                #expect(commandRow.sourceIndices == [0, 1, 2, 3, 4])
            } else {
                #expect(commandRow.itemIndices == [0])
                #expect(commandRow.sourceIndices == [0, 1])
            }
        }
    }

    @Test func pollingPreservesOutputBehindATerminalReference() throws {
        var command = CodexExecWire.call("run", #"await tools.exec_command({cmd:"swift test"})"#)
        command.content = [.terminal(id: "terminal-run")]
        command.rawOutput = .object(["session_id": .number(11732)])
        command.terminalOutput = "initial diagnostics\n"
        var poll = CodexExecWire.call("poll", #"await tools.write_stdin({session_id:11732,chars:""})"#)
        poll.content = [.content(.text("Process exited with code 1\nFAILED: testExample"))]
        let rows = TranscriptRow.rows(from: [command, poll].map(TranscriptItem.toolCall))
        let row = try #require(rows.first)
        guard case .item(.toolCall(let result)) = row else {
            Issue.record("Expected the original command")
            return
        }
        #expect(result.content.contains(.terminal(id: "terminal-run")))
        #expect(result.content.contains(.content(.text("initial diagnostics\n"))))
        #expect(result.content.contains(.content(.text("Process exited with code 1\nFAILED: testExample"))))
    }

    @Test func pollingResultsRemainAccessible() {
        let command = CodexExecWire.call("run", #"await tools.exec_command({cmd:"swift test"})"#)
        let empty = CodexExecWire.call("poll", #"await tools.write_stdin({session_id:11732,chars:""})"#)
        var result = empty
        result.content = [.content(.text("Process exited with code 1\nFAILED: testExample"))]
        var failed = empty
        failed.status = .failed
        var raw = empty
        raw.rawOutput = .object(["exit_code": .number(1)])
        var terminal = empty
        terminal.terminalOutput = "FAILED: testExample"
        for poll in [result, failed, raw, terminal] {
            for grouping in [true, false] {
                let rows = TranscriptRow.rows(from: [command, poll].map(TranscriptItem.toolCall), grouping: grouping)
                #expect(rows.contains { $0.id == "tool-poll" && !$0.isPolling })
            }
            let other = CodexExecWire.call("other", #"await tools.exec_command({cmd:"swift build"})"#)
            let rows = TranscriptRow.rows(from: [command, poll, other].map(TranscriptItem.toolCall))
            guard case .toolGroup(let group)? = rows.first else {
                Issue.record("Expected one group")
                continue
            }
            #expect(group.calls.contains { $0.id == poll.id })
        }
    }

    @Test func pollingFoldsIntoTheStepItWaitsOn() {
        let poll = CodexExecWire.call(
            "poll", #"text(await tools.write_stdin({session_id:11732,chars:"",yield_time_ms:30000}))"#)
        #expect(poll.isPolling)
        let typed = CodexExecWire.call("typed", #"text(await tools.write_stdin({session_id:11732,chars:"y\n"}))"#)
        #expect(!typed.isPolling)
        let sleep = CodexExecWire.sleep("sleep")
        #expect(sleep.isPolling)
        #expect(sleep.sentence == "Waited 30s")

        let command = CodexExecWire.call("run", #"text(await tools.exec_command({cmd:"swift test"}))"#)
        let alone = TranscriptRow.rows(from: [command, poll, sleep].map(TranscriptItem.toolCall))
        // One step and its waiting are no group; a poll with output remains accessible.
        #expect(alone.count == 3)
        #expect(alone.filter(\.isPolling).count == 1)
        let edit = CodexExecWire.call(
            "edit", #"await tools.apply_patch("*** Begin Patch\n*** Add File: notes.txt\n+done\n*** End Patch")"#)
        let rows = TranscriptRow.rows(from: [command, poll, sleep, edit].map(TranscriptItem.toolCall))
        guard case .toolGroup(let group)? = rows.first, rows.count == 1 else {
            Issue.record("Expected one group")
            return
        }
        #expect(group.calls.map(\.id) == ["run", "sleep", "edit"])
        #expect(group.summary == "Edited 1 file and ran 1 command")
    }

    // MARK: - Groups

    @Test func theCapturedTurnIsOneGroupOnceItsApprovalIsAnswered() throws {
        let done = try fold(Wire.promptTurn)
        let rows = TranscriptRow.rows(from: done.items)
        #expect(rows.count == 3)
        guard case .toolGroup(let group) = rows[1] else {
            Issue.record("Expected the calls as one group")
            return
        }
        #expect(group.calls.map(\.id) == [Wire.readToolCallID, Wire.writeToolCallID, Wire.bashToolCallID])
        #expect(group.summary == "Read 1 file, listed 1 folder and edited 1 file")
        #expect(group.outcome == nil)
    }

    @Test func aRequestWaitingForTheUserIsNeverGrouped() throws {
        let asking = try fold(
            Array(Wire.promptTurn.prefix(while: { $0 != Wire.permissionRequest })) + [Wire.permissionRequest],
            answered: false)
        let rows = TranscriptRow.rows(from: asking.items)
        #expect(!rows.contains { if case .toolGroup = $0 { true } else { false } })
        #expect(rows.count == 4)
    }

    @Test func groupingCanBeTurnedOff() throws {
        let done = try fold(Wire.promptTurn)
        #expect(TranscriptRow.rows(from: done.items, grouping: false).count == done.items.count)
    }

    @Test func reasoningBetweenCallsJoinsTheirGroupAndProseEndsIt() {
        var state = SessionState()
        state.appendUserMessage("Look around")
        state.apply(.toolCall(ToolCallUpdate(toolCallId: "1", title: "make", kind: .execute, status: .completed)))
        state.apply(.agentThoughtChunk(ContentChunk(content: .text("Now the tests."))))
        state.apply(.toolCall(ToolCallUpdate(toolCallId: "2", title: "make test", kind: .execute, status: .completed)))
        state.apply(.agentMessageChunk(ContentChunk(content: .text("Both pass."))))
        state.apply(.toolCall(ToolCallUpdate(toolCallId: "3", title: "make lint", kind: .execute, status: .inProgress)))
        let rows = TranscriptRow.rows(from: state.items)
        #expect(rows.count == 4)
        guard case .toolGroup(let group) = rows[1] else {
            Issue.record("Expected the first two calls and the thought as one group")
            return
        }
        #expect(group.items.count == 3)
        #expect(group.summary == "Ran 2 commands")
        #expect(rows[3].id == "tool-3")
    }

    @Test func aGroupSaysHowItEndedOnlyWhenItsLastCallDidnt() {
        func group(_ statuses: [ToolCallStatus]) -> ToolWorkGroup {
            ToolWorkGroup(
                items: statuses.enumerated().map { index, status in
                    .toolCall(ToolCallState(id: "\(index)", title: "make", kind: .execute, status: status))
                })
        }
        #expect(group([.failed, .completed]).outcome == nil)
        #expect(group([.completed, .failed]).outcome == .failed)
        #expect(group([.completed, .cancelled]).outcome == .cancelled)
        #expect(group([.completed, .inProgress]).isRunning)
        #expect(group([.completed, .inProgress]).currentCall?.id == "1")
    }

    @Test func summariesNameTheThreeKindsThatMatterMost() {
        var calls = (0..<3).map {
            ToolCallState(id: "read\($0)", title: "Read /a/\($0).swift", kind: .read, status: .completed)
        }
        calls += [
            ToolCallState(id: "s", title: "Search for 'x' in .", kind: .search, status: .completed),
            ToolCallState(id: "f", title: "Fetch", kind: .fetch, status: .completed),
            ToolCallState(id: "c", title: "make", kind: .execute, status: .completed),
        ]
        var edit = ToolCallState(id: "e", title: "Edit /a/0.swift", kind: .edit, status: .completed)
        edit.content = [.diff(FileDiff(path: "/a/0.swift", oldText: "a", newText: "b"))]
        calls.append(edit)
        #expect(
            ToolWorkSummary(calls: calls).sentence
                == "Read 3 files, edited 1 file, ran 1 command and made 2 other calls")
    }

    @Test func filesReadTwiceCountOnceAndRefusedEditsNotAtAll() throws {
        let read = try #require(try fold(Wire.promptTurn).call(Wire.readToolCallID))
        var refused = ToolCallState(id: "w", title: "Write /a.txt", kind: .edit, status: .failed)
        refused.content = [.diff(FileDiff(path: "/a.txt", oldText: nil, newText: "x"))]
        #expect(ToolWorkSummary(calls: [read, read, refused]).sentence == "Read 1 file")
        #expect(ToolWorkSummary(calls: [refused]).sentence == nil)
    }

    @Test func aGroupSharesAGlyphOnlyWhenItsCallsDo() throws {
        let done = try fold(Wire.promptTurn)
        let calls = done.items.compactMap(\.toolCall)
        #expect(ToolWorkSummary.sharedCategory(of: calls) == nil)
        #expect(ToolWorkSummary.sharedCategory(of: calls.prefix(1)) == .read)
    }

    // MARK: - Output

    @Test func longOutputKeepsItsUsefulEnd() {
        let output = (1...1000).map { "line \($0)" }.joined(separator: "\n")
        let start = ToolOutputExcerpt(output, keeping: .start)
        #expect(start.text.hasPrefix("line 1\n"))
        #expect(start.shownLines == ToolOutputExcerpt.maxLines)
        #expect(start.note == "Showing the first 400 of 1,000 lines")
        let end = ToolOutputExcerpt(output, keeping: .end)
        #expect(end.text.hasSuffix("line 1000"))
        #expect(end.note == "Showing the last 400 of 1,000 lines")
        let short = ToolOutputExcerpt("ok\n", keeping: .end)
        #expect(short.text == "ok\n")
        #expect(short.note == nil)
    }

    @Test func oneEnormousLineIsCutNotDropped() {
        let excerpt = ToolOutputExcerpt(String(repeating: "a", count: 100_000), keeping: .end)
        #expect(excerpt.text.count == ToolOutputExcerpt.maxCharacters)
        #expect(excerpt.isTruncated)
        #expect(excerpt.note == "Showing the last part of a long line")
    }

    // MARK: - Narration

    @Test func theWellSaysWhatTheTranscriptSays() throws {
        let running = try fold([Wire.readToolCall, Wire.readInputUpdate])
        let activity = TaskActivityNarration(items: running.items, plan: [])
        #expect(activity.verb == "Reading")
        #expect(activity.object == "notes.txt")
        #expect(activity.objectIsCode)
        let mcp = try fold([CodexMCPWire.toolCall])
        #expect(TaskActivityNarration(items: mcp.items, plan: []).verb == "Using")
    }
}

private extension TranscriptItem {
    var toolCall: ToolCallState? {
        if case .toolCall(let call) = self { call } else { nil }
    }
}

private extension SessionState {
    func call(_ id: String) -> ToolCallState? {
        items.lazy.compactMap { item -> ToolCallState? in
            guard case .toolCall(let call) = item, call.id == id else { return nil }
            return call
        }.first
    }
}
