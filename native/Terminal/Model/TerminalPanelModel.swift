import Foundation
import Observation
import Terminal

/// One task's terminal panel: its tabs, each tab's running terminal, and whether it's showing.
/// Shells keep running while the panel is hidden or another task is selected; they end when their
/// tab closes.
@Observable
final class TerminalPanelModel: TerminalSurfaceEvents {
    /// The task's folder (its worktree, when it has one), where new tabs start.
    let workingDirectory: URL
    var isVisible = false
    private(set) var tabs = TerminalTabList()
    private(set) var logs: [UUID: TerminalLog] = [:]
    /// The tab the user asked to close while a program runs in it, awaiting confirmation.
    var confirmingClose: UUID?
    /// The tab whose terminal has keyboard focus.
    private(set) var focusedTab: UUID?

    var isFocused: Bool {
        focusedTab != nil
    }

    @ObservationIgnored private var surfaces: [UUID: TerminalSurface] = [:]
    /// What each job tab runs, to run it again.
    @ObservationIgnored private var jobRequests: [UUID: TerminalJobRequest] = [:]
    /// Told when a tab's job ends, with the job as it ended.
    @ObservationIgnored var jobFinished: (TerminalJob) -> Void = { _ in }
    @ObservationIgnored private let engine: () -> TerminalEngine?
    /// Hands focus back to the task's composer when the terminal gives it up.
    @ObservationIgnored var focusComposer: () -> Void = {}
    /// Rereads the user's Ghostty config (`reload_config` in their key bindings).
    @ObservationIgnored var reloadConfig: () -> Void = {}
    /// A command every tab runs instead of a shell (a sign-in, say); nil for the user's shell.
    @ObservationIgnored private let command: String?
    /// The command for a new shell: the user's chosen shell, or `shell` when given; nil leaves the
    /// choice to the terminal's config. Fails when the shell isn't there.
    @ObservationIgnored var resolveShell: (_ shell: String?) -> Result<String?, TerminalStartFailure> = { _ in
        .success(nil)
    }

    init(workingDirectory: URL, command: String? = nil, engine: @escaping () -> TerminalEngine?) {
        self.workingDirectory = workingDirectory
        self.command = command
        self.engine = engine
    }

    func surface(for id: UUID) -> TerminalSurface? {
        surfaces[id]
    }

    /// Shows the panel, opening a first tab if there's none, and focuses the selected terminal.
    func show() {
        isVisible = true
        if tabs.isEmpty {
            newTab()
        } else {
            focusSelected()
        }
    }

    /// Hides the panel; its shells keep running.
    func hide() {
        let hadFocus = isFocused
        isVisible = false
        if hadFocus {
            focusComposer()
        }
    }

    func newTab() {
        let tab = tabs.add()
        isVisible = true
        start(tab.id, in: workingDirectory)
        focusSelected()
    }

    func select(_ id: UUID) {
        tabs.select(id)
        focusSelected()
    }

    func selectTab(offset: Int) {
        tabs.selectTab(offset: offset)
        focusSelected()
    }

    /// Runs a job in a tab of its own: the tab that already has it (ending a run still going), or a
    /// new one. Shows the panel and selects the tab, leaving keyboard focus where it was.
    @discardableResult
    func run(_ request: TerminalJobRequest) -> UUID {
        let job = TerminalJob(key: request.key, name: request.name, command: request.command)
        let id: UUID
        if let existing = tabs.tab(forJob: request.key) {
            id = existing.id
            surfaces.removeValue(forKey: id)?.close()
            tabs.select(id)
            tabs.setJob(job, of: id)
            tabs.setTitle(nil, of: id)
            tabs.setStatus(.running, of: id)
            tabs.resetCommand(in: id)
        } else {
            id = tabs.add(job: job).id
        }
        jobRequests[id] = request
        isVisible = true
        start(id, in: request.directory, jobCommand: request.commandLine)
        return id
    }

    /// Attaches output from an existing command, leaving keyboard focus in the composer.
    func attach(_ log: TerminalLog) {
        let id = tabs.add(job: log.job).id
        logs[id] = log
        isVisible = true
        log.changed = { [weak self, weak log] in
            guard let self, let log else { return }
            let wasRunning = tabs.tabs.first { $0.id == id }?.job?.isRunning == true
            tabs.setJob(log.job, of: id)
            tabs.setStatus(log.job.isRunning ? .running : .exited, of: id)
            if wasRunning && !log.job.isRunning { jobFinished(log.job) }
        }
        log.changed()
    }

    /// Runs a tab's job again, in the same tab.
    func rerunJob(in id: UUID) {
        if let log = logs[id] {
            if !log.job.isRunning { log.retry() }
            return
        }
        if let request = jobRequests[id] {
            run(request)
        }
    }

    /// The folder a job tab's command runs in.
    func jobDirectory(of id: UUID) -> URL? {
        jobRequests[id]?.directory
    }

    /// Stops a tab's running job: first by interrupting it (⌃C), so it can clean up; asked again
    /// while it's stopping, by ending its terminal.
    func stopJob(in id: UUID) {
        if let log = logs[id] { return log.stop() }
        guard let job = tabs.tabs.first(where: { $0.id == id })?.job, job.isRunning else { return }
        if job.isStopping {
            surfaces.removeValue(forKey: id)?.close()
            tabs.setStatus(.exited, of: id)
            finishJob(in: id, status: nil)
        } else {
            tabs.updateJob(of: id) { $0.isStopping = true }
            surfaces[id]?.interrupt()
        }
    }

