/// When Native keeps the Mac awake: never, while agents work, or always.
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

    /// For the status bar, where space is short.
    var shortTitle: String {
        switch self {
        case .off: "Off"
        case .whileAgentsWork: "Agents"
        case .on: "On"
        }
    }

    /// The description under each choice.
    var explanation: String {
        switch self {
        case .off: "Your Mac sleeps on its usual schedule"
        case .whileAgentsWork: "Awake whenever agents have work running"
        case .on: "Awake all the time, agents or not"
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
