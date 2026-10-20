import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

/// What a client does with a session through a real host and the fake agent: opening, prompting
/// with attachments and instructions, answering questions, hidden commands, stopping, the queue,
/// retries, and settings that have to survive a reload.
@Suite("Host sessions, end to end", .serialized, .timeLimit(.minutes(1)))
struct HostSessionTests {
    private func started(_ harness: HostHarness) async throws -> (Recorder, HostSessionID) {
        try harness.start()
        let recorder = try await harness.connect()
        let summary = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path(percentEncoded: false), attach: true))
        return (recorder, summary.id)
    }

    @Test("A session started with a client's id and attach streams from its first event; a retry returns it")
    func newSessionWithClientID() async throws {
        let harness = try HostHarness()
        try harness.start()
        let recorder = try await harness.connect()
        let id = HostSessionID()
        let params = NewSessionParams(
            sessionID: id, agentID: "fake", cwd: "/tmp", meta: .object(["plugin": .bool(true)]), attach: true)
        let summary = try await recorder.client.newSession(params)
        #expect(summary.id == id)
        #expect(await recorder.payloads(id).first == .reset(loading: false))
        #expect(await recorder.mirror(id).state.configOptions.first?.id == "mode")
        let again = try await recorder.client.newSession(params)
        #expect(again.agentSessionID == summary.agentSessionID)
        #expect(try await recorder.client.sessions().count == 1)
        await recorder.stop()
    }

    @Test("Opening with attach answers at once and the agent's replay streams in")
    func openWithAttach() async throws {
        let harness = try HostHarness()
        let (recorder, first) = try await started(harness)
        _ = try await recorder.client.prompt(PromptParams(sessionID: first, text: "hello"))
        try await recorder.wait("the turn") { await $0.turnsEnded(first) == ["end_turn"] }
        let agentSession = try #require(await recorder.summaries[first]?.agentSessionID)
        try await recorder.client.closeSession(first)

        let id = HostSessionID()
        let summary = try await recorder.client.openSession(
            OpenSessionParams(
                sessionID: id, agentID: "fake", agentSessionID: agentSession, cwd: "/tmp", title: "Earlier",
                attach: true))
        #expect(summary.id == id)
        #expect(summary.phase == .loading)
        try await recorder.wait("the replay") { await $0.agentText(id) == "echo: hello" }
        try await recorder.wait("the load to finish") { await $0.summaries[id]?.phase == .idle }
        #expect(await recorder.mirror(id).userMessages == ["hello"])
        #expect(await !recorder.mirror(id).isLoading)
        await recorder.stop()
    }

    @Test("A session that can't load says why, in its summary and its transcript")
    func failedOpen() async throws {
        let harness = try HostHarness()
        try harness.start()
        let recorder = try await harness.connect()
        let summary = try await recorder.client.openSession(
            OpenSessionParams(agentID: "fake", agentSessionID: SessionID("missing"), cwd: "/tmp", attach: true))
        try await recorder.wait("the failure") { await $0.summaries[summary.id]?.phase == .disconnected }
        #expect(await recorder.summaries[summary.id]?.problem != nil)
        #expect(await recorder.notices(summary.id).contains { $0.hasPrefix("Couldn't load this session") })
        #expect(await !recorder.mirror(summary.id).isLoading)
        await recorder.stop()
    }

    @Test("A session the agent never saved carries on in a fresh agent session, under the same id")
    func unsavedSessionIsReplaced() async throws {
        let harness = try HostHarness()
        let (first, session) = try await started(harness)
        let original = try #require(await first.summaries[session]?.agentSessionID)
        await first.stop()
        harness.kill()
        // As an agent that only saves a session once a turn ends would have it after a crash.
        try FileManager.default.removeItem(at: harness.agentStore.appending(path: "\(original.rawValue).json"))

        try harness.start()
        let second = try await harness.connect()
        try await second.client.attach(session)
        _ = try await second.client.prompt(PromptParams(sessionID: session, text: "hello"))
        try await second.wait("the turn") { await $0.turnsEnded(session) == ["end_turn"] }
        #expect(await second.agentText(session) == "echo: hello")
        let replaced = try #require(try await second.client.sessions().first { $0.id == session })
        #expect(replaced.agentSessionID != original)
        #expect(replaced.agentSessionID != nil)
        await second.stop()
    }

    @Test("Content, attachments and instructions reach the agent; the same instructions go only once")
    func contentAndPreamble() async throws {
        let harness = try HostHarness()
        let (recorder, session) = try await started(harness)
        let preamble = PromptPreambleSpec(
            marker: PreambleMarker(id: "plan", label: "Plan mode", symbol: "list.bullet"), instructions: "Plan first.")
        _ = try await recorder.client.prompt(
            PromptParams(
                sessionID: session, text: "look",
                content: [.text("look"), .resourceLink(uri: "file:///tmp/a.txt", name: "a.txt")],
                attachments: [EchoAttachment(name: "a.txt", url: URL(filePath: "/tmp/a.txt"))], preamble: preamble))
        try await recorder.wait("the first turn") { await $0.turnsEnded(session).count == 1 }
        _ = try await recorder.client.prompt(PromptParams(sessionID: session, text: "again", preamble: preamble))
        try await recorder.wait("the second turn") { await $0.turnsEnded(session).count == 2 }
        let received = harness.received
        #expect(received.count == 2)
        #expect(received.first?.hasPrefix("prompt\t<native_instructions id=\"plan\"") == true)
        #expect(received.first?.hasSuffix("look[link a.txt]") == true)
        #expect(received.last == "prompt\tagain")
        let message = await recorder.mirror(session).state.items.compactMap { item in
            if case .message(let message) = item, message.role == .user { message } else { nil }
        }.first
        #expect(message?.text == "look")
        #expect(message?.attachments.map(\.name) == ["a.txt"])
        #expect(message?.preamble?.id == "plan")
        await recorder.stop()
    }

    @Test("A question reaches the client, and the answer reaches the agent")
    func questions() async throws {
        let harness = try HostHarness()
        let (recorder, session) = try await started(harness)
        _ = try await recorder.client.prompt(PromptParams(sessionID: session, text: "question please"))
        try await recorder.wait("the question") { await !$0.mirror(session).questions.isEmpty }
        let question = try #require(await recorder.mirror(session).questions.first)
        #expect(question.request.message == "Which color?")
        #expect(await recorder.summaries[session]?.needsApproval == true)
        try await recorder.client.respondQuestion(
            RespondQuestionParams(
                sessionID: session, questionID: question.id,
                response: .object(["action": .string("accept"), "content": .object(["color": .string("blue")])])))
        try await recorder.wait("the turn") { await $0.turnsEnded(session) == ["end_turn"] }
        #expect(await recorder.agentText(session).contains("question: accept blue"))
        #expect(await recorder.mirror(session).questions.isEmpty)
        #expect(try await recorder.client.activity().contains { $0.kind == .questionAsked })
        await recorder.stop()
    }

    @Test("An approval waiting when the client quits is there for the next one, which can answer it")
    func approvalSurvivesClientRestart() async throws {
        let harness = try HostHarness()
        let (first, session) = try await started(harness)
        _ = try await first.client.prompt(PromptParams(sessionID: session, text: "permission please"))
        try await first.wait("the approval") { await !$0.mirror(session).state.pendingPermissions.isEmpty }
        await first.stop()

        let second = try await harness.connect()
        let summary = try await second.client.attach(session)
        #expect(summary.needsApproval)
        let toolCall = try #require(await second.mirror(session).state.pendingPermissions.first?.toolCallID)
        try await second.client.respondPermission(
            RespondPermissionParams(sessionID: session, toolCallID: toolCall, optionID: "allow"))
        try await second.wait("the turn") { await $0.turnsEnded(session) == ["end_turn"] }
        #expect(await second.agentText(session).contains("permission: allow"))
        await second.stop()
    }

    @Test("A hidden command's reply comes back to its caller and stays out of the transcript")
    func hiddenCommand() async throws {
        let harness = try HostHarness()
        let (recorder, session) = try await started(harness)
        let output = try await recorder.client.runHidden(RunHiddenParams(sessionID: session, text: "/context"))
        #expect(output == "context: 42% used")
        // The agent sends its reply again after the turn; that copy is dropped too.
        try await Task.sleep(for: .milliseconds(500))
        #expect(await recorder.agentText(session).isEmpty)
        #expect(await recorder.mirror(session).userMessages.isEmpty)
        _ = try await recorder.client.prompt(PromptParams(sessionID: session, text: "hello"))
        try await recorder.wait("the turn") { await $0.turnsEnded(session) == ["end_turn"] }
        #expect(await recorder.agentText(session) == "echo: hello")
        await recorder.stop()
    }

    @Test("Stopping a turn whose agent won't confirm: asking again ends it on the host's side")
    func stopTwice() async throws {
        let harness = try HostHarness()
        let (recorder, session) = try await started(harness)
        _ = try await recorder.client.prompt(PromptParams(sessionID: session, text: "stubborn 8"))
        try await recorder.wait("the turn to get going") { await $0.agentText(session).contains("tick 1") }
        try await recorder.client.cancel(session)
        try await recorder.wait("the stop to show") { await $0.summaries[session]?.isStopping == true }
        try await Task.sleep(for: .milliseconds(1_100))
        try await recorder.client.cancel(session)
        try await recorder.wait("the turn to end") { await $0.turnsEnded(session) == ["cancelled"] }
        #expect(await recorder.notices(session).contains { $0.hasPrefix("Fake Agent didn't confirm it stopped") })
        #expect(await recorder.summaries[session]?.isStopping == false)
        await recorder.stop()
    }

    @Test("Send Now on an agent that can't steer stops the turn and sends the message next")
    func sendNowInterrupts() async throws {
        let harness = try HostHarness()
        harness.agentEnvironment = ["FAKE_AGENT_NO_STEERING": "1"]
        let (recorder, session) = try await started(harness)
        _ = try await recorder.client.prompt(PromptParams(sessionID: session, text: "slow 20"))
        let next = PromptParams(sessionID: session, text: "next")
        #expect(try await recorder.client.prompt(next) == .queued)
        try await recorder.wait("the turn to get going") { await $0.agentText(session).contains("tick 1") }
        try await recorder.client.sendQueuedNow(QueueItemParams(sessionID: session, itemID: next.requestID))
        try await recorder.wait("both turns") { await $0.turnsEnded(session) == ["cancelled", "end_turn"] }
        #expect(harness.received == ["prompt\tslow 20", "prompt\tnext"])
        await recorder.stop()
    }

    @Test("Queued messages can be reordered, removed and put back")
    func queueEdits() async throws {
        let harness = try HostHarness()
        let (recorder, session) = try await started(harness)
        _ = try await recorder.client.prompt(PromptParams(sessionID: session, text: "slow 5"))
        let items = ["a", "b", "c"].map { PromptParams(sessionID: session, text: $0) }
        for item in items {
            _ = try await recorder.client.prompt(item)
        }
        try await recorder.client.moveQueued(
            MoveQueuedParams(sessionID: session, itemID: items[2].requestID, before: items[0].requestID))
        try await recorder.client.removeQueued(QueueItemParams(sessionID: session, itemID: items[0].requestID))
        #expect(try await recorder.client.sessions().first?.queue.map(\.text) == ["c", "b"])
        try await recorder.client.restoreQueued(
            RestoreQueuedParams(sessionID: session, itemID: items[0].requestID, index: 1))
        #expect(try await recorder.client.sessions().first?.queue.map(\.text) == ["c", "a", "b"])
        try await recorder.wait("every turn") { await $0.turnsEnded(session).count == 4 }
        #expect(harness.received == ["prompt\tslow 5", "prompt\tc", "prompt\ta", "prompt\tb"])
        await recorder.stop()
    }

    @Test("A prompt that fails for a passing reason goes out again by itself, shown once")
    func passingFailureRetries() async throws {
        let harness = try HostHarness()
        let (recorder, session) = try await started(harness)
        _ = try await recorder.client.prompt(PromptParams(sessionID: session, text: "flaky-once hi"))
        try await recorder.wait("the failure") { await !$0.failures(session).isEmpty }
        #expect(await recorder.summaries[session]?.retryAt != nil)
        #expect(await recorder.failures(session).first?.contains("will try again in 5 seconds") == true)
        try await recorder.wait("the retry", timeout: .seconds(15)) {
            await $0.turnsEnded(session).contains("end_turn")
        }
        #expect(harness.received == ["prompt\tflaky-once hi", "prompt\tflaky-once hi"])
        #expect(await recorder.mirror(session).userMessages == ["flaky-once hi"])
        #expect(await recorder.summaries[session]?.retryAt == nil)
        await recorder.stop()
    }

    @Test("Settings chosen for a session are set back after it's reloaded")
    func configSetBack() async throws {
        let harness = try HostHarness()
        let (recorder, session) = try await started(harness)
        try await recorder.client.setConfigOption(
            SetConfigOptionParams(sessionID: session, configID: "mode", value: "plan"))
        _ = try await recorder.client.restartAgent("fake")
        _ = try await recorder.client.prompt(PromptParams(sessionID: session, text: "mode?"))
        try await recorder.wait("the turn") { await $0.turnsEnded(session) == ["end_turn"] }
        #expect(await recorder.agentText(session).contains("mode: plan"))
        #expect(harness.received.filter { $0 == "config\tmode=plan" }.count == 2)
        await recorder.stop()
    }

    @Test("The model comes back before the effort, so setting it back doesn't undo the effort")
    func configSetBackModelFirst() async throws {
        let harness = try HostHarness()
        let (recorder, session) = try await started(harness)
        // The agent lists the effort before the model, and "effort" sorts first too; choosing a
        // model puts the effort back to its default, as codex-acp does.
        try await recorder.client.setConfigOption(
            SetConfigOptionParams(sessionID: session, configID: "model", value: "beta"))
        try await recorder.client.setConfigOption(
            SetConfigOptionParams(sessionID: session, configID: "effort", value: "high"))
        _ = try await recorder.client.restartAgent("fake")
        _ = try await recorder.client.prompt(PromptParams(sessionID: session, text: "config?"))
        try await recorder.wait("the turn") { await $0.turnsEnded(session) == ["end_turn"] }
        #expect(await recorder.agentText(session).contains("model=beta effort=high"))
        let setBack = harness.received.filter { $0.hasPrefix("config\t") }.dropFirst(2)
        #expect(Array(setBack) == ["config\tmodel=beta", "config\teffort=high"])
        await recorder.stop()
    }

    @Test("MCP servers replaced for a session go to the agent at its next load")
    func replacedMCPServers() async throws {
        let harness = try HostHarness()
        try harness.start()
        let recorder = try await harness.connect()
        let server = { (name: String) in
            JSONValue.object([
                "name": .string(name), "command": .string("/usr/bin/true"), "args": .array([]), "env": .array([]),
            ])
        }
        let session = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: "/tmp", mcpServers: [server("tracker-old")], attach: true))
        try await recorder.client.setMCPServers(
            SetMCPServersParams(sessionID: session.id, mcpServers: [server("tracker"), server("docs")]))
        let renamed = JSONValue.object([
            "name": .string("docs"), "command": .string("/usr/bin/false"), "args": .array([]), "env": .array([]),
        ])
        // By name: "docs" is replaced, "tracker" kept, and "extra" (which the session lacked) added. The
        // host adds Native's own tools last (HostTasksTests).
        try await recorder.client.setMCPServers(
            SetMCPServersParams(sessionID: session.id, mcpServers: [renamed, server("extra")], replacingNamed: true))
        _ = try await recorder.client.restartAgent("fake")
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "hello"))
        try await recorder.wait("the turn") { await $0.turnsEnded(session.id) == ["end_turn"] }
        let loads = try String(contentsOf: harness.agentStore.appending(path: "loads.log"), encoding: .utf8)
        #if canImport(Network) && canImport(CryptoKit)
        let hostTools = ",native "
        #else
        let hostTools = ""  // No host tools off Apple's platforms yet (`HostTasks.canServe`).
        #endif
        #expect(loads == "tracker /usr/bin/true,docs /usr/bin/false,extra /usr/bin/true\(hostTools)\n")
        await recorder.stop()
    }

    @Test("The agent's saved sessions are listed, closed and deleted through the host")
    func agentSessions() async throws {
        let harness = try HostHarness()
        let (recorder, session) = try await started(harness)
        let other = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp"))
        let listed = try await recorder.client.listAgentSessions(ListAgentSessionsParams(agentID: "fake", cwd: "/"))
        let ids = Set(listed.sessions.map(\.sessionId))
        let first = try #require(await recorder.summaries[session]?.agentSessionID)
        let second = try #require(other.agentSessionID)
        #expect(ids == [first, second])
        try await recorder.client.closeSession(other.id, closeInAgent: true)
        try await recorder.client.deleteAgentSession(DeleteAgentSessionParams(agentID: "fake", agentSessionID: first))
        try await recorder.wait("the deleted session to close") { await $0.closed.contains(session) }
        #expect(harness.received == ["close\t\(second.rawValue)", "delete\t\(first.rawValue)"])
        let remaining = try await recorder.client.listAgentSessions(ListAgentSessionsParams(agentID: "fake"))
        #expect(remaining.sessions.map(\.sessionId) == [second])
        #expect(try await recorder.client.sessions().isEmpty)
        await recorder.stop()
    }
}
