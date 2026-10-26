import ACP
import Git
import Modes
import NativeAutomation
import NativePolicy
import SwiftUI

/// Fine print's one settings door at the field's trailing edge: the model (led by the mode when it
/// isn't Build) opens Task Settings, whose Goal and MCP servers rows open their pages in place.
struct ComposerSettingsControl: View {
    let session: SessionModel
    let settings: ComposerSettings
    let mode: TaskModeControl
    @Binding var isPresented: Bool
    /// While Plan suspends the permission level, the level it returns to.
    var resumedAutonomy: String?
    /// The popover was asked for by its command (⇧⌘E), so it opens with the current model highlighted.
    var highlightsCurrent = false

    @Environment(AppModel.self) var app
    @Environment(AutomationCenter.self) var automation
    @Environment(SettingsPresentation.self) var presentation: SettingsPresentation?
    @Environment(GitStore.self) private var git: GitStore?
    @Environment(\.mcpServersPopover) private var mcpPresentation
    @State private var showsMCP = false
    @State private var showsGoalEditor = false
    @State private var isHovered = false
    @State private var changes = ConfigOptionChangeQueue()
    @State private var pending: ComposerSettingsPopover.Pending?
    @State private var failure: ComposerSettingsPopover.Failure?
    @Environment(\.undoManager) private var undoManager
    @State private var modelCatalog: [ComposerAgentModel] = []
    @State private var loadingModelID: String?
    @State private var lastChange: (optionID: String, value: String)?

    var library: MCPLibrary? { MCPServersPlugin.library(in: app.plugins) }
    private var policy: NativePolicy { PolicyCenter.shared.policy }
    private var permissionsManaged: Bool { policy.isManaged(.forbiddenPermissionModes) }

