extension ConfigOption.SelectOption {
    /// The moment a known permission mode asks, rather than the adapter's technical mode name.
    /// Unknown modes keep their own words; a new adapter must never inherit guessed permissions.
    public var askingTitle: String {
        if let mode = TaskPermissionMode(rawValue: value) { return mode.title }
        return switch value {
        case "read-only", "default": "Before any change"
        case "workspace-write": "Before leaving the worktree"
        case "acceptEdits": "Beyond allowed edits and commands"
        case "agent", "auto": "When something looks risky"
        case "agent-full-access", "bypassPermissions": "Never"
        case "dontAsk": "Refuse anything not already allowed"
        default: name
        }
    }
}

extension ConfigOption.SelectOption {
    /// What a known permission mode lets the agent do without asking, said as consequences, for the
    /// line under the levels. `workspace` names where it works freely (the task's branch); unknown
    /// modes keep the agent's own description.
    public func askingCaption(agentName: String, workspace: String?) -> String? {
        if let mode = TaskPermissionMode(rawValue: value) { return description ?? mode.summary }
        let place = workspace ?? "the project"
        return switch value {
        case "read-only": "Reads freely. Asks before editing a file or running a command."
        case "workspace-write": "Works freely in \(place). Asks for anything outside it, and for the network."
        case "agent": "Works freely. Asks only when an action looks risky."
        case "agent-full-access", "bypassPermissions": "Full access. Runs anything on this Mac without asking."
        case "default": "Reads freely. Asks before every edit and command."
        case "acceptEdits":
            "Edits files in \(place) and runs common file commands freely. Asks before anything else."
        case "auto": "\(agentName) judges each action and asks only when one looks risky."
        case "dontAsk": "Does only what’s already allowed and refuses the rest, without asking."
        default: descriptionWithoutName
        }
    }
}
