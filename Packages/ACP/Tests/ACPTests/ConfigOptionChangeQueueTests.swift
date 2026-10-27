import Foundation
import Testing

@testable import ACP

@MainActor
struct ConfigOptionChangeQueueTests {
    private struct SettingsFailure: Error { let message: String }
    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            if ContinuousClock.now > deadline { throw SettingsFailure(message: "Timed out") }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    @Test func serializesWholeSnapshotReplies() async throws {
        let changes = ConfigOptionChangeQueue()
        var first: CheckedContinuation<Void, Never>?
        var second: CheckedContinuation<Void, Never>?
        var events: [String] = []
        var snapshot = ["model": "haiku", "effort": "low"]
        var undo: String?
        changes.enqueue("model") {
            events.append("model starts")
            var reply = snapshot
            await withCheckedContinuation { first = $0 }
            reply["model"] = "sonnet"
            snapshot = reply
            undo = "model"
            events.append("model ends")
        }
        changes.enqueue("effort") {
            events.append("effort starts")
            var reply = snapshot
            await withCheckedContinuation { second = $0 }
            reply["effort"] = "high"
            snapshot = reply
            undo = "effort"
            events.append("effort ends")
        }
        changes.enqueue("effort") { events.append("duplicate") }
        try await wait { first != nil }
        #expect(events == ["model starts"], "Snapshot requests overlapped")
        #expect(changes.contains("model") && changes.contains("effort"), "Queued settings were unlocked")
        first?.resume()
        try await wait { second != nil }
        #expect(!changes.contains("model") && changes.contains("effort"), "Completion cleared another setting")
        changes.enqueue("effort") { events.append("second duplicate") }
        second?.resume()
        try await wait { changes.isEmpty }
        #expect(
            events == ["model starts", "model ends", "effort starts", "effort ends"], "Requests lost click order")
        #expect(snapshot == ["model": "sonnet", "effort": "high"], "A full snapshot reverted a setting")
        #expect(undo == "effort", "Undo tracks the wrong user change")
    }

}
