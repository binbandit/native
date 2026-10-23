import ACP
import Foundation
import NativeHostProtocol
import Testing

@testable import NativeHost

@Suite("Owned process tree stops", .serialized, .timeLimit(.minutes(1)))
struct AgentStopProcessesTests {
    @Test("An empty snapshot does not prove that an unobserved writer exited")
    func escapedWriter() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "native-stop-escape-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let parent = Process()
        parent.executableURL = URL(filePath: "/bin/sh")
        parent.arguments = [
            "-c",
            "while [ ! -f fork ]; do sleep 0.02; done; /bin/sh -c 'while [ ! -f write ]; do sleep 0.02; done; printf survived > marker' & echo $! > child.pid",
        ]
        parent.currentDirectoryURL = folder
        parent.standardOutput = FileHandle.nullDevice
        parent.standardError = FileHandle.nullDevice
        try parent.run()
        var tree = AgentStopProcesses(root: parent.processIdentifier)
        defer { Self.end(&tree) }
        try Data().write(to: folder.appending(path: "fork"))
        let deadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: folder.appending(path: "child.pid").path),
            ContinuousClock.now < deadline
        {
            try await Task.sleep(for: .milliseconds(10))
        }
        let child = try childPID(in: folder)
        var childCleanup = AgentStopProcesses(root: child)
        defer { Self.end(&childCleanup) }
        // Foundation can still report a zombie parent as running on Linux. The child's kernel
        // parent identifies reparenting without waiting for the child's inherited resources.
        while Self.parent(of: child) == parent.processIdentifier, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(Self.parent(of: child) != parent.processIdentifier)
        tree.terminate()
        #expect(!tree.hasRemainingProcesses)
        try Data().write(to: folder.appending(path: "write"))
        let writeDeadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: folder.appending(path: "marker").path),
            ContinuousClock.now < writeDeadline
        {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "marker").path))
    }

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
            "trap 'exit 0' TERM; /bin/sh -c 'trap \"\" TERM; while [ ! -f write ]; do sleep 0.02; done; printf survived > marker' & echo $! > child.pid; wait",
        ]
        parent.currentDirectoryURL = folder
        parent.standardOutput = FileHandle.nullDevice
        parent.standardError = FileHandle.nullDevice
        try parent.run()
        var tree = AgentStopProcesses(root: parent.processIdentifier)
        defer { Self.end(&tree) }
        let deadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: folder.appending(path: "child.pid").path),
            ContinuousClock.now < deadline
        {
            try await Task.sleep(for: .milliseconds(10))
        }
        let child = try childPID(in: folder)
        tree.refresh()
        // A shell's wait and inherited TERM mask differ across hosts. Force the parent exit so
        // this fixture tests ownership after reparenting, independently of shell signal handling.
        kill(parent.processIdentifier, SIGKILL)
        while Self.parent(of: child) == parent.processIdentifier, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(Self.parent(of: child) != parent.processIdentifier)
        #expect(kill(child, 0) == 0)
        let stopDeadline = ContinuousClock.now + .seconds(5)
        repeat {
            tree.terminate()
            try await Task.sleep(for: .milliseconds(10))
        } while tree.hasRemainingProcesses && ContinuousClock.now < stopDeadline
        #expect(!tree.hasRemainingProcesses)
        try Data().write(to: folder.appending(path: "write"))
        try await Task.sleep(for: .milliseconds(200))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "marker").path))
    }

    private func childPID(in folder: URL) throws -> pid_t {
        try #require(
            Int32(
                String(contentsOf: folder.appending(path: "child.pid"), encoding: .utf8).trimmingCharacters(
                    in: .whitespacesAndNewlines)))
    }

    private static func end(_ tree: inout AgentStopProcesses) {
        let deadline = ContinuousClock.now + .seconds(2)
        repeat {
            tree.terminate()
            usleep(10_000)
        } while tree.hasRemainingProcesses && ContinuousClock.now < deadline
    }

    private static func parent(of pid: pid_t) -> pid_t? {
        #if canImport(Darwin)
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size)) == Int32(size) else { return nil }
        return pid_t(info.pbi_ppid)
        #elseif os(Linux)
        guard let stat = try? String(contentsOfFile: "/proc/\(pid)/stat", encoding: .utf8),
            let end = stat.lastIndex(of: ")")
        else { return nil }
        let fields = stat[stat.index(after: end)...].split(separator: " ")
        return fields.count > 1 ? pid_t(fields[1]) : nil
        #else
        return nil
        #endif
    }
}
