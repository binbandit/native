import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import SessionTitling
import Testing

@testable import NativeHost

@Suite("Host title retries", .serialized, .timeLimit(.minutes(1)))
@HostActor
struct HostTitleRetryTests {
    typealias Rig = HostTitleTests.Rig
    typealias Titler = HostTitleTests.ScriptedTitler

    private func settled(_ id: HostSessionID, in host: HostCore) async throws {
        for _ in 0..<500 {
            if host.sessions[id]?.phase == .idle, !host.titling.generating.contains(id) { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("The turn and title did not settle")
    }

    @Test("A failed or unavailable title is retried once on the next turn", arguments: [false, true])
    func retriesOnNextTurn(unavailable: Bool) async throws {
        let rig = try Rig()
        let titler = Titler(answer: unavailable ? nil : "...")
        let host = try rig.host(titler)
        let client = try await rig.connect(to: host)
        try await client.configureTitles(ConfigureTitlesParams(provider: .onDevice))
        let id = try await rig.startTask("fix the login test", on: client)
        try await settled(id, in: host)
        #expect(titler.requests.count == 1)
        titler.script.withLock { $0.answer = "Fix login test" }
        _ = try await client.prompt(PromptParams(sessionID: id, text: "try again"))
        try await settled(id, in: host)
        #expect(titler.requests.count == 2)
        #expect(host.sessions[id]?.titleState.generated == "Fix login test")
        #expect(titler.requests.last?.prompt == "fix the login test")
        await client.stop()
    }

    @Test("The retry budget survives a restart, and a manual rename prevents a retry")
    func boundedRetryAndRename() async throws {
        let rig = try Rig()
        let titler = Titler(answer: "...")
        let first = try rig.host(titler)
        let client = try await rig.connect(to: first)
        try await client.configureTitles(ConfigureTitlesParams(provider: .onDevice))
        let id = try await rig.startTask("fix the login test", on: client)
        try await settled(id, in: first)
        _ = try await client.prompt(PromptParams(sessionID: id, text: "try again"))
        try await settled(id, in: first)
        #expect(titler.requests.count == 2)
        await client.stop()
        for link in first.agents.values { link.endNow() }
        let second = try rig.host(titler)
        let later = try await rig.connect(to: second)
        _ = try await later.prompt(PromptParams(sessionID: id, text: "third turn"))
        try await settled(id, in: second)
        #expect(titler.requests.count == 2)
        #expect(second.sessions[id]?.displayTitle == "Fix the login test")

        let renamed = try await rig.startTask("add upload retry", on: later)
        try await settled(renamed, in: second)
        try await later.setSessionTitle(SetSessionTitleParams(sessionID: renamed, title: "Mine", source: .user))
        let before = titler.requests.count
        _ = try await later.prompt(PromptParams(sessionID: renamed, text: "another turn"))
        try await settled(renamed, in: second)
        #expect(titler.requests.count == before)
        #expect(second.sessions[renamed]?.displayTitle == "Mine")
        await later.stop()
    }

    @Test("A slow title exposes the first-message fallback immediately")
    func slowTitle() async throws {
        let rig = try Rig()
        let titler = Titler(answer: "Fix login test", released: false)
        let host = try rig.host(titler)
        let client = try await rig.connect(to: host)
        try await client.configureTitles(ConfigureTitlesParams(provider: .onDevice))
        let id = try await rig.startTask("fix the login test", on: client)
        let summary = try #require(try await client.sessions().first { $0.id == id })
        #expect(summary.titles?.fallback == "Fix the login test")
        titler.release()
        try await settled(id, in: host)
        await client.stop()
    }

    @Test("A later usable prompt can name a task whose first prompt had no title material")
    func skippedFirstPrompt() async throws {
        let rig = try Rig()
        let titler = Titler(answer: "Fix login test")
        let host = try rig.host(titler)
        let client = try await rig.connect(to: host)
        try await client.configureTitles(ConfigureTitlesParams(provider: .onDevice))
        let session = try await client.newSession(NewSessionParams(agentID: "fake", cwd: rig.project.path()))
        _ = try await client.prompt(PromptParams(sessionID: session.id, text: "", content: [.text("")]))
        try await settled(session.id, in: host)
        #expect(titler.requests.isEmpty)
        _ = try await client.prompt(PromptParams(sessionID: session.id, text: "fix the login test"))
        try await settled(session.id, in: host)
        #expect(host.sessions[session.id]?.titleState.generated == "Fix login test")
        await client.stop()
    }

    @Test("Content-only prompts can name a task without separate transcript metadata", arguments: [false, true])
    func contentOnly(attachment: Bool) async throws {
        let rig = try Rig()
        let titler = Titler(answer: "Fix login test")
        let host = try rig.host(titler)
        let client = try await rig.connect(to: host)
        try await client.configureTitles(ConfigureTitlesParams(provider: .onDevice))
        let session = try await client.newSession(NewSessionParams(agentID: "fake", cwd: rig.project.path()))
        let content: [ContentBlock] =
            attachment
            ? [.resourceLink(uri: "file:///login.log", name: "login.log")] : [.text("fix the login test")]
        _ = try await client.prompt(
            PromptParams(sessionID: session.id, text: "", content: content))
        try await settled(session.id, in: host)
        #expect(titler.requests.first?.prompt == (attachment ? "login.log" : "fix the login test"))
        #expect(host.sessions[session.id]?.titleState.generated == "Fix login test")
        await client.stop()
    }

    @Test("Client titlers get a distinct retry request once")
    func clientRetry() async throws {
        let rig = try Rig()
        let host = try rig.host(nil)
        let client = try await rig.connect(to: host)
        try await client.configureTitles(ConfigureTitlesParams(provider: .client))
        let id = try await rig.startTask("fix the login test", on: client)
        try await settled(id, in: host)
        let first = try #require(try await client.sessions().first { $0.id == id }?.titles?.request)
        _ = try await client.prompt(PromptParams(sessionID: id, text: "try again"))
        try await settled(id, in: host)
        let retry = try #require(try await client.sessions().first { $0.id == id }?.titles?.request)
        #expect(retry != first)
        #expect(retry.prompt == first.prompt)
        _ = try await client.prompt(PromptParams(sessionID: id, text: "third turn"))
        try await settled(id, in: host)
        #expect(try await client.sessions().first { $0.id == id }?.titles?.request == retry)
        await client.stop()
    }

    @Test("Stopping the first turn does not prevent a title retry")
    func stoppedFirstTurn() async throws {
        let rig = try Rig()
        let titler = Titler(answer: "...")
        let host = try rig.host(titler)
        let client = try await rig.connect(to: host)
        try await client.configureTitles(ConfigureTitlesParams(provider: .onDevice))
        let id = try await rig.startTask("slow 50", on: client)
        try await client.cancel(id)
        try await settled(id, in: host)
        #expect(host.sessions[id]?.record.lastStopReason == "cancelled")
        titler.script.withLock { $0.answer = "Count slowly" }
        _ = try await client.prompt(PromptParams(sessionID: id, text: "continue"))
        try await settled(id, in: host)
        #expect(host.sessions[id]?.titleState.generated == "Count slowly")
        await client.stop()
    }

    @Test("An unavailable model is retried on the next turn after a restart, not at each restart")
    func unavailableAcrossRestart() async throws {
        let rig = try Rig()
        let titler = Titler(answer: nil)
        let first = try rig.host(titler)
        let client = try await rig.connect(to: first)
        try await client.configureTitles(ConfigureTitlesParams(provider: .onDevice))
        let id = try await rig.startTask("fix the login test", on: client)
        try await settled(id, in: first)
        await client.stop()
        for link in first.agents.values { link.endNow() }
        let second = try rig.host(titler)
        let later = try await rig.connect(to: second)
        #expect(titler.requests.count == 1)
        titler.script.withLock { $0.answer = "Fix login test" }
        _ = try await later.prompt(PromptParams(sessionID: id, text: "continue"))
        try await settled(id, in: second)
        #expect(titler.requests.count == 2)
        #expect(second.sessions[id]?.titleState.generated == "Fix login test")
        await later.stop()
    }
}
