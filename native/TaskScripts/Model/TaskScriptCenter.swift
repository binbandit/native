import Exec
import Foundation
import Observation
import Synchronization
import TaskScripts

/// What Native knows about the task a script runs for, beyond its folder.
struct TaskScriptTask: Hashable, Sendable {
    var id: String?
    var title: String?
    /// The agent's id.
    var agent: String?
}

/// The project a folder belongs to, and the branch checked out there.
struct TaskScriptFolder: Hashable, Sendable {
    var projectRoot: URL
    var branch: String?
}

/// Runs task scripts as tasks' worktrees are made and removed, tasks start and are deleted, and
/// turns finish, and keeps each task's log of them (docs/scripts.md). A new worktree's setup holds
/// its task: messages queue until setup succeeds or the user skips it.
///
/// It knows nothing of git or sessions: the app's wiring tells it about worktrees and tasks, and
/// gives it the environment, the command runner and a way to hold a folder's turns.
@Observable
final class TaskScriptCenter {
    /// Why a task's messages wait while its setup runs.
    static let setupHold = "Waiting for the worktree's setup script"
    /// How many runs each folder's log keeps.
    static let logLimit = 20

    let settings: TaskScriptSettings
    /// Each folder's runs, oldest first, by standardized folder.
    private(set) var runs: [URL: [TaskScriptRun]] = [:]

    /// The login shell's environment, which every script starts from.
    @ObservationIgnored var environment: () async -> [String: String] = { [:] }
    /// Runs the scripts on the machine the projects are on.
    @ObservationIgnored var runner: any CommandRunner
    /// Holds a folder's turns while its setup runs, or lifts the hold with nil.
    @ObservationIgnored var holdTurns: (URL, String?) -> Void = { _, _ in }
    /// The open task working in a folder, if any.
    @ObservationIgnored var lookUpTask: (URL) -> TaskScriptTask? = { _ in nil }
    /// The project a folder belongs to.
    @ObservationIgnored var lookUpFolder: (URL) async -> TaskScriptFolder? = { _ in nil }
    /// Makes a detached worktree of a project, with its env files, to test a script in: its folder
    /// and the branch it was made from.
    @ObservationIgnored var makeScratchWorktree: ((URL) async throws -> (folder: URL, baseBranch: String?))?
    /// Removes a scratch worktree made by `makeScratchWorktree`, without a checkpoint.
    @ObservationIgnored var removeScratchWorktree: ((URL) async -> Void)?

    /// Tasks seen starting, by folder, for events that only learn the folder (teardown).
    @ObservationIgnored private var knownTasks: [URL: TaskScriptTask] = [:]
    /// Folders and events already told that the repository's script isn't allowed.
    @ObservationIgnored private var notedUnapproved: Set<String> = []

    init(settings: TaskScriptSettings, runner: any CommandRunner) {
        self.settings = settings
        self.runner = runner
    }

    // MARK: - What the log shows

    func runs(in folder: URL) -> [TaskScriptRun] {
        runs[folder.standardizedFileURL] ?? []
    }

    /// The setup of the task's worktree, if Native made one this run.
    func setupRun(in folder: URL) -> TaskScriptRun? {
        runs(in: folder).last { $0.event == .setup }
    }

    /// Other events' runs in the folder that failed and haven't been put away, newest first.
    func failures(in folder: URL) -> [TaskScriptRun] {
        runs(in: folder).filter { $0.event != .setup && $0.isFailure && !$0.isDismissed }.reversed()
    }

