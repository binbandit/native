import Foundation

/// What keeping awake is doing and why, decided from the policy, the app's activity and the power
/// state. Pure, so every combination can be tested.
nonisolated struct KeepAwakeStatus: Hashable, Sendable {
    enum Reason: Hashable, Sendable {
        /// The mode is Off and no timer runs.
        case off
        /// While Agents Work, and none is working.
        case waitingForAgents
        case agentsWorking(Int)
        case alwaysOn
        case timer(until: Date)
        /// Would keep awake, but the battery rule says not on battery.
        case pausedOnBattery
        /// Would keep awake, but the battery is below `KeepAwakeBatteryRule.lowBattery`.
        case pausedLowBattery
    }

    var reason: Reason
    /// The assertions this status calls for (what's actually held may fall short).
    var assertions: Set<PowerAssertionKind>

    var isActive: Bool {
        !assertions.isEmpty
    }

    static let off = KeepAwakeStatus(reason: .off, assertions: [])

    static func evaluate(_ policy: KeepAwakePolicy, activity: KeepAwakeActivity, power: PowerState, now: Date) -> KeepAwakeStatus {
        let wanted: Reason
        if let until = policy.timer(at: now) {
            wanted = .timer(until: until)
        } else {
            switch policy.mode {
            case .off: return .off
            case .on: wanted = .alwaysOn
            case .whileAgentsWork:
                guard activity.workingAgents > 0 else { return KeepAwakeStatus(reason: .waitingForAgents, assertions: []) }
                wanted = .agentsWorking(activity.workingAgents)
            }
        }
        if power.isOnBattery {
            switch policy.battery {
            case .keepAwake:
                break
            case .pluggedInOnly:
                return KeepAwakeStatus(reason: .pausedOnBattery, assertions: [])
            case .stopWhenLow:
                if let level = power.batteryLevel, level < KeepAwakeBatteryRule.lowBattery {
                    return KeepAwakeStatus(reason: .pausedLowBattery, assertions: [])
                }
            }
        }
        // the reference app takes `caffeinate -i -s`: idle sleep everywhere, system sleep on power.
        var assertions: Set<PowerAssertionKind> = [.preventIdleSleep, .preventSystemSleep]
        if policy.keepsDisplayOn {
            assertions.insert(.preventDisplaySleep)
        }
        return KeepAwakeStatus(reason: wanted, assertions: assertions)
    }
}
