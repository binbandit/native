import ACP
import Foundation
import NativePolicy

extension AppModel {
    func showQuickEntry(selection text: String? = nil) {
        guard quickEntry.isEnabled else { return }
        if composeTask.isPresented { return }
        if composeTask.isHeld {
            composeTask.isPresented = true
            composeTask.navigationSelection = self.selection
            restoreComposeHold()
            quickEntry.taskOpenRequests &+= 1
            return
        }
        if !quickEntry.isPresented, quickEntry.draft.isEmpty, quickEntry.context == nil {
            prepareQuickEntryAddress()
            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let source = selection.flatMap(session)?.displayTitle ?? currentProject?.name ?? "Native"
                quickEntry.context = .init(source: source, text: text)
            }
        }
        reconcileQuickEntryAgent()
        quickEntry.isPresented = true
        #if DEBUG
        QuickEntryPreviewFixtures.applyLaunchState(to: self)
        #endif
    }

    /// Addresses an empty draft to where the user is: the current project, its device and agent.
    func prepareQuickEntryAddress() {
        let project = currentProject
        quickEntry.project = project?.id
        quickEntry.device = selection.map(device(of:)) ?? project.map { preferredDevice(for: $0.id) } ?? .thisMac
        quickEntry.agent = defaultAgent(in: project)?.id
        quickEntry.failure = nil
    }

    var quickEntryRuntimes: [AgentRuntime] {
        switch quickEntry.device {
        case .thisMac: agents
        case .remote(let id): hosts.host(id)?.runtimes ?? []
        }
    }

    var quickEntryRuntime: AgentRuntime? {
        quickEntryRuntimes.first { $0.agent.id == quickEntry.agent }
    }

    func chooseQuickEntryProject(_ project: Project.ID) {
        guard !composeTask.isHeld else { return }
        quickEntry.project = project
        quickEntry.device = preferredDevice(for: project)
        quickEntry.agent = defaultAgent(in: projects.project(project))?.id
        quickEntry.failure = nil
        quickEntry.picker = nil
        reconcileQuickEntryAgent()
        if composeTask.isPresented { prepareComposeEditor() }
    }

    /// - Parameter choosing: The caller's draft takes the folder even while the panel and page are closed
    ///   (Home's start field).
    func addQuickEntryProject(_ url: URL, choosing: Bool = false) async {
        guard let url = await admittedProjectFolder(url) else {
            quickEntry.failure = actionFailure?.message ?? "Only approved folders can be added."
            actionFailure = nil
            return
        }
        let project = projects.add(url)
        if choosing || quickEntry.isPresented || composeTask.isPresented { chooseQuickEntryProject(project.id) }
        // Listing can take time. The address must change before the user can press Start again.
        _ = await addProject(url, focus: false)
    }

    func chooseQuickEntryDevice(_ device: SessionDevice) {
        guard !composeTask.isHeld else { return }
        quickEntry.device = device
        quickEntry.failure = nil
        quickEntry.picker = nil
        reconcileQuickEntryAgent()
        if composeTask.isPresented { prepareComposeEditor() }
    }

    func reconcileQuickEntryAgent() {
        if composeTask.isPresented, quickEntry.device.isRemote, quickEntryRuntimes.isEmpty { return }
        if !quickEntryRuntimes.contains(where: { $0.agent.id == quickEntry.agent }) {
            let preferred = defaultAgent(in: quickEntry.project.flatMap(projects.project))?.id
            quickEntry.agent =
                quickEntryRuntimes.first(where: { $0.agent.id == preferred && $0.isAvailable })?.agent.id
                ?? quickEntryRuntimes.first(where: \.isAvailable)?.agent.id
        }
    }

    /// The same start pipeline as New Task, with selection independent of creation. Background
    /// completion must never restore an old selection over navigation the user made meanwhile.
    func startQuickEntry(open: Bool, send: Bool = true) {
        guard quickEntry.isEnabled, quickEntry.isPresented, !send || quickEntry.hasMessage else { return }
        startQuickEntryDraft(open: open, send: send, confirms: !open)
    }

    /// Quick Entry's draft and address become one task. Every surface that writes this draft
    /// (the panel, Home's start field) starts through here, so validation and policy stay in one place.
    /// - Parameter confirms: Quick Entry's own toast confirms a start that stays put; Home shows its receipt.
    @discardableResult
    func startQuickEntryDraft(open: Bool, send: Bool = true, confirms: Bool) -> StartingTask? {
        guard let project = quickEntry.project.flatMap(projects.project) else {
            quickEntry.failure = "Choose a project before starting the task."
            quickEntry.picker = .project
            return nil
        }
        guard let option = deviceOptions(for: project.id).first(where: { $0.device == quickEntry.device }),
            option.canStart
        else {
            quickEntry.failure = "\(deviceName(quickEntry.device)) can't take a task right now. Choose another device."
            quickEntry.picker = .device
            return nil
        }
        guard let runtime = quickEntryRuntime else {
            quickEntry.failure = "Choose an available agent on this device."
            quickEntry.picker = .agent
            return nil
        }
        guard PolicyCenter.shared.policy.agents.allows(runtime.agent.id.rawValue) else {
            quickEntry.failure = "Your organization doesn't allow this agent. Choose another agent."
            quickEntry.picker = .agent
            return nil
        }
        if quickEntry.device == .thisMac {
            checkFolder(of: project)
            if missingFolder(of: project.id) != nil {
                quickEntry.failure = "The project folder is unavailable. Choose another project or restore the folder."
                return nil
            }
        }
        let task = StartingTask(
            project: project.id, agent: runtime.agent, isAgentPicked: true,
            workspaceLabel: taskWorkspaces?.newTaskWorkspaceLabel(in: project) ?? "Preparing the workspace")
        task.device = quickEntry.device
        task.draft = quickEntry.message
        task.attachments = quickEntry.attachments
        task.isSendRequested = send
        task.wantsComposerFocus = open && !send
        startingTasks.insert(task, at: 0)
        ProjectDevicePreference.remember(task.device, for: project.id)
        quickEntry.lastStartedTask = confirms ? task : nil
        quickEntry.clearAfterStarting()
        if open {
            selection = task.id
            quickEntry.taskOpenRequests &+= 1
        }
        Task { await start(task) }
        return task
    }

    func expandQuickEntry(selection: String? = nil) {
        guard quickEntry.isEnabled, !composeTask.isPresented else { return }
        if !quickEntry.isPresented { showQuickEntry(selection: selection) }
        quickEntry.dismiss()
        composeTask.isPresented = true
        composeTask.navigationSelection = self.selection
        composeTask.stage = .writing
        if composeTask.starting != nil { composeTask.editor = nil }
        composeTask.starting = nil
        prepareComposeEditor()
        restoreComposeHold()
        quickEntry.taskOpenRequests &+= 1
        #if DEBUG
        ComposeTaskPreviewFixtures.applyLaunchState(to: self)
        #endif
    }

    func openQuickEntryTask() {
        guard let task = quickEntry.lastStartedTask else { return }
        quickEntry.lastStartedTask = nil
        let destination = task.openedSession ?? task.id
        guard startingTask(destination) != nil || catalog.contains(destination) else { return }
        selection = destination
        quickEntry.taskOpenRequests &+= 1
    }

    func restoreQuickEntryFocus() {
        guard let selection else { return }
        if let task = startingTask(selection) {
            task.wantsComposerFocus = true
        } else {
            session(selection)?.wantsComposerFocus = true
        }
    }
}
