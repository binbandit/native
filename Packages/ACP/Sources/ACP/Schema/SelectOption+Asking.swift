extension ConfigOption.SelectOption {
    /// The moment a known permission mode asks, rather than the adapter's technical mode name.
    /// Unknown modes keep their own words; a new adapter must never inherit guessed permissions.
    public var askingTitle: String {
        switch value {
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
