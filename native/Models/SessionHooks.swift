import ACP

/// Where a feature takes part in sessions without the models knowing it: the Modes feature fills
/// these in at launch (`ModesWiring`). Shared by every session, through `SessionServices`.
final class SessionHooks {
    /// The instructions to send ahead of a session's next prompt, given the ones its agent had last
    /// (`SessionState.deliveredPreamble`), or nil for none.
    var preamble: (SessionModel, PromptPreamble.Marker?) -> PromptPreamble? = { _, _ in nil }
    /// A task the user started, ready for its first prompt: on its own, or `continuing` an earlier
    /// conversation of the same task (`/clear`, or one restarted after a crash).
    var taskStarted: (_ session: SessionModel, _ continuing: SessionModel?) async -> Void = { _, _ in }

    /// What goes ahead of `prompt`. An agent's slash command has to lead its prompt, so the
    /// instructions wait for the next one.
    func preamble(for session: SessionModel, prompt: String) -> PromptPreamble? {
        guard !prompt.hasPrefix("/") else { return nil }
        return preamble(session, session.state.deliveredPreamble)
    }
}
