import Foundation
import TaskScripts
import Terminal

/// Projects use the same runner, policy and timeout as other scripts. Their after-commands reuse
/// terminal job status and tabs, with captured output so they also work without a terminal engine.
enum TaskScriptsTerminalWiring {
    static func connect(_ center: TaskScriptCenter, model: AppModel, terminals: TerminalStore) {
        var attempts: [UUID: Int] = [:]
        center.runUpdated = { [weak center, weak model, weak terminals] run in
            guard run.event == .afterWorktree, let center, let model, let terminals,
                let session = model.sessions.open(in: run.folder).first(where: { $0.root === $0 })
            else { return }
            let panel = terminals.panel(for: session)
            let key = "task-script.\(run.id)"
            let log: TerminalLog
            if let existing = panel.logs.values.first(where: { $0.job.key == key }) {
                log = existing
                if attempts[run.id] != run.attempt { panel.isVisible = true }
            } else {
                // A closed tab releases its captured output. Progress from that attempt must not
                // reopen it, but Retry can attach a fresh log for the new attempt.
                guard attempts[run.id] != run.attempt else { return }
                log = TerminalLog(job: job(for: run))
                log.retry = { [weak center, weak run] in
                    guard let run else { return }
                    center?.retry(run)
                }
                log.stop = { [weak center, weak run] in
                    guard let run else { return }
                    center?.stop(run)
                }
                panel.attach(log)
            }
            attempts[run.id] = run.attempt
            log.job = job(for: run)
            log.output = (run.output.droppedBytes > 0 ? "Earlier output omitted.\n" : "") + run.output.text
            log.detail = run.failure.map { TaskScriptFailureText.detail($0, ofRun: run) }
            log.changed()
        }
    }

    private static func job(for run: TaskScriptRun) -> TerminalJob {
        var job = TerminalJob(
            key: "task-script.\(run.id)", name: run.event.title,
            command: run.plan.scripts.map(\.text).joined(separator: "\n"), startedAt: run.startedAt)
        if run.isRunning { return job }
        let status: Int32
        switch run.state {
        case .failed(let report):
            switch report.result.outcome {
            case .failed(let code): status = code
            case .cancelled:
                job.isStopping = true
                status = 130
            case .timedOut: status = 124
            default: status = 1
            }
        case .skipped:
            let cancelled = run.reports.last?.result.outcome == .cancelled
            job.isStopping = cancelled
            job.finish(status: cancelled ? 130 : nil, duration: .seconds(run.duration ?? 0))
            return job
        case .succeeded: status = 0
        case .awaitingApproval, .running: return job
        }
        job.finish(status: status, duration: .seconds(run.duration ?? 0))
        return job
    }
}
