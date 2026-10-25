import ACP

extension GitChangesReview {
    /// Only the task's captured edits are attributable to it. Reading the working tree here would
    /// pick up later edits by other tasks and allocate arbitrary blobs just to open Settings.
    static func previewDiffs(of session: SessionModel) -> [FileDiff] {
        guard session.phase != .prompting, !session.isRestoringHistory,
            let turn = session.state.turns.last, !turn.isLateOutput
        else { return [] }
        var diffs: [FileDiff] = []
        for item in session.state.items[turn.items].reversed() {
            guard case .toolCall(let call) = item, call.status == .completed else { continue }
            for content in call.content {
                if case .diff(let diff) = content {
                    diffs.append(diff)
                    if diffs.count == 12 { return diffs }
                }
            }
        }
        return diffs
    }
}
