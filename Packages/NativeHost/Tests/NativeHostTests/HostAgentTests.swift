import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

/// Agents as clients see them through the host: their status, starting, stopping and restarting
/// them, signing in, and every process an agent started ending with it.
@Suite("Host agents, end to end", .serialized, .timeLimit(.minutes(1)))
struct HostAgentTests {
    @Test("Agents are listed with their status, which clients hear change as they start and stop")
    func statusAndChanges() async throws {
        let harness = try HostHarness()
        try harness.start()
        let recorder = try await harness.connect()
        #expect(try await recorder.client.agents().map(\.state) == [.stopped])
        let started = try await recorder.client.startAgent("fake")
        #expect(started.state == .ready)
        #expect(started.processID != nil)
        #expect(started.launchedSpec == harness.agentSpec)
        let initialize = try JSONDecoder().decode(
            InitializeResponse.self, from: JSONEncoder().encode(try #require(started.initialize)))
        #expect(initialize.authMethods.map(\.id) == ["token"])
        #expect(initialize.agentCapabilities.steering)
        try await recorder.wait("the change to arrive") { await $0.agents["fake"]?.state == .ready }
        let stopped = try await recorder.client.stopAgent("fake")
        #expect(stopped.stopped)
        #expect(stopped.agent.state == .stopped)
        #expect(stopped.agent.processID == nil)
        try await recorder.wait("the stop to arrive") { await $0.agents["fake"]?.state == .stopped }
        await recorder.stop()
    }

    @Test("An agent that isn't installed says so, with a host error clients can tell apart")
    func notInstalled() async throws {
        let harness = try HostHarness()
        try harness.start()
        let recorder = try await harness.connect()
        try await recorder.client.syncAgents([AgentSpec(id: "ghost", name: "Ghost", command: "no-such-agent-cli")])
        let agent = try await recorder.client.startAgent("ghost")
        #expect(agent.state == .notInstalled)
        #expect(agent.problem == "no-such-agent-cli")
        let error = await #expect(throws: RPCError.self) {
            _ = try await recorder.client.newSession(NewSessionParams(agentID: "ghost", cwd: "/tmp"))
        }
        #expect(error.flatMap { HostErrorCode($0) } == .agentNotInstalled)
        #expect(error?.isAuthRequired == false)
        await recorder.stop()
    }

    @Test("An agent isn't stopped while one of its sessions is working")
    func stopRefusedWhileWorking() async throws {
        let harness = try HostHarness()
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "slow 4"))
        #expect(try await recorder.client.stopAgent("fake").stopped == false)
        try await recorder.wait("the turn") { await $0.turnsEnded(session.id) == ["end_turn"] }
        #expect(try await recorder.client.stopAgent("fake").stopped)
        await recorder.stop()
    }

    @Test("A message sent after the agent stopped while idle still shows once its session reloads")
    func messageSurvivesReload() async throws {
        let harness = try HostHarness()
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "hello"))
        try await recorder.wait("the turn") { await $0.turnsEnded(session.id) == ["end_turn"] }
        #expect(try await recorder.client.stopAgent("fake").stopped)

        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "again"))
        try await recorder.wait("the turn after the reload") { await $0.turnsEnded(session.id).count == 2 }
        #expect(await recorder.agentText(session.id).contains("echo: again"))
        let shown = await recorder.mirror(session.id).state.items.compactMap { item in
            if case .message(let message) = item, message.role == .user { message.text } else { nil }
        }
        #expect(shown == ["hello", "again"])
        // Inside the reload, so clients take it for history, not for the turn starting again.
        let payloads = await recorder.payloads(session.id)
        let reload = payloads[(payloads.lastIndex { if case .reset = $0 { true } else { false } } ?? 0)...]
        let echoed = try #require(reload.firstIndex { if case .prompt = $0 { true } else { false } })
        let loaded = try #require(reload.firstIndex { if case .loaded = $0 { true } else { false } })
        #expect(echoed < loaded)
        await recorder.stop()
    }

    @Test("Restarting an agent mid-turn resumes the turn and says the user restarted it")
    func restartMidTurn() async throws {
        let harness = try HostHarness()
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "slow 20"))
        try await recorder.wait("the turn to get going") { await $0.agentText(session.id).contains("tick 1") }
        let restarted = try await recorder.client.restartAgent("fake")
        #expect(restarted.state == .ready)
        try await recorder.wait("the resumed turn") { await $0.turnsEnded(session.id) == ["end_turn"] }
        let note = try #require(await recorder.recoveries(session.id).first)
        #expect(note.cause == .agentRestarted)
        #expect(note.action == .resumed)
        #expect(note.sentence().hasPrefix("You restarted Fake Agent at"))
        await recorder.stop()
    }

    @Test("Signing in goes to the agent with the method chosen")
    func authenticate() async throws {
        let harness = try HostHarness()
        try harness.start()
        let recorder = try await harness.connect()
        let agent = try await recorder.client.authenticateAgent("fake", methodID: "token")
        #expect(!agent.isSigningIn)
        #expect(!agent.needsSignIn)
        #expect(harness.received == ["authenticate\ttoken"])
        await recorder.stop()
    }

    @Test("Stopping an agent ends what it started in a process group of its own")
    func stopEndsProcessGroups() async throws {
        let harness = try HostHarness()
        harness.agentEnvironment = ["FAKE_AGENT_GRANDCHILD": harness.grandchildFile.path(percentEncoded: false)]
        try harness.start()
        let recorder = try await harness.connect()
        _ = try await recorder.client.startAgent("fake")
        let grandchild = try #require(harness.grandchild)
        #expect(getpgid(grandchild) == grandchild)
        #expect(try await recorder.client.stopAgent("fake").stopped)
        try await recorder.wait("the grandchild to end") { _ in kill(grandchild, 0) != 0 }
        await recorder.stop()
    }

    @Test("An agent that crashes takes what it started with it, and comes back for the turn")
    func crashEndsProcessGroups() async throws {
        let harness = try HostHarness()
        harness.agentEnvironment = ["FAKE_AGENT_GRANDCHILD": harness.grandchildFile.path(percentEncoded: false)]
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        let grandchild = try #require(harness.grandchild)
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "crash-once now"))
        try await recorder.wait("the recovered turn") { await $0.turnsEnded(session.id) == ["end_turn"] }
        try await recorder.wait("the old grandchild to end") { _ in kill(grandchild, 0) != 0 }
        #expect(harness.grandchild != grandchild)
        await recorder.stop()
    }

    @Test("Quit and Stop Agents ends known processes, records an unverified stop, and resumes nothing")
    func quitAndStopAgents() async throws {
        let harness = try HostHarness()
        harness.agentEnvironment = ["FAKE_AGENT_GRANDCHILD": harness.grandchildFile.path(percentEncoded: false)]
        try harness.start()
        let first = try await harness.connect()
        let session = try await first.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        _ = try await first.client.prompt(PromptParams(sessionID: session.id, text: "stubborn 30"))
        try await first.wait("the turn to get going") { await $0.agentText(session.id).contains("tick 1") }
        let grandchild = try #require(harness.grandchild)
        let asked = ContinuousClock.now
        try await first.client.shutdownHost(stopAgents: true)
        #expect(try await harness.waitForExit() == 0)
        // An agent that ignores the cancel holds it up a moment, not for good.
        #expect(ContinuousClock.now - asked < .seconds(4))
        #expect(kill(grandchild, 0) != 0)
        await first.stop()

        try harness.start()
        let second = try await harness.connect()
        let summary = try #require(try await second.client.sessions().first)
        #expect(summary.phase == .idle)
        #expect(summary.lastStopReason == "error")
        let activity = try await second.client.activity()
        #expect(activity.contains { $0.kind == .stopped && $0.agentSessionID == session.agentSessionID })
        #expect(!activity.contains { $0.kind == .recovered || $0.kind == .hostStarted })
        await second.stop()
    }

    @Test("After a crash, the host's restart is journaled with how the previous run ended")
    func hostStartedSaysWhy() async throws {
        let harness = try HostHarness()
        try harness.start()
        let first = try await harness.connect()
        #expect(try await first.client.activity().isEmpty)
        await first.stop()
        harness.kill()
        try harness.start()
        let second = try await harness.connect()
        let entry = try #require(try await second.client.activity().last)
        #expect(entry.kind == .hostStarted)
        #expect(entry.previousRun == .crashed)
        await second.stop()
    }
}
