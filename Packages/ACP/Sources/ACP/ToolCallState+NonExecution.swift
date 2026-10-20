/// Why a call ended without running to completion, when its agent says. Claude Code puts it in the
/// failed call's `_meta.claudeCode.nonExecutionKind` (claude-agent-acp 0.93.0, live only; replayed
/// history leaves it out): `interrupted` or `cancelled` when a stop cut its run short, `user-rejected`
/// when the user refused it, and `permission-rule` or `automode-…` when a rule or auto mode did.
/// Since Claude Code 2.1.293 a command that the user's stop killed is `user-rejected` too, which the
/// reducer settles once the turn ends stopped. Codex doesn't say: codex-acp 2.2.2 reports declined
/// and interrupted calls as plain `failed`.
extension ToolCallState {
    /// The user, a permission rule or auto mode refused the call, so it never ran.
    public var wasRefused: Bool {
        guard status == .failed, let kind = nonExecutionKind else { return false }
        return kind == "user-rejected" || kind == "permission-rule" || kind.hasPrefix("automode")
    }

    /// A stop cut the call's run short.
    var wasCutShort: Bool {
        nonExecutionKind == "interrupted" || nonExecutionKind == "cancelled"
    }

    var nonExecutionKind: String? {
        meta?["claudeCode"]?["nonExecutionKind"]?.stringValue
    }
}
