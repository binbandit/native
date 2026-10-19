import ACP

/// What the agent may do without asking at a permission mode, in plain words, shown under the mode's
/// name, so never restating it. Native has its own words for the modes the bundled adapters offer
/// (by their wire values, never by agent); any other mode reads as the agent describes it, less a
/// leading "<name>:".
enum AutonomySummary {
    static func summary(of choice: SelectSetting.Choice) -> String? {
        known[choice.value] ?? choice.descriptionWithoutName
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
        "dontAsk": "Does only what’s already allowed and refuses the rest, without asking",
        "bypassPermissions": "Does everything without asking",
    ]
}
