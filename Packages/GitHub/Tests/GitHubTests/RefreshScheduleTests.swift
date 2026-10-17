import Foundation
import Testing
@testable import GitHub

struct RefreshScheduleTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func refreshesRightAwayAtFirst() {
        let schedule = RefreshSchedule()
        #expect(schedule.isDue(.background, at: start))
        #expect(schedule.refreshesOnReturn(at: start))
    }

    @Test func steadyIntervalDependsOnWhoIsWatching() {
        var schedule = RefreshSchedule()
        schedule.recordSuccess(at: start)
        #expect(schedule.nextRefresh(.watching) == start.addingTimeInterval(120))
        #expect(schedule.nextRefresh(.background) == start.addingTimeInterval(600))
        #expect(!schedule.refreshesOnReturn(at: start.addingTimeInterval(30)))
        #expect(schedule.refreshesOnReturn(at: start.addingTimeInterval(61)))
    }

    @Test func transientFailuresBackOffExponentiallyToACap() {
        var schedule = RefreshSchedule()
        var delays: [TimeInterval] = []
        for _ in 0..<8 {
            schedule.recordFailure(.offline("no network"), at: start)
            delays.append(schedule.nextRefresh(.watching).timeIntervalSince(start))
        }
        #expect(delays == [30, 60, 120, 240, 480, 900, 900, 900])

        schedule.recordSuccess(at: start)
        #expect(schedule.consecutiveFailures == 0)
        #expect(schedule.nextRefresh(.watching) == start.addingTimeInterval(120))
    }

    @Test func rateLimitWaitsForTheReset() {
        var schedule = RefreshSchedule()
        let reset = start.addingTimeInterval(1_800)
        schedule.recordFailure(.rateLimited("API rate limit exceeded"), at: start, rateLimitResetsAt: reset)

        #expect(schedule.nextRefresh(.watching) == reset.addingTimeInterval(5))
        #expect(!schedule.refreshesOnReturn(at: start.addingTimeInterval(600)))
        #expect(schedule.refreshesOnReturn(at: reset.addingTimeInterval(10)))
    }

    @Test func rateLimitWithoutAResetBacksOff() {
        var schedule = RefreshSchedule()
        schedule.recordFailure(.rateLimited("secondary rate limit"), at: start)
        #expect(schedule.nextRefresh(.watching) == start.addingTimeInterval(30))
    }

    @Test func problemsTheUserMustFixAreRecheckedSlowly() {
        var schedule = RefreshSchedule()
        schedule.recordFailure(.notAuthenticated("gh auth login"), at: start)
        schedule.recordFailure(.notAuthenticated("gh auth login"), at: start)
        #expect(schedule.nextRefresh(.watching) == start.addingTimeInterval(600))
        // Coming back after signing in in a terminal should pick it up.
        #expect(schedule.refreshesOnReturn(at: start.addingTimeInterval(90)))
    }
}
