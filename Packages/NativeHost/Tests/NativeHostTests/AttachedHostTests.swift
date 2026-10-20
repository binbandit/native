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
        // A stand-in for the app: a shell that starts the host the way AttachedHost does, then waits.
        let parent = Process()
        parent.executableURL = URL(filePath: "/bin/sh")
        parent.arguments = [
            "-c", #""$0" serve --home "$1" --plugins "$2" --inherit-environment --exit-with-parent & wait"#,
            HostHarness.products.appending(path: "native-host").path(percentEncoded: false),
            harness.home.path(percentEncoded: false), harness.plugins.path(percentEncoded: false),
        ]
        try parent.run()
        let recorder = try await harness.connect()
        let host = try #require(await recorder.client.hostInfo?.processID)
        _ = try await recorder.client.startAgent("fake")
        let grandchild = try #require(harness.grandchild)
        kill(parent.processIdentifier, SIGKILL)
        try await recorder.wait("the host to exit") { _ in kill(host, 0) != 0 }
        try await recorder.wait("the agent's own processes to end") { _ in kill(grandchild, 0) != 0 }
        await recorder.stop()
    }
}