    private var manager: String? {
        let keys: Set<PolicyKey> = [.agentsAllowed, .forbiddenPermissionModes, .mcpAllowed, .mcpBlocked, .mcpRequired]
        return policy.managedKeys.isDisjoint(with: keys) ? nil : policy.organizationName ?? "your organization"
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            ComposerSettingsDoorLabel(
                mode: mode.current.id == .build ? nil : mode.current.name,
                model: settings.model?.shortModelName ?? "Task Settings",
                isFast: settings.modelSwitches.first?.isOn == true,
                isOpen: isPresented, isHovered: isHovered)
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
        .dsHitTarget(DS.ComposerSettings.controlHeight)
        .accessibilityLabel("Task Settings")
        .accessibilityValue(
            [
                mode.current.id == .build ? nil : "\(mode.current.name) mode", settings.model?.shortModelName,
                session.agentName,
            ]
            .compactMap { $0 }.joined(separator: ", ")
        )
        .accessibilityHint("Model, effort and when \(session.agentName) asks")
        .accessibilityIdentifier("composer-settings")
        .help(CommandRegistry.shared.help("Task Settings", for: .sessionChooseModel))
        .focusedSceneValue(\.mcpServersPopover, mcpPresentation)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            content.dsPopoverBackground()
        }
        .task(id: session.clientID) { await library?.track(session.context) }
        .onChange(of: session.modelChange?.stage) { _, stage in
            if stage == .applied {
                lastChange = nil
                AccessibilityNotification.Announcement("Using \(session.agentName). Undo available.").post()
            } else if stage == .failed, let message = session.modelChange?.error {
                AccessibilityNotification.Announcement(message).post()
            }
        }
        .onChange(of: mcpPresentation?.wrappedValue, initial: true) { _, show in
            if show == true {
                showsGoalEditor = false
                showsMCP = true
                isPresented = true
            }
        }
        .onChange(of: automation.goal(for: session)?.isEditorRequested, initial: true) { _, requested in
            guard requested == true else { return }
            // Menu, goal-bar and slash-command requests need a presenter even while settings is closed.
            showsMCP = false
            mcpPresentation?.wrappedValue = false
            showsGoalEditor = true
            isPresented = true
            automation.goal(for: session)?.isEditorRequested = false
        }
        .onChange(of: isPresented) { _, open in
            if open, app.offersAgentModels {
                modelCatalog = app.agentModels(for: session)
            }
            if !open {
                showsMCP = false
                showsGoalEditor = false
                mcpPresentation?.wrappedValue = false
                lastChange = nil
            }
        }
    }

    @ViewBuilder private var content: some View {
        if showsGoalEditor, let controller = automation.goal(for: session) {
            ComposerSettingsPageFrame(title: controller.goal == nil ? "Set a Goal" : "Goal", onBack: backFromPage) {
                SessionGoalEditor(controller: controller, agentName: session.agentName) { isPresented = false }
            }
        } else if showsMCP, let library {
            ComposerSettingsPageFrame(title: "MCP Servers", onBack: backFromPage) {
                MCPSessionPanel(
                    library: library, session: session, entries: library.entries(forSession: session.clientID),
                    onManage: {
                        isPresented = false
                        presentation?.open(.mcpServers)
                    }, isPage: true)
            }
        } else {
            ComposerSettingsPopover(
                settings: settings, agentName: session.agentName, workspace: workspace, manager: manager,
                permissionsManaged: permissionsManaged, forbiddenModes: policy.forbiddenPermissionModes,
                rows: taskRows(openGoal: { showsGoalEditor = true }, openMCP: openMCP),
                agentModels: app.offersAgentModels ? refreshedCatalog : nil,
                currentAgentID: session.agent.id, modelChange: session.modelChange,
                loadingModelID: loadingModelID, onChooseAgentModel: chooseModel,
                onAgentsSettings: {
                    isPresented = false; presentation?.open(.agents)
                },
                resumedAutonomy: resumedAutonomy, pending: pending, failure: modelFailure ?? failure,
                isStopped: session.phase == .disconnected,
                onRestart: { Task { await app.restartAgent(for: session) } },
                highlightsCurrent: highlightsCurrent,
                onClose: { isPresented = false },
                onUndo: undo,
                onSet: set)
        }
    }

    /// Keep the opening order, while permissions and availability remain live.
    private var refreshedCatalog: [ComposerAgentModel] {
        let fresh = app.agentModels(for: session)
        guard !modelCatalog.isEmpty else { return fresh }
        let existing = modelCatalog.compactMap { old in fresh.first { $0.id == old.id } }
        return existing + fresh.filter { row in !modelCatalog.contains { $0.id == row.id } }
    }

    private var modelFailure: ComposerSettingsPopover.Failure? {
        guard session.modelChange?.stage == .failed, let change = session.modelChange else { return nil }
        return .init(optionID: "agent-model", message: change.error ?? "Couldn't change the model.") {
            change.retry(undoManager: undoManager)
        }
    }

    private func chooseModel(_ row: ComposerAgentModel) {
        if row.agent == session.agent.id, case .model(let value) = row.kind,
            let model = settings.model, let value
        {
            set(model, value)
        } else if row.kind == .load {
            guard loadingModelID == nil else { return }
            loadingModelID = row.id
            Task {
                defer { loadingModelID = nil }
                do {
                    try await app.loadAgentModels(row, for: session)
                    let fresh = app.agentModels(for: session)
                    let index = modelCatalog.firstIndex { $0.id == row.id } ?? modelCatalog.endIndex
                    modelCatalog.removeAll { $0.agent == row.agent }
                    modelCatalog.insert(
                        contentsOf: fresh.filter { $0.agent == row.agent }, at: min(index, modelCatalog.count))
                    failure = nil
                } catch {
                    failure = .init(optionID: "agent-model", message: error.localizedDescription) { chooseModel(row) }
                }
            }
        } else {
            app.chooseAgentModel(row, for: session, undoManager: undoManager)
        }
    }

    /// The task's branch, which the captions name as where the agent works freely.
    private var workspace: String? {
        git?.model(for: session.cwd, session: session.key).branch?.name
    }

    private func openMCP() {
        showsMCP = true
        mcpPresentation?.wrappedValue = true
    }

    private func backFromPage() {
        showsMCP = false
        showsGoalEditor = false
        mcpPresentation?.wrappedValue = false
    }

    // MARK: - Changing a setting

    func set(_ setting: SelectSetting, _ value: String) {
        guard !changes.contains(setting.option.id) else { return }
        let change = ComposerSettingsPopover.Pending(optionID: setting.option.id, value: value)
        let name = setting.choices.first { $0.value == value }?.name ?? value
        failure = nil
        changes.enqueue(setting.option.id) {
            // Earlier replies replace complete snapshots. Read the undo value only after they finish.
            let previous =
                session.configOptions.first { $0.id == setting.option.id }
                .flatMap(SelectSetting.init)?.value ?? setting.value
            // The loader shows only once the agent's confirmation is slow enough to notice.
            let loader = Task {
                try await Task.sleep(for: DS.ComposerSettings.applyingDelay)
                pending = change
            }
            await session.pick(setting.option, value: value)
            loader.cancel()
            pending = nil
            let actual = session.configOptions.first { $0.id == setting.option.id }.flatMap(SelectSetting.init)
            if let actual, actual.value != value {
                let message = "Couldn't switch to \(name). \(actual.currentName) is still on."
                failure = .init(optionID: setting.option.id, message: message) { set(actual, value) }
                AccessibilityNotification.Announcement(message).post()
            } else {
                lastChange = (setting.option.id, previous)
                AccessibilityNotification.Announcement("\(setting.option.name): \(name)").post()
            }
        }
    }

    /// ⌘Z in the popover takes back its last change.
    private func undo() {
        guard changes.isEmpty else { return }
        if let lastChange,
            let setting = session.configOptions.first(where: { $0.id == lastChange.optionID }).flatMap(
                SelectSetting.init)
        {
            self.lastChange = nil
            set(setting, lastChange.value)
        } else {
            session.modelChange?.undoSelection?.undo()
        }
    }
}

