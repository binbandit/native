import Foundation
import Testing

@testable import ACP

/// What a participant has in its context: its own items and what delivered transfers conveyed,
/// never what they merely considered.
struct TaskHistoryCoverageTests {
    private let history = TaskHistoryID()

    /// Claude Code (1) runs items 1 to 3, Codex (2) items 4 to 6, Claude Code again 7 and 8.
    private let items: [TaskHistoryItem] = [1, 1, 1, 2, 2, 2, 1, 1].enumerated().map { offset, source in
        TaskHistoryItem(seq: offset + 1, source: source, body: .agent("item \(offset + 1)"))
    }

    private func transfer(
        to target: Int, conveyed: [ClosedRange<Int>], state: TaskHistoryTransfer.State = .delivered,
        from source: TaskHistoryID? = nil
    ) -> TaskHistoryTransfer {
        TaskHistoryTransfer(
            sourceHistory: source ?? history, target: target, from: 0, through: 8, conveyed: conveyed,
            strategy: .delta, state: state)
    }

    @Test("A participant's own items carry its watermark until another's begin")
    func ownItems() {
        #expect(TaskHistoryCoverage.watermark(from: 0, over: items, participant: 1, conveyed: []) == 3)
        #expect(TaskHistoryCoverage.watermark(from: 0, over: items, participant: 2, conveyed: []) == 0)
        #expect(TaskHistoryCoverage.missing(items, participant: 1, conveyed: []).map(\.seq) == [4, 5, 6])
    }

    @Test("Only delivered transfers of this history count, and only for what they conveyed")
    func conveyedOnly() {
        let transfers = [
            transfer(to: 1, conveyed: [4...5]),
            transfer(to: 1, conveyed: [6...6], state: .sent),
            transfer(to: 1, conveyed: [6...6], from: TaskHistoryID()),
            transfer(to: 2, conveyed: [1...3]),
        ]
        let conveyed = TaskHistoryCoverage.conveyed(to: 1, by: transfers, in: history)
        #expect(conveyed == [4...5])
        #expect(TaskHistoryCoverage.watermark(from: 3, over: items, participant: 1, conveyed: conveyed) == 5)
        // Item 6 was considered but not conveyed: it stays missing, past the gap Claude Code's own
        // later items don't fill.
        #expect(TaskHistoryCoverage.missing(items, participant: 1, conveyed: conveyed).map(\.seq) == [6])
        let codex = TaskHistoryCoverage.conveyed(to: 2, by: transfers, in: history)
        #expect(TaskHistoryCoverage.watermark(from: 0, over: items, participant: 2, conveyed: codex) == 6)
    }

    @Test("Unknown transfer values from a newer host decode without failing")
    func unknownValues() throws {
        let transfer = transfer(to: 1, conveyed: [1...2])
        var json = String(decoding: try JSONEncoder().encode(transfer), as: UTF8.self)
        json = json.replacingOccurrences(of: #""delta""#, with: #""fork""#)
            .replacingOccurrences(of: #""delivered""#, with: #""queued""#)
        let decoded = try JSONDecoder().decode(TaskHistoryTransfer.self, from: Data(json.utf8))
        #expect(decoded.strategy == .unknown)
        #expect(decoded.state == .unknown)
        #expect(decoded.conveyed == [1...2])
    }
}
