import Foundation
import NativeAutomation

/// Something that happened to an expedition: the user acting on it, or its crew reporting back.
public nonisolated enum TeamworkEvent: Codable, Hashable, Sendable {
    /// Begins: makes the base, then starts planning.
    case start
    case baseReady(URL)
    case baseFailed(String)
    case taskCreated(CrewSlot, task: UUID)
    /// A session couldn't be created, or its prompt couldn't be sent.
    case taskFailed(CrewSlot, message: String)
    /// A turn ended. `cost` is the session's running total.
    case turnEnded(CrewSlot, outcome: TurnOutcome, reply: String?, cost: Double?)
    case pullRequestOpened(WorkflowPullRequestResult)
    case pullRequestFailed(String)
    /// Native put back a protected file an agent changed.
    case documentRestored(String)

    // The user, on the route.
    /// Approves the route as the user edited it.
    case approve(Route)
    /// Sends the route back to the lead with the user's note.
    case requestChanges(String)
    /// Turns the route down, which stops the expedition.
    case discard

    // The user, on the expedition.
    case pause
    case resume
    case stop
    /// Grants the budget again on top of what's spent.
    case extendBudget
    /// Skips the work that hasn't started and goes straight to the debrief.
    case wrapUp
    /// Sends the user's message to the lead.
    case messageLead(String)
    /// Opens the pull request again after it failed.
    case retryPullRequest
    /// Finishes without the pull request that failed to open.
    case finishWithoutPullRequest
    /// Applies the lead's revision of the legs ahead that waits for the user.
    case approveRouteChange
    /// Turns that revision down; the approved route stands.
    case keepRoute

    // The user, on one assignment or checkpoint.
    case message(CrewSlot, text: String)
    case retry(CrewSlot)
    case resumeSlot(CrewSlot)
    case skip(CrewSlot)
    /// Takes an assignment's latest reply as its report, or passes a checkpoint as it stands.
    case accept(CrewSlot)
    case stopSlot(CrewSlot)
    /// Moves an assignment that isn't running to another agent.
    case reassign(String, agent: WorkflowAgent)
    /// Grants a failing checkpoint one more round of fixes.
    case anotherRound(String)
    /// When the provider limit that stopped a seat resets, as the Usage feature knows it.
    case limitResets(CrewSlot, at: Date)
    /// That limit has reset: the seat picks back up.
    case limitReset(CrewSlot)
}
