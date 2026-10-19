import ACP

/// What the agent may do without asking at a permission mode, in plain words. Native knows the
/// modes the bundled adapters offer (by their wire values, never by agent); any other mode reads as
/// the agent describes it.
enum AutonomySummary {
    static func summary(of choice: SelectSetting.Choice) -> String? {
        known[choice.value] ?? choice.description
    }

    /// The plain words for Plan Mode, which suspends the level while it's on.
    static let planMode = "Plans first and changes nothing until you approve the plan"

    private static let known: [String: String] = [
        // Codex
        "read-only": "Looks around, never changes anything without asking",
        "workspace-write": "Edits files in the project, asks before anything outside it",
        "agent": "Does most things, asks only when something looks risky",
        "agent-full-access": "Does everything without asking, anywhere on this Mac",
        // Claude Code
        "default": "Asks before edits and commands",
        "acceptEdits": "Edits files, asks before commands",
        "auto": "Decides for itself, asks only when something looks risky",
        "dontAsk": "Never asks: does only what’s already allowed, refuses the rest",
        "bypassPermissions": "Does everything without asking",
    ]
}
