import ACP
import Foundation
import NativeHostProtocol
import Testing

@testable import NativeHost

@Suite("Owned process tree stops", .serialized, .timeLimit(.minutes(1)))
struct AgentStopProcessesTests {
    @Test("New requests wait while the previous agent's commands are being terminated")
    @HostActor
    func requestsWaitForStop() async throws {
        let link = AgentLink(spec: AgentSpec(id: "fake", name: "Fake Agent", command: "/no-such-agent"))
        link.commandStopOwnsTree = true
        link.beginCommandStop()
        let request = Task {
            try await link.ensureStarted(
                environment: { [:] }, clientInfo: Implementation(name: "test", version: "1"),
                onEvent: { _, _ in })
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(link.hostAgent.state == .stopped)
        request.cancel()
        await #expect(throws: CancellationError.self) { try await request.value }
    }

    @Test("A remembered shell still ends after its parent exits")
    func reparentedCommand() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "native-stop-tree-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let parent = Process()
        parent.executableURL = URL(filePath: "/bin/sh")
        parent.arguments = [
            "-c",
            "trap 'exit 0' TERM; /bin/sh -c 'trap \"\" TERM; sleep 3; printf survived > marker' & echo $! > child.pid; wait",
        ]
        parent.currentDirectoryURL = folder
        parent.standardOutput = FileHandle.nullDevice
        parent.standardError = FileHandle.nullDevice
        try parent.run()
        var tree = AgentStopProcesses(root: parent.processIdentifier)
        defer { tree.terminate() }
        let deadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: folder.appending(path: "child.pid").path),
            ContinuousClock.now < deadline
        {
            try await Task.sleep(for: .milliseconds(10))
        }
        let child = try #require(
            Int32(
                String(contentsOf: folder.appending(path: "child.pid"), encoding: .utf8).trimmingCharacters(
                    in: .whitespacesAndNewlines)))
        tree.refresh()
        kill(parent.processIdentifier, SIGTERM)
        while parent.isRunning, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!parent.isRunning)
        #expect(kill(child, 0) == 0)
        repeat {
            tree.terminate()
            try await Task.sleep(for: .milliseconds(10))
        } while tree.hasRemainingProcesses && ContinuousClock.now < deadline
        #expect(!tree.hasRemainingProcesses)
        try await Task.sleep(for: .seconds(4))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "marker").path))
    }
}
