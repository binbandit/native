import Foundation
import ProjectActions
import Terminal

/// An action running, or run, in the background: no terminal, a toast when it ends, and its output
/// kept to show on request.
struct ProjectActionBackgroundRun {
    let id = UUID()
    let action: ProjectAction
    /// Where it ran, for the output sheet.
    let directory: URL
    let startedAt: Date
    var isStopping = false
    var result: Result?
    /// The run itself; cancelling it ends the command.
    var task: Task<Void, Never>?

    enum Result: Equatable {
        case finished(TerminalJob.Outcome, output: String)
        /// It never ran: the shell or the folder isn't there.
        case failedToStart(String)
    }

    var state: ProjectActionRunState {
        switch result {
        case nil: .running(since: startedAt, isStopping: isStopping)
        case .finished(let outcome, _)?: .finished(outcome)
        case .failedToStart(let reason)?: .couldNotStart(reason)
        }
    }

    /// The most output kept: the end, where failures usually are.
    nonisolated static let outputLimit = 200_000

    nonisolated static func trimmed(_ output: String) -> String {
        output.count > outputLimit ? "…" + output.suffix(outputLimit) : output
    }
}
