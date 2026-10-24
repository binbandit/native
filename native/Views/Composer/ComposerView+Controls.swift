import SwiftUI

extension ComposerView {
    func currentControls(_ settings: ComposerSettings) -> some View {
        ComposerControlsRow(
            settings: settings,
            agentName: session.agentName,
            resumedAutonomy: autonomyBeforePlan,
            followUpHint: followUpHint,
            isModelPickerOpen: $isModelPickerOpen,
            isPickingFiles: $isPickingFiles,
            onAttach: attach,
            onSet: set,
            onCycleEffort: { apply(settings.nextEffort) },
            mode: TaskModeControl(session: session, modes: taskModes),
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
