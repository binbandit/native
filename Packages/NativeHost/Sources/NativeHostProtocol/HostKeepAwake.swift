import Foundation

// Keeping the host's machine awake (docs/durability.md, "Sleep"). The policy is the user's Keep Mac
// Awake setting; the host holds the power assertions, since it's the process the agents keep busy,
// and it keeps doing so after the app quits. Its state is part of `HostStatus`.

extension HostProtocol.Method {
    /// `{policy}` → `HostKeepAwakeState`. The owner, and paired devices that may manage the host.
    public static let setKeepAwake = "_native/host/keep_awake/set"
}

/// When the machine is kept awake: never, while agents work, or always.
public enum KeepAwakeMode: String, WireEnum, Identifiable {
    case off
    case whileAgentsWork
    case on
    /// From a newer client; treated as `off`.
    case unknown

    /// What a user can pick, in order.
    public static let choices: [KeepAwakeMode] = [.off, .whileAgentsWork, .on]

    public var id: String { rawValue }

    /// The next mode for the cycling shortcut: Off, While Agents Work, On, and around.
    public var next: KeepAwakeMode {
        switch self {
        case .off, .unknown: .whileAgentsWork
        case .whileAgentsWork: .on
        case .on: .off
        }
    }
}

/// What keeping awake does on battery power. Stopping below 10% is the default, so a forgotten
/// keep-awake never drains the battery flat.
public enum KeepAwakeBatteryRule: String, WireEnum, Identifiable {
    case keepAwake
    case stopWhenLow
    case pluggedInOnly
    /// From a newer client; treated as `stopWhenLow`.
    case unknown

    public static let choices: [KeepAwakeBatteryRule] = [.keepAwake, .stopWhenLow, .pluggedInOnly]

    /// Below this share of charge, `stopWhenLow` lets the machine sleep.
    public static let lowBattery = 0.1

    public var id: String { rawValue }
}

/// The power assertions keeping awake takes, the same ones `caffeinate` takes for its flags.
public enum PowerAssertionKind: String, WireEnum {
    /// `caffeinate -i`: no idle sleep, on battery too. The display may still sleep.
    case preventIdleSleep
    /// `caffeinate -s`: no system sleep at all while on power. macOS ignores it on battery, and
    /// closing a laptop's lid still sleeps it.
    case preventSystemSleep
    /// `caffeinate -d`: the display stays on.
    case preventDisplaySleep
    case unknown
}

/// Everything the user chose about keeping the machine awake. Plain data, so a client hands it to
/// its host as is.
public struct KeepAwakePolicy: Codable, Hashable, Sendable {
    public var mode = KeepAwakeMode.off
    /// Stay awake until then whatever the mode, then go back to it ("Stay awake for 2 hours").
    public var awakeUntil: Date?
    /// Also keep the display from dimming and sleeping (`caffeinate -d`), not just the system.
    public var keepsDisplayOn = false
    public var battery = KeepAwakeBatteryRule.stopWhenLow

    public init(
        mode: KeepAwakeMode = .off, awakeUntil: Date? = nil, keepsDisplayOn: Bool = false,
        battery: KeepAwakeBatteryRule = .stopWhenLow
    ) {
        self.mode = mode
        self.awakeUntil = awakeUntil
        self.keepsDisplayOn = keepsDisplayOn
        self.battery = battery
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(KeepAwakeMode.self, forKey: .mode) ?? .off
        awakeUntil = try container.decodeIfPresent(Date.self, forKey: .awakeUntil)
        keepsDisplayOn = try container.decodeIfPresent(Bool.self, forKey: .keepsDisplayOn) ?? false
        battery = try container.decodeIfPresent(KeepAwakeBatteryRule.self, forKey: .battery) ?? .stopWhenLow
    }

    /// The timer, if it's still running at `date`.
    public func timer(at date: Date) -> Date? {
        awakeUntil.flatMap { $0 > date ? $0 : nil }
    }
}

/// Whether the machine runs on battery, and how charged it is.
public struct PowerState: Codable, Hashable, Sendable {
    public var isOnBattery = false
    /// 0...1, or nil for machines without a battery.
    public var batteryLevel: Double?

