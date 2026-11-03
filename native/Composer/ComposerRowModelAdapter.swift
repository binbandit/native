import ACP
import Foundation

/// Presents choices from the models and routes selections through their public actions.
struct ComposerRowModelAdapter {
    let app: AppModel
    /// Nil addresses the unsent Compose task, whose editor has no agent connection.
    var session: SessionModel?
    var undoManager: UndoManager?

    private var options: [ConfigOption] { session?.configOptions ?? app.composeTask.options }
    private var settings: ComposerSettings { ComposerSettings(options) }

    private var sessionModels: [ComposerAgentModel] {
        guard let session else { return [] }
        if app.offersAgentModels { return app.composerAgentModels(for: session) }
        return (settings.model?.choices ?? [.init(value: "", name: "Default")]).map {
            ComposerAgentModel(
                agent: session.agent.id, agentName: session.agentName, choice: $0,
                kind: .model(settings.model == nil ? nil : $0.value))
        }
    }

    var state: ComposerRowState {
        let model = settings.model?.currentName ?? "Default"
        let agent = session?.agentName ?? app.composeTask.editor?.agentName ?? "Choose agent"
        let modes = modeChoices
        let selected = modes.first(where: \.isSelected)
        let full = modes.first { $0.id == TaskPermissionMode.fullAccess.rawValue && $0.unavailable == nil }
        let locations = locationChoices
        return ComposerRowState(
            agentLabel: "\(agent) · \(model)", agents: agentGroups,
            effort: settings.effort?.choices.map {
                .init(id: $0.value, title: $0.name, isSelected: $0.value == settings.effort?.value)
            } ?? [],
            modes: modes, modeLabel: selected?.title ?? settings.autonomy?.currentName ?? "Mode unavailable",
            isDefaultMode: selected?.id == TaskPermissionMode.fullAccess.rawValue, defaultModeID: full?.id,
            locations: locations, locationLabel: locations.first(where: \.isSelected)?.title ?? "Where",
            contextFraction: session?.usage?.fractionUsed, isWorking: session?.canCancel == true,
            isStopping: session?.isStopping == true,
            selectionNotice: session?.modelChange?.receipt,
            canChoose: session.map { !$0.isChangingWorkspace && !$0.isChangingAgent } ?? !app.composeTask.isHeld)
    }

    func actions(
        attach: @escaping () -> Void, context: @escaping () -> Void, send: @escaping () -> Void
    ) -> ComposerRowActions {
        ComposerRowActions(
            chooseModel: chooseModel, chooseEffort: { pick(category: "thought_level", value: $0) },
            chooseMode: { pick(category: "mode", value: $0) }, chooseLocation: chooseLocation,
            attach: attach, context: context, send: send, stop: { Task { await session?.cancel() } })
    }

    private var agentGroups: [ComposerRowState.Agent] {
        if let session {
            let catalog = sessionModels
            var groups: [ComposerRowState.Agent] = []
            for entry in catalog {
                let selected =
                    entry.agent == session.agent.id
                    && {
                        if case .model(let value) = entry.kind { return value == nil || value == settings.model?.value }
                        return false
                    }()
                let row = ComposerRowState.Choice(
                    id: entry.id, title: entry.choice.displayName, detail: entry.distinction(in: catalog) ?? "",
                    isSelected: selected, unavailable: entry.unavailable)
                if let index = groups.firstIndex(where: { $0.id == entry.agent.rawValue }) {
                    groups[index].models.append(row)
                } else {
                    groups.append(.init(id: entry.agent.rawValue, name: entry.agentName, models: [row]))
                }
            }
            return groups
        }
        return app.quickEntryRuntimes.map { runtime in
            let selected = runtime.agent.id == app.composeTask.configuredAgent
            let project = app.quickEntry.project.flatMap(app.projects.project)
            let offered = ComposerSettings(
                selected ? options : app.composeStartingOptions(for: runtime.agent.id, in: project))
            let models = offered.model?.choices ?? [.init(value: "", name: "Default")]
            return .init(
                id: runtime.agent.id.rawValue, name: runtime.agent.displayName,
                models: models.map {
                    .init(
                        id: draftModelID(agent: runtime.agent.id, value: $0.value), title: $0.displayName,
                        isSelected: selected && ($0.value == offered.model?.value || offered.model == nil),
                        unavailable: runtime.isAvailable ? nil : runtime.status.guidance ?? runtime.status.label)
                })
        }
    }

