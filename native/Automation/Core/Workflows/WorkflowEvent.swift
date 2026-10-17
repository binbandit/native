import Foundation

/// Something that happened to a run: the user acting on it, or its tasks reporting back.
nonisolated enum WorkflowEvent: Hashable, Sendable {
    case start
    /// The host created the step's task session.
    case taskCreated(step: String, task: UUID)
    /// The step's task couldn't be created, or its prompt couldn't be sent.
    case taskFailed(step: String, message: String)
    /// A turn of the step's task ended. `cost` is the session's running total.
    case turnEnded(step: String, outcome: TurnOutcome, reply: String?, cost: Double?)
    case pullRequestOpened(step: String, WorkflowPullRequestResult)
    case pullRequestFailed(step: String, message: String)

    /// Lets a gated step run, with the user's edits to its prompt if they made any.
    case approve(step: String, prompt: String?)
    /// Turns a gate down, which stops the run: the steps after it were built on this one.
    case reject(step: String)
    /// Leaves a step out; the steps after it run without its output.
    case skip(step: String)
    /// Runs a stopped step again from scratch, in a fresh task.
    case retry(step: String)
    /// Picks a stopped step back up in its task, granting a spent goal budget again.
    case resume(step: String)
    /// Answers a step that's blocked or stopped, in its task.
    case reply(step: String, text: String)
    /// Takes a stopped step's latest reply as its output and moves on.
    case accept(step: String)
    /// Stops a step's running turn.
    case stop(step: String)
    /// Holds the run: turns in flight finish, but nothing new goes out until it resumes.
    case pauseRun
    case resumeRun
    /// Stops the whole run.
    case cancel
}
