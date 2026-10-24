import ACP
import Foundation
import Modes
import NativePolicy

extension AppModel {
    /// This model is deliberately unregistered and has no connection. Only Start creates a task.
    func prepareComposeEditor() {
        let compose = composeTask
        let old = compose.editor
        guard
            let agent = quickEntryRuntime?.agent
                ?? quickEntry.agent.flatMap(plugins.agent) ?? plugins.agents.first
        else { return }
        let project = quickEntry.project.flatMap(projects.project)
        let previousChoices = compose.configuredAgent == agent.id ? compose.choices : [:]
        compose.configuredAgent = agent.id
        let editor = SessionModel(
            agent: agent, id: SessionID("native-compose-\(UUID())"), cwd: project?.url ?? URL(filePath: "/"),
            connection: nil, services: sessions.services, supportsSteering: false,
            promptCapabilities: quickEntryRuntime?.capabilities?.prompt ?? PromptCapabilities(), phase: .idle)
        editor.draft = old?.draft ?? quickEntry.message
        editor.attachments = old?.attachments ?? quickEntry.attachments
        editor.wantsComposerFocus = true
        compose.editor = editor
        compose.choices = [:]
        compose.options = AgentSessionDefaults.offeredOptions(for: agent.id)
        var categories = AgentSessionDefaults.configuredValues(for: agent.id)
        if let project, let model = ProjectTaskDefaults.model(for: project.id, agent: agent.id) {
            categories["model"] = model
        }
        let defaults = NewSessionChoices(defaults: categories, lastUsed: AgentSessionDefaults.lastUsed(for: agent.id))
        for id in defaults.order(in: compose.options) {
            if case .set(let option, let value)? = defaults.start(
                of: id, in: compose.options, allows: { !PolicyPermissionModes.forbids($0, value: $1) }),
                let index = compose.options.firstIndex(where: { $0.id == option.id }),
                case .select(_, let choices) = option.kind
            {
                compose.options[index].kind = .select(currentValue: value, options: choices)
            }
        }
        let mode = ModeResolver.resolve(ModeLibrary.shared.startingMode, options: compose.options) {
            !PolicyPermissionModes.forbids($0, value: $1)
        }
        for change in mode.changes {
            if let index = compose.options.firstIndex(where: { $0.id == change.optionID }),
                case .select(_, let choices) = compose.options[index].kind
            {
                compose.options[index].kind = .select(currentValue: change.value, options: choices)
            }
        }
        compose.defaults = Dictionary(
            compose.options.compactMap { option in
                guard let category = option.category, case .select(let value, _) = option.kind else { return nil }
                return (category, value)
            }, uniquingKeysWith: { first, _ in first })
        for setting in compose.options.compactMap(SelectSetting.init) {
            if let category = setting.option.category, let value = previousChoices[category] {
                compose.choose(setting, value: value)
            }
        }
    }

    func chooseComposeAgent(_ agent: AgentDefinition.ID) {
        guard !composeTask.isHeld, composeTask.stage == .writing else { return }
        quickEntry.agent = agent
        quickEntry.failure = nil
        prepareComposeEditor()
    }

    func closeComposeTask() {
        guard composeTask.isPresented else { return }
        if composeTask.starting != nil {
            composeTask.isPresented = false
            return
        }
        guard !composeTask.isHeld else { composeTask.isPresented = false; return }
        // Returning to Quick Entry retains the whole draft. The page's context is now quoted text.
        quickEntry.draft = composeTask.editor?.draft ?? quickEntry.draft
        quickEntry.attachments = composeTask.editor?.attachments ?? quickEntry.attachments
        quickEntry.context = nil
        composeTask.editor = nil
        composeTask.isPresented = false
        quickEntry.picker = nil
    }

    func readComposeWorkspaces() async {
        let compose = composeTask
        let projectID = quickEntry.project
        let device = quickEntry.device
        let read = UUID()
        compose.workspaceRead = read
        compose.isReadingWorkspaces = true
        compose.workspaceFailure = nil
        compose.workspaces = []
        compose.workspace = nil
        defer { if compose.workspaceRead == read { compose.isReadingWorkspaces = false } }
        guard let project = projectID.flatMap(projects.project) else { return }
        do {
            let options: [TaskWorkspaceOption]
            if case .remote(let id) = device {
                guard let host = hosts.host(id), host.isOnline, let path = project.checkoutPath(on: device),
                    let provider = await taskWorkspaces(on: host)
                else { return }
                options = try await provider.workspaceOptions(
                    in: project.onHost(at: path), current: URL(filePath: path))
            } else {
                options = try await taskWorkspaces?.workspaceOptions(in: project, current: project.url) ?? []
            }
            guard compose.workspaceRead == read, projectID == quickEntry.project, device == quickEntry.device else {
                return
            }
            compose.workspaces = options.map {
                TaskWorkspaceOption(choice: $0.choice, title: $0.title, detail: $0.detail, isCurrent: false)
            }
            // Explicitly address an isolated worktree where git can make one; plain folders stay folders.
            compose.workspace = options.contains(where: { $0.choice == .newWorktree }) ? .newWorktree : .project
        } catch {
            guard compose.workspaceRead == read, projectID == quickEntry.project, device == quickEntry.device else {
                return
            }
            compose.workspaceFailure = "Couldn't read workspaces. \(error.localizedDescription)"
        }
    }

