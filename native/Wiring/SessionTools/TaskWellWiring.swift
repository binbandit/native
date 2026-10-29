import ACP
import AppAppearance
import GitHub
import NativeCommands
import NativePolicy
import ProjectActions
import SessionTools
import SwiftUI
import Terminal

/// The well reads the existing tool models; opening it never starts a second tool runtime.
struct TaskWellWiring: View {
    let session: SessionModel
    let tools: SessionToolsScreenModel
    let turnChanges: TurnChangesActions?
    var width = DS.TaskWell.width
    var isCompact = false
    let openSubagents: (SessionID?) -> Void
    @Environment(AppModel.self) private var app
    @Environment(TerminalStore.self) private var terminal
    @Environment(ProjectActionRunner.self) private var actions
    @Environment(GitStore.self) private var git
    @Environment(GitHubModel.self) private var gitHub
    @Environment(PolicyCenter.self) private var policy
    @State private var patchExport = TaskWellPatchExport()

    var body: some View {
        TaskWellToolbar(
            session: session, tools: tools, identity: identity,
            turnChanges: turnChanges, detail: detail, width: width, isCompact: isCompact,
            openSubagent: { openSubagents($0) }
        ) { page in
            if page == .dev, let target {
                ProjectActionsMenuContent(target: target, showsManagedExplanation: false)
            } else if page == .subagents {
                TaskWellSubagentsRoster(session: session) { id in
                    tools.showsWell = false
                    openSubagents(id)
                }
            }
        }
        .environment(\.dsWorkingAnimation, session.workingAnimation)
        .onAppear {
            tools.hasWell = true
            tools.wellToolAvailable = available
            tools.wellToolEnabled = { detail($0).unavailableReason == nil }
            tools.wellToolAction = perform
        }
        .onDisappear {
            tools.hasWell = false
            tools.wellToolAvailable = { _ in false }
            tools.wellToolEnabled = { _ in false }
            tools.wellToolAction = { _ in }
            tools.wellExportPatch = nil
        }
        .onChange(of: terminal.panel(for: session).tabs.selected?.job?.startedAt) { _, _ in
            if tools.wellPage == .dev { tools.showsWell = false }
        }
        .onChange(of: actions.pendingRun?.action.id) { _, id in
            if id != nil, tools.wellPage == .dev { tools.showsWell = false }
        }
        .task(id: session.key) {
            if let target { actions.store.refresh(target.project) }
        }
        // What was exported belongs to the task it came from.
        .onChange(of: session.key) { patchExport = TaskWellPatchExport() }
        .onChange(of: offersPatch, initial: true) { _, offers in
            tools.wellExportPatch = offers ? { exportPatch() } : nil
        }
        .taskWellPatchExporter(patchExport) {
            // Back where Export Patch was chosen, to say what was saved and what to do with it.
            tools.showsWell = true
        }
    }

    private var target: ProjectActionTarget? {
        guard !app.device(of: session.key).isRemote else { return nil }
        return ProjectActionsWiring.target(for: session, model: app)
    }

    private var pullRequest: PullRequestSummary? {
        AppTaskPullRequests(model: app, git: git, gitHub: gitHub).pullRequest(for: session.key)
    }

    private var repository: GitRepositoryModel { git.model(for: session.cwd, session: session.key) }

    /// Export Patch stands in for the pull request on a branch that can't reach GitHub.
    private var offersPatch: Bool {
        !session.isProjectless && policy.isGitHubOutOfReach && repository.branchName != nil
            && tools.registry.place(for: .pullRequest) != .off
    }

    private var identity: TaskWellIdentity {
        let device = app.device(of: session.key)
        let managed = policy.policy.managedKeys
        let workerKeys = PolicyCenter.taskWorkerKeys
        var panelKeys = workerKeys.union([.taskScriptsRepository, .shortcutBindings, .forbiddenPermissionModes])
        if offersPatch { panelKeys.formUnion([.network, .deploymentMode]) }
        let management = managed.isDisjoint(with: panelKeys) ? nil : policy.managementLine
        let turn = session.state.turns.last(where: { !$0.isLateOutput })
        let timing = turn?.duration.map { duration in
            let idle =
                session.phase == .idle ? turn?.endedAt.map { "idle since \(DSFormat.time($0, now: .now)), " } ?? "" : ""
            return "\(idle)last turn \(DSFormat.duration(duration))"
        }
        return TaskWellIdentity(
            model: ComposerSettings(session.configOptions).model?.shortModelName,
            machine: device.isRemote ? "On \(app.deviceName(device))" : "On this Mac",
            timing: timing, contextFraction: session.usage.flatMap { $0.size > 0 ? $0.fractionUsed : nil },
            isManaged: !managed.isDisjoint(with: workerKeys), management: management,
            project: app.projectName(of: session), branch: session.isProjectless ? nil : repository.branchName)
    }

