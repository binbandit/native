import Exec
import Foundation
import Observation
import ProjectActions
import Terminal

/// Runs project actions: in a terminal tab named after the action, in the task's worktree, or in
/// the background, with a toast when it ends. Every surface (the header's Run menu, the palette,
/// the menu bar, the project's menu) runs actions through here.
@MainActor
@Observable
final class ProjectActionRunner {
    let store: ProjectActionStore
    private(set) var backgroundRuns: [ProjectActionRunKey: ProjectActionBackgroundRun] = [:]
    /// The latest run that ended where the user couldn't see it.
    var toast: ProjectActionToast?
    /// A repo action waiting for the user to allow the repo's commands.
    var pendingRun: ProjectActionPendingRun?
    /// The background run whose output is open.
    var shownOutput: ProjectActionRunKey?

    /// What the runner needs from the rest of the app, set by `ProjectActionsWiring`.
    struct Hooks {
        /// The login-shell environment background runs start from.
        var environment: () async -> [String: String] = { ProcessInfo.processInfo.environment }
        var commandRunner: (any CommandRunner)?
        /// Whether the user lets the project's repo supply commands (the repo scripts switch).
        var allowsRepository: (URL) -> Bool = { _ in false }
        var allowRepository: (URL) -> Void = { _ in }
        /// The task in view, if it has a model.
        var visibleSession: () -> SessionModel? = { nil }
        /// Brings a task into view with its terminal showing the job's tab.
        var showTerminal: (SessionKey, String) -> Void = { _, _ in }
        /// Opens the project's settings, where its actions are edited.
        var editActions: (Project) -> Void = { _ in }
    }

    @ObservationIgnored var hooks = Hooks()
    @ObservationIgnored private let terminals: TerminalStore

    init(store: ProjectActionStore, terminals: TerminalStore) {
        self.store = store
        self.terminals = terminals
        terminals.jobFinished = { [weak self] key, job in self?.terminalJobFinished(job, in: key) }
    }

    // MARK: Running

    /// Runs an action. One from the repo asks first until the project's repo commands are allowed.
    func run(_ action: ProjectAction, in target: ProjectActionTarget) {
        if action.id.isFromRepository, !hooks.allowsRepository(target.project.url) {
            pendingRun = ProjectActionPendingRun(action: action, target: target)
            return
        }
        start(action, in: target)
    }

    /// Runs the action waiting on the user, allowing the repo's commands from now on if asked.
    func confirmPendingRun(allowingRepository: Bool) {
        guard let pending = pendingRun else { return }
        pendingRun = nil
        if allowingRepository {
            hooks.allowRepository(pending.target.project.url)
        }
        start(pending.action, in: pending.target)
    }

    /// Runs the project's last action again.
    func runLast(in target: ProjectActionTarget) {
        if let action = headerAction(in: target) {
            run(action, in: target)
        }
    }

    /// The header names the newest running action, otherwise the last run or first available one.
    func headerAction(in target: ProjectActionTarget) -> ProjectAction? {
        let newest = running(in: target).max { lhs, rhs in
            guard case .running(let left, _) = state(of: lhs, in: target),
                case .running(let right, _) = state(of: rhs, in: target)
            else { return false }
            return left < right
        }
        let list = store.list(for: target.project)
        return newest ?? store.lastRunAction(in: target.project) ?? list.yours.first ?? list.fromRepository.first
    }

    /// Stops the action: a terminal run is interrupted (then ended, if asked again), a background
    /// run's command ends.
    func stop(_ action: ProjectAction, in target: ProjectActionTarget) {
        if let session = target.session {
            let panel = terminals.panel(for: session)
            if let tab = panel.tabs.tab(forJob: action.id.rawValue), tab.job?.isRunning == true {
                panel.stopJob(in: tab.id)
            }
        }
        let key = ProjectActionRunKey(action.id, in: target)
        if backgroundRuns[key]?.result == nil {
            backgroundRuns[key]?.isStopping = true
            backgroundRuns[key]?.task?.cancel()
        }
    }

    private func start(_ action: ProjectAction, in target: ProjectActionTarget) {
        store.recordRun(action.id, in: target.project)
        let launch = ProjectActionLaunch(action, worktree: target.worktree, project: target.project.url)
        // Without a task in view there's no terminal to show it in; it runs quietly instead.
        if action.presentation == .terminal, let session = target.session, terminals.availability == .available {
            terminals.run(
                TerminalJobRequest(
                    key: action.id.rawValue, name: action.name, command: action.command,
                    commandLine: launch.terminalCommand(shell: terminals.jobShell), directory: launch.directory),
                for: session)
        } else {
            startInBackground(launch, in: target)
        }
    }

    private func startInBackground(_ launch: ProjectActionLaunch, in target: ProjectActionTarget) {
        let key = ProjectActionRunKey(launch.action.id, in: target)
        backgroundRuns[key]?.task?.cancel()
        var run = ProjectActionBackgroundRun(action: launch.action, directory: launch.directory, startedAt: .now)
        guard let commandRunner = hooks.commandRunner else {
            run.result = .failedToStart("This device can't run commands.")
            backgroundRuns[key] = run
            return finished(key, in: target)
        }
        let hooks = hooks
        let runID = run.id
        run.task = Task { [weak self] in
            let result = await Self.execute(
                launch, folderName: launch.directory.abbreviatedPath, runner: commandRunner,
                environment: await hooks.environment())
            // A newer run of the same action replaced this one; its ending is its own.
            guard let self, backgroundRuns[key]?.id == runID else { return }
            backgroundRuns[key]?.result = result
            finished(key, in: target)
        }
        backgroundRuns[key] = run
        // From the project's menu, with none of its tasks in view, nothing else shows it started.
        if target.session == nil {
            let action = launch.action
            toast = ProjectActionToast(
                tone: .info, message: "Running \(action.name) in \(target.project.name)'s folder",
                detail: action.command, steps: [.init(title: "Stop") { [weak self] in self?.stop(action, in: target) }])
        }
    }

