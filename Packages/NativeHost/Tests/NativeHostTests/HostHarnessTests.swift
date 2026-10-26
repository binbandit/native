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
