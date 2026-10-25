import SessionTools

/// Stable IDs used by saved tool arrangements.
extension SessionToolID {
    static let changes: Self = "changes"
    static let terminal: Self = "terminal"
    static let dev: Self = "dev"
    static let subagents: Self = "subagents"
    static let pullRequest: Self = "pullRequest"
}

/// Where each built-in tool can live. Changes is the only one with a pane of its own; the others
/// open the shared workbench, the subagent inspector or the pull request.
extension SessionToolSpec {
    static let changes = SessionToolSpec(id: .changes, places: [.side, .fact, .off], defaultPlace: .side)
    static let terminal = SessionToolSpec(id: .terminal, places: [.workbench, .off], defaultPlace: .workbench)
    static let dev = SessionToolSpec(id: .dev, places: [.workbench, .off], defaultPlace: .workbench)
    static let subagents = SessionToolSpec(id: .subagents, places: [.side, .off], defaultPlace: .side)
    static let pullRequest = SessionToolSpec(id: .pullRequest, places: [.fact, .off], defaultPlace: .fact)
}
