import Foundation
import Testing

@testable import TaskList

@MainActor
@Suite struct TaskActivityDatesTests {
    private let old = Date(timeIntervalSince1970: 1_000)
    private let recent = Date(timeIntervalSince1970: 2_000)

    @Test("Completed tasks keep their activity date and order before and after opening")
    func reopening() {
        let dates = TaskActivityDates<String>()
        let listed = ["first": old, "second": old.addingTimeInterval(100)]
        // The host's startup snapshot includes a completed turn in an unopened task.
        dates.record(recent, for: "first")
        func order(live: [String: Date] = [:]) -> [String] {
            listed.keys.sorted {
                (dates.date(for: $0, listed: listed[$0], live: live[$0]) ?? .distantPast)
                    > (dates.date(for: $1, listed: listed[$1], live: live[$1]) ?? .distantPast)
            }
        }
        #expect(order() == ["first", "second"])
        #expect(order(live: ["first": recent]) == ["first", "second"])
        #expect(dates.date(for: "first", listed: old) == recent)
        #expect(dates.date(for: "first", listed: old, live: recent) == recent)
        // A new prompt, including one sent while the task isn't open here, advances its order.
        dates.record(recent.addingTimeInterval(100), for: "second")
        #expect(dates.date(for: "second") == recent.addingTimeInterval(100))
        #expect(order() == ["second", "first"])
    }

    @Test("Repeated, missing and stale host dates cannot rewind known activity")
    func metadataAndStaleSnapshots() {
        let dates = TaskActivityDates<String>()
        dates.record(recent, for: "task")
        dates.record(recent, for: "task")
        dates.record(nil, for: "task")
        dates.record(old, for: "task")
        #expect(dates.date(for: "task", listed: old, live: old) == recent)
    }

    @Test("Unknown tasks keep the listing date without inventing a date on opening")
    func listingFallback() {
        let dates = TaskActivityDates<String>()
        #expect(dates.date(for: "task") == nil)
        #expect(dates.date(for: "task", listed: old) == old)
        dates.record(nil, for: "task")
        #expect(dates.date(for: "task", listed: old) == old)
    }

    @Test("Newer provider activity and in-app prompts take precedence over older host activity")
    func newerActivity() {
        let dates = TaskActivityDates<String>()
        dates.record(old, for: "task")
        #expect(dates.date(for: "task", listed: recent, live: old) == recent)
        #expect(dates.date(for: "task", listed: old, live: recent) == recent)
        #expect(dates.date(for: "other", listed: old) == old)
    }
}
