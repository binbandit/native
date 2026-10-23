import ACP
import Foundation
import NativePolicy

extension AppModel {
    func showQuickEntry(selection text: String? = nil) {
        guard quickEntry.isEnabled else { return }
        if !quickEntry.isPresented, quickEntry.draft.isEmpty, quickEntry.context == nil {
            let project = currentProject
            quickEntry.project = project?.id
            quickEntry.device = selection.map(device(of:)) ?? project.map { preferredDevice(for: $0.id) } ?? .thisMac
            quickEntry.agent = defaultAgent(in: project)?.id
            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let source = selection.flatMap(session)?.displayTitle ?? project?.name ?? "Native"
                quickEntry.context = .init(source: source, text: text)
            }
        }
        reconcileQuickEntryAgent()
        quickEntry.isPresented = true
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
        quickEntry.project = project
        quickEntry.device = preferredDevice(for: project)
        quickEntry.agent = defaultAgent(in: projects.project(project))?.id
        quickEntry.failure = nil
        quickEntry.picker = nil
        reconcileQuickEntryAgent()
    }

    func chooseQuickEntryDevice(_ device: SessionDevice) {
        quickEntry.device = device
        quickEntry.failure = nil
        quickEntry.picker = nil
        reconcileQuickEntryAgent()
    }

    func reconcileQuickEntryAgent() {
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
        guard let project = quickEntry.project.flatMap(projects.project) else {
            quickEntry.failure = "Choose a project before starting the task."
            quickEntry.picker = .project
            return
        }
        guard let option = deviceOptions(for: project.id).first(where: { $0.device == quickEntry.device }),
            option.canStart
        else {
            quickEntry.failure = "\(deviceName(quickEntry.device)) can't take a task right now. Choose another device."
            quickEntry.picker = .device
            return
        }
        guard let runtime = quickEntryRuntime else {
            quickEntry.failure = "Choose an available agent on this device."
            quickEntry.picker = .agent
            return
        }
        guard PolicyCenter.shared.policy.agents.allows(runtime.agent.id.rawValue) else {
            quickEntry.failure = "Your organization doesn't allow this agent. Choose another agent."
            quickEntry.picker = .agent
            return
        }
        if quickEntry.device == .thisMac {
            checkFolder(of: project)
            if missingFolder(of: project.id) != nil {
                quickEntry.failure = "The project folder is unavailable. Choose another project or restore the folder."
                return
            }
        }
        let task = StartingTask(
            project: project.id, agent: runtime.agent, isAgentPicked: true,
            workspaceLabel: taskWorkspaces?.newTaskWorkspaceLabel(in: project) ?? "Preparing the workspace")
        task.device = quickEntry.device
        task.draft = quickEntry.message
        task.isSendRequested = send
        task.wantsComposerFocus = open && !send
        startingTasks.insert(task, at: 0)
        ProjectDevicePreference.remember(task.device, for: project.id)
        quickEntry.lastStartedTask = open ? nil : task
        quickEntry.clearAfterStarting()
        if open { selection = task.id }
        Task { await start(task) }
    }

    func expandQuickEntry(selection: String? = nil) {
        if !quickEntry.isPresented { showQuickEntry(selection: selection) }
        // Slice 2 replaces this destination with Compose's page, using the same draft.
        startQuickEntry(open: true, send: false)
    }

    func openQuickEntryTask() {
        guard let task = quickEntry.lastStartedTask else { return }
        quickEntry.lastStartedTask = nil
        let destination = task.openedSession ?? task.id
        guard startingTask(destination) != nil || catalog.contains(destination) else { return }
        selection = destination
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
