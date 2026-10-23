#if os(macOS)
import Darwin
import Foundation
import NativeHostProtocol
import Testing

@testable import NativeHostClient

/// A host the app starts itself, for when background activity is off: it lives as long as the app.
@Suite("Attached host", .serialized, .timeLimit(.minutes(1)))
struct AttachedHostTests {
    @Test("It gets what launchd would give it and its channel, and nothing else of the app's environment")
    func environment() {
        let app = [
            "HOME": "/Users/me", "USER": "me", "LOGNAME": "me", "SHELL": "/bin/zsh", "TMPDIR": "/tmp/x",
            "PATH": "/opt/homebrew/bin:/usr/bin", "DYLD_INSERT_LIBRARIES": "/evil.dylib", "OPENAI_API_KEY": "secret",
        ]
        let location = HostLocation(directory: URL(filePath: "/tmp/h"), channel: "abc", isDevelopment: true)
        #expect(
            AttachedHost.environment(for: location, from: app) == [
                "HOME": "/Users/me", "USER": "me", "LOGNAME": "me", "SHELL": "/bin/zsh", "TMPDIR": "/tmp/x",
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "NATIVE_HOST_CHANNEL": "abc", "NATIVE_HOST_DEVELOPMENT": "1",
            ])
    }

    @Test("When whatever started it is killed, it stops its agents and exits")
    func exitsWithParent() async throws {
        let harness = try HostHarness()
        harness.agentEnvironment = ["FAKE_AGENT_GRANDCHILD": harness.grandchildFile.path(percentEncoded: false)]
        let parent = try startAttached(harness)
        let recorder = try await harness.connect()
        let host = try #require(await recorder.client.hostInfo?.processID)
        _ = try await recorder.client.startAgent("fake")
        let grandchild = try #require(harness.grandchild)
        kill(parent.processIdentifier, SIGKILL)
        try await recorder.wait("the host to exit") { _ in kill(host, 0) != 0 }
        try await recorder.wait("the agent's own processes to end") { _ in kill(grandchild, 0) != 0 }
        await recorder.stop()
    }

    @Test(
        "Quitting the app or ending the host ends known processes without recovering the turn",
        arguments: [Ending.appQuits, .hostTerminated])
    func endsTurnsWithoutRecovery(_ ending: Ending) async throws {
        let harness = try HostHarness()
        let parent = try startAttached(harness)
        let first = try await harness.connect()
        let host = try #require(await first.client.hostInfo?.processID)
        let summary = try await first.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path(percentEncoded: false)))
        try await first.client.attach(summary.id)
        _ = try await first.client.prompt(PromptParams(sessionID: summary.id, text: "slow 30"))
        try await first.wait("the turn to get going") { await $0.agentText(summary.id).contains("tick 2") }
        switch ending {
        case .appQuits: kill(parent.processIdentifier, SIGKILL)
        case .hostTerminated: kill(host, SIGTERM)
        }
        try await first.wait("the host to exit") { _ in kill(host, 0) != 0 }
        await first.stop()
        kill(parent.processIdentifier, SIGKILL)

        // The next host (the app opened again) has nothing to pick up.
        try harness.start()
        let second = try await harness.connect()
        try await second.client.attach(summary.id)
        let reopened = try await second.client.sessions().first { $0.id == summary.id }
        #expect(reopened?.lastStopReason == "error")
        #expect(reopened?.phase != .prompting && reopened?.phase != .recovering)
        try await Task.sleep(for: .seconds(1))
        #expect(await second.recoveries(summary.id).isEmpty)
        #expect(harness.received == ["prompt\tslow 30"])
        let kinds = try await second.client.activity().map(\.kind)
        #expect(kinds.contains(.stopped))
        #expect(!kinds.contains(.recovered) && !kinds.contains(.hostStarted))
        await second.stop()
    }

    enum Ending: Sendable, CustomTestStringConvertible {
        case appQuits, hostTerminated

        var testDescription: String {
            switch self {
            case .appQuits: "the app quits"
            case .hostTerminated: "the host gets SIGTERM"
            }
        }
    }

    /// A stand-in for the app: a shell that starts the host the way AttachedHost does, then waits.
    private func startAttached(_ harness: HostHarness) throws -> Process {
        let parent = Process()
        parent.executableURL = URL(filePath: "/bin/sh")
        parent.arguments = [
            "-c", #""$0" serve --home "$1" --plugins "$2" --inherit-environment --exit-with-parent & wait"#,
            HostHarness.products.appending(path: "native-host").path(percentEncoded: false),
            harness.home.path(percentEncoded: false), harness.plugins.path(percentEncoded: false),
        ]
        try parent.run()
        return parent
    }
}
#endif
