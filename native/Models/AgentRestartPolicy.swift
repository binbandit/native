import Foundation

/// How often Native restarts an agent that stopped on its own: right away, unless it has already
/// crashed a few times in the last few minutes, when restarting would only loop.
nonisolated struct AgentRestartPolicy: Equatable, Sendable {
    static let limit = 3
    static let window: TimeInterval = 5 * 60

    private var restarts: [Date] = []

    /// Whether to restart after a crash at `now`; records the restart when it says yes.
    mutating func allowsRestart(at now: Date = .now) -> Bool {
        restarts.removeAll { now.timeIntervalSince($0) > Self.window }
        guard restarts.count < Self.limit else { return false }
        restarts.append(now)
        return true
    }
}
