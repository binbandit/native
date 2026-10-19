import Exec
import Foundation

/// How one script went.
public struct TaskScriptResult: Hashable, Sendable {
    public enum Outcome: Hashable, Sendable {
        case succeeded
        case failed(exitCode: Int32)
        /// Stopped for running longer than its event allows, with everything it started.
        case timedOut(after: Duration)
        /// Stopped by the user, or because Native no longer needed it.
        case cancelled
        /// It couldn't start: its folder is gone, or the shell or interpreter isn't there.
        case couldNotStart(String)
    }

    public var outcome: Outcome
    public var duration: Duration

    public init(outcome: Outcome, duration: Duration) {
        self.outcome = outcome
        self.duration = duration
    }

    public var succeeded: Bool { outcome == .succeeded }
}

/// A script that ran, and how it went.
public struct TaskScriptReport: Hashable, Sendable {
    public var script: TaskScript
    public var result: TaskScriptResult

    public init(script: TaskScript, result: TaskScriptResult) {
        self.script = script
        self.result = result
    }
}

/// Runs task scripts on the machine the project is on, through that machine's command runner.
public struct TaskScriptRunner: Sendable {
    private let runner: any CommandRunner
    /// The login shell's environment, which every script starts from.
    private let environment: [String: String]

    public init(runner: any CommandRunner, environment: [String: String]) {
        self.runner = runner
        self.environment = environment
    }

    /// Runs the plan's scripts one after another in the context's folder, stopping at the first that
    /// doesn't succeed, and reports how each that ran went. The plan's timeout covers all of them.
    /// `onStart` hears as each begins, and `onOutput` gets its output as it arrives. Cancelling the
    /// task stops the running script and everything it started.
    public func run(
        _ plan: TaskScriptPlan, context: TaskScriptContext,
        onStart: @escaping @Sendable (TaskScript) -> Void = { _ in },
        onOutput: @escaping @Sendable (Data) -> Void
    ) async -> [TaskScriptReport] {
        let clock = ContinuousClock()
        let deadline = clock.now + plan.timeout
        var reports: [TaskScriptReport] = []
        for script in plan.scripts {
            let remaining = deadline - clock.now
            guard remaining > .zero else {
                let result = TaskScriptResult(outcome: .timedOut(after: plan.timeout), duration: .zero)
                reports.append(TaskScriptReport(script: script, result: result))
                break
            }
            guard !Task.isCancelled else {
                reports.append(TaskScriptReport(script: script, result: .init(outcome: .cancelled, duration: .zero)))
                break
            }
            onStart(script)
            let result = await run(
                script, context: context, timeout: remaining, reportedTimeout: plan.timeout, onOutput: onOutput)
            reports.append(TaskScriptReport(script: script, result: result))
            guard result.succeeded else { break }
        }
        return reports
    }

    private func run(
        _ script: TaskScript, context: TaskScriptContext, timeout: Duration, reportedTimeout: Duration,
        onOutput: @escaping @Sendable (Data) -> Void
    ) async -> TaskScriptResult {
        let clock = ContinuousClock()
        let start = clock.now
        let command = script.command(
            in: context.worktreePath, environment: environment.merging(context.environment) { $1 }, timeout: timeout)
        let outcome: TaskScriptResult.Outcome
        do {
            let result = try await runner.run(command) { onOutput($0.data) }
            outcome = result.exitCode == 0 ? .succeeded : .failed(exitCode: result.exitCode)
        } catch CommandError.timedOut {
            outcome = .timedOut(after: reportedTimeout)
        } catch is CancellationError {
            outcome = .cancelled
        } catch {
            outcome = .couldNotStart(error.localizedDescription)
        }
        return TaskScriptResult(outcome: outcome, duration: clock.now - start)
    }
}
