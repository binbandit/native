import Foundation

/// Everything the user chose about keeping the Mac awake. Plain data, so the app can hand it to a
/// background host process as is.
nonisolated struct KeepAwakePolicy: Codable, Hashable, Sendable {
    var mode = KeepAwakeMode.off
    /// Stay awake until then whatever the mode, then go back to it ("Stay awake for 2 hours").
    var awakeUntil: Date?
    /// Also keep the display from dimming and sleeping (`caffeinate -d`), not just the system.
    var keepsDisplayOn = false
    var battery = KeepAwakeBatteryRule.stopWhenLow

    /// The timer, if it's still running at `date`.
    func timer(at date: Date) -> Date? {
        awakeUntil.flatMap { $0 > date ? $0 : nil }
    }
}

/// What the app is doing that keeping awake depends on.
nonisolated struct KeepAwakeActivity: Hashable, Sendable {
    /// Tasks with a turn in flight.
    var workingAgents = 0
}
