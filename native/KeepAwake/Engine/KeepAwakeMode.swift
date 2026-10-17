/// When Native keeps the Mac awake (the reference app's "Keep computer awake": On, Agent, Off).
nonisolated enum KeepAwakeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case whileAgentsWork
    case on

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .whileAgentsWork: "While Agents Work"
        case .on: "On"
        }
    }

    /// For the status bar, where the reference app shows "On", "Agent" or "Off".
    var shortTitle: String {
        switch self {
        case .off: "Off"
        case .whileAgentsWork: "Agents"
        case .on: "On"
        }
    }

    /// the reference app's descriptions under each choice.
    var explanation: String {
        switch self {
        case .off: "Allow normal system sleep"
        case .whileAgentsWork: "Stay awake while an agent is working"
        case .on: "Keep this Mac awake continuously"
        }
    }

    /// The next mode for the cycling shortcut: Off, While Agents Work, On, and around.
    var next: KeepAwakeMode {
        switch self {
        case .off: .whileAgentsWork
        case .whileAgentsWork: .on
        case .on: .off
        }
    }
}