    /// Teardowns and task-deleted runs that failed for tasks no longer on screen, newest first.
    var departedFailures: [TaskScriptRun] {
        runs.values.joined()
            .filter { ($0.event == .teardown || $0.event == .taskDeleted) && $0.isFailure && !$0.isDismissed }
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// The teardown that just ran in `folder`, if it failed, for saying so where the task was archived.
    func teardownFailure(in folder: URL) -> TaskScriptReport? {
        runs(in: folder).last { $0.event == .teardown }?.failure
    }

    // MARK: - Events

    /// A task's worktree was just made: starts its setup scripts and holds the task until they're
    /// done, or asks first when the repository's script isn't allowed yet.
    func worktreeCreated(
        folder: URL, projectRoot: URL, branch: String?, baseBranch: String?, copiedFiles: [String],
        copyFailure: String?
    ) {
        let plan = settings.plan(for: .setup, project: projectRoot)
        guard !plan.isEmpty || copyFailure != nil else { return }
        let context = TaskScriptContext(
            event: .setup, projectPath: projectRoot.folderPath, worktreePath: folder.folderPath, branch: branch,
            baseBranch: baseBranch)
        let run = TaskScriptRun(
            event: .setup, folder: folder, projectRoot: projectRoot, context: context, plan: plan,
            state: plan.awaitingApproval == nil ? .running : .awaitingApproval)
        run.copiedFiles = copiedFiles
        run.copyFailure = copyFailure
        record(run)
        guard !plan.isEmpty else {
            // Nothing to run; the run only says the env files couldn't be copied.
            finish(run, as: .succeeded)
            return
        }
        holdTurns(folder, Self.setupHold)
        if run.state == .running {
            start(run)
        }
    }

    func taskStarted(in folder: URL, task: TaskScriptTask) {
        remember(task, in: folder)
        runEvent(.taskStarted, in: folder, task: task)
    }

    func turnFinished(in folder: URL, task: TaskScriptTask) {
        remember(task, in: folder)
        runEvent(.turnFinished, in: folder, task: task)
    }

    /// A task's worktree is about to be removed: stops what still runs there and runs its teardown
    /// scripts, returning once they're done. A failure is kept in the log and never thrown.
    func teardown(folder: URL, projectRoot: URL, branch: String?) async {
        for run in runs(in: folder) where run.isRunning || run.state == .awaitingApproval {
            // Setup that's still going is skipped rather than failed, so it doesn't hold the folder.
            if run.event == .setup { skip(run) } else { run.work?.cancel() }
        }
        holdTurns(folder, nil)
        let plan = settings.plan(for: .teardown, project: projectRoot)
        guard !plan.scripts.isEmpty else { return }
        let task = lookUpTask(folder) ?? knownTasks[folder.standardizedFileURL]
        let run = TaskScriptRun(
            event: .teardown, folder: folder, projectRoot: projectRoot,
            context: context(.teardown, folder: folder, projectRoot: projectRoot, branch: branch, task: task),
            plan: plan, state: .running)
        record(run)
        start(run)
        await run.work?.value
    }

    /// A task was deleted for good. Its worktree is gone by now, so the scripts run in the project's
    /// folder then.
    func taskDeleted(folder: URL, projectRoot: URL, task: TaskScriptTask) {
        let key = folder.standardizedFileURL
        let known = knownTasks.removeValue(forKey: key)
        let task = TaskScriptTask(
            id: task.id ?? known?.id, title: task.title ?? known?.title, agent: task.agent ?? known?.agent)
        let plan = settings.plan(for: .taskDeleted, project: projectRoot)
        guard !plan.scripts.isEmpty else { return }
        let directory =
            FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) ? folder : projectRoot
        let run = TaskScriptRun(
            event: .taskDeleted, folder: folder, projectRoot: projectRoot,
            context: context(.taskDeleted, folder: directory, projectRoot: projectRoot, branch: nil, task: task),
            plan: plan, state: .running)
        record(run)
        start(run)
    }

    // MARK: - The user's choices

    /// Runs a failed or stopped run's event again, with the scripts as they are now.
    func retry(_ run: TaskScriptRun) {
        run.work?.cancel()
        run.plan = settings.plan(for: run.event, project: run.projectRoot)
        run.output = TaskScriptOutput()
        run.isDismissed = false
        if run.event == .setup, run.plan.awaitingApproval != nil {
            run.state = .awaitingApproval
        } else if run.plan.scripts.isEmpty {
            // The script was removed meanwhile, so there's nothing left to wait for.
            finish(run, as: .succeeded)
        } else {
            start(run)
        }
    }

    /// Lets the repository's scripts run in the run's project from now on, and runs them.
    func allowRepositoryScripts(for run: TaskScriptRun) {
        settings.setAllowsRepositoryScripts(true, forProjectAt: run.projectRoot)
        retry(run)
    }

