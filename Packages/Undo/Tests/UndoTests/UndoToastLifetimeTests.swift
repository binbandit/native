import Testing

@testable import Undo

@Suite struct UndoToastLifetimeTests {
    @Test func hoverPreservesTheRemainingTime() {
        let start = ContinuousClock.now
        var lifetime = UndoToastLifetime(duration: .seconds(5), now: start)
        lifetime.setHeld(true, now: start.advanced(by: .seconds(1)))
        #expect(lifetime.deadline == nil)
        lifetime.setHeld(false, now: start.advanced(by: .seconds(30)))
        #expect(lifetime.deadline == start.advanced(by: .seconds(34)))
    }

    @Test func leavingLateGrantsThreeSeconds() {
        let start = ContinuousClock.now
        var lifetime = UndoToastLifetime(duration: .seconds(5), now: start)
        lifetime.setHeld(true, now: start.advanced(by: .seconds(4)))
        lifetime.setHeld(false, now: start.advanced(by: .seconds(40)))
        #expect(lifetime.deadline == start.advanced(by: .seconds(43)))
    }

    @Test func repeatedHoverNotificationsDoNotRestartTheTimer() {
        let start = ContinuousClock.now
        var lifetime = UndoToastLifetime(duration: .seconds(5), now: start)
        lifetime.setHeld(false, now: start.advanced(by: .seconds(2)))
        #expect(lifetime.deadline == start.advanced(by: .seconds(5)))
        lifetime.setHeld(true, now: start.advanced(by: .seconds(3)))
        lifetime.setHeld(true, now: start.advanced(by: .seconds(10)))
        lifetime.setHeld(false, now: start.advanced(by: .seconds(20)))
        #expect(lifetime.deadline == start.advanced(by: .seconds(23)))
    }
}
