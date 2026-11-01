import ACP
import Foundation

/// Part D can mount the row with this adapter. No agent, folder or permission transition lives here.
struct ComposerRowModelAdapter {
    let app: AppModel
    /// Nil addresses the unsent Compose task, whose editor has no agent connection.
    var session: SessionModel?
    var undoManager: UndoManager?

    private var options: [ConfigOption] { session?.configOptions ?? app.composeTask.options }
    private var settings: ComposerSettings { ComposerSettings(options) }

    var state: ComposerRowState {
        let model = settings.model?.currentName ?? "Default"
        let agent = session?.agentName ?? app.composeTask.editor?.agentName ?? "Choose agent"
        let modes = modeChoices
        let selected = modes.first(where: \.isSelected)
        let full = modes.first { $0.title == "Full access" && $0.unavailable == nil }
        let isNew = session.map(\.canChangeWorkspace) ?? (app.quickEntry.project != nil)
        let locations = isNew ? locationChoices : []
        return ComposerRowState(
            agentLabel: "\(agent) · \(model)", agents: agentGroups,
            effort: settings.effort?.choices.map {
                .init(id: $0.value, title: $0.name, isSelected: $0.value == settings.effort?.value)
            } ?? [],
            modes: modes, modeLabel: selected?.title ?? settings.autonomy?.currentName ?? "Mode unavailable",
            isDefaultMode: selected?.title == "Full access", defaultModeID: full?.id,
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
            let catalog = app.composerAgentModels(for: session)
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
            guard let row = app.composerAgentModels(for: session).first(where: { $0.id == id }), row.unavailable == nil
            else { return }
            switch row.kind {
            case .load:
                Task {
                    do { try await app.loadAgentModels(row, for: session) } catch {
                        session.addNotice("Couldn't load models: \(error.localizedDescription)", isError: true)
                    }
                }
            case .model:
                if row.agent == session.agent.id, case .model(let value) = row.kind, value == settings.model?.value {
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
            Task { await session.pick(setting.option, value: value) }
        } else {
            app.composeTask.choose(setting, value: value)
        }
    }

    private var locationChoices: [ComposerRowState.Choice] {
        let isProject = session.map { app.usesProjectFolder($0.key) } ?? (app.composeTask.workspace == .project)
        let blocked =
            session.flatMap(app.workspaceChangeBlock)
            ?? (app.offersProjectFolderTasks ? nil : "Enable Project Folder Tasks in Labs to choose a folder.")
        let canBranch = session != nil || app.composeTask.workspaces.contains { $0.choice == .newWorktree }
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
        if let session {
            Task {
                do { try await app.changeWorkspace(of: session, to: workspace) } catch {
                    session.addNotice(
                        "Couldn't change where this task runs: \(error.localizedDescription)", isError: true)
                }
            }
        } else {
            app.chooseComposeWorkspace(workspace)
        }
    }

    private func draftModelID(agent: AgentDefinition.ID, value: String) -> String {
        "\(agent.rawValue.count):\(agent.rawValue)\(value)"
    }

    /// PR #240's canonical titles also work against the still-supported provider catalogs.
    /// Unsupported choices stay visible and disabled; this never invents a provider capability.
    private var modeChoices: [ComposerRowState.Choice] {
        let labels: [(String, String, String, [String])] = [
            (
                "ask-first", "Ask first", "Asks before edits and commands, subject to your permission rules.",
                ["ask-first", "default", "read-only"]
            ),
            (
                "accept-edits", "Accept edits", "Allows file edits. Asks before other actions.",
                ["accept-edits", "acceptEdits", "workspace-write"]
            ),
            ("auto", "Auto", "Reviews actions automatically and asks when an action needs you.", ["auto", "agent"]),
            (
                "full-access", "Full access", "The agent can run any command and change any file without asking.",
                ["full-access", "bypassPermissions", "agent-full-access"]
            ),
        ]
        return labels.map { id, title, detail, aliases in
            let offered = settings.autonomy?.choices.first { aliases.contains($0.value) }
            let value = offered?.value ?? id
            let forbidden = settings.autonomy.map { PolicyPermissionModes.forbids($0.option, value: value) } ?? false
            return .init(
                id: value, title: title, detail: detail,
                isSelected: aliases.contains(settings.autonomy?.value ?? ""),
                unavailable: forbidden
                    ? "Managed by your organization" : offered == nil ? "Not offered by this agent" : nil)
        }
    }
}