    /// Goes on without the repository's script this time, running the rest.
    func runWithoutRepositoryScript(_ run: TaskScriptRun) {
        run.plan.awaitingApproval = nil
        if run.plan.scripts.isEmpty {
            skip(run)
        } else {
            start(run)
        }
    }

    /// Lets the task go on without its setup: whatever still runs stops, and queued messages go out.
    func skip(_ run: TaskScriptRun) {
        run.work?.cancel()
        finish(run, as: .skipped)
    }

    /// Stops a running run. Setup stays held, for the user to retry or skip.
    func stop(_ run: TaskScriptRun) {
        run.work?.cancel()
    }

    func dismiss(_ run: TaskScriptRun) {
        run.isDismissed = true
    }

    // MARK: - Tests from Settings

    /// Where Settings tests a script.
    enum TestTarget: Hashable {
        /// A detached worktree of the project, removed afterwards.
        case scratchWorktree(project: URL)
        /// A task's own folder, for real.
        case task(folder: URL)
    }

    /// Runs `text` once as `event`'s script, outside any task's log, and returns the run to watch.
    func test(_ text: String, source: TaskScript.Source, event: TaskScriptEvent, in target: TestTarget) -> TaskScriptRun
    {
        let script = TaskScript(event: event, source: source, text: text)
        let plan = TaskScriptPlan(event: event, scripts: [script], timeout: settings.timeout(for: event))
        let folder: URL
        switch target {
        case .scratchWorktree(let project): folder = project
        case .task(let task): folder = task
        }
        let context = TaskScriptContext(
            event: event, projectPath: folder.folderPath, worktreePath: folder.folderPath, taskTitle: "Script test")
        let run = TaskScriptRun(
            event: event, folder: folder, projectRoot: folder, context: context, plan: plan, state: .running,
            isTest: true)
        run.work = Task { [weak self] in
            await self?.runTest(run, in: target)
        }
        return run
    }

    private func runTest(_ run: TaskScriptRun, in target: TestTarget) async {
        var scratch: URL?
        switch target {
        case .scratchWorktree(let project):
            guard let makeScratchWorktree else { return fail(run, "Scratch worktrees aren't available here.") }
            run.output.appendLine("Making a scratch worktree of \(project.lastPathComponent)…")
            do {
                let worktree = try await makeScratchWorktree(project)
                scratch = worktree.folder
                run.folder = worktree.folder
                run.projectRoot = project
                run.context.projectPath = project.folderPath
                run.context.worktreePath = worktree.folder.folderPath
                run.context.baseBranch = worktree.baseBranch
            } catch {
                return fail(run, "Couldn't make a scratch worktree: \(error.localizedDescription)")
            }
        case .task(let folder):
            if let info = await lookUpFolder(folder) {
                run.projectRoot = info.projectRoot
                run.context = context(
                    run.event, folder: folder, projectRoot: info.projectRoot, branch: info.branch,
                    task: lookUpTask(folder))
            }
        }
        await execute(run)
        if let scratch, let removeScratchWorktree {
            // In a task of its own, so stopping the test doesn't also stop the clean-up.
            await Task { await removeScratchWorktree(scratch) }.value
            run.output.appendLine("Removed the scratch worktree.")
        }
    }

    // MARK: - Running

    private func runEvent(_ event: TaskScriptEvent, in folder: URL, task: TaskScriptTask) {
        Task {
            let info = await lookUpFolder(folder) ?? TaskScriptFolder(projectRoot: folder)
            let plan = settings.plan(for: event, project: info.projectRoot)
            let unapproved = plan.awaitingApproval.map { "\(folder.standardizedFileURL.path)\0\($0.event.rawValue)" }
            let notesUnapproved = unapproved.map { notedUnapproved.insert($0).inserted } ?? false
            guard !plan.scripts.isEmpty || notesUnapproved else { return }
            // A newer turn makes the last one's script moot.
            for run in runs(in: folder) where run.event == event && run.isRunning {
                run.work?.cancel()
            }
            let run = TaskScriptRun(
                event: event, folder: folder, projectRoot: info.projectRoot,
                context: context(event, folder: folder, projectRoot: info.projectRoot, branch: info.branch, task: task),
                plan: plan, state: .running)
            if let pending = plan.awaitingApproval {
                run.output.appendLine(
                    "Skipped \(pending.event.repositoryPath): this project's repository scripts aren't allowed on this Mac. Allow them in the project's settings."
                )
            }
            record(run)
            if plan.scripts.isEmpty {
                finish(run, as: .skipped)
            } else {
                start(run)
            }
        }
    }

