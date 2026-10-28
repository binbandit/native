import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@testable import NativeHost

@Suite("Stop owns command termination", .serialized, .timeLimit(.minutes(1)))
struct HostStopCommandTests {
    @Test("Immediate restart includes another client's Stop arriving during cleanup")
    @HostActor
    func restartWithConcurrentStop() async throws {
        let rig = try HostStopCommandRig()
        defer { rig.cleanup() }
        let first = try await rig.connect()
        let second = try await rig.connect()
        let otherAgent = AgentSpec(
            id: "other", name: "Other Agent", command: rig.harness.agentSpec.command,
            env: rig.harness.agentSpec.env)
        try await first.client.syncAgents([rig.harness.agentSpec, otherAgent])
        let initial = try await first.client.newSession(
            NewSessionParams(agentID: "fake", cwd: rig.harness.root.path, attach: true))
        let later = try await second.client.newSession(
            NewSessionParams(agentID: "other", cwd: rig.harness.root.path, attach: true))
        _ = try await first.client.prompt(PromptParams(sessionID: initial.id, text: "stubborn 100"))
        _ = try await second.client.prompt(PromptParams(sessionID: later.id, text: "stubborn 100"))
        try await first.wait("the first command") { await $0.agentText(initial.id).contains("tick 1") }
        try await second.wait("the second command") { await $0.agentText(later.id).contains("tick 1") }
        try await first.client.cancel(initial.id)
        // Keep the initial drain open until the other client has submitted Stop. A shutdown reply
        // alone cannot do this: the host may already have exited by the time the client reads it.
        let release = rig.holdCleanup()
        defer { release.finish() }
        try await first.client.shutdownHost(stopAgents: false, immediately: true)
        #expect(rig.core.isRestartingImmediately)
        #expect(rig.exits.values.isEmpty)
        try await second.client.cancel(later.id)
        // Keep a later cleanup pending even if the real command exits quickly. Only a second
        // snapshot can find this gate, and it cannot disappear before that snapshot is observed.
        let laterCleanup = rig.holdCleanup()
        defer { laterCleanup.finish() }
        #expect(!laterCleanup.wasDrained)
        release.finish()
        try await second.wait("the second cleanup snapshot") { _ in await laterCleanup.wasDrained }
        #expect(rig.exits.values.isEmpty)
        laterCleanup.finish()
        try await second.wait("the restart to finish both stops") { _ in !rig.exits.values.isEmpty }
        #expect(rig.exits.values == [75])
        #expect(rig.core.stoppingSessions.isEmpty)
        #expect(try rig.core.store.unfinishedTurns().isEmpty)
        let saved = try rig.core.store.sessions()
        #expect(saved.first { $0.id == initial.id }?.lastStopReason == "cancelled")
        #expect(saved.first { $0.id == later.id }?.lastStopReason == "cancelled")
        // The in-process exit records the status while leaving the sockets available to drain.
        _ = try await first.client.sessions()
        _ = try await second.client.sessions()
        #expect(await first.turnsEnded(initial.id) == ["cancelled"])
        #expect(await second.turnsEnded(later.id) == ["cancelled"])
        #expect(await first.recoveries(initial.id).isEmpty)
        #expect(await second.recoveries(later.id).isEmpty)
        await first.stop()
        await second.stop()
    }

    @Test("Immediate restart finishes Stop without waiting for a shared sibling and recovers that sibling")
    func restartWithWorkingSibling() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let first = try await harness.connect()
        let stopped = try await first.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path, attach: true))
        let sibling = try await first.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path, attach: true))
        _ = try await first.client.prompt(PromptParams(sessionID: stopped.id, text: "slow 100"))
        _ = try await first.client.prompt(PromptParams(sessionID: sibling.id, text: "stubborn 100"))
        try await first.wait("the sibling to start") { await $0.agentText(sibling.id).contains("tick 1") }
        try await first.client.cancel(stopped.id)
        try await first.client.shutdownHost(stopAgents: false, immediately: true)
        let exit = try await harness.waitForExit(timeout: .seconds(5))
        try #require(exit == 75)
        await first.stop()
        try harness.start()
        let second = try await harness.connect()
        try await second.client.attach(stopped.id)
        try await second.client.attach(sibling.id)
        try await second.wait("the sibling recovery") { await !$0.recoveries(sibling.id).isEmpty }
        #expect(await second.summaries[stopped.id]?.lastStopReason == "cancelled")
        #expect(await second.recoveries(stopped.id).isEmpty)
        #expect(await second.recoveries(sibling.id).first?.cause == .hostUpdated)
        await second.stop()
    }

    @Test("Closing a stopped task then exiting still waits for its orphaned command", arguments: [false, true])
    func closeThenShutdown(restart: Bool) async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
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
        #expect(!AgentStopProcesses(root: pid).hasRemainingProcesses)
        try await recorder.wait("the command to exit") { _ in kill(pid, 0) != 0 }
        #expect(!FileManager.default.fileExists(atPath: harness.agentStore.appending(path: "stop-marker.txt").path))
        await recorder.stop()
    }

    @Test("Closing a task or quitting during Stop cannot discard its command cleanup", arguments: [false, true])
    func closeDuringStop(shutdown: Bool) async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
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
        try await recorder.wait("the command to exit") { _ in kill(pid, 0) != 0 }
        #expect(!FileManager.default.fileExists(atPath: harness.agentStore.appending(path: "stop-marker.txt").path))
        await recorder.stop()
    }

    @Test(
        "Stop ends the observed shell without touching unrelated processes",
        arguments: [false, true])
    func cancelledCommand(agentExits: Bool) async throws {
        let unrelated = Process()
        unrelated.executableURL = URL(filePath: "/bin/sleep")
        unrelated.arguments = ["30"]
        try unrelated.run()
        defer { if unrelated.isRunning { unrelated.terminate() } }
        let harness = try HostHarness()
        defer { harness.cleanup() }
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
        try await recorder.wait("the stop result") { await $0.turnsEnded(session.id) == ["cancelled"] }
        #expect(await recorder.notices(session.id).contains { $0.hasPrefix("Stopped.") })
        #expect(!AgentStopProcesses(root: pid).hasRemainingProcesses)
        try await recorder.wait("the command to exit") { _ in kill(pid, 0) != 0 }
        #expect(unrelated.isRunning)
        #expect(!FileManager.default.fileExists(atPath: harness.agentStore.appending(path: "stop-marker.txt").path))
        #expect(await recorder.summaries[session.id]?.phase == .idle)
        #expect(await recorder.summaries[session.id]?.isQueuePaused == true)
        #expect(await recorder.recoveries(session.id).isEmpty)
        await recorder.stop()
    }
}