    /// Validate at the action, then snapshot the draft once. Retries use that exact snapshot.
    func startComposeTask(revealing: Bool = true) {
        let compose = composeTask
        #if DEBUG
        guard compose.previewState == nil else { return }
        #endif
        guard quickEntry.isEnabled, compose.stage == .writing, !compose.isHeld,
            compose.hasContent, !compose.pendingAttachments, !compose.isReadingWorkspaces, let editor = compose.editor
        else { return }
        guard let project = quickEntry.project.flatMap(projects.project) else {
            quickEntry.failure = "Choose a folder before starting the task."
            quickEntry.picker = .project
            return
        }
        guard composeDeviceOption?.canStart == true else {
            quickEntry.failure = "This device can't take the task yet. Hold it here or choose another device."
            return
        }
        guard let runtime = quickEntryRuntime, PolicyCenter.shared.policy.agents.allows(runtime.agent.id.rawValue)
        else {
            quickEntry.failure = "Choose an available agent for this task."
            quickEntry.picker = .agent
            return
        }
        guard editor.missingAttachments.isEmpty else {
            quickEntry.failure = "An attached file is no longer available. Remove it or attach it again."
            return
        }
        if quickEntry.device == .thisMac {
            checkFolder(of: project)
            guard missingFolder(of: project.id) == nil else {
                quickEntry.failure =
                    "The folder is unavailable. Restore it or choose another folder. Your draft is kept."
                return
            }
        }
        let task = StartingTask(
            project: project.id, agent: runtime.agent, isAgentPicked: true,
            workspaceLabel: compose.workspace == .newWorktree
                ? "Creating a worktree"
                : taskWorkspaces?.newTaskWorkspaceLabel(in: project) ?? "Preparing the workspace")
        task.device = quickEntry.device
        task.workspaceChoice = compose.workspace
        task.draft = editor.draft
        task.attachments = editor.attachments
        task.configChoices = compose.choices
        task.usesComposePresentation = true
        task.isSendRequested = true
        task.wantsComposerFocus = false
        compose.starting = task
        compose.stage = .folding
        quickEntry.clearAfterStarting()
        startingTasks.insert(task, at: 0)
        if revealing {
            compose.navigationSelection = task.id
            selection = task.id
        } else {
            quickEntry.lastStartedTask = task
        }
        ProjectDevicePreference.remember(task.device, for: project.id)
        Task {
            await start(task)
            if !compose.isPresented, compose.starting === task {
                compose.editor = nil
                compose.starting = nil
                compose.stage = .writing
            }
        }
    }

    func cancelComposeStart() {
        guard let task = composeTask.starting, task.openedSession == nil else { return }
        discard(task)
        composeTask.navigationSelection = selection
        composeTask.starting = nil
        composeTask.stage = .writing
    }

    /// Config is re-read after each choice, since a model can change the effort options it offers.
    func applyComposeChoices(of task: StartingTask, to session: SessionModel) async {
        for category in ["model", "thought_level", "mode"] {
            guard let value = task.configChoices[category] else { continue }
            guard let option = session.configOptions.first(where: { $0.category == category }),
                case .select(_, let choices) = option.kind, choices.contains(where: { $0.value == value }),
                !PolicyPermissionModes.forbids(option, value: value)
            else {
                task.isSendRequested = false
                session.addNotice(
                    "The selected setting is unavailable. Your draft is kept. Review the task's settings before sending.",
                    isError: true)
                continue
            }
            await session.setConfigOption(option, to: value)
            guard case .select(let actual, _)? = session.configOptions.first(where: { $0.category == category })?.kind,
                actual == value
            else {
                task.isSendRequested = false
                session.addNotice(
                    "Couldn't apply the selected setting. Your draft is kept. Review the task's settings before sending.",
                    isError: true)
                continue
            }
        }
    }

    func finishComposeTransition() {
        guard let task = composeTask.starting,
            task.failure != nil || task.openedSession != nil,
            composeTask.stage == .settled
        else { return }
        composeTask.isPresented = false
        composeTask.editor = nil
        composeTask.starting = nil
    }

    var composeDeviceOption: SessionDeviceOption? {
        #if DEBUG
        if let options = quickEntry.previewDeviceOptions { return options.first { $0.device == quickEntry.device } }
        #endif
        return quickEntry.project.flatMap { id in deviceOptions(for: id).first { $0.device == quickEntry.device } }
    }
}