    private func start(_ run: TaskScriptRun) {
        run.state = .running
        run.attempt += 1
        run.work = Task { [weak self] in
            await self?.execute(run)
        }
    }

    /// Runs the run's plan, streaming its output into it, then records how it went and, for setup,
    /// holds or releases its task.
    private func execute(_ run: TaskScriptRun) async {
        let attempt = run.attempt
        run.state = .running
        run.startedAt = .now
        run.finishedAt = nil
        run.reports = []
        guard FileManager.default.fileExists(atPath: run.context.worktreePath) else {
            return fail(run, "The folder \(run.context.worktreePath) doesn't exist anymore.")
        }
        let runner = TaskScriptRunner(runner: runner, environment: await environment())
        let pending = TaskScriptPendingOutput()
        let labelsScripts = run.plan.scripts.count > 1
        let flusher = Task { [weak run] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                if let chunk = pending.take() { run?.output.append(chunk) }
            }
        }
        let reports = await runner.run(
            run.plan, context: run.context,
            onStart: { script in
                if labelsScripts { pending.append(Data("› \(script.name)\n".utf8)) }
                Task { @MainActor in run.current = script }
            },
            onOutput: { pending.append($0) })
        flusher.cancel()
        if let chunk = pending.take() { run.output.append(chunk) }
        // Skipped or started again meanwhile: the user's choice stands.
        guard run.attempt == attempt, run.state == .running else { return }
        run.current = nil
        run.reports = reports
        if let failed = reports.first(where: { !$0.result.succeeded }) {
            finish(run, as: .failed(failed))
        } else {
            finish(run, as: .succeeded)
        }
    }

    private func finish(_ run: TaskScriptRun, as state: TaskScriptRun.State) {
        run.state = state
        run.current = nil
        run.finishedAt = .now
        if run.event.holdsTask, !run.isTest {
            holdTurns(run.folder, run.releasesTask ? nil : Self.setupHold)
        }
    }

    /// Ends a run that couldn't get as far as its scripts.
    private func fail(_ run: TaskScriptRun, _ reason: String) {
        guard let script = run.plan.scripts.first ?? run.plan.awaitingApproval else { return }
        run.output.appendLine(reason)
        finish(
            run,
            as: .failed(
                TaskScriptReport(script: script, result: .init(outcome: .couldNotStart(reason), duration: .zero))))
    }

    private func record(_ run: TaskScriptRun) {
        let key = run.folder.standardizedFileURL
        var log = runs[key] ?? []
        log.append(run)
        if log.count > Self.logLimit {
            log.removeFirst(log.count - Self.logLimit)
        }
        runs[key] = log
    }

    private func remember(_ task: TaskScriptTask, in folder: URL) {
        let key = folder.standardizedFileURL
        let known = knownTasks[key]
        knownTasks[key] = TaskScriptTask(
            id: task.id ?? known?.id, title: task.title ?? known?.title, agent: task.agent ?? known?.agent)
    }

    private func context(
        _ event: TaskScriptEvent, folder: URL, projectRoot: URL, branch: String?, task: TaskScriptTask?
    ) -> TaskScriptContext {
        TaskScriptContext(
            event: event, projectPath: projectRoot.folderPath, worktreePath: folder.folderPath, branch: branch,
            taskID: task?.id, taskTitle: task?.title, agent: task?.agent)
    }
}

/// Output that arrived off the main actor, waiting for the run's next refresh, so a chatty script
/// redraws its log ten times a second rather than for every line.
nonisolated private final class TaskScriptPendingOutput: Sendable {
    private let data = Mutex(Data())

    func append(_ chunk: Data) {
        data.withLock { $0.append(chunk) }
    }

    func take() -> Data? {
        data.withLock { data in
            defer { data = Data() }
            return data.isEmpty ? nil : data
        }
    }
}

extension TaskScriptFolder {
    init(projectRoot: URL) {
        self.init(projectRoot: projectRoot, branch: nil)
    }
}
