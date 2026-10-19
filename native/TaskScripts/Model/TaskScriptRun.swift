import Foundation
import Observation
import TaskScripts

/// One event's scripts running in one folder: a task's setup, a finished turn, a teardown, or a test
/// from Settings. Its output fills in as it arrives.
@Observable
final class TaskScriptRun: Identifiable {
    enum State: Equatable {
        /// The repository's script waits for the user to allow the project's repository scripts.
        /// Only setup asks; other events run without it.
        case awaitingApproval
        case running
        case succeeded
        /// The first script that didn't succeed, and how.
        case failed(TaskScriptReport)
        /// The user went on without it.
        case skipped
    }

    let id = UUID()
    let event: TaskScriptEvent
    /// Where it runs: the task's worktree, or the project's folder.
    var folder: URL
    /// The project's main checkout.
    var projectRoot: URL
    var context: TaskScriptContext
    var plan: TaskScriptPlan
    var state: State
    /// The script running now.
    var current: TaskScript?
    var output = TaskScriptOutput()
    var reports: [TaskScriptReport] = []
    var startedAt = Date.now
    var finishedAt: Date?
    /// What Native did before the scripts, for setup: the env files it copied.
    var copiedFiles: [String] = []
    /// Why copying the env files failed, for setup.
    var copyFailure: String?
    /// The user put its result away.
    var isDismissed = false
    /// A test from Settings rather than one of a task's own runs.
    let isTest: Bool

    @ObservationIgnored var work: Task<Void, Never>?
    /// Counts starts, so a run that was stopped and started again ignores the stopped one's end.
    @ObservationIgnored var attempt = 0

    init(
        event: TaskScriptEvent, folder: URL, projectRoot: URL, context: TaskScriptContext, plan: TaskScriptPlan,
        state: State, isTest: Bool = false
    ) {
        self.event = event
        self.folder = folder
        self.projectRoot = projectRoot
        self.context = context
        self.plan = plan
        self.state = state
        self.isTest = isTest
    }

    var isRunning: Bool { state == .running }

    var isFailure: Bool {
        if case .failed = state { true } else { false }
    }

    /// The report of the script that failed, if one did.
    var failure: TaskScriptReport? {
        if case .failed(let report) = state { report } else { nil }
    }

    /// Whether the task it holds can go on: setup that worked or was skipped.
    var releasesTask: Bool {
        state == .succeeded || state == .skipped
    }

    /// How long it ran, once it's done.
    var duration: TimeInterval? {
        finishedAt.map { $0.timeIntervalSince(startedAt) }
    }
}
