import ACP

/// What the transcript's own controls do on the session screen, answered by the tools that own
/// them: Changes answers the files-changed card's Review and Commit, Subagents a subagent's card.
struct SessionTranscriptActions {
    var turnChanges: TurnChangesActions?
    var openSubagent: ((SessionID) -> Void)?

    /// Every tool's answers, the first tool's winning where two answer the same control.
    static func merging(_ all: [Self]) -> Self {
        Self(
            turnChanges: all.lazy.compactMap(\.turnChanges).first,
            openSubagent: all.lazy.compactMap(\.openSubagent).first)
    }
}