    private func chooseModel(_ id: String) {
        if let session {
            guard let row = sessionModels.first(where: { $0.id == id }), row.unavailable == nil
            else { return }
            switch row.kind {
            case .load:
                Task {
                    do { try await app.loadAgentModels(row, for: session) } catch {
                        session.addNotice("Couldn't load models: \(error.localizedDescription)", isError: true)
                    }
                }
            case .model(let value):
                if row.agent == session.agent.id {
                    if let value, value != settings.model?.value { pick(category: "model", value: value) }
                    return
                }
                app.chooseAgentModel(row, for: session, undoManager: undoManager)
            }
            return
        }
        for runtime in app.quickEntryRuntimes {
            guard
                let row = agentGroups.first(where: { $0.id == runtime.agent.id.rawValue })?.models.first(where: {
                    $0.id == id
                }),
                row.unavailable == nil
            else { continue }
            let project = app.quickEntry.project.flatMap(app.projects.project)
            let model = ComposerSettings(app.composeStartingOptions(for: runtime.agent.id, in: project)).model
            let choice = model?.choices.first { draftModelID(agent: runtime.agent.id, value: $0.value) == id }
            app.chooseComposeAgent(runtime.agent.id)
            if let choice { pick(category: "model", value: choice.value) }
            return
        }
    }

    private func pick(category: String, value: String) {
        guard let setting = options.first(where: { $0.category == category }).flatMap(SelectSetting.init),
            setting.choices.contains(where: { $0.value == value }),
            !PolicyPermissionModes.forbids(setting.option, value: value)
        else { return }
        if let session {
            session.enqueueComposerPick(setting.option, value: value)
        } else {
            app.composeTask.choose(setting, value: value)
        }
    }

    private var locationChoices: [ComposerRowState.Choice] {
        guard session == nil, app.quickEntry.project != nil else { return [] }
        let isProject = app.composeTask.workspace == .project
        let blocked = app.offersProjectFolderTasks ? nil : "Enable Project Folder Tasks in Labs to choose a folder."
        let canBranch = app.composeTask.workspaces.contains { $0.choice == .newWorktree }
        return [
            .init(
                id: "project", title: "In my folder", detail: "Use the project folder as it is.",
                isSelected: isProject, unavailable: blocked),
            .init(
                id: "branch", title: "On a new branch",
                detail: "Use a separate copy with an automatically named branch.",
                isSelected: !isProject,
                unavailable: blocked ?? (canBranch ? nil : "This project cannot create a new branch.")),
        ]
    }

    private func chooseLocation(_ id: String) {
        guard let choice = locationChoices.first(where: { $0.id == id }), choice.unavailable == nil else { return }
        let workspace: TaskWorkspaceChoice = id == "project" ? .project : .newWorktree
        app.chooseComposeWorkspace(workspace)
    }

    private func draftModelID(agent: AgentDefinition.ID, value: String) -> String {
        "\(agent.rawValue.count):\(agent.rawValue)\(value)"
    }

    private var modeChoices: [ComposerRowState.Choice] {
        TaskPermissionMode.allCases.map { mode in
            let offered = settings.autonomy?.choices.first { $0.value == mode.rawValue }
            let unsupported =
                offered == nil
                || (settings.autonomy?.option.permissionMappings.map { $0[mode.rawValue] == nil } ?? false)
            let forbidden =
                settings.autonomy.map {
                    PolicyPermissionModes.forbids($0.option, value: mode.rawValue)
                } ?? false
            return .init(
                id: mode.rawValue, title: mode.title, detail: offered?.description ?? mode.summary,
                isSelected: settings.autonomy?.value == mode.rawValue,
                unavailable: unsupported
                    ? "Not offered by this agent" : forbidden ? "Managed by your organization" : nil)
        }
    }
}