    public init(isOnBattery: Bool = false, batteryLevel: Double? = nil) {
        self.isOnBattery = isOnBattery
        self.batteryLevel = batteryLevel
    }
}

/// What keeping awake is doing and why, decided from the policy, how many agents work and the
/// power state. Pure, so every combination can be tested, and the app and the host decide alike.
public struct KeepAwakeStatus: Codable, Hashable, Sendable {
    public enum Reason: String, WireEnum {
        /// The mode is Off and no timer runs.
        case off
        /// While Agents Work, and none is working.
        case waitingForAgents
        case agentsWorking
        case alwaysOn
        case timer
        /// Would keep awake, but the battery rule says not on battery.
        case pausedOnBattery
        /// Would keep awake, but the battery is below `KeepAwakeBatteryRule.lowBattery`.
        case pausedLowBattery
        case unknown
    }

    public var reason: Reason
    /// How many agents work, for `agentsWorking`.
    public var workingAgents: Int
    /// When the timer ends, for `timer`.
    public var until: Date?
    /// The assertions this status calls for (what's actually held may fall short).
    public var assertions: Set<PowerAssertionKind>

    public init(
        reason: Reason, workingAgents: Int = 0, until: Date? = nil, assertions: Set<PowerAssertionKind> = []
    ) {
        self.reason = reason
        self.workingAgents = workingAgents
        self.until = until
        self.assertions = assertions
    }

    public var isActive: Bool {
        !assertions.isEmpty
    }

    public static let off = KeepAwakeStatus(reason: .off)

    public static func evaluate(
        _ policy: KeepAwakePolicy, workingAgents: Int, power: PowerState, now: Date
    ) -> KeepAwakeStatus {
        var wanted: KeepAwakeStatus
        if let until = policy.timer(at: now) {
            wanted = KeepAwakeStatus(reason: .timer, until: until)
        } else {
            switch policy.mode {
            case .off, .unknown: return .off
            case .on: wanted = KeepAwakeStatus(reason: .alwaysOn)
            case .whileAgentsWork:
                guard workingAgents > 0 else { return KeepAwakeStatus(reason: .waitingForAgents) }
                wanted = KeepAwakeStatus(reason: .agentsWorking, workingAgents: workingAgents)
            }
        }
        if power.isOnBattery {
            switch policy.battery {
            case .keepAwake:
                break
            case .pluggedInOnly:
                return KeepAwakeStatus(reason: .pausedOnBattery)
            case .stopWhenLow, .unknown:
                if let level = power.batteryLevel, level < KeepAwakeBatteryRule.lowBattery {
                    return KeepAwakeStatus(reason: .pausedLowBattery)
                }
            }
        }
        // As `caffeinate -i -s` does: no idle sleep anywhere, no system sleep on power. The display
        // sleeps as usual unless the user asked otherwise.
        wanted.assertions = [.preventIdleSleep, .preventSystemSleep]
        if policy.keepsDisplayOn {
            wanted.assertions.insert(.preventDisplaySleep)
        }
        return wanted
    }
}

/// A host's keep-awake: the policy it follows, what that comes to now, and what it actually holds.
public struct HostKeepAwakeState: Codable, Hashable, Sendable {
    public var policy: KeepAwakePolicy
    public var status: KeepAwakeStatus
    /// The assertions held right now; short of `status.assertions` when the system refused one.
    public var held: Set<PowerAssertionKind>
    /// Whether this host can hold assertions at all (a host on a platform without a backend can't).
    public var isSupported: Bool

    public init(
        policy: KeepAwakePolicy, status: KeepAwakeStatus, held: Set<PowerAssertionKind>, isSupported: Bool = true
    ) {
        self.policy = policy
        self.status = status
        self.held = held
        self.isSupported = isSupported
    }
}

public struct SetKeepAwakeParams: Codable, Sendable {
    public var policy: KeepAwakePolicy

    public init(policy: KeepAwakePolicy) {
        self.policy = policy
    }
}