    /// Runs the command with the user's shell, as the repo's event scripts run (`$SHELL -c`, in the
    /// login-shell environment).
    @concurrent
    private static func execute(
        _ launch: ProjectActionLaunch, folderName: String, runner: any CommandRunner, environment: [String: String]
    ) async -> ProjectActionBackgroundRun.Result {
        let directory = launch.directory.path(percentEncoded: false)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue
        else {
            return .failedToStart("\(folderName) doesn't exist.")
        }
        let shell = environment["SHELL"] ?? "/bin/zsh"
        let command = Command(
            shell, ["-c", launch.action.command], in: directory,
            environment: environment.merging(launch.environment) { $1 })
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let result = try await runner.run(command)
            let output = ProjectActionBackgroundRun.trimmed(result.output + result.errorOutput)
            return .finished(.exited(status: result.exitCode, duration: clock.now - start), output: output)
        } catch is CancellationError {
            return .finished(.stopped(duration: clock.now - start), output: "")
        } catch {
            return .failedToStart(error.localizedDescription)
        }
    }

    // MARK: State

    /// How the action's latest run in the target is going: its terminal tab's job, or its
    /// background run, whichever is newer.
    func state(of action: ProjectAction, in target: ProjectActionTarget) -> ProjectActionRunState? {
        let background = backgroundRuns[ProjectActionRunKey(action.id, in: target)]
        let job = target.session.flatMap { terminals.panel(for: $0).tabs.tab(forJob: action.id.rawValue)?.job }
        switch (job, background) {
        case (let job?, let background?):
            return job.startedAt > background.startedAt ? Self.state(of: job) : background.state
        case (let job?, nil):
            return Self.state(of: job)
        case (nil, let background?):
            return background.state
        case (nil, nil):
            return nil
        }
    }

    private static func state(of job: TerminalJob) -> ProjectActionRunState {
        job.outcome.map(ProjectActionRunState.finished) ?? .running(since: job.startedAt, isStopping: job.isStopping)
    }

    /// The target's actions that are running now.
    func running(in target: ProjectActionTarget) -> [ProjectAction] {
        store.list(for: target.project).all.filter { state(of: $0, in: target)?.isRunning == true }
    }

    /// Reveals an existing run without starting it again. The well and output actions share it.
    @discardableResult
    func showOutput(of action: ProjectAction, in target: ProjectActionTarget) -> Bool {
        let key = ProjectActionRunKey(action.id, in: target)
        let background = backgroundRuns[key]
        if let session = target.session {
            let panel = terminals.panel(for: session)
            if let tab = panel.tabs.tab(forJob: action.id.rawValue), let job = tab.job,
                background == nil || job.startedAt > (background?.startedAt ?? .distantPast)
            {
                panel.show()
                panel.select(tab.id)
                return true
            }
        }
        guard background != nil else { return false }
        shownOutput = key
        return true
    }

    func output(of key: ProjectActionRunKey) -> ProjectActionBackgroundRun? {
        backgroundRuns[key]
    }

    // MARK: Endings

    private func finished(_ key: ProjectActionRunKey, in target: ProjectActionTarget) {
        guard let run = backgroundRuns[key], let result = run.result else { return }
        let name = run.action.name
        switch result {
        case .failedToStart(let reason):
            toast = ProjectActionToast(
                tone: .failure, message: "Couldn't run \(name)", detail: reason,
                steps: [.init(title: "Edit Action…") { [hooks] in hooks.editActions(target.project) }])
        case .finished(let outcome, _):
            var steps = [ProjectActionToast.Step(title: "Show Output") { [weak self] in self?.shownOutput = key }]
            if !outcome.succeeded, target.session != nil, terminals.availability == .available {
                var visible = run.action
                visible.presentation = .terminal
                steps.append(.init(title: "Run in Terminal") { [weak self] in self?.run(visible, in: target) })
            }
            toast = ProjectActionToast(
                tone: Self.tone(of: outcome), message: outcome.summary(of: name), detail: run.action.command,
                steps: steps)
        }
    }

    /// A terminal run that ended out of sight (another task in view, the panel hidden, or another
    /// tab selected) says so.
    private func terminalJobFinished(_ job: TerminalJob, in key: SessionKey) {
        if let visible = hooks.visibleSession(), visible.key == key {
            let panel = terminals.panel(for: visible)
            if panel.isVisible, panel.tabs.selected?.job?.key == job.key { return }
        }
        let jobKey = job.key
        toast = ProjectActionToast(
            tone: job.outcome.map(Self.tone) ?? .info,
            message: job.outcome?.summary(of: job.name) ?? job.name,
            detail: job.command,
            steps: [.init(title: "Show") { [hooks] in hooks.showTerminal(key, jobKey) }])
    }

    private static func tone(of outcome: TerminalJob.Outcome) -> ProjectActionToast.Tone {
        switch outcome {
        case .exited(status: 0, _): .success
        case .exited(status: .some, _): .failure
        case .exited(status: nil, _), .stopped: .info
        }
    }
}
