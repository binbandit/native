import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@testable import NativeHost

@Suite("Stop recovers stuck agents", .serialized, .timeLimit(.minutes(1)))
struct HostStuckStopTests {
    @Test("Stop ends a stuck turn despite another working session and recovers the sibling")
    func sharedProcess() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let stopped = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path, attach: true))
        let sibling = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path, attach: true))
        _ = try await recorder.client.prompt(PromptParams(sessionID: stopped.id, text: "stubborn 100"))
        _ = try await recorder.client.prompt(PromptParams(sessionID: sibling.id, text: "stubborn 100"))
        try await recorder.wait("both turns to start") {
            let first = await $0.agentText(stopped.id)
            let second = await $0.agentText(sibling.id)
            return first.contains("tick 1") && second.contains("tick 1")
        }
        let queue = PromptParams(sessionID: stopped.id, text: "queued")
        _ = try await recorder.client.prompt(queue)
        try await recorder.client.cancel(stopped.id)
        try await recorder.wait("Stop to finish within its grace period", timeout: .seconds(5)) {
            await $0.turnsEnded(stopped.id) == ["cancelled"]
        }
        #expect(
            await recorder.notices(stopped.id).contains("Stopped. Fake Agent didn't respond, so Native stopped it."))
        #expect(await recorder.summaries[stopped.id]?.isStopping == false)
        let cancels = try String(contentsOf: harness.agentStore.appending(path: "cancels.log"), encoding: .utf8)
        #expect(cancels.split(separator: "\n").map(String.init) == [stopped.agentSessionID?.rawValue])
        #expect(await recorder.summaries[stopped.id]?.queue.map(\.id) == [queue.requestID])
        #expect(await recorder.summaries[stopped.id]?.isQueuePaused == true)
        try await recorder.wait("the sibling to recover") { await $0.agentText(sibling.id).contains("resumed") }
        #expect(await recorder.recoveries(stopped.id).isEmpty)
        _ = try await recorder.client.prompt(PromptParams(sessionID: stopped.id, text: "next"))
        try await recorder.wait("the next messages") { await $0.agentText(stopped.id).contains("echo: next") }
        #expect(await recorder.agentText(stopped.id).contains("tick 1"))
        #expect(
            await recorder.notices(stopped.id).contains("Stopped. Fake Agent didn't respond, so Native stopped it."))
        #expect(harness.received.filter { $0 == "prompt\tstubborn 100" }.count == 2)
        await recorder.stop()
    }

    @Test(
        "Stop ends a sleeping tool, retains history, and accepts the next message",
        arguments: ["ignore", "die", "reply"])
    func sleepingTool(behavior: String) async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        harness.agentEnvironment["FAKE_AGENT_NO_RESUME"] = "1"
        if behavior == "die" { harness.agentEnvironment["FAKE_AGENT_EXIT_ON_CANCEL"] = "1" }
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path, attach: true))
        let prompt = behavior == "reply" ? "cancel-leaves-command" : "stuck-tool"
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: prompt))
        let ready = harness.agentStore.appending(path: "command-ready")
        try await recorder.wait("the sleeping command") { _ in FileManager.default.fileExists(atPath: ready.path) }
        let pid = try #require(
            Int32(String(contentsOf: harness.agentStore.appending(path: "command.pid"), encoding: .utf8)))
        defer { if kill(pid, 0) == 0 { kill(pid, SIGKILL) } }
        let before = try #require(try await recorder.client.agents().first?.processID)
        let started = ContinuousClock.now
        try await recorder.client.cancel(session.id)
        try await recorder.wait("the stop", timeout: .seconds(5)) { await $0.turnsEnded(session.id) == ["cancelled"] }
        #expect(ContinuousClock.now - started < .seconds(5))
        #expect(!AgentStopProcesses(root: pid).hasRemainingProcesses)
        #expect(await recorder.mirror(session.id).state.turns.last?.stopReason == .cancelled)
        if behavior != "reply" {
            #expect(await recorder.notices(session.id) == ["Stopped. Fake Agent didn't respond, so Native stopped it."])
            #expect(
                await recorder.mirror(session.id).state.items.contains {
                    if case .toolCall(let call) = $0 {
                        call.title == "sleep 600" && call.status == .cancelled
                    } else {
                        false
                    }
                })
        } else {
            #expect(await recorder.notices(session.id) == ["Stopped."])
        }
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "hello again"))
        try await recorder.wait("the next turn") { await $0.agentText(session.id).contains("echo: hello again") }
        #expect(try await recorder.client.agents().first?.processID != before)
        #expect(await recorder.mirror(session.id).userMessages == [prompt, "hello again"])
        #expect(await recorder.notices(session.id).count == 1)
        await recorder.stop()
    }

    @Test("A second Stop immediately skips the grace period")
    func secondPress() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path, attach: true))
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "stubborn 100"))
        try await recorder.wait("the turn") { await $0.agentText(session.id).contains("tick 1") }
        try await recorder.client.cancel(session.id)
        #expect(await recorder.summaries[session.id]?.isStopping == true)
        try await recorder.client.cancel(session.id)
        try await recorder.wait("the immediate stop", timeout: .seconds(1)) {
            await $0.turnsEnded(session.id) == ["cancelled"]
        }
        await recorder.stop()
    }
}