/// The door: `[Mode · ]Model[ · Fast]`, quiet at rest, lit while hovered or open.
struct ComposerSettingsDoorLabel: View {
    let mode: String?
    let model: String
    var isFast = false
    let isOpen: Bool
    var isHovered = false

    var body: some View {
        let lit = isOpen || isHovered
        HStack(spacing: DS.Space.xs) {
            Text(
                "\(Text(mode.map { "\($0) " } ?? "").foregroundStyle(lit ? .dsTextPrimary : .dsTextSecondary))\(Text(mode == nil ? "" : "· ").foregroundStyle(.dsTextQuaternary))\(Text(model))\(Text(isFast ? " · " : "").foregroundStyle(.dsTextQuaternary))\(Text(isFast ? "Fast" : ""))"
            )
            .lineLimit(1)
            Image(systemName: "chevron.down").font(.dsMicro)
        }
        .font(.dsBody)
        .foregroundStyle(lit ? .dsTextPrimary : .dsTextTertiary)
        .padding(.leading, DS.Space.md)
        .padding(.trailing, DS.Space.sm)
        .frame(height: DS.ComposerSettings.controlHeight)
        .background(
            isOpen ? Color.dsSelected : isHovered ? .dsHover : .clear,
            in: .rect(cornerRadius: DS.Radius.control)
        )
        .contentShape(.rect)
    }
}

/// A page that opens in place of Task Settings at its width, with the way back on its first line;
/// Escape goes back too, never closing the popover.
struct ComposerSettingsPageFrame<Content: View>: View {
    let title: String
    let onBack: () -> Void
    @ViewBuilder let content: () -> Content

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ComposerSettingsPageHeader(title: title, onBack: onBack)
            content()
        }
        .padding(.top, DS.ComposerSettings.popoverInset)
        .frame(minWidth: DS.ComposerSettings.popoverWidth)
        // Holds the keys until something inside takes them, so Escape reaches the way back.
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.leftArrow) {
            guard isFocused else { return .ignored }
            onBack()
            return .handled
        }
        .onKeyPress(.escape) {
            onBack()
            return .handled
        }
    }
}
