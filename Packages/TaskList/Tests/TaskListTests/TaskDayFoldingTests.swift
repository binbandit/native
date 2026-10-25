import Foundation
import Testing

@testable import TaskList

struct TaskDayFoldingTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Melbourne") ?? .gmt
        return calendar
    }

    private var now: Date { Date(timeIntervalSince1970: 1_792_894_500) }

    @Test func calendarDayRatherThanTwentyFourHours() throws {
        let midnight = calendar.startOfDay(for: now)
        #expect(earlier(midnight.addingTimeInterval(-1)))
        #expect(!earlier(midnight))
        #expect(!earlier(now.addingTimeInterval(60)))
        #expect(!earlier(nil))
        let old = try #require(calendar.date(byAdding: .day, value: -2, to: midnight))
        #expect(!earlier(old, interval: .week))
        let weekBoundary = try #require(calendar.date(byAdding: .day, value: -6, to: midnight))
        #expect(!earlier(weekBoundary, interval: .week))
        #expect(earlier(weekBoundary.addingTimeInterval(-1), interval: .week))
        #expect(!earlier(old, interval: .never))
    }

    @Test func activityAndUnseenWorkStayVisible() {
        #expect(earlier(.distantPast))
        #expect(!earlier(.distantPast, atRest: false))
        #expect(!earlier(.distantPast, unread: true))
        #expect(!earlier(.distantPast, protected: true))
    }

    @Test func preservesOrderAndCoordinatorFamilies() {
        let tasks = ["old", "parent", "child-old", "child-working", "new", "old-2"]
        let result = TaskDayFolding.partition(tasks) {
            !["new", "child-working"].contains($0)
        } isChild: {
            $0.hasPrefix("child")
        }
        #expect(result.current == ["parent", "child-old", "child-working", "new"])
        #expect(result.earlier == ["old", "old-2"])
        let resting = TaskDayFolding.partition(tasks, isEarlier: { _ in true }, isChild: { $0.hasPrefix("child") })
        #expect(resting.current.isEmpty)
        #expect(resting.earlier == tasks)
    }

    @Test @MainActor func additionsPersistWithoutChangingLegacyPreferences() throws {
        let name = "TaskDayFoldingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "sidebar.showAgentIcons")
        let preferences = TaskSidebarPreferences(defaults: defaults)
        #expect(preferences.facts == [.needs, .machines])
        #expect(preferences.foldAfter == .day)
        preferences.set(.ages, shown: true)
        preferences.set(.needs, shown: false)
        preferences.setFoldAfter(.week)
        let reopened = TaskSidebarPreferences(defaults: defaults)
        #expect(reopened.facts == [.machines, .ages])
        #expect(reopened.foldAfter == .week)
        #expect(defaults.bool(forKey: "sidebar.showAgentIcons"))
    }

    private func earlier(
        _ date: Date?, atRest: Bool = true, unread: Bool = false, protected: Bool = false,
        interval: TaskDayFolding.Interval = .day
    ) -> Bool {
        TaskDayFolding.isEarlier(
            lastActivity: date, isAtRest: atRest, isUnread: unread, isProtected: protected,
            interval: interval, now: now, calendar: calendar)
    }
}
