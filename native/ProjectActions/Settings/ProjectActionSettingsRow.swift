import ProjectActions
import SwiftUI

/// One action in the project's settings: its icon, name, command, and where and how it runs.
struct ProjectActionSettingsRow<Controls: View>: View {
    let action: ProjectAction
    @ViewBuilder var controls: Controls

    var body: some View {
        SettingsRow(
            action.name,
            icon: action.icon ?? ProjectActionGlyph.fallback,
            description: Text(action.command).font(.dsMono),
            detail: Text(Self.whereItRuns(action))
        ) {
            HStack(spacing: DS.Space.sm) {
                controls
            }
        }
    }

    /// "In the terminal · in apps/web of the task's worktree".
    static func whereItRuns(_ action: ProjectAction) -> String {
        let presentation =
            action.presentation == .terminal ? "In the terminal" : "In the background, with a toast when it ends"
        let base = action.directory.base == .worktree ? "the task's worktree" : "the project's folder"
        let folder = action.directory.path.isEmpty ? "in \(base)" : "in \(action.directory.path) of \(base)"
        return "\(presentation) · \(folder)"
    }
}

/// The "…" menu on one of the user's actions: move it up or down, or delete it.
struct ProjectActionRowMenu: View {
    let name: String
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void
    let delete: () -> Void

    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
        Menu {
            Button("Move Up") { move(-1) }
                .disabled(!canMoveUp)
            Button("Move Down") { move(1) }
                .disabled(!canMoveDown)
            Divider()
            Button("Delete", role: .destructive, action: delete)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: SettingsMetrics.navGlyph, weight: .regular))
                .foregroundStyle(isHovered ? Color.dsTextPrimary : Color.dsTextSecondary)
                .frame(width: DS.Size.controlSM, height: DS.Size.controlSM)
                .background(isHovered ? Color.dsHover : .clear, in: shape)
                .contentShape(shape)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .trackHover($isHovered)
        .help("More for \(name)")
        .accessibilityLabel("More for \(name)")
        .accessibilityActions {
            if canMoveUp { Button("Move Up") { move(-1) } }
            if canMoveDown { Button("Move Down") { move(1) } }
            Button("Delete", action: delete)
        }
    }
}
