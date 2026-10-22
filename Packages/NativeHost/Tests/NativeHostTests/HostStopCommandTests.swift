import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@Suite("Stop owns command termination", .serialized, .timeLimit(.minutes(1)))
struct HostStopCommandTests {
    @Test("Closing a stopped task then exiting still waits for its orphaned command", arguments: [false, true])
    func closeThenShutdown(restart: Bool) async throws {
        let harness = try HostHarness()
        harness.agentEnvironment["FAKE_AGENT_EXIT_ON_CANCEL"] = "1"
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path, attach: true))
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "cancel-leaves-command"))
        let ready = harness.agentStore.appending(path: "command-ready")
        try await recorder.wait("the shell to start") { _ in FileManager.default.fileExists(atPath: ready.path) }
        let pid = try #require(
            Int32(String(contentsOf: harness.agentStore.appending(path: "command.pid"), encoding: .utf8)))
        defer { if kill(pid, 0) == 0 { kill(-pid, SIGKILL) } }
        try await recorder.client.cancel(session.id)
        try await recorder.wait("the adapter to exit") {
            await $0.agents["fake"]?.state == .stopped
        }
        try await recorder.client.closeSession(session.id)
        try await recorder.client.shutdownHost(stopAgents: !restart, immediately: restart)
        #expect(try await harness.waitForExit() == (restart ? 75 : 0))
        #expect(kill(pid, 0) != 0)
        try await Task.sleep(for: .seconds(6))
        #expect(!FileManager.default.fileExists(atPath: harness.agentStore.appending(path: "stop-marker.txt").path))
        await recorder.stop()
    }

    @Test("Closing a task or quitting during Stop cannot discard its command cleanup", arguments: [false, true])
    func closeDuringStop(shutdown: Bool) async throws {
        let harness = try HostHarness()
        harness.agentEnvironment["FAKE_AGENT_NO_STEERING"] = "1"
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path, attach: true))
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "cancel-leaves-command"))
        let ready = harness.agentStore.appending(path: "command-ready")
        try await recorder.wait("the shell to start") { _ in FileManager.default.fileExists(atPath: ready.path) }
        let pid = try #require(
            Int32(String(contentsOf: harness.agentStore.appending(path: "command.pid"), encoding: .utf8)))
        defer { if kill(pid, 0) == 0 { kill(-pid, SIGKILL) } }
        try await recorder.client.cancel(session.id)
        if shutdown {
            let next = PromptParams(sessionID: session.id, text: "next")
            _ = try await recorder.client.prompt(next)
            try await recorder.client.sendQueuedNow(QueueItemParams(sessionID: session.id, itemID: next.requestID))
            try await recorder.client.shutdownHost(stopAgents: true)
            #expect(try await harness.waitForExit() == 0)
            #expect(!harness.received.contains("prompt\tnext"))
        } else {
            try await recorder.client.closeSession(session.id)
        }
        try await Task.sleep(for: .seconds(6))
        #expect(!FileManager.default.fileExists(atPath: harness.agentStore.appending(path: "stop-marker.txt").path))
        #expect(kill(pid, 0) != 0)
        await recorder.stop()
    }

    @Test("A shared agent stays Stopping with an explanation until its other task can stop")
    func sharedAgent() async throws {
        let harness = try HostHarness()
        try harness.start()
        let recorder = try await harness.connect()
        let first = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path, attach: true))
        let second = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path, attach: true))
        _ = try await recorder.client.prompt(PromptParams(sessionID: second.id, text: "stubborn 100"))
        try await recorder.wait("the sibling turn") { await $0.agentText(second.id).contains("tick 1") }
        _ = try await recorder.client.prompt(PromptParams(sessionID: first.id, text: "slow 100"))
        try await recorder.wait("the target turn") { await $0.agentText(first.id).contains("tick 1") }
        try await recorder.client.cancel(first.id)
        try await Task.sleep(for: .seconds(3))
        #expect(await recorder.turnsEnded(first.id).isEmpty)
        #expect(await recorder.summaries[first.id]?.isStopping == true)
        #expect(await recorder.notices(first.id).contains { $0.contains("may still be running") })
        #expect(await recorder.turnsEnded(second.id).isEmpty)
        try await recorder.client.cancel(second.id)
        try await recorder.wait("both stops") {
            let firstEnded = await $0.turnsEnded(first.id)
            let secondEnded = await $0.turnsEnded(second.id)
            return firstEnded == ["cancelled"] && secondEnded == ["cancelled"]
        }
        #expect(await recorder.recoveries(first.id).isEmpty)
        #expect(await recorder.recoveries(second.id).isEmpty)
        await recorder.stop()
    }

    @Test(
        "A cancel acknowledgement or agent exit cannot leave a shell writing files after Stopped",
        arguments: [false, true])
    func cancelledCommand(agentExits: Bool) async throws {
        let unrelated = Process()
        unrelated.executableURL = URL(filePath: "/bin/sleep")
        unrelated.arguments = ["30"]
        try unrelated.run()
        defer { if unrelated.isRunning { unrelated.terminate() } }
        let harness = try HostHarness()
        if agentExits { harness.agentEnvironment["FAKE_AGENT_EXIT_ON_CANCEL"] = "1" }
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path, attach: true))
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "cancel-leaves-command"))
        let ready = harness.agentStore.appending(path: "command-ready")
        try await recorder.wait("the shell to start") { _ in FileManager.default.fileExists(atPath: ready.path) }
        let pid = try #require(
            Int32(String(contentsOf: harness.agentStore.appending(path: "command.pid"), encoding: .utf8)))
        defer { if kill(pid, 0) == 0 { kill(-pid, SIGKILL) } }
        try await recorder.client.cancel(session.id)
        try await recorder.wait("Stopped") { await $0.turnsEnded(session.id) == ["cancelled"] }
        #expect(kill(pid, 0) != 0)
        #expect(unrelated.isRunning)
        try await Task.sleep(for: .seconds(6))
        #expect(!FileManager.default.fileExists(atPath: harness.agentStore.appending(path: "stop-marker.txt").path))
        #expect(await recorder.summaries[session.id]?.phase == .idle)
        #expect(await recorder.recoveries(session.id).isEmpty)
        await recorder.stop()
    }
}