    /// A tool that's off in Settings ▸ Task Tools never reaches the well, nor does its key.
    private func available(_ tool: TaskWellTool) -> Bool {
        guard tools.registry.place(for: tool.spec) != .off else { return false }
        return switch tool {
        case .changes: !session.isProjectless && tools.registry.tool(.changes) != nil
        case .terminal: true
        case .dev: target != nil
        case .subagents: session.hasSubagents
        case .pullRequest: !session.isProjectless && (offersPatch || pullRequest != nil)
        }
    }

    private func perform(_ tool: TaskWellTool) {
        switch tool {
        case .changes: tools.toggle(.changes)
        case .terminal: terminal.panel(for: session).showShell()
        case .dev:
            if let target, let action = actions.latestOutputAction(in: target),
                actions.showOutput(of: action, in: target)
            {
                tools.showsWell = false
            }
        case .subagents: break
        case .pullRequest:
            if !offersPatch, let pullRequest { gitHub.open(pullRequest) }
        }
    }

    private func exportPatch() {
        guard let branch = repository.branchName else { return }
        Task {
            await patchExport.prepare(from: repository, branch: branch)
            // The save panel takes over from the well; without one, the well says why.
            tools.showsWell = patchExport.document == nil
        }
    }

    /// What Dev is doing, or what choosing it would do: the run and how long it's been going, the
    /// last run's command to show again, or the actions to choose from.
    private func devText(_ action: ProjectAction?, isRunning: Bool, in target: ProjectActionTarget) -> String {
        if let action { return isRunning ? "\(action.name) · running" : action.command }
        let count = actions.store.list(for: target.project).all.count
        return switch count {
        case 0: "No project actions yet"
        case 1: "1 action to run"
        default: "\(count) actions to run"
        }
    }

    private func detail(_ tool: TaskWellTool) -> TaskWellToolDetail {
        switch tool {
        case .changes:
            let fact = tools.registry.tool(.changes)?.fact(
                SessionToolContext(session: session, screen: tools, tool: .changes))
            var detail = TaskWellToolDetail(text: fact?.text ?? "No changes", isSelected: tools.isOpen(.changes))
            if case .diff(let added, let removed) = fact?.accessory {
                detail.stats = DiffStats(added: added, removed: removed)
            }
            return detail
        case .terminal:
            if app.device(of: session.key).isRemote {
                return TaskWellToolDetail(
                    text: "Not available here",
                    unavailableReason: "This task runs on another machine. Its terminal cannot be opened on this Mac.")
            }
            let panel = terminal.panel(for: session)
            let shells = panel.tabs.tabs.filter { $0.job == nil }
            let label = URL(fileURLWithPath: terminal.jobShell).lastPathComponent
            return TaskWellToolDetail(
                text: "\(label) · \(session.cwd.abbreviatedPath)",
                isSelected: panel.isVisible && panel.tabs.selected?.job == nil,
                isRunning: shells.contains { $0.isCommandRunning && $0.status == .running })
        case .dev:
            guard let target else { return TaskWellToolDetail() }
            let action = actions.latestOutputAction(in: target)
            let panel = terminal.panel(for: session)
            let since: Date? = action.flatMap {
                if case .running(let since, _) = actions.state(of: $0, in: target) { since } else { nil }
            }
            let repositoryActionsOff =
                policy.isManaged(.taskScriptsRepository)
                && !policy.policy.taskScripts.repositoryScriptsEnabled
            return TaskWellToolDetail(
                text: devText(action, isRunning: since != nil, in: target),
                isSelected: panel.isVisible && panel.tabs.selected?.job != nil,
                isRunning: since != nil, runningSince: since,
                note: repositoryActionsOff ? "Repository actions are off. Your actions are still available." : nil,
                isManaged: repositoryActionsOff)
        case .subagents:
            let subagents = session.state.subagents
            let working = subagents.filter { $0.workState?.isWorking == true }.count
            return TaskWellToolDetail(text: "\(subagents.count) workers · \(working) working")
        case .pullRequest:
            if offersPatch {
                return TaskWellToolDetail(
                    text: "Not available here", unavailableReason: patchExport.note, isManaged: policy.isNetworkManaged,
                    recovery: patchExport.isPreparing ? nil : .init(title: "Export Patch…", action: exportPatch))
            }
            guard let pullRequest else { return TaskWellToolDetail() }
            let state = PullRequestStateIcon(state: pullRequest.state, isDraft: pullRequest.isDraft).label
            let checks = pullRequest.state == .open ? pullRequest.checks.map(ChecksIndicator.summary) : nil
            return TaskWellToolDetail(
                text: ["#\(pullRequest.number) \(state)", checks].compactMap { $0 }.joined(separator: " · "))
        }
    }
}

#if DEBUG
#Preview("Well - Existing tool adapters") {
    DSPreviewPair { TaskWellPanelPreview() }
}
#endif
