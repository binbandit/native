import Foundation
import NativeHostProtocol
import SessionTitling
import Synchronization
import Testing

@testable import NativeHost

extension HostTitleTests {
    final class OutcomeTitler: SessionTitleGenerator {
        let calls = Mutex<[SessionTitleRequest]>([])

        func title(for request: SessionTitleRequest) async throws -> String? {
            calls.withLock { $0.append(request) }
            return request.firstTurnOutcome == nil ? "Fix build" : "Fix SessionModel isolation"
        }
    }

    @Test("A generated host title stays through later turns and is final on disk")
    func generatedTitleStays() async throws {
        let rig = try Rig()
        let titler = OutcomeTitler()
        let host = try rig.host(titler)
        let client = try await rig.connect(to: host)
        try await client.configureTitles(ConfigureTitlesParams(provider: .onDevice))
        let id = try await rig.startTask("fix the build", on: client)
        for _ in 0..<500 {
            if host.sessions[id]?.titleState.generated == "Fix build",
                host.sessions[id]?.titleState.firstTurnFinished == true
            {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(host.sessions[id]?.titleState.generated == "Fix build")
        #expect(titler.calls.withLock { $0.count } == 1)
        let saved = try #require(try host.store.titles()[id])
        #expect(saved.generated == "Fix build" && saved.refinementCount == 0 && saved.firstTurnFinished)
        #expect(saved.request == nil && saved.progress == nil)
        _ = try await client.prompt(PromptParams(sessionID: id, text: "and test it"))
        try await Task.sleep(for: .milliseconds(100))
        #expect(titler.calls.withLock { $0.count } == 1)
        await client.stop()
        for link in host.agents.values { link.endNow() }
    }

    @Test("A late model answer cannot refine a client's generated title")
    func lateModelCannotRefine() async throws {
        let rig = try Rig()
        let titler = ScriptedTitler(answer: "Fix build", released: false)
        let host = try rig.host(titler)
        let client = try await rig.connect(to: host)
        try await client.configureTitles(ConfigureTitlesParams(provider: .onDevice))
        let id = try await rig.startTask("fix the build", on: client)
        for _ in 0..<500 {
            if host.sessions[id]?.phase == .idle && !titler.requests.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try await client.setSessionTitle(SetSessionTitleParams(sessionID: id, title: "Fix build", source: .generated))
        #expect(host.sessions[id]?.titleState.refinementCount == 0)
        titler.script.withLock { $0.answer = "Fix SessionModel isolation" }
        titler.release()
        for _ in 0..<500 where host.titling.generating.contains(id) { try await Task.sleep(for: .milliseconds(20)) }
        #expect(host.sessions[id]?.titleState.generated == "Fix build")
        #expect(host.sessions[id]?.titleState.request == nil && host.sessions[id]?.titleState.progress == nil)
        #expect(titler.requests.count == 1)
        await client.stop()
        for link in host.agents.values { link.endNow() }
    }

    @Test("A late model answer leaves a client's completed title settled")
    func lateModelAfterClient() async throws {
        let rig = try Rig()
        let titler = ScriptedTitler(answer: "Late model answer", released: false)
        let host = try rig.host(titler)
        let client = try await rig.connect(to: host)
        try await client.configureTitles(ConfigureTitlesParams(provider: .onDevice))
        let id = try await rig.startTask("fix login state", on: client)
        for _ in 0..<500 where titler.requests.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        try await client.setSessionTitle(
            SetSessionTitleParams(sessionID: id, title: "Fix login state", source: .generated))
        titler.release()
        for _ in 0..<500 where host.titling.generating.contains(id) { try await Task.sleep(for: .milliseconds(20)) }
        #expect(host.sessions[id]?.titleState.generated == "Fix login state")
        #expect(host.sessions[id]?.titleState.progress == nil)
        await client.stop()
        for link in host.agents.values { link.endNow() }
    }

    @Test("Client answers cannot replace a generated title, even with a refinement revision")
    func clientCannotRefine() async throws {
        let rig = try Rig()
        let host = try rig.host(nil)
        let client = try await rig.connect(to: host)
        try await client.configureTitles(ConfigureTitlesParams(provider: .client))
        let id = try await rig.startTask("fix the build", on: client)
        for _ in 0..<500 {
            if host.sessions[id]?.phase == .idle { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try await client.setSessionTitle(SetSessionTitleParams(sessionID: id, title: "Fix build", source: .generated))
        let titles = try #require(try await client.sessions().first { $0.id == id }?.titles)
        #expect(titles.generated == "Fix build" && titles.request == nil)
        try await client.setSessionTitle(
            SetSessionTitleParams(sessionID: id, title: "Stale initial answer", source: .generated))
        #expect(host.sessions[id]?.titleState.generated == "Fix build")
        try await client.setSessionTitle(
            SetSessionTitleParams(
                sessionID: id, title: "Fix SessionModel isolation", source: .generated, revision: 1))
        try await client.setSessionTitle(
            SetSessionTitleParams(
                sessionID: id, title: "Duplicate answer", source: .generated, revision: 1))
        #expect(host.sessions[id]?.titleState.generated == "Fix build")
        await client.stop()
        for link in host.agents.values { link.endNow() }
    }
}
