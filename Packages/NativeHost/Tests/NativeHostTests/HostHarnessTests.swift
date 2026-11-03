import Foundation
import Testing

@Suite("End-to-end host cleanup", .serialized, .timeLimit(.minutes(1)))
struct HostHarnessTests {
    @Test("Starting again does not lose the previous host process")
    func repeatedStart() throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let firstPID = try #require(harness.hostProcessID)
        try harness.start()
        let secondPID = try #require(harness.hostProcessID)
        harness.cleanup()
        expectGone([firstPID, secondPID], root: harness.root)
    }

    @Test("Deferred cleanup runs on return, thrown error, and exit timeout", arguments: Ending.allCases)
    func deferredCleanup(_ ending: Ending) async throws {
        let harness = try HostHarness()
        let root = harness.root
        var pid: Int32?
        do {
            defer { harness.cleanup() }
            try harness.start()
            pid = harness.hostProcessID
            switch ending {
            case .success: break
            case .error: throw CancellationError()
            case .timeout:
                #expect(try await harness.waitForExit(timeout: .milliseconds(1)) == nil)
            }
        } catch is CancellationError {
            #expect(ending == .error)
        }
        expectGone([try #require(pid)], root: root)
        // Cleanup is safe to call again, including from deinit.
        harness.cleanup()
    }

    @Test("Connecting waits for a handshake even when startup takes more than ten seconds")
    func delayedConnection() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let pid = try #require(harness.hostProcessID)
        // Reproduce a host that is not scheduled under load, through the real socket and handshake.
        #expect(kill(pid, SIGSTOP) == 0)
        let resume = Task {
            try await Task.sleep(for: .seconds(11))
            #expect(kill(pid, SIGCONT) == 0)
        }
        defer { resume.cancel() }
        let recorder = try await harness.connect()
        try await resume.value
        #expect(await recorder.client.hostInfo != nil)
        #expect(try await recorder.client.sessions().isEmpty)
        await recorder.stop()
    }

    @Test("A host that never answers fails at connect with its last connection state")
    func connectionTimeout() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        do {
            _ = try await harness.connect(timeout: .milliseconds(100))
            Issue.record("Connected without a host")
        } catch let error as HostHarness.ConnectionFailure {
            #expect(error.reason.contains("did not complete initialization"))
            #expect(error.reason.contains("Last client state:"))
        }
    }

    @Test("A host that exits before initialization reports its exit instead of notConnected")
    func hostExited() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let pid = try #require(harness.hostProcessID)
        #expect(kill(pid, SIGKILL) == 0)
        do {
            _ = try await harness.connect()
            Issue.record("Connected to an exited host")
        } catch let error as HostHarness.ConnectionFailure {
            #expect(error.reason.contains("Host exited before connecting"))
            #expect(error.reason.contains("status 9"))
        }
    }

    @Test("Cancelling setup stops waiting without requiring the startup watchdog")
    func cancelledConnection() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        let setup = Task { try await harness.connect() }
        setup.cancel()
        do {
            _ = try await setup.value
            Issue.record("Connected after cancellation")
        } catch is CancellationError {}
    }

    enum Ending: CaseIterable, Sendable {
        case success, error, timeout
    }

    private func expectGone(_ pids: [Int32], root: URL) {
        for pid in pids {
            #expect(kill(pid, 0) == -1)
            #expect(errno == ESRCH)
        }
        #expect(!FileManager.default.fileExists(atPath: root.path(percentEncoded: false)))
    }
}
