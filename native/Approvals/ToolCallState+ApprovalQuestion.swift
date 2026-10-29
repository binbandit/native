import ACP
import ApprovalAnalysis

extension ToolCallState {
    /// The ask in a line, for rows and Home's queue. An irreversible command names what it would do
    /// ("Overwrite `main` on origin?"), so it never reads like the routine ask for the same program.
    func approvalQuestion(
        workingDirectory: String, pushPlace: String? = nil, pushBranch: String? = nil,
        knowledge: CommandKnowledge = .bundled
    ) -> String {
        guard kind != .switchMode, let command = shellCommand else { return askSummary }
        let analysis = ApprovalCommand(
            command: command, workingDirectory: rawInput?["cwd"]?.stringValue ?? workingDirectory,
            worktreeDirectory: workingDirectory, knowledge: knowledge)
        guard analysis.risk == .irreversible else { return askSummary }
        let phrase =
            analysis.pushTarget?.headline(place: pushPlace, destination: pushBranch, marking: { "`\($0)`" })
            ?? analysis.action
        return phrase.prefix(1).uppercased() + phrase.dropFirst() + "?"
    }
}
