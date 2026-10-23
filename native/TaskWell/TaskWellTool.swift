import NativeCommands

enum TaskWellTool: CaseIterable, Identifiable {
    case changes, terminal, dev, subagents, pullRequest

    var id: Self { self }
    var title: String {
        switch self {
        case .changes: "Changes"
        case .terminal: "Terminal"
        case .dev: "Dev"
        case .subagents: "Subagents"
        case .pullRequest: "Pull request"
        }
    }
    var symbol: String {
        switch self {
        case .changes: "plus.forwardslash.minus"
        case .terminal: "terminal"
        case .dev: "play"
        case .subagents: "person.2"
        case .pullRequest: "arrow.triangle.pull"
        }
    }
    var command: CommandID {
        switch self {
        case .changes: .sessionToolChanges
        case .terminal: "taskWell.terminal"
        case .dev: "taskWell.dev"
        case .subagents: "taskWell.subagents"
        case .pullRequest: "taskWell.pullRequest"
        }
    }
}
