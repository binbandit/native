import NativeHostProtocol

// What the keep-awake choices are called wherever they're offered.

extension KeepAwakeMode {
    var title: String {
        switch self {
        case .off, .unknown: "Off"
        case .whileAgentsWork: "While Agents Work"
        case .on: "On"
        }
    }

    /// For the status bar, where space is short.
    var shortTitle: String {
        switch self {
        case .off, .unknown: "Off"
        case .whileAgentsWork: "Agents"
        case .on: "On"
        }
    }

    /// The description under each choice.
    var explanation: String {
        switch self {
        case .off, .unknown: "Your Mac sleeps on its usual schedule"
        case .whileAgentsWork: "Awake whenever agents have work running"
        case .on: "Awake all the time, agents or not"
        }
    }
}

extension KeepAwakeBatteryRule {
    var title: String {
        switch self {
        case .keepAwake: "Keep awake"
        case .stopWhenLow, .unknown: "Stop below 10%"
        case .pluggedInOnly: "Don't keep awake"
        }
    }
}
