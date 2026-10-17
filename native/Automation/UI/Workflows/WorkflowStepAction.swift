import Foundation
import NativeAutomation

/// What the user can do with a step in its current state. Every stopped step offers a way on, so a
/// run never strands the user: retry or resume it, take what it has, skip it, or stop the run.
enum WorkflowStepAction: Hashable, Identifiable {
    case stop
    case retry
    case resume(title: String)
    case accept
    case skip
    case stopWorkflow

    var id: String { title }

    var title: String {
        switch self {
        case .stop: "Stop Step"
        case .retry: "Retry"
        case .resume(let title): title
        case .accept: "Use Reply"
        case .skip: "Skip"
        case .stopWorkflow: "Stop Workflow"
        }
    }

    var systemImage: String {
        switch self {
        case .stop: "stop.fill"
        case .retry: "arrow.counterclockwise"
        case .resume: "play.fill"
        case .accept: "checkmark"
        case .skip: "forward.end"
        case .stopWorkflow: "xmark"
        }
    }

    var help: String {
        switch self {
        case .stop: "Stop this step's turn. The rest of the workflow waits."
        case .retry: "Run this step again from the start, in a new session"
        case .resume: "Continue this step in its session"
        case .accept: "Take the step's latest reply as its result and move on"
        case .skip: "Leave this step out; the steps after it run without its result"
        case .stopWorkflow: "Stop the whole workflow"
        }
    }

    func event(for step: String) -> WorkflowEvent {
        switch self {
        case .stop: .stop(step: step)
        case .retry: .retry(step: step)
        case .resume: .resume(step: step)
        case .accept: .accept(step: step)
        case .skip: .skip(step: step)
        case .stopWorkflow: .cancel
        }
    }

    /// The step's main way on, then the rest.
    static func available(for step: WorkflowStepRun, isRunCancelled: Bool) -> (primary: WorkflowStepAction?, others: [WorkflowStepAction]) {
        guard !isRunCancelled else { return (nil, []) }
        let hasTask = step.task != nil
        let hasReply = step.latestReply?.isEmpty == false
        switch step.status {
        case .waiting, .paused:
            return (nil, [.skip])
        case .awaitingApproval, .succeeded, .skipped:
            return (nil, [])
        case .starting, .running:
            return (nil, [.stop])
        case .blocked:
            return (nil, [.resume(title: "Continue Without Answering")] + (hasReply ? [.accept] : []) + [.skip])
        case .limited:
            let resume = WorkflowStepAction.resume(title: step.goal.map { $0.goal.exhaustedBudget(at: .now, iterationCeiling: GoalLoop.safetyIterationCeiling) != nil } == true ? "Extend Budget" : "Resume")
            return (hasTask ? resume : .retry, (hasReply ? [.accept] : []) + [.skip])
        case .failed:
            return (.retry, (hasTask ? [.resume(title: "Continue in Session")] : []) + [.skip, .stopWorkflow])
        case .interrupted:
            return (hasTask ? .resume(title: "Resume") : .retry, [.skip, .stopWorkflow])
        case .cancelled:
            return (hasTask ? .resume(title: "Resume") : .retry, (hasTask ? [.retry] : []) + (hasReply ? [.accept] : []) + [.skip])
        }
    }
}
