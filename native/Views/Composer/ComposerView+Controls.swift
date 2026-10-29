import ACP
import NativePolicy
import SwiftUI

extension ComposerView {
    @ViewBuilder
    func settingsNote(_ settings: ComposerSettings) -> some View {
        if PolicyCenter.shared.isManaged(.forbiddenPermissionModes),
            session.modelChange?.isPermissionPolicyBlocked != true
        {
            let manager = PolicyCenter.shared.policy.organizationDisplayName
            let explainsLevel = session.modelChange?.stage == .applied && session.modelChange?.permissionNotice != nil
            let choice = explainsLevel ? nil : settings.autonomy?.current.map(Self.whenItAsks)
            Label(
                "Managed by \(manager)\(choice.map { ": \($0)" } ?? "")",
                systemImage: "lock"
            )
            .font(.dsCaption)
            .foregroundStyle(.dsTextTertiary)
            .padding(.horizontal, DS.Space.xxl)
        } else if session.modelChange?.stage == .applied, session.modelChange?.permissionNotice == nil,
            let level = settings.autonomy?.current, ["default", "read-only"].contains(level.value)
        {
            Text("\(session.agentName) asks before any change.")
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .padding(.horizontal, DS.ComposerQuote.inset)
        } else if let followUpHint {
            Text(followUpHint.text)
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .padding(.horizontal, DS.Space.xxl)
        }
    }

    /// A permission level as a phrase after the manager's name: "asks before any change", "never asks".
    static func whenItAsks(_ level: SelectSetting.Choice) -> String {
        switch level.value {
        case "agent-full-access", "bypassPermissions": "never asks"
        case "dontAsk": "refuses anything not already allowed"
        case "read-only", "default", "workspace-write", "acceptEdits", "agent", "auto":
            "asks \(level.askingTitle.prefix(1).lowercased() + level.askingTitle.dropFirst())"
        // A mode Native doesn't know keeps the agent's own name.
        default: level.name
        }
    }

    func currentControls(_ settings: ComposerSettings) -> some View {
        ComposerControlsRow(
            settings: settings,
            agentName: session.agentName,
            agentPicker: app.offersAgentModels
                ? ComposerAgentPicker(
                    models: app.composerAgentModels(for: session), current: session.agent.id,
                    pending: session.modelChange?.isPending == true ? session.modelChange?.choice.agent : nil,
                    showsLoader: session.modelChange?.showsLoader == true,
                    highlightsAgent: session.isAgentPickerRequested,
                    onChoose: { app.switchAgent(to: $0, for: session, undoManager: undoManager) }) : nil,
            resumedAutonomy: autonomyBeforePlan,
            followUpHint: followUpHint,
            isModelPickerOpen: $isModelPickerOpen,
            isPickingFiles: $isPickingFiles,
            onAttach: attach,
            onSet: set,
            onCycleEffort: { apply(settings.nextEffort) },
            mode: TaskModeControl(
                session: session, modes: taskModes, resolvedProjectName: app.projectName(of: session)),
            extras: { density in SessionGoalControl(session: session, showsIcon: density.showsIcons) },
            context: { density in
                // The session's MCP servers sit beside the context ring, quiet like it.
                HStack(spacing: DS.Space.xxs) {
                    MCPComposerChip(session: session, showsCount: !density.showsIcons)
                    ContextIndicator(session: session, style: density.showsIcons ? .ring : .labeled)
                }
            }
        )
        // The file picker opens on the task's own folder.
        .fileDialogDefaultDirectory(session.cwd)
        .disabled(!canEdit)
    }

}