    private func finishJob(in id: UUID, status: Int32?, duration: Duration? = nil) {
        guard let job = tabs.tabs.first(where: { $0.id == id })?.job, job.isRunning else { return }
        tabs.updateJob(of: id) { $0.finish(status: status, duration: duration) }
        if let finished = tabs.tabs.first(where: { $0.id == id })?.job {
            jobFinished(finished)
        }
    }

    /// Closes a tab, first asking when a program is still running in it.
    func requestClose(_ id: UUID) {
        if surfaces[id]?.needsConfirmClose == true || logs[id]?.job.isRunning == true {
            confirmingClose = id
        } else {
            close(id)
        }
    }

    func close(_ id: UUID) {
        let hadFocus = focusedTab == id
        if let log = logs.removeValue(forKey: id) {
            log.changed = {}
            if log.job.isRunning { log.stop() }
        }
        if confirmingClose == id {
            confirmingClose = nil
        }
        surfaces.removeValue(forKey: id)?.close()
        jobRequests[id] = nil
        tabs.close(id)
        if focusedTab == id {
            focusedTab = nil
        }
        if tabs.isEmpty {
            isVisible = false
            if hadFocus {
                focusComposer()
            }
        } else if hadFocus {
            focusSelected()
        }
    }

    /// Starts a fresh shell in a tab whose shell ended or never started, in `directory` or the
    /// task's folder.
    /// - Parameter shell: A shell to run this time instead of the chosen one, such as the
    ///   fallback when the chosen one is missing.
    func restart(_ id: UUID, in directory: URL? = nil, shell: String? = nil) {
        // A job tab runs its job again rather than a shell.
        if logs[id] != nil || (jobRequests[id] != nil && directory == nil && shell == nil) {
            return rerunJob(in: id)
        }
        jobRequests[id] = nil
        tabs.setJob(nil, of: id)
        surfaces.removeValue(forKey: id)?.close()
        tabs.setTitle(nil, of: id)
        tabs.setStatus(.running, of: id)
        tabs.resetCommand(in: id)
        start(id, in: directory ?? workingDirectory, shell: shell)
        if tabs.selectedID == id {
            focusSelected()
        }
    }

    /// Ends every shell, for when the task goes away.
    func closeAll() {
        for id in tabs.tabs.map(\.id) { close(id) }
        jobRequests = [:]
        isVisible = false
    }

    /// Whether the selected tab has a terminal that can take keyboard focus.
    var canFocus: Bool {
        tabs.selectedID.flatMap { surfaces[$0] } != nil
    }

    func focusSelected() {
        guard let id = tabs.selectedID else { return }
        surfaces[id]?.focus()
    }

    /// - Parameter jobCommand: What a job tab runs instead of a shell.
    private func start(_ id: UUID, in directory: URL, shell: String? = nil, jobCommand: String? = nil) {
        guard let engine = engine() else {
            tabs.setStatus(.failedToStart(.engineFailed), of: id)
            return
        }
        do {
            let command = try jobCommand ?? command ?? resolveShell(shell).get()
            surfaces[id] = try engine.makeSurface(
                id: id, launch: TerminalLaunch(workingDirectory: directory, command: command), events: self)
        } catch let failure as TerminalStartFailure {
            tabs.setStatus(.failedToStart(failure), of: id)
        } catch {
            tabs.setStatus(.failedToStart(.engineFailed), of: id)
        }
    }

    // MARK: TerminalSurfaceEvents

    func surface(_ id: UUID, didSetTitle title: String?) {
        tabs.setTitle(title, of: id)
    }

    func surface(_ id: UUID, didChangeStatus status: TerminalStatus) {
        if jobRequests[id] != nil {
            // A job that ends at once (a typo, a missing script) ran; it didn't fail to start.
            tabs.setStatus(status == .running ? .running : .exited, of: id)
            finishJob(in: id, status: nil)
        } else {
            tabs.setStatus(status, of: id)
        }
        if status != .running {
            // The last title is the command that ended the shell ("exit"); the tab's name reads better.
            tabs.setTitle(nil, of: id)
        }
    }

    func surface(_ id: UUID, didFinishCommandWith status: Int32, after duration: Duration) {
        if jobRequests[id] != nil {
            finishJob(in: id, status: status >= 0 ? status : nil, duration: duration)
        } else {
            tabs.finishCommand(status: status, in: id)
        }
    }

    func surface(_ id: UUID, didChangeCommandRunning isRunning: Bool) {
        // A command can finish and another start between samples. Compare with the model's
        // completion state, so a missed idle prompt cannot suppress the next running command.
        guard let tab = tabs.tabs.first(where: { $0.id == id }),
            tab.status == .running, tab.isCommandRunning != isRunning
        else { return }
        tabs.setCommandRunning(isRunning, of: id)
    }

    func surfaceDidRequestClose(_ id: UUID) {
        close(id)
    }

    func surface(_ id: UUID, didRequest request: TerminalSurfaceRequest) {
        switch request {
        case .newTab:
            newTab()
        case .selectTab(offset: let offset):
            selectTab(offset: offset)
        case .goToTab(number: let number):
            let index = min(number, tabs.tabs.count) - 1
            if tabs.tabs.indices.contains(index) {
                select(tabs.tabs[index].id)
            }
        case .reloadConfig:
            reloadConfig()
        }
    }

    func surface(_ id: UUID, didChangeFocus isFocused: Bool) {
        if isFocused {
            focusedTab = id
        } else if focusedTab == id {
            focusedTab = nil
        }
    }
}
